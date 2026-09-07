# wave.do - ModelSim/Questa waveform configuration for apb_slave

set TB  apb_slave_tb
set DUT /$TB/dut

onerror {resume}
quietly WaveActivateNextPane {} 0
configure wave -signalnamewidth 1

# =============================================================================
# 1. APB Bus Interface
# =============================================================================
add wave -divider {APB Interface}
add wave -noupdate -color Gold   -label {pclk}    /$TB/r_pclk
add wave -noupdate -color Gold   -label {presetn} /$TB/r_presetn
add wave -noupdate -color Yellow -label {psel}    /$TB/r_psel
add wave -noupdate -color Yellow -label {penable} /$TB/r_penable
add wave -noupdate -color Yellow -label {pwrite}  /$TB/r_pwrite
add wave -noupdate -color Yellow -radix hex -label {paddr}  /$TB/r_paddr
add wave -noupdate -color Yellow -radix hex -label {pwdata} /$TB/r_pwdata
add wave -noupdate -color Yellow -radix bin -label {pstrb}  /$TB/r_pstrb
add wave -noupdate -color Green  -radix hex -label {prdata} /$TB/w_prdata
add wave -noupdate -color Gold   -label {pready}  /$TB/w_pready
add wave -noupdate -color Red    -label {pslverr} /$TB/w_pslverr

# =============================================================================
# 2. Internal Control & Decode
# =============================================================================
add wave -divider {Internal Decode}
add wave -noupdate -color Orange -label {w_access}     $DUT/w_access
add wave -noupdate -color Orange -label {w_addr_valid} $DUT/w_addr_valid
add wave -noupdate -color Orange -label {w_write}      $DUT/w_write

# =============================================================================
# 3. Register Bank & Live Status
# =============================================================================
add wave -divider {Register Bank}
add wave -noupdate -color Cyan -radix hex -label {o_reg0} /$TB/w_reg0
add wave -noupdate -color Cyan -radix hex -label {o_reg1} /$TB/w_reg1
add wave -noupdate -color Cyan -radix hex -label {o_reg2} /$TB/w_reg2
add wave -noupdate -color Cyan -radix hex -label {o_reg3} /$TB/w_reg3
add wave -noupdate -color Cyan -radix hex -label {o_reg4} /$TB/w_reg4
add wave -noupdate -color Cyan -radix hex -label {o_reg5} /$TB/w_reg5
add wave -noupdate -color Cyan -radix hex -label {o_reg6} /$TB/w_reg6
add wave -noupdate -color Magenta -radix hex -label {i_status (live)} /$TB/r_status

# =============================================================================
# 4. Testbench & Scoreboard
# =============================================================================
add wave -divider {Verification}
add wave -noupdate -radix decimal -label {checks_run}   /$TB/r_tests
add wave -noupdate -radix decimal -label {error_count}  /$TB/r_errors
add wave -noupdate -color Green -radix hex -label {last_read_data}  /$TB/r_read_data
add wave -noupdate -color Red   -label {last_read_error} /$TB/r_read_error

# Zoom to cover the full simulation run (0 to 380 ns)
WaveRestoreZoom {0 ns} {380 ns}
configure wave -namecolwidth 180 -valuecolwidth 100
update
