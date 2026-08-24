# RTL Advanced Projects

[![RTL Lint](https://github.com/longhai-tran/rtl-advanced-projects/actions/workflows/lint.yml/badge.svg)](https://github.com/longhai-tran/rtl-advanced-projects/actions/workflows/lint.yml)
![Language](https://img.shields.io/badge/HDL-Verilog%20%7C%20SystemVerilog-2f80ed)
![Simulation](https://img.shields.io/badge/Sim-Questa%20%7C%20Vivado%20xsim-27ae60)
![IP Blocks](https://img.shields.io/badge/IP%20Blocks-5-informational)
![Status](https://img.shields.io/badge/Status-Active%20Development-f39c12)

Advanced RTL design projects covering reusable IP blocks, synthesis methodology, clock-domain crossing, low-power techniques, and SoC integration. Each module ships with synthesizable RTL, a self-checking testbench, simulator scripts, constraints where applicable, and documented design trade-offs.

---

## 📁 Repository Layout

```text
rtl-advanced-projects/
├── 01_ip_blocks/
│   ├── async_fifo_gray/          # Gray-pointer dual-clock FIFO        ✅ RTL + TB
│   ├── axi4_lite_slave/          # AXI4-Lite register slave             🔄 In progress
│   ├── i2c_master_core/          # I2C master with APB wrapper          🔄 In progress
│   ├── spi_flash_controller/     # SPI NOR Flash command controller     🔄 In progress
│   └── apb_slave/                # APB peripheral slave                 📋 Planned
├── 02_synthesis/                 # Vivado and Design Compiler flows      📋 Planned
├── 03_cdc_design/                # Pulse and handshake synchronizers     📋 Planned
├── 04_low_power/                 # Clock/power gating and multi-VT       📋 Planned
├── 05_mini_soc/                  # Capstone bus/peripheral integration   📋 Planned
├── docs/                         # Repository-wide RTL and synthesis guidance
├── scripts/                      # Git workflow and cleanup helpers
└── skills/                       # Local project templates and checklists
```

Each IP block follows a consistent internal structure:

```text
<module>/
├── rtl/                          # Synthesizable source files
├── sim/
│   ├── modelsim/                 # Questa / ModelSim Makefile + batch scripts
│   └── xsim/                    # Vivado xsim Makefile + batch scripts
├── constraints/                  # XDC / SDC (timing, CDC grouping)
├── docs/                         # Module spec, test plan, waveform notes
└── README.md                     # Port list, architecture, run instructions
```

---

## 🔥 Featured Design: Async FIFO Gray

[`01_ip_blocks/async_fifo_gray`](01_ip_blocks/async_fifo_gray/) is the reference module for this repository. Key highlights:

- **Gray-coded pointers** crossing independent clock domains with no glitch risk.
- **Two-stage synchronizers** with `ASYNC_REG` attributes for tool-aware placement.
- **Per-domain active-low resets** and precise full/empty detection.
- **Vivado XDC** with `set_clock_groups -asynchronous` for timing sign-off.
- **Self-checking testbench** covering normal, full, empty, and concurrent traffic scenarios.

→ See the [module README](01_ip_blocks/async_fifo_gray/README.md) for the full port list, architecture walkthrough, and simulation results.

---

## 📊 Project Status

| Phase | Module / Area | Status | Notes |
|:-----:|---|:---:|---|
| 1 | `async_fifo_gray` | ✅ RTL + TB | Questa passed · xsim + lint gates remain |
| 1 | `spi_flash_controller` | 🔄 In progress | Questa batch passed · xsim, lint, docs remain |
| 1 | `axi4_lite_slave` | 🔄 In progress | RTL skeleton + partial register map exist |
| 1 | `i2c_master_core` | 🔄 In progress | RTL compiles · TB `always assign` loop to fix |
| 1 | `apb_slave` | 📋 Planned | Not started |
| 2 | Synthesis flows | 📋 Planned | Vivado + DC scripts/reports after Phase 1 |
| 3 | CDC library | 📋 Planned | Pulse sync + handshake sync not yet implemented |
| 4 | Low-power examples | 📋 Planned | Clock/power gating + multi-VT material planned |
| 5 | Mini SoC | 📋 Planned | Capstone integration follows preceding phases |

> Full week-by-week tasks and Definition of Done criteria are in [`implementation_plan.md`](implementation_plan.md).

---

## ✅ Verification Contract

A module is **not** considered verified simply because its source files exist. Before promotion to `main`, every module must satisfy these gates:

| Gate | Requirement |
|:---:|---|
| 📄 **Specification** | Ports, reset/clock behavior, protocol, and corner cases are documented |
| 🔬 **RTL Quality** | Compile and lint are clean; design is synthesizable |
| 🧪 **Functional Verification** | Self-checking tests cover nominal, reset, boundary, and back-pressure scenarios |
| ⏱ **Implementation** | XDC/SDC and synthesis reports are included where applicable |
| 📝 **Documentation** | README, simulation results, and a reference waveform are available |

CI runs **Verilator lint** on all RTL files for every push and pull request to `main` and `dev`. Simulator results are recorded in each module's own README.

---

## 🚀 Quick Start

> Requires Questa/ModelSim **or** Vivado installed and on your `PATH`.

```bash
# Questa / ModelSim — run and clean
cd 01_ip_blocks/spi_flash_controller/sim/modelsim
make sim
make clean

# Vivado xsim — run and clean
cd 01_ip_blocks/spi_flash_controller/sim/xsim
make sim
make clean
```

**Starting a new work item** using the repository Git helper:

```bash
bash scripts/git_flow.sh start ip_blocks axi4_lite_slave
# implement RTL → lint → simulate → document
bash scripts/git_flow.sh push  ip_blocks axi4_lite_slave
bash scripts/git_flow.sh merge ip_blocks axi4_lite_slave
```

The helper stages only the requested path — no `git add .` — and keeps feature branches available for review after merging into `dev`.

---

## 🛠 Tools

| Tool | Role | Required |
|---|---|:---:|
| Questa / ModelSim | Primary RTL simulation | ✅ Yes |
| Vivado xsim | Secondary simulation + FPGA flow | ✅ Yes |
| Verilator | RTL lint in CI | ✅ Yes |
| Synopsys Design Compiler | ASIC synthesis scripts | ⚙ Optional |
| Git + GNU Make | Workflow and simulator entry points | ✅ Yes |

*Exact tool versions are kept environment-specific and recorded alongside synthesis reports.*

---

## 🗺 Roadmap

| Phase | Scope | Exit Deliverable |
|:-----:|---|---|
| **0** | Baseline | Repeatable simulation commands and reliable pass/fail results |
| **1** | IP Blocks | AXI4-Lite + APB completed alongside FIFO, I2C, and SPI |
| **2** | Synthesis | Vivado timing reports and reviewed DC scripts |
| **3** | CDC | Async FIFO stress, pulse sync, and handshake sync |
| **4** | Low Power | Clock gating, power sequencing, and multi-VT analysis |
| **5** | Mini SoC | End-to-end bus/peripheral verification and synthesis |

---

## 📚 Documentation

| Document | Description |
|---|---|
| [`docs/rtl_coding_guidelines.md`](docs/rtl_coding_guidelines.md) | In-house RTL coding style and naming conventions |
| [`docs/synthesis_flow.md`](docs/synthesis_flow.md) | Vivado and DC synthesis flow setup |
| [`docs/timing_closure_tips.md`](docs/timing_closure_tips.md) | Timing closure strategies and common fixes |
| [`implementation_plan.md`](implementation_plan.md) | Executable 26-week roadmap with DoD criteria |
| [`plan_study.md`](plan_study.md) | Portfolio-wide VLSI study roadmap |

---

## 🔗 Related Work

| Repository | Purpose |
|---|---|
| [rtl-design-practice](https://github.com/longhai-tran/rtl-design-practice) | Foundational Verilog modules: combinational, sequential, FSM, memory, interfaces |
| [sv-verification](https://github.com/longhai-tran/sv-verification) | SystemVerilog testbenches, assertions, and functional coverage |
| [uvm-projects](https://github.com/longhai-tran/uvm-projects) | UVM-based verification environments |

This repository is part of the [VLSI engineering portfolio](https://github.com/longhai-tran).

---

## 📜 License

No license has been declared yet. Treat this repository as a personal study portfolio until a license is added.
