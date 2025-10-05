# ===================================================================
# Finálny a Explicitný SDC Súbor pre HDMI Projekt (Verzia 4.0)
# ===================================================================

# 1. Definuj hlavný vstupný hodinový signál (50 MHz)
create_clock -period 20.0 -name SYS_CLK [get_ports {SYS_CLK}]


# 2. MANUÁLNE A EXPLICITNE definuj hodiny generované z PLL.
# Použijeme parameter '-name', aby sme im dali jednoduché a predvídateľné mená.
# Cesty k pinom sú z vášho pôvodného SDC, kde boli správne.
# 800x600 pixel_clk 4 /5, pixel_clk5 4 /1
# 680x480 pixel_clk 87 /160, pixel_clk5 87 /32

create_generated_clock -name pixel_clk \
  -source [get_ports {SYS_CLK}] \
  -multiply_by 4 -divide_by 5 \
  [get_pins {clkpll_inst|altpll_component|auto_generated|pll1|clk[0]}]

create_generated_clock -name pixel_clk5 \
  -source [get_ports {SYS_CLK}] \
  -multiply_by 4 -divide_by 1 \
  [get_pins {clkpll_inst|altpll_component|auto_generated|pll1|clk[1]}]

create_generated_clock -name clk_100mhz \
  -source [get_ports {SYS_CLK}] \
  -multiply_by 2 -divide_by 1 \
  [get_pins {clkpll_inst|altpll_component|auto_generated|pll1|clk[2]}]

create_generated_clock -name clk_100mhz_shifted \
  -source [get_ports {SYS_CLK}] \
  -multiply_by 2 \
  -divide_by 1 \
  -offset -2.5 \
  [get_pins {clkpll_inst|altpll_component|auto_generated|pll1|clk[3]}]

# 3. KĽÚČOVÝ KROK: Definuj asynchrónne skupiny s použitím nami definovaných mien.
# Tento príkaz teraz bude fungovať, pretože hodiny 'pixel_clk' a 'pixel_clk5'
# sme v kroku 2 explicitne vytvorili a pomenovali.
set_clock_groups -asynchronous \
  -group [get_clocks {SYS_CLK}] \
  -group [get_clocks {pixel_clk pixel_clk5 clk_100mhz clk_100mhz_shifted}]


# 4. Pridaj príkaz pre odvodenie neistoty hodín.
# Teraz, keď sú všetky hodiny a ich vzťahy správne definované,
# tento príkaz by mal prebehnúť bez kritických varovaní.
derive_clock_uncertainty