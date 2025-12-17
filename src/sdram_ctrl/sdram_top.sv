/**
 * @file        sdram_top.sv
 * @brief       Top-Level SDRAM Interface (Wrapper).
 * @details     Integruje 'sdram_ctrl' (jadro) a 'sdram_cmd_checker' (ochrana).
 * Poskytuje jednotné, bezpečné rozhranie pre užívateľa.
 *
 * Tok dát:
 * User Cmd  -> [Checker] -> [Controller] -> SDRAM
 * User Data -> [Controller (Skid+FIFO)]  -> SDRAM
 *
 * @param CFifoAddrWidth Hĺbka interných FIFO bufferov (2^N).
 * @param T_*_CYCLES     Časovanie SDRAM.
 */

`default_nettype none

`ifndef SDRAM_TOP_SV
`define SDRAM_TOP_SV

import sdram_pkg::*;

module sdram_top #(
    parameter int CFifoAddrWidth = 6,
    // Timing Parameters (Propagované do ctrl a checkera)
    parameter int T_RAS_CYCLES   = sdram_pkg::T_RAS_CYCLES,
    parameter int T_RCD_CYCLES   = sdram_pkg::T_RCD_CYCLES,
    parameter int T_RP_CYCLES    = sdram_pkg::T_RP_CYCLES,
    parameter int T_WR_CYCLES    = sdram_pkg::T_WR_CYCLES,
    parameter int T_RFC_CYCLES   = sdram_pkg::T_RFC_CYCLES,
    parameter int T_MRD_CYCLES   = sdram_pkg::T_MRD_CYCLES,
    parameter int CAS_LATENCY    = sdram_pkg::CAS_LATENCY,
    parameter int BURST_LEN      = sdram_pkg::BURST_LEN
)(
    // --- System ---
    input  logic                               clk_i,
    input  logic                               clk_sh_i, // Phase-shifted clock for SDRAM
    input  logic                               rst_ni,   // Asynchronous reset active low
    input  logic                               error_clear_i, // Clears sticky errors

    // --- User Command Interface ---
    // Write Command
    input  sdram_pkg::sdram_cmd_t                   wr_cmd_data_i,
    input  logic                               wr_cmd_valid_i,
    output logic                               wr_cmd_ready_o,
    // Read Command
    input  sdram_pkg::sdram_cmd_t                   rd_cmd_data_i,
    input  logic                               rd_cmd_valid_i,
    output logic                               rd_cmd_ready_o,

    // --- User Data Interface ---
    // Write Data
    input  logic [sdram_pkg::DATA_WIDTH-1:0]   wdata_i,
    input  logic [sdram_pkg::DATA_WIDTH/8-1:0] wdata_be_i,
    input  logic                               wdata_valid_i,
    output logic                               wdata_ready_o,
    output logic [CFifoAddrWidth:0]            wdata_level_o,

    // Read Data
    output logic [sdram_pkg::DATA_WIDTH-1:0]   rdata_o,
    output logic                               rdata_valid_o,
    input  logic                               rdata_ready_i,
    output logic [CFifoAddrWidth:0]            rdata_level_o,

    // --- Diagnostics ---
    output logic                               busy_o,
    output logic                               cmd_error_o,   // From Checker
    output logic [15:0]                        error_code_o,  // From Checker
    output logic [1:0]                         fifo_error_o,  // From Ctrl

    // --- SDRAM Physical Interface ---
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0]  sdram_addr_o,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba_o,
    output logic                                  sdram_cs_n_o,
    output logic                                  sdram_ras_n_o,
    output logic                                  sdram_cas_n_o,
    output logic                                  sdram_we_n_o,
    inout  logic [sdram_pkg::DATA_WIDTH-1:0]      sdram_dq_io,
    output logic [sdram_pkg::DATA_WIDTH/8-1:0]    sdram_dqm_o,
    output logic                                  sdram_cke_o,
    output logic                                  sdram_clk_o
);

    // -------------------------------------------------------------------------
    // Internal Signals: Checker -> Controller Glue
    // -------------------------------------------------------------------------
    sdram_pkg::sdram_cmd_t  chk_wr_cmd;
    logic                   chk_wr_valid;
    logic                   chk_wr_ready;

    sdram_pkg::sdram_cmd_t  chk_rd_cmd;
    logic                   chk_rd_valid;
    logic                   chk_rd_ready;

    // -------------------------------------------------------------------------
    // 1. Instance: Command Checker (Gatekeeper)
    // -------------------------------------------------------------------------
    // Validuje príkazy od užívateľa predtým, než sa dostanú do FSM radiča.
    
    sdram_cmd_checker #(
        .C_NUM_BANKS  (1 << sdram_pkg::BANK_ADDR_WIDTH),
        .T_RAS_CYCLES (T_RAS_CYCLES), 
        .T_RP_CYCLES  (T_RP_CYCLES), 
        .T_WR_CYCLES  (T_WR_CYCLES)
    ) u_checker (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .clear_errors_i (error_clear_i),

        // Input from User
        .wr_cmd_i       (wr_cmd_data_i),
        .wr_cmd_valid_i (wr_cmd_valid_i),
        .wr_cmd_ready_o (wr_cmd_ready_o),

        .rd_cmd_i       (rd_cmd_data_i),
        .rd_cmd_valid_i (rd_cmd_valid_i),
        .rd_cmd_ready_o (rd_cmd_ready_o),

        // Output to Controller
        .wr_cmd_o       (chk_wr_cmd),
        .wr_cmd_valid_o (chk_wr_valid),
        .wr_cmd_ready_i (chk_wr_ready),

        .rd_cmd_o       (chk_rd_cmd),
        .rd_cmd_valid_o (chk_rd_valid),
        .rd_cmd_ready_i (chk_rd_ready),

        // Diag
        .cmd_error_o    (cmd_error_o),
        .error_code_o   (error_code_o)
    );

    // -------------------------------------------------------------------------
    // 2. Instance: SDRAM Controller (Core)
    // -------------------------------------------------------------------------
    // Vykonáva príkazy, spravuje refresh a fyzickú vrstvu.
    
    sdram_ctrl #(
        .CFifoAddrWidth (CFifoAddrWidth),
        // Forward Timings
        .T_RAS_CYCLES   (T_RAS_CYCLES),
        .T_RCD_CYCLES   (T_RCD_CYCLES),
        .T_RP_CYCLES    (T_RP_CYCLES),
        .T_WR_CYCLES    (T_WR_CYCLES),
        .T_RFC_CYCLES   (T_RFC_CYCLES),
        .T_MRD_CYCLES   (T_MRD_CYCLES),
        .CAS_LATENCY    (CAS_LATENCY),
        .BURST_LEN      (BURST_LEN)
    ) u_ctrl (
        // System
        .clk_i          (clk_i),
        .clk_sh_i       (clk_sh_i),
        .rst_ni         (rst_ni),
        .error_clear_i  (error_clear_i),

        // Commands from Checker
        .wr_cmd_data_i  (chk_wr_cmd),
        .wr_cmd_valid_i (chk_wr_valid),
        .wr_cmd_ready_o (chk_wr_ready),

        .rd_cmd_data_i  (chk_rd_cmd),
        .rd_cmd_valid_i (chk_rd_valid),
        .rd_cmd_ready_o (chk_rd_ready),

        // Data Paths (User Direct Access - Internal Skid Buffers handle timing)
        .wdata_i        (wdata_i),
        .wdata_be_i     (wdata_be_i),
        .wdata_valid_i  (wdata_valid_i),
        .wdata_ready_o  (wdata_ready_o),
        .wdata_level_o  (wdata_level_o),

        .rdata_o        (rdata_o),
        .rdata_valid_o  (rdata_valid_o),
        .rdata_ready_i  (rdata_ready_i),
        .rdata_level_o  (rdata_level_o),

        // PHY Interface
        .sdram_addr_o   (sdram_addr_o),
        .sdram_ba_o     (sdram_ba_o),
        .sdram_cs_n_o   (sdram_cs_n_o),
        .sdram_ras_n_o  (sdram_ras_n_o),
        .sdram_cas_n_o  (sdram_cas_n_o),
        .sdram_we_n_o   (sdram_we_n_o),
        .sdram_dq_io    (sdram_dq_io),
        .sdram_dqm_o    (sdram_dqm_o),
        .sdram_cke_o    (sdram_cke_o),
        .sdram_clk_o    (sdram_clk_o),

        // Diag
        .busy_o         (busy_o),
        .fifo_error_o   (fifo_error_o)
    );

endmodule

`endif // SDRAM_TOP_SV

`default_nettype wire
