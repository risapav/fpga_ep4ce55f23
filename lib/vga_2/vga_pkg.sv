// ============================================================================
// vga_pkg.sv - Vylepšený a robustný balíček pre VGA časovanie a farby
//
// Verzia: 2.3
// Autor: Tvoj tím / Škola
//
// Tento balíček definuje VGA režimy, stavy FSM, RGB farby, štruktúry časovania
// a pomocné funkcie pre VGA radiče.
// ============================================================================

`ifndef VGA_PKG_DONE
`define VGA_PKG_DONE

package vga_pkg;

    // =========================================================================
    // Polarita signálov (či sú aktívne pri vysokej alebo nízkej úrovni)
    // =========================================================================
    localparam bit P_ACTIVE_HIGH = 1'b1;
    localparam bit P_ACTIVE_LOW  = 1'b0;

    // =========================================================================
    // VGA režimy - jednotlivé štandardy podľa rozlíšenia a frekvencie
    // =========================================================================
    typedef enum logic [4:0] {
        VGA_640x480_60,
        VGA_800x600_60,
        VGA_1024x768_60,
        VGA_1024x768_70,
        VGA_1280x720_60,
        VGA_1280x1024_60,
        VGA_1920x1080_60,
        VGA_1920x1080_75,
        VGA_1920x1080_85,
        VGA_CUSTOM
    } VGA_mode_e;

    // =========================================================================
    // Stavy riadiacich automatov pre horizontálne a vertikálne riadenie
    // =========================================================================
    typedef enum logic [1:0] {
        SYNC,       // synchronizačný impulz
        BACKPORCH,  // spätný porch
        ACTIVE,     // zobrazovaná oblasť (viditeľné pixely)
        FRONTPORCH  // predný porch
    } VGA_state_e;

    // =========================================================================
    // Preddefinované RGB565 farby (16-bitová farebná hĺbka)
    // =========================================================================
    localparam logic [15:0]
        RED     = 16'hF800,
        GREEN   = 16'h07E0,
        BLUE    = 16'h001F,
        YELLOW  = 16'hFFE0,
        CYAN    = 16'h07FF,
        PURPLE  = 16'hF81F,
        ORANGE  = 16'hFC00,
        BLACK   = 16'h0000,
        WHITE   = 16'hFFFF;

    // =========================================================================
    // Parametre a štruktúry pre časovanie (jeden H- alebo V-riadok)
    // =========================================================================
    parameter int LINE_WIDTH = 12;

    typedef struct packed {
        logic [LINE_WIDTH-1:0] visible_area;  // počet zobrazovaných pixelov
        logic [LINE_WIDTH-1:0] front_porch;   // predná medzera
        logic [LINE_WIDTH-1:0] sync_pulse;    // šírka sync impulzu
        logic [LINE_WIDTH-1:0] back_porch;    // zadná medzera
        logic                  polarity;      // polarita sync signálu
    } line_t;

    // =========================================================================
    // Výpočet celkového počtu cyklov pre daný riadok
    // =========================================================================
    function automatic logic [13:0] get_total(line_t line);
        return line.visible_area + line.front_porch + line.sync_pulse + line.back_porch;
    endfunction

    // =========================================================================
    // Ďalšie pomocné typy (pozícia, stav, výstup atď.)
    // =========================================================================
    typedef struct packed {
        logic [LINE_WIDTH-1:0] x;
        logic [LINE_WIDTH-1:0] y;
    } position_t;

    typedef struct packed {
        logic sync;
        logic active;
        logic blank;
    } fsm_output_t;

    typedef struct packed {
        logic h_sync;
        logic v_sync;
        logic active;
        logic blank;
    } signal_t;

    typedef struct packed {
        position_t pos;
        logic [15:0] data;
        logic sof;  // start of frame
        logic eol;  // end of line
    } vstream_t;

    typedef struct packed {
        logic [4:0] red;
        logic [5:0] grn;
        logic [4:0] blu;
        logic       hs;
        logic       vs;
    } VGA_565_output_t;

    // =========================================================================
    // Získanie časovacích parametrov pre daný VGA režim
    // =========================================================================
    function automatic void get_vga_timing(
        input  VGA_mode_e mode,
        output line_t h_line,
        output line_t v_line
    );
        case (mode)
            VGA_640x480_60: begin
                h_line = '{640, 16, 96, 48, P_ACTIVE_LOW};
                v_line = '{480, 10, 2, 33, P_ACTIVE_LOW};
            end
            VGA_800x600_60: begin
                h_line = '{800, 40, 128, 88, P_ACTIVE_HIGH};
                v_line = '{600, 1, 4, 23, P_ACTIVE_HIGH};
            end
            VGA_1024x768_60: begin
                h_line = '{1024, 24, 136, 160, P_ACTIVE_LOW};
                v_line = '{768, 3, 6, 29, P_ACTIVE_LOW};
            end
            VGA_1024x768_70: begin
                h_line = '{1024, 24, 136, 144, P_ACTIVE_LOW};
                v_line = '{768, 3, 6, 29, P_ACTIVE_LOW};
            end
            VGA_1280x720_60: begin
                h_line = '{1280, 110, 40, 220, P_ACTIVE_HIGH};
                v_line = '{720, 5, 5, 20, P_ACTIVE_HIGH};
            end
            VGA_1280x1024_60: begin
                h_line = '{1280, 48, 112, 248, P_ACTIVE_HIGH};
                v_line = '{1024, 1, 3, 38, P_ACTIVE_HIGH};
            end
            VGA_1920x1080_60: begin
                h_line = '{1920, 88, 44, 148, P_ACTIVE_HIGH};
                v_line = '{1080, 4, 5, 36, P_ACTIVE_HIGH};
            end
            VGA_1920x1080_75: begin
                h_line = '{1920, 80, 80, 200, P_ACTIVE_HIGH};
                v_line = '{1080, 3, 5, 40, P_ACTIVE_HIGH};
            end
            VGA_1920x1080_85: begin
                h_line = '{1920, 96, 88, 216, P_ACTIVE_HIGH};
                v_line = '{1080, 3, 6, 42, P_ACTIVE_HIGH};
            end
            default: begin
                // Predvolený fallback režim
                h_line = '{640, 16, 96, 48, P_ACTIVE_LOW};
                v_line = '{480, 10, 2, 33, P_ACTIVE_LOW};
            end
        endcase
    endfunction

    // =========================================================================
    // Pixelová frekvencia (Hz) pre jednotlivé režimy
    // =========================================================================
    function automatic int get_pixel_clock(input VGA_mode_e mode);
        case (mode)
            VGA_640x480_60:     return 25_200_000;
            VGA_800x600_60:     return 40_000_000;
            VGA_1024x768_60:    return 65_000_000;
            VGA_1024x768_70:    return 75_000_000;
            VGA_1280x720_60:    return 74_250_000;
            VGA_1280x1024_60:   return 108_000_000;
            VGA_1920x1080_60:   return 148_500_000;
            VGA_1920x1080_75:   return 184_000_000;
            VGA_1920x1080_85:   return 214_750_000;
            default:            return 0;
        endcase
    endfunction

endpackage : vga_pkg

`endif // VGA_PKG_DONE
