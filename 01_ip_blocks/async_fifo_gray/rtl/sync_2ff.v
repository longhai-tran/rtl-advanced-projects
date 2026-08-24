/*******************************************************************************
 * Module: sync_2ff.v                                                          *
 * Description: 2-stage flip-flop synchronizer for Clock Domain Crossing (CDC).
 *              Reduces metastability probability to negligible levels.
 *
 *              IMPORTANT: Safe for multi-bit signals ONLY when the input
 *              changes by at most 1 bit per cycle — i.e. Gray-code pointers.
 *              Do NOT use with arbitrary multi-bit buses.
 * File Created: Saturday, 22nd August 2026 9:51:01 am                         *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Monday, 24th August 2026 10:46:07 am                         *
 * Modified By: Long Hai                                                       *
*******************************************************************************/

`timescale 1ns/1ps
`default_nettype none

module sync_2ff #(
    parameter WIDTH = 1                 // Synchronizer width (1 for single-bit; PTR_W for Gray pointer)
) (
    input  wire             i_clk,      // Destination clock domain
    input  wire             i_rst_n,    // Async reset in destination domain (active-low)
    input  wire [WIDTH-1:0] i_d,        // Async input from source domain
    output wire [WIDTH-1:0] o_q         // Synchronized output in destination domain
);

    // (* ASYNC_REG = "TRUE" *) tells synthesis tools (Vivado/Quartus) to:
    //   - Place these FFs close together (minimize inter-FF routing delay)
    //   - Disable optimization / retiming across the synchronizer chain
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] r_ff1;
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] r_ff2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_ff1 <= {WIDTH{1'b0}};
            r_ff2 <= {WIDTH{1'b0}};
        end else begin
            r_ff1 <= i_d;
            r_ff2 <= r_ff1;
        end
    end

    assign o_q = r_ff2;

endmodule

`default_nettype wire
