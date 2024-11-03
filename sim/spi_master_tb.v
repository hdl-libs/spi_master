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
// Module Name   : spi_master_tb
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

module spi_master_tb;

    // Parameters
    localparam real TIMEPERIOD = 10;
    localparam integer DATA_WIDTH = 8;
    localparam CPOL = 1'b0;
    localparam CPHA = 1'b0;

    // Ports
    reg                   clk = 0;
    reg                   rstn = 0;
    wire                  spi_miso;
    reg                   tx_valid = 0;
    reg  [DATA_WIDTH-1:0] tx_data = 0;
    wire                  spi_scsn;
    wire                  spi_sclk;
    wire                  spi_mosi;
    wire                  tx_ready;
    wire [DATA_WIDTH-1:0] rx_data;
    wire                  rx_valid;
    reg                   load = 0;
    reg  [          31:0] baud_div = 0;

    spi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .CPOL      (CPOL),
        .CPHA      (CPHA)
    ) dut (
        .clk     (clk),
        .rstn    (rstn),
        .load    (load),
        .baud_div(baud_div),
        .spi_scsn(spi_scsn),
        .spi_sclk(spi_sclk),
        .spi_miso(spi_miso),
        .spi_mosi(spi_mosi),
        .tx_valid(tx_valid),
        .tx_data (tx_data),
        .tx_ready(tx_ready),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    assign spi_miso = spi_mosi;

    initial begin
        begin
            tx_valid = 0;
            tx_data  = 0;
            wait (rstn);
            #50;
            load     = 1;
            baud_div = 5;
            #50;
            load     = 0;
            baud_div = 0;
            #100;
            tx_data  = 16'h0081;
            tx_valid = 1'b1;
            #20;
            tx_valid = 1'b0;
            wait (tx_ready);
            tx_data  = 16'h0081;
            tx_valid = 1'b1;
            #30;
            tx_valid = 1'b0;
            wait (tx_ready);
            #1000;
            $finish;
        end
    end

    always #(TIMEPERIOD / 2) clk = !clk;

    // reset block
    initial begin
        rstn = 1'b0;
        #(TIMEPERIOD * 2);
        rstn = 1'b1;
    end

    // record block
    initial begin
        $dumpfile("sim/test_tb.lxt");
        $dumpvars(0, spi_master_tb);
    end

endmodule

// verilog_format: off
`resetall
// verilog_format: on
