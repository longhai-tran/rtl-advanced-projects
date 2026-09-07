# simulate.do
quietly set RTL ../../rtl
quietly set SIM ..
if {![file isdirectory work]} {vlib work}
vlog -timescale "1ns/1ps" $RTL/i2c_master_core.v $RTL/i2c_master_apb.v $SIM/i2c_master_core_tb.v
vsim -t 1ps i2c_master_core_tb
log -r /*
run -all
quit -f
