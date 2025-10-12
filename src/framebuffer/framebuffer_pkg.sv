`ifndef FRAMEBUFFER_PKG_SV
`define FRAMEBUFFER_PKG_SV

package framebuffer_pkg;

    // Definuje operačné režimy pre framebuffer a súvisiace moduly.
    typedef enum {
        NORMAL,               // 0: Plná funkčnosť s AXI-Stream a double bufferingom
        PASSTHROUGH,          // 1: Jednoduché premostenie vstupu na výstup
        BRAM_BACKEND,         // 2: Plná logika, ale s internou BRAM namiesto SDRAM
        DIAG_WRITE_READ_TEST  // 3: Diagnostický test oddeleného zápisu a čítania
    } op_mode_e;

endpackage

`endif
