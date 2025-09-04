`ifndef AXISTREAMTOVGA
`define AXISTREAMTOVGA

`timescale 1ns/1ns
`default_nettype none

import vga_pkg::*;
import axi_pkg::*;

// =============================================================================
// == Modul: AxiStreamToVGA
// == Popis: Hlavný modul, ktorý premosťuje AXI4-Stream na paralelný VGA výstup.
// ==        Používa asynchrónne FIFO a inštancuje finálny `Vga` radič.
// =============================================================================
module AxiStreamToVGA #(
    // --- Parametre ---
    parameter int        FIFO_DEPTH = 2048,           // Hĺbka FIFO buffera
    parameter VGA_mode_e C_VGA_MODE = VGA_640x480_60  // Pevne nastavený VGA režim
)(
    // --- AXI Hodinová Doména ---
    input  logic axi_clk_i,
    input  logic axi_rst_ni,

    // --- Pixel Hodinová Doména ---
    input  logic pix_clk_i,
    input  logic pix_rst_ni,

    // --- AXI Stream Rozhranie (slave) ---
    axi4s_if.slave s_axis,

    // --- Výstupy do fyzického VGA rozhrania ---
    output VGA_data_t vga_data_o,
    output VGA_sync_t vga_sync_o,
    output logic      hde_o,
    output logic      vde_o
);

    // =========================================================================
    // ==                          INTERNÉ SIGNÁLY                          ==
    // =========================================================================

    // --- FIFO Rozhranie ---
    logic           wr_en;
    axi4s_payload_t fifo_wr_data;
    logic           full;

    logic           rd_en;
    axi4s_payload_t fifo_rd_data;
    logic           empty;


    // =========================================================================
    // ==                    AXI DOMÉNA -> ZÁPIS DO FIFO                    ==
    // =========================================================================

    // Povolíme zápis do FIFO, ak sú dáta platné (TVALID) a FIFO nie je plné.
    assign wr_en = s_axis.TVALID && !full;
    // Spätný signál TREADY hovorí masteru, či sme pripravení prijať dáta.
    assign s_axis.TREADY = !full;
    // Priame priradenie AXI-Stream signálov do štruktúry pre zápis do FIFO.
    assign fifo_wr_data = '{TUSER: s_axis.TUSER, TLAST: s_axis.TLAST, TDATA: s_axis.TDATA};


    // =========================================================================
    // ==                       ASYNCHRÓNNE FIFO                            ==
    // =========================================================================

    AsyncFIFO #(
        .DATA_WIDTH($bits(axi4s_payload_t)),
        .DEPTH(FIFO_DEPTH)
    ) fifo_inst (
        // Zápisová strana - riadená AXI hodinami
        .wr_clk_i     (axi_clk_i),
        .wr_rst_ni    (axi_rst_ni),
        .wr_en_i      (wr_en),
        .wr_data_i    (fifo_wr_data),
        .full_o       (full),
        .overflow_o   (), // Výstup pretečenia nevyužívame

        // Čítacia strana - riadená Pixel hodinami
        .rd_clk_i     (pix_clk_i),
        .rd_rst_ni    (pix_rst_ni),
        .rd_en_i      (rd_en),
        .rd_data_o    (fifo_rd_data),
        .empty_o      (empty),
        .underflow_o  () // Výstup podtečenia nevyužívame
    );


    // =========================================================================
    // ==                PIXEL DOMÉNA -> INŠTANCIA VGA RADIČA               ==
    // =========================================================================

    // Získame parametre pre požadovaný VGA režim pomocou funkcie z vga_pkg.
    // Tieto parametre sa použijú na konfiguráciu `Vga` modulu.
    localparam VGA_params_t C_VGA_PARAMS = get_vga_params(C_VGA_MODE);

    // Inštancia finálneho `Vga` modulu, ktorý sme predtým odladili.
    Vga vga_inst (
        .clk_i        (pix_clk_i),
        .rst_ni       (pix_rst_ni),
        .enable_i     (1'b1), // VGA radič beží neustále, keď nie je v resete

        // Konfigurácia časovania na základe zvoleného režimu
        .h_line_i     (C_VGA_PARAMS.h_line),
        .v_line_i     (C_VGA_PARAMS.v_line),

        // Pripojenie na čítaciu stranu FIFO
        .fifo_data_i  (fifo_rd_data.TDATA), // Na vstup posielame len dátovú časť
        .fifo_empty_i (empty),

        // Priame pripojenie výstupov na výstupné porty tohto modulu
        .hde_o        (hde_o),
        .vde_o        (vde_o),
        .dat_o        (vga_data_o),
        .syn_o        (vga_sync_o),
        .eol_o        (), // Tieto pulzy nepotrebujeme na výstupe
        .eof_o        ()
    );


    // =========================================================================
    // ==              PIXEL DOMÉNA -> RIADENIE ČÍTANIA Z FIFO              ==
    // =========================================================================

    // Povolíme čítanie z FIFO (vygenerujeme `rd_en` pulz) vždy, keď je
    // VGA radič v aktívnej oblasti (hde_o a vde_o sú '1').
    assign rd_en = hde_o && vde_o;

endmodule

`endif //AXISTREAMTOVGA