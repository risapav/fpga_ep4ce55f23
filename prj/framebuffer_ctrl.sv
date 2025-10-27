// =============================================================================
// Súbor: framebuffer_ctrl.sv
// Verzia: 4.5 (Refaktorované AXI rozhrania + explicitný clk/rstn)
// Dátum: 27. október 2025
//
// Popis:
// Kompletný návrh ping-pong framebuffer kontroléra.
// Modul používa explicitné 'clk' a 'rstn' porty a
// AXI4-Stream rozhrania 'axi4s_if.slave' a 'axi4s_if.master'.
//
// Zmeny vo verzii 4.5:
// - Refaktorovaná hlavička modulu podľa požiadavky:
//   - Ponechané explicitné porty clk, clk_sh, rstn.
//   - Odstránené jednotlivé AXI signály (s_axis_valid, ...).
//   - Pridané AXI rozhrania s_axis a m_axis.
// - Interná logika upravená na prácu s s_axis.TVALID, m_axis.TDATA, atď.
//
// Závislosti:
// - Balíček 'sdram_pkg'
// - Balíček 'framebuffer_pkg'
// - Modul 'SdramController'
// - Rozhranie 'axi4s_if' (z axi_interfaces.sv)
// =============================================================================

`ifndef FRAMEBUFFER_CTRL_SV // Zmenené meno include guard
`define FRAMEBUFFER_CTRL_SV // Zmenené meno include guard

`default_nettype none

// Importy balíčkov (teraz sú oba externé)
import sdram_pkg::*;
import framebuffer_pkg::*;
// Import AXI rozhrania pre definíciu 'axi4s_if'
import axi_pkg::*; // Potrebné pre axi4s_if (ak axi_interfaces importuje axi_pkg)
// Predpokladáme, že axi_interfaces.sv je zahrnutý v projekte
// a definuje axi4s_if

// ============================================================================
// >>> Ping-Pong Framebuffer Kontrolér <<<
// ============================================================================
module framebuffer_ctrl #( // Premenovaný modul
    // --- Parametre rozlíšenia a režimu ---
    parameter int FRAME_WIDTH  = 800,
    parameter int FRAME_HEIGHT = 600,
    parameter op_mode_e C_OP_MODE = NORMAL
)(
    // --- REFAKTOROVANÉ PORTY ---
    input  logic clk,
    input  logic clk_sh, // Fázovo posunutý CLK pre SDRAM
    input  logic rstn,

    // Vstupné AXI rozhranie (poskytuje vstupné dáta)
    axi4s_if.slave  s_axis,
    // Výstupné AXI rozhranie (poskytuje výstupné dáta)
    axi4s_if.master m_axis,
    // --- Koniec refaktorovaných portov ---

    // SDRAM interface (priamo na piny kontroléra)
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
        // Priame prepojenie signálov z vstupného do výstupného rozhrania
        assign m_axis.TVALID = s_axis.TVALID;
        assign m_axis.TDATA  = s_axis.TDATA;
        assign m_axis.TLAST  = s_axis.TLAST;
        assign m_axis.TUSER  = s_axis.TUSER;
        assign s_axis.TREADY = m_axis.TREADY;

        // Bezpečné zaparkovanie SDRAM pinov (kontrolér nie je aktívny)
        assign sdram_dq    = {sdram_pkg::DATA_WIDTH{1'bz}}; // Správny tristate
        assign sdram_addr  = '0;
        assign sdram_ba    = '0;
        assign sdram_cas_n = 1'b1;
        assign sdram_cke   = 1'b0; // CKE neaktívne
        assign sdram_clk   = 1'b0; // CLK neaktívny
        assign sdram_cs_n  = 1'b1;
        assign sdram_we_n  = 1'b1;
        assign sdram_ras_n = 1'b1;
        assign sdram_dqm   = '0;

        // Diagnostika pre tento režim
        assign debug_led_0_o[0]   = s_axis.TVALID;
        assign debug_led_0_o[1]   = s_axis.TREADY;
        assign debug_led_0_o[2]   = s_axis.TLAST;
        assign debug_led_0_o[3]   = s_axis.TUSER[0]; // Predpokladáme, že TUSER[0] je relevantný
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
    localparam int CFifoAddrWidth   = 6; // Šírka adresy pre FIFO (zhodná s tou v SdramController)
    localparam int CFrameSizeWords  = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int CAddrWidthTotal  = sdram_pkg::ROW_ADDR_WIDTH + sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH;

    // Bázové adresy pre ping-pong buffre v SDRAM
    localparam logic [CAddrWidthTotal-1:0] CFrameABaseAddr = '0;
    localparam logic [CAddrWidthTotal-1:0] CFrameBBaseAddr = CAddrWidthTotal'(CFrameSizeWords);

    // Prahová hodnota pre FIFO čítania (kedy požiadať o ďalšie dáta)
    localparam int CReadThreshold = 32;

    // --------------------------------------------------
    // Typy pre FSM stavu buffrov
    // --------------------------------------------------
    typedef enum logic {BUF_A, BUF_B} active_buf_t; // Ktorý buffer je aktívny pre R/W
    typedef enum logic [1:0] {EMPTY, FILLING, FULL, READING} buffer_state_t;

    // --------------------------------------------------
    // Signály a Registre
    // --------------------------------------------------
    buffer_state_t buf_a_state, buf_b_state; // Stav každého buffra
    active_buf_t   write_buf, read_buf;    // Ukazovatele na aktívny R/W buffer
    logic          swap_buffers_req;       // Žiadosť o prehodenie buffrov

    // Počítadlá adries
    logic [$clog2(CFrameSizeWords)-1:0] write_addr_cnt;  // Počítadlo pixelov pre vstupný stream
    logic [$clog2(CFrameSizeWords)-1:0] read_addr_cnt;   // Počítadlo adries pre príkazy čítania (skoky po BURST_LEN)
    logic [$clog2(CFrameSizeWords)-1:0] wr_cmd_addr_cnt; // Počítadlo adries pre príkazy zápisu (skoky po BURST_LEN)

    // Signály pre príkazy do SdramController
    sdram_cmd_t wr_cmd_data, rd_cmd_data;
    logic       wr_cmd_valid, rd_cmd_valid;
    logic       wr_cmd_ready, rd_cmd_ready;

    // Stavy FIFO z SdramController
    logic [CFifoAddrWidth:0] rdata_level, wdata_level; // Upravená šírka

    logic [CAddrWidthTotal-1:0] wr_full_addr, rd_full_addr;
    logic       first_frame_done; // Príznak, že prvý buffer bol zaplnený

    // Počítadlá pre generovanie výstupných TLAST/TUSER
    logic [$clog2(FRAME_WIDTH)-1:0] m_axis_x_cnt;
    logic [$clog2(FRAME_HEIGHT)-1:0] m_axis_y_cnt;

    // --------------------------------------------------
    // Inštancia SDRAM Kontroléra (teraz z externého súboru)
    // --------------------------------------------------
    SdramController #(
        .CFifoAddrWidth(CFifoAddrWidth)
    ) sdram_inst (
        .clk(clk),
        .clk_sh(clk_sh),
        .rstn(rstn),

        // --- Pripojenie príkazov a dát ---
        .wr_cmd_data(wr_cmd_data),
        .wr_cmd_valid(wr_cmd_valid),
        .wr_cmd_ready(wr_cmd_ready),
        .wdata(s_axis.TDATA),         // Priamo z AXI rozhrania
        .wdata_valid(s_axis.TVALID),  // Priamo z AXI rozhrania
        .wdata_ready(s_axis.TREADY),  // Priamo na AXI rozhranie
        .wdata_level(wdata_level),

        .rd_cmd_data(rd_cmd_data),
        .rd_cmd_valid(rd_cmd_valid),
        .rd_cmd_ready(rd_cmd_ready),
        .rdata(m_axis.TDATA),         // Priamo na AXI rozhranie
        .rdata_valid(m_axis.TVALID),  // Priamo na AXI rozhranie
        .rdata_ready(m_axis.TREADY),  // Priamo z AXI rozhrania
        .rdata_level(rdata_level),

        // --- Pripojenie fyzických pinov SDRAM ---
        .sdram_addr(sdram_addr),
        .sdram_ba(sdram_ba),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_dq(sdram_dq),
        .sdram_dqm(sdram_dqm),
        .sdram_cke(sdram_cke),
        .sdram_clk(sdram_clk)
    );

    // --------------------------------------------------
    // FSM pre stav Ping-Pong Buffrov
    // --------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn) begin
            buf_a_state <= EMPTY;
            buf_b_state <= EMPTY;
            write_buf   <= BUF_A;
            read_buf    <= BUF_B;
            first_frame_done <= 1'b0;
        end else begin
            if (swap_buffers_req) begin
                write_buf <= read_buf;
                read_buf  <= write_buf;
                first_frame_done <= 1'b1;
            end

            unique case (buf_a_state)
                EMPTY:   begin
                  if (write_buf == BUF_A)
                    buf_a_state <= FILLING;
                end
                FILLING: begin
                  if (s_axis.TVALID && s_axis.TREADY && write_addr_cnt == CFrameSizeWords - 1)
                    buf_a_state <= FULL;
                end
                FULL:    begin
                  if (read_buf == BUF_A && first_frame_done)
                    buf_a_state <= READING;
                end
                READING: begin
                  if (rd_cmd_valid && rd_cmd_ready && read_addr_cnt >= CFrameSizeWords - sdram_pkg::BURST_LEN)
                    buf_a_state <= EMPTY;
                end
                default: buf_a_state <= EMPTY;
            endcase

            unique case (buf_b_state)
                EMPTY:   begin
                  if (write_buf == BUF_B)
                    buf_b_state <= FILLING;
                end
                FILLING: begin
                  if (s_axis.TVALID && s_axis.TREADY && write_addr_cnt == CFrameSizeWords - 1)
                    buf_b_state <= FULL;
                end
                FULL:    begin
                  if (read_buf == BUF_B && first_frame_done)
                    buf_b_state <= READING;
                end
                READING: begin
                  if (rd_cmd_valid && rd_cmd_ready && read_addr_cnt >= CFrameSizeWords - sdram_pkg::BURST_LEN)
                    buf_b_state <= EMPTY;
                end
                default: buf_b_state <= EMPTY;
            endcase
        end
    end

    // Kombinačná logika pre žiadosť o prehodenie buffrov
    always_comb begin
        swap_buffers_req = 1'b0;
        if (write_buf == BUF_A && buf_a_state == FULL && read_buf == BUF_B && buf_b_state == EMPTY)
            swap_buffers_req = 1'b1;
        else if (write_buf == BUF_B && buf_b_state == FULL && read_buf == BUF_A && buf_a_state == EMPTY)
            swap_buffers_req = 1'b1;
    end

    // --------------------------------------------------
    // Generátor príkazov na ZÁPIS
    // --------------------------------------------------
    always_comb begin
        logic [CAddrWidthTotal-1:0] base_addr;
        base_addr = (write_buf == BUF_A) ? CFrameABaseAddr : CFrameBBaseAddr;
        wr_full_addr = base_addr + wr_cmd_addr_cnt;

        wr_cmd_data.addr.row  = wr_full_addr[sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH +: sdram_pkg::ROW_ADDR_WIDTH];
        wr_cmd_data.addr.bank = wr_full_addr[sdram_pkg::COL_ADDR_WIDTH +: sdram_pkg::BANK_ADDR_WIDTH];
        wr_cmd_data.addr.col  = wr_full_addr[0 +: sdram_pkg::COL_ADDR_WIDTH];
        wr_cmd_data.rw = 1'b1;
        wr_cmd_data.auto_precharge = 1'b0;
        wr_cmd_valid = (wdata_level >= sdram_pkg::BURST_LEN);
    end

    // Počítadlo adries pre pixely
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req)
          write_addr_cnt <= '0;
        else if (s_axis.TVALID && s_axis.TREADY) begin
            if (write_addr_cnt == CFrameSizeWords - 1)
              write_addr_cnt <= '0;
            else
              write_addr_cnt <= write_addr_cnt + 1'b1;
        end
    end

    // Počítadlo adries pre príkazy zápisu
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req)
          wr_cmd_addr_cnt <= '0;
        else if (wr_cmd_valid && wr_cmd_ready) begin
            if (wr_cmd_addr_cnt >= CFrameSizeWords - sdram_pkg::BURST_LEN)
              wr_cmd_addr_cnt <= '0;
            else
              wr_cmd_addr_cnt <= wr_cmd_addr_cnt + sdram_pkg::BURST_LEN;
        end
    end

    // --------------------------------------------------
    // Generátor príkazov na ČÍTANIE
    // --------------------------------------------------
    always_comb begin
        logic [CAddrWidthTotal-1:0] base_addr;
        base_addr = (read_buf == BUF_A) ? CFrameABaseAddr : CFrameBBaseAddr;
        rd_full_addr = base_addr + read_addr_cnt;

        rd_cmd_data.addr.row  = rd_full_addr[sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH +: sdram_pkg::ROW_ADDR_WIDTH];
        rd_cmd_data.addr.bank = rd_full_addr[sdram_pkg::COL_ADDR_WIDTH +: sdram_pkg::BANK_ADDR_WIDTH];
        rd_cmd_data.addr.col  = rd_full_addr[0 +: sdram_pkg::COL_ADDR_WIDTH];
        rd_cmd_data.rw = 1'b0;
        rd_cmd_data.auto_precharge = 1'b0;
        rd_cmd_valid = first_frame_done &&
                       (rdata_level < CReadThreshold) &&
                       (read_addr_cnt < CFrameSizeWords - sdram_pkg::BURST_LEN) &&
                       ((read_buf == BUF_A) ? (buf_a_state == READING) : (buf_b_state == READING));
    end

    // Počítadlo adries pre príkazy čítania
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req)
          read_addr_cnt <= '0;
        else if (rd_cmd_valid && rd_cmd_ready) begin
            if (read_addr_cnt >= CFrameSizeWords - sdram_pkg::BURST_LEN)
              read_addr_cnt <= '0;
            else
              read_addr_cnt <= read_addr_cnt + sdram_pkg::BURST_LEN;
        end
    end

    // --------------------------------------------------
    // Generovanie výstupných TLAST (Koniec riadku) a TUSER (Začiatok snímku)
    // --------------------------------------------------
    assign m_axis.TLAST = (m_axis_x_cnt == FRAME_WIDTH - 1); // EOL
    // Predpokladáme, že USER_WIDTH je 1. Pre širšie TUSER by bolo potrebné priradenie celého vektora.
    assign m_axis.TUSER = (m_axis_x_cnt == 0) && (m_axis_y_cnt == 0); // SOF

    // Tieto počítadlá sledujú výstupný AXI stream
    always_ff @(posedge clk) begin
        if (!rstn) begin
            m_axis_x_cnt <= '0;
            m_axis_y_cnt <= '0;
        end else if (m_axis.TVALID && m_axis.TREADY) begin
            if (m_axis.TLAST) begin
                m_axis_x_cnt <= '0;
                if (m_axis_y_cnt == FRAME_HEIGHT - 1) begin
                    m_axis_y_cnt <= '0;
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
    assign debug_led_0_o[1:0] = buf_a_state;
    assign debug_led_0_o[3:2] = buf_b_state;
    assign debug_led_0_o[4]   = write_buf;
    assign debug_led_0_o[5]   = read_buf;
    assign debug_led_0_o[6]   = swap_buffers_req;
    assign debug_led_0_o[7]   = first_frame_done;

    assign debug_led_1_o[0] = s_axis.TVALID; // Použitie rozhrania
    assign debug_led_1_o[1] = s_axis.TREADY; // Použitie rozhrania
    assign debug_led_1_o[2] = m_axis.TVALID; // Použitie rozhrania
    assign debug_led_1_o[3] = m_axis.TREADY; // Použitie rozhrania
    assign debug_led_1_o[4] = wr_cmd_valid;
    assign debug_led_1_o[5] = wr_cmd_ready;
    assign debug_led_1_o[6] = rd_cmd_valid;
    assign debug_led_1_o[7] = rd_cmd_ready;
  end // gen_framebuffer_active

endgenerate

endmodule

`default_nettype wire

`endif // FRAMEBUFFER_CTRL_SV

