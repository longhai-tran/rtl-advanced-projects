# timing.xdc — Async FIFO Gray: timing constraints for Vivado
# Two asynchronous clock domains

# Write clock (100 MHz)
create_clock -period 10.000 -name wr_clk [get_ports i_wr_clk]

# Read clock (66 MHz — independent)
create_clock -period 15.000 -name rd_clk [get_ports i_rd_clk]

# Declare both clocks as asynchronous — no timing paths between domains
set_clock_groups -asynchronous \
    -group [get_clocks wr_clk] \
    -group [get_clocks rd_clk]

# Mark synchronizer FFs with ASYNC_REG (already in RTL via attribute,
# this XDC ensures proper placement)
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *u_sync_*/*r_ff*}]
