// =============================================================================
// Súbor: framebuffer_ctrl.sv
// Verzia: 2.0 - Refaktorovaný s podporou testovacích režimov
// Dátum: 12. október 2025
//
// Popis:
// Modul bol refaktorovaný tak, aby podporoval viacero operačných a
// diagnostických režimov voliteľných cez jeden parameter `C_OP_MODE`.
// To odstraňuje potrebu manuálneho komentovania kódu a zjednodušuje
// testovanie jednotlivých častí systému.
//
// =============================================================================

`ifndef FRAMEBUFFER_CTRL_SV
`define FRAMEBUFFER_CTRL_SV

(* default_nettype = "none" *)
import axi_pkg::*;
import axis_streamer_pkg::*;
import framebuffer_pkg::*;

module framebuffer_ctrl #(

    // ZMEŇTE REŽIM PREPINANÍM HODNOTY TOHTO PARAMETRA
    parameter op_mode_e C_OP_MODE = NORMAL,

    // Ostatné parametre zostávajú
    parameter int CLOCK_FREQ_HZ   = 100_000_000,
    parameter int BRAM_H_RES      = 64,
    parameter int BRAM_V_RES      = 48,
    parameter int H_RES           = 800,
    parameter int V_RES           = 600,
    parameter int tRP             = 3,
    parameter int tRCD            = 3,
    parameter int tWR             = 2,
    parameter int tRFC            = 9,
    parameter int tRAS            = 7,
    parameter int CAS_LATENCY     = 3
)(
    input  logic axi_clk_i,
    input  logic axi_rst_ni,
    input  logic clk_i,
    input  logic clk_sh_i,
    input  logic rst_ni,

    axi4s_if.slave  s_axis_video_in,
    axi4s_if.master m_axis_video_out,

    output logic [12:0] sdram_addr,
    output logic [1:0]  sdram_ba,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    inout wire [15:0] sdram_dq, // Toto je už správne
    output logic [1:0]  sdram_dqm,
    output logic        sdram_cke,
    output logic        sdram_clk,

    output logic [7:0] debug_led_o
);

import sdram_pkg::*;

    // --- Parametre ---
//    localparam integer CLOCK_FREQ_HZ    = 100_000_000;
    localparam integer CLK_PERIOD       = 10; // ns
    localparam integer DATA_WIDTH       = 16;

    // Konfigurácia pre Wrapper
    localparam integer PACKET_LEN_WORDS = 480_000; // 800 * 600
    localparam integer BURST_LEN        = 8;
    localparam integer NUM_BUFFERS      = 2; // Double-Buffering

    // --- Signály ---
    logic clk;
    logic clk_sh;
    logic rstn;

    // --- Priradenie hodín a resetu ---
    assign clk = clk_i;
    assign clk_sh = clk_sh_i;
    assign rstn = rst_ni;

    // AXI-Stream signály
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic                  s_axis_tvalid;
    logic                  s_axis_tready;
    logic                  s_axis_tlast;

    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic                  m_axis_tvalid;
    logic                  m_axis_tready;
    logic                  m_axis_tlast;

    // SDRAM Controller Interface
    logic                     cmd_fifo_valid;
    logic                     cmd_fifo_ready;
    sdram_cmd_t               cmd_fifo_data;
    logic                     wdata_valid;
    logic [DATA_WIDTH-1:0]    wdata;
    logic [1:0]               wdata_dqm_i;
    logic                     wdata_ready;
    logic                     resp_valid;
    logic                     resp_last;
    logic [DATA_WIDTH-1:0]    resp_data;
    logic                     resp_ready;

    // Debug porty
    buffer_state_t debug_buffer_state [0:NUM_BUFFERS-1];
    logic [$clog2(NUM_BUFFERS)-1:0] debug_find_empty_start_idx;
    logic [$clog2(NUM_BUFFERS)-1:0] debug_find_full_start_idx;

    // Premenné pre kontrolu dát
    logic [DATA_WIDTH-1:0] frame0_first_word, frame0_last_word;
    logic [DATA_WIDTH-1:0] frame1_first_word, frame1_last_word;

    // =========================================================================
    // --- VÝBER OPERAČNÉHO REŽIMU ---
    // =========================================================================
    generate
        if (C_OP_MODE == NORMAL) begin : g_normal_mode

            // --- Pripojenie AXI-Stream rozhraní k interným signálom ---
            assign s_axis_tdata  = s_axis_video_in.TDATA;
            assign s_axis_tvalid = s_axis_video_in.TVALID;
            assign s_axis_tlast  = s_axis_video_in.TLAST;
            assign s_axis_video_in.TREADY = s_axis_tready; // Spätné priradenie

            assign m_axis_video_out.TDATA  = m_axis_tdata;
            assign m_axis_video_out.TVALID = m_axis_tvalid;
            assign m_axis_video_out.TLAST  = m_axis_tlast;
            assign m_axis_tready = m_axis_video_out.TREADY; // Spätné priradenie

            // --- Inštancia Wrapperu ---
            AxiStreamSdramWrapper #(
                .AXIS_DATA_WIDTH(DATA_WIDTH),
                .PACKET_LEN_WORDS(PACKET_LEN_WORDS),
                .BURST_LEN(BURST_LEN),
                .NUM_BUFFERS(NUM_BUFFERS)
            ) wrapper_inst (
                .clk, .rstn,
                .s_axis_tdata, .s_axis_tvalid, .s_axis_tready, .s_axis_tlast,
                .m_axis_tdata, .m_axis_tvalid, .m_axis_tready, .m_axis_tlast,
                .cmd_fifo_valid, .cmd_fifo_ready, .cmd_fifo_data,
                .wdata_valid, .wdata, .wdata_dqm_i, .wdata_ready,
                .resp_valid, .resp_last, .resp_data, .resp_ready,
                .debug_buffer_state, .debug_find_empty_start_idx, .debug_find_full_start_idx
            );

            // --- Inštancia SDRAM Kontroléra (v6.10 Quartus-Ready) ---
            SdramController #(
                .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
                .DATA_WIDTH(DATA_WIDTH),
                .BURST_LEN(BURST_LEN)
            ) sdram_inst (
                .clk, .clk_sh, .rstn,
                .cmd_fifo_valid, .cmd_fifo_ready, .cmd_fifo_data,
                .resp_valid, .resp_last, .resp_data, .resp_ready,
                .wdata_valid, .wdata, .wdata_dqm_i, .wdata_ready,
                .sdram_addr, .sdram_ba, .sdram_cs_n, .sdram_ras_n, .sdram_cas_n, .sdram_we_n,
                .sdram_dq, .sdram_dqm, .sdram_cke, .sdram_clk
            );

            assign debug_led_o[0] = s_axis_video_in.TVALID;
            assign debug_led_o[1] = s_axis_video_in.TREADY;
            assign debug_led_o[2] = m_axis_video_out.TVALID;
            assign debug_led_o[3] = m_axis_video_out.TREADY;

            assign debug_led_o[7:6] = debug_find_empty_start_idx;
            assign debug_led_o[5:4] = debug_find_full_start_idx;

        end else if (C_OP_MODE == PASSTHROUGH) begin : gen_passthrough
            // --- Zoskratovanie AXI-Stream vstupu priamo na výstup ---
            assign m_axis_video_out.TDATA  = s_axis_video_in.TDATA;
            assign m_axis_video_out.TVALID = s_axis_video_in.TVALID;
            assign m_axis_video_out.TLAST  = s_axis_video_in.TLAST;
            assign m_axis_video_out.TUSER  = s_axis_video_in.TUSER;
            assign s_axis_video_in.TREADY  = m_axis_video_out.TREADY; // Prepojenie spätného tlaku

            // --- Ukončenie nepoužívaných SDRAM portov ---
            // Bezpečné zaparkovanie SDRAM pinov
            assign sdram_dq    = 16'bz;
            assign sdram_addr  = 13'b0;
            assign sdram_ba    = 2'b0;
            assign sdram_cs_n  = 1'b1; // Inactive
            assign sdram_ras_n = 1'b1; // Inactive
            assign sdram_cas_n = 1'b1; // Inactive
            assign sdram_we_n  = 1'b1; // Inactive
            assign sdram_dqm   = 2'b0;
            assign sdram_cke   = 1'b0; // Clock Enable low (disabled/power-down)
            assign sdram_clk   = 1'b0;

            // Diagnostika pre tento režim
            assign debug_led_o[0] = s_axis_video_in.TVALID;
            assign debug_led_o[1] = s_axis_video_in.TREADY;
            assign debug_led_o[2] = m_axis_video_out.TVALID;
            assign debug_led_o[3] = m_axis_video_out.TREADY;
            assign debug_led_o[7:4] = 4'b0;

        end
    endgenerate


endmodule
`endif
