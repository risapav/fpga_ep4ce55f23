//=============================================================================
// vga_controller.sv - Univerzálny a znovupoužiteľný VGA Controller
//
// Verzia: 3.0
//
// === Popis Architektúry ===
// Tento modul slúži ako kompletný VGA controller, ktorý prijíma pixelové
// dáta cez AXI4-Stream zbernicu a generuje plnohodnotný VGA signál.
// Je navrhnutý pre prácu v dvoch hodinových doménach (axi_clk a pix_clk)
// a obsahuje robustnú logiku pre Clock Domain Crossing (CDC).
//
// === Kľúčové Vlastnosti Verzie 3.0 (Refaktoring) ===
// 1. UNIVERZÁLNOSŤ: Modul je plne parametrizovateľný pre rôzne rozlíšenia,
//    farebné hĺbky a šírky AXI zbernice.
//
// 2. PRENOSITEĽNOSŤ: Boli odstránené závislosti na externých `interface`
//    a `package` definíciách. Modul teraz používa diskrétne porty,
//    čo umožňuje jeho jednoduchú integráciu do akéhokoľvek projektu.
//
// 3. ROBUSTNOSŤ: Ponechaná osvedčená architektúra s asynchrónnym FIFO
//    pre dáta a dvojstupňovými synchronizátormi pre riadiace signály,
//    čo zaručuje bezpečný prechod medzi hodinovými doménami.
//
// 4. DIAGNOSTIKA: Modul poskytuje "lepivé" (sticky) príznaky pretečenia
//    a podtečenia FIFO buffera pre jednoduché ladenie.
//=============================================================================
`default_nettype none

// Importujeme len VGA balíček, ktorý obsahuje definície režimov (VGA_mode_e)
// a užitočné funkcie, ktoré sú pre tento modul nevyhnutné.
import vga_pkg::*;

module vga_controller #(
    // --- Konfigurácia VGA Výstupu ---
    parameter VGA_mode_e RESOLUTION   = VGA_1024x768_60, // Predvolené rozlíšenie (napr. VGA_640x480)
    parameter int        C_R_WIDTH    = 5,           // Šírka červeného kanálu v bitoch
    parameter int        C_G_WIDTH    = 6,           // Šírka zeleného kanálu v bitoch
    parameter int        C_B_WIDTH    = 5,           // Šírka modrého kanálu v bitoch

    // --- Konfigurácia AXI4-Stream Vstupu ---
    parameter int        AXIS_TDATA_WIDTH = 16, // Šírka dát na AXI vstupe
    parameter int        AXIS_TUSER_WIDTH = 1,  // Šírka TUSER na AXI vstupe

    // --- Konfigurácia Interných Zdrojov ---
    parameter int        FIFO_DEPTH   = 1024,      // Hĺbka interného asynchrónneho FIFO
    parameter bit        TEST_MODE    = 0          // 1 = Zobrazí testovací obrazec (farebné pruhy)
)(
    // --- Hodiny a Resety ---
    input  logic pix_clk,  // Hodiny pre VGA časovanie a výstup (Pixel Clock)
    input  logic pix_rstn, // Reset pre pix_clk doménu, aktívny v nule
    input  logic axi_clk,  // Hodiny pre AXI-Stream vstup
    input  logic axi_rstn, // Reset pre axi_clk doménu, aktívny v nule

    // --- AXI4-Stream Slave Vstup (Diskrétne Porty) ---
    input  logic [AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input  logic [AXIS_TUSER_WIDTH-1:0] s_axis_tuser,
    input  logic                        s_axis_tlast,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,

    // --- VGA Výstupné Porty ---
    output logic [C_R_WIDTH-1:0] VGA_R,
    output logic [C_G_WIDTH-1:0] VGA_G,
    output logic [C_B_WIDTH-1:0] VGA_B,
    output logic                 VGA_HS,
    output logic                 VGA_VS,

    // --- Diagnostické Výstupy ---
    output logic overflow_sticky_flag,
    output logic underflow_sticky_flag
);

    //==========================================================================
    // ČASŤ 1: INTERNÉ VGA ČASOVANIE
    //==========================================================================
    // Táto sekcia generuje všetky potrebné časovacie signály na základe
    // zvoleného rozlíšenia. Používa externý modul `Vga_timing`.

    line_t     h_line, v_line;
    position_t pos;
    signal_t   signal;

    // Získanie časovacích parametrov z vga_pkg na základe zvoleného rozlíšenia
    always_comb begin
        get_vga_timing(RESOLUTION, h_line, v_line);
    end

    // Inštancia generátora časovania
    Vga_timing vga_timing_inst (
        .clk_pix(pix_clk), .rstn(pix_rstn),
        .h_line(h_line),   .v_line(v_line),
        .pos(pos),         .signal(signal)
    );

    //==========================================================================
    // ČASŤ 2: SPRACOVANIE DÁT, FIFO A SYNCHRONIZÁCIA (CDC)
    //==========================================================================
    // Táto kľúčová sekcia zabezpečuje prenos dát z axi_clk domény do pix_clk
    // domény a synchronizáciu riadiacich signálov.

    // --- Definícia lokálnej dátovej štruktúry pre FIFO ---
    // Toto nahrádza závislosť na externom `axi_pkg` a robí modul samostatným.
    localparam int PAYLOAD_WIDTH = 1 + AXIS_TUSER_WIDTH + AXIS_TDATA_WIDTH;
    typedef struct packed {
        logic                       TLAST;
        logic [AXIS_TUSER_WIDTH-1:0] TUSER;
        logic [AXIS_TDATA_WIDTH-1:0] TDATA;
    } stream_payload_t;

    // --- Signály pre FIFO a riadenie toku ---
    logic wr_en, full, rd_en, empty, overflow, underflow, underflow_detected;
    stream_payload_t fifo_wr_data, fifo_rd_data, pixel_reg;

    // --- Logika Synchronizácie Snímky (Frame Sync) ---
    // Detekuje začiatok a koniec snímky v pix_clk doméne a prenáša túto
    // informáciu bezpečne do axi_clk domény na riadenie AXI streamu.

	// Krok 1: Detekcia udalostí v pix_clk doméne
	logic start_of_frame_condition;
	logic end_of_frame_condition;

	assign start_of_frame_condition = signal.active && (pos.x == 'd0) && (pos.y == 'd0);
	assign end_of_frame_condition   = signal.active && (pos.x == h_line.visible_area - 1) && (pos.y == v_line.visible_area - 1);

    // Krok 2: Registrácia udalostí (odstraňuje timing hazards pred CDC)
    logic start_of_frame_pix_clk_reg, end_of_frame_pix_clk_reg;
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn) begin
            start_of_frame_pix_clk_reg <= 1'b0;
            end_of_frame_pix_clk_reg   <= 1'b0;
        end else begin
            start_of_frame_pix_clk_reg <= start_of_frame_condition;
            end_of_frame_pix_clk_reg   <= end_of_frame_condition;
        end
    end

    // Krok 3: Bezpečný prenos do axi_clk domény cez dvojstupňový synchronizátor
    logic start_of_frame_axi_clk, end_of_frame_axi_clk;
    TwoFlopSynchronizer #(.WIDTH(1)) frame_start_sync_inst (.clk(axi_clk), .rst_n(axi_rstn), .d(start_of_frame_pix_clk_reg), .q(start_of_frame_axi_clk));
    TwoFlopSynchronizer #(.WIDTH(1)) frame_end_sync_inst   (.clk(axi_clk), .rst_n(axi_rstn), .d(end_of_frame_pix_clk_reg),   .q(end_of_frame_axi_clk));

    // Krok 4: Stavový automat v axi_clk doméne, ktorý povoľuje/zakazuje AXI stream
    logic stream_enabled;
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)
            stream_enabled <= 1'b0;
        else if (start_of_frame_axi_clk)
            stream_enabled <= 1'b1;
        else if (end_of_frame_axi_clk)
            stream_enabled <= 1'b0;
    end

    // --- Logika Zápisu do FIFO (axi_clk doména) ---
    assign s_axis_tready  = stream_enabled && !full;
    assign wr_en          = s_axis_tvalid && s_axis_tready;
    assign fifo_wr_data   = '{TUSER: s_axis_tuser, TLAST: s_axis_tlast, TDATA: s_axis_tdata};

    // --- Inštancia Asynchrónneho FIFO ---
    AsyncFIFO #(.DATA_WIDTH(PAYLOAD_WIDTH), .DEPTH(FIFO_DEPTH))
    fifo_inst (
        .wr_clk(axi_clk), .wr_rstn(axi_rstn), .wr_en(wr_en), .wr_data(fifo_wr_data), .full(full), .overflow(overflow),
        .rd_clk(pix_clk), .rd_rstn(pix_rstn), .rd_en(rd_en), .rd_data(fifo_rd_data), .empty(empty), .underflow(underflow)
    );

    // --- Logika Čítania z FIFO (pix_clk doména) ---
    assign rd_en              = signal.active && !empty;
    assign underflow_detected = signal.active && empty;

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)
            pixel_reg <= '{default:'0};
        else if (rd_en)
            pixel_reg <= fifo_rd_data;
    end

    //==========================================================================
    // ČASŤ 3: DIAGNOSTIKA
    //==========================================================================
    logic overflow_sticky, underflow_sticky;
    assign overflow_sticky_flag  = overflow_sticky;
    assign underflow_sticky_flag = underflow_sticky;

    // "Lepkavý" príznak pretečenia v axi_clk doméne
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)                   overflow_sticky <= 1'b0;
        else if (overflow)               overflow_sticky <= 1'b1;
        else if (start_of_frame_axi_clk) overflow_sticky <= 1'b0; // Reset na začiatku snímky
    end

    // "Lepkavý" príznak podtečenia v pix_clk doméne
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)                       underflow_sticky <= 1'b0;
        else if (underflow)                  underflow_sticky <= 1'b1;
        else if (start_of_frame_pix_clk_reg) underflow_sticky <= 1'b0; // Reset na začiatku snímky
    end

    //==========================================================================
    // ČASŤ 4: FINÁLNY VÝBER FARBY A VÝSTUPNÁ LOGIKA
    //==========================================================================
    localparam int COLOR_WIDTH = C_R_WIDTH + C_G_WIDTH + C_B_WIDTH;
    logic [COLOR_WIDTH-1:0] pixel_color;

    // Multiplexer pre výber finálnej farby pixelu
    always_comb begin
        if (TEST_MODE) begin
            // V testovacom režime sa generujú farebné pruhy
            unique case (1'b1)
                !signal.active: pixel_color = 'd0; // Čierna mimo aktívnej oblasti
                pos.x < (h_line.visible_area/8)*1: pixel_color = 16'hFFFF; // Biela
                pos.x < (h_line.visible_area/8)*2: pixel_color = 16'hFFE0; // Žltá
                pos.x < (h_line.visible_area/8)*3: pixel_color = 16'h07FF; // Tyrkysová
                pos.x < (h_line.visible_area/8)*4: pixel_color = 16'h07E0; // Zelená
                pos.x < (h_line.visible_area/8)*5: pixel_color = 16'hF81F; // Fialová
                pos.x < (h_line.visible_area/8)*6: pixel_color = 16'hF800; // Červená
                pos.x < (h_line.visible_area/8)*7: pixel_color = 16'h001F; // Modrá
                default:                           pixel_color = 'd0; // Čierna
            endcase
        end else begin
            // V normálnom režime sa zobrazujú dáta z AXI streamu
            unique case (1'b1)
                underflow_detected: pixel_color = 16'hF81F; // Fialová signalizuje podtečenie
                signal.active:      pixel_color = pixel_reg.TDATA; // Dáta z FIFO
                default:            pixel_color = 'd0; // Čierna mimo aktívnej oblasti
            endcase
        end
    end

    // --- Finálne priradenie na výstupné porty ---
    // Logika automaticky extrahuje farebné zložky z `pixel_color` vektora.
    // Predpokladá sa poradie bitov {Červená, Zelená, Modrá}.
    assign VGA_R  = pixel_color[COLOR_WIDTH-1 -: C_R_WIDTH];
    assign VGA_G  = pixel_color[C_B_WIDTH + C_G_WIDTH - 1 -: C_G_WIDTH];
    assign VGA_B  = pixel_color[C_B_WIDTH - 1 -: C_B_WIDTH];
    assign VGA_HS = signal.h_sync;
    assign VGA_VS = signal.v_sync;

endmodule
