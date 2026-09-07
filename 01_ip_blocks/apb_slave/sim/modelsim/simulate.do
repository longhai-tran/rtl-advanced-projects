quietly set RTL ../../rtl
quietly set SIM ..
if {[file isdirectory work]} {vdel -all -lib work}
vlib work
vmap work work
vlog -timescale "1ns/1ps" $RTL/apb_slave.v $SIM/apb_slave_tb.v
vsim -t 1ps apb_slave_tb
onerror {quit -f -code 1}
run -all
quit -f -code 0
