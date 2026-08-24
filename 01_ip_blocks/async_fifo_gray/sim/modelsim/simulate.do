# simulate.do — Portable ModelSim/Questa runner for async_fifo_gray
# Usage (standalone, no Makefile needed):
#   vsim -c -do simulate.do

set MODULE async_fifo
set TOP    ${MODULE}_tb

# Clean stale library
if {[file exists work]} { vdel -all -lib work }
vlib work
vmap work work

# Auto-discover RTL + TB sources
set SOURCES [lsort [glob -nocomplain \
    ../../rtl/*.v   ../../rtl/*.sv \
    ../*.v          ../*.sv]]

if {[llength $SOURCES] == 0} {
    puts {[ERROR] No source files found in ../../rtl/ or ../}
    quit -f
}

foreach f $SOURCES { vlog -timescale "1ns/1ps" $f }

# Auto-detect: batch mode (CI / make do) vs interactive GUI
if {[info exists ::env(VSIM_BATCH)] || [catch {gui_is_open} result]} {
    vsim -c work.$TOP
    run -all
    quit -f
} else {
    vsim work.$TOP
    do wave.do
    run -all
}
