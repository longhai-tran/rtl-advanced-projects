//=============================================================================
// Testbench: async_fifo_tb
// DUT:       async_fifo -- dual-clock FIFO with Gray-code pointers
//
// Read-port style: combinational / show-ahead
//   o_rd_data is valid at the CURRENT read pointer as soon as ~o_empty.
//   rd_en ADVANCES the pointer -- it does not gate the output.
//   -> Data must be sampled BEFORE asserting rd_en.
//
// Test plan:
//   T1 - Basic: write 8, read 8
//   T2 - Fill to FULL
//   T3 - Drain to EMPTY  (continues from T2 state; no reset between T2/T3)
//   T4 - Concurrent: write clock faster than read clock
//   T5 - Concurrent: read clock faster than write clock
//=============================================================================
`timescale 1ns/1ps

// EXPECT_HIGH: check that a flag signal is asserted; record error if not.
// Using a macro (not a task) so we can pass a signal directly.
`define EXPECT_HIGH(sig, name) \
    if (sig) $display("[PASS] %s asserted", name); \
    else begin $display("[ERR]  %s NOT asserted", name); err = err + 1; end

module async_fifo_tb;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter DW      = 8;   // data width
    parameter AW      = 4;   // address width  ->  depth = 2^AW = 16
    parameter WR_HALF = 5;   // write clock half-period (ns)  ->  100 MHz
    parameter RD_HALF = 8;   // read  clock half-period (ns)  ->  ~62.5 MHz

    //-------------------------------------------------------------------------
    // DUT signals
    //-------------------------------------------------------------------------
    reg             r_wr_clk,  r_rd_clk;
    reg             r_wr_rst_n, r_rd_rst_n;
    reg             r_wr_en,   r_rd_en;
    reg  [DW-1:0]   r_wr_data;

    wire            w_full,    w_empty;
    wire [DW-1:0]   w_rd_data;
    wire [AW:0]     w_wr_count, w_rd_count;

    //-------------------------------------------------------------------------
    // DUT instantiation
    //-------------------------------------------------------------------------
    async_fifo #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW)) dut (
        .i_wr_clk   (r_wr_clk),
        .i_wr_rst_n (r_wr_rst_n),
        .i_wr_en    (r_wr_en),
        .i_wr_data  (r_wr_data),
        .o_full     (w_full),
        .o_wr_count (w_wr_count),
        .i_rd_clk   (r_rd_clk),
        .i_rd_rst_n (r_rd_rst_n),
        .i_rd_en    (r_rd_en),
        .o_rd_data  (w_rd_data),
        .o_empty    (w_empty),
        .o_rd_count (w_rd_count)
    );

    //-------------------------------------------------------------------------
    // Clock generation
    //-------------------------------------------------------------------------
    initial r_wr_clk = 0; always #(WR_HALF) r_wr_clk = ~r_wr_clk;
    initial r_rd_clk = 0; always #(RD_HALF) r_rd_clk = ~r_rd_clk;

    //-------------------------------------------------------------------------
    // Reference model
    //   ref_q[] stores expected data in write order (256-entry circular buffer).
    //   Indices are masked with & 8'hFF to wrap at 256 and avoid out-of-bounds.
    //-------------------------------------------------------------------------
    reg [DW-1:0] ref_q [0:255];
    integer      wr_idx = 0, rd_idx = 0, err = 0, tnum = 0;

    //=========================================================================
    // Tasks
    //=========================================================================

    //--- reset_all -----------------------------------------------------------
    // Assert reset on BOTH domains, then release.
    // Each domain has its own rst_n (CDC best practice): reset de-asserts
    // synchronously to each clock independently.
    task reset_all;
        begin
            r_wr_rst_n = 0; r_rd_rst_n = 0;
            r_wr_en    = 0; r_rd_en    = 0;
            r_wr_data  = 0;
            repeat(4) @(posedge r_wr_clk);
            repeat(4) @(posedge r_rd_clk);
            r_wr_rst_n = 1; r_rd_rst_n = 1;
            @(posedge r_wr_clk);
            wr_idx = 0; rd_idx = 0;
        end
    endtask

    //--- wr ------------------------------------------------------------------
    // Attempt one write. Signals are driven AFTER posedge+#1 to avoid a
    // simulation race: the #1 delay pushes the assignment past the clock's
    // active-region, so the DUT samples clean values on the NEXT posedge.
    task wr;
        input [DW-1:0] d;
        begin
            // @(posedge r_wr_clk); #1;           // #1: anti-race delay
            @(negedge r_wr_clk);
            if (w_full) begin
                $display("[WARN] T%0d: Write skipped - FIFO full (data=%02h)", tnum, d);
            end else begin
                r_wr_en   = 1;
                r_wr_data = d;
                ref_q[wr_idx & 8'hFF] = d;     // & 8'hFF: circular wrap
                wr_idx = wr_idx + 1;
                // @(posedge r_wr_clk); #1;
                @(negedge r_wr_clk);
                r_wr_en = 0;
            end
        end
    endtask

    //--- rd_check ------------------------------------------------------------
    // Show-ahead read: o_rd_data is already stable at the CURRENT pointer.
    // Step 1 -- verify data BEFORE advancing. Step 2 -- pulse rd_en to advance.
    task rd_check;
        begin
            // @(posedge r_rd_clk); #1;
            @(negedge r_rd_clk);
            if (w_empty) begin
                $display("[WARN] T%0d: Read skipped - FIFO empty (idx=%0d)", tnum, rd_idx);
            end else begin
                if (w_rd_data !== ref_q[rd_idx & 8'hFF]) begin
                    $display("[ERR]  T%0d: exp=%02h got=%02h idx=%0d",
                             tnum, ref_q[rd_idx & 8'hFF], w_rd_data, rd_idx);
                    err = err + 1;
                end
                r_rd_en = 1;                    // advance pointer
                @(negedge r_rd_clk);
                r_rd_en = 0;
                rd_idx  = rd_idx + 1;
            end
        end
    endtask

    //=========================================================================
    // Test sequence
    //=========================================================================
    integer i;

    initial begin
        $dumpfile("wave.vcd");              // VCD for GTKWave / Vivado waveform viewer
        $dumpvars(0, async_fifo_tb);
        $display("==== Async FIFO Gray -- TB (DW=%0d DEPTH=%0d) ====", DW, 1 << AW);

        // T1: basic write then read ----------------------------------------
        tnum = 1; reset_all;
        $display("-- T%0d: Write 8 / Read 8 --", tnum);
        for (i = 0; i < 8; i = i+1) wr(8'hA0 + i);
        repeat(4) @(posedge r_rd_clk); // wait for CDC sync latency (2 FF stages)
        for (i = 0; i < 8; i = i+1) rd_check;

        // T2: fill to FULL -------------------------------------------------
        tnum = 2; reset_all;
        $display("-- T%0d: Fill to FULL --", tnum);
        for (i = 0; i < 20; i = i+1) wr(8'hB0 + i); // writes beyond 16 hit FULL
        repeat(2) @(posedge r_wr_clk);
        `EXPECT_HIGH(w_full, "FULL")

        // T3: drain to EMPTY (no reset -- continues from T2 full state) -----
        tnum = 3;
        $display("-- T%0d: Drain to EMPTY --", tnum);
        repeat(20) rd_check;
        repeat(4) @(posedge r_rd_clk);
        `EXPECT_HIGH(w_empty, "EMPTY")

        // T4: concurrent -- write clock faster than read -------------------
        // fork/join: both begin blocks run IN PARALLEL; join waits for both.
        tnum = 4; reset_all;
        $display("-- T%0d: Concurrent wr>rd --", tnum);
        fork
            begin : writer4 for (i=0; i<12; i=i+1) wr(8'hC0+i); end
            begin : reader4 repeat(3) @(posedge r_rd_clk);
                            for (i=0; i<12; i=i+1) rd_check; end
        join

        // T5: concurrent -- read clock faster than write -------------------
        tnum = 5; reset_all;
        $display("-- T%0d: Concurrent rd>wr --", tnum);
        fork
            begin : writer5
                for (i=0; i<10; i=i+1) begin
                    wr(8'hD0+i);
                    @(posedge r_wr_clk); // extra gap to make writer slower
                end
            end
            begin : reader5
                repeat(2) @(posedge r_rd_clk);
                for (i=0; i<10; i=i+1) rd_check;
            end
        join

        // Summary ----------------------------------------------------------
        repeat(10) @(posedge r_wr_clk);
        $display("================================================");
        if (err == 0) $display("  RESULT: ALL TESTS PASSED");
        else          $display("  RESULT: %0d ERROR(S)", err);
        $display("================================================");
        $finish;
    end

    // Timeout guard: stops infinite simulation if DUT hangs
    initial begin
        #200_000;                           // underscore for readability: 200 us
        $display("[TIMEOUT] Simulation exceeded 200 us limit");
        $finish;
    end

endmodule
