# wave.do - ModelSim/Questa waveform configuration for i2c_master_core

set TB      i2c_master_core_tb
set WRAPPER /$TB/dut
set CORE    $WRAPPER/u_i2c_core

onerror {resume}
quietly WaveActivateNextPane {} 0
configure wave -signalnamewidth 1

add wave -divider {APB Interface}
add wave -noupdate -color Gold   -label {pclk}    /$TB/r_pclk
add wave -noupdate -color Gold   -label {presetn} /$TB/r_presetn
add wave -noupdate -color Yellow -label {psel}    /$TB/r_psel
add wave -noupdate -color Yellow -label {penable} /$TB/r_penable
add wave -noupdate -color Yellow -label {pwrite}  /$TB/r_pwrite
add wave -noupdate -color Yellow -radix hex -label {paddr}  /$TB/r_paddr
add wave -noupdate -color Yellow -radix hex -label {pwdata} /$TB/r_pwdata
add wave -noupdate -color Green  -radix hex -label {prdata} /$TB/w_prdata
add wave -noupdate -color Gold   -label {pready}  /$TB/w_pready

add wave -divider {Software Registers and Status}
add wave -noupdate -color Cyan   -radix unsigned -label {clk_div}     $WRAPPER/r_clk_div_val
add wave -noupdate -color Cyan                   -label {rw}          $WRAPPER/r_rw
add wave -noupdate -color Cyan   -radix hex      -label {target_addr} $WRAPPER/r_target_addr
add wave -noupdate -color Cyan   -radix hex      -label {tx_data}     $WRAPPER/r_tx_data
add wave -noupdate -color Cyan   -radix hex      -label {rx_data}     $WRAPPER/w_rx_data
add wave -noupdate -color Yellow                 -label {start_req}   $WRAPPER/w_start_request
add wave -noupdate -color Yellow                 -label {start_pulse} $WRAPPER/w_start_pulse
add wave -noupdate -color Orange                 -label {BUSY}        $WRAPPER/w_busy
add wave -noupdate -color Green                  -label {DONE}        $WRAPPER/r_done_status
add wave -noupdate -color Red                    -label {ACK_ERROR}   $WRAPPER/w_ack_error

add wave -divider {Resolved I2C Bus}
add wave -noupdate -color Orange  -label {master_scl_low} /$TB/w_scl_drive_low
add wave -noupdate -color Orange  -label {master_sda_low} /$TB/w_sda_drive_low
add wave -noupdate -color Magenta -label {slave_sda_low}  /$TB/r_slave_sda_low
add wave -noupdate -color White   -label {SCL}            /$TB/w_scl_bus
add wave -noupdate -color White   -label {SDA}            /$TB/w_sda_bus

add wave -divider {Core FSM and Datapath}
add wave -noupdate -color Green  -radix unsigned -label {state}         $CORE/r_state
add wave -noupdate -color Yellow                 -label {high_phase}    $CORE/r_high_phase
add wave -noupdate -color Yellow -radix unsigned -label {bit_index}     $CORE/r_bit_index
add wave -noupdate -color Gold   -radix unsigned -label {div_count}     $CORE/r_div_count
add wave -noupdate -color Gold   -radix unsigned -label {latched_div}   $CORE/r_clk_div
add wave -noupdate -color Cyan   -radix hex      -label {address_frame} $CORE/r_address_frame
add wave -noupdate -color Cyan   -radix hex      -label {tx_latched}    $CORE/r_tx_latched
add wave -noupdate -color Cyan   -radix hex      -label {rx_shift}      $CORE/r_rx_shift
add wave -noupdate -color Orange                 -label {core_busy}     $CORE/o_busy
add wave -noupdate -color Green                  -label {core_done}     $CORE/o_done

add wave -divider {Verification}
add wave -noupdate -radix decimal -label {test_number}   /$TB/r_test_number
add wave -noupdate -radix decimal -label {error_count}   /$TB/r_error_count
add wave -noupdate -radix decimal -label {stop_count}    /$TB/r_stop_count
add wave -noupdate -radix hex     -label {slave_address} /$TB/r_slave_address_frame
add wave -noupdate -radix hex     -label {slave_wdata}   /$TB/r_slave_write_data

# T2 is the first complete I2C transaction after the APB register tests.
WaveRestoreZoom {250 ns} {2300 ns}
configure wave -namecolwidth 180 -valuecolwidth 90
update
