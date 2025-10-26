// =============================================================================
// Súbor: FramebufferWithSdramController_Final.sv
// Verzia: 4.3 (Odstránené $bits)
// Dátum: 17. október 2025
//
// Popis:
// Kompletný návrh ping-pong framebuffer kontroléra.
// Premenovaný modul na 'framebuffer_ctrl'.
//
// Zmeny vo verzii 4.3:
// - Odstránené použitie '$bits' pri inkrementácii počítadiel pre lepšiu
//   kompatibilitu s Quartus.
//
// Zmeny vo verzii 4.2:
// - Refaktoring: Odstránená definícia modulu 'SdramController'.
//   Modul teraz závisí od externého súboru 'SdramController.sv'.
// - Premenovanie: Modul 'FramebufferController' premenovaný na 'framebuffer_ctrl'.
// =============================================================================

`ifndef FRAMEBUFFER_CTRL_SV // Zmenené meno include guard
`define FRAMEBUFFER_CTRL_SV // Zmenené meno include guard

`default_nettype none

// Importy balíčkov (teraz sú oba externé)
import sdram_pkg::*;
import framebuffer_pkg::*;

// ============================================================================
// >>> Ping-Pong Framebuffer Kontrolér <<<
// Typ: Moore FSM pre stavy buffrov
// Účel: Riadi zápis a čítanie dvoch buffrov v SDRAM pamäti
//       prostredníctvom modulu SdramController.
//
// Závislosti:
// - Balíček 'sdram_pkg' (musí byť v projekte)
// - Balíček 'framebuffer_pkg' (musí byť v projekte)
// - Modul 'SdramController' (musí byť v projekte)
// ============================================================================
module framebuffer_ctrl #( // Premenovaný modul
    // --- Parametre rozlíšenia a režimu ---
    parameter int FRAME_WIDTH  = 800,
    parameter int FRAME_HEIGHT = 600,
    parameter op_mode_e C_OP_MODE = NORMAL
)(
    input  logic clk,
    input  logic clk_sh, // Fázovo posunutý CLK pre SDRAM
    input  logic rstn,

    // AXI Stream Slave Interface (input frame data)
    input  logic s_axis_valid,
    output logic s_axis_ready,
    input  logic [sdram_pkg::DATA_WIDTH-1:0] s_axis_data, // Použitie scope pre parameter
    input  logic s_axis_last,
    input  logic s_axis_user,

    // AXI Stream Master Interface (output frame data)
    output logic m_axis_valid,
    input  logic m_axis_ready,
    output logic [sdram_pkg::DATA_WIDTH-1:0] m_axis_data, // Použitie scope pre parameter
    output logic m_axis_last,
    output logic m_axis_user,

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
  // Jednoducho prepojí vstupný stream na výstupný.
  // ==============================================================
  if (C_OP_MODE == PASSTHROUGH) begin : gen_passthrough
        assign m_axis_valid = s_axis_valid;
        assign m_axis_data  = 16'hFFE0;//s_axis_data;
        assign m_axis_last  = s_axis_last;
        assign m_axis_user  = s_axis_user;
        assign s_axis_ready = m_axis_ready;

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
        assign debug_led_0_o[0]   = s_axis_valid;
        assign debug_led_0_o[1]   = s_axis_ready;
        assign debug_led_0_o[2]   = s_axis_last;
        assign debug_led_0_o[3]   = s_axis_user;
        assign debug_led_0_o[7:4] = 4'b0;

        assign debug_led_1_o[0]   = m_axis_valid;
        assign debug_led_1_o[1]   = m_axis_ready;
        assign debug_led_1_o[2]   = m_axis_last;
        assign debug_led_1_o[3]   = m_axis_user;
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
        // Ostatné parametre časovania (tRP, tRCD, atď.) sú
        // ponechané na predvolených hodnotách definovaných v SdramController.sv
    ) sdram_inst (
        .clk(clk),
        .clk_sh(clk_sh),
        .rstn(rstn),

        // --- Pripojenie príkazov a dát ---
        // Zápis (Framebuffer -> SDRAM)
        .wr_cmd_data(wr_cmd_data),
        .wr_cmd_valid(wr_cmd_valid),
        .wr_cmd_ready(wr_cmd_ready),
        .wdata(s_axis_data),         // Dáta priamo zo vstupu
        .wdata_valid(s_axis_valid),
        .wdata_ready(s_axis_ready),  // Back-pressure na vstup
        .wdata_level(wdata_level),

        // Čítanie (SDRAM -> Framebuffer)
        .rd_cmd_data(rd_cmd_data),
        .rd_cmd_valid(rd_cmd_valid),
        .rd_cmd_ready(rd_cmd_ready),
        .rdata(m_axis_data),         // Dáta priamo na výstup
        .rdata_valid(m_axis_valid),  // Valid signál na výstup
        .rdata_ready(m_axis_ready),  // Back-pressure z výstupu
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
            // Inicializačný stav
            buf_a_state <= EMPTY;
            buf_b_state <= EMPTY;
            write_buf   <= BUF_A; // Začíname písať do A
            read_buf    <= BUF_B; // Budeme čítať z B (keď bude A plný)
            first_frame_done <= 1'b0;
        end else begin
            // --- Logika prehodenia (Swap) ---
            if (swap_buffers_req) begin
                write_buf <= read_buf;  // Nový buffer na zápis je ten, z ktorého sa čítalo
                read_buf  <= write_buf;  // Nový buffer na čítanie je ten, čo sa práve zaplnil
                first_frame_done <= 1'b1; // Už máme prvý platný buffer
            end

            // --- FSM pre Buffer A ---
            unique case (buf_a_state)
                EMPTY:   begin
                  if (write_buf == BUF_A) // Ak bol tento buffer vybraný na zápis
                    buf_a_state <= FILLING;
                end
                FILLING: begin
                  // Posledný pixel je zapísaný (sledujeme vstupný stream)
                  if (s_axis_valid && s_axis_ready && write_addr_cnt == CFrameSizeWords - 1)
                    buf_a_state <= FULL;
                end
                FULL:    begin
                  // Ak bol tento buffer vybraný na čítanie
                  if (read_buf == BUF_A && first_frame_done)
                    buf_a_state <= READING;
                end
                READING: begin
                  // Ak bol vydaný príkaz na čítanie posledného burstu
                  if (rd_cmd_valid && rd_cmd_ready && read_addr_cnt >= CFrameSizeWords - sdram_pkg::BURST_LEN)
                    buf_a_state <= EMPTY; // Buffer je prázdny a pripravený na nový zápis
                end
                default: buf_a_state <= EMPTY; // Bezpečný stav
            endcase

            // --- FSM pre Buffer B (identická logika) ---
            unique case (buf_b_state)
                EMPTY:   begin
                  if (write_buf == BUF_B)
                    buf_b_state <= FILLING;
                end
                FILLING: begin
                  if (s_axis_valid && s_axis_ready && write_addr_cnt == CFrameSizeWords - 1)
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
                default: buf_b_state <= EMPTY; // Bezpečný stav
            endcase
        end
    end

    // Kombinačná logika pre žiadosť o prehodenie buffrov
    always_comb begin
        swap_buffers_req = 1'b0;
        // Prípad 1: Písali sme do A, A je plný. Čítali sme z B, B je prázdny.
        if (write_buf == BUF_A && buf_a_state == FULL && read_buf == BUF_B && buf_b_state == EMPTY)
            swap_buffers_req = 1'b1;
        // Prípad 2: Písali sme do B, B je plný. Čítali sme z A, A je prázdny.
        else if (write_buf == BUF_B && buf_b_state == FULL && read_buf == BUF_A && buf_a_state == EMPTY)
            swap_buffers_req = 1'b1;
    end

    // --------------------------------------------------
    // Generátor príkazov na ZÁPIS (Write Command Generator)
    // --------------------------------------------------
    always_comb begin
        logic [CAddrWidthTotal-1:0] base_addr;
        base_addr = (write_buf == BUF_A) ? CFrameABaseAddr : CFrameBBaseAddr;
        wr_full_addr = base_addr + wr_cmd_addr_cnt;

        // Rozdelenie adresy pre SDRAM príkaz
        wr_cmd_data.addr.row  = wr_full_addr[sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH +: sdram_pkg::ROW_ADDR_WIDTH];
        wr_cmd_data.addr.bank = wr_full_addr[sdram_pkg::COL_ADDR_WIDTH +: sdram_pkg::BANK_ADDR_WIDTH];
        wr_cmd_data.addr.col  = wr_full_addr[0 +: sdram_pkg::COL_ADDR_WIDTH];

        wr_cmd_data.rw = 1'b1; // Zápis
        wr_cmd_data.auto_precharge = 1'b0; // Bez auto-precharge

        // Príkaz je platný, ak je vo 'wdata_fifo' dosť dát na celý burst
        wr_cmd_valid = (wdata_level >= sdram_pkg::BURST_LEN);
    end

    // Počítadlo adries pre pixely (sleduje s_axis stream)
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req) // Reset pri resete alebo prehodení buffrov
          write_addr_cnt <= '0;
        else if (s_axis_valid && s_axis_ready) begin // Len ak prebehne platný prenos
            if (write_addr_cnt == CFrameSizeWords - 1)
              write_addr_cnt <= '0; // Pretečenie na konci snímku
            else
              write_addr_cnt <= write_addr_cnt + 1'b1; // Odstránené $bits
        end
    end

    // Počítadlo adries pre príkazy zápisu (skoky po BURST_LEN)
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req)
          wr_cmd_addr_cnt <= '0;
        else if (wr_cmd_valid && wr_cmd_ready) begin // Len ak kontrolér prijal príkaz
            if (wr_cmd_addr_cnt >= CFrameSizeWords - sdram_pkg::BURST_LEN)
              wr_cmd_addr_cnt <= '0;
            else
              wr_cmd_addr_cnt <= wr_cmd_addr_cnt + sdram_pkg::BURST_LEN; // Odstránené $bits
        end
    end

    // --------------------------------------------------
    // Generátor príkazov na ČÍTANIE (Read Command Generator)
    // --------------------------------------------------
    always_comb begin
        logic [CAddrWidthTotal-1:0] base_addr;
        base_addr = (read_buf == BUF_A) ? CFrameABaseAddr : CFrameBBaseAddr;
        rd_full_addr = base_addr + read_addr_cnt;

        // Rozdelenie adresy
        rd_cmd_data.addr.row  = rd_full_addr[sdram_pkg::COL_ADDR_WIDTH + sdram_pkg::BANK_ADDR_WIDTH +: sdram_pkg::ROW_ADDR_WIDTH];
        rd_cmd_data.addr.bank = rd_full_addr[sdram_pkg::COL_ADDR_WIDTH +: sdram_pkg::BANK_ADDR_WIDTH];
        rd_cmd_data.addr.col  = rd_full_addr[0 +: sdram_pkg::COL_ADDR_WIDTH];

        rd_cmd_data.rw = 1'b0; // Čítanie
        rd_cmd_data.auto_precharge = 1'b0;

        // Príkaz je platný, ak:
        // 1. Už máme prvý snímok (first_frame_done)
        // 2. Je miesto v 'rdata_fifo' (pod prahovou hodnotou)
        // 3. Ešte sme nedočítali posledný burst snímku
        // 4. Buffer, z ktorého čítame, je v stave READING
        rd_cmd_valid = first_frame_done &&
                       (rdata_level < CReadThreshold) &&
                       (read_addr_cnt < CFrameSizeWords - sdram_pkg::BURST_LEN) && // Zabezpečí, že neprekročíme hranicu
                       ((read_buf == BUF_A) ? (buf_a_state == READING) : (buf_b_state == READING));
    end

    // Počítadlo adries pre príkazy čítania (skoky po BURST_LEN)
    always_ff @(posedge clk) begin
        if (!rstn || swap_buffers_req) // Reset pri resete alebo prehodení
          read_addr_cnt <= '0;
        else if (rd_cmd_valid && rd_cmd_ready) begin // Len ak kontrolér prijal príkaz
            if (read_addr_cnt >= CFrameSizeWords - sdram_pkg::BURST_LEN)
              read_addr_cnt <= '0; // Začíname odznova (aj keď by nemal nastať, poistka)
            else
              read_addr_cnt <= read_addr_cnt + sdram_pkg::BURST_LEN; // Odstránené $bits
        end
    end

    // --------------------------------------------------
    // Generovanie výstupných TLAST (Koniec riadku) a TUSER (Začiatok snímku)
    // --------------------------------------------------
    assign m_axis_last = (m_axis_x_cnt == FRAME_WIDTH - 1); // EOL
    assign m_axis_user = (m_axis_x_cnt == 0) && (m_axis_y_cnt == 0); // SOF

    // Tieto počítadlá sledujú výstupný AXI stream (m_axis)
    always_ff @(posedge clk) begin
        if (!rstn) begin
            m_axis_x_cnt <= '0;
            m_axis_y_cnt <= '0;
        end else if (m_axis_valid && m_axis_ready) begin // Len ak prebehne platný prenos na výstupe
            // Horizontálne počítadlo
            if (m_axis_last) begin // Ak sme na konci riadku
                m_axis_x_cnt <= '0;
                // Vertikálne počítadlo
                if (m_axis_y_cnt == FRAME_HEIGHT - 1) begin // Ak sme na konci posledného riadku
                    m_axis_y_cnt <= '0; // Reset pre nový snímok
                end else begin
                    m_axis_y_cnt <= m_axis_y_cnt + 1'b1; // Posun na ďalší riadok, odstránené $bits
                end
            end else begin
                m_axis_x_cnt <= m_axis_x_cnt + 1'b1; // Posun na ďalší pixel, odstránené $bits
                // m_axis_y_cnt sa nemení
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

    assign debug_led_1_o[0] = s_axis_valid;
    assign debug_led_1_o[1] = s_axis_ready;
    assign debug_led_1_o[2] = m_axis_valid;
    assign debug_led_1_o[3] = m_axis_ready;
    assign debug_led_1_o[4] = wr_cmd_valid;
    assign debug_led_1_o[5] = wr_cmd_ready;
    assign debug_led_1_o[6] = rd_cmd_valid;
    assign debug_led_1_o[7] = rd_cmd_ready;
  end // gen_framebuffer_active

endgenerate

endmodule

`default_nettype wire

`endif // FRAMEBUFFER_CTRL_SV

