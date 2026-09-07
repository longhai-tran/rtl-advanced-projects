/*******************************************************************************
 * Module: i2c_master_core.v                                                   *
 * Description: One-byte, 7-bit-address I2C controller with ACK/NACK handling. *
 * File Created: Friday, 31st July 2026 10:28:03 am                            *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Tuesday, 4th August 2026 11:36:31 am                         *
 * Modified By: Long Hai                                                       *
 *******************************************************************************/

/*
 * I2C Master Controller - Design Notes
 * ======================================
 * Protocol overview (single-byte transfer):
 *
 *  SDA ──┐  ┌──── A6 A5 A4 A3 A2 A1 A0 R/W ── ACK ── D7..D0 ── ACK ──┐  ┌──
 *        └──┘ START                                                  └──┘ STOP
 *  SCL  ─────────┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ...........  ┌────────
 *                └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘
 *
 * Open-drain model:
 *   - Master drives SCL and SDA LOW by asserting scl_drive_low / sda_drive_low.
 *   - When drive signals are de-asserted, external pull-ups return lines HIGH.
 *   - The instantiating top-level resolves the wired-AND bus.
 *
 * Clock generation:
 *   - System clock is divided by (2 × HALF_PERIOD) to produce SCL.
 *   - half_tick pulses once per SCL half-period; each state step takes exactly
 *     one or two half-ticks depending on whether SCL needs to change.
 *
 * Supported states:
 *   IDLE → START → ADDRESS(8 bits) → ADDR_ACK → WRITE/READ(8 bits) →
 *   WRITE_ACK / READ_NACK → STOP_LOW → STOP_HIGH → STOP_FREE → IDLE
 */

`timescale 1ns/1ps
`default_nettype none

module i2c_master_core (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_start,
    input  wire        i_rw,
    input  wire [6:0]  i_target_addr,
    input  wire [7:0]  i_tx_data,
    input  wire [15:0] i_clk_div,
    input  wire        i_sda,

    output reg         o_scl_drive_low,
    output reg         o_sda_drive_low,
    output reg  [7:0]  o_rx_data,
    output reg         o_busy,
    output reg         o_done,
    output reg         o_ack_error
);

    // -------------------------------------------------------------------------
    // Clock divider constants
    // -------------------------------------------------------------------------
    localparam [15:0] LP_MIN_CLK_DIV = 16'd2;

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    // State names map directly to the I2C protocol phase they implement.
    localparam [3:0] ST_IDLE       = 4'd0;  // Bus free; waiting for start request
    localparam [3:0] ST_START      = 4'd1;  // SDA pulled LOW while SCL HIGH (START)
    localparam [3:0] ST_ADDRESS    = 4'd2;  // Clocking out 8-bit address frame (addr[6:0] + R/W)
    localparam [3:0] ST_ADDR_ACK   = 4'd3;  // Releasing SDA; sampling slave ACK bit
    localparam [3:0] ST_WRITE      = 4'd4;  // Clocking out 8-bit data byte (write)
    localparam [3:0] ST_WRITE_ACK  = 4'd5;  // Releasing SDA; sampling slave ACK bit for data
    localparam [3:0] ST_READ       = 4'd6;  // Sampling 8 bits driven by the slave (read)
    localparam [3:0] ST_READ_NACK  = 4'd7;  // Master drives NACK (SDA HIGH) to stop read
    localparam [3:0] ST_STOP_LOW   = 4'd8;  // SCL released HIGH, SDA still LOW
    localparam [3:0] ST_STOP_HIGH  = 4'd9;  // SDA released HIGH while SCL HIGH (STOP)
    localparam [3:0] ST_STOP_FREE  = 4'd10; // Bus quiescent; assert done and return to IDLE

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    reg [3:0]  r_state;
    reg [15:0] r_div_count;
    reg [15:0] r_clk_div;
    reg        r_high_phase;
    reg        r_rw_latched;
    reg [7:0]  r_address_frame;
    reg [7:0]  r_tx_latched;
    // Bit 0 is merged from live SDA when o_rx_data is committed.
    // verilator lint_off UNUSEDSIGNAL
    reg [7:0]  r_rx_shift;
    // verilator lint_on UNUSEDSIGNAL
    reg [2:0]  r_bit_index;

    // half_tick: TRUE for exactly one clock cycle every SCL half-period.
    // All state transitions occur only on this tick to maintain precise I2C timing.
    wire w_half_tick = (r_div_count == (r_clk_div - 1'b1));

    // -------------------------------------------------------------------------
    // Main FSM - asynchronous reset, half-tick gated transitions
    // -------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // De-assert all drive signals so bus lines are pulled HIGH by pull-ups
            r_state           <= ST_IDLE;
            r_div_count       <= 16'd0;
            r_clk_div         <= LP_MIN_CLK_DIV;
            r_high_phase      <= 1'b0;
            r_rw_latched      <= 1'b0;
            r_address_frame   <= 8'h00;
            r_tx_latched      <= 8'h00;
            r_rx_shift        <= 8'h00;
            r_bit_index       <= 3'd7;
            o_scl_drive_low   <= 1'b0;
            o_sda_drive_low   <= 1'b0;
            o_rx_data         <= 8'h00;
            o_busy            <= 1'b0;
            o_done            <= 1'b0;
            o_ack_error       <= 1'b0;
        end else begin
            // done is a single-cycle pulse; de-assert by default every cycle
            o_done <= 1'b0;

            if (r_state == ST_IDLE) begin
                // ── IDLE ────────────────────────────────────────────────────
                // Keep both bus lines released and wait for a start request.
                o_scl_drive_low <= 1'b0;
                o_sda_drive_low <= 1'b0;
                o_busy          <= 1'b0;
                r_div_count     <= 16'd0;
                r_high_phase    <= 1'b0;

                if (i_start) begin
                    // Latch all inputs so they cannot change mid-transfer
                    r_address_frame <= {i_target_addr, i_rw};
                    r_tx_latched    <= i_tx_data;
                    r_rw_latched    <= i_rw;
                    r_clk_div       <= (i_clk_div < LP_MIN_CLK_DIV) ?
                                       LP_MIN_CLK_DIV : i_clk_div;
                    r_rx_shift      <= 8'h00;
                    r_bit_index     <= 3'd7;
                    o_ack_error     <= 1'b0;
                    o_busy          <= 1'b1;
                    // Pull SDA LOW while SCL is HIGH — this IS the START condition.
                    // SCL will be pulled LOW on the next half_tick (ST_START handler).
                    o_sda_drive_low <= 1'b1;
                    r_state         <= ST_START;
                end
            end else if (w_half_tick) begin
                // All non-idle state transitions happen here to maintain I2C timing
                r_div_count <= 16'd0;

                case (r_state)
                    // ── ST_START ────────────────────────────────────────────
                    // SDA is already LOW (set in IDLE→START transition).
                    // Now pull SCL LOW to begin the first address bit.
                    ST_START: begin
                        o_scl_drive_low <= 1'b1;
                        o_sda_drive_low <= ~r_address_frame[7];
                        r_high_phase    <= 1'b0;
                        r_state         <= ST_ADDRESS;
                    end

                    // ── ST_ADDRESS ──────────────────────────────────────────
                    // Clock out the 8-bit address frame (bits [7:0], MSB first).
                    // Uses high_phase toggle: low half → release SCL, high half → pull SCL LOW.
                    // SDA is updated on the falling edge (low-half entry) so it is stable
                    // during the subsequent SCL high phase (I2C setup/hold requirement).
                    ST_ADDRESS: begin
                        if (!r_high_phase) begin
                            // Rising edge of SCL: release line and let pull-up raise it
                            o_scl_drive_low <= 1'b0;
                            r_high_phase    <= 1'b1;
                        end else begin
                            // Falling edge of SCL: pull it low again
                            o_scl_drive_low <= 1'b1;
                            r_high_phase    <= 1'b0;
                            if (r_bit_index == 0) begin
                                // Last bit just clocked; release SDA for ACK phase
                                o_sda_drive_low <= 1'b0;
                                r_state         <= ST_ADDR_ACK;
                            end else begin
                                // Advance to next bit and pre-drive SDA
                                r_bit_index     <= r_bit_index - 1'b1;
                                o_sda_drive_low <= ~r_address_frame[r_bit_index - 1'b1];
                            end
                        end
                    end

                    // ── ST_ADDR_ACK ─────────────────────────────────────────
                    // Release SDA and generate one SCL cycle; sample sda on the
                    // falling edge (high_phase == 1) to read the slave ACK/NACK.
                    // ACK  = slave pulls SDA LOW  → sda == 0
                    // NACK = SDA remains HIGH    → sda == 1  (ack_error)
                    ST_ADDR_ACK: begin
                        if (!r_high_phase) begin
                            o_scl_drive_low <= 1'b0;
                            r_high_phase    <= 1'b1;
                        end else begin
                            o_scl_drive_low <= 1'b1;
                            r_high_phase    <= 1'b0;
                            if (i_sda) begin
                                // NACK received — abort and issue STOP
                                o_ack_error     <= 1'b1;
                                o_sda_drive_low <= 1'b1;
                                r_state         <= ST_STOP_LOW;
                            end else if (r_rw_latched) begin
                                // ACK received, read transfer → release SDA for slave to drive
                                r_bit_index     <= 3'd7;
                                o_sda_drive_low <= 1'b0;
                                r_state         <= ST_READ;
                            end else begin
                                // ACK received, write transfer → pre-drive MSB of data byte
                                r_bit_index     <= 3'd7;
                                o_sda_drive_low <= ~r_tx_latched[7];
                                r_state         <= ST_WRITE;
                            end
                        end
                    end

                    // ── ST_WRITE ────────────────────────────────────────────
                    // Clock out the 8-bit TX byte MSB-first, same half_phase
                    // toggle rhythm as ST_ADDRESS.
                    ST_WRITE: begin
                        if (!r_high_phase) begin
                            o_scl_drive_low <= 1'b0;
                            r_high_phase    <= 1'b1;
                        end else begin
                            o_scl_drive_low <= 1'b1;
                            r_high_phase    <= 1'b0;
                            if (r_bit_index == 0) begin
                                // Last data bit sent; release SDA for slave ACK
                                o_sda_drive_low <= 1'b0;
                                r_state         <= ST_WRITE_ACK;
                            end else begin
                                r_bit_index     <= r_bit_index - 1'b1;
                                o_sda_drive_low <= ~r_tx_latched[r_bit_index - 1'b1];
                            end
                        end
                    end

                    // ── ST_WRITE_ACK ────────────────────────────────────────
                    // Sample slave's data-byte ACK and then proceed to STOP.
                    // ack_error is set but the STOP sequence is still issued to
                    // leave the bus in a defined idle state even on failure.
                    ST_WRITE_ACK: begin
                        if (!r_high_phase) begin
                            o_scl_drive_low <= 1'b0;
                            r_high_phase    <= 1'b1;
                        end else begin
                            o_scl_drive_low <= 1'b1;
                            r_high_phase    <= 1'b0;
                            if (i_sda)
                                o_ack_error <= 1'b1;
                            // SDA LOW needed to generate valid STOP (SDA: LOW→HIGH while SCL HIGH)
                            o_sda_drive_low <= 1'b1;
                            r_state         <= ST_STOP_LOW;
                        end
                    end

                    // ── ST_READ ─────────────────────────────────────────────
                    // Master releases SDA; slave drives each bit.
                    // Bits are sampled on the falling edge of SCL (high_phase == 1)
                    // and accumulated in rx_shift, MSB first.
                    // Last bit is merged directly to avoid a stale rx_shift[0].
                    ST_READ: begin
                        if (!r_high_phase) begin
                            o_scl_drive_low <= 1'b0;
                            r_high_phase    <= 1'b1;
                        end else begin
                            o_scl_drive_low          <= 1'b1;
                            r_high_phase             <= 1'b0;
                            r_rx_shift[r_bit_index]  <= i_sda;
                            if (r_bit_index == 0) begin
                                // Assemble final byte; use live sda for bit[0] to avoid
                                // a one-cycle delay from the rx_shift assignment above.
                                o_rx_data       <= {r_rx_shift[7:1], i_sda};
                                r_bit_index     <= 3'd7;
                                // Keep SDA released (HIGH) to send NACK to slave,
                                // signalling that the master will not read another byte.
                                o_sda_drive_low <= 1'b0;
                                r_state         <= ST_READ_NACK;
                            end else begin
                                r_bit_index <= r_bit_index - 1'b1;
                            end
                        end
                    end

                    // ── ST_READ_NACK ────────────────────────────────────────
                    // Generate one SCL cycle with SDA HIGH (NACK) to tell the
                    // slave that this is the final byte of the read.
                    ST_READ_NACK: begin
                        if (!r_high_phase) begin
                            o_scl_drive_low <= 1'b0;
                            r_high_phase    <= 1'b1;
                        end else begin
                            o_scl_drive_low <= 1'b1;
                            r_high_phase    <= 1'b0;
                            // SDA LOW here so STOP can be generated (LOW→HIGH with SCL HIGH)
                            o_sda_drive_low <= 1'b1;
                            r_state         <= ST_STOP_LOW;
                        end
                    end

                    // ── STOP sequence (3 steps) ─────────────────────────────
                    // I2C STOP = SDA goes LOW→HIGH while SCL is HIGH.
                    // Step 1: raise SCL first (SDA still LOW).
                    // Step 2: raise SDA while SCL is HIGH → this is the STOP event.
                    // Step 3: hold both HIGH for one half-period (bus free), then signal done.
                    ST_STOP_LOW: begin
                        o_scl_drive_low <= 1'b0;
                        o_sda_drive_low <= 1'b1;
                        r_state         <= ST_STOP_HIGH;
                    end

                    ST_STOP_HIGH: begin
                        o_scl_drive_low <= 1'b0;
                        o_sda_drive_low <= 1'b0;
                        r_state         <= ST_STOP_FREE;
                    end

                    ST_STOP_FREE: begin
                        o_busy  <= 1'b0;
                        o_done  <= 1'b1;
                        r_state <= ST_IDLE;
                    end

                    // ── Default (unreachable in normal operation) ────────────
                    // Safety net: force bus lines to safe idle state
                    default: begin
                        r_state         <= ST_IDLE;
                        o_scl_drive_low <= 1'b0;
                        o_sda_drive_low <= 1'b0;
                        o_busy          <= 1'b0;
                    end
                endcase
            end else begin
                // Normal clock cycle — just advance the divider counter
                r_div_count <= r_div_count + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
