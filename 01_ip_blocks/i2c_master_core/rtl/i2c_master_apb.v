/*******************************************************************************
 * Module: i2c_master_apb.v                                                    *
 * Description:                                                                *
 * File Created: Saturday, 22nd August 2026 9:51:01 am                         *
 * Author: Long Hai                                                            *
 * -----                                                                       *
 * Last Modified: Thursday, 27th August 2026 3:20:30 pm                        *
 * Modified By: Long Hai                                                       *
*******************************************************************************/
//=============================================================================
// Description: APB slave wrapper for i2c_master_core.
//              Upgrade from rtl-design-practice/i2c_master.v:
//              Adds APB4 register interface so SoC software can control I2C.
//
// Register Map (APB word = 32-bit):
//   Offset 0x00 — CTRL   [31:16]=CLK_DIV_VAL [1]=RW  [0]=START (write-to-set)
//   Offset 0x04 — ADDR   [6:0]=TARGET_ADDR
//   Offset 0x08 — TXDATA [7:0]=TX_DATA
//   Offset 0x0C — RXDATA [7:0]=RX_DATA (read-only)
//   Offset 0x10 — STATUS [3]=ACK_ERR [2]=DONE [1]=BUSY [0]=SDA_IN
//
// APB Interface:
//   psel, penable, pwrite, paddr[7:0], pwdata[31:0], prdata[31:0], pready
//
// I2C signals passed through to top-level for open-drain connection:
//   scl_drive_low, sda_drive_low, i_sda
//=============================================================================
`timescale 1ns/1ps
`default_nettype none

module i2c_master_apb #(
    parameter integer CLK_DIV = 50   // default: 100kHz I2C on 10MHz sys clock
) (
    // APB slave interface
    input  wire        pclk,
    input  wire        presetn,      // Active-low reset
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,       // Always 1 (zero-wait-state slave)

    // I2C bus (open-drain)
    output wire        scl_drive_low,
    output wire        sda_drive_low,
    input  wire        i_sda          // Resolved SDA from top-level
);

    // APB is always ready (combinational slave)
    assign pready = 1'b1;

    //=========================================================================
    // Register Address Map (Byte Offset)
    //=========================================================================
    localparam [7:0] ADDR_CTRL   = 8'h00;
    localparam [7:0] ADDR_ADDR   = 8'h04;
    localparam [7:0] ADDR_TXDATA = 8'h08;
    localparam [7:0] ADDR_RXDATA = 8'h0C;
    localparam [7:0] ADDR_STATUS = 8'h10;

    //=========================================================================
    // Internal registers
    //=========================================================================
    // CTRL register
    reg [15:0] r_clk_div_val;
    reg        r_rw;            // 0=write, 1=read
    // ADDR register
    reg [6:0]  r_target_addr;
    // TXDATA register
    reg [7:0]  r_tx_data;

    // START pulse — set by software, cleared after one cycle
    reg r_start;
    reg r_start_d;
    wire w_start_request = r_start & ~r_start_d;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) r_start_d <= 1'b0;
        else          r_start_d <= r_start;
    end

    //=========================================================================
    // APB access phase. PREADY is always high, so each transfer completes here.
    //=========================================================================
    wire w_wr_en = psel & pwrite & penable;
    wire w_rd_en = psel & ~pwrite & penable;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_clk_div_val <= CLK_DIV[15:0];
            r_rw          <= 1'b0;
            r_start       <= 1'b0;
            r_target_addr <= 7'd0;
            r_tx_data     <= 8'd0;
        end else begin
            r_start <= 1'b0;   // auto-clear START each cycle
            if (w_wr_en) begin
                case (paddr)
                    ADDR_CTRL: begin
                        r_clk_div_val <= pwdata[31:16];
                        r_rw          <= pwdata[1];
                        r_start       <= pwdata[0];
                    end
                    ADDR_ADDR:   r_target_addr <= pwdata[6:0];
                    ADDR_TXDATA: r_tx_data     <= pwdata[7:0];
                    default: ;
                endcase
            end
        end
    end

    //=========================================================================
    // APB read
    //=========================================================================
    wire [7:0] w_rx_data;
    wire       w_busy;
    wire       w_done;
    wire       w_ack_error;
    wire       w_start_pulse = w_start_request & ~w_busy;
    reg        r_done_status;

    // DONE is sticky so software polling cannot miss the core's one-cycle pulse.
    // A new START request clears it.
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            r_done_status <= 1'b0;
        else if (w_start_pulse)
            r_done_status <= 1'b0;
        else if (w_done)
            r_done_status <= 1'b1;
    end

    always @(*) begin
        prdata = 32'd0;
        if (w_rd_en) begin
            case (paddr)
                ADDR_CTRL:   prdata = {r_clk_div_val, 14'd0, r_rw, 1'b0};
                ADDR_ADDR:   prdata = {25'd0, r_target_addr};
                ADDR_TXDATA: prdata = {24'd0, r_tx_data};
                ADDR_RXDATA: prdata = {24'd0, w_rx_data};
                ADDR_STATUS: prdata = {28'd0, w_ack_error, r_done_status,
                                       w_busy, i_sda};
                default:     prdata = 32'd0;
            endcase
        end
    end

    //=========================================================================
    // i2c_master_core instantiation
    //=========================================================================
    i2c_master_core u_i2c_core (
        .i_clk          (pclk),
        .i_rst_n        (presetn),
        .i_start        (w_start_pulse),
        .i_rw           (r_rw),
        .i_target_addr  (r_target_addr),
        .i_tx_data      (r_tx_data),
        .i_clk_div      (r_clk_div_val),
        .i_sda          (i_sda),
        .o_scl_drive_low(scl_drive_low),
        .o_sda_drive_low(sda_drive_low),
        .o_rx_data      (w_rx_data),
        .o_busy         (w_busy),
        .o_done         (w_done),
        .o_ack_error    (w_ack_error)
    );

endmodule

`default_nettype wire
