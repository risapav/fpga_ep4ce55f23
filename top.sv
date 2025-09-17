//=============================================================================
// top.sv - Univerzálny Generátor VGA Signálu
// Verzia: 4.0
// Dátum:  12. júl 2025
// Autor:  Gemini (Refaktoring)
//
// === Popis a vylepšenia (Verzia 4.0) ===
// 1. PLNÁ PARAMETRIZÁCIA:
//    - Zmena VGA režimu sa teraz vykonáva úpravou jediného parametra `VGA_MODE`.
//    - Všetky závislé konštanty (časovanie, frekvencia hodín, polarita,
//      šírka čítačov) sa odvodzujú automaticky.
//    - Pridané režimy: 640x480@60Hz, 800x600@72Hz, 1280x720@60Hz.
//
// 2. ČISTÝ A ROBUSTNÝ KÓD:
//    - Odstránené všetky dočasné a debugovacie artefakty.
//    - Opravené všetky varovania (truncation warnings) explicitným
//      špecifikovaním šírky konštánt.
//    - Vylepšená štruktúra a pridané detailné komentáre pre lepšiu
//      čitateľnosť a budúcu údržbu.
//
// 3. ARCHITEKTÚRA (zostáva zachovaná):
//    - Osvedčený 3-stupňový pipeline model pre generovanie stabilného
//      VGA výstupu bez hazardov (glitch-free).
//=============================================================================
`default_nettype none

module top (
    // -- Hlavné vstupy
    input  logic       SYS_CLK,    // Hlavné hodiny z externého kryštálu (napr. 50 MHz)
    input  logic       RESET_N,    // Asynchrónny reset, aktívny v nule

    // -- Periférie
    output logic [7:0] SMG_SEG,
    output logic [2:0] SMG_DIG,
    output logic [5:0] LED,
    input  logic [5:0] BSW,

    // -- VGA Výstup
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS
);

//==========================================================================
//  KONFIGURÁCIA A PARAMETRE VGA REŽIMU
//==========================================================================
// *** TU SA PREPÍNA POŽADOVANÝ VGA REŽIM ***
// Zmenou tohto parametra sa automaticky prepočíta celý projekt.
// Pre syntézu je potrebné aj zodpovedajúco prekonfigurovať PLL.
parameter string VGA_MODE = "640x480@60Hz";

// --- Definície konštánt pre rôzne VGA režimy ---
localparam string MODE_640_480_60 = "640x480@60Hz";
localparam string MODE_800_600_72 = "800x600@72Hz";
localparam string MODE_1280_720_60 = "1280x720@60Hz";

// --- Odvodené parametre na základe zvoleného VGA_MODE ---
localparam int PIXEL_CLOCK_HZ =
    (VGA_MODE == MODE_640_480_60)  ? 25_200_000 :  // 25.2 MHz
    (VGA_MODE == MODE_800_600_72)  ? 50_000_000 :  // 50.0 MHz
    (VGA_MODE == MODE_1280_720_60) ? 74_250_000 :  // 74.25 MHz
    0; // Predvolená hodnota (spôsobí chybu pri syntéze, ak je režim neznámy)

// Horizontálne časovanie
localparam int H_VISIBLE = (VGA_MODE == MODE_640_480_60) ? 640 : (VGA_MODE == MODE_800_600_72) ? 800 : 1280;
localparam int H_FRONT   = (VGA_MODE == MODE_640_480_60) ? 16  : (VGA_MODE == MODE_800_600_72) ? 56  : 110;
localparam int H_SYNC    = (VGA_MODE == MODE_640_480_60) ? 96  : (VGA_MODE == MODE_800_600_72) ? 120 : 40;
localparam int H_BACK    = (VGA_MODE == MODE_640_480_60) ? 48  : (VGA_MODE == MODE_800_600_72) ? 64  : 220;
localparam int H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;

// Vertikálne časovanie
localparam int V_VISIBLE = (VGA_MODE == MODE_640_480_60) ? 480 : (VGA_MODE == MODE_800_600_72) ? 600 : 720;
localparam int V_FRONT   = (VGA_MODE == MODE_640_480_60) ? 10  : (VGA_MODE == MODE_800_600_72) ? 37  : 5;
localparam int V_SYNC    = (VGA_MODE == MODE_640_480_60) ? 2   : (VGA_MODE == MODE_800_600_72) ? 6   : 5;
localparam int V_BACK    = (VGA_MODE == MODE_640_480_60) ? 33  : (VGA_MODE == MODE_800_600_72) ? 23  : 20;
localparam int V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

// Polarita synchronizácie (1 = negatívna, 0 = pozitívna)
localparam bit SYNC_HS_NEG = (VGA_MODE == MODE_1280_720_60) ? 1'b0 : 1'b1;
localparam bit SYNC_VS_NEG = (VGA_MODE == MODE_1280_720_60) ? 1'b0 : 1'b1;

// Automatický výpočet potrebnej šírky pre čítače
localparam int H_BITS = $clog2(H_TOTAL);
localparam int V_BITS = $clog2(V_TOTAL);


//==========================================================================
// PLL INŠTANCIA A HLAVNÝ RESET
//==========================================================================
logic pixel_clk;
logic pll_locked;

ClkPll clkpll_inst (
    .inclk0 (SYS_CLK),    // Vstup z externého kryštálu
    .areset (~RESET_N),   // Reset pre PLL, aktívny v 1
    .c0     (pixel_clk),  // Výstupný pixel clock (frekvencia závisí od `VGA_MODE`)
    .locked (pll_locked)  // Signál, že PLL je stabilný
);

// Robustný synchrónny reset pre celú logiku.
// Obvod zostáva v resete, kým nie je uvoľnený externý reset A ZÁROVEŇ
// kým sa PLL nestabilizuje (nezamkne).
logic reset;
assign reset = !RESET_N || !pll_locked;


//==========================================================================
// 7-SEGMENTOVÝ DISPLEJ
//==========================================================================
logic [3:0] digit0 = 4'd1;
logic [3:0] digit1 = 4'd2;
logic [3:0] digit2 = 4'd3;

localparam int ONE_MS_TICKS = PIXEL_CLOCK_HZ / 1000;
logic [$clog2(ONE_MS_TICKS)-1:0] ms_counter;
logic [1:0] seg_sel;

always_ff @(posedge pixel_clk or posedge reset) begin
    if (reset) begin
        ms_counter <= 'd0; 
        seg_sel    <= 2'd0;
    end else if (ms_counter == ONE_MS_TICKS - 1) begin
        ms_counter <= 'd0;
        seg_sel    <= seg_sel + 1;
    end else begin
        ms_counter <= ms_counter + 1;
    end
end

always_comb begin
    case (seg_sel)
        2'd0:   begin SMG_DIG = 3'b110; SMG_SEG = seg_decoder(digit0); end
        2'd1:   begin SMG_DIG = 3'b101; SMG_SEG = seg_decoder(digit1); end
        2'd2:   begin SMG_DIG = 3'b011; SMG_SEG = seg_decoder(digit2); end
        default:begin SMG_DIG = 3'b111; SMG_SEG = 8'hFF; end
    endcase
end

function automatic [7:0] seg_decoder(input logic [3:0] val);
    case (val)
        4'h0: return 8'b11000000; 4'h1: return 8'b11111001;
        4'h2: return 8'b10100100; 4'h3: return 8'b10110000;
        4'h4: return 8'b10011001; 4'h5: return 8'b10010010;
        4'h6: return 8'b10000010; 4'h7: return 8'b11111000;
        4'h8: return 8'b10000000; 4'h9: return 8'b10010000;
        default: return 8'hFF; // blank
    endcase
endfunction


//==========================================================================
// LED INDIKÁTORY
//==========================================================================
// LED[0] bliká ako "srdcový tep" (heartbeat), čo vizuálne potvrdzuje,
// že systém beží (PLL je zamknutá a hodiny fungujú).
logic led0_reg;
localparam int BLINK_DIVIDER = PIXEL_CLOCK_HZ / 2; // Počet cyklov pre 0.5s
logic [$clog2(BLINK_DIVIDER)-1:0] blink_counter_reg;

always_ff @(posedge pixel_clk or posedge reset) begin
    if (reset) begin
        blink_counter_reg <= 'd0;
        led0_reg          <= 1'b0;
    end else if (blink_counter_reg == BLINK_DIVIDER - 1) begin
        blink_counter_reg <= 'd0;
        led0_reg          <= ~led0_reg;
    end else begin
        blink_counter_reg <= blink_counter_reg + 1;
    end
end

// LED[5:1] zobrazujú inverzný stav tlačidiel BSW[5:1].
assign LED = {~BSW[5:1], led0_reg};


//==========================================================================
// JADRO VGA GENERÁTORA
//==========================================================================
// --- Krok 1: Generovanie súradníc (Horizontálny a Vertikálny čítač) ---
logic [H_BITS-1:0] hcount;
logic [V_BITS-1:0] vcount;
logic [H_BITS-1:0] hcount_next;
logic [V_BITS-1:0] vcount_next;

// Kombinačná logika pre výpočet ďalšej pozície (x, y)
always_comb begin
    hcount_next = hcount + 1;
    vcount_next = vcount;

    if (hcount == H_TOTAL - 1) begin
        hcount_next = {H_BITS{1'b0}}; // Reset na 0
        if (vcount == V_TOTAL - 1) begin
            vcount_next = {V_BITS{1'b0}}; // Reset na 0
        end else begin
            vcount_next = vcount + 1;
        end
    end
end

// Sekvenčná logika pre uloženie novej pozície do registrov
always_ff @(posedge pixel_clk or posedge reset) begin
    if (reset) begin
        hcount <= 'd0;
        vcount <= 'd0;
    end else begin
        hcount <= hcount_next;
        vcount <= vcount_next;
    end
end

// --- Krok 2: Výpočet budúcich stavov signálov (Kombinačná logika) ---
logic hsync_next, vsync_next, visible_next;
logic [4:0] vga_r_next;
logic [5:0] vga_g_next;
logic [4:0] vga_b_next;

// Výpočet polohy pre synchronizačné pulzy
logic h_sync_period, v_sync_period;
assign h_sync_period = (hcount >= H_VISIBLE + H_FRONT) && (hcount < H_VISIBLE + H_FRONT + H_SYNC);
assign v_sync_period = (vcount >= V_VISIBLE + V_FRONT) && (vcount < V_VISIBLE + V_FRONT + V_SYNC);

// Aplikácia polarity
assign hsync_next = SYNC_HS_NEG ? ~h_sync_period : h_sync_period;
assign vsync_next = SYNC_VS_NEG ? ~v_sync_period : v_sync_period;

// Výpočet viditeľnej oblasti obrazovky
assign visible_next = (hcount < H_VISIBLE) && (vcount < V_VISIBLE);

// Generovanie obsahu obrazu - jednoduchý červený obdĺžnik v strede
always_comb begin
    vga_r_next = 5'd0;
    vga_g_next = 6'd0;
    vga_b_next = 5'd0;

    // Podmienka pre vykreslenie obdĺžnika
    if (visible_next &&
        hcount > (H_VISIBLE/4) && hcount < (H_VISIBLE*3/4) &&
        vcount > (V_VISIBLE/4) && vcount < (V_VISIBLE*3/4))
    begin
        vga_r_next = 5'b11111; // Max červená
        vga_g_next = 6'b00000;
        vga_b_next = 5'b00000;
    end
end

// --- Krok 3: Výstupné registre (Pipeline) ---
// Všetky vypočítané "_next" hodnoty sa uložia do registrov. Toto zabezpečí,
// že všetky výstupy sa zmenia naraz po hrane hodín a budú stabilné a čisté.
logic hsync_reg, vsync_reg;
logic [4:0] vga_r_reg;
logic [5:0] vga_g_reg;
logic [4:0] vga_b_reg;

always_ff @(posedge pixel_clk or posedge reset) begin
    if (reset) begin
        hsync_reg <= ~SYNC_HS_NEG; // V resete sú synch. signály neaktívne
        vsync_reg <= ~SYNC_VS_NEG;
        {vga_r_reg, vga_g_reg, vga_b_reg} <= 'd0;
    end else begin
        hsync_reg <= hsync_next;
        vsync_reg <= vsync_next;
        vga_r_reg <= vga_r_next;
        vga_g_reg <= vga_g_next;
        vga_b_reg <= vga_b_next;
    end
end

// --- Krok 4: Finálne priradenie na výstupné porty ---
// Na výstupy posielame už len stabilné, registrované signály.
assign VGA_HS = hsync_reg;
assign VGA_VS = vsync_reg;
assign VGA_R  = vga_r_reg;
assign VGA_G  = vga_g_reg;
assign VGA_B  = vga_b_reg;

endmodule