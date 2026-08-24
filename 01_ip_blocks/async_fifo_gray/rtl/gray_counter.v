/*******************************************************************************
 * Module: gray_counter.v                                                      *
 * Description:                                                                *
 * Description: N-bit binary counter with Gray-code output.
 *              Used as read/write pointer in async FIFO.
 *              Gray code guarantees only 1-bit change per clock cycle,
 *              making it safe to sample across clock domains.
 * File Created: Saturday, 22nd August 2026 9:51:01 am                         *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Monday, 24th August 2026 10:26:40 am                         *
 * Modified By: Long Hai                                                       *
*******************************************************************************/

`timescale 1ns/1ps
`default_nettype none

module gray_counter #(
    parameter WIDTH = 5     // Counter width (ADDR_WIDTH + 1; extra MSB for full/empty detect)
) (
    input  wire             i_clk,
    input  wire             i_rst_n,    // active-low
    input  wire             i_en,
    output wire [WIDTH-1:0] o_gray,     // Gray-code output (WIDTH bits)
    output wire [WIDTH-1:0] o_bin       // Binary output (WIDTH bits)
);

    reg [WIDTH-1:0] r_bin;

    // Sequential: increment binary counter on enable
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)  r_bin <= {WIDTH{1'b0}};
        else if (i_en) r_bin <= r_bin + 1'b1;
    end

    // Combinational: binary -> Gray  (Gray[i] = Bin[i] ^ Bin[i+1])
    assign o_gray = r_bin ^ (r_bin >> 1);
    assign o_bin  = r_bin;

endmodule

`default_nettype wire
