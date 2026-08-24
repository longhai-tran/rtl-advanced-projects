# wave.tcl — Vivado xsim waveform configuration for async_fifo_gray

log_wave -recursive /
set TB async_fifo_tb

add_wave_divider "Write Domain"
add_wave /$TB/r_wr_clk
add_wave /$TB/r_wr_rst_n
add_wave /$TB/r_wr_en
add_wave -name "wr_data"  -radix hex /$TB/r_wr_data
add_wave -name "FULL"               /$TB/w_full
add_wave -name "wr_count" -radix dec /$TB/w_wr_count

add_wave_divider "Read Domain"
add_wave /$TB/r_rd_clk
add_wave /$TB/r_rd_rst_n
add_wave /$TB/r_rd_en
add_wave -name "rd_data"  -radix hex /$TB/w_rd_data
add_wave -name "EMPTY"              /$TB/w_empty
add_wave -name "rd_count" -radix dec /$TB/w_rd_count

add_wave_divider "CDC Pointers"
add_wave -name "wr_gray"      -radix hex /$TB/dut/w_wr_gray
add_wave -name "rd_gray"      -radix hex /$TB/dut/w_rd_gray
add_wave -name "wr_gray_sync" -radix hex /$TB/dut/w_wr_gray_sync
add_wave -name "rd_gray_sync" -radix hex /$TB/dut/w_rd_gray_sync

add_wave_divider "Verification"
add_wave -name "err_count" -radix dec /$TB/err

run all
