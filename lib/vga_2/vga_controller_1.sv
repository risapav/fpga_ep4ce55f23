//=============================================================================
// vga_controller.sv - Univerzálny a znovupoužiteľný VGA Controller (Refaktorovaný)
//
// Verzia: 3.1 (Refaktorovaná podľa odporúčaní)
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
    parameter bit        TEST_MODE    = 0
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
    output logic underflow_sticky_flag
);

    //==========================================================================
    // ČASŤ 1: INTERNÉ VGA ČASOVANIE
    //==========================================================================

    line_t     h_line, v_line;
    position_t pos;
    signal_t   signal;

    always_comb begin
        get_vga_timing(RESOLUTION, h_line, v_line);
    end

    Vga_timing vga_timing_inst (
        .clk_pix(pix_clk), .rstn(pix_rstn),
        .h_line(h_line),   .v_line(v_line),
        .pos(pos),         .signal(signal)
    );

    //==========================================================================
    // ČASŤ 2: FIFO, SYNCHRONIZÁCIA A STREAM LOGIKA
    //==========================================================================

    localparam int PAYLOAD_WIDTH = AXIS_TDATA_WIDTH + AXIS_TUSER_WIDTH + 1; // TDATA + TUSER + TLAST
    localparam int COLOR_WIDTH = C_R_WIDTH + C_G_WIDTH + C_B_WIDTH;

    typedef struct packed {
        logic                         TLAST;
        logic [AXIS_TUSER_WIDTH-1:0] TUSER;
        logic [AXIS_TDATA_WIDTH-1:0] TDATA;
    } stream_payload_t;

    logic wr_en, full, rd_en, empty, overflow, underflow, underflow_detected;
    stream_payload_t fifo_wr_data, fifo_rd_data, pixel_reg;

    // CDC: Detekcia začiatku/konca snímky
    logic sof_pix_reg, eof_pix_reg;
    logic sof_axi_sync, eof_axi_sync;

    assign sof_pix_reg = signal.active && (pos.x == 0) && (pos.y == 0);
    assign eof_pix_reg = signal.active && (pos.x == h_line.visible_area - 1) && (pos.y == v_line.visible_area - 1);

    logic sof_pix_latched, eof_pix_latched;
    always_ff @(posedge pix_clk) begin
        if (!pix_rstn) begin
            sof_pix_latched <= 1'b0;
            eof_pix_latched <= 1'b0;
        end else begin
            sof_pix_latched <= sof_pix_reg;
            eof_pix_latched <= eof_pix_reg;
        end
    end

    TwoFlopSynchronizer #(.WIDTH(1)) sync_sof (.clk(axi_clk), .rst_n(axi_rstn), .d(sof_pix_latched), .q(sof_axi_sync));
    TwoFlopSynchronizer #(.WIDTH(1)) sync_eof (.clk(axi_clk), .rst_n(axi_rstn), .d(eof_pix_latched), .q(eof_axi_sync));

    logic stream_enabled;
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)             stream_enabled <= 1'b0;
        else if (sof_axi_sync)     stream_enabled <= 1'b1;
        else if (eof_axi_sync)     stream_enabled <= 1'b0;
    end

    assign s_axis_tready = stream_enabled && !full;
    assign wr_en         = s_axis_tvalid && s_axis_tready;

    assign fifo_wr_data = '{TUSER: s_axis_tuser, TLAST: s_axis_tlast, TDATA: s_axis_tdata};

    AsyncFIFO #(.DATA_WIDTH(PAYLOAD_WIDTH), .DEPTH(FIFO_DEPTH)) fifo_inst (
        .wr_clk(axi_clk), .wr_rstn(axi_rstn), .wr_en(wr_en), .wr_data(fifo_wr_data), .full(full), .overflow(overflow),
        .rd_clk(pix_clk), .rd_rstn(pix_rstn), .rd_en(rd_en), .rd_data(fifo_rd_data), .empty(empty), .underflow(underflow)
    );

    assign rd_en = signal.active && !empty;
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

    always_ff @(posedge axi_clk) begin
        if (!axi_rstn)              overflow_sticky <= 1'b0;
        else if (overflow)         overflow_sticky <= 1'b1;
        else if (eof_axi_sync)     overflow_sticky <= 1'b0;
    end

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn)             underflow_sticky <= 1'b0;
        else if (underflow)        underflow_sticky <= 1'b1;
        else if (sof_pix_latched)  underflow_sticky <= 1'b0;
    end

    //==========================================================================
    // ČASŤ 4: GENERÁTOR FARBIEK A VÝSTUP
    //==========================================================================

    function automatic [COLOR_WIDTH-1:0] encode_color(input logic[7:0] r, g, b);
        return {r[7 -: C_R_WIDTH], g[7 -: C_G_WIDTH], b[7 -: C_B_WIDTH]};
    endfunction

    logic [COLOR_WIDTH-1:0] pixel_color;

    always_comb begin
        if (TEST_MODE) begin
            unique case (1'b1)
                !signal.active: pixel_color = '0;
                pos.x < (h_line.visible_area/8)*1: pixel_color = encode_color(8'hFF, 8'hFF, 8'hFF); // Biela
                pos.x < (h_line.visible_area/8)*2: pixel_color = encode_color(8'hFF, 8'hFF, 8'h00); // Žltá
                pos.x < (h_line.visible_area/8)*3: pixel_color = encode_color(8'h00, 8'hFF, 8'hFF); // Tyrkysová
                pos.x < (h_line.visible_area/8)*4: pixel_color = encode_color(8'h00, 8'hFF, 8'h00); // Zelená
                pos.x < (h_line.visible_area/8)*5: pixel_color = encode_color(8'hFF, 8'h00, 8'hFF); // Fialová
                pos.x < (h_line.visible_area/8)*6: pixel_color = encode_color(8'hFF, 8'h00, 8'h00); // Červená
                pos.x < (h_line.visible_area/8)*7: pixel_color = encode_color(8'h00, 8'h00, 8'hFF); // Modrá
                default:                           pixel_color = '0;
            endcase
        end else begin
            unique case (1'b1)
                underflow_detected: pixel_color = encode_color(8'hFF, 8'h00, 8'hFF); // Fialová = podtečenie
                signal.active:      pixel_color = pixel_reg.TDATA;
                default:            pixel_color = '0;
            endcase
        end
    end

    assign VGA_R  = pixel_color[COLOR_WIDTH-1 -: C_R_WIDTH];
    assign VGA_G  = pixel_color[C_B_WIDTH + C_G_WIDTH - 1 -: C_G_WIDTH];
    assign VGA_B  = pixel_color[C_B_WIDTH - 1 -: C_B_WIDTH];
    assign VGA_HS = signal.h_sync;
    assign VGA_VS = signal.v_sync;

endmodule
