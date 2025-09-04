# ===================================================================
# Kompletný SDC Súbor pre VGA/SDRAM Projekt
# ===================================================================

# 1. Definuje hlavný 50 MHz hodinový signál (perióda 20 ns)
create_clock -name "SYS_CLK" -period 20.0 [get_ports {SYS_CLK}]

# 2. Povie Quartusu, aby si odvodil neistotu hodín (jitter, atď.)
derive_clock_uncertainty

# pixel_clk
create_generated_clock -name pixel_clk -source [get_ports {SYS_CLK}] -multiply_by 119 -divide_by 50 [get_pins {clkpll_inst|altpll_component|auto_generated|pll1|clk[0]}]
