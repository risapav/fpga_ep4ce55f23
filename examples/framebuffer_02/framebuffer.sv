`ifndef FRAMEBUFFER_CTRL_SV
`define FRAMEBUFFER_CTRL_SV

(* default_nettype = "none" *)
import vga_pkg::*;
import axi_pkg::*;
import axis_streamer_pkg::*;

module framebuffer_ctrl #(
    parameter int H_RES = 800,
    parameter int V_RES = 600,
    parameter int FIFO_DEPTH = 2048
)(
    // --- Hodinové domény a resety ---
    input  logic axi_clk_i,
    input  logic axi_rst_ni,
    input  logic sdram_clk_i,
    input  logic sdram_rst_ni,

    // --- Video Stream Porty ---
    axi4s_if.slave  s_axis_video_in,
    axi4s_if.master m_axis_video_out,

    // --- SDRAM Porty ---
    inout  wire [15:0] SDRAM_DQ,
    output logic [12:0] SDRAM_ADDR,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CAS_N,
    output logic        SDRAM_CKE,
    output logic        SDRAM_CLK,
    output logic        SDRAM_CS_N,
    output logic        SDRAM_WE_N,
    output logic        SDRAM_RAS_N,
    output logic        SDRAM_UDQM,
    output logic        SDRAM_LDQM,

    // --- Diagnostika ---
    output logic [7:0] debug_led_o
);

    // =========================================================================
    // Interné FIFO pre test (AXI → AXI) - zatiaľ bez SDRAM
    // =========================================================================
    typedef struct packed {
        logic [15:0] TDATA;
        logic        TUSER;
        logic        TLAST;
    } fifo_payload_t;

    logic wr_en, rd_en;
    fifo_payload_t fifo_wr_data, fifo_rd_data;
    logic fifo_full, fifo_empty;

    // --- Priradenie AXI-Stream vstupu do FIFO zápisu ---
    assign wr_en       = s_axis_video_in.TVALID && !fifo_full;
    assign s_axis_video_in.TREADY = !fifo_full;
    assign fifo_wr_data = '{TDATA: s_axis_video_in.TDATA, TUSER: s_axis_video_in.TUSER, TLAST: s_axis_video_in.TLAST};

    // --- FIFO čítanie do AXI-Stream výstupu ---
    assign rd_en = m_axis_video_out.TREADY && !fifo_empty;
    assign m_axis_video_out.TVALID = !fifo_empty;
    assign m_axis_video_out.TDATA  = fifo_rd_data.TDATA;
    assign m_axis_video_out.TUSER  = fifo_rd_data.TUSER;
    assign m_axis_video_out.TLAST  = fifo_rd_data.TLAST;

    // --- Jednoduché asynchrónne FIFO ---
    cdc_async_fifo #(
        .DATA_WIDTH($bits(fifo_payload_t)),
        .DEPTH(FIFO_DEPTH)
    ) fifo_inst (
        .wr_clk_i(axi_clk_i),
        .wr_rst_ni(axi_rst_ni),
        .wr_en_i(wr_en),
        .wr_data_i(fifo_wr_data),
        .full_o(fifo_full),
        .overflow_o(),

        .rd_clk_i(axi_clk_i),
        .rd_rst_ni(axi_rst_ni),
        .rd_en_i(rd_en),
        .rd_data_o(fifo_rd_data),
        .empty_o(fifo_empty),
        .underflow_o()
    );

    // =========================================================================
    // Diagnostika
    // =========================================================================
    assign debug_led_o[0] = s_axis_video_in.TVALID;
    assign debug_led_o[1] = s_axis_video_in.TREADY;
    assign debug_led_o[2] = m_axis_video_out.TVALID;
    assign debug_led_o[3] = m_axis_video_out.TREADY;
    assign debug_led_o[4] = fifo_full;
    assign debug_led_o[5] = fifo_empty;
    assign debug_led_o[6] = 1'b0;
    assign debug_led_o[7] = 1'b0;

    // =========================================================================
    // SDRAM signály - pre test zatiaľ tristate alebo nula
    // =========================================================================
    assign SDRAM_DQ   = 16'bz;
    assign SDRAM_ADDR = 13'b0;
    assign SDRAM_BA   = 2'b0;
    assign SDRAM_CAS_N= 1'b1;
    assign SDRAM_CKE  = 1'b0;
    assign SDRAM_CLK  = 1'b0;
    assign SDRAM_CS_N = 1'b1;
    assign SDRAM_WE_N = 1'b1;
    assign SDRAM_RAS_N= 1'b1;
    assign SDRAM_UDQM = 1'b1;
    assign SDRAM_LDQM = 1'b1;

endmodule
`endif
