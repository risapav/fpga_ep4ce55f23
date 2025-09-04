module top (
    // Clock & Reset
    input logic CLOCK_50,
    input logic RESET_N,

    // HDMI (TMDS výstup + I2C konfigurácia)
    output logic HDMI_SCL,
    inout  logic HDMI_SDA,
    output logic HDMI_CEC,
    output logic TMDS_TX2_P,
    output logic TMDS_TX2_N,
    output logic TMDS_TX1_P,
    output logic TMDS_TX1_N,
    output logic TMDS_TX0_P,
    output logic TMDS_TX0_N,
    output logic TMDS_CLK_P,
    output logic TMDS_CLK_N,

    // Ethernet RMII (LAN8720A)
    input  logic ETH_REF_CLK,
    inout  logic ETH_MDIO,
    output logic ETH_MDC,
    input  logic ETH_CRS_DV,
    input  logic ETH_RXD0,
    input  logic ETH_RXD1,
    output logic ETH_TX_EN,
    output logic ETH_TXD0,
    output logic ETH_TXD1,

    // SD Card (SPI Mode)
    output logic SD_CS,
    output logic SD_CLK,
    output logic SD_MOSI,
    input  logic SD_MISO,

    // Kamera OV5640 (DVP + I2C)
    output logic CAM_SCL,
    inout  logic CAM_SDA,
    input  logic CAM_PCLK,
    input  logic CAM_VSYNC,
    input  logic CAM_HREF,
    output logic CAM_XCLK,
    output logic CAM_RST_N,
    output logic CAM_PWDN,
    input  logic CAM_D7,
    input  logic CAM_D6,
    input  logic CAM_D5,
    input  logic CAM_D4,
    input  logic CAM_D3,
    input  logic CAM_D2,
    input  logic CAM_D1,
    input  logic CAM_D0
);

    // -------------------------------------------------------------
    // Tu implementuj svoju logiku pre jednotlivé periférie
    // Napr. HDMI výstup, Ethernet komunikáciu, SD SPI, kameru atď.
    // -------------------------------------------------------------

    // Príklad: inicializácia HDMI_CEC na 0
    assign HDMI_CEC = 1'b0;

    // Príklad: kamera reset (aktívne nízka)
    assign CAM_RST_N = 1'b1;
    assign CAM_PWDN  = 1'b0;

    // SD card default
    assign SD_CS   = 1'b1;
    assign SD_CLK  = 1'b0;
    assign SD_MOSI = 1'b0;

    // Ethernet default hodnoty (pokiaľ nie je logika)
    assign ETH_MDC    = 1'b0;
    assign ETH_TX_EN  = 1'b0;
    assign ETH_TXD0   = 1'b0;
    assign ETH_TXD1   = 1'b0;

    // Kamera hodiny
    assign CAM_XCLK = CLOCK_50;  // Alebo PLL generovaný 24 MHz clock

endmodule
