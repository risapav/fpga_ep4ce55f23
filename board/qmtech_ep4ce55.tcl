# ============================================================================ #
#                  QMTECH EP4CE55F23 Board Definition File                     #
# ============================================================================ #
# This file contains all static pin assignments and settings for the board.
# It should not be edited unless the board hardware itself is modified.
# This file is sourced by the main project .qsf file.
# ---------------------------------------------------------------------------- #

# --- Global Assignments ---
set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE55F23C8
set_global_assignment -name DEVICE_FILTER_PACKAGE FBGA
set_global_assignment -name DEVICE_FILTER_PIN_COUNT 484
set_global_assignment -name DEVICE_FILTER_SPEED_GRADE 8
set_global_assignment -name VERILOG_INPUT_VERSION SystemVerilog_2005
set_instance_assignment -name PARTITION_HIERARCHY root_partition -to | -section_id Top

# --- Configuration Pins ---
set_location_assignment PIN_D1  -to ~ALTERA_ASDO_DATA1~
set_location_assignment PIN_E2  -to ~ALTERA_FLASH_nCE_nCSO~
set_location_assignment PIN_K2  -to ~ALTERA_DCLK~
set_location_assignment PIN_K1  -to ~ALTERA_DATA0~
set_location_assignment PIN_K22 -to ~ALTERA_nCEO~

# --- Clock and Reset ---
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SYS_CLK
set_location_assignment PIN_T2 -to SYS_CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to RESET_N
set_location_assignment PIN_W13 -to RESET_N

# --- 7-Segment LED Display ---
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SMG_SEG[7..0]
set_location_assignment PIN_A4 -to SMG_SEG[7]
set_location_assignment PIN_B1 -to SMG_SEG[6]
set_location_assignment PIN_B4 -to SMG_SEG[5]
set_location_assignment PIN_A5 -to SMG_SEG[4]
set_location_assignment PIN_C3 -to SMG_SEG[3]
set_location_assignment PIN_A3 -to SMG_SEG[2]
set_location_assignment PIN_B2 -to SMG_SEG[1]
set_location_assignment PIN_C4 -to SMG_SEG[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SMG_DIG[2..0]
set_location_assignment PIN_B6 -to SMG_DIG[2]
set_location_assignment PIN_B3 -to SMG_DIG[1]
set_location_assignment PIN_B5 -to SMG_DIG[0]

# --- Onboard LEDs ---
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[5..0]
set_location_assignment PIN_A6 -to LED[5]
set_location_assignment PIN_B7 -to LED[4]
set_location_assignment PIN_A7 -to LED[3]
set_location_assignment PIN_B8 -to LED[2]
set_location_assignment PIN_A8 -to LED[1]
set_location_assignment PIN_E4 -to LED[0]

# --- Push Buttons ---
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BSW[5..0]
set_location_assignment PIN_B9   -to BSW[5]
set_location_assignment PIN_A9   -to BSW[4]
set_location_assignment PIN_B10  -to BSW[3]
set_location_assignment PIN_A10  -to BSW[2]
set_location_assignment PIN_AA13 -to BSW[1]
set_location_assignment PIN_Y13  -to BSW[0]

# --- VGA Output ---
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_R[4..0]
set_location_assignment PIN_N20 -to VGA_R[4]
set_location_assignment PIN_B21 -to VGA_R[3]
set_location_assignment PIN_M20 -to VGA_R[2]
set_location_assignment PIN_N19 -to VGA_R[1]
set_location_assignment PIN_M19 -to VGA_R[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_G[5..0]
set_location_assignment PIN_D22 -to VGA_G[5]
set_location_assignment PIN_E21 -to VGA_G[4]
set_location_assignment PIN_C22 -to VGA_G[3]
set_location_assignment PIN_D21 -to VGA_G[2]
set_location_assignment PIN_C21 -to VGA_G[1]
set_location_assignment PIN_B22 -to VGA_G[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_B[4..0]
set_location_assignment PIN_H21 -to VGA_B[4]
set_location_assignment PIN_H22 -to VGA_B[3]
set_location_assignment PIN_F21 -to VGA_B[2]
set_location_assignment PIN_F22 -to VGA_B[1]
set_location_assignment PIN_E22 -to VGA_B[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_HS
set_location_assignment PIN_J21 -to VGA_HS
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_VS
set_location_assignment PIN_J22 -to VGA_VS

# --- SDRAM Interface ---
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to DRAM_DQ[15..0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to DRAM_ADDR[12..0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to DRAM_BA[1..0]
set_location_assignment PIN_V11  -to DRAM_DQ[15]
# ... (všetky ostatné DRAM priradenia) ...
set_location_assignment PIN_AA5 -to DRAM_LDQM

# --- UART (USB Bridge) ---
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_RX
set_location_assignment PIN_J2 -to UART_RX
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_TX
set_location_assignment PIN_J1 -to UART_TX
