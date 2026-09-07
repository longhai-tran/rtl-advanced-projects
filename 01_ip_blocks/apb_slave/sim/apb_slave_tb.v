/*******************************************************************************
 * Module: apb_slave_tb.v                                                      *
 * Description: Self-checking testbench for the APB4 register slave.
 *              Covers: reset, full/partial writes, read-only status,
 *              invalid addresses, and back-to-back transfers.
 * File Created: Thursday, 27th August 2026 11:01:53 am                        *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Thursday, 27th August 2026 3:25:21 pm                        *
 * Modified By: Long Hai                                                       *
*******************************************************************************/

`timescale 1ns/1ps
`default_nettype none

module apb_slave_tb;

    // --- Address Map (mirrors DUT localparams) ---
    localparam [7:0] ADDR_REG0   = 8'h00;
    localparam [7:0] ADDR_REG1   = 8'h04;
    localparam [7:0] ADDR_REG2   = 8'h08;
    localparam [7:0] ADDR_REG6   = 8'h18;
    localparam [7:0] ADDR_STATUS = 8'h1C;

    // --- APB Bus Drivers (reg = driven by testbench) ---
    reg         r_pclk;
    reg         r_presetn;
    reg         r_psel;
    reg         r_penable;
    reg         r_pwrite;
    reg  [7:0]  r_paddr;
    reg  [31:0] r_pwdata;
    reg  [3:0]  r_pstrb;

    // --- APB Bus Responses (wire = driven by DUT) ---
    wire [31:0] w_prdata;
    wire        w_pready;
    wire        w_pslverr;

    // --- Application Interface ---
    reg  [31:0] r_status;  // Drives i_status on the DUT
    wire [31:0] w_reg0;
    wire [31:0] w_reg1;
    wire [31:0] w_reg2;
    wire [31:0] w_reg3;
    wire [31:0] w_reg4;
    wire [31:0] w_reg5;
    wire [31:0] w_reg6;

    // --- Scoreboard Counters ---
    integer r_errors;       // Number of failed checks
    integer r_tests;        // Total checks run

    // --- Temp variables for task outputs ---
    reg [31:0] r_read_data;
    reg        r_read_error;

    // --- DUT Instantiation ---
    // RESET_VALUE = 0xA5A5_0000 so we can confirm reset is actually applied
    apb_slave #(.RESET_VALUE(32'hA5A5_0000)) dut (
        .pclk     (r_pclk),
        .presetn  (r_presetn),
        .psel     (r_psel),
        .penable  (r_penable),
        .pwrite   (r_pwrite),
        .paddr    (r_paddr),
        .pwdata   (r_pwdata),
        .pstrb    (r_pstrb),
        .prdata   (w_prdata),
        .pready   (w_pready),
        .pslverr  (w_pslverr),
        .i_status (r_status),
        .o_reg0   (w_reg0),
        .o_reg1   (w_reg1),
        .o_reg2   (w_reg2),
        .o_reg3   (w_reg3),
        .o_reg4   (w_reg4),
        .o_reg5   (w_reg5),
        .o_reg6   (w_reg6)
    );

    // --- Clock Generation: 10 ns period = 100 MHz ---
    initial r_pclk = 1'b0;
    always #5 r_pclk = ~r_pclk;

    // =========================================================================
    // Task: apb_idle
    // De-assert all bus signals — bus returns to idle state.
    // =========================================================================
    task apb_idle;
        begin
            r_psel    = 1'b0;
            r_penable = 1'b0;
            r_pwrite  = 1'b0;
            r_paddr   = 8'd0;
            r_pwdata  = 32'd0;
            r_pstrb   = 4'd0;
        end
    endtask

    // =========================================================================
    // Task: apb_write
    // Performs one complete APB write transfer (Setup → Access → Idle).
    //   Cycle 1 (Setup) : PSEL=1, PENABLE=0, address/data/strb driven
    //   Cycle 2 (Access): PENABLE=1, transfer completes, PSLVERR sampled
    //   Cycle 3         : bus returns to idle
    // =========================================================================
    task apb_write;
        input [7:0]  addr;   // Target register address
        input [31:0] data;   // Data to write
        input [3:0]  strb;   // Byte enables (1 bit per byte lane)
        output       error;  // Captures PSLVERR at end of Access phase
        begin
            // Setup phase: present address and data
            @(negedge r_pclk);
            r_psel    = 1'b1;
            r_penable = 1'b0;
            r_pwrite  = 1'b1;
            r_paddr   = addr;
            r_pwdata  = data;
            r_pstrb   = strb;

            // Access phase: assert PENABLE, sample error response
            @(negedge r_pclk);
            r_penable = 1'b1;
            #1 error = w_pslverr;  // Small delay to let combinational signals settle

            // Return to idle
            @(negedge r_pclk);
            apb_idle;
        end
    endtask

    // =========================================================================
    // Task: apb_read
    // Performs one complete APB read transfer (Setup → Access → Idle).
    //   Cycle 1 (Setup) : PSEL=1, PENABLE=0, PWRITE=0, address driven
    //   Cycle 2 (Access): PENABLE=1, PRDATA and PSLVERR sampled
    //   Cycle 3         : bus returns to idle
    // =========================================================================
    task apb_read;
        input  [7:0]  addr;   // Target register address
        output [31:0] data;   // Captured read data from DUT
        output        error;  // Captures PSLVERR at end of Access phase
        begin
            // Setup phase: present address, indicate read
            @(negedge r_pclk);
            r_psel    = 1'b1;
            r_penable = 1'b0;
            r_pwrite  = 1'b0;
            r_paddr   = addr;

            // Access phase: assert PENABLE, capture PRDATA (combinational)
            @(negedge r_pclk);
            r_penable = 1'b1;
            #1 begin
                data  = w_prdata;   // PRDATA is valid combinationally in Access phase
                error = w_pslverr;
            end

            // Return to idle
            @(negedge r_pclk);
            apb_idle;
        end
    endtask

    // =========================================================================
    // Task: check
    // Self-checking assertion. Increments r_tests each call.
    // Prints [PASS] or [FAIL] and increments r_errors on failure.
    // =========================================================================
    task check;
        input condition;          // Expression that must be true to pass
        input [8*64-1:0] message; // Description printed with result
        begin
            r_tests = r_tests + 1;
            if (condition)
                $display("[PASS] %0s", message);
            else begin
                r_errors = r_errors + 1;
                $display("[FAIL] %0s", message);
            end
        end
    endtask

    // =========================================================================
    // Task: back_to_back_write
    // Performs two APB writes with no idle cycle between them (T6).
    // Access phase of write 1 → Setup phase of write 2 in the next cycle.
    // =========================================================================
    task back_to_back_write;
        begin
            // Write 1 Setup: REG1 = 0x1111_1111
            @(negedge r_pclk);
            r_psel    = 1'b1;
            r_penable = 1'b0;
            r_pwrite  = 1'b1;
            r_paddr   = ADDR_REG1;
            r_pwdata  = 32'h1111_1111;
            r_pstrb   = 4'hF;

            // Write 1 Access: REG1 committed on next rising edge
            @(negedge r_pclk);
            r_penable = 1'b1;

            // Write 2 Setup: immediately switch to REG2 (no idle gap)
            @(negedge r_pclk);
            r_penable = 1'b0;
            r_paddr   = ADDR_REG2;
            r_pwdata  = 32'h2222_2222;

            // Write 2 Access: REG2 committed on next rising edge
            @(negedge r_pclk);
            r_penable = 1'b1;

            // Return to idle
            @(negedge r_pclk);
            apb_idle;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // Initialise scoreboard and drive a known i_status value
        r_errors = 0;
        r_tests  = 0;
        r_status = 32'hCAFE_BABE;
        apb_idle;

        // Apply reset for 3 clock cycles then release
        r_presetn = 1'b0;
        repeat (3) @(posedge r_pclk);
        r_presetn = 1'b1;
        @(posedge r_pclk);

        // -----------------------------------------------------------------
        // T1: Reset and idle — verify default state after reset
        // -----------------------------------------------------------------
        $display("[TEST] T1: reset and idle outputs");
        check(w_pready === 1'b1, "PREADY is always asserted");
        check(w_reg0 === 32'hA5A5_0000 && w_reg6 === 32'hA5A5_0000,
              "all R/W registers reset to RESET_VALUE");
        check(w_pslverr === 1'b0 && w_prdata === 32'd0,
              "idle response is clean");

        // -----------------------------------------------------------------
        // T2: Full-word write then read — PSTRB=0xF writes all 4 byte lanes
        // -----------------------------------------------------------------
        $display("[TEST] T2: full-word read and write");
        apb_write(ADDR_REG0, 32'h1234_5678, 4'hF, r_read_error);
        apb_read (ADDR_REG0, r_read_data, r_read_error);
        check(r_read_data === 32'h1234_5678 && !r_read_error,
              "full-word write reads back correctly");

        // -----------------------------------------------------------------
        // T3: Byte strobe — PSTRB=0b0101 → only byte lanes 0 and 2 change
        //   Before : REG0 = 0x1234_5678
        //   PWDATA  = 0xDEAD_BEEF, PSTRB = 0b0101
        //   After  : REG0 = 0x12AD_56EF  (bytes 1,3 unchanged)
        // -----------------------------------------------------------------
        $display("[TEST] T3: APB4 byte strobes");
        apb_write(ADDR_REG0, 32'hDEAD_BEEF, 4'b0101, r_read_error);
        apb_read (ADDR_REG0, r_read_data, r_read_error);
        check(r_read_data === 32'h12AD_56EF,
              "PSTRB updates only selected byte lanes");
        // PSTRB=0 → no byte lane written, register must stay the same
        apb_write(ADDR_REG0, 32'hFFFF_FFFF, 4'b0000, r_read_error);
        check(w_reg0 === 32'h12AD_56EF, "zero strobe leaves register unchanged");

        // -----------------------------------------------------------------
        // T4: STATUS register (0x1C) — read-only, wired to i_status
        //   Writes must be silently ignored (no PSLVERR, no data change)
        // -----------------------------------------------------------------
        $display("[TEST] T4: read-only status register");
        apb_read(ADDR_STATUS, r_read_data, r_read_error);
        check(r_read_data === 32'hCAFE_BABE, "STATUS reflects live input");
        apb_write(ADDR_STATUS, 32'h0000_0000, 4'hF, r_read_error);
        apb_read (ADDR_STATUS, r_read_data, r_read_error);
        check(r_read_data === 32'hCAFE_BABE && !r_read_error,
              "STATUS ignores writes without reporting an error");

        // -----------------------------------------------------------------
        // T5: Invalid and misaligned addresses
        //   0x20 = out-of-range  → PSLVERR=1, PRDATA=0
        //   0x02 = misaligned    → PSLVERR=1, no register modified
        // -----------------------------------------------------------------
        $display("[TEST] T5: invalid and misaligned addresses");
        apb_read(8'h20, r_read_data, r_read_error);
        check(r_read_error && r_read_data === 32'd0,
              "out-of-range read returns zero and PSLVERR");
        apb_write(8'h02, 32'hFFFF_FFFF, 4'hF, r_read_error);
        check(r_read_error && w_reg0 === 32'h12AD_56EF,
              "misaligned write reports PSLVERR and changes no data");

        // -----------------------------------------------------------------
        // T6: Back-to-back transfers — no idle cycle between two writes
        // -----------------------------------------------------------------
        $display("[TEST] T6: back-to-back transfers");
        back_to_back_write;
        check(w_reg1 === 32'h1111_1111 && w_reg2 === 32'h2222_2222,
              "consecutive transfers complete without an idle cycle");

        // --- Final Simulation Summary Report ---
        $display("==================================================");
        $display("           SIMULATION SUMMARY REPORT              ");
        $display("==================================================");
        $display("  Total Test Scenarios   : 6 (T1 - T6)");
        $display("  Assertion Checks Run   : %0d", r_tests);
        $display("  Assertion Errors       : %0d", r_errors);
        $display("==================================================");
        if (r_errors == 0) begin
            $display("  FINAL RESULT: ALL TESTS PASSED");
            $display("==================================================");
            $finish;
        end else begin
            $display("  FINAL RESULT: TEST FAILED (%0d error(s))", r_errors);
            $display("==================================================");
            $fatal(1, "RESULT: %0d ERROR(S)", r_errors);
        end
    end

    // --- Watchdog: abort simulation if it runs beyond 100 µs ---
    initial begin
        #100000;
        $display("[FAIL] Watchdog timeout");
        $fatal(1);
    end

    // --- VCD Dump for waveform viewing ---
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, apb_slave_tb);
    end

endmodule

`default_nettype wire
