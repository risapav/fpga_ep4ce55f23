module top_00 (
    // Clock & Reset
    input  logic SYS_CLK,
    input  logic RESET_N,

    // 7-Segment Display
    output logic [7:0] SMG_SEG,
    output logic [2:0] SMG_DIG,

    // LEDs
    output logic [5:0] LED,

    // Push Buttons
    input  logic [5:0] BSW,

    // VGA Output
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS,

    // SDRAM Interface
    inout  logic [15:0] DRAM_DQ,
    output logic [12:0] DRAM_ADDR,
    output logic [1:0]  DRAM_BA,
    output logic        DRAM_CAS_N,
    output logic        DRAM_CKE,
    output logic        DRAM_CLK,
    output logic        DRAM_CS_N,
    output logic        DRAM_WE_N,
    output logic        DRAM_RAS_N,
    output logic        DRAM_UDQM,
    output logic        DRAM_LDQM,

    // UART
    input  logic UART_RX,
    output logic UART_TX,

    // PMOD J10
    inout  logic J10_1,
    inout  logic J10_2,
    inout  logic J10_3,
    inout  logic J10_4,
    inout  logic J10_7,
    inout  logic J10_8,
    inout  logic J10_9,
    inout  logic J10_10,

    // PMOD J11
    inout  logic J11_1,
    inout  logic J11_2,
    inout  logic J11_3,
    inout  logic J11_4,
    inout  logic J11_7,
    inout  logic J11_8,
    inout  logic J11_9,
    inout  logic J11_10
);

    // ----------------------------------------------------------------------------
    // Example default behavior (static assignment for test purposes)
    // ----------------------------------------------------------------------------

    // Display number "0" on 7-segment, digit 0 active
    assign SMG_SEG = 8'b11000000;  // Common cathode: segments a-f on
    assign SMG_DIG = 3'b110;       // Activate digit 0

    // Light up LEDs
    assign LED = 6'b101010;

    // Send VGA test pattern (e.g., sync signals low)
    assign VGA_R  = 5'd0;
    assign VGA_G  = 6'd0;
    assign VGA_B  = 5'd0;
    assign VGA_HS = 1'b0;
    assign VGA_VS = 1'b0;

    // SDRAM signals - left unconnected for now
    assign DRAM_ADDR   = 13'd0;
    assign DRAM_BA     = 2'd0;
    assign DRAM_CAS_N  = 1'b1;
    assign DRAM_CKE    = 1'b1;
    assign DRAM_CLK    = SYS_CLK;
    assign DRAM_CS_N   = 1'b1;
    assign DRAM_WE_N   = 1'b1;
    assign DRAM_RAS_N  = 1'b1;
    assign DRAM_UDQM   = 1'b1;
    assign DRAM_LDQM   = 1'b1;

    // UART passthrough (loopback)
    assign UART_TX = UART_RX;

    // PMOD pins left floating
    assign J10_1  = 1'bz;
    assign J10_2  = 1'bz;
    assign J10_3  = 1'bz;
    assign J10_4  = 1'bz;
    assign J10_7  = 1'bz;
    assign J10_8  = 1'bz;
    assign J10_9  = 1'bz;
    assign J10_10 = 1'bz;

    assign J11_1  = 1'bz;
    assign J11_2  = 1'bz;
    assign J11_3  = 1'bz;
    assign J11_4  = 1'bz;
    assign J11_7  = 1'bz;
    assign J11_8  = 1'bz;
    assign J11_9  = 1'bz;
    assign J11_10 = 1'bz;

endmodule
