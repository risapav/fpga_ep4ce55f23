//=============================================================================
// vga_controller.sv - Univerzálny a znovupoužiteľný VGA Controller
//
// Verzia: 3.1
//
// Popis:
//  Modul spracúva pixelové dáta z AXI4-Stream (axi_clk doména) a generuje VGA
//  signál (pix_clk doména). Obsahuje FIFO pre bezpečné clock domain crossing.
//
// Novinky vo verzii 3.1:
// * Podpora prepínania medzi RGB565 a RGB888 formátmi pixelov
// * Spracovanie TLAST pre detekciu konca riadku
// * Debug výstupy: valid pixel counter a fifo_active
// * Vylepšená AXI handshake logika
//=============================================================================
`default_nettype none

import vga_pkg::*;

module vga_controller #(
    parameter VGA_mode_e RESOLUTION       = VGA_1024x768_60,
    parameter int        C_R_WIDTH        = 5,
    parameter int        C_G_WIDTH        = 6,
    parameter int        C_B_WIDTH        = 5,
    parameter int        AXIS_TDATA_WIDTH = 16,     // Šírka dát zo streamu (16 pre RGB565, 24 pre RGB888)
    parameter int        AXIS_TUSER_WIDTH = 1,
    parameter int        FIFO_DEPTH       = 1024,
    parameter bit        TEST_MODE        = 0,
    parameter bit        USE_RGB888       = 0       // Ak 1, očakáva 24-bitové RGB vstupy
)(
    input  logic pix_clk,
    input  logic pix_rstn,
    input  logic axi_clk,
    input  logic axi_rstn,

    // AXI4-Stream vstup pixelov
    input  logic [AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input  logic [AXIS_TUSER_WIDTH-1:0] s_axis_tuser,
    input  logic                        s_axis_tlast,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,

    // VGA výstupy (RGB a sync signály)
    output logic [C_R_WIDTH-1:0] VGA_R,
    output logic [C_G_WIDTH-1:0] VGA_G,
    output logic [C_B_WIDTH-1:0] VGA_B,
    output logic                 VGA_HS,
    output logic                 VGA_VS,

    // Stavové signály FIFO
    output logic overflow_sticky_flag,
    output logic underflow_sticky_flag,

    // Debug výstupy
    output logic [15:0] valid_pixel_counter, // Počet platných pixelov od začiatku rámca
    output logic        fifo_active          // FIFO nie je prázdna
);

    // --- VGA timing signály ---
    line_t h_line, v_line;
    position_t pos;
    signal_t signal;

    // Na základe zvolenej rozlíšenia načítaj VGA časovanie
    always_comb begin
        get_vga_timing(RESOLUTION, h_line, v_line);
    end

    // Inštancia modulu pre generovanie VGA sync signálov a pozície pixelu
    Vga_timing vga_timing_inst (
        .clk_pix(pix_clk), .rstn(pix_rstn),
        .h_line(h_line),   .v_line(v_line),
        .pos(pos),         .signal(signal)
    );

    // --- FIFO dátová štruktúra pre stream ---
    localparam int PAYLOAD_WIDTH = 1 + AXIS_TUSER_WIDTH + AXIS_TDATA_WIDTH;
    typedef struct packed {
        logic                       TLAST;  // Indikácia konca riadku
        logic [AXIS_TUSER_WIDTH-1:0] TUSER;
        logic [AXIS_TDATA_WIDTH-1:0] TDATA;
    } stream_payload_t;

    // --- FIFO kontrolné signály ---
    logic wr_en, full, rd_en, empty, overflow, underflow;
    stream_payload_t fifo_wr_data, fifo_rd_data, pixel_reg;

    // --- Detekcia začiatku a konca rámca na pix_clk ---
    logic start_of_frame_condition, end_of_frame_condition;
    assign start_of_frame_condition = signal.active && (pos.x == 0) && (pos.y == 0);
    assign end_of_frame_condition   = signal.active && (pos.x == h_line.visible_area-1) && (pos.y == v_line.visible_area-1);

    // Synchronizácia týchto signálov do axi_clk domény pre riadenie stream_enabled
    logic start_of_frame_pix_clk_reg, end_of_frame_pix_clk_reg;
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn) begin
            start_of_frame_pix_clk_reg <= 0;
            end_of_frame_pix_clk_reg <= 0;
        end else begin
            start_of_frame_pix_clk_reg <= start_of_frame_condition;
            end_of_frame_pix_clk_reg   <= end_of_frame_condition;
        end
    end

    logic start_of_frame_axi_clk, end_of_frame_axi_clk;
    TwoFlopSynchronizer #(.WIDTH(1)) frame_start_sync (.clk(axi_clk), .rst_n(axi_rstn), .d(start_of_frame_pix_clk_reg), .q(start_of_frame_axi_clk));
    TwoFlopSynchronizer #(.WIDTH(1)) frame_end_sync   (.clk(axi_clk), .rst_n(axi_rstn), .d(end_of_frame_pix_clk_reg),   .q(end_of_frame_axi_clk));

    // Stream povolený medzi začiatkom a koncom rámca
    logic stream_enabled;
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)
            stream_enabled <= 0;
        else if (start_of_frame_axi_clk)
            stream_enabled <= 1;
        else if (end_of_frame_axi_clk)
            stream_enabled <= 0;
    end

    // FIFO zápis podmienka: stream povolený + FIFO nie je full + axi stream validný
    assign s_axis_tready = stream_enabled && !full;
    assign wr_en = s_axis_tvalid && s_axis_tready;
    assign fifo_wr_data = '{TUSER: s_axis_tuser, TLAST: s_axis_tlast, TDATA: s_axis_tdata};

    // --- Inštancia asynchrónneho FIFO pre clock domain crossing ---
    AsyncFIFO #(
        .DATA_WIDTH(PAYLOAD_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) fifo_inst (
        .wr_clk(axi_clk), .wr_rstn(axi_rstn),
        .wr_en(wr_en), .wr_data(fifo_wr_data),
        .full(full), .overflow(overflow),

        .rd_clk(pix_clk), .rd_rstn(pix_rstn),
        .rd_en(rd_en), .rd_data(fifo_rd_data),
        .empty(empty), .underflow(underflow)
    );

    // FIFO čítanie povolené ak pixel aktívny a FIFO nie je prázdna
    assign rd_en = signal.active && !empty;

    // Indikácia podtečenia FIFO počas aktívnej pixelovej oblasti
    logic underflow_detected = signal.active && empty;
    assign fifo_active = !empty;

    // Registrácia pixelových dát pre použitie v pix_clk doméne
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)
            pixel_reg <= '{default:'0};
        else if (rd_en)
            pixel_reg <= fifo_rd_data;
    end

    // --- Sticky flagy pre overflow/underflow, resetované na začiatku rámca ---
    logic overflow_sticky, underflow_sticky;
    assign overflow_sticky_flag = overflow_sticky;
    assign underflow_sticky_flag = underflow_sticky;

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)
            overflow_sticky <= 0;
        else if (overflow)
            overflow_sticky <= 1;
        else if (start_of_frame_axi_clk)
            overflow_sticky <= 0;
    end

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)
            underflow_sticky <= 0;
        else if (underflow)
            underflow_sticky <= 1;
        else if (start_of_frame_pix_clk_reg)
            underflow_sticky <= 0;
    end

    // --- Dekódovanie farieb ---
    localparam int COLOR_WIDTH = C_R_WIDTH + C_G_WIDTH + C_B_WIDTH;
    logic [COLOR_WIDTH-1:0] pixel_color;

    // Funkcia pre prevod vstupných pixelov do výstupného formátu
    function logic [COLOR_WIDTH-1:0] decode_color(input logic [AXIS_TDATA_WIDTH-1:0] data);
        if (USE_RGB888) begin
            // Pre RGB888 očakávame 24-bitové vstupy:
            // data[23:16] = R, [15:8] = G, [7:0] = B
            // Tu zúžime na RGB565 (5,6,5 bitov)
            // Ak nie je šírka 24, odporúčame upraviť AXIS_TDATA_WIDTH param.
            return {
                data[23:19],    // 5 bitov R
                data[15:10],    // 6 bitov G
                data[7:3]       // 5 bitov B
            };
        end else begin
            // Pri RGB565 jednoducho skopíruj vstupné bity (16 bitov)
            return data[COLOR_WIDTH-1:0];
        end
    endfunction

    // --- Výber farby pre VGA výstup ---
    always_comb begin
        if (TEST_MODE) begin
            // Testovacia paleta farieb (8 pásiem)
            unique case (1'b1)
                !signal.active: pixel_color = 0;
                pos.x < h_line.visible_area/8 * 1: pixel_color = 16'hFFFF; // Biela
                pos.x < h_line.visible_area/8 * 2: pixel_color = 16'hFFE0; // Žltá
                pos.x < h_line.visible_area/8 * 3: pixel_color = 16'h07FF; // Azúrová
                pos.x < h_line.visible_area/8 * 4: pixel_color = 16'h07E0; // Zelená
                pos.x < h_line.visible_area/8 * 5: pixel_color = 16'hF81F; // Ružová
                pos.x < h_line.visible_area/8 * 6: pixel_color = 16'hF800; // Červená
                pos.x < h_line.visible_area/8 * 7: pixel_color = 16'h001F; // Modrá
                default: pixel_color = 16'h0000; // Čierna
            endcase
        end else begin
            // Dekóduj farbu z FIFO dát
            pixel_color = decode_color(pixel_reg.TDATA);
        end
    end

    // --- Výstup RGB pre VGA ---
    // Vyberáme jednotlivé kanály z pixel_color (RGB565)
    assign VGA_R = pixel_color[COLOR_WIDTH-1 -: C_R_WIDTH];
    assign VGA_G = pixel_color[C_B_WIDTH + C_G_WIDTH - 1 -: C_G_WIDTH];
    assign VGA_B = pixel_color[C_B_WIDTH - 1 -: C_B_WIDTH];

	     typedef struct packed { logic h_sync, v_sync, active, blank; } signal_t;
	 
    // --- Výstup sync signály ---
    assign VGA_HS = signal.hsync;
    assign VGA_VS = signal.vsync;

    // --- Počítadlo platných pixelov (debug) ---
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)
            valid_pixel_counter <= 0;
        else if (start_of_frame_condition)
            valid_pixel_counter <= 0;
        else if (signal.active)
            valid_pixel_counter <= valid_pixel_counter + 1;
    end

endmodule
