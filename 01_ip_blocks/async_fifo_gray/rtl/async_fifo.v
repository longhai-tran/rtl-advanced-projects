/*******************************************************************************
 * Module: async_fifo.v                                                        *
 * Description:                                                                *
 * Description: Asynchronous FIFO with Gray-code pointers (Cummings method).
 *              Dual-clock: write and read domains have independent clocks and
 *              active-low asynchronous resets.
 *              Read port is combinational (show-ahead / look-ahead style).
 *
 * File Created: Saturday, 22nd August 2026 9:51:01 am                         *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Monday, 24th August 2026 10:24:59 am                         *
 * Modified By: Long Hai                                                       *
*******************************************************************************/

`timescale 1ns/1ps
`default_nettype none

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4     // Depth = 2^ADDR_WIDTH  (default: 4 -> 16 entries)
) (
    // Write clock domain
    input  wire                  i_wr_clk,
    input  wire                  i_wr_rst_n,
    input  wire                  i_wr_en,
    input  wire [DATA_WIDTH-1:0] i_wr_data,
    output reg                   o_full,
    output wire [ADDR_WIDTH:0]   o_wr_count,

    // Read clock domain
    input  wire                  i_rd_clk,
    input  wire                  i_rd_rst_n,
    input  wire                  i_rd_en,
    output wire [DATA_WIDTH-1:0] o_rd_data,
    output reg                   o_empty,
    output wire [ADDR_WIDTH:0]   o_rd_count
);

    localparam LP_DEPTH = 1 << ADDR_WIDTH;
    localparam LP_PTR_W = ADDR_WIDTH + 1;

    //=========================================================================
    // Gray-to-Binary conversion function
    //   Used to convert synchronized Gray pointers back to binary for
    //   word-count calculation without crossing raw binary signals.
    //=========================================================================
    function automatic [LP_PTR_W-1:0] gray2bin;
        input [LP_PTR_W-1:0] gray;
        integer k;
        begin
            gray2bin[LP_PTR_W-1] = gray[LP_PTR_W-1];
            for (k = LP_PTR_W-2; k >= 0; k = k-1)
                gray2bin[k] = gray2bin[k+1] ^ gray[k];
        end
    endfunction

    //=========================================================================
    // Pointer wire declarations (forward-declared before RAM uses them)
    //=========================================================================
    wire [LP_PTR_W-1:0] w_wr_gray;
    wire [LP_PTR_W-1:0] w_wr_bin;
    wire [LP_PTR_W-1:0] w_rd_gray;
    wire [LP_PTR_W-1:0] w_rd_bin;

    //=========================================================================
    // Dual-port behavioral RAM
    //=========================================================================
    reg [DATA_WIDTH-1:0] mem [0:LP_DEPTH-1];

    wire w_wr_fire = i_wr_en & ~o_full;
    wire w_rd_fire = i_rd_en & ~o_empty;

    always @(posedge i_wr_clk) begin
        if (w_wr_fire)
            mem[w_wr_bin[ADDR_WIDTH-1:0]] <= i_wr_data;
    end

    // Combinational (show-ahead) read: data valid as soon as ~o_empty
    assign o_rd_data = mem[w_rd_bin[ADDR_WIDTH-1:0]];

    //=========================================================================
    // Write pointer (write domain)
    //=========================================================================

    gray_counter #(.WIDTH(LP_PTR_W)) u_wr_ptr (
        .i_clk   (i_wr_clk),
        .i_rst_n (i_wr_rst_n),
        .i_en    (w_wr_fire),
        .o_gray  (w_wr_gray),
        .o_bin   (w_wr_bin)
    );

    //=========================================================================
    // Read pointer (read domain)
    //=========================================================================
    gray_counter #(.WIDTH(LP_PTR_W)) u_rd_ptr (
        .i_clk   (i_rd_clk),
        .i_rst_n (i_rd_rst_n),
        .i_en    (w_rd_fire),
        .o_gray  (w_rd_gray),
        .o_bin   (w_rd_bin)
    );

    //=========================================================================
    // CDC: sync write Gray pointer into read domain (for empty detection)
    //=========================================================================
    wire [LP_PTR_W-1:0] w_wr_gray_sync;

    sync_2ff #(.WIDTH(LP_PTR_W)) u_sync_wr2rd (
        .i_clk   (i_rd_clk),
        .i_rst_n (i_rd_rst_n),
        .i_d     (w_wr_gray),
        .o_q     (w_wr_gray_sync)
    );

    //=========================================================================
    // CDC: sync read Gray pointer into write domain (for full detection)
    //=========================================================================
    wire [LP_PTR_W-1:0] w_rd_gray_sync;

    sync_2ff #(.WIDTH(LP_PTR_W)) u_sync_rd2wr (
        .i_clk   (i_wr_clk),
        .i_rst_n (i_wr_rst_n),
        .i_d     (w_rd_gray),
        .o_q     (w_rd_gray_sync)
    );

    //=========================================================================
    // EMPTY detection (read domain)
    //   Empty when rd_gray == synchronized wr_gray
    //=========================================================================
    wire w_empty_next = (w_rd_gray == w_wr_gray_sync);

    always @(posedge i_rd_clk or negedge i_rd_rst_n) begin
        if (!i_rd_rst_n) o_empty <= 1'b1;
        else             o_empty <= w_empty_next;
    end

    //=========================================================================
    // FULL detection (write domain)
    //   Cummings method: MSB and MSB-1 inverted, lower bits equal
    //=========================================================================
    wire w_full_next = (w_wr_gray ==
                        {~w_rd_gray_sync[LP_PTR_W-1:LP_PTR_W-2],
                          w_rd_gray_sync[LP_PTR_W-3:0]});

    always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
        if (!i_wr_rst_n) o_full <= 1'b0;
        else             o_full <= w_full_next;
    end

    //=========================================================================
    // Word count — each domain uses its own binary pointer plus the
    // synchronized (gray2bin converted) pointer from the other domain.
    // Result is an approximation due to CDC latency.
    //=========================================================================
    assign o_wr_count = w_wr_bin - gray2bin(w_rd_gray_sync);  // write domain view
    assign o_rd_count = gray2bin(w_wr_gray_sync) - w_rd_bin;  // read domain view

endmodule

`default_nettype wire
