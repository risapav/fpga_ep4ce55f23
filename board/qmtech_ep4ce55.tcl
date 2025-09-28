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
if { [info exists USE_7_SEG_DISPLAY] && $USE_7_SEG_DISPLAY == 1 } {
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
}

# --- Onboard LEDs ---
if { [info exists USE_LEDS] && $USE_LEDS == 1 } {
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED[5..0]
  set_location_assignment PIN_A6 -to LED[5]
  set_location_assignment PIN_B7 -to LED[4]
  set_location_assignment PIN_A7 -to LED[3]
  set_location_assignment PIN_B8 -to LED[2]
  set_location_assignment PIN_A8 -to LED[1]
  set_location_assignment PIN_E4 -to LED[0]
}

# --- Push Buttons ---
if { [info exists USE_BUTTONS] && $USE_BUTTONS == 1 } {
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BSW[5..0]
  set_location_assignment PIN_B9   -to BSW[5]
  set_location_assignment PIN_A9   -to BSW[4]
  set_location_assignment PIN_B10  -to BSW[3]
  set_location_assignment PIN_A10  -to BSW[2]
  set_location_assignment PIN_AA13 -to BSW[1]
  set_location_assignment PIN_Y13  -to BSW[0]
}

# --- VGA Output ---
if { [info exists USE_VGA] && $USE_VGA == 1 } {
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
}

# --- SDRAM Interface (HY57V641620FTP-6 compatible) W9825G6KH-6 ---
if { [info exists USE_SDRAM] && $USE_SDRAM == 1 } {
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_DQ[15..0]
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_ADDR[12..0]
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_BA[1..0]
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_CAS_N
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_CKE
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_CLK
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_CS_N
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_WE_N
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_RAS_N
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_UDQM
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_LDQM

  set_location_assignment PIN_V11  -to SDRAM_DQ[15]
  set_location_assignment PIN_W10  -to SDRAM_DQ[14]
  set_location_assignment PIN_Y10  -to SDRAM_DQ[13]
  set_location_assignment PIN_V10  -to SDRAM_DQ[12]
  set_location_assignment PIN_V9   -to SDRAM_DQ[11]
  set_location_assignment PIN_Y8   -to SDRAM_DQ[10]
  set_location_assignment PIN_W8   -to SDRAM_DQ[9]
  set_location_assignment PIN_Y7   -to SDRAM_DQ[8]
  set_location_assignment PIN_AB5  -to SDRAM_DQ[7]
  set_location_assignment PIN_AA7  -to SDRAM_DQ[6]
  set_location_assignment PIN_AB7  -to SDRAM_DQ[5]
  set_location_assignment PIN_AA8  -to SDRAM_DQ[4]
  set_location_assignment PIN_AB8  -to SDRAM_DQ[3]
  set_location_assignment PIN_AA9  -to SDRAM_DQ[2]
  set_location_assignment PIN_AB9  -to SDRAM_DQ[1]
  set_location_assignment PIN_AA10 -to SDRAM_DQ[0]

  set_location_assignment PIN_V6   -to SDRAM_ADDR[12]
  set_location_assignment PIN_Y4   -to SDRAM_ADDR[11]
  set_location_assignment PIN_W1   -to SDRAM_ADDR[10]
  set_location_assignment PIN_V5   -to SDRAM_ADDR[9]
  set_location_assignment PIN_Y3   -to SDRAM_ADDR[8]
  set_location_assignment PIN_AA1  -to SDRAM_ADDR[7]
  set_location_assignment PIN_Y2   -to SDRAM_ADDR[6]
  set_location_assignment PIN_V4   -to SDRAM_ADDR[5]
  set_location_assignment PIN_V3   -to SDRAM_ADDR[4]
  set_location_assignment PIN_U1   -to SDRAM_ADDR[3]
  set_location_assignment PIN_U2   -to SDRAM_ADDR[2]
  set_location_assignment PIN_V1   -to SDRAM_ADDR[1]
  set_location_assignment PIN_V2   -to SDRAM_ADDR[0]

  set_location_assignment PIN_W2   -to SDRAM_BA[1]
  set_location_assignment PIN_Y1   -to SDRAM_BA[0]

  set_location_assignment PIN_AA4 -to SDRAM_CAS_N
  set_location_assignment PIN_W6 -to SDRAM_CKE
  set_location_assignment PIN_Y6 -to SDRAM_CLK
  set_location_assignment PIN_AA3 -to SDRAM_CS_N


  set_location_assignment PIN_AB4 -to SDRAM_WE_N
  set_location_assignment PIN_AB3 -to SDRAM_RAS_N
  set_location_assignment PIN_W7 -to SDRAM_UDQM
  set_location_assignment PIN_AA5 -to SDRAM_LDQM
}

# --- UART (USB Bridge) ---
if { [info exists USE_UART] && $USE_UART == 1 } {
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_RX
  set_location_assignment PIN_J2 -to UART_RX
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to UART_TX
  set_location_assignment PIN_J1 -to UART_TX
}

#--- Ethernet (LAN8720A – RMII interface) ---
if { [info exists USE_ETH] && $USE_ETH == 1 } {
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_REF_CLK
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_MDIO
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_MDC
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_CRS_DV
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_RXD0
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_RXD1
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_TX_EN
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_TXD0
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ETH_TXD1

  set_location_assignment PIN_E13 -to ETH_REF_CLK
  set_location_assignment PIN_F13 -to ETH_MDIO
  set_location_assignment PIN_G13 -to ETH_MDC
  set_location_assignment PIN_D13 -to ETH_CRS_DV
  set_location_assignment PIN_E14 -to ETH_RXD0
  set_location_assignment PIN_F14 -to ETH_RXD1
  set_location_assignment PIN_G14 -to ETH_TX_EN
  set_location_assignment PIN_H14 -to ETH_TXD0
  set_location_assignment PIN_J14 -to ETH_TXD1
}

#--- SD Card (SPI Mode) ---
if { [info exists USE_SDC] && $USE_SDC == 1 } {
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SD_CS
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SD_CLK
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SD_MOSI
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SD_MISO
  set_location_assignment PIN_F19 -to SD_CS
  set_location_assignment PIN_E18 -to SD_CLK
  set_location_assignment PIN_C19 -to SD_MOSI
  set_location_assignment PIN_B19 -to SD_MISO
}

#--- Kamera OV5640 (typicky cez SCCB/I2C + DVP rozhranie) ---
if { [info exists USE_CAM] && $USE_CAM == 1 } {
  # Nastavenie I/O štandardu pre celú dátovú zbernicu naraz
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_D[7..0]
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_SCL
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_SDA
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_PCLK
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_VSYNC
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_HREF
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_XCLK
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_RST_N
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CAM_PWDN

  set_location_assignment PIN_T17 -to CAM_SCL
  set_location_assignment PIN_R17 -to CAM_SDA
  set_location_assignment PIN_T16 -to CAM_PCLK
  set_location_assignment PIN_P16 -to CAM_VSYNC
  set_location_assignment PIN_N16 -to CAM_HREF
  set_location_assignment PIN_M16 -to CAM_XCLK
  set_location_assignment PIN_L16 -to CAM_RST_N
  set_location_assignment PIN_K16 -to CAM_PWDN

  # DVP Data [D7:D0]
  set_location_assignment PIN_T15 -to CAM_D7
  set_location_assignment PIN_R15 -to CAM_D6
  set_location_assignment PIN_P15 -to CAM_D5
  set_location_assignment PIN_N15 -to CAM_D4
  set_location_assignment PIN_M15 -to CAM_D3
  set_location_assignment PIN_L15 -to CAM_D2
  set_location_assignment PIN_K15 -to CAM_D1
  set_location_assignment PIN_J15 -to CAM_D0
}

# ========================================================================== #
#             PASS TCL VARIABLES TO SYSTEMVERILOG AS MACROS                  #
# ========================================================================== #
# This section creates Verilog macros (`define) based on the settings from
# the main .qsf file, allowing for conditional compilation in top.sv.

# Zoznam všetkých konfigurovateľných periférií
set peripheral_list {
    7_SEG_DISPLAY
    LEDS
    BUTTONS
    VGA
    SDRAM
    UART
    ETH
    SDC
    CAM
}

# Cyklus, ktorý prejde zoznam a automaticky vytvorí makrá
foreach peripheral $peripheral_list {
    set var_name "USE_${peripheral}"
    if { [info exists $var_name] && [set $var_name] == 1 } {
        set_global_assignment -name VERILOG_MACRO "${var_name}=1"
        post_message "INFO: Passing macro to Verilog: ${var_name}=1"
    }
}
