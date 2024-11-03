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
// Module Name   : clk_gen
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

module clk_gen #(
    parameter CLK_MODE_SEL = 2'b00,  // 00:BUAD_GEN,01:CLK_DIV,10:EXT_CLK
    parameter CPOL         = 1'b0,
    parameter CPHA         = 1'b0
) (
    input  wire        clk,
    input  wire        rstn,
    input  wire        oen,
    input  wire        en,
    input  wire        load,
    input  wire [11:0] baud_freq,
    input  wire [15:0] baud_limit,
    input  wire [31:0] baud_div,
    input  wire        ext_clk,     // don't exceed 1/4 of the clk frequency
    output reg         sync_clk,
    output reg         shift_en,
    output reg         latch_en
);
    reg       int_sync_clk = 1'b0;
    reg [1:0] sync_clk_dd;

    // ***********************************************************************************
    // config register
    // ***********************************************************************************
    generate
        if (CLK_MODE_SEL == 2'b00) begin

            reg [11:0] baud_freq_reg;
            reg [15:0] baud_limit_reg;
            reg [15:0] counter;
            reg [ 3:0] count16;
            reg        ce_16;

            always @(posedge clk) begin
                if (~rstn) begin
                    baud_freq_reg  <= 4;
                    baud_limit_reg <= 1;
                end else if (load) begin
                    if (baud_freq > 0) begin
                        baud_freq_reg <= baud_freq;
                    end

                    if (baud_limit > 0) begin
                        baud_limit_reg <= baud_limit;
                    end
                end
            end

            always @(posedge clk) begin
                if (~rstn | ~en) begin
                    counter <= 16'b0;
                end else if (counter >= baud_limit_reg) begin
                    counter <= counter - baud_limit_reg;
                end else begin
                    counter <= counter + {4'h0, baud_freq_reg};
                end
            end

            // clock divider output
            always @(posedge clk) begin
                if (~rstn | ~en) begin
                    ce_16 <= 1'b0;
                end else if (counter >= baud_limit_reg) begin
                    ce_16 <= 1'b1;
                end else begin
                    ce_16 <= 1'b0;
                end
            end

            // ce_16 divider output
            always @(posedge clk) begin
                if (~rstn | ~en) begin
                    count16 <= 4'b0;
                end else if (ce_16) begin
                    count16 <= count16 + 4'h1;
                end
            end

            always @(posedge clk) begin
                if (~rstn | ~en) begin
                    int_sync_clk <= 1'b0;
                end else begin
                    if (ce_16) begin
                        if (count16 < 8) begin
                            int_sync_clk <= 1'b0;
                        end else begin
                            int_sync_clk <= 1'b1;
                        end
                    end
                end
            end

        end else if (CLK_MODE_SEL == 2'b01) begin
            reg [31:0] baud_div_reg;
            reg [31:0] counter;
            always @(posedge clk) begin
                if (~rstn) begin
                    baud_div_reg <= 15;
                end else if (load) begin
                    if (baud_div > 1) begin
                        baud_div_reg <= baud_div - 1;
                    end
                end
            end

            always @(posedge clk) begin
                if (~rstn | ~en) begin
                    counter <= 16'b0;
                end else if (counter >= baud_div_reg) begin
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end

            // clk divider output
            always @(posedge clk) begin
                if (~rstn | ~en) begin
                    int_sync_clk <= 1'b0;
                end else if (counter > baud_div_reg[31:1]) begin
                    int_sync_clk <= 1'b1;
                end else begin
                    int_sync_clk <= 1'b0;
                end
            end
        end else if (CLK_MODE_SEL == 2'b10) begin
            always @(posedge clk) begin
                int_sync_clk <= ext_clk;
            end
        end else begin
            always @(posedge clk) begin
                int_sync_clk <= 1'b0;
            end
        end
    endgenerate

    // ***********************************************************************************
    // tx enable strobe
    // ***********************************************************************************
    always @(posedge clk) begin
        if (~rstn | ~en) begin
            sync_clk_dd <= 2'b00;
        end else begin
            sync_clk_dd <= {sync_clk_dd[0], int_sync_clk};
        end
    end

    always @(posedge clk) begin
        if (~rstn | ~en) begin
            shift_en <= 1'b0;
        end else begin
            if ((sync_clk_dd[0] & (~sync_clk_dd[1]))) begin
                shift_en <= 1'b1;
            end else begin
                shift_en <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (~rstn | ~en) begin
            latch_en <= 1'b0;
        end else begin
            if ((sync_clk_dd[1] & (~sync_clk_dd[0]))) begin
                latch_en <= 1'b1;
            end else begin
                latch_en <= 1'b0;
            end
        end
    end

    // ***********************************************************************************
    // sync clk for output
    // ***********************************************************************************

    always @(posedge clk) begin
        if (~rstn | ~en) begin
            sync_clk <= CPOL;
        end else begin
            if (oen) begin
                if (shift_en) begin
                    sync_clk <= CPHA ? ~CPOL : CPOL;
                end else if (latch_en) begin
                    sync_clk <= CPHA ? CPOL : ~CPOL;
                end
            end else begin
                sync_clk <= CPOL;
            end
        end
    end

endmodule

// verilog_format: off
`resetall
// verilog_format: on
