// =============================================================================
// Súbor: framebuffer_ctrl.sv
// Verzia: 4.14 (Oprava časovania - Registrované príkazy pre Checker)
// Dátum: 27. október 2025
//
// Popis:
// Kompletný návrh ping-pong framebuffer kontroléra.
//
// Zmeny vo verzii 4.14:
// - OPRAVA (Timing): Pridaný register (pipeline stage) pre
//   'wr_cmd_data_to_chk', 'wr_cmd_valid_to_chk',
//   'rd_cmd_data_to_chk', a 'rd_cmd_valid_to_chk'
//   pred ich vstupom do 'SdramCmdChecker', aby sa opravila
//   setup time violation na ceste z 'write_buf'.
//
// Závislosti:
// - Balíček 'sdram_pkg'
// - Balíček 'framebuffer_pkg'
// - Modul 'SdramController'
// - Modul 'SdramCmdChecker'
// - Rozhranie 'axi4s_if' (z axi_interfaces.sv)
// =============================================================================

`ifndef FRAMEBUFFER_CTRL_SV
`define FRAMEBUFFER_CTRL_SV

`default_nettype none

// Importy balíčkov
import sdram_pkg::*;
import framebuffer_pkg::*;
import axi_pkg::*;

module framebuffer_ctrl #(
    parameter int FRAME_WIDTH  = 800,
    parameter int FRAME_HEIGHT = 600,
    parameter op_mode_e C_OP_MODE = NORMAL
)(
    input  logic clk,
    input  logic clk_sh,
    input  logic rstn,

    // Vstupné AXI rozhranie
    axi4s_if.slave  s_axis,
    // Výstupné AXI rozhranie
    axi4s_if.master m_axis,

    // SDRAM interface
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    inout  wire  [sdram_pkg::DATA_WIDTH-1:0] sdram_dq,
    output logic [sdram_pkg::DATA_WIDTH/8-1:0] sdram_dqm,
    output logic sdram_cke,
    output logic sdram_clk,

    // Debug LEDs
    output logic [7:0] debug_led_0_o,
    output logic [7:0] debug_led_1_o
);

// Generovanie logiky na základe zvoleného režimu
generate
  // ==============================================================
  // REŽIM 1: PASSTHROUGH (Premostenie)
  // ==============================================================
  if (C_OP_MODE == PASSTHROUGH) begin : gen_passthrough
        assign m_axis.TVALID = s_axis.TVALID;
        assign m_axis.TDATA  = s_axis.TDATA;
        assign m_axis.TLAST  = s_axis.TLAST;
        assign m_axis.TUSER  = s_axis.TUSER;
        assign s_axis.TREADY = m_axis.TREADY;

        assign sdram_dq    = {sdram_pkg::DATA_WIDTH{1'bz}};
        assign sdram_addr  = 0;
        assign sdram_ba    = 0;
        assign sdram_cas_n = 1'b1;
        assign sdram_cke   = 1'b0;
        assign sdram_clk   = 1'b0;
        assign sdram_cs_n  = 1'b1;
        assign sdram_we_n  = 1'b1;
        assign sdram_ras_n = 1'b1;
        assign sdram_dqm   = 0;

        assign debug_led_0_o[0]   = s_axis.TVALID;
        assign debug_led_0_o[1]   = s_axis.TREADY;
        assign debug_led_0_o[2]   = s_axis.TLAST;
        assign debug_led_0_o[3]   = s_axis.TUSER[0];
        assign debug_led_0_o[7:4] = 4'b0;
        assign debug_led_1_o[0]   = m_axis.TVALID;
        assign debug_led_1_o[1]   = m_axis.TREADY;
        assign debug_led_1_o[2]   = m_axis.TLAST;
        assign debug_led_1_o[3]   = m_axis.TUSER[0];
        assign debug_led_1_o[7:4] = 4'b0;
  end
  // ==============================================================
  // OSTATNÉ REŽIMY (NORMAL)
  // ==============================================================
  else begin : gen_framebuffer_active
    // --------------------------------------------------
    // Lokálne parametre
    // --------------------------------------------------
    localparam int CFifoAddrWidth   = 6;
    localparam longint unsigned CFrameSizeWords  = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int CAddrWidthTotal  = sdram_pkg::ROW_ADDR_WIDTH + sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH;

    localparam int CBurstLen = sdram_pkg::BURST_LEN;
    localparam longint unsigned CFrameSizeAligned = ((CFrameSizeWords + CBurstLen - 1) / CBurstLen) * CBurstLen;

    localparam logic [CAddrWidthTotal-1:0] CFrameABaseAddr = 0;
    localparam logic [CAddrWidthTotal-1:0] CFrameBBaseAddr = CAddrWidthTotal'(CFrameSizeAligned);

    localparam int CReadThreshold = 32;
    localparam int CWriteThreshold = 8 * CBurstLen;

    // --------------------------------------------------
    // Typy pre FSM stavu buffrov
    // --------------------------------------------------
    typedef enum logic {BUF_A, BUF_B} active_buf_t;
    typedef enum logic [1:0] {EMPTY, FILLING, FULL, READING} buffer_state_t;

    // --------------------------------------------------
    // Signály a Registre
    // --------------------------------------------------
    buffer_state_t buf_a_state, buf_b_state;
    active_buf_t   write_buf, read_buf;
    logic          swap_buffers_req_comb;
    logic          swap_buffers_req_reg;

    logic [$clog2(CFrameSizeWords)-1:0] write_addr_cnt;
    logic [$clog2(CFrameSizeAligned)-1:0] read_addr_cnt;
    logic [$clog2(CFrameSizeAligned)-1:0] wr_cmd_addr_cnt;

    // --- OPRAVA (Timing): Signály pre pipeline príkazov ---
    // Kombinačné signály (pred registrom)
    sdram_cmd_t wr_cmd_data_comb, rd_cmd_data_comb;
    logic       wr_cmd_valid_comb, rd_cmd_valid_comb;
    // Registrované signály (do checkera)
    sdram_cmd_t wr_cmd_data_reg, rd_cmd_data_reg;
    logic       wr_cmd_valid_reg, rd_cmd_valid_reg;

    // Signály medzi Checkerom a SDRAM Controllerom
    logic       wr_cmd_ready_from_chk, rd_cmd_ready_from_chk;
    sdram_cmd_t wr_cmd_data_to_sdram, rd_cmd_data_to_sdram;
    logic       wr_cmd_valid_to_sdram, rd_cmd_valid_to_sdram;
    logic       wr_cmd_ready_from_sdram, rd_cmd_ready_from_sdram;
    logic       cmd_error;
    logic [15:0] error_code;
    // --- Koniec opravy ---

    logic [CFifoAddrWidth:0] rdata_level, wdata_level;
    logic [CAddrWidthTotal-1:0] wr_full_addr, rd_full_addr;
    logic       first_frame_done;

    logic [$clog2(FRAME_WIDTH)-1:0] m_axis_x_cnt;
    logic [$clog2(FRAME_HEIGHT)-1:0] m_axis_y_cnt;

    // --------------------------------------------------
    // Inštancia SDRAM Command Checkera
    // --------------------------------------------------
    SdramCmdChecker i_cmd_checker (
        .clk(clk),
        .rstn(rstn),
        .clear_errors_i(1'b0),
        // OPRAVA (Timing): Pripojenie registrovaných signálov
        .wr_cmd_in(wr_cmd_data_reg),
        .wr_cmd_valid(wr_cmd_valid_reg),
        .wr_cmd_ready(wr_cmd_ready_from_chk),
        .rd_cmd_in(rd_cmd_data_reg),
        .rd_cmd_valid(rd_cmd_valid_reg),
        .rd_cmd_ready(rd_cmd_ready_from_chk),

        .wr_cmd_out(wr_cmd_data_to_sdram),
        .wr_cmd_out_valid(wr_cmd_valid_to_sdram),
        .wr_cmd_out_ready(wr_cmd_ready_from_sdram),
        .rd_cmd_out(rd_cmd_data_to_sdram),
        .rd_cmd_out_valid(rd_cmd_valid_to_sdram),
        .rd_cmd_out_ready(rd_cmd_ready_from_sdram),
        .cmd_error(cmd_error),
        .error_code(error_code)
    );

    // --------------------------------------------------
    // Inštancia SDRAM Kontroléra
    // --------------------------------------------------
logic busy, fifo_error;

    SdramController #(
        .CFifoAddrWidth(CFifoAddrWidth)
    ) sdram_inst (
        .clk(clk),
        .clk_sh(clk_sh),
        .rstn(rstn),
        .wr_cmd_data(wr_cmd_data_to_sdram),
        .wr_cmd_valid(wr_cmd_valid_to_sdram),
        .wr_cmd_ready(wr_cmd_ready_from_sdram),
        .rd_cmd_data(rd_cmd_data_to_sdram),
        .rd_cmd_valid(rd_cmd_valid_to_sdram),
        .rd_cmd_ready(rd_cmd_ready_from_sdram),
        .wdata(s_axis.TDATA),
        .wdata_valid(s_axis.TVALID),
        .wdata_ready(s_axis.TREADY),
        .wdata_level(wdata_level),
        .rdata(m_axis.TDATA),
        .rdata_valid(m_axis.TVALID),
        .rdata_ready(m_axis.TREADY),
        .rdata_level(rdata_level),
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
        .busy_o(busy),
        .fifo_error_o(fifo_error)
    );

    // --------------------------------------------------
    // FSM pre stav Ping-Pong Buffrov
    // --------------------------------------------------

    logic buf_a_will_be_full;
    logic buf_b_will_be_full;
    logic buf_a_will_be_empty;
    logic buf_b_will_be_empty;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            buf_a_state <= EMPTY;
            buf_b_state <= EMPTY;
            write_buf   <= BUF_A;
            read_buf    <= BUF_B;
            first_frame_done <= 1'b0;
        end else begin
            if (swap_buffers_req_reg) begin
                write_buf <= read_buf;
                read_buf  <= write_buf;
                first_frame_done <= 1'b1;
            end

            // FSM pre Buffer A
            unique case (buf_a_state)
                EMPTY:   if (write_buf == BUF_A) buf_a_state <= FILLING;
                FILLING: if (buf_a_will_be_full) buf_a_state <= FULL;
                FULL:    if (read_buf == BUF_A && first_frame_done) buf_a_state <= READING;
                READING: if (buf_a_will_be_empty) buf_a_state <= EMPTY;
                default: buf_a_state <= EMPTY;
            endcase

            // FSM pre Buffer B
            unique case (buf_b_state)
                EMPTY:   if (write_buf == BUF_B) buf_b_state <= FILLING;
                FILLING: if (buf_b_will_be_full) buf_b_state <= FULL;
                FULL:    if (read_buf == BUF_B && first_frame_done) buf_b_state <= READING;
                READING: if (buf_b_will_be_empty) buf_b_state <= EMPTY;
                default: buf_b_state <= EMPTY;
            endcase
        end
    end

    always_comb begin
        // Podmienky prechodu (presunuté z FSM)
        buf_a_will_be_full = (buf_a_state == FILLING) && (s_axis.TVALID && s_axis.TREADY && write_addr_cnt == CFrameSizeWords - 1);
        buf_b_will_be_full = (buf_b_state == FILLING) && (s_axis.TVALID && s_axis.TREADY && write_addr_cnt == CFrameSizeWords - 1);

        // OPRAVA (Timing): Použitie registrovaných signálov
        buf_a_will_be_empty = (buf_a_state == READING) && (rd_cmd_valid_reg && rd_cmd_ready_from_chk && read_addr_cnt >= CFrameSizeAligned - CBurstLen);
        buf_b_will_be_empty = (buf_b_state == READING) && (rd_cmd_valid_reg && rd_cmd_ready_from_chk && read_addr_cnt >= CFrameSizeAligned - CBurstLen);

        // Logika pre swap (s predikciou)
        swap_buffers_req_comb = 1'b0;
        if (write_buf == BUF_A && (buf_a_state == FULL || buf_a_will_be_full) && read_buf == BUF_B && (buf_b_state == EMPTY || buf_a_will_be_empty))
            swap_buffers_req_comb = 1'b1;
        else if (write_buf == BUF_B && (buf_b_state == FULL || buf_b_will_be_full) && read_buf == BUF_A && (buf_a_state == EMPTY || buf_a_will_be_empty))
            swap_buffers_req_comb = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            swap_buffers_req_reg <= 1'b0;
        end else begin
            swap_buffers_req_reg <= swap_buffers_req_comb;
        end
    end

    // --------------------------------------------------
    // Generátor príkazov na ZÁPIS
    // --------------------------------------------------
    always_comb begin
        logic [CAddrWidthTotal-1:0] base_addr;
        base_addr = (write_buf == BUF_A) ? CFrameABaseAddr : CFrameBBaseAddr;
        wr_full_addr = base_addr + wr_cmd_addr_cnt;

        // Priradenie do kombinačných signálov
        wr_cmd_data_comb.addr.row  = wr_full_addr[sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH +: sdram_pkg::ROW_ADDR_WIDTH];
        wr_cmd_data_comb.addr.bank = wr_full_addr[sdram_pkg::COL_ADDR_WIDTH +: sdram_pkg::BANK_ADDR_WIDTH];
        wr_cmd_data_comb.addr.col  = wr_full_addr[0 +: sdram_pkg::COL_ADDR_WIDTH];
        wr_cmd_data_comb.rw = 1'b1;
        wr_cmd_data_comb.auto_precharge = 1'b0;

        wr_cmd_valid_comb = (wdata_level >= CWriteThreshold);
    end

    // Počítadlo adries pre pixely (spoločné)
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req_reg)
            write_addr_cnt <= 0;
        else if (s_axis.TVALID && s_axis.TREADY) begin
            if (write_addr_cnt == CFrameSizeWords - 1)
                write_addr_cnt <= 0;
            else
                write_addr_cnt <= write_addr_cnt + 1'b1;
        end
    end

    // Počítadlo adries pre príkazy zápisu (spoločné)
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req_reg)
            wr_cmd_addr_cnt <= 0;
        // OPRAVA (Timing): Použitie registrovaných signálov
        else if (wr_cmd_valid_reg && wr_cmd_ready_from_chk) begin
            if (wr_cmd_addr_cnt >= CFrameSizeAligned - CBurstLen)
                wr_cmd_addr_cnt <= 0;
            else
                wr_cmd_addr_cnt <= wr_cmd_addr_cnt + CBurstLen;
        end
    end


    // --------------------------------------------------
    // Generátor príkazov na ČÍTANIE
    // --------------------------------------------------
    always_comb begin
        logic [CAddrWidthTotal-1:0] base_addr;
        base_addr = (read_buf == BUF_A) ? CFrameABaseAddr : CFrameBBaseAddr;
        rd_full_addr = base_addr + read_addr_cnt;

        // Priradenie do kombinačných signálov
        rd_cmd_data_comb.addr.row  = rd_full_addr[sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH +: sdram_pkg::ROW_ADDR_WIDTH];
        rd_cmd_data_comb.addr.bank = rd_full_addr[sdram_pkg::COL_ADDR_WIDTH +: sdram_pkg::BANK_ADDR_WIDTH];
        rd_cmd_data_comb.addr.col  = rd_full_addr[0 +: sdram_pkg::COL_ADDR_WIDTH];
        rd_cmd_data_comb.rw = 1'b0;
        rd_cmd_data_comb.auto_precharge = 1'b0;

        rd_cmd_valid_comb = first_frame_done &&
                       (rdata_level < CReadThreshold) &&
                       (read_addr_cnt < CFrameSizeAligned) &&
                       ((read_buf == BUF_A) ? (buf_a_state == READING) : (buf_b_state == READING));
    end

    // Počítadlo adries pre príkazy čítania (spoločné)
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req_reg)
          read_addr_cnt <= 0;
        // OPRAVA (Timing): Použitie registrovaných signálov
        else if (rd_cmd_valid_reg && rd_cmd_ready_from_chk) begin
            if (read_addr_cnt >= CFrameSizeAligned - CBurstLen)
              read_addr_cnt <= 0;
            else
              read_addr_cnt <= read_addr_cnt + CBurstLen;
        end
    end

    // --------------------------------------------------
    // OPRAVA (Timing): Register pre príkazy (Stupeň 1)
    // --------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn) begin
            wr_cmd_valid_reg <= 1'b0;
            wr_cmd_data_reg  <= 0;
            rd_cmd_valid_reg <= 1'b0;
            rd_cmd_data_reg  <= 0;
        end else if (swap_buffers_req_reg) begin
            // Vynulujeme pipeline pri swape
            wr_cmd_valid_reg <= 1'b0;
            wr_cmd_data_reg  <= 0;
            rd_cmd_valid_reg <= 1'b0;
            rd_cmd_data_reg  <= 0;
        end else begin
            // Normálne preklopenie kombinačných hodnôt
            wr_cmd_valid_reg <= wr_cmd_valid_comb;
            wr_cmd_data_reg  <= wr_cmd_data_comb;
            rd_cmd_valid_reg <= rd_cmd_valid_comb;
            rd_cmd_data_reg  <= rd_cmd_data_comb;
        end
    end


    // --------------------------------------------------
    // Generovanie výstupných TLAST (Koniec riadku) a TUSER (Začiatok snímku)
    // --------------------------------------------------
    assign m_axis.TLAST = (m_axis_x_cnt == FRAME_WIDTH - 1);
    assign m_axis.TUSER = (m_axis_x_cnt == 0) && (m_axis_y_cnt == 0);

    always_ff @(posedge clk) begin
        if (!rstn) begin
            m_axis_x_cnt <= 0;
            m_axis_y_cnt <= 0;
        end else if (m_axis.TVALID && m_axis.TREADY) begin
            if (m_axis.TLAST) begin
                m_axis_x_cnt <= 0;
                if (m_axis_y_cnt == FRAME_HEIGHT - 1) begin
                    m_axis_y_cnt <= 0;
                end else begin
                    m_axis_y_cnt <= m_axis_y_cnt + 1'b1;
                end
            end else begin
                m_axis_x_cnt <= m_axis_x_cnt + 1'b1;
            end
        end
    end

    // --------------------------------------------------
    // Debug LED mapovanie
    // --------------------------------------------------
    assign debug_led_0_o[1:0] = {busy, fifo_error};
    assign debug_led_0_o[3:2] = buf_b_state;
    assign debug_led_0_o[4]   = write_buf;
    assign debug_led_0_o[5]   = read_buf;
    assign debug_led_0_o[6]   = swap_buffers_req_reg; // Použitie registrovaného
    assign debug_led_0_o[7]   = first_frame_done;

    assign debug_led_1_o[0] = s_axis.TVALID;
    assign debug_led_1_o[1] = s_axis.TREADY;
    assign debug_led_1_o[2] = m_axis.TVALID;
    assign debug_led_1_o[3] = m_axis.TREADY;
    // OPRAVA (Timing): Zobrazenie registrovaných signálov
    assign debug_led_1_o[4] = wr_cmd_valid_reg;
    assign debug_led_1_o[5] = wr_cmd_ready_from_chk;
    assign debug_led_1_o[6] = rd_cmd_valid_reg;
    assign debug_led_1_o[7] = cmd_error;

  end // gen_framebuffer_active

endgenerate

endmodule

`default_nettype wire

`endif // FRAMEBUFFER_CTRL_SV

