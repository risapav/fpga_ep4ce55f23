`ifndef VGA_CTRL_HYBRID
`define VGA_CTRL_HYBRID

`timescale 1ns/1ns
(* default_nettype = "none" *)

import vga_pkg::*;

module vga_ctrl #(
    parameter vga_data_t BLANKING_COLOR   = BLUE,
    parameter vga_data_t UNDERRUN_COLOR   = PURPLE,
    parameter int MAX_COUNTER_H           = 2047,
    parameter int MAX_COUNTER_V           = 2047,
    parameter bit ASYNC_RESET             = 0   // 0 = synchrónny, 1 = asynchrónny
)(
    // --- Vstupy ---
    input  logic clk_i,
    input  logic rst_ni,
    input  logic enable_i,
    input  line_t h_line_i,
    input  line_t v_line_i,
    input  vga_data_t fifo_data_i,
    input  logic fifo_empty_i,

    // --- Výstupy ---
    output logic hde_o,
    output logic vde_o,
    output vga_data_t dat_o,
    output vga_sync_t syn_o,
    output logic eol_o,
    output logic eof_o,
    output logic fifo_rd_en_o
);

    // ================================
    // Lokálne premenné
    // ================================
    localparam int H_WIDTH = $clog2(MAX_COUNTER_H);
    localparam int V_WIDTH = $clog2(MAX_COUNTER_V);

    logic [H_WIDTH-1:0] h_count;
    logic [V_WIDTH-1:0] v_count;
    logic hde_d, vde_d, hsyn_d, vsyn_d, eol_d;
    logic [H_WIDTH-1:0] h_active, h_fp, h_sync, h_bp, h_total;
    logic [V_WIDTH-1:0] v_active, v_fp, v_sync, v_bp, v_total;

    // ================================
    // Priradenie hodnôt zo štruktúr
    // ================================
    assign h_active = h_line_i.visible_area;
    assign h_fp     = h_line_i.front_porch;
    assign h_sync   = h_line_i.sync_pulse;
    assign h_bp     = h_line_i.back_porch;
    assign h_total  = h_active + h_fp + h_sync + h_bp;

    assign v_active = v_line_i.visible_area;
    assign v_fp     = v_line_i.front_porch;
    assign v_sync   = v_line_i.sync_pulse;
    assign v_bp     = v_line_i.back_porch;
    assign v_total  = v_active + v_fp + v_sync + v_bp;

    // ================================
    // Sekvenčná logika čítačov s voliteľným resetom
    // ================================
    generate
        if (ASYNC_RESET) begin : gen_async_reset
            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    h_count <= '0;
                    v_count <= '0;
                end else if (enable_i) begin
                    if (h_count == h_total - 1) begin
                        h_count <= '0;
                        v_count <= (v_count == v_total - 1) ? '0 : v_count + 1;
                    end else h_count <= h_count + 1;
                end
            end
        end else begin : gen_sync_reset
            always_ff @(posedge clk_i) begin
                if (!rst_ni) begin
                    h_count <= '0;
                    v_count <= '0;
                end else if (enable_i) begin
                    if (h_count == h_total - 1) begin
                        h_count <= '0;
                        v_count <= (v_count == v_total - 1) ? '0 : v_count + 1;
                    end else h_count <= h_count + 1;
                end
            end
        end
    endgenerate

    // ================================
    // Kombinačná logika
    // ================================
    assign hde_d = (h_count >= (h_sync + h_bp)) && (h_count < (h_sync + h_bp + h_active));
    assign vde_d = (v_count >= (v_sync + v_bp)) && (v_count < (v_sync + v_bp + v_active));
    assign hsyn_d = (h_count < h_sync);
    assign vsyn_d = (v_count < v_sync);
    assign eol_d = (h_count == h_total - 1);

    assign fifo_rd_en_o = hde_d && vde_d && !fifo_empty_i;

    // ================================
    // Výstupná farba s pamäťou poslednej platnej hodnoty
    // ================================
    vga_data_t vga_data_reg;
    generate
        if (ASYNC_RESET) begin : gen_async_reset_outputs
            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    hde_o <= 1'b0;
                    vde_o <= 1'b0;
                    syn_o <= '{hs:1'b1, vs:1'b1};
                    eol_o <= 1'b0;
                    eof_o <= 1'b0;
                    vga_data_reg <= BLANKING_COLOR;
                end else if (enable_i) begin
                    hde_o <= hde_d;
                    vde_o <= vde_d;
                    eol_o <= eol_d;
                    eof_o <= eol_d && (v_count == v_total - 1);
                    syn_o.hs <= (hsyn_d != h_line_i.polarity);
                    syn_o.vs <= (vsyn_d != v_line_i.polarity);

                    if (hde_d && vde_d) begin
                        if (!fifo_empty_i) vga_data_reg <= fifo_data_i;
                    end else begin
                        vga_data_reg <= BLANKING_COLOR;
                    end
                end
            end
        end else begin : gen_sync_reset_outputs
            always_ff @(posedge clk_i) begin
                if (!rst_ni) begin
                    hde_o <= 1'b0;
                    vde_o <= 1'b0;
                    syn_o <= '{hs:1'b1, vs:1'b1};
                    eol_o <= 1'b0;
                    eof_o <= 1'b0;
                    vga_data_reg <= BLANKING_COLOR;
                end else if (enable_i) begin
                    hde_o <= hde_d;
                    vde_o <= vde_d;
                    eol_o <= eol_d;
                    eof_o <= eol_d && (v_count == v_total - 1);
                    syn_o.hs <= (hsyn_d != h_line_i.polarity);
                    syn_o.vs <= (vsyn_d != v_line_i.polarity);

                    if (hde_d && vde_d) begin
                        if (!fifo_empty_i) vga_data_reg <= fifo_data_i;
                    end else begin
                        vga_data_reg <= BLANKING_COLOR;
                    end
                end
            end
        end
    endgenerate


    assign dat_o = vga_data_reg;

endmodule

`endif // VGA_CTRL_HYBRID

