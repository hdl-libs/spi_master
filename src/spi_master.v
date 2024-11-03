// ---------------------------------------------------------------------------------------
// Copyright (c) 2024 john_tito All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// ---------------------------------------------------------------------------------------
// +FHEADER-------------------------------------------------------------------------------
// Author        : john_tito
// Module Name   : spi_master
// ---------------------------------------------------------------------------------------
// Revision      : 1.0
// Description   : File Created
// ---------------------------------------------------------------------------------------
// Synthesizable : Yes
// Clock Domains : clk
// Reset Strategy: sync reset
// -FHEADER-------------------------------------------------------------------------------

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module spi_master #(
    parameter integer DATA_WIDTH = 8,
    parameter         CPOL       = 1'b0,
    parameter         CPHA       = 1'b1
) (
    input wire clk,
    input wire rstn,

    input wire        load,
    input wire [31:0] baud_div,

    output reg                   spi_scsn,
    output wire                  spi_sclk,
    input  wire                  spi_miso,
    output wire                  spi_mosi,
    output reg                   tx_busy,
    input  wire                  tx_valid,
    input  wire [DATA_WIDTH-1:0] tx_data,
    output reg                   tx_ready,
    output reg  [DATA_WIDTH-1:0] rx_data,
    output reg                   rx_valid
);

    localparam [3:0] FSM_IDLE = 4'b0000;
    localparam [3:0] FSM_PRE_WAIT = 4'b0001;
    localparam [3:0] FSM_TRANSMIT = 4'b0011;
    localparam [3:0] FSM_POST_WAIT = 4'b0010;  // 在该状态禁用时钟输出，等待半个时钟周期后结束传输

    reg  [             3:0] c_state;
    reg  [             3:0] n_state;

    reg  [DATA_WIDTH-1 : 0] spi_tx_buff;
    reg  [DATA_WIDTH-1 : 0] spi_rx_buff;
    reg  [             4:0] tx_bit_cnt;
    reg  [             4:0] rx_bit_cnt;
    wire                    tx_shift_en;
    wire                    rx_shift_en;
    wire                    sync_clk;
    reg                     clk_en = 1'b0;
    reg                     clk_oen = 1'b0;
    reg                     tx_data_latched;
    reg  [             7:0] tx_data_latch;

    always @(posedge clk) begin
        if (!rstn) begin
            c_state <= FSM_IDLE;
        end else begin
            c_state <= n_state;
        end
    end

    always @(*) begin
        if (!rstn) begin
            n_state = FSM_IDLE;
        end else begin
            case (c_state)
                FSM_IDLE: begin
                    if (tx_valid) begin
                        n_state = FSM_PRE_WAIT;
                    end else begin
                        n_state = FSM_IDLE;
                    end
                end
                FSM_PRE_WAIT: begin
                    if (tx_shift_en) begin
                        n_state = FSM_TRANSMIT;
                    end else begin
                        n_state = FSM_PRE_WAIT;
                    end
                end
                FSM_TRANSMIT: begin
                    if ((rx_shift_en == 1'b1) && (rx_bit_cnt >= DATA_WIDTH - 1)) begin
                        if (tx_data_latched) begin
                            n_state = FSM_TRANSMIT;
                        end else begin
                            n_state = FSM_POST_WAIT;
                        end
                    end else begin
                        n_state = FSM_TRANSMIT;
                    end
                end
                FSM_POST_WAIT: begin
                    if (tx_shift_en) begin
                        n_state = FSM_IDLE;
                    end else begin
                        n_state = FSM_POST_WAIT;
                    end
                end

                default: n_state = FSM_IDLE;
            endcase
        end
    end

    clk_gen #(
        .CLK_MODE_SEL(2'b01),
        .CPOL        (CPOL),
        .CPHA        (CPHA)
    ) clk_gen_dut (
        .clk       (clk),
        .rstn      (rstn),
        .oen       (clk_oen),
        .en        (clk_en),
        .load      (load),
        .baud_freq (0),
        .baud_limit(0),
        .baud_div  (baud_div),
        .sync_clk  (sync_clk),
        .shift_en  (tx_shift_en),
        .latch_en  (rx_shift_en)
    );

    always @(posedge clk) begin
        if (!rstn) begin
            clk_en  <= 1'b0;
            clk_oen <= 1'b0;
        end else begin
            case (n_state)
                FSM_PRE_WAIT: begin
                    clk_en  <= 1'b1;
                    clk_oen <= 1'b1;
                end
                FSM_TRANSMIT: begin
                    clk_en  <= 1'b1;
                    clk_oen <= 1'b1;
                end
                FSM_POST_WAIT: begin
                    clk_en  <= 1'b1;
                    clk_oen <= ~CPHA;
                end
                default: begin
                    clk_en  <= 1'b0;
                    clk_oen <= 1'b0;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            spi_scsn <= 1'b1;
        end else begin
            case (n_state)
                FSM_PRE_WAIT, FSM_POST_WAIT, FSM_TRANSMIT: begin
                    spi_scsn <= 1'b0;
                end
                default: begin
                    spi_scsn <= 1'b1;
                end
            endcase
        end
    end
    assign spi_sclk = sync_clk;
    assign spi_mosi = spi_tx_buff[DATA_WIDTH-1];

    // latch data here
    always @(posedge clk) begin
        if (!rstn) begin
            tx_data_latch <= 0;
        end else begin
            if (tx_ready & tx_valid) begin
                tx_data_latch <= tx_data;
            end else begin
                tx_data_latch <= tx_data_latch;
            end
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            tx_data_latched <= 1'b0;
        end else begin
            case (n_state)
                FSM_TRANSMIT: begin
                    if (tx_ready) begin
                        tx_data_latched <= tx_valid;
                    end else begin
                        tx_data_latched <= tx_data_latched;
                    end
                end
                default: begin
                    tx_data_latched <= 1'b0;
                end
            endcase
        end
    end

    // load new data when first bit is going shift out
    always @(posedge clk) begin
        if (!rstn) begin
            spi_tx_buff <= 0;
        end else begin
            case (n_state)
                FSM_PRE_WAIT, FSM_POST_WAIT: begin
                    spi_tx_buff <= spi_tx_buff;
                end
                FSM_TRANSMIT: begin
                    if (tx_shift_en) begin
                        if (tx_bit_cnt == 0) begin
                            spi_tx_buff <= {tx_data_latch};
                        end else begin
                            spi_tx_buff <= {spi_tx_buff[DATA_WIDTH-2:0], 1'b0};
                        end
                    end
                end
                default: begin
                    spi_tx_buff <= 0;
                end
            endcase
        end
    end

    // clear data when lsat bit shift in
    always @(posedge clk) begin
        if (!rstn) begin
            spi_rx_buff <= 0;
        end else begin
            case (n_state)
                FSM_TRANSMIT: begin
                    if (rx_shift_en) begin
                        if (rx_bit_cnt == (DATA_WIDTH - 1)) begin
                            spi_rx_buff <= {(DATA_WIDTH) {1'b0}};
                        end else begin
                            spi_rx_buff <= {spi_rx_buff[DATA_WIDTH-2:0], spi_miso};
                        end
                    end
                end
                default: begin
                    spi_rx_buff <= 0;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            tx_bit_cnt <= 0;
            rx_bit_cnt <= 0;
        end else begin
            case (n_state)
                FSM_TRANSMIT: begin
                    if (tx_shift_en) begin
                        if (tx_bit_cnt >= DATA_WIDTH - 1) begin
                            tx_bit_cnt <= 0;
                        end else begin
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        end
                    end
                    if (rx_shift_en) begin
                        if (rx_bit_cnt >= DATA_WIDTH - 1) begin
                            rx_bit_cnt <= 0;
                        end else begin
                            rx_bit_cnt <= rx_bit_cnt + 1;
                        end
                    end
                end
                default: begin
                    tx_bit_cnt <= 0;
                    rx_bit_cnt <= 0;
                end
            endcase
        end
    end

    // latch data and report when the last bit is shift in
    always @(posedge clk) begin
        if (!rstn) begin
            rx_data  <= 0;
            rx_valid <= 1'b0;
        end else begin
            case (n_state)
                FSM_TRANSMIT, FSM_POST_WAIT: begin
                    if (rx_shift_en) begin
                        if (rx_bit_cnt == (DATA_WIDTH - 1)) begin
                            rx_valid <= 1'b1;
                            rx_data  <= {spi_rx_buff[DATA_WIDTH-2:0], spi_miso};
                        end else begin
                            rx_data  <= 0;
                            rx_valid <= 1'b0;
                        end
                    end else begin
                        rx_data  <= 0;
                        rx_valid <= 1'b0;
                    end
                end
                default: begin
                    rx_data  <= 0;
                    rx_valid <= 1'b0;
                end
            endcase
        end
    end

    // keep busy until all transfers have been finished
    always @(posedge clk) begin
        if (!rstn) begin
            tx_busy <= 1'b1;
        end else begin
            case (n_state)
                FSM_IDLE: begin
                    tx_busy <= 1'b0;
                end
                default: begin
                    tx_busy <= 1'b1;
                end
            endcase
        end
    end

    // require new data at the time when all bits are shifted out
    always @(posedge clk) begin
        if (!rstn) begin
            tx_ready <= 1'b0;
        end else begin
            case (n_state)
                FSM_IDLE: begin
                    tx_ready <= 1'b1;
                end
                FSM_TRANSMIT: begin
                    if ((tx_shift_en == 1'b1) && (tx_bit_cnt == DATA_WIDTH / 2 - 1)) begin
                        tx_ready <= 1'b1;
                    end else begin
                        tx_ready <= 1'b0;
                    end
                end
                default: begin
                    tx_ready <= 1'b0;
                end
            endcase
        end
    end

endmodule

// verilog_format: off
`resetall
// verilog_format: on
