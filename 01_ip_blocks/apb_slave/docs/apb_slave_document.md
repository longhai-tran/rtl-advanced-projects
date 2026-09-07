# APB Slave — Technical Specification & Architecture Manual

> **Module**: `apb_slave`
> **Giao thức chuẩn**: ARM AMBA APB Architecture Specification (**ARM IHI0024E**, APB4)
> **Thiết kế**: Zero-Wait-State Register Completer with Byte Strobes
> **Repo**: `rtl-advanced-projects / 01_ip_blocks / apb_slave`
> **Cập nhật**: 2026-09-03

---

## 📌 Bảng Đối Chiếu Tiêu Chuẩn ARM IHI0024E (Specification Compliance)

Tài liệu này được biên soạn và thiết kế dựa trên đặc tả kiến trúc chính thức:
* **Tài liệu tham chiếu:** *ARM AMBA® APB Architecture Specification (Doc ID: ARM IHI 0024E, Issue E.b)*.
* **Vai trò module (Component Role):** **APB Completer** (Slave).

### Bảng Đối Chiếu Tính Năng & Mức Độ Tuân Thủ

| Điều khoản ARM IHI0024E | Hạng mục quy định trong Spec | Mức độ đáp ứng trong RTL | Giải trình thiết kế (Design Rationale) |
|---|---|:---:|---|
| **Chapter 2: Signal Descriptions** | Tín hiệu bắt tay & Bus Interface | **Tuân thủ 100%** | Đầy đủ các chân cơ bản (`PCLK`, `PRESETn`, `PSEL`, `PENABLE`, `PWRITE`, `PADDR`, `PWDATA`, `PRDATA`). |
| **Chapter 2: Signal Descriptions** | Write Strobes (`PSTRB[3:0]`) | **Tuân thủ 100%** | Hỗ trợ ghi linh hoạt theo từng byte lane cho word 32-bit (`PSTRB[n]` tương ứng byte lane `n`). |
| **Chapter 2: Signal Descriptions** | Protection Control (`PPROT[2:0]`) | *Lược bỏ (Omitted)* | Module là register file ngoại vi nội bộ, không phân quyền Secure/Privileged nên không cần thiết kế chân `PPROT` nhằm tối ưu diện tích (gate count). |
| **Chapter 3: Transfers** | Write Transfers | **Tuân thủ 100%** | Chốt ghi dữ liệu tại cạnh lên `PCLK` khi thỏa mãn điều kiện bắt tay: `PSEL & PENABLE & PREADY == 1`. |
| **Chapter 3: Transfers** | Read Transfers | **Tuân thủ 100%** | `PRDATA` hợp lệ ngay trong chu kỳ Access (`PENABLE=1`), trả về giá trị thanh ghi tương ứng. |
| **Chapter 3: Transfers** | Error Responses (`PSLVERR`) | **Tuân thủ 100%** | Báo lỗi khi địa chỉ ngoài dải hoặc không căn chỉnh 4-byte; cờ lỗi chỉ kích hoạt duy nhất trong pha Access. |
| **Chapter 3 & 4** | Wait States (`PREADY`) | **Tuân thủ (Zero-wait)** | Phản hồi tức thì với `PREADY = 1'b1`, tối ưu độ trễ (latency) cho thanh ghi cấu hình nội bộ. |
| **Chapter 4: Operating States** | Máy trạng thái bus (`IDLE, SETUP, ACCESS`) | **Tuân thủ 100%** | Nhận diện chính xác 2 pha: Setup (`PSEL=1, PENABLE=0`) và Access (`PENABLE=1`). Hỗ trợ chuyển tiếp Back-to-Back. |

---

## Mục Lục

1. [Tổng Quan Giao Thức APB4 (ARM IHI0024E)](#1-tổng-quan-giao-thức-apb4-arm-ihi0024e)
2. [Kiến Trúc Module](#2-kiến-trúc-module)
3. [Register Map](#3-register-map)
4. [Port Interface](#4-port-interface)
5. [Hoạt Động Chi Tiết (Protocol Transfers)](#5-hoạt-động-chi-tiết-protocol-transfers)
6. [RTL — Phân Tích Hiện Thực Phần Cứng](#6-rtl--phân-tích-hiện-thực-phần-cứng)
7. [Testbench & Verification Plan](#7-testbench--verification-plan)
8. [Chạy Simulation](#8-chạy-simulation)
9. [Timing & Synthesis](#9-timing--synthesis)
10. [Vị Trí trong Study Plan & SoC Integration](#10-vị-trí-trong-study-plan--soc-integration)
11. [Câu Hỏi Phỏng Vấn Thường Gặp (Design Trade-offs)](#11-câu-hỏi-phỏng-vấn-thường-gặp-design-trade-offs)

---

## 1. Tổng Quan Giao Thức APB4 (ARM IHI0024E)

### 1.1 Vị Trí của APB trong Hệ Thống AMBA

Theo định nghĩa của ARM, **AMBA (Advanced Microcontroller Bus Architecture)** là chuẩn bus trên chip (on-chip bus). Trong đó:
* **AXI4 / AXI4-Lite:** Bus hiệu năng cao, nhiều kênh độc lập, hỗ trợ pipelining, phù hợp kết nối CPU, Memory Controller.
* **AHB / AHB-Lite:** Bus hiệu năng trung bình, hỗ trợ truyền burst, phù hợp hệ thống MCU đơn giản.
* **APB4:** Bus tối ưu cho ngoại vi tiêu thụ năng lượng thấp (**Low-power, low-bandwidth peripherals**) như GPIO, UART, Timers, Register Interfaces.

### 1.2 Máy Trạng Thái Bus (ARM IHI0024E — Chapter 4: Operating States)

Theo chuẩn ARM IHI0024E (Chapter 4), một APB transfer được quản lý bởi Finite State Machine gồm 3 trạng thái:

<p align="center">
  <img src="operating_state.png" alt="ARM APB Operating State Machine" width="380"/>
</p>

1. **IDLE (`PSEL=0, PENABLE=0`):** Trạng thái mặc định khi bus không có yêu cầu truyền nhận.
2. **SETUP (`PSEL=1, PENABLE=0`):** Master kích hoạt transfer. Địa chỉ `PADDR`, điều khiển `PWRITE`, và dữ liệu `PWDATA` được đưa lên bus và ổn định trong đúng 1 chu kỳ clock.
3. **ACCESS (`PSEL=1, PENABLE=1`):** Thực thi transfer:
   * **Wait State (`PREADY=0`):** Slave yêu cầu thêm thời gian xử lý, bus duy trì trạng thái ACCESS.
   * **Transfer Complete (`PREADY=1`):** Bắt tay hoàn tất tại cạnh lên của `PCLK`.
   * Nếu không có transfer tiếp theo: Trở về `IDLE`.
   * Nếu có transfer mới ngay lập tức: Nhảy trực tiếp về `SETUP` (**Back-to-Back Transfer**).

> 💡 **Đặc tính của module này:** Là **Zero-Wait-State Completer**, tín hiệu `PREADY` luôn bằng `1`. Do đó mọi transfer hoàn thành trong chính xác 2 chu kỳ clock (1 Setup + 1 Access).

### 1.3 So Sánh Kiến Trúc: APB4 vs AXI4-Lite

| Tiêu chí              | APB4                       | AXI4-Lite                      |
|-----------------------|----------------------------|---------------------------------|
| Số channel           | 1 (shared)                 | 5 (AW, W, B, AR, R)            |
| Cơ chế               | Setup → Access             | VALID / READY handshake         |
| Outstanding transfers | 1 tại một thời điểm        | Phụ thuộc implementation        |
| Back-pressure        | `PREADY`                   | `READY` per channel             |
| Burst                | Không hỗ trợ               | Không hỗ trợ (chỉ AXI4 full)   |
| Byte strobe          | `PSTRB[3:0]`               | `WSTRB[3:0]`                    |
| Dùng cho             | Low-BW peripherals         | Memory-mapped control + data    |

---

## 2. Kiến Trúc Module

### 2.1 Block Diagram

```
                   ┌─────────────────────────────────────────┐
  APB Master       │              apb_slave                  │
  (Bridge)         │                                         │
                   │  ┌─────────────┐    ┌───────────────┐   │
  PSEL  ──────────►│  │   Address   │    │  Register     │   ├──► o_reg0
  PENABLE ────────►│  │   Decoder   │──► │  Bank         │   ├──► o_reg1
  PWRITE ─────────►│  │             │    │  r_regs[0:6]  │   ├──► o_reg2
  PADDR[7:0] ─────►│  │ w_addr_valid│    │               │   ├──► o_reg3
  PWDATA[31:0] ───►│  │ w_write     │    │  32-bit x 7   │   ├──► o_reg4
  PSTRB[3:0] ─────►│  └─────────────┘    └──────┬────────┘   ├──► o_reg5
                   │                            │            ├──► o_reg6
  PREADY ◄─────────│─── 1'b1 (constant)         │            │
  PRDATA[31:0] ◄───│─── Read MUX ───────────────┘            │
  PSLVERR ◄────────│─── Error Logic                          │
                   │                                         │
  i_status[31:0] ─►│─── STATUS Reg (R/O, live)               │
                   │                                         │
                   └─────────────────────────────────────────┘
```

### 2.2 Thành Phần Bên Trong

| Thành phần       | Loại          | Mô tả                                              |
|------------------|---------------|-----------------------------------------------------|
| `r_regs[0:6]`    | Sequential    | Mảng 7 thanh ghi 32-bit, ghi theo PSTRB            |
| Address Decoder  | Combinational | Kiểm tra range và alignment của `PADDR`             |
| Write Logic      | Sequential    | Ghi có điều kiện theo byte lane                    |
| Read MUX         | Combinational | Chọn data trả về theo địa chỉ                      |
| Error Logic      | Combinational | `PSLVERR` khi địa chỉ ngoài range hoặc misaligned  |

---

## 3. Register Map

| Địa chỉ | Tên    | Access | Kết nối ra ngoài | Mô tả                        |
|---------|--------|:------:|------------------|------------------------------|
| `0x00`  | REG0   | R/W    | `o_reg0`         | General-purpose register 0   |
| `0x04`  | REG1   | R/W    | `o_reg1`         | General-purpose register 1   |
| `0x08`  | REG2   | R/W    | `o_reg2`         | General-purpose register 2   |
| `0x0C`  | REG3   | R/W    | `o_reg3`         | General-purpose register 3   |
| `0x10`  | REG4   | R/W    | `o_reg4`         | General-purpose register 4   |
| `0x14`  | REG5   | R/W    | `o_reg5`         | General-purpose register 5   |
| `0x18`  | REG6   | R/W    | `o_reg6`         | General-purpose register 6   |
| `0x1C`  | STATUS | **R/O**| ← `i_status`     | Live status, write bị ignore |

### Quy tắc địa chỉ hợp lệ

- Phải trong range `0x00` – `0x1C`: `PADDR[7:5] == 3'b000`
- Phải căn chỉnh 4-byte: `PADDR[1:0] == 2'b00`
- Vi phạm một trong hai → `PSLVERR = 1`

### Byte Strobe `PSTRB[3:0]`

```
PSTRB[3]  PSTRB[2]  PSTRB[1]  PSTRB[0]
  │          │          │          │
[31:24]   [23:16]    [15:8]     [7:0]
```

- `PSTRB[n] = 1` → byte lane `n` được ghi
- `PSTRB[n] = 0` → byte lane `n` giữ nguyên giá trị cũ

---

## 4. Port Interface

### 4.1 APB Bus Signals

| Signal         | Dir | Width | Mô tả                                   |
|----------------|:---:|------:|-----------------------------------------|
| `pclk`         | In  | 1     | APB clock                               |
| `presetn`      | In  | 1     | Active-low asynchronous reset           |
| `psel`         | In  | 1     | Slave được chọn                         |
| `penable`      | In  | 1     | Access phase qualifier                  |
| `pwrite`       | In  | 1     | `1` = write, `0` = read                 |
| `paddr`        | In  | 8     | Byte address                            |
| `pwdata`       | In  | 32    | Write data                              |
| `pstrb`        | In  | 4     | Write byte enables                      |
| `prdata`       | Out | 32    | Read data (combinational)               |
| `pready`       | Out | 1     | Luôn = `1` (no wait state)              |
| `pslverr`      | Out | 1     | `1` = invalid address error             |

### 4.2 Application Interface

| Signal        | Dir | Width | Mô tả                                    |
|---------------|:---:|------:|------------------------------------------|
| `i_status`    | In  | 32    | Live status value, đọc qua `0x1C`        |
| `o_reg0`      | Out | 32    | Giá trị hiện tại của REG0                |
| `o_reg1`      | Out | 32    | Giá trị hiện tại của REG1                |
| `o_reg2`      | Out | 32    | Giá trị hiện tại của REG2                |
| `o_reg3`      | Out | 32    | Giá trị hiện tại của REG3                |
| `o_reg4`      | Out | 32    | Giá trị hiện tại của REG4                |
| `o_reg5`      | Out | 32    | Giá trị hiện tại của REG5                |
| `o_reg6`      | Out | 32    | Giá trị hiện tại của REG6                |

### 4.3 Parameter

| Parameter     | Default         | Mô tả                                    |
|---------------|-----------------|------------------------------------------|
| `RESET_VALUE` | `32'h0000_0000` | Giá trị reset cho tất cả 7 thanh ghi R/W |

---

## 5. Hoạt Động Chi Tiết (Protocol Transfers)

### 5.1 Write Transfer Không Có Wait State (ARM IHI0024E — Chapter 3: Transfers)

Theo chuẩn ARM IHI0024E (Mục Write transfers without wait states), một chu kỳ ghi diễn ra như sau:
* **Chu kỳ 1 (Setup Phase):** Master kéo `PSEL=1`, giữ `PENABLE=0`. Đưa `PADDR`, `PWRITE=1`, `PWDATA`, và `PSTRB` lên bus.
* **Chu kỳ 2 (Access Phase):** Master kéo `PENABLE=1`. Slave phản hồi `PREADY=1`.
* **Kết thúc:** Tại cạnh lên kế tiếp của `PCLK`, dữ liệu `PWDATA` được chốt vào flip-flop bên trong Slave.

```text
Cycle:           1        2       3
               Setup   Access   Idle
PCLK    ────┐  ┌────┐  ┌────┐  ┌──────
            └──┘    └──┘    └──┘
PSEL    ─────────────────────┐
                             └────────
                    ┌───────┐
PENABLE ────────────┘       └─────────
PWRITE  ─────────────── 1 ────────────
PADDR   ────────────── 0x04 ──────────
PWDATA  ────────── 0xAABBCCDD ────────
PSTRB   ─────────────── 0xF ──────────
PREADY  ──────────────────────────────  ← always 1
                    ↑
     Transfer completes (rising edge, PSEL=PENABLE=PREADY=1)
```

### 5.2 Read Transfer Không Có Wait State (ARM IHI0024E — Chapter 3: Transfers)

Theo chuẩn ARM IHI0024E (Mục Read transfers without wait states):
* Master điều khiển `PWRITE=0` và đưa địa chỉ `PADDR` tại pha Setup.
* Trong pha Access (`PENABLE=1`), Slave **bắt buộc phải lái dữ liệu hợp lệ lên bus `PRDATA`** trước hoặc tại cạnh lên clock hoàn tất transfer.
* Module `apb_slave` này sử dụng multiplexer combinational thuần túy, do đó `PRDATA` ổn định tức thì ngay khi `PENABLE=1`.

```text
Cycle:           1       2        3
               Setup   Access    Idle
PCLK    ────┐  ┌────┐  ┌────┐  ┌──────
            └──┘    └──┘    └──┘
PSEL    ─────────────────────┐
                             └────────
                    ┌───────┐
PENABLE ────────────┘       └─────────
PWRITE  ─────────────── 0 ────────────
PADDR   ────────────── 0x04 ──────────
PRDATA  ────────────── 0xAABBCCDD ────  (combinational, valid in Access phase)
PREADY  ──────────────────────────────  ← always 1
PSLVERR ─────────────── 0 ────────────  (0 = no error)
```

### 5.3 Error Response (ARM IHI0024E — Chapter 3: Transfers, Error responses)

Chuẩn ARM IHI0024E định nghĩa tín hiệu `PSLVERR` dùng để báo lỗi transfer:
* `PSLVERR` chỉ được đánh giá và có giá trị hợp lệ khi transfer hoàn tất (`PSEL=1, PENABLE=1, PREADY=1`).
* Khi bus ở trạng thái `IDLE` hoặc `SETUP`, `PSLVERR` được giữ ở mức `0`.
* Trong module này: Khi địa chỉ nằm ngoài dải (`> 0x1C`) hoặc không căn chỉnh 4-byte (`PADDR[1:0] != 2'b00`), module sẽ kéo `PSLVERR = 1` trong suốt Access phase, trả về `PRDATA = 32'd0`, và **tuyệt đối không làm thay đổi (corrupt) dữ liệu** của các thanh ghi hiện có.

```text
Cycle:           1       2        3
                Setup  Access    Idle
PCLK    ────┐  ┌────┐  ┌────┐  ┌──────
            └──┘    └──┘    └──┘
PSEL    ─────────────────────┐
                             └────────
                    ┌───────┐
PENABLE ────────────┘       └─────────
PADDR   ────────────── 0x20 ──────────  (out-of-range: valid range 0x00–0x1C)
PREADY  ──────────────────────────────  ← always 1
                    ┌───────┐
PSLVERR ────────────┘       └─────────  (asserted ONLY in Access phase per ARM spec)
PRDATA  ─────────────── 0 ────────────  (returns 0 on error)
```

### 5.4 Back-to-Back Transfers (ARM IHI0024E — Chapter 4: Operating States)

Theo sơ đồ trạng thái tại Chapter 4 của ARM IHI0024E, giao thức hỗ trợ chuyển tiếp trực tiếp từ `ACCESS` về `SETUP` của transfer tiếp theo:
* Khi transfer 1 kết thúc ở Access phase (`PENABLE=1, PREADY=1`), nếu có transfer 2 kế tiếp:
* Tín hiệu `PSEL` **tiếp tục giữ mức HIGH**.
* `PENABLE` được hạ xuống LOW trong đúng 1 chu kỳ để tạo pha **Setup của transfer 2**, đồng thời `PADDR` và `PWDATA` mới được cập nhật.

```text
Cycle:        1        2      3       4        5
            Setup1  Access1 Setup2  Access2  Idle
PCLK  ──┐    ┌──┐    ┌──┐    ┌──┐    ┌──┐    ┌───────
        └────┘  └────┘  └────┘  └────┘  └────┘
PSEL  ───────────────────────────────────────────┐      ← stays HIGH throughout
                                                 └───
                     ┌──┐            ┌──┐
PENABLE ─────────────┘  └────────────┘  └────────────   ← LOW→HIGH→LOW→HIGH→LOW
PADDR   ────── ADDR1 ──────── ADDR2 ─────────────────   ← changes at Setup2
PREADY  ─────────────────────────────────────────────   ← always 1
                  ↑                    ↑
            Write1 committed       Write2 committed
```

---

## 6. RTL — Phân Tích Hiện Thực Phần Cứng

Kiến trúc phần cứng của `apb_slave.v` hiện thực hóa đầy đủ các quy tắc giao thức của **ARM IHI0024E**:

### 6.1 Giải Mã Tín Hiệu Giao Thức (Protocol Decoding)

Theo chuẩn ARM, việc chốt ghi hoặc trả dữ liệu chỉ được thực hiện khi transfer đang ở pha `ACCESS` và địa chỉ hợp lệ:

```verilog
// Nhận diện pha Access theo ARM spec: PSEL=1 và PENABLE=1
wire w_access = psel & penable;

// Kiểm tra tính hợp lệ của địa chỉ (Address Decoding):
// - Thuộc vùng nhớ ngoại vi (0x00–0x1F):  paddr[7:5] == 3'b000
// - Căn chỉnh 4-byte (Alignment check):   paddr[1:0] == 2'b00
wire w_addr_valid = (paddr[7:5] == 3'b000) && (paddr[1:0] == 2'b00);

// Điều kiện chốt ghi (Write Qualifier):
// Access phase + lệnh Write + Địa chỉ hợp lệ + Không thuộc vùng STATUS (index < 7)
wire w_write = w_access & pwrite & w_addr_valid & (paddr[4:2] < 3'd7);
```

* **Bảo vệ thanh ghi STATUS:** Thanh ghi `STATUS` đặt tại `0x1C` (`paddr[4:2] = 3'd7`). Biểu thức `paddr[4:2] < 3'd7` ngăn chặn việc ghi đè lên giá trị trạng thái phần cứng, đồng thời không gây báo lỗi `PSLVERR` (phù hợp với chuẩn SoC dummy-write).

### 6.2 Hiện Thực Write Path & Byte Strobes (ARM IHI0024E — Chapter 2: Signal Descriptions)

```verilog
always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
        // Reset tất cả 7 register về RESET_VALUE
        for (r_index = 0; r_index < 7; r_index = r_index + 1)
            r_regs[r_index] <= RESET_VALUE;
    end else if (w_write) begin
        // Byte-lane selective write
        // paddr[4:2] chọn register index (0x00→0, 0x04→1, ..., 0x18→6)
        for (r_byte = 0; r_byte < 4; r_byte = r_byte + 1) begin
            if (pstrb[r_byte])
                r_regs[paddr[4:2]][r_byte*8 +: 8] <= pwdata[r_byte*8 +: 8];
        end
    end
end
```

**Cú pháp `[r_byte*8 +: 8]`**: Part-select với chiều rộng cố định —
`r_byte*8` là bit start, `8` là width. Đây là cách chuẩn để access byte lane
trong Verilog, được synthesis tool hỗ trợ đầy đủ.

### 6.3 Read Logic (Combinational)

```verilog
always @(*) begin
    prdata = 32'd0;                           // Default: trả về 0
    if (w_access && !pwrite && w_addr_valid) begin
        case (paddr)
            ADDR_REG0:   prdata = r_regs[0];
            ADDR_REG1:   prdata = r_regs[1];
            ADDR_REG2:   prdata = r_regs[2];
            ADDR_REG3:   prdata = r_regs[3];
            ADDR_REG4:   prdata = r_regs[4];
            ADDR_REG5:   prdata = r_regs[5];
            ADDR_REG6:   prdata = r_regs[6];
            ADDR_STATUS: prdata = i_status;   // Live value, không qua FF
            default:     prdata = 32'd0;
        endcase
    end
end
```

**Lý do Combinational:** `PRDATA` phải hợp lệ trong cùng Access phase,
không thể có thêm 1 clock delay — đây là yêu cầu bắt buộc của APB4 spec.

### 6.4 Output Assignments

```verilog
assign pready  = 1'b1;                      // Zero wait state
assign pslverr = w_access & ~w_addr_valid;  // Error chỉ trong Access phase

assign o_reg0 = r_regs[0];
// ...
assign o_reg6 = r_regs[6];
```

---

## 7. Testbench & Verification

### 7.1 Kiến Trúc Testbench

```
apb_slave_tb.v
├── DUT: apb_slave (RESET_VALUE = 0xA5A5_0000)
├── Clock gen: period 10 ns (100 MHz)
├── Tasks:
│   ├── apb_idle()                    ← de-assert tất cả bus signals
│   ├── apb_write(addr, data, strb)   ← 1 complete APB write transfer
│   ├── apb_read(addr)                ← 1 complete APB read transfer
│   ├── back_to_back_write()          ← 2 writes không có idle giữa
│   └── check(condition, msg)         ← self-checking assertion
└── Watchdog: $fatal sau 100 µs nếu simulation không kết thúc
```

### 7.2 Test Cases

| ID | Test | Kích thích | Kiểm tra |
|----|------|-----------|----------|
| **T1** | Reset & Idle | Assert/deassert `presetn` | `PREADY=1`, `PSLVERR=0`, `PRDATA=0`, tất cả regs = `0xA5A5_0000` |
| **T2** | Full-word write/read | Ghi `0x1234_5678` vào REG0 với `PSTRB=0xF` | Readback chính xác |
| **T3** | Byte strobe | Ghi `0xDEAD_BEEF` với `PSTRB=0b0101` | Chỉ byte 0 và byte 2 thay đổi |
| **T4** | STATUS register | Đọc `0x1C` khi `i_status=0xCAFE_BABE` | Live value, write không ảnh hưởng |
| **T5** | Invalid address | Đọc `0x20`, ghi misaligned `0x02` | `PSLVERR=1`, data=0, không corrupt reg |
| **T6** | Back-to-back | 2 write liên tiếp không idle | Cả hai hoàn thành, giá trị đúng |

### 7.3 Ví Dụ Byte Strobe (T3)

```
Trạng thái REG0 ban đầu (sau T2): 0x1234_5678

Ghi với PSTRB=0b0101, PWDATA=0xDEAD_BEEF:
  - PSTRB[0]=1 → byte[7:0]   thay đổi: 0x78 → 0xEF
  - PSTRB[1]=0 → byte[15:8]  giữ nguyên:    0x56
  - PSTRB[2]=1 → byte[23:16] thay đổi: 0x34 → 0xAD
  - PSTRB[3]=0 → byte[31:24] giữ nguyên:    0x12

Kết quả REG0: 0x12AD_56EF  ✓
```

### 7.4 Kết Quả Simulation

```text
[TEST] T1: reset and idle outputs
[PASS] PREADY is always asserted
[PASS] all R/W registers reset to RESET_VALUE
[PASS] idle response is clean
[TEST] T2: full-word read and write
[PASS] full-word write reads back correctly
[TEST] T3: APB4 byte strobes
[PASS] PSTRB updates only selected byte lanes
[PASS] zero strobe leaves register unchanged
[TEST] T4: read-only status register
[PASS] STATUS reflects live input
[PASS] STATUS ignores writes without reporting an error
[TEST] T5: invalid and misaligned addresses
[PASS] out-of-range read returns zero and PSLVERR
[PASS] misaligned write reports PSLVERR and changes no data
[TEST] T6: back-to-back transfers
[PASS] consecutive transfers complete without an idle cycle
==================================================
           SIMULATION SUMMARY REPORT
==================================================
  Total Test Scenarios   : 6 (T1 - T6)
  Assertion Checks Run   : 11
  Assertion Errors       : 0
==================================================
  FINAL RESULT: ALL TESTS PASSED
==================================================
Time: 380 ns  Errors: 0, Warnings: 0
```

Verified on **Questa 2025.2** và **Vivado xsim 2025.2**.

---

## 8. Chạy Simulation

### 8.1 ModelSim / Questa

```bash
cd sim/modelsim

make sim    # Batch mode — nhanh, CI-friendly
make gui    # GUI mode — mở waveform với màu sắc đã cấu hình
make do     # Portable: chạy qua simulate.do (không cần make)
make clean  # Xóa build artifacts
```

### 8.2 Vivado xsim

```bash
cd sim/xsim

make sim    # Batch simulation
make gui    # Mở Vivado waveform viewer
make clean
```

### 8.3 Cấu Hình Waveform (`wave.do` & `wave.tcl`)

Waveform được cấu hình theo 4 nhóm chức năng (Dividers) chuẩn hóa đồng bộ với các IP trong repo:

| Nhóm Divider | Tín hiệu | Định dạng / Màu sắc (ModelSim) | Ý nghĩa |
|---|---|---|---|
| **1. APB Interface** | `pclk`, `presetn`, `pready`<br>`psel`, `penable`, `pwrite`, `paddr`, `pwdata`, `pstrb`<br>`prdata`<br>`pslverr` | **Gold**<br>**Yellow** (Hex/Bin)<br>**Green** (Hex)<br>**Red** | Bus APB4 theo chuẩn ARM IHI0024E |
| **2. Internal Decode** | `w_access`, `w_addr_valid`, `w_write` | **Orange** | Tín hiệu giải mã điều kiện pha Access, địa chỉ hợp lệ và chốt ghi |
| **3. Register Bank** | `o_reg0` … `o_reg6`<br>`i_status` | **Cyan** (Hex)<br>**Magenta** (Hex) | Giá trị 7 thanh ghi R/W và thanh ghi trạng thái sống (Live Status) |
| **4. Verification** | `checks_run`, `error_count`<br>`last_read_data`, `last_read_error` | **Decimal**<br>**Green** / **Red** | Giám sát kết quả kiểm thử và scoreboard trong Testbench |

> *Ghi chú: ModelSim/Questa sử dụng [`sim/modelsim/wave.do`](../sim/modelsim/wave.do) tự động zoom `0 ns - 380 ns`. Vivado xsim sử dụng [`sim/xsim/wave.tcl`](../sim/xsim/wave.tcl).*

---

## 9. Timing & Synthesis

### 9.1 Timing Constraint

```tcl
# constraints/timing.xdc
create_clock -name pclk -period 10.000 [get_ports pclk]
# Target: 100 MHz
```

### 9.2 Timing Paths Chính

| Path | From | To | Loại |
|------|------|----|------|
| Write register | `pclk` cạnh lên | `r_regs[n][7:0]` | Sequential |
| Read data | `r_regs[n]` | `prdata` | Combinational |
| Error detect | `paddr` | `pslverr` | Combinational |
| PREADY | — | `pready` | Constant `1'b1` |

**Critical path** thường là Read MUX → `PRDATA`: từ register output qua case decoder
ra `prdata`. Với 8 địa chỉ, path này rất nông — dễ meet timing ở 100 MHz.

### 9.3 Resource Estimate (FPGA)

| Resource | Ước tính |
|----------|----------|
| Flip-Flops | 7 × 32 = **224 FF** (register bank) |
| LUTs | ~50–80 LUT (decode + MUX) |
| DSP / BRAM | 0 |

---

## 10. Vị Trí trong Study Plan

### 10.1 Trong `rtl-advanced-projects`

```
01_ip_blocks/
├── async_fifo_gray/     ← Học trước: CDC, Gray code
├── apb_slave/           ← ĐÂY — register map, protocol slave
├── axi4_lite_slave/     ← Học sau: phức tạp hơn (5 channels)
├── i2c_master_core/
└── spi_flash_controller/
```

### 10.2 Kết Nối với Mini SoC (Phase cuối)

APB Slave là **building block** của `05_mini_soc/apb_subsystem/`:

```
05_mini_soc/
└── rtl/
    ├── soc_top.v
    ├── cpu_core/              ← RISC-V / simple CPU (AXI Master)
    ├── apb_subsystem/
    │   ├── axi_to_apb_bridge.v    ← APB Master (IP có sẵn hoặc tự viết)
    │   ├── apb_slave_gpio.v       ← apb_slave + GPIO logic
    │   ├── apb_slave_uart.v       ← apb_slave + UART control regs
    │   └── apb_slave_timer.v      ← apb_slave + Timer control
    └── memory_subsystem/
```

`apb_slave.v` là **template tái sử dụng** — logic register bank + address decode
+ byte strobe sẽ được lặp lại trong mỗi peripheral của SoC, chỉ thay đổi
phần application logic.

---

## 11. Câu Hỏi Phỏng Vấn Thường Gặp

### Q1: Tại sao PREADY luôn = 1 trong design này?

**A**: Design này là zero-wait-state slave — register reads và writes hoàn thành
trong cùng Access phase. Nếu muốn insert wait states (ví dụ: slave cần thêm
thời gian xử lý), giữ `PREADY=0` cho đến khi sẵn sàng, sau đó `PREADY=1`.

---

### Q2: Sự khác biệt giữa read-only STATUS và R/W register là gì?

**A**:
- **R/W register** (`r_regs[n]`): Giá trị lưu trong flip-flop, thay đổi khi host write.
- **STATUS** (`0x1C`): Kết nối trực tiếp từ `i_status` — là **wire** từ hardware bên
  ngoài (interrupt flags, busy signals...). Host chỉ có thể đọc, không thể thay đổi.

---

### Q3: Điều gì xảy ra nếu write vào STATUS register (0x1C)?

**A**: Transfer hoàn thành bình thường (`PSLVERR=0`, `PREADY=1`), nhưng giá trị
`i_status` không thay đổi. Địa chỉ `0x1C` hợp lệ nên không báo lỗi, nhưng
`w_write` kiểm tra `paddr[4:2] < 3'd7` loại trừ index 7 (STATUS) khỏi write path.

---

### Q4: Tại sao PRDATA là combinational thay vì registered?

**A**: APB4 spec yêu cầu `PRDATA` hợp lệ **trong cùng Access phase** — tức ngay
khi `PENABLE=1`. Nếu dùng registered output, data đến chậm hơn 1 cycle, vi phạm
protocol. Nhược điểm: combinational path có thể dài hơn, nhưng với 8 register
thì không đáng ngại ở 100 MHz.

---

### Q5: Byte strobe hoạt động như thế nào?

**A**: `PSTRB[n]=1` cho phép ghi byte lane `n`. Vòng lặp trong RTL chạy 4 lần
(byte 0–3), mỗi lần kiểm tra `PSTRB[r_byte]` trước khi ghi. Cú pháp
`[r_byte*8 +: 8]` là part-select với width cố định = 8 bit — chuẩn để access
byte lane trong Verilog synthesis.

---

### Q6: Làm sao phát hiện misaligned access?

**A**: Kiểm tra `paddr[1:0] == 2'b00` — địa chỉ 32-bit phải chia hết cho 4.
Ví dụ `0x02` có `paddr[1:0] = 2'b10`, vi phạm → `w_addr_valid=0` → `PSLVERR=1`,
không ghi dữ liệu vào register nào.

---

## 12. Tài Liệu Tham Khảo (References)

1. **ARM AMBA® APB Architecture Specification (ARM IHI 0024E, Issue E.b)** — Đặc tả giao thức chuẩn chính thức phát hành bởi ARM Limited.
2. **ARM AMBA Protocol Overview** — Tài liệu hướng dẫn phân cấp hệ thống bus on-chip (AXI, AHB, APB).
3. **Module Implementation & Verification Sources:**
   * RTL Source: [`rtl/apb_slave.v`](../rtl/apb_slave.v)
   * Verification Testbench: [`sim/apb_slave_tb.v`](../sim/apb_slave_tb.v)
   * Test Plan Contract: [`docs/test_plan.md`](test_plan.md)
   * Constraints File: [`constraints/timing.xdc`](../constraints/timing.xdc)
   * Quick-Start Guide: [`README.md`](../README.md)
