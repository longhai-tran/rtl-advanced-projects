/*******************************************************************************
 * Module: i2c_master_core_tb.v                                                *
 * Description:                                                                *
 * Description: Self-checking testbench for i2c_master_apb IP block.
 *              Verifies both APB register interface (Level 1) and
 *              I2C bus-level protocol transactions with an inline Slave Model (Level 2).
 * File Created: Monday, 24th August 2026 5:12:45 pm                           *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Thursday, 27th August 2026 10:23:41 am                       *
 * Modified By: Long Hai                                                       *
*******************************************************************************/

`timescale 1ns/1ps
`default_nettype none

module i2c_master_core_tb;

    //=========================================================================
    // 1. APB Register Address Map (Byte Offset)
    //=========================================================================
    localparam [7:0] ADDR_CTRL   = 8'h00; // [31:16]=CLK_DIV, [1]=RW, [0]=START
    localparam [7:0] ADDR_ADDR   = 8'h04; // [6:0]=TARGET_ADDR
    localparam [7:0] ADDR_TXDATA = 8'h08; // [7:0]=TX_DATA (for write ops)
    localparam [7:0] ADDR_RXDATA = 8'h0C; // [7:0]=RX_DATA (read-only)
    localparam [7:0] ADDR_STATUS = 8'h10; // [3]=ACK_ERR, [2]=DONE, [1]=BUSY, [0]=SDA_IN

    //=========================================================================
    // 2. APB Bus Interface Signals
    //=========================================================================
    reg         r_pclk;
    reg         r_presetn;
    reg         r_psel;
    reg         r_penable;
    reg         r_pwrite;
    reg  [7:0]  r_paddr;
    reg  [31:0] r_pwdata;
    wire [31:0] w_prdata;
    wire        w_pready;

    //=========================================================================
    // 3. I2C Open-Drain Bus Modeling
    //    - Both Master and Slave pull the line LOW actively (drive 1'b0).
    //    - When neither drives LOW, the line floats (1'bz), and external
    //      pull-up (tri1) pulls the bus HIGH (1'b1).
    //=========================================================================
    wire w_scl_drive_low;       // Driven by Master: 1 = pull SCL LOW
    wire w_sda_drive_low;       // Driven by Master: 1 = pull SDA LOW
    wire w_scl_bus = ~w_scl_drive_low; // SCL is driven only by Master (no clock stretching)

    tri1 w_sda_bus;             // Shared bidirectional SDA with pull-up resistor
    reg  r_slave_sda_low;       // Driven by Slave model: 1 = pull SDA LOW

    // Wired-AND open-drain resolution
    assign w_sda_bus = w_sda_drive_low ? 1'b0 : 1'bz; // Master drive
    assign w_sda_bus = r_slave_sda_low  ? 1'b0 : 1'bz; // Slave drive

    //=========================================================================
    // 4. Device Under Test (DUT) Instantiation
    //=========================================================================
    i2c_master_apb #(.CLK_DIV(4)) dut (
        .pclk          (r_pclk),
        .presetn       (r_presetn),
        .psel          (r_psel),
        .penable       (r_penable),
        .pwrite        (r_pwrite),
        .paddr         (r_paddr),
        .pwdata        (r_pwdata),
        .prdata        (w_prdata),
        .pready        (w_pready),
        .scl_drive_low (w_scl_drive_low),
        .sda_drive_low (w_sda_drive_low),
        .i_sda         (w_sda_bus)
    );

    // 100 MHz APB Clock (Period = 10 ns)
    initial r_pclk = 1'b0;
    always #5 r_pclk = ~r_pclk;

    //=========================================================================
    // 5. Testbench Variables & Metrics Tracking
    //=========================================================================
    integer r_error_count;         // Total failed assertions
    integer r_test_number;         // Current running test case ID
    integer r_completed_trans_count;          // Number of I2C STOP conditions detected on bus
    integer r_t_start;             // Timestamp when START condition is detected
    reg [31:0] r_read_data;        // Buffer for APB readback data
    reg [7:0]  r_slave_address_frame; // 8-bit frame received by Slave: {ADDR[6:0], RW}
    reg [7:0]  r_slave_write_data;    // Data byte received by Slave in write ops

    // Monitor STOP conditions on the bus: SDA rising while SCL is HIGH
    always @(posedge w_sda_bus) begin
        if (w_scl_bus && r_presetn)
            r_completed_trans_count = r_completed_trans_count + 1;
    end

    //=========================================================================
    // 6. APB Bus Functional Model (BFM) Tasks
    //=========================================================================

    //-------------------------------------------------------------------------
    // Task: apb_write
    // Description: Performs a 2-cycle APB Write transfer.
    //              Drives inputs on negedge pclk to provide clean setup/hold
    //              times and avoid race conditions with DUT at posedge pclk.
    //-------------------------------------------------------------------------
    task apb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            // Cycle 1: SETUP Phase (PSEL=1, PENABLE=0)
            @(negedge r_pclk);
            r_psel    = 1'b1;
            r_penable = 1'b0;
            r_pwrite  = 1'b1;
            r_paddr   = addr;
            r_pwdata  = data;

            // Cycle 2: ACCESS Phase (PSEL=1, PENABLE=1 -> DUT samples at posedge)
            @(negedge r_pclk);
            r_penable = 1'b1;

            // Cycle 3: IDLE (Return bus to quiescent state)
            @(negedge r_pclk);
            r_psel    = 1'b0;
            r_penable = 1'b0;
            r_pwrite  = 1'b0;
            r_paddr   = 8'h00;
            r_pwdata  = 32'h0000_0000;
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: apb_read
    // Description: Performs a 2-cycle APB Read transfer and captures prdata.
    //-------------------------------------------------------------------------
    task apb_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            // Cycle 1: SETUP Phase
            @(negedge r_pclk);
            r_psel    = 1'b1;
            r_penable = 1'b0;
            r_pwrite  = 1'b0;
            r_paddr   = addr;

            // Cycle 2: ACCESS Phase (DUT drives prdata)
            @(negedge r_pclk);
            r_penable = 1'b1;
            #1 data = w_prdata; // Capture read data slightly after posedge/negedge

            // Cycle 3: IDLE
            @(negedge r_pclk);
            r_psel    = 1'b0;
            r_penable = 1'b0;
            r_paddr   = 8'h00;
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: start_transfer
    // Description: Convenience task to write CTRL register and trigger I2C start.
    //              pwdata format: [31:16]=clk_div, [1]=rw, [0]=START(1'b1)
    //-------------------------------------------------------------------------
    task start_transfer;
        input        rw;
        input [15:0] clk_div;
        begin
            apb_write(ADDR_CTRL, {clk_div, 14'd0, rw, 1'b1});
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: wait_done
    // Description: Polls STATUS[2] (DONE bit) until asserted or timeout reached.
    // Timing calculation:
    //   - 1 I2C transfer takes ~160 PCLK cycles (19-20 SCL @ CLK_DIV=4).
    //   - In a loop, each apb_read takes 3 PCLK cycles (1 idle + 1 setup + 1 access).
    //   - MAX_POLL_TIMEOUT = 80 (~240 PCLK cycles) provides safety timeout to prevent hangs.
    //-------------------------------------------------------------------------
    localparam integer MAX_POLL_TIMEOUT = 80;

    task wait_done;
        integer poll_count;
        begin : poll_loop
            for (poll_count = 0; poll_count < MAX_POLL_TIMEOUT; poll_count = poll_count + 1) begin
                apb_read(ADDR_STATUS, r_read_data);
                if (r_read_data[2]) begin     // STATUS.DONE sticky bit is set
                    disable poll_loop;
                end
            end
            if (!r_read_data[2]) begin
                $display("[ERR] T%0d: STATUS.DONE did not assert within timeout (%0d polls)",
                         r_test_number, MAX_POLL_TIMEOUT);
                r_error_count = r_error_count + 1;
            end
        end
    endtask

    //=========================================================================
    // 7. I2C Slave Behavioral Model Tasks
    //=========================================================================

    //-------------------------------------------------------------------------
    // Task: receive_i2c_byte
    // Description: Samples 8 consecutive bits from SDA on posedge SCL (MSB-first).
    //-------------------------------------------------------------------------
    task receive_i2c_byte;
        output [7:0] data;
        integer bit_index;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                @(posedge w_scl_bus);
                data[bit_index] = w_sda_bus;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: drive_ack
    // Description: Drives ACK (SDA=0) or NACK (SDA=1/Z) during the 9th SCL clock.
    //              SDA is driven on negedge SCL so it is stable at posedge SCL.
    //-------------------------------------------------------------------------
    task drive_ack;
        input ack; // 1 = Send ACK (pull LOW), 0 = Send NACK (release line)
        begin
            @(negedge w_scl_bus);
            r_slave_sda_low = ack; // Pull SDA LOW if ack=1
            @(posedge w_scl_bus);  // Master samples ACK here
            @(negedge w_scl_bus);
            r_slave_sda_low = 1'b0; // Release SDA after ACK bit
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: wait_start
    // Description: Detects I2C START condition (SDA falls while SCL is HIGH).
    //-------------------------------------------------------------------------
    task wait_start;
        begin
            @(negedge w_sda_bus); // SDA transitions 1 -> 0
            r_t_start = $time;    // Record transaction start timestamp
            if (!w_scl_bus) begin
                $display("[ERR] T%0d: Invalid START: SDA fell while SCL was LOW", r_test_number);
                r_error_count = r_error_count + 1;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: wait_stop
    // Description: Detects I2C STOP condition (SDA rises while SCL is HIGH).
    //-------------------------------------------------------------------------
    task wait_stop;
        begin
            @(posedge w_sda_bus); // SDA transitions 0 -> 1
            $display("[TIME] T%0d: transaction = %0d ns", r_test_number, $time - r_t_start);
            if (!w_scl_bus) begin
                $display("[ERR] T%0d: Invalid STOP: SDA rose while SCL was LOW", r_test_number);
                r_error_count = r_error_count + 1;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: slave_write_transaction
    // Description: Emulates full Slave response during a Master WRITE transaction:
    //              1. Wait for START condition
    //              2. Receive 8-bit Address Frame -> Send address ACK/NACK
    //              3. If address ACKed: Receive 8-bit Data -> Send data ACK/NACK
    //              4. Wait for STOP condition
    //-------------------------------------------------------------------------
    task slave_write_transaction;
        input address_ack; // 1 = ACK address, 0 = NACK address
        input data_ack;    // 1 = ACK data byte, 0 = NACK data byte
        begin
            wait_start;
            receive_i2c_byte(r_slave_address_frame);
            drive_ack(address_ack);
            if (address_ack) begin
                receive_i2c_byte(r_slave_write_data);
                drive_ack(data_ack);
            end
            wait_stop;
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: slave_read_transaction
    // Description: Emulates full Slave response during a Master READ transaction:
    //              1. Wait for START condition
    //              2. Receive 8-bit Address Frame -> Send address ACK
    //              3. Drive 8 bits of read_data to Master (MSB first)
    //              4. Check that Master replies with NACK (SDA=1)
    //              5. Wait for STOP condition
    //-------------------------------------------------------------------------
    task slave_read_transaction;
        input [7:0] read_data; // Byte that Slave will send to Master
        integer bit_index;
        begin
            wait_start;
            receive_i2c_byte(r_slave_address_frame);
            drive_ack(1'b1); // Always ACK matching address

            // Transmit 8 bits onto SDA
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                r_slave_sda_low = ~read_data[bit_index]; // Drive LOW if bit is 0
                @(posedge w_scl_bus);
                if (bit_index != 0)
                    @(negedge w_scl_bus);
            end
            @(negedge w_scl_bus);
            r_slave_sda_low = 1'b0; // Release SDA so Master can send NACK

            // 9th clock cycle: Master must send NACK on the last read byte
            @(posedge w_scl_bus);
            if (w_sda_bus !== 1'b1) begin
                $display("[ERR] T%0d: Master did not send NACK for final read byte", r_test_number);
                r_error_count = r_error_count + 1;
            end
            wait_stop;
        end
    endtask

    //=========================================================================
    // 8. Self-Checking Scoreboard & Helper Tasks
    //=========================================================================
    task expect_equal;
        input [31:0] actual;
        input [31:0] expected;
        input [8*80-1:0] label;
        begin
            if (actual !== expected) begin
                $display("[ERR] T%0d: %0s expected=%08h actual=%08h",
                         r_test_number, label, expected, actual);
                r_error_count = r_error_count + 1;
            end else begin
                $display("[PASS] T%0d: %0s", r_test_number, label);
            end
        end
    endtask

    task reset_dut;
        begin
            r_presetn       = 1'b0; // Assert active-low reset
            r_psel          = 1'b0;
            r_penable       = 1'b0;
            r_pwrite        = 1'b0;
            r_paddr         = 8'h00;
            r_pwdata        = 32'h0000_0000;
            r_slave_sda_low = 1'b0;
            repeat (4) @(posedge r_pclk);
            @(negedge r_pclk);
            r_presetn = 1'b1;       // De-assert reset
        end
    endtask

    //=========================================================================
    // 9. Main Test Execution Flow (Test Cases T1 - T6)
    //=========================================================================
    initial begin
        r_error_count = 0;
        r_test_number = 0;
        r_completed_trans_count  = 0;
        reset_dut;

        //---------------------------------------------------------------------
        // TC1: APB Register R/W and Reset Values
        // Tests default register values, readback verification, and unmapped address.
        //---------------------------------------------------------------------
        r_test_number = 1;
        $display("-- T1: APB reset values and register access | time=%0t --", $time);
        apb_read(ADDR_CTRL, r_read_data);
        expect_equal(r_read_data, 32'h0004_0000, "CTRL reset value");   // CLK_DIV=4, RW=0, START=0
        apb_write(ADDR_ADDR, 32'h0000_0050);                            // Set target address to 0x50
        apb_read(ADDR_ADDR, r_read_data);
        expect_equal(r_read_data, 32'h0000_0050, "ADDR readback");
        apb_write(ADDR_TXDATA, 32'h0000_00A5);                          // Set TXDATA to 0xA5
        apb_read(ADDR_TXDATA, r_read_data);
        expect_equal(r_read_data, 32'h0000_00A5, "TXDATA readback");
        apb_read(8'hFC, r_read_data);                                   // Read unmapped address
        expect_equal(r_read_data, 32'h0000_0000, "unmapped read");

        //---------------------------------------------------------------------
        // TC2: Bus-level Write with Address ACK and Data ACK
        // Flow: ADDR=0x50, TXDATA=0x3C, Write op (RW=0)
        // Expected Address Frame: {7'h50, 1'b0} = 8'hA0
        // Expected Data: 8'h3C, STATUS: DONE=1, ACK_ERR=0
        //---------------------------------------------------------------------
        r_test_number = 2;
        $display("-- T2: bus-level write with address and data ACK | time=%0t --", $time);
        apb_write(ADDR_ADDR, 32'h0000_0050);
        apb_write(ADDR_TXDATA, 32'h0000_003C);
        fork
            slave_write_transaction(1'b1, 1'b1); // Slave: ACK addr, ACK data
            start_transfer(1'b0, 16'd4);         // Master: RW=0 (Write), CLK_DIV=4
        join
        wait_done;
        expect_equal({24'd0, r_slave_address_frame}, 32'h0000_00A0,
                     "write address frame (7'h50 + RW=0 -> 8'hA0)");
        expect_equal({24'd0, r_slave_write_data}, 32'h0000_003C,
                     "write data byte (8'h3C)");
        apb_read(ADDR_STATUS, r_read_data);
        expect_equal({30'd0, r_read_data[3], r_read_data[2]}, 32'h0000_0001,
                     "write DONE=1 ACK_ERR=0");

        //---------------------------------------------------------------------
        // TC3: Bus-level Read with Address ACK and Master NACK
        // Flow: ADDR=0x50, Read op (RW=1), Slave transmits 8'hD6
        // Expected Address Frame: {7'h50, 1'b1} = 8'hA1
        // Expected RXDATA: 8'hD6
        //---------------------------------------------------------------------
        r_test_number = 3;
        $display("-- T3: bus-level read and master NACK | time=%0t --", $time);
        fork
            slave_read_transaction(8'hD6);       // Slave: Send 0xD6 on bus
            start_transfer(1'b1, 16'd3);         // Master: RW=1 (Read), CLK_DIV=3
        join
        wait_done;
        expect_equal({24'd0, r_slave_address_frame}, 32'h0000_00A1,
                     "read address frame (7'h50 + RW=1 -> 8'hA1)");
        apb_read(ADDR_RXDATA, r_read_data);
        expect_equal(r_read_data, 32'h0000_00D6, "RXDATA value (8'hD6)");

        //---------------------------------------------------------------------
        // TC4: Address NACK (Target device does not respond / address mismatch)
        // Flow: Slave returns NACK on address. Master must abort data phase,
        //       assert ACK_ERR flag, and issue a valid STOP condition.
        //---------------------------------------------------------------------
        r_test_number = 4;
        $display("-- T4: address NACK aborts with STOP | time=%0t --", $time);
        fork
            slave_write_transaction(1'b0, 1'b0); // Slave: NACK address
            start_transfer(1'b0, 16'd2);         // Master: RW=0 (Write), CLK_DIV=2
        join
        wait_done;
        apb_read(ADDR_STATUS, r_read_data);
        expect_equal({30'd0, r_read_data[3], r_read_data[2]}, 32'h0000_0003,
                     "address NACK status (DONE=1, ACK_ERR=1)");

        //---------------------------------------------------------------------
        // TC5: Data NACK (Target ACKs address but NACKs data byte)
        // Flow: Master must set ACK_ERR flag and issue STOP condition.
        //---------------------------------------------------------------------
        r_test_number = 5;
        $display("-- T5: data NACK sets ACK_ERR | time=%0t --", $time);
        fork
            slave_write_transaction(1'b1, 1'b0); // Slave: ACK addr, NACK data
            start_transfer(1'b0, 16'd4);         // Master: RW=0 (Write), CLK_DIV=4
        join
        wait_done;
        apb_read(ADDR_STATUS, r_read_data);
        expect_equal({30'd0, r_read_data[3], r_read_data[2]}, 32'h0000_0003,
                     "data NACK status (DONE=1, ACK_ERR=1)");

        //---------------------------------------------------------------------
        // TC6: Asynchronous Reset during Active Transfer
        // Flow: Trigger a transfer, wait until bus is actively driven (SCL=0),
        //       then assert presetn=0. Master must immediately release SCL and SDA
        //       (bus lines float back to 1 via pull-up) and clear internal status.
        //---------------------------------------------------------------------
        r_test_number = 6;
        $display("-- T6: reset during an active transfer releases the bus | time=%0t --", $time);
        start_transfer(1'b0, 16'd4);
        apb_read(ADDR_STATUS, r_read_data);
        expect_equal({30'd0, r_read_data[2], r_read_data[1]}, 32'h0000_0001,
                     "BUSY=1 and previous DONE cleared");
        wait (w_scl_bus == 1'b0); // Wait until Master pulls SCL LOW (active transfer)
        r_presetn = 1'b0;         // Assert asynchronous reset mid-transfer
        #1;
        expect_equal({30'd0, w_scl_bus, w_sda_bus}, 32'h0000_0003,
                     "bus released by reset (SCL=1, SDA=1 via pull-ups)");
        repeat (3) @(posedge r_pclk);
        @(negedge r_pclk);
        r_presetn = 1'b1;         // De-assert reset
        apb_read(ADDR_STATUS, r_read_data);
        expect_equal({29'd0, r_read_data[3:1]}, 32'h0000_0000,
                     "status cleared by reset (BUSY=0, DONE=0, ACK_ERR=0)");

        //---------------------------------------------------------------------
        // Testbench Summary & Exit Status
        //---------------------------------------------------------------------
        $display("==================================================");
        $display("           SIMULATION SUMMARY REPORT              ");
        $display("==================================================");
        $display("  Total Test Cases       : %0d", r_test_number);
        $display("  Valid I2C Transactions : %0d (STOP conditions)", r_completed_trans_count);
        $display("  Assertion Errors       : %0d", r_error_count);
        $display("==================================================");
        if (r_error_count == 0) begin
            $display("  FINAL RESULT: ALL TESTS PASSED");
            $display("==================================================");
            $finish;
        end else begin
            $display("  FINAL RESULT: TEST FAILED (%0d error(s))", r_error_count);
            $display("==================================================");
            $fatal(1, "RESULT: %0d ERROR(S)", r_error_count);
        end
    end

    // Global simulation watchdog (prevents infinite simulator hangs)
    initial begin
        #200_000;
        $fatal(1, "[TIMEOUT] Simulation exceeded 200 us watchdog limit");
    end

endmodule

`default_nettype wire
