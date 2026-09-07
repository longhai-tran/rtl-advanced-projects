# Reference constraint for the default 100 MHz APB/core clock used by the TB.
# Override the period at integration if pclk runs at another frequency.
create_clock -name pclk -period 10.000 [get_ports pclk]

# SDA/SCL board delays depend on pull-ups, bus capacitance, and the selected I2C
# speed grade. Constrain those paths at the SoC/board top level; no false paths
# are declared here.
