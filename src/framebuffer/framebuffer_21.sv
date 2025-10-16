// =============================================================================
// Súbor: framebuffer_ctrl.sv
// Verzia: 2.7 - Definitívna oprava systémového deadlocku
// Dátum: 15. október 2025
//
// Popis:
// Táto verzia opravuje kritickú chybu v prepojení medzi modulmi. Bol
// vytvorený spätnnoväzobný signál (`cmd_fifo_level_sig`), ktorý správne
// informuje `AxiStreamSdramWrapper` o úrovni zaplnenia príkazového FIFO
// v `SdramControllerFinal`. Tým sa zabraňuje preplneniu a rieši sa
// problém so systémovým zaseknutím (deadlock).
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

    // Parametre rozlíšenia a pamäte
    parameter int H_RES           = 800,
    parameter int V_RES           = 600
)(
    input  logic clk_i,
    input  logic clk_sh_i,
    input  logic rst_ni,

    // AXI-Stream rozhrania
    axi4s_if.slave  s_axis_video_in,
    axi4s_if.master m_axis_video_out,

    // SDRAM fyzické rozhranie
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    inout wire [sdram_pkg::DATA_WIDTH-1:0] sdram_dq,
    output logic [sdram_pkg::DATA_WIDTH/8-1:0] sdram_dqm,
    output logic sdram_cke,
    output logic sdram_clk,

    // Ladiace výstupy
    output logic [7:0] debug_led_0_o,
    output logic [7:0] debug_led_1_o
);

    import sdram_pkg::*;

    // --- Lokálne Parametre ---
    localparam integer NUM_BUFFERS = 2; // Double-Buffering
    localparam integer SEGMENT_LEN_WORDS = (H_RES * V_RES) / NUM_BUFFERS;
    localparam integer CMD_FIFO_DEPTH = 16; // Musí sa zhodovať s wrapperom

    // --- Interné Signály ---
    logic clk;
    logic clk_sh;
    logic rstn;

    assign clk = clk_i;
    assign clk_sh = clk_sh_i;
    assign rstn = rst_ni;

    // Signály pre prepojenie Wrapperu a Kontroléra
    logic                     cmd_fifo_valid;
    logic                     cmd_fifo_ready;
    sdram_cmd_t               cmd_fifo_data;
    logic [DATA_WIDTH-1:0]    wdata;
    logic [DATA_WIDTH/8-1:0]  wdata_dqm_i;
    logic                     wdata_valid;
    logic                     wdata_ready;
    logic                     resp_valid;
    logic                     resp_last;
    logic [DATA_WIDTH-1:0]    resp_data;
    logic                     resp_ready;

    // --- Signály pre ladiace informácie a spätnú väzbu ---
    logic stream_timeout_error_sig;
    // OPRAVA (v2.7): Signál pre spätnú väzbu o úrovni zaplnenia FIFO
    logic [$clog2(CMD_FIFO_DEPTH)-1:0] cmd_fifo_level_sig;


    // =========================================================================
    // --- VÝBER OPERAČNÉHO REŽIMU ---
    // =========================================================================
    generate
        if (C_OP_MODE == NORMAL) begin : g_normal_mode

            // --- Inštancia Wrapperu (posledná verzia) ---
            AxiStreamSdramWrapper #(
                .SEGMENT_LEN_WORDS(SEGMENT_LEN_WORDS),
                .NUM_BUFFERS(NUM_BUFFERS),
                .CMD_FIFO_DEPTH(CMD_FIFO_DEPTH)
            ) wrapper_inst (
                .clk(clk),
                .rstn(rstn),
                .soft_reset_i(1'b0),

                .s_axis_tdata(s_axis_video_in.TDATA),
                .s_axis_tvalid(s_axis_video_in.TVALID),
                .s_axis_tready(s_axis_video_in.TREADY),
                .s_axis_tlast(s_axis_video_in.TLAST),
                .s_axis_tuser_sof(s_axis_video_in.TUSER[0]),

                .m_axis_tdata(m_axis_video_out.TDATA),
                .m_axis_tvalid(m_axis_video_out.TVALID),
                .m_axis_tready(m_axis_video_out.TREADY),
                .m_axis_tlast(m_axis_video_out.TLAST),

                .cmd_fifo_valid(cmd_fifo_valid),
                .cmd_fifo_ready(cmd_fifo_ready),
                // OPRAVA (v2.7): Správne prepojenie spätnej väzby
                .cmd_fifo_level_i(cmd_fifo_level_sig),
                .cmd_fifo_data(cmd_fifo_data),
                .wdata_valid(wdata_valid),
                .wdata(wdata),
                .wdata_dqm_i(wdata_dqm_i),
                .wdata_ready(wdata_ready),
                .resp_valid(resp_valid),
                .resp_last(resp_last),
                .resp_data(resp_data),
                .resp_ready(resp_ready),

                // Prepojenie všetkých status a debug portov
                .stream_timeout_error(stream_timeout_error_sig),
                .active_reads(),
                .active_writes(),
                .debug_pipeline_level_o(),
                .debug_cmd_fifo_level_o(),
                .debug_write_ptr_o(debug_led_0_o[1:0]),
                .debug_read_ptr_o(debug_led_0_o[3:2])
            );

            // --- Inštancia SDRAM Kontroléra (posledná verzia) ---
            SdramControllerFinal #(
                .ENABLE_DEBUG(1'b1),
                .CMD_FIFO_DEPTH(CMD_FIFO_DEPTH)
            ) sdram_inst (
                .clk(clk),
                .clk_sh(clk_sh),
                .rstn(rstn),
                .cmd_fifo_valid(cmd_fifo_valid),
                .cmd_fifo_ready(cmd_fifo_ready),
                .cmd_fifo_data(cmd_fifo_data),
                .resp_valid(resp_valid),
                .resp_last(resp_last),
                .resp_data(resp_data),
                .resp_ready(resp_ready),
                .wdata_valid(wdata_valid),
                .wdata(wdata),
                .wdata_dqm_i(wdata_dqm_i),
                .wdata_ready(wdata_ready),
                .sdram_addr(sdram_addr),
                .sdram_ba(sdram_ba),
                .sdram_cs_n(sdram_cs_n),
                .sdram_ras_n(sdram_ras_n),
                .sdram_cas_n(sdram_cas_n),
                .sdram_we_n(sdram_we_n),
                .sdram_dq(sdram_dq),
                .sdram_dqm(sdram_dqm),
                .sdram_cke(sdram_cke),
                .sdram_clk(sdram_clk),
                .debug_state_o(debug_led_1_o[4:0]),
                .debug_rd_fifo_level_o(),
                .debug_wr_fifo_level_o(),
                // OPRAVA (v2.7): Výstup z kontroléra pripojený na spätnú väzbu
                .debug_cmd_fifo_level_o(cmd_fifo_level_sig)
            );

            // --- Ladiace LED ---
            assign debug_led_0_o[4] = stream_timeout_error_sig;
            assign debug_led_0_o[7:5] = cmd_fifo_level_sig[2:0]; // Zobrazenie úrovne CMD FIFO
            assign debug_led_1_o[7:5] = 3'b0; // Rezerva

        end else if (C_OP_MODE == PASSTHROUGH) begin : gen_passthrough
            assign m_axis_video_out.TDATA  = s_axis_video_in.TDATA;
            assign m_axis_video_out.TVALID = s_axis_video_in.TVALID;
            assign m_axis_video_out.TLAST  = s_axis_video_in.TLAST;
            assign m_axis_video_out.TUSER  = s_axis_video_in.TUSER;
            assign s_axis_video_in.TREADY  = m_axis_video_out.TREADY;

            assign sdram_dq    = {DATA_WIDTH{1'bz}};
            assign sdram_addr  = '0;
            assign sdram_ba    = '0;
            assign sdram_cs_n  = 1'b1;
            assign sdram_ras_n = 1'b1;
            assign sdram_cas_n = 1'b1;
            assign sdram_we_n  = 1'b1;
            assign sdram_dqm   = '0;
            assign sdram_cke   = 1'b0;
            assign sdram_clk   = 1'b0;

            assign debug_led_0_o[0] = s_axis_video_in.TVALID;
            assign debug_led_0_o[1] = s_axis_video_in.TREADY;
            assign debug_led_0_o[2] = m_axis_video_out.TVALID;
            assign debug_led_0_o[3] = m_axis_video_out.TREADY;
            assign debug_led_0_o[7:4] = 4'b0;
            assign debug_led_1_o = 8'h00;

        end
    endgenerate

endmodule
`endif

