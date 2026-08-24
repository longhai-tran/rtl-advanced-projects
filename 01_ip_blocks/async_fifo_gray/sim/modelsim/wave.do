# wave.do — ModelSim waveform configuration for async_fifo_gray

set TB async_fifo_tb

onerror {resume}
quietly WaveActivateNextPane {} 0
configure wave -signalnamewidth 1

add wave -divider {Write Domain}
add wave -noupdate -color Gold   -label {wr_clk}    /$TB/r_wr_clk
add wave -noupdate -color Gold   -label {wr_rst_n}  /$TB/r_wr_rst_n
add wave -noupdate -color Gold   -label {wr_en}     /$TB/r_wr_en
add wave -noupdate -color Gold   -radix hex -label {wr_data}  /$TB/r_wr_data
add wave -noupdate -color Orange -label {FULL}      /$TB/w_full
add wave -noupdate -color Gold   -radix dec -label {wr_count} /$TB/w_wr_count

add wave -divider {Read Domain}
add wave -noupdate -color Cyan   -label {rd_clk}    /$TB/r_rd_clk
add wave -noupdate -color Cyan   -label {rd_rst_n}  /$TB/r_rd_rst_n
add wave -noupdate -color Cyan   -label {rd_en}     /$TB/r_rd_en
add wave -noupdate -color Cyan   -radix hex -label {rd_data}  /$TB/w_rd_data
add wave -noupdate -color Red    -label {EMPTY}     /$TB/w_empty
add wave -noupdate -color Cyan   -radix dec -label {rd_count} /$TB/w_rd_count

add wave -divider {CDC Pointers}
add wave -noupdate -color Yellow  -radix hex -label {wr_gray}      /$TB/dut/w_wr_gray
add wave -noupdate -color Yellow  -radix hex -label {rd_gray}      /$TB/dut/w_rd_gray
add wave -noupdate -color Magenta -radix hex -label {wr_gray_sync} /$TB/dut/w_wr_gray_sync
add wave -noupdate -color Magenta -radix hex -label {rd_gray_sync} /$TB/dut/w_rd_gray_sync

add wave -divider {Verification}
add wave -noupdate -radix decimal -label {err_count} /$TB/err

WaveRestoreZoom {0 ns} {500 ns}
configure wave -namecolwidth 160 -valuecolwidth 80
update
