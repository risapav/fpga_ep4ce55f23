`ifndef FRAMEBUFFER_PKG_SV
`define FRAMEBUFFER_PKG_SV

// framebuffer_pkg.sv
// Verzia: 1.0
// Dátum: 25.10.2025
package framebuffer_pkg;

    // Definuje operačné režimy pre framebuffer a súvisiace moduly.
    typedef enum logic [1:0] {
        NORMAL               = 2'b00, // 0: Plná funkčnosť s AXI-Stream a double bufferingom
        PASSTHROUGH          = 2'b01, // 1: Jednoduché premostenie vstupu na výstup
        BRAM_BACKEND         = 2'b10, // 2: Plná logika, ale s internou BRAM namiesto SDRAM
        DIAG_WRITE_READ_TEST = 2'b11  // 3: Diagnostický test oddeleného zápisu a čítania
    } op_mode_e;

endpackage

`endif
