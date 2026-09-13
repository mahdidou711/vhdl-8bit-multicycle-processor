## proc8_de1: TimeQuest constraints
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

## core_clk is the register output toggled by proc8_de1_top every
## CORE_CLK_HALF_PERIOD = 3_125_000 CLOCK_50 cycles: 50 MHz / 6_250_000 = 8 Hz.
create_generated_clock -name core_clk -source [get_ports {CLOCK_50}] -divide_by 6250000 [get_registers {core_clk}]

## KEY0 is an asynchronous pushbutton. Its only loads are the asynchronous
## clears of the two reset synchronizer registers; all internal reset releases
## come from the synchronizer output and remain timed against CLOCK_50.
set_false_path -from [get_ports {KEY0}]
