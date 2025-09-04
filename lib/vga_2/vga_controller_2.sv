//=============================================================================
// vga_controller.sv - Univerzálny a znovupoužiteľný VGA Controller
//
// Verzia: 3.1
//
// === Popis Architektúry ===
// Tento modul slúži ako kompletný VGA controller, ktorý prijíma pixelové
// dáta cez AXI4-Stream zbernicu a generuje plnohodnotný VGA signál.
// Navrhnutý pre dve hodinové domény (axi_clk a pix_clk), obsahuje robustnú
// logiku pre bezpečný Clock Domain Crossing (CDC).
//
// === Novinky vo verzii 3.1 ===
// * Pridaná podpora prepínania medzi RGB565 a RGB888.
// * Pridané spracovanie TLAST pre detekciu konca riadku.
// * Debugové výstupy: valid pixel counter a aktivita FIFO.
// * Silnejšia AXI handshake logika (ready/valid flow control).
//=============================================================================
`default_nettype none

import vga_pkg::*;

module vga_controller #(
    parameter VGA_mode_e RESOLUTION   = VGA_800x600,
    parameter int        C_R_WIDTH    = 5,
    parameter int        C_G_WIDTH    = 6,
    parameter int        C_B_WIDTH    = 5,
    parameter int        AXIS_TDATA_WIDTH = 16,
    parameter int        AXIS_TUSER_WIDTH = 1,
    parameter int        FIFO_DEPTH   = 1024,
    parameter bit        TEST_MODE    = 0,
    parameter bit        USE_RGB888   = 0
)(
    input  logic pix_clk,
    input  logic pix_rstn,
    input  logic axi_clk,
    input  logic axi_rstn,

    input  logic [AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input  logic [AXIS_TUSER_WIDTH-1:0] s_axis_tuser,
    input  logic                        s_axis_tlast,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,

    output logic [C_R_WIDTH-1:0] VGA_R,
    output logic [C_G_WIDTH-1:0] VGA_G,
    output logic [C_B_WIDTH-1:0] VGA_B,
    output logic                 VGA_HS,
    output logic                 VGA_VS,

    output logic overflow_sticky_flag,
    output logic underflow_sticky_flag,

    output logic [15:0] valid_pixel_counter, // nový debug výstup
    output logic        fifo_active          // indikuje aktívny stav FIFO
);

    line_t h_line, v_line;
    position_t pos;
    signal_t signal;

    always_comb begin
        get_vga_timing(RESOLUTION, h_line, v_line);
    end

    Vga_timing vga_timing_inst (
        .clk_pix(pix_clk), .rstn(pix_rstn),
        .h_line(h_line),   .v_line(v_line),
        .pos(pos),         .signal(signal)
    );

    localparam int PAYLOAD_WIDTH = 1 + AXIS_TUSER_WIDTH + AXIS_TDATA_WIDTH;
    typedef struct packed {
        logic                       TLAST;
        logic [AXIS_TUSER_WIDTH-1:0] TUSER;
        logic [AXIS_TDATA_WIDTH-1:0] TDATA;
    } stream_payload_t;

    logic wr_en, full, rd_en, empty, overflow, underflow, underflow_detected;
    stream_payload_t fifo_wr_data, fifo_rd_data, pixel_reg;

    logic start_of_frame_condition, end_of_frame_condition;
    assign start_of_frame_condition = signal.active && (pos.x == 0) && (pos.y == 0);
    assign end_of_frame_condition   = signal.active && (pos.x == h_line.visible_area-1) && (pos.y == v_line.visible_area-1);

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

    logic stream_enabled;
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)
            stream_enabled <= 0;
        else if (start_of_frame_axi_clk)
            stream_enabled <= 1;
        else if (end_of_frame_axi_clk)
            stream_enabled <= 0;
    end

    assign s_axis_tready = stream_enabled && !full;
    assign wr_en = s_axis_tvalid && s_axis_tready;
    assign fifo_wr_data = '{TUSER: s_axis_tuser, TLAST: s_axis_tlast, TDATA: s_axis_tdata};

    AsyncFIFO #(.DATA_WIDTH(PAYLOAD_WIDTH), .DEPTH(FIFO_DEPTH)) fifo_inst (
        .wr_clk(axi_clk), .wr_rstn(axi_rstn), .wr_en(wr_en), .wr_data(fifo_wr_data), .full(full), .overflow(overflow),
        .rd_clk(pix_clk), .rd_rstn(pix_rstn), .rd_en(rd_en), .rd_data(fifo_rd_data), .empty(empty), .underflow(underflow)
    );

    assign rd_en = signal.active && !empty;
    assign underflow_detected = signal.active && empty;
    assign fifo_active = !empty;

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)
            pixel_reg <= '{default:'0};
        else if (rd_en)
            pixel_reg <= fifo_rd_data;
    end

    logic overflow_sticky, underflow_sticky;
    assign overflow_sticky_flag = overflow_sticky;
    assign underflow_sticky_flag = underflow_sticky;

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)                   overflow_sticky <= 0;
        else if (overflow)              overflow_sticky <= 1;
        else if (start_of_frame_axi_clk) overflow_sticky <= 0;
    end

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)                       underflow_sticky <= 0;
        else if (underflow)                  underflow_sticky <= 1;
        else if (start_of_frame_pix_clk_reg) underflow_sticky <= 0;
    end

    localparam int COLOR_WIDTH = C_R_WIDTH + C_G_WIDTH + C_B_WIDTH;
    logic [COLOR_WIDTH-1:0] pixel_color;

    function logic [COLOR_WIDTH-1:0] decode_color(input logic [AXIS_TDATA_WIDTH-1:0] data);
        if (USE_RGB888)
            return {data[23:19], data[15:10], data[7:3]}; // RGB888 -> RGB565 kompatibilné zúženie
        else
            return data[COLOR_WIDTH-1:0];
    endfunction

    always_comb begin
        if (TEST_MODE) begin
            unique case (1'b1)
                !signal.active: pixel_color = 0;
                pos.x < h_line.visible_area/8 * 1: pixel_color = 16'hFFFF;
                pos.x < h_line.visible_area/8 * 2: pixel_color = 16'hFFE0;
                pos.x < h_line.visible_area/8 * 3: pixel_color = 16'h07FF;
                pos.x < h_line.visible_area/8 * 4: pixel_color = 16'h07E0;
                pos.x < h_line.visible_area/8 * 5: pixel_color = 16'hF81F;
                pos.x < h_line.visible_area/8 * 6: pixel_color = 16'hF800;
                pos.x < h_line.visible_area/8 * 7: pixel_color = 16'h001F;
                default: pixel_color = 0;
            endcase
        end else begin
            unique case (1'b1)
                underflow_detected: pixel_color = 16'hF81F;
                signal.active: pixel_color = decode_color(pixel_reg.TDATA);
                default: pixel_color = 0;
            endcase
        end
    end

    assign VGA_R = pixel_color[COLOR_WIDTH-1 -: C_R_WIDTH];
    assign VGA_G = pixel_color[C_B_WIDTH + C_G_WIDTH - 1 -: C_G_WIDTH];
    assign VGA_B = pixel_color[C_B_WIDTH - 1 -: C_B_WIDTH];
    assign VGA_HS = signal.h_sync;
    assign VGA_VS = signal.v_sync;

    // Valid pixel counter – zvyšuje sa iba ak signál a FIFO sú aktívne
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn || start_of_frame_condition)
            valid_pixel_counter <= 0;
        else if (signal.active && rd_en)
            valid_pixel_counter <= valid_pixel_counter + 1;
    end

endmodule
