/**
 * @file        axis_picture_generator.sv
 * @brief       Generátor testovacích obrazcov pre AXI4-Stream.
 * @details     Generuje statické a animované obrazce vo formáte RGB565.
 * Využíva 4-stupňovú pipeline pre dosiahnutie vysokého časovania (timing closure).
 * Obsahuje optimalizácie pre matematické operácie (fixed-point násobenie).
 *
 * @param H_RES       Horizontálne rozlíšenie.
 * @param V_RES       Vertikálne rozlíšenie.
 * @param DATA_WIDTH  Šírka TDATA (RGB565 = 16).
 * @param USER_WIDTH  Šírka TUSER.
 * @param NUM_MODES   Počet režimov.
 */

`default_nettype none

`ifndef AXIS_PICTURE_GENERATOR_SV
`define AXIS_PICTURE_GENERATOR_SV

import axi_pkg::*; // Import AXI parametrov

module axis_picture_generator #(
    // --- Rozlíšenie ---
    parameter int unsigned H_RES = 640,
    parameter int unsigned V_RES = 480,

    // --- AXI4-Stream parametre ---
    parameter int unsigned DATA_WIDTH = axi_pkg::AXI_TDATA_WIDTH,
    parameter int unsigned USER_WIDTH = axi_pkg::AXI_TUSER_WIDTH,
    parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int unsigned ID_WIDTH   = 0,
    parameter int unsigned DEST_WIDTH = 0,

    // --- Konfigurácia ---
    parameter int unsigned NUM_MODES  = 8
)(
    // --- Hodiny a Reset ---
    input  wire logic clk_i,
    input  wire logic rst_ni,

    // --- Control ---
    input  wire logic [$clog2(NUM_MODES)-1:0] mode_i,

    // --- AXI4-Stream Výstup ---
    axi4s_if.master m_axis
);

    // -------------------------------------------------------------------------
    // 1. Konštanty a Typy
    // -------------------------------------------------------------------------
    localparam int CLog2HRes  = $clog2(H_RES);
    localparam int CLog2VRes  = $clog2(V_RES);
    localparam int CModeWidth = $clog2(NUM_MODES);

    localparam int CCheckerSizeSmall = 3;
    localparam int CCheckerSizeLarge = 5;
    localparam int CAnimWidth        = 8;

    // Fixed-point matematika (Q18) pre výpočet pruhov
    function automatic int calc_recip_div8_q18(input int unsigned hres);
        return ((1 << 18) * 8 + (hres / 2)) / hres;
    endfunction

    localparam int C_RECIP_HRES_DIV8_Q18 = calc_recip_div8_q18(H_RES);
    localparam int C_Q_SHIFT             = 18;
    localparam int C_MOD_64_MASK         = 6'h3F;

    typedef enum logic [CModeWidth-1:0] {
        MODE_CHECKER_SMALL = 3'd0,
        MODE_CHECKER_LARGE = 3'd1,
        MODE_H_GRADIENT    = 3'd2,
        MODE_V_GRADIENT    = 3'd3,
        MODE_COLOR_BARS    = 3'd4,
        MODE_CROSSHAIR     = 3'd5,
        MODE_DIAG_SCROLL   = 3'd6,
        MODE_MOVING_BAR    = 3'd7
    } mode_e;

    typedef struct packed {
        logic [4:0] red;
        logic [5:0] grn;
        logic [4:0] blu;
    } rgb565_t;

    localparam rgb565_t
        CColorBlack    = 16'h0000,
        CColorWhite    = 16'hFFFF,
        CColorRed      = 16'hF800,
        CColorGreen    = 16'h07E0,
        CColorBlue     = 16'h001F,
        CColorYellow   = 16'hFFE0,
        CColorCyan     = 16'h07FF,
        CColorMagenta  = 16'hF81F,
        CColorOrange   = 16'hFC00;

    localparam rgb565_t CColorPalette [0:7] = '{
        CColorRed, CColorOrange, CColorYellow, CColorGreen,
        CColorCyan, CColorBlue, CColorMagenta, CColorWhite
    };

    // -------------------------------------------------------------------------
    // 2. Signály Pipeline
    // -------------------------------------------------------------------------
    
    // Riadenie toku
    logic can_advance;

    // Stage 0: Counters
    logic [CLog2HRes-1:0]  x_reg, x_next;
    logic [CLog2VRes-1:0]  y_reg, y_next;
    logic [CModeWidth-1:0] mode_q;
    logic [CAnimWidth-1:0] scroll_offset;
    logic                  active_area_comb;
    logic                  start_of_frame_comb;
    logic                  end_of_line_comb;

    // Stage 1: Registered Inputs
    logic [CLog2HRes-1:0]  x_s1_reg;
    logic [CLog2VRes-1:0]  y_s1_reg;
    logic [CModeWidth-1:0] mode_q_s1_reg;
    logic [CAnimWidth-1:0] scroll_offset_s1_reg;
    logic                  active_area_s1_reg;
    logic                  eol_s1_reg;
    logic                  sof_s1_reg;

    // Stage 2: Math Results
    logic [3:0]                       bar_idx_comb_raw;
    logic [CLog2HRes+CLog2VRes:0]     sum_xy_comb;
    logic                             bar_on_comb;
    logic [2:0]                       bar_idx_s2_reg;
    logic [CLog2HRes+CLog2VRes:0]     sum_xy_s2_reg;
    logic                             bar_on_s2_reg;
    // Delayed Stage 2
    logic [CLog2HRes-1:0]             x_s2_reg;
    logic [CLog2VRes-1:0]             y_s2_reg;
    logic [CModeWidth-1:0]            mode_q_s2_reg;
    logic                             active_area_s2_reg;
    logic                             eol_s2_reg;
    logic                             sof_s2_reg;

    // Stage 3: MUX
    rgb565_t              pixel_data_s3_comb;
    rgb565_t              pixel_data_s3_reg;
    logic                 active_area_s3_reg;
    logic                 eol_s3_reg;
    logic                 sof_s3_reg;

    // Stage 4: Output Registers
    logic                 tvalid_reg_out;
    logic                 tlast_reg_out;
    logic [USER_WIDTH-1:0] tuser_reg_out;
    rgb565_t              pixel_data_reg_out;

    // -------------------------------------------------------------------------
    // Stage 0: Počítadlá a Základná Logika
    // -------------------------------------------------------------------------
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            x_reg <= '0;
            y_reg <= '0;
        end else if (can_advance) begin
            x_reg <= x_next;
            y_reg <= y_next;
        end
    end

    always_comb begin
        x_next = x_reg;
        y_next = y_reg;
        if (x_reg == H_RES - 1) begin
            x_next = '0;
            y_next = (y_reg == V_RES - 1) ? '0 : y_reg + 1'b1;
        end else begin
            x_next = x_reg + 1'b1;
        end
    end

    assign active_area_comb    = (x_reg < H_RES) && (y_reg < V_RES);
    assign start_of_frame_comb = (x_reg == 0) && (y_reg == 0);
    assign end_of_line_comb    = (x_reg == H_RES - 1);

    // Control Registers
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mode_q        <= '0;
            scroll_offset <= '0;
        end else if (can_advance) begin
            mode_q <= mode_i;
            if ((x_reg == H_RES - 1) && (y_reg == V_RES - 1)) begin
                scroll_offset <= scroll_offset + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 1: Registrácia pre Math
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            x_s1_reg             <= '0;
            y_s1_reg             <= '0;
            mode_q_s1_reg        <= '0;
            scroll_offset_s1_reg <= '0;
            active_area_s1_reg   <= 1'b0;
            eol_s1_reg           <= 1'b0;
            sof_s1_reg           <= 1'b0;
        end else if (can_advance) begin
            x_s1_reg             <= x_reg;
            y_s1_reg             <= y_reg;
            mode_q_s1_reg        <= mode_q;
            scroll_offset_s1_reg <= scroll_offset;
            active_area_s1_reg   <= active_area_comb;
            eol_s1_reg           <= end_of_line_comb && active_area_comb;
            sof_s1_reg           <= start_of_frame_comb && active_area_comb;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 1->2: Kombinačná matematika (Heavy Lifting)
    // -------------------------------------------------------------------------
    always_comb begin
        logic [CLog2HRes + C_Q_SHIFT - 1:0] bar_idx_product;
        logic [CLog2HRes + CAnimWidth : 0]  sum_mod_comb;

        // 1. Color Bars Index (Fixed Point Mul)
        bar_idx_product  = x_s1_reg * C_RECIP_HRES_DIV8_Q18;
        bar_idx_comb_raw = 4'(bar_idx_product >> C_Q_SHIFT);

        // 2. Moving Bar Logic
        sum_mod_comb = x_s1_reg + scroll_offset_s1_reg;
        bar_on_comb  = (sum_mod_comb & C_MOD_64_MASK) < 16;

        // 3. Diagonal Scroll
        sum_xy_comb = x_s1_reg + y_s1_reg + scroll_offset_s1_reg;
    end

    // -------------------------------------------------------------------------
    // Stage 2: Capture Math Results
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            bar_idx_s2_reg     <= '0;
            sum_xy_s2_reg      <= '0;
            bar_on_s2_reg      <= 1'b0;
            x_s2_reg           <= '0;
            y_s2_reg           <= '0;
            mode_q_s2_reg      <= '0;
            active_area_s2_reg <= 1'b0;
            eol_s2_reg         <= 1'b0;
            sof_s2_reg         <= 1'b0;
        end else if (can_advance) begin
            // Math results
            bar_idx_s2_reg     <= (bar_idx_comb_raw >= 8) ? 3'd7 : 3'(bar_idx_comb_raw);
            sum_xy_s2_reg      <= sum_xy_comb;
            bar_on_s2_reg      <= bar_on_comb;
            
            // Pipeline forwarding
            x_s2_reg           <= x_s1_reg;
            y_s2_reg           <= y_s1_reg;
            mode_q_s2_reg      <= mode_q_s1_reg;
            active_area_s2_reg <= active_area_s1_reg;
            eol_s2_reg         <= eol_s1_reg;
            sof_s2_reg         <= sof_s1_reg;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: Pixel Generation MUX
    // -------------------------------------------------------------------------
    always_comb begin
        pixel_data_s3_comb = CColorBlack;

        if (active_area_s2_reg) begin
            unique case (mode_e'(mode_q_s2_reg))
                MODE_CHECKER_SMALL: begin
                    pixel_data_s3_comb = (x_s2_reg[CCheckerSizeSmall] ^ y_s2_reg[CCheckerSizeSmall]) 
                                         ? CColorWhite : CColorBlack;
                end
                MODE_CHECKER_LARGE: begin
                    pixel_data_s3_comb = (x_s2_reg[CCheckerSizeLarge] ^ y_s2_reg[CCheckerSizeLarge]) 
                                         ? CColorBlue : CColorYellow;
                end
                MODE_COLOR_BARS: begin
                    pixel_data_s3_comb = CColorPalette[bar_idx_s2_reg];
                end
                MODE_CROSSHAIR: begin
                    logic is_vert_line, is_horiz_line;
                    logic [CLog2HRes-1:0] center_x = H_RES >> 1;
                    logic [CLog2VRes-1:0] center_y = V_RES >> 1;
                    
                    is_vert_line  = (x_s2_reg >= center_x - 1) && (x_s2_reg <= center_x + 1);
                    is_horiz_line = (y_s2_reg >= center_y - 1) && (y_s2_reg <= center_y + 1);
                    pixel_data_s3_comb = (is_vert_line || is_horiz_line) ? CColorWhite : CColorBlue;
                end
                MODE_H_GRADIENT: begin
                    logic [CLog2HRes-1:0] x_shift_g, x_shift_b;
                    pixel_data_s3_comb.red = x_s2_reg[9:5];
                    x_shift_g              = x_s2_reg >> 2;
                    pixel_data_s3_comb.grn = x_shift_g[9:4];
                    x_shift_b              = x_s2_reg >> 4;
                    pixel_data_s3_comb.blu = x_shift_b[9:5];
                end
                MODE_V_GRADIENT: begin
                    logic [CLog2VRes-1:0] y_shift_g, y_shift_b;
                    pixel_data_s3_comb.red = y_s2_reg[8:4];
                    y_shift_g              = y_s2_reg >> 2;
                    pixel_data_s3_comb.grn = y_shift_g[8:3];
                    y_shift_b              = y_s2_reg >> 3;
                    pixel_data_s3_comb.blu = y_shift_b[8:4];
                end
                MODE_DIAG_SCROLL: begin
                    pixel_data_s3_comb.red = sum_xy_s2_reg[4 +: 5];
                    pixel_data_s3_comb.grn = sum_xy_s2_reg[3 +: 6];
                    pixel_data_s3_comb.blu = sum_xy_s2_reg[2 +: 5];
                end
                MODE_MOVING_BAR: begin
                    pixel_data_s3_comb = bar_on_s2_reg ? CColorRed : CColorBlack;
                end
                default: pixel_data_s3_comb = CColorOrange;
            endcase
        end
    end

    // Stage 3 Registers
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            active_area_s3_reg <= 1'b0;
            eol_s3_reg         <= 1'b0;
            sof_s3_reg         <= 1'b0;
            pixel_data_s3_reg  <= '0;
        end else if (can_advance) begin
            active_area_s3_reg <= active_area_s2_reg;
            eol_s3_reg         <= eol_s2_reg;
            sof_s3_reg         <= sof_s2_reg;
            pixel_data_s3_reg  <= pixel_data_s3_comb;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 4: Final Output
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tvalid_reg_out     <= 1'b0;
            tlast_reg_out      <= 1'b0;
            tuser_reg_out      <= '0;
            pixel_data_reg_out <= '0;
        end else if (can_advance) begin
            tvalid_reg_out     <= active_area_s3_reg;
            tlast_reg_out      <= eol_s3_reg;
            tuser_reg_out      <= {USER_WIDTH{sof_s3_reg}};
            pixel_data_reg_out <= pixel_data_s3_reg;
        end
    end

    // -------------------------------------------------------------------------
    // AXI Output Mapping & Handshake
    // -------------------------------------------------------------------------
    // Skid Buffer logic: Pause pipeline if output valid AND slave not ready
    assign can_advance = m_axis.TREADY || !tvalid_reg_out;

    assign m_axis.TVALID = tvalid_reg_out;
    assign m_axis.TDATA  = pixel_data_reg_out;
    assign m_axis.TLAST  = tlast_reg_out;
    assign m_axis.TUSER  = tuser_reg_out;

    assign m_axis.TKEEP  = (KEEP_WIDTH > 0) ? {KEEP_WIDTH{1'b1}} : '0;
    assign m_axis.TID    = (ID_WIDTH > 0)   ? {ID_WIDTH{1'b0}}   : '0;
    assign m_axis.TDEST  = (DEST_WIDTH > 0) ? {DEST_WIDTH{1'b0}} : '0;

endmodule

`default_nettype wire

`endif // AXIS_PICTURE_GENERATOR_SV
