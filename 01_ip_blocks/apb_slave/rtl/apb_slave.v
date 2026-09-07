/*******************************************************************************
 * Module: apb_slave.v                                                         *
 * Protocol:    ARM AMBA APB4 (IHI0024)
 * Description: Zero-wait-state slave. Contains 7 R/W registers (0x00–0x18)
 *              and 1 read-only STATUS register (0x1C).
 *              Supports byte-lane writes via PSTRB.
 * File Created: Thursday, 27th August 2026 11:01:52 am                        *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Thursday, 27th August 2026 4:02:00 pm                        *
 * Modified By: Long Hai                                                       *
*******************************************************************************/

`timescale 1ns/1ps
`default_nettype none

module apb_slave #(
    parameter [31:0] RESET_VALUE = 32'h0000_0000  // Reset value for all R/W registers
) (
    // --- APB Bus Signals ---
    input  wire        pclk,      // APB clock
    input  wire        presetn,   // Active-low asynchronous reset
    input  wire        psel,      // Slave select (Setup phase: PSEL=1, PENABLE=0)
    input  wire        penable,   // Access phase qualifier (PENABLE=1 = active transfer)
    input  wire        pwrite,    // 1 = write, 0 = read
    input  wire [7:0]  paddr,     // Byte address (valid range: 0x00–0x1C, 4-byte aligned)
    input  wire [31:0] pwdata,    // Write data
    input  wire [3:0]  pstrb,     // Write byte enables: pstrb[n]=1 → write byte lane n
    output reg  [31:0] prdata,    // Read data (combinational — valid during Access phase)
    output wire        pready,    // Always 1: no wait states inserted
    output wire        pslverr,   // 1 = address error (out-of-range or misaligned)

    // --- Application Interface ---
    input  wire [31:0] i_status,  // Live read-only status (wired directly to 0x1C)
    output wire [31:0] o_reg0,    // REG0 current value (0x00)
    output wire [31:0] o_reg1,    // REG1 current value (0x04)
    output wire [31:0] o_reg2,    // REG2 current value (0x08)
    output wire [31:0] o_reg3,    // REG3 current value (0x0C)
    output wire [31:0] o_reg4,    // REG4 current value (0x10)
    output wire [31:0] o_reg5,    // REG5 current value (0x14)
    output wire [31:0] o_reg6     // REG6 current value (0x18)
);

    // --- Register Address Map ---
    localparam [7:0] ADDR_REG0   = 8'h00;
    localparam [7:0] ADDR_REG1   = 8'h04;
    localparam [7:0] ADDR_REG2   = 8'h08;
    localparam [7:0] ADDR_REG3   = 8'h0C;
    localparam [7:0] ADDR_REG4   = 8'h10;
    localparam [7:0] ADDR_REG5   = 8'h14;
    localparam [7:0] ADDR_REG6   = 8'h18;
    localparam [7:0] ADDR_STATUS = 8'h1C;  // Read-only, reflects i_status

    // --- Internal Storage ---
    reg [31:0] r_regs [0:6];  // 7 x 32-bit R/W register bank
    integer r_index;           // Loop variable for reset
    integer r_byte;            // Loop variable for byte-lane write

    // --- Transfer Decode ---
    // w_access: true during Access phase (PSEL=1, PENABLE=1)
    wire w_access = psel & penable;

    // w_addr_valid: address must be in range 0x00–0x1F and 4-byte aligned
    //   paddr[7:5] == 0  → address within 0x00–0x1F
    //   paddr[1:0] == 0  → 4-byte aligned (no misalignment)
    wire w_addr_valid = (paddr[7:5] == 3'b000) && (paddr[1:0] == 2'b00);

    // w_write: actual register write condition
    //   paddr[4:2] < 7 excludes STATUS (0x1C → index 7) from write path
    wire w_write = w_access & pwrite & w_addr_valid & (paddr[4:2] < 3'd7);

    // --- APB Response ---
    assign pready  = 1'b1;                   // Always ready (zero wait state)
    assign pslverr = w_access & ~w_addr_valid; // Error when address is invalid

    // --- Register Outputs (wired directly from storage) ---
    assign o_reg0 = r_regs[0];
    assign o_reg1 = r_regs[1];
    assign o_reg2 = r_regs[2];
    assign o_reg3 = r_regs[3];
    assign o_reg4 = r_regs[4];
    assign o_reg5 = r_regs[5];
    assign o_reg6 = r_regs[6];

    // --- Write Logic (Sequential) ---
    // On reset: all 7 registers load RESET_VALUE.
    // On write: only byte lanes where pstrb[n]=1 are updated.
    //   paddr[4:2] selects the register index (0x00→0, 0x04→1, ..., 0x18→6).
    //   [r_byte*8 +: 8] selects 8 bits starting at bit r_byte*8 (indexed part-select).
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            for (r_index = 0; r_index < 7; r_index = r_index + 1)
                r_regs[r_index] <= RESET_VALUE;
        end else if (w_write) begin
            for (r_byte = 0; r_byte < 4; r_byte = r_byte + 1) begin
                if (pstrb[r_byte])  // Only write if this byte lane is enabled
                    r_regs[paddr[4:2]][r_byte*8 +: 8] <= pwdata[r_byte*8 +: 8];
            end
        end
    end

    // --- Read Logic (Combinational) ---
    // PRDATA must be valid in the same Access phase cycle (APB4 requirement).
    // Reads outside the valid address range return 0 (PSLVERR is also asserted).
    // STATUS (0x1C) is wired live to i_status — writes to it are silently ignored.
    always @(*) begin
        prdata = 32'd0;  // Default: return 0
        if (w_access && !pwrite && w_addr_valid) begin
            case (paddr)
                ADDR_REG0:   prdata = r_regs[0];
                ADDR_REG1:   prdata = r_regs[1];
                ADDR_REG2:   prdata = r_regs[2];
                ADDR_REG3:   prdata = r_regs[3];
                ADDR_REG4:   prdata = r_regs[4];
                ADDR_REG5:   prdata = r_regs[5];
                ADDR_REG6:   prdata = r_regs[6];
                ADDR_STATUS: prdata = i_status;  // Live value, not stored in FF
                default:     prdata = 32'd0;
            endcase
        end
    end

endmodule

`default_nettype wire
