`timescale 1ns / 1ns
`ifndef VGA_PKG_DONE
`define VGA_PKG_DONE

package vga_pkg;

    parameter int TIMING_WIDTH = 12;
	
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
        VGA_1680x1050_60,
        VGA_1920x1080_60,
        VGA_1920x1080_75,
        VGA_1920x1080_85,
        VGA_CUSTOM
    } VGA_mode_e;

    // =========================================================================
    // Parametre a štruktúry pre časovanie (jeden H- alebo V-riadok)
    // =========================================================================
    typedef struct packed {
        logic [TIMING_WIDTH-1:0] visible_area, front_porch, sync_pulse, back_porch;
        bit                      polarity;
    } Line_t;

    // =========================================================================
    // Ďalšie pomocné typy (pozícia, stav, výstup atď.)
    // =========================================================================	
    typedef struct packed { logic [4:0] red; logic [5:0] grn; logic [4:0] blu; } VGA_data_t;
    typedef struct packed { logic hs; logic vs; } VGA_sync_t;

    // --- NOVÁ ZJEDNOTENÁ ŠTRUKTÚRA PRE PARAMETRE ---
    typedef struct packed {
        Line_t h_line;
        Line_t v_line;
    } VGA_params_t;

    // =========================================================================
    // Preddefinované RGB565 farby (16-bitová farebná hĺbka)
    // =========================================================================
    localparam VGA_data_t
        RED    = 16'hF800, GREEN  = 16'h07E0, BLUE   = 16'h001F,
        YELLOW = 16'hFFE0, CYAN   = 16'h07FF, PURPLE = 16'hF81F,
        ORANGE = 16'hFC00, BLACK  = 16'h0000, WHITE  = 16'hFFFF;

    // =========================================================================
    // Získanie časovacích parametrov pre daný VGA režim
    // =========================================================================
//    function automatic VGA_params_t get_vga_params(input VGA_mode_e mode);
//        case (mode)
//            VGA_640x480_60: return '{ h_line:'{640, 16, 96, 48, P_ACTIVE_LOW},  v_line:'{480, 10, 2, 33, P_ACTIVE_LOW}};
//            VGA_800x600_60: return '{ h_line:'{800, 40, 128, 88, P_ACTIVE_HIGH}, v_line:'{600, 1, 4, 23, P_ACTIVE_HIGH}};
//            VGA_1024x768_60: return '{h_line:'{1024, 24, 136, 160, P_ACTIVE_LOW}, v_line:'{768, 3, 6, 29, P_ACTIVE_LOW}};
//            VGA_1024x768_70: return '{h_line:'{1024, 24, 136, 144, P_ACTIVE_LOW}, v_line:'{768, 3, 6, 29, P_ACTIVE_LOW}};
//            VGA_1280x720_60: return '{h_line:'{1280, 110, 40, 220, P_ACTIVE_HIGH},v_line:'{720, 5, 5, 20, P_ACTIVE_HIGH}};
//            VGA_1280x1024_60:return '{h_line:'{1280, 48, 112, 248, P_ACTIVE_HIGH},v_line:'{1024, 1, 3, 38, P_ACTIVE_HIGH}};
//            VGA_1680x1050_60:return '{h_line:'{1680, 48, 32, 80, P_ACTIVE_HIGH}, v_line:'{1050, 3, 6, 21, P_ACTIVE_LOW}};
//            VGA_1920x1080_60:return '{h_line:'{1920, 88, 44, 148, P_ACTIVE_HIGH},v_line:'{1080, 4, 5, 36, P_ACTIVE_HIGH}};
//            VGA_1920x1080_75:return '{h_line:'{1920, 80, 80, 200, P_ACTIVE_HIGH},v_line:'{1080, 3, 5, 40, P_ACTIVE_HIGH}};
//            VGA_1920x1080_85:return '{h_line:'{1920, 96, 88, 216, P_ACTIVE_HIGH},v_line:'{1080, 3, 6, 42, P_ACTIVE_HIGH}};			
//				default: return '{default: '0}; 
//        endcase
//    endfunction

function automatic VGA_params_t get_vga_params(input VGA_mode_e mode);
    // 1. Vytvoríme lokálnu premennú typu, ktorý chceme vrátiť
    VGA_params_t params; 

    // 2. Vnútri 'case' príkazu naplníme jej členy
    case (mode)
        VGA_640x480_60: begin
            params.h_line = '{640, 16, 96, 48, P_ACTIVE_LOW};
            params.v_line = '{480, 10, 2, 33, P_ACTIVE_LOW};
        end
        VGA_800x600_60: begin
            params.h_line = '{800, 40, 128, 88, P_ACTIVE_HIGH};
            params.v_line = '{600, 1, 4, 23, P_ACTIVE_HIGH};
        end
        VGA_1024x768_60: begin
            params.h_line = '{1024, 24, 136, 160, P_ACTIVE_LOW};
            params.v_line = '{768, 3, 6, 29, P_ACTIVE_LOW};
        end
        // ... a tak ďalej pre všetky ostatné režimy ...
        VGA_1920x1080_85: begin
            params.h_line = '{1920, 96, 88, 216, P_ACTIVE_HIGH};
            params.v_line = '{1080, 3, 6, 42, P_ACTIVE_HIGH};
        end
        default: begin
            //params = '{default: '0};
				params = '0;
        end
    endcase

    // 3. Vrátime jednoduchú, naplnenú premennú. Tomuto už Icarus rozumie.
    return params; 
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
            VGA_1680x1050_60:   return 119_000_000;
            VGA_1920x1080_60:   return 148_500_000;
            VGA_1920x1080_75:   return 184_000_000;
            VGA_1920x1080_85:   return 214_750_000;
            default:            return 0;
        endcase
    endfunction	
    
endpackage : vga_pkg

`endif // VGA_PKG_DONE
