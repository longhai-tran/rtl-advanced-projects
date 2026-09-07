# i2c_master_core — I2C Master with APB Interface

![Language](https://img.shields.io/badge/Language-Verilog-blue.svg)
![Status](https://img.shields.io/badge/Status-Verified-success.svg)
![Protocol](https://img.shields.io/badge/Protocol-I%C2%B2C-green.svg)
![Address](https://img.shields.io/badge/Address-7--bit-orange.svg)
![Interface](https://img.shields.io/badge/Interface-APB4-8e44ad.svg)
![Simulator](https://img.shields.io/badge/Sim-Questa%20%7C%20xsim-blueviolet.svg)

A synthesizable, SoC-ready I2C Master controller consisting of two layers:

- **`i2c_master_core`** — one-byte, 7-bit-address I2C FSM engine (ported from [`rtl-design-practice`](https://github.com/longhai-tran/rtl-design-practice/tree/main/05_interfaces/i2c_top)).
- **`i2c_master_apb`** — APB4 slave wrapper exposing a five-register software interface for SoC integration.

Both modules use an open-drain output model: they assert `scl_drive_low` / `sda_drive_low` to pull bus lines LOW, and rely on external pull-ups to restore them to HIGH.

> Related: [`rtl-design-practice/05_interfaces/i2c_top`](https://github.com/longhai-tran/rtl-design-practice/tree/main/05_interfaces/i2c_top) — original standalone master + slave integration with 1000+ transaction testbench.

---

## Upgrade from rtl-design-practice

| Feature | Original (`rtl-design-practice`) | This module |
|---|---|---|
| Control interface | Direct signal wires | **APB4 register slave** |
| SoC integration | Not possible | Plugs into any APB bus fabric |
| Software programmability | No | All parameters set via register writes |
| Clock divider | Compile-time parameter only | **Runtime-programmable** via `CTRL[31:16]` |
| Transfer status | Single-cycle `done` pulse | **Sticky `DONE` bit** — polling-safe |
| Testbench coverage | Standalone master + slave integration | APB register test + bus-level slave model |

---

## Specification

| Property | Value |
|---|---|
| Protocol | I2C — Inter-Integrated Circuit |
| Address width | 7-bit target address, MSB-first |
| Data width | 1 byte per transaction |
| Duplex | Half-duplex; SDA shared by master and target |
| Transactions | Write (ADDR + DATA) and Read (ADDR + DATA) |
| ACK/NACK | Slave ACKs address and data; master NACKs after last read byte |
| Bus model | Wired-AND open-drain; pull-ups resolve bus HIGH |
| SCL frequency | `f_scl = f_clk / (2 x CLK_DIV)` |
| Min CLK_DIV | 2 (clamped in hardware if lower value written) |
| Reset style | Active-low asynchronous (`presetn` / `i_rst_n`) |
| PREADY latency | Zero wait-state (combinational APB slave) |
| START gating | New `START` accepted only when `BUSY = 0` |
| DONE behavior | Sticky — stays set until next `START` is accepted |

---

## Architecture

### Block Diagram

```text
          APB Bus (PCLK domain)
               |
   +-----------v-------------------+
   |      i2c_master_apb           |  <- APB4 register slave (new in this repo)
   |  +------------------------+   |
   |  |  Register File         |   |
   |  |  0x00  CTRL            |   |
   |  |  0x04  ADDR            |   |
   |  |  0x08  TXDATA          |   |
   |  |  0x0C  RXDATA (RO)     |   |
   |  |  0x10  STATUS (RO)     |   |
   |  +-----------+------------+   |
   +--------------|-----------------+
                  | (start_pulse, rw, target_addr, tx_data, clk_div)
   +--------------v-----------------+
   |     i2c_master_core            |  <- FSM engine (ported from rtl-design-practice)
   |   11-state Mealy FSM           |
   |   half_tick clock divider      |
   +----------+---------------------+
              |
   scl_drive_low  sda_drive_low  i_sda
              |
   +----------v---------------------+
   |  Open-drain bus (top-level)    |   scl = ~scl_drive_low
   |  wire AND resolution           |   sda = ~(master_drv OR slave_drv)
   +--------------------------------+
```

### Open-drain Bus Model

```verilog
// Instantiating top-level or testbench resolves the bus:
wire scl = scl_drive_low ? 1'b0 : 1'b1;
tri1 sda_bus;                                    // pull-up resistor
assign sda_bus = sda_drive_low  ? 1'b0 : 1'bz;  // master drive
assign sda_bus = slave_sda_low  ? 1'b0 : 1'bz;  // slave drive
```

`i_sda` (the resolved bus value) is fed back into the master so it can:
- Sample the target ACK bit after address and data phases.
- Detect a bus conflict or stuck-bus condition.

---

## Parameters

| Parameter | Default | Description |
|---|---:|---|
| `CLK_DIV` | `50` | Compile-time default loaded into `CTRL[31:16]` at reset; sets `f_scl = f_clk / 100` |

> At runtime, `CTRL[31:16]` overrides `CLK_DIV`. The hardware enforces a minimum of `2` to guarantee reliable SCL generation.

---

## Ports

### `i2c_master_apb` — APB Wrapper

| Port | Dir | Width | Description |
|---|---|---:|---|
| `pclk` | In | 1 | APB clock |
| `presetn` | In | 1 | Active-low asynchronous reset |
| `psel` | In | 1 | APB peripheral select |
| `penable` | In | 1 | APB enable (access phase) |
| `pwrite` | In | 1 | Transfer direction: `1` = write |
| `paddr` | In | 8 | Register byte address |
| `pwdata` | In | 32 | Write data |
| `prdata` | Out | 32 | Read data |
| `pready` | Out | 1 | Always `1` (zero-wait-state slave) |
| `scl_drive_low` | Out | 1 | Pull SCL LOW when asserted |
| `sda_drive_low` | Out | 1 | Pull SDA LOW when asserted |
| `i_sda` | In | 1 | Resolved SDA value from open-drain bus |

### `i2c_master_core` — FSM Engine

| Port | Dir | Width | Description |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low asynchronous reset |
| `i_start` | In | 1 | Start pulse (one-cycle) — launch a transfer |
| `i_rw` | In | 1 | `0` = write, `1` = read |
| `i_target_addr` | In | 7 | 7-bit I2C target address |
| `i_tx_data` | In | 8 | Byte to transmit (write transactions) |
| `i_clk_div` | In | 16 | SCL half-period in system clocks (min 2) |
| `i_sda` | In | 1 | Resolved SDA from open-drain bus |
| `o_scl_drive_low` | Out | 1 | Pull SCL LOW |
| `o_sda_drive_low` | Out | 1 | Pull SDA LOW |
| `o_rx_data` | Out | 8 | Received byte (read transactions) |
| `o_busy` | Out | 1 | Transfer in progress |
| `o_done` | Out | 1 | One-cycle pulse: transfer complete |
| `o_ack_error` | Out | 1 | Set when target sends NACK |

---

## Register Map

### `0x00` — CTRL (Write)

| Bits | Field | Description |
|---|---|---|
| `[31:16]` | `CLK_DIV_VAL` | Runtime SCL divider (min 2 enforced in hardware) |
| `[15:2]` | — | Reserved; write as 0 |
| `[1]` | `RW` | `0` = write transaction, `1` = read transaction |
| `[0]` | `START` | Write `1` to launch a transfer (auto-clears next cycle) |

Writing `START = 1` while `BUSY = 1` is silently ignored.

### `0x04` — ADDR (R/W)

| Bits | Field | Description |
|---|---|---|
| `[6:0]` | `TARGET_ADDR` | 7-bit I2C target address |

### `0x08` — TXDATA (R/W)

| Bits | Field | Description |
|---|---|---|
| `[7:0]` | `TX_DATA` | Byte to transmit in a write transaction |

### `0x0C` — RXDATA (Read-only)

| Bits | Field | Description |
|---|---|---|
| `[7:0]` | `RX_DATA` | Byte received in the last read transaction |

### `0x10` — STATUS (Read-only)

| Bit | Field | Description |
|---|---|---|
| `[3]` | `ACK_ERR` | Set on NACK; cleared on next accepted `START` |
| `[2]` | `DONE` | Sticky: set when transfer completes, cleared on next accepted `START` |
| `[1]` | `BUSY` | `1` while a transfer is in progress |
| `[0]` | `SDA_IN` | Live value of the resolved SDA line |

> **Polling sequence:** Write `START = 1` to CTRL, then poll `STATUS[2]` until `DONE = 1`. A 200 us watchdog in the testbench enforces a finite upper bound.

---

## FSM — `i2c_master_core`

The controller implements an 11-state Mealy FSM. State transitions are gated by `half_tick` (one pulse per SCL half-period).

```text
  IDLE --[i_start]--> START --> ADDRESS (8 bits, addr[6:0]+R/W, MSB first)
                                    |
                               ADDR_ACK
                              /         \
                          NACK           ACK
                            |           / \
                         (error)    WRITE  READ (8 bits)
                            |         |      |
                          STOP    WRITE_ACK  READ_NACK
                                     |           |
                                  STOP_LOW <-----+
                                     |
                                  STOP_HIGH
                                     |
                                  STOP_FREE --> IDLE  (done pulse)
```

### State Reference

| State | SCL | SDA Action | Description |
|---|---|---|---|
| `IDLE` | Released | Released | Wait for `i_start`; latch all inputs |
| `START` | Released->Low | Low (held) | SDA falls while SCL HIGH — I2C START condition |
| `ADDRESS` | Toggling | Address bits | Clock out 8-bit address frame (addr[6:0] + R/W), MSB first |
| `ADDR_ACK` | Toggles | Released | Sample target ACK; NACK sets `ack_error` but still completes with STOP |
| `WRITE` | Toggling | TX data bits | Clock out 8-bit data byte, MSB first |
| `WRITE_ACK` | Toggles | Released | Sample target ACK for data byte |
| `READ` | Toggling | Released | Sample 8 SDA bits into shift register, MSB first |
| `READ_NACK` | Low | High | Master drives NACK after receiving final read byte |
| `STOP_LOW` | Released | Low | Prepare STOP: release SCL while SDA still Low |
| `STOP_HIGH` | High | Released | STOP condition: SDA rises while SCL HIGH |
| `STOP_FREE` | High | High | Assert `done` for one cycle; return to IDLE |

---

## Quick Start

> Requires **Questa / ModelSim** or **Vivado** on your `PATH`.

```bash
# Questa / ModelSim
cd sim/modelsim
make sim        # batch simulation — auto exits PASS / FAIL
make gui        # interactive GUI with waveform
make clean      # remove compiled artifacts

# Vivado xsim
cd sim/xsim
make sim
make clean
```

### APB Software Flow

```text
1. Write TARGET_ADDR      -> ADDR register   (0x04)
2. Write TX_DATA          -> TXDATA register (0x08)   [write transactions only]
3. Write {CLK_DIV, 14'd0, RW, 1'b1} -> CTRL register (0x00)   <- START fires
4. Poll STATUS[2] (DONE) until set
5. On write: check STATUS[3] (ACK_ERR)
6. On read:  read RXDATA register (0x0C)
```

### Example — Write `0x3C` to target `0x50` at CLK_DIV = 4

```verilog
apb_write(8'h04, 32'h0000_0050);          // ADDR = 0x50
apb_write(8'h08, 32'h0000_003C);          // TXDATA = 0x3C
apb_write(8'h00, 32'h0004_0000 | 32'h1); // CTRL: CLK_DIV=4, RW=0, START=1
// poll STATUS[2] == 1 (DONE)
// check STATUS[3] == 0 (no ACK error)
```

### Example — Read from target `0x50` at CLK_DIV = 3

```verilog
apb_write(8'h04, 32'h0000_0050);           // ADDR = 0x50
apb_write(8'h00, 32'h0003_0000 | 32'h3);  // CTRL: CLK_DIV=3, RW=1, START=1
// poll STATUS[2] == 1 (DONE)
apb_read(8'h0C, rx_data);                 // read received byte from RXDATA
```

---

## Test Plan

> Full details: [`docs/test_plan.md`](docs/test_plan.md)

The testbench [`sim/i2c_master_core_tb.v`](sim/i2c_master_core_tb.v) includes an inline I2C slave model using `tri1 SDA` with open-drain assignments. It covers two levels:

**Level 1 — APB Register** (T1): Reset values, register read-back, and unmapped address returns zero.

**Level 2 — Bus-level** (T2-T6): APB write and background slave task launched with `fork...join` to exercise real I2C waveforms.

| ID | Stimulus | Checks |
|:--:|---|---|
| T1 | Reset + APB R/W + unmapped read | Reset values (`CTRL = 0x0004_0000`), register readback, zero on unmapped |
| T2 | Write `0x3C` to target `0x50` (both ACK) | START/STOP on bus, address frame `0xA0`, data `0x3C`, `DONE=1 ACK_ERR=0` |
| T3 | Read from target `0x50`, slave sends `0xD6` | Address frame `0xA1`, `RXDATA = 0xD6`, master issues NACK after last byte |
| T4 | Address NACK | No data phase; `ACK_ERR=1`, valid STOP, finite completion |
| T5 | Address ACK then data NACK | `ACK_ERR=1`, valid STOP, finite completion |
| T6 | Reset during active transfer | `DONE` clears on accepted START; reset immediately releases SCL and SDA |

**Pass Criteria:**
- Zero compile warnings or errors.
- Scoreboard error count = 0.
- Watchdog at **200 us** does not expire.
- `$fatal` on any check failure — non-zero exit code for CI.

---

## Simulation Results

### Questa / ModelSim — 2026-08-24

```
-- T1: APB reset values and register access | time=40000 --
[PASS] T1: CTRL reset value
[PASS] T1: ADDR readback
[PASS] T1: TXDATA readback
[PASS] T1: unmapped read
-- T2: bus-level write with address and data ACK | time=220000 --
[TIME] T2: transaction = 1560 ns
[PASS] T2: write address frame (7'h50 + RW=0 -> 8'hA0)
[PASS] T2: write data byte (8'h3C)
[PASS] T2: write DONE=1 ACK_ERR=0
-- T3: bus-level read and master NACK | time=1990000 --
[TIME] T3: transaction = 1170 ns
[PASS] T3: read address frame (7'h50 + RW=1 -> 8'hA1)
[PASS] T3: RXDATA value (8'hD6)
-- T4: address NACK aborts with STOP | time=3280000 --
[TIME] T4: transaction = 420 ns
[PASS] T4: address NACK status (DONE=1, ACK_ERR=1)
-- T5: data NACK sets ACK_ERR | time=3820000 --
[TIME] T5: transaction = 1560 ns
[PASS] T5: data NACK status (DONE=1, ACK_ERR=1)
-- T6: reset during an active transfer releases the bus | time=5530000 --
[PASS] T6: BUSY=1 and previous DONE cleared
[PASS] T6: bus released by reset (SCL=1, SDA=1 via pull-ups)
[PASS] T6: status cleared by reset (BUSY=0, DONE=0, ACK_ERR=0)
==================================================
           SIMULATION SUMMARY REPORT
==================================================
  Total Test Cases       : 6
  Valid I2C Transactions : 4 (STOP conditions)
  Assertion Errors       : 0
==================================================
  FINAL RESULT: ALL TESTS PASSED
==================================================
Time: 5670 ns  Errors: 0, Warnings: 0
```

**Tool:** Questa Altera Starter FPGA Edition-64, Version 2025.2

### Vivado xsim

> Pending — xsim gate not yet confirmed.

---

## Design Notes

### Clock Divider and SCL Frequency

The runtime-writable `CLK_DIV_VAL` field in CTRL overrides the compile-time `CLK_DIV` parameter on every new START. The FSM enforces a minimum of `2`:

```
f_scl = f_clk / (2 x max(CLK_DIV_VAL, 2))
```

| CLK_DIV_VAL | f_clk = 100 MHz | f_clk = 50 MHz |
|---|---|---|
| 50 (default) | 1.0 MHz | 500 kHz |
| 500 | 100 kHz | 50 kHz |
| 1250 | 40 kHz | 20 kHz |

### Sticky DONE vs. One-cycle `done` Pulse

`i2c_master_core` outputs a **one-cycle** `o_done` pulse — safe for interrupt-driven flows. `i2c_master_apb` converts this to a **sticky `STATUS.DONE` bit** — safe for polling-based software. DONE clears automatically when the next `START` is accepted.

### Input Latching

All transfer inputs (`target_addr`, `tx_data`, `rw`, `clk_div`) are **latched at the moment START is accepted** so software can safely modify registers during a transfer without affecting it.

### APB Zero-Wait-State Compliance

`PREADY` is hardwired to `1`. All register writes complete in the APB access phase with no wait states. This makes the slave compatible with any APB3/APB4 interconnect without wait-state support.

---

## File Structure

```text
i2c_master_core/
├── rtl/
│   ├── i2c_master_core.v       # 11-state FSM engine
│   └── i2c_master_apb.v        # APB4 register slave wrapper
├── sim/
│   ├── i2c_master_core_tb.v    # Self-checking TB with inline slave model
│   ├── modelsim/
│   │   ├── Makefile
│   │   ├── simulate.do
│   │   ├── wave.do
│   │   └── transcript           # Latest simulation log (2026-08-24, ALL PASS)
│   └── xsim/
│       ├── Makefile
│       ├── simulate.tcl
│       └── wave.tcl
├── docs/
│   ├── test_plan.md             # 6 test cases with stimulus and checks
│   └── README.md
├── constraints/
│   └── timing.xdc               # Clock constraint for Vivado synthesis
└── README.md                    # This file
```

---


## 📚 References

| # | Document | Source / Description |
|:---:|---|---|
| [1] | **I²C Protocol — Lý Thuyết Giao Thức I²C** | [`docs/i2c_theory.md`](../../docs/i2c_theory.md) — Open-drain bus, START/STOP, address frame, ACK/NACK, FSM architecture |
| [2] | **I²C-bus specification and user manual Rev. 7.0** | [NXP UM10204](https://www.nxp.com/docs/en/user-guide/UM10204.pdf) — Official I²C standard specification |
| [3] | **Understanding the I²C Bus** | [Texas Instruments SLVA704](https://www.ti.com/lit/an/slva704/slva704.pdf?ts=1699596969514&ref_url=https%3A%2F%2Fwww.google.com%2F) — Hardware implementation guide & pull-up calculation |
| [4] | **Wikipedia — I²C** | [wikipedia.org](https://en.wikipedia.org/wiki/I%C2%B2C) — Protocol overview, history, and bus characteristics |
| [5] | **Giao thức I2C — E-Lab** | [blog.deviot.vn](https://blog.deviot.vn/posts/lap-trinh-vi-dieu-khien/giao-thuc-i2c) — Practical guide and timing diagram walkthrough |

---

## 🔗 Related Work

| Resource | Description |
|---|---|
| [rtl-design-practice / i2c_top](https://github.com/longhai-tran/rtl-design-practice/tree/main/05_interfaces/i2c_top) | Original standalone master + slave, 1000+ transaction TB |
| [05_mini_soc](../../05_mini_soc/) | Capstone SoC — `i2c_master_apb` connects via AXI-to-APB bridge |
| [docs/rtl_coding_guidelines.md](../../docs/rtl_coding_guidelines.md) | Repository RTL coding style |
