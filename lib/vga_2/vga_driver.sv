// vga_driver.sv - Finálny, robustný a diagnostikovateľný VGA driver
//
// Verzia 2.3
//
// === Zhrnutie vylepšení ===
// 1. OPRAVA ČASOVANIA (CDC): Pridaný registračný stupeň pred synchronizátormi
//    pre signály `start_of_frame` a `end_of_frame`. Týmto sa odstraňuje
//    posledná chyba nespĺňania časovania (timing failure) pri prechode
//    medzi pix_clk a axi_clk doménami.
// ... (ostatné komentáre zostávajú)

`default_nettype none

import vga_pkg::*;
import axi_pkg::*;

module vga_driver #(
    parameter VGA_mode_e RESOLUTION = VGA_800x600,
    parameter int        FIFO_DEPTH = 1024,
    parameter bit        TEST_MODE  = 0
)(
    // ... Zoznam portov zostáva nezmenený ...
    input  logic pix_clk,
    input  logic pix_rstn,
    input  logic axi_clk,
    input  logic axi_rstn,
    axi4s_if.slave s_axis,
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS,
    output logic       overflow_sticky_flag,
    output logic       underflow_sticky_flag
);

    // =======================================================
    // ČASŤ 1: INTERNÉ VGA ČASOVANIE (BEZ ZMENY)
    // =======================================================
    line_t     h_line, v_line;
    position_t pos;
    signal_t   signal;

    always_comb begin
        get_vga_timing(RESOLUTION, h_line, v_line);
    end

    Vga_timing vga_timing_inst (
        .clk_pix(pix_clk), .rstn(pix_rstn),
        .h_line(h_line), .v_line(v_line),
        .pos(pos), .signal(signal)
    );

    // =======================================================
    // ČASŤ 2: SPRACOVANIE DÁT, FIFO A SYNCHRONIZÁCIA (UPRAVENÉ)
    // =======================================================
    logic wr_en, full;
    logic rd_en, empty;
    logic overflow, underflow;
    logic underflow_detected;

    axi4s_payload_t fifo_wr_data;
    axi4s_payload_t fifo_rd_data;
    axi4s_payload_t pixel_reg;
    logic [15:0]    pixel_color;

    // --- Logika synchronizácie snímky (Frame Sync) ---
    
    // --- KROK 1: Kombinačne vypočítame podmienky pre začiatok a koniec snímky ---
    logic start_of_frame_condition;
    logic end_of_frame_condition;
    
    assign start_of_frame_condition = signal.active && (pos.x == 0) && (pos.y == 0);
    assign end_of_frame_condition   = signal.active && (pos.x == h_line.visible_area - 1) && (pos.y == v_line.visible_area - 1);

    // --- KROK 2: Výsledok zaregistrujeme v pix_clk doméne ---
    // Toto rozdelí dlhú kombinačnú cestu a opraví chybu časovania.
    logic start_of_frame_pix_clk_reg;
    logic end_of_frame_pix_clk_reg;

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn) begin
            start_of_frame_pix_clk_reg <= 1'b0;
            end_of_frame_pix_clk_reg   <= 1'b0;
        end else begin
            start_of_frame_pix_clk_reg <= start_of_frame_condition;
            end_of_frame_pix_clk_reg   <= end_of_frame_condition;
        end
    end

    // --- KROK 3: Až teraz posielame čisté, registrované signály do synchronizátora ---
    logic start_of_frame_axi_clk, end_of_frame_axi_clk;
    TwoFlopSynchronizer #(.WIDTH(1)) frame_start_sync_inst (.clk(axi_clk), .rst_n(axi_rstn), .d(start_of_frame_pix_clk_reg), .q(start_of_frame_axi_clk));
    TwoFlopSynchronizer #(.WIDTH(1)) frame_end_sync_inst   (.clk(axi_clk), .rst_n(axi_rstn), .d(end_of_frame_pix_clk_reg),   .q(end_of_frame_axi_clk));

    // Stavový register pre povolenie streamu (bez zmeny)
    logic stream_enabled;
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)
            stream_enabled <= 1'b0;
        else if (start_of_frame_axi_clk)
            stream_enabled <= 1'b1;
        else if (end_of_frame_axi_clk)
            stream_enabled <= 1'b0;
    end

    // FIFO a logika prenosu dát (bez zmeny)
    assign s_axis.TREADY = stream_enabled && !full;
    assign wr_en         = s_axis.TVALID && s_axis.TREADY;
    assign fifo_wr_data  = '{TUSER: s_axis.TUSER, TLAST: s_axis.TLAST, TDATA: s_axis.TDATA};

    AsyncFIFO #(.DATA_WIDTH($bits(axi4s_payload_t)), .DEPTH(FIFO_DEPTH)) 
    fifo_inst (
        .wr_clk(axi_clk), .wr_rstn(axi_rstn), .wr_en(wr_en), .wr_data(fifo_wr_data), .full(full), .overflow(overflow),
        .rd_clk(pix_clk), .rd_rstn(pix_rstn), .rd_en(rd_en), .rd_data(fifo_rd_data), .empty(empty), .underflow(underflow)
    );

    // Logika čítania z FIFO (bez zmeny)
    assign rd_en              = signal.active && !empty;
    assign underflow_detected = signal.active && empty;

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)  pixel_reg <= '{default:0};
        else if (rd_en) pixel_reg <= fifo_rd_data;
    end
    
    // --- Diagnostika: Lepivé príznaky chýb ---
    logic overflow_sticky, underflow_sticky;
    assign overflow_sticky_flag  = overflow_sticky;
    assign underflow_sticky_flag = underflow_sticky;

    // Príznak pretečenia v axi_clk doméne (bez zmeny)
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)                   overflow_sticky <= 1'b0;
        else if (overflow)               overflow_sticky <= 1'b1;
        else if (start_of_frame_axi_clk) overflow_sticky <= 1'b0;
    end

    // Príznak podtečenia v pix_clk doméne (upravené pre použitie registrovaného signálu)
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)                       underflow_sticky <= 1'b0;
        else if (underflow)                  underflow_sticky <= 1'b1;
        // OPRAVA: Používame nový, registrovaný signál na reset príznaku
        else if (start_of_frame_pix_clk_reg) underflow_sticky <= 1'b0;
    end

    // =======================================================
    // ČASŤ 3: FINÁLNY VÝBER FARBY A VÝSTUP (BEZ ZMENY)
    // =======================================================
    always_comb begin
        if (TEST_MODE) begin
            unique case (1'b1)
                !signal.active: pixel_color = BLACK;
                pos.x < (h_line.visible_area/8)*1: pixel_color = WHITE;
                pos.x < (h_line.visible_area/8)*2: pixel_color = YELLOW;
                pos.x < (h_line.visible_area/8)*3: pixel_color = CYAN;
                pos.x < (h_line.visible_area/8)*4: pixel_color = GREEN;
                pos.x < (h_line.visible_area/8)*5: pixel_color = PURPLE;
                pos.x < (h_line.visible_area/8)*6: pixel_color = RED;
                pos.x < (h_line.visible_area/8)*7: pixel_color = BLUE;
                default:                           pixel_color = BLACK;
            endcase
        end else begin
            unique case (1'b1)
                underflow_detected: pixel_color = PURPLE;
                signal.active:      pixel_color = pixel_reg.TDATA;
                default:            pixel_color = BLACK;
            endcase
        end
    end

    assign VGA_R  = pixel_color[15:11];
    assign VGA_G  = pixel_color[10:5];
    assign VGA_B  = pixel_color[4:0];
    assign VGA_HS = signal.h_sync;
    assign VGA_VS = signal.v_sync;

endmodule
