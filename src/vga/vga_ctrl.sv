`ifndef VGA_CTRL_FIXED
`define VGA_CTRL_FIXED

`timescale 1ns/1ns
(* default_nettype = "none" *)

import vga_pkg::*;

module vga_ctrl #(
    parameter vga_data_t BLANKING_COLOR = BLACK,
    parameter vga_data_t UNDERRUN_COLOR = PURPLE,
    parameter int MAX_COUNTER_H = MaxPosCounterX,
    parameter int MAX_COUNTER_V = MaxPosCounterY
)(
    // Vstupy
    input  wire logic clk_i,
    input  wire logic rst_ni,
    input  wire logic enable_i,
    input  line_t     h_line_i,
    input  line_t     v_line_i,
    input  vga_data_t fifo_data_i, // Používame jednotný typ vga_data_t
    input  wire logic fifo_empty_i,

    // Výstupy
    output logic      hde_o,
    output logic      vde_o,
    output vga_data_t dat_o,
    output vga_sync_t syn_o,
    output logic      eol_o,
    output logic      eof_o,

    // ZMENA: Pridaný nový výstupný port na riadenie FIFO
    output logic      fifo_rd_en_o
);

    wire hde_d, vde_d;
    wire hsyn_d, vsyn_d;
    wire eol_d, eof_d;
    wire valid_pixel, underrun;

    reg        hde_q, vde_q;
    reg        eol_q, eof_q;
    vga_data_t data_q;
    vga_sync_t sync_q;

    vga_timing #(
        .MAX_COUNTER_H(MAX_COUNTER_H),
        .MAX_COUNTER_V(MAX_COUNTER_V)
    ) timing_inst (
        .clk_i(clk_i), .rst_ni(rst_ni), .enable_i(enable_i),
        .h_line_i(h_line_i), .v_line_i(v_line_i),
        .hde_o(hde_d), .vde_o(vde_d), .hsyn_o(hsyn_d), .vsyn_o(vsyn_d),
        .eol_o(eol_d), .eof_o(eof_d)
    );

    assign underrun    = hde_d & vde_d & fifo_empty_i;
    assign valid_pixel = hde_d & vde_d & ~fifo_empty_i;

    // ZMENA: Logika pre `rd_en` je teraz bezpečne tu.
    // Používame `_d` (neregistrované) signály na vyžiadanie dát o 1 takt skôr (prefetch).
    assign fifo_rd_en_o = hde_d & vde_d;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            hde_q <= 1'b0; vde_q <= 1'b0; data_q <= BLANKING_COLOR;
            sync_q.hs <= 1'b1; sync_q.vs <= 1'b1;
            eol_q <= 1'b0; eof_q <= 1'b0;
        end else if (enable_i) begin
            hde_q <= hde_d; vde_q <= vde_d;
            sync_q.hs <= hsyn_d; sync_q.vs <= vsyn_d;
            eol_q <= eol_d; eof_q <= eof_d;

            if (underrun)           data_q <= UNDERRUN_COLOR;
            else if (valid_pixel)   data_q <= fifo_data_i;
            else                    data_q <= BLANKING_COLOR;
        end
    end

    assign hde_o = hde_q; assign vde_o = vde_q;
    assign dat_o = data_q; assign syn_o = sync_q;
    assign eol_o = eol_q; assign eof_o = eof_q;
endmodule
`endif