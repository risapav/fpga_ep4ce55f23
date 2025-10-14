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
import vga_pkg::*;
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
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    inout  wire [15:0]  sdram_dq,
    output logic [1:0]  sdram_dqm,
    output logic sdram_cke,
    output logic sdram_clk,
    output logic [7:0] debug_led_o
);

// Generovanie logiky na základe zvoleného režimu
generate
    // ==============================================================
    // REŽIM 1: PASSTHROUGH (Premostenie)
    // Jednoducho prepojí vstupný stream na výstupný.
    // ==============================================================
    if (C_OP_MODE == PASSTHROUGH) begin : gen_passthrough
        assign m_axis_video_out.TVALID = s_axis_video_in.TVALID;
        assign m_axis_video_out.TDATA  = s_axis_video_in.TDATA;
        assign m_axis_video_out.TLAST  = s_axis_video_in.TLAST;
        assign m_axis_video_out.TUSER  = s_axis_video_in.TUSER;
        assign s_axis_video_in.TREADY  = m_axis_video_out.TREADY;

        // Bezpečné zaparkovanie SDRAM pinov
        assign sdram_dq    = 16'bz;
        assign sdram_addr  = 13'b0;
        assign sdram_ba    = 2'b0;
        assign sdram_cas_n = 1'b1;
        assign sdram_cke   = 1'b0;
        assign sdram_clk   = 1'b0;
        assign sdram_cs_n  = 1'b1;
        assign sdram_we_n  = 1'b1;
        assign sdram_ras_n = 1'b1;
        assign sdram_dqm   = 2'b0;

        // Diagnostika pre tento režim
        assign debug_led_o[0] = s_axis_video_in.TVALID;
        assign debug_led_o[1] = s_axis_video_in.TREADY;
        assign debug_led_o[2] = m_axis_video_out.TVALID;
        assign debug_led_o[3] = m_axis_video_out.TREADY;
        assign debug_led_o[7:4] = 4'b0;
    end
    // ==============================================================
    // OSTATNÉ REŽIMY (NORMAL, BRAM, DIAG_TEST)
    // Tieto režimy zdieľajú spoločnú štruktúru a signály.
    // ==============================================================
    else begin : gen_framebuffer_active
        // --- Spoločné signály a parametre pre všetky aktívne režimy ---
        localparam int ADDR_WIDTH = 24;
        localparam int FRAME_SIZE = H_RES * V_RES;
        logic [ADDR_WIDTH-1:0] BUFFER_0_BASE_ADDR = 0;
        logic [ADDR_WIDTH-1:0] BUFFER_1_BASE_ADDR = FRAME_SIZE;

        logic write_buffer_is_0_reg;
        logic [ADDR_WIDTH-1:0] write_buffer_base_addr, read_buffer_base_addr;

        logic                  sdram_reader_valid, sdram_reader_ready;
        logic [ADDR_WIDTH-1:0] sdram_reader_addr;
        logic                  sdram_writer_valid, sdram_writer_ready;
        logic [ADDR_WIDTH-1:0] sdram_writer_addr;
        logic [15:0]           sdram_writer_data;
        logic                  sdram_resp_valid, sdram_resp_last;
        logic [15:0]           sdram_resp_data;

        logic [$clog2(H_RES)-1:0] wr_x_cnt, rd_x_cnt;
        logic [$clog2(V_RES)-1:0] wr_y_cnt, rd_y_cnt;
        logic reading_active;

        // --------------------------------------------------------------
        // SEKČNÁ ČASŤ 1: Výber pamäťového úložiska (BRAM vs SDRAM)
        // --------------------------------------------------------------
        if (C_OP_MODE == BRAM_BACKEND) begin : bram_backend

            logic [15:0] bram_read_data_reg;
            logic        bram_resp_valid_reg, bram_resp_last_reg;
            // ... (kód pre BRAM zostáva nezmenený) ...
            localparam int BRAM_FRAME_SIZE = BRAM_H_RES * BRAM_V_RES;
            localparam int BRAM_DEPTH = BRAM_FRAME_SIZE * 2;
            localparam int BRAM_ADDR_WIDTH = $clog2(BRAM_DEPTH);

            logic [15:0] bram_mem [0:BRAM_DEPTH-1];
            logic [BRAM_ADDR_WIDTH-1:0] bram_wr_addr, bram_rd_addr, bram_rd_addr_reg;

            assign sdram_writer_ready = 1'b1;
            assign sdram_reader_ready = 1'b1;
            assign bram_wr_addr = (write_buffer_is_0_reg ? 0 : BRAM_FRAME_SIZE) + ((wr_y_cnt % BRAM_V_RES) * BRAM_H_RES) + (wr_x_cnt % BRAM_H_RES);
            assign bram_rd_addr = (write_buffer_is_0_reg ? BRAM_FRAME_SIZE : 0) + ((rd_y_cnt % BRAM_V_RES) * BRAM_H_RES) + (rd_x_cnt % BRAM_H_RES);

            always_ff @(posedge axi_clk_i)
              if (sdram_writer_valid) bram_mem[bram_wr_addr] <= sdram_writer_data;

            always_ff @(posedge axi_clk_i) begin
                bram_rd_addr_reg   <= bram_rd_addr; bram_read_data_reg <= bram_mem[bram_rd_addr_reg];
                bram_resp_valid_reg <= sdram_reader_valid;
                bram_resp_last_reg  <= (rd_x_cnt == H_RES-1) && (rd_y_cnt == V_RES-1) && sdram_reader_valid;
            end

            assign sdram_resp_valid = bram_resp_valid_reg;
            assign sdram_resp_last = bram_resp_last_reg;
            assign sdram_resp_data = bram_read_data_reg;
            assign sdram_dq = 16'bz;
            assign sdram_addr = 13'b0;
            assign sdram_ba = 2'b0;
            assign sdram_cas_n = 1'b1;
            assign sdram_cke = 1'b0;
            assign sdram_clk = 1'b0;
            assign sdram_cs_n = 1'b1;
            assign sdram_we_n = 1'b1;
            assign sdram_ras_n = 1'b1;
            assign sdram_dqm = 2'b0;
        end
        else begin : sdram_backend // Pre režimy NORMAL a DIAG_WRITE_READ_TEST
            // --- Inštancia SDRAM ovládača ---
            SdramDriver #(
                .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(16),
                .BURST_LENGTH(8),
                .PRIORITY_MODE("ROUND_ROBIN"),
                .tRP(tRP), .tRCD(tRCD), .tWR(tWR), .tRFC(tRFC), .tRAS(tRAS),
                .CAS_LATENCY(CAS_LATENCY)
            ) u_sdram_driver (
                .clk_axi(axi_clk_i), .clk(clk_i), .clk_sh(clk_sh_i),
                .rstn_axi(axi_rst_ni), .rstn(rst_ni),
                .reader_valid(sdram_reader_valid),
                .reader_ready(sdram_reader_ready),
                .reader_addr(sdram_reader_addr),
                .writer_valid(sdram_writer_valid),
                .writer_ready(sdram_writer_ready),
                .writer_addr(sdram_writer_addr),
                .writer_data(sdram_writer_data),
                .writer_dqm_i(2'b00),
                .resp_valid(sdram_resp_valid),
                .resp_last(sdram_resp_last),
                .resp_data(sdram_resp_data),
                .resp_ready(m_axis_video_out.TREADY),
                .error_overflow_o(),
                .error_underflow_o(),
                .error_clear_i(1'b0),
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
                .controller_state_o(debug_led_o[4:0]),
                .debug_arb_writer_ready_o(debug_led_o[5])
/*
                ,
                .debug_arb_reader_valid_o(debug_led_o[6]),
                .debug_arb_reader_ready_o(debug_led_o[7])
*/
            );
        end

        // --------------------------------------------------------------
        // SEKČNÁ ČASŤ 2: Výber riadiacej logiky (Normálna vs Diagnostická)
        // --------------------------------------------------------------
        if (C_OP_MODE == NORMAL || C_OP_MODE == BRAM_BACKEND) begin : normal_logic
            // --- NORMÁLNA WRITER LOGIKA ---
            always_ff @(posedge axi_clk_i or negedge axi_rst_ni) begin
                if (!axi_rst_ni) begin
                    wr_x_cnt <= '0; wr_y_cnt <= '0; write_buffer_is_0_reg <= 1'b1;
                end else begin
                    if (s_axis_video_in.TVALID && s_axis_video_in.TREADY) begin
                        if (wr_x_cnt == H_RES-1)
                          {wr_x_cnt, wr_y_cnt} <= (wr_y_cnt == V_RES-1) ? '0 : {0, wr_y_cnt + 1};
                        else
                          wr_x_cnt <= wr_x_cnt + 1;
                    end
                    if (s_axis_video_in.TVALID && s_axis_video_in.TREADY && s_axis_video_in.TLAST) begin
                        write_buffer_is_0_reg <= ~write_buffer_is_0_reg;
                    end
                end
            end
            assign sdram_writer_addr = write_buffer_base_addr + (wr_y_cnt*H_RES) + wr_x_cnt;
            assign sdram_writer_data = s_axis_video_in.TDATA; // Pre finálnu verziu
            // assign sdram_writer_data = 16'hF800; // Pre testovanie s červenou farbou
            assign sdram_writer_valid = s_axis_video_in.TVALID;
            assign s_axis_video_in.TREADY = sdram_writer_ready;

            // --- NORMÁLNA READER LOGIKA ---
            always_ff @(posedge axi_clk_i or negedge axi_rst_ni) begin
                if (!axi_rst_ni) begin
                    rd_x_cnt <= '0; rd_y_cnt <= '0; reading_active <= 1'b0;
                end else begin
                    if (m_axis_video_out.TREADY && !reading_active) reading_active <= 1'b1;
                    if (m_axis_video_out.TVALID && m_axis_video_out.TREADY) begin
                        if (rd_x_cnt == H_RES-1)
                          {rd_x_cnt, rd_y_cnt} <= (rd_y_cnt == V_RES-1) ? '0 : {0, rd_y_cnt + 1};
                        else
                          rd_x_cnt <= rd_x_cnt + 1;
                    end
                    if (m_axis_video_out.TVALID && m_axis_video_out.TREADY && m_axis_video_out.TLAST) begin
                       reading_active <= 1'b0; // Deaktivuj po skončení snímku
                    end
                end
            end
            assign sdram_reader_addr = read_buffer_base_addr + (rd_y_cnt*H_RES) + rd_x_cnt;
            assign sdram_reader_valid = reading_active;
            assign m_axis_video_out.TVALID = sdram_resp_valid;
            assign m_axis_video_out.TDATA  = sdram_resp_data;
            assign m_axis_video_out.TLAST  = sdram_resp_last;
            assign m_axis_video_out.TUSER  = 1'b0;
            assign write_buffer_base_addr = (write_buffer_is_0_reg) ? BUFFER_0_BASE_ADDR : BUFFER_1_BASE_ADDR;
            assign read_buffer_base_addr  = (write_buffer_is_0_reg) ? BUFFER_1_BASE_ADDR : BUFFER_0_BASE_ADDR;
        end
        else if (C_OP_MODE == DIAG_WRITE_READ_TEST) begin : diag_logic

            localparam int TEST_DURATION_CYCLES = 600_000_000; // 6 sekúnd pri 100MHz
            // --- DIAGNOSTICKÁ LOGIKA: ODDELENÝ ZÁPIS A ČÍTANIE ---
            logic [$clog2(TEST_DURATION_CYCLES)-1:0] test_timer;
            logic        write_phase_active;
            logic        read_phase_active;

            always_ff @(posedge axi_clk_i or negedge axi_rst_ni) begin
                if (!axi_rst_ni) test_timer <= '0; else test_timer <= test_timer + 1;
            end

            assign write_phase_active = (test_timer < TEST_DURATION_CYCLES/2); // 1. sekunda: iba zápis
            assign read_phase_active  = (test_timer >= TEST_DURATION_CYCLES/2); // 2. sekunda: iba čítanie

            // Writer logika (aktívna len v prvej fáze)
            assign sdram_writer_valid = write_phase_active;
            assign sdram_writer_data  = 16'hF800; // Vždy zapisujeme červenú

            always_ff @(posedge axi_clk_i or negedge axi_rst_ni) begin
                if (!axi_rst_ni) {wr_x_cnt, wr_y_cnt} <= '0;
                else if (write_phase_active && sdram_writer_ready) begin
                    if (wr_x_cnt == H_RES - 1) begin
                      {wr_x_cnt, wr_y_cnt} <= (wr_y_cnt == V_RES - 1) ? '0 : {'0, wr_y_cnt + 1};
                    end
                    else wr_x_cnt <= wr_x_cnt + 1;
                end
            end

            assign sdram_writer_addr = (wr_y_cnt * H_RES) + wr_x_cnt;
            assign s_axis_video_in.TREADY = 1'b0;

            // Reader logika (aktívna len v druhej fáze)
            always_ff @(posedge axi_clk_i or negedge axi_rst_ni) begin
                if (!axi_rst_ni) {rd_x_cnt, rd_y_cnt, reading_active} <= '0;
                else begin
                    if (read_phase_active && !reading_active)
                      reading_active <= 1'b1;
                    if (reading_active && m_axis_video_out.TVALID && m_axis_video_out.TREADY) begin
                       if (rd_x_cnt == H_RES-1) begin
                          {rd_x_cnt, rd_y_cnt} <= (rd_y_cnt == V_RES-1) ? '0 : {'0, rd_y_cnt + 1};
                        end
                       else rd_x_cnt <= rd_x_cnt + 1;
                    end
                end
            end

            assign sdram_reader_addr = (rd_y_cnt * H_RES) + rd_x_cnt;
            assign sdram_reader_valid = reading_active;
            assign m_axis_video_out.TVALID = sdram_resp_valid;
            assign m_axis_video_out.TDATA  = sdram_resp_data;
            assign m_axis_video_out.TLAST  = sdram_resp_last;
            assign m_axis_video_out.TUSER  = 1'b0;

            // Pre tento test sú adresy bufferov irelevantné
            assign write_buffer_base_addr = '0;
            assign read_buffer_base_addr = '0;

            // Diagnostika pre tento režim
            assign debug_led_o[7] = write_phase_active;
            assign debug_led_o[6] = read_phase_active;
        end
    end
endgenerate

endmodule
`endif
