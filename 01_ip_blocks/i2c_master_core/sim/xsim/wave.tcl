# wave.tcl - Vivado xsim waveform configuration for i2c_master_core

log_wave -recursive /
set TB      i2c_master_core_tb
set WRAPPER /$TB/dut
set CORE    $WRAPPER/u_i2c_core

add_wave_divider "APB Interface"
add_wave -name "pclk"              /$TB/r_pclk
add_wave -name "presetn"           /$TB/r_presetn
add_wave -name "psel"              /$TB/r_psel
add_wave -name "penable"           /$TB/r_penable
add_wave -name "pwrite"            /$TB/r_pwrite
add_wave -name "paddr"  -radix hex /$TB/r_paddr
add_wave -name "pwdata" -radix hex /$TB/r_pwdata
add_wave -name "prdata" -radix hex /$TB/w_prdata
add_wave -name "pready"            /$TB/w_pready

add_wave_divider "Software Registers and Status"
add_wave -name "clk_div"     -radix dec $WRAPPER/r_clk_div_val
add_wave -name "rw"                     $WRAPPER/r_rw
add_wave -name "target_addr" -radix hex $WRAPPER/r_target_addr
add_wave -name "tx_data"     -radix hex $WRAPPER/r_tx_data
add_wave -name "rx_data"     -radix hex $WRAPPER/w_rx_data
add_wave -name "start_req"               $WRAPPER/w_start_request
add_wave -name "start_pulse"             $WRAPPER/w_start_pulse
add_wave -name "BUSY"                    $WRAPPER/w_busy
add_wave -name "DONE"                    $WRAPPER/r_done_status
add_wave -name "ACK_ERROR"               $WRAPPER/w_ack_error

add_wave_divider "Resolved I2C Bus"
add_wave -name "master_scl_low" /$TB/w_scl_drive_low
add_wave -name "master_sda_low" /$TB/w_sda_drive_low
add_wave -name "slave_sda_low"  /$TB/r_slave_sda_low
add_wave -name "SCL"            /$TB/w_scl_bus
add_wave -name "SDA"            /$TB/w_sda_bus

add_wave_divider "Core FSM and Datapath"
add_wave -name "state"         -radix unsigned $CORE/r_state
add_wave -name "high_phase"                    $CORE/r_high_phase
add_wave -name "bit_index"     -radix unsigned $CORE/r_bit_index
add_wave -name "div_count"     -radix unsigned $CORE/r_div_count
add_wave -name "latched_div"   -radix unsigned $CORE/r_clk_div
add_wave -name "address_frame" -radix hex      $CORE/r_address_frame
add_wave -name "tx_latched"    -radix hex      $CORE/r_tx_latched
add_wave -name "rx_shift"      -radix hex      $CORE/r_rx_shift
add_wave -name "core_busy"                     $CORE/o_busy
add_wave -name "core_done"                     $CORE/o_done

add_wave_divider "Verification"
add_wave -name "test_number"   -radix dec /$TB/r_test_number
add_wave -name "error_count"   -radix dec /$TB/r_error_count
add_wave -name "stop_count"    -radix dec /$TB/r_stop_count
add_wave -name "slave_address" -radix hex /$TB/r_slave_address_frame
add_wave -name "slave_wdata"   -radix hex /$TB/r_slave_write_data

run all
