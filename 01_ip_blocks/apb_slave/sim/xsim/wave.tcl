# wave.tcl - Vivado xsim waveform configuration for apb_slave

log_wave -recursive /
set TB  apb_slave_tb
set DUT /$TB/dut

# =============================================================================
# 1. APB Bus Interface
# =============================================================================
add_wave_divider "APB Interface"
add_wave -name "pclk"              /$TB/r_pclk
add_wave -name "presetn"           /$TB/r_presetn
add_wave -name "psel"              /$TB/r_psel
add_wave -name "penable"           /$TB/r_penable
add_wave -name "pwrite"            /$TB/r_pwrite
add_wave -name "paddr"   -radix hex /$TB/r_paddr
add_wave -name "pwdata"  -radix hex /$TB/r_pwdata
add_wave -name "pstrb"   -radix bin /$TB/r_pstrb
add_wave -name "prdata"  -radix hex /$TB/w_prdata
add_wave -name "pready"            /$TB/w_pready
add_wave -name "pslverr"           /$TB/w_pslverr

# =============================================================================
# 2. Internal Control & Decode
# =============================================================================
add_wave_divider "Internal Decode"
add_wave -name "w_access"          $DUT/w_access
add_wave -name "w_addr_valid"      $DUT/w_addr_valid
add_wave -name "w_write"           $DUT/w_write

# =============================================================================
# 3. Register Bank & Live Status
# =============================================================================
add_wave_divider "Register Bank"
add_wave -name "o_reg0"  -radix hex /$TB/w_reg0
add_wave -name "o_reg1"  -radix hex /$TB/w_reg1
add_wave -name "o_reg2"  -radix hex /$TB/w_reg2
add_wave -name "o_reg3"  -radix hex /$TB/w_reg3
add_wave -name "o_reg4"  -radix hex /$TB/w_reg4
add_wave -name "o_reg5"  -radix hex /$TB/w_reg5
add_wave -name "o_reg6"  -radix hex /$TB/w_reg6
add_wave -name "i_status" -radix hex /$TB/r_status

# =============================================================================
# 4. Testbench & Scoreboard
# =============================================================================
add_wave_divider "Verification"
add_wave -name "checks_run"       -radix dec /$TB/r_tests
add_wave -name "error_count"      -radix dec /$TB/r_errors
add_wave -name "last_read_data"   -radix hex /$TB/r_read_data
add_wave -name "last_read_error"             /$TB/r_read_error

run all
