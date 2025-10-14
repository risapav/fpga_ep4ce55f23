// AxiStreamSdramWrapper.sv - Verzia 1.5 - Double Buffering Architecture
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny:
// 1. ARCHITEKTÚRA: Kompletný refaktoring na "double-buffering" (ping-pong). Modul
//    teraz využíva dve oddelené pamäťové oblasti v SDRAM pre simultánny zápis
//    a čítanie.
// 2. SYNCHRONIZÁCIA: Zápis a čítanie sú plne oddelené. Výmena ("swap") bufferov
//    nastane až vtedy, keď je celý frame zapísaný do jedného buffera a zároveň
//    je predchádzajúci frame úplne prečítaný z druhého.
// 3. RIADENIE: Pôvodný FSM bol nahradený robustnou riadiacou logikou s príznakmi
//    (`write_frame_done`, `read_frame_done`), ktoré sledujú stav každého buffera.
// 4. EFEKTIVITA: Architektúra je ideálna pre streaming veľkých paketov (napr. video
//    snímky), pretože maximalizuje využitie SDRAM a udržuje plynulý tok dát.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    parameter integer NUM_BUFFERS      = 2, // Počet bufferov (2 pre double buffering)
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer PACKET_LEN_WORDS  = 1024,
    parameter integer BURST_LEN         = 8,
    parameter logic [SDRAM_ADDR_WIDTH-1:0] SDRAM_BASE_ADDR = 24'h0
) (
    // AXI-Stream Slave Interface (s_axis) - zdroj dát
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,

    // AXI-Stream Master Interface (m_axis) - prijímač dát
    output logic [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast,

    // Rozhranie pre SdramController
    output logic                     cmd_fifo_valid,
    input  logic                     cmd_fifo_ready,
    output sdram_pkg::sdram_cmd_t    cmd_fifo_data,
    output logic                     wdata_valid,
    output logic [AXIS_DATA_WIDTH-1:0] wdata,
    output logic [1:0]                wdata_dqm_i,
    input  logic                     wdata_ready,
    input  logic                     resp_valid,
    input  logic                     resp_last,
    input  logic [AXIS_DATA_WIDTH-1:0] resp_data,
    output logic                     resp_ready,

    // --- Ladiace výstupy ---
    output sdram_pkg::buffer_state_t debug_buffer_state [0:NUM_BUFFERS-1],
    output logic [$clog2(NUM_BUFFERS)-1:0] debug_find_empty_start_idx,
    output logic [$clog2(NUM_BUFFERS)-1:0] debug_find_full_start_idx,

    // Systémové signály
    input  logic                     clk,
    input  logic                     rstn
);

    import sdram_pkg::*;

    // --- Double Buffering Parametre ---
    localparam logic [SDRAM_ADDR_WIDTH-1:0] BUFFER0_BASE_ADDR = SDRAM_BASE_ADDR;
    localparam logic [SDRAM_ADDR_WIDTH-1:0] BUFFER1_BASE_ADDR = SDRAM_BASE_ADDR + PACKET_LEN_WORDS;

    initial begin
        if (PACKET_LEN_WORDS % BURST_LEN != 0) begin
            $fatal(1, "FATAL: PACKET_LEN_WORDS musí byť násobkom BURST_LEN (%0d)", BURST_LEN);
        end
        if (BUFFER1_BASE_ADDR + PACKET_LEN_WORDS > (1 << SDRAM_ADDR_WIDTH)) begin
            $fatal(1, "FATAL: Nedostatok adresného priestoru v SDRAM pre dva buffery.");
        end
    end

    // --- Stavové registre pre Double Buffering ---
    logic write_buf_sel; // 0 alebo 1: vyberá buffer pre zápis
    logic read_buf_sel;  // 0 alebo 1: vyberá buffer pre čítanie
    logic buffer_ready_to_read[0:1]; // Príznak, či je buffer plný a pripravený na čítanie

    // --- Stavové registre pre Zápisovú cestu ---
    logic [SDRAM_ADDR_WIDTH-1:0] write_addr_offset;
    logic [$clog2(PACKET_LEN_WORDS)-1:0] write_words_count;
    logic write_frame_done;

    // --- Stavové registre pre Čítaciu cestu ---
    logic [SDRAM_ADDR_WIDTH-1:0] read_addr_offset;
    logic [$clog2(PACKET_LEN_WORDS)-1:0] read_words_sent_count;
    logic read_frame_done;

    // --- Buffer pre jeden burst (zápis) ---
    logic [AXIS_DATA_WIDTH-1:0] w_data_buffer [0:BURST_LEN-1];
    logic [$clog2(BURST_LEN+1)-1:0] w_buffer_fill_count;
    logic [$clog2(BURST_LEN)-1:0]   w_burst_sent_count;

    // --- Riadiace signály ---
    logic issue_write_cmd, issue_read_cmd;

    // --- Sekvenčná logika ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            // Počiatočný stav: zapisujeme do buffera 0, čítame z buffera 1 (ktorý nie je pripravený)
            write_buf_sel <= 1'b0;
            read_buf_sel  <= 1'b1;
            buffer_ready_to_read[0] <= 1'b0;
            buffer_ready_to_read[1] <= 1'b0;

            write_addr_offset <= '0;
            write_words_count <= '0;
            write_frame_done  <= 1'b0;

            read_addr_offset <= '0;
            read_words_sent_count <= '0;
            read_frame_done <= 1'b1; // Počiatočné čítanie je považované za "hotové", aby sa mohol uskutočniť prvý swap

            w_buffer_fill_count <= '0;
            w_burst_sent_count <= '0;
        end else begin
            // --- Logika pre výmenu ("swap") bufferov ---
            // Výmena nastane, keď je zápis jedného frame hotový A ZÁROVEŇ je hotové aj čítanie predchádzajúceho.
            if (write_frame_done && read_frame_done) begin
                write_buf_sel <= ~write_buf_sel;
                read_buf_sel  <= ~read_buf_sel;

                // Označíme novo naplnený buffer ako pripravený na čítanie
                buffer_ready_to_read[write_buf_sel] <= 1'b1;
                // Buffer, z ktorého sme čítali, je teraz voľný pre zápis
                buffer_ready_to_read[read_buf_sel] <= 1'b0;

                // Resetujeme počítadlá pre nové operácie
                write_frame_done      <= 1'b0;
                write_addr_offset     <= '0;
                write_words_count     <= '0;

                read_frame_done       <= 1'b0;
                read_addr_offset      <= '0;
                read_words_sent_count <= '0;
            end

            // --- Zápisová logika ---
            if (!write_frame_done) begin
                if (s_axis_tready && s_axis_tvalid) begin
                    write_words_count <= write_words_count + 1;
                end
                if (s_axis_tready && s_axis_tvalid) begin
                    w_buffer_fill_count <= w_buffer_fill_count + 1;
                end else if (issue_write_cmd) begin
                    w_buffer_fill_count <= 0;
                end
                if (issue_write_cmd) begin
                    w_burst_sent_count <= 0;
                end else if (wdata_valid && wdata_ready) begin
                    w_burst_sent_count <= w_burst_sent_count + 1;
                end
                if (issue_write_cmd) begin
                    write_addr_offset <= write_addr_offset + BURST_LEN;
                end
                if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
                    write_frame_done <= 1'b1;
                end
            end

            // --- Čítacia logika ---
            if (!read_frame_done && buffer_ready_to_read[read_buf_sel]) begin
                if (issue_read_cmd) begin
                    read_addr_offset <= read_addr_offset + BURST_LEN;
                end
                if (m_axis_tvalid && m_axis_tready) begin
                    read_words_sent_count <= read_words_sent_count + 1;
                end
                if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                    read_frame_done <= 1'b1;
                end
            end
        end
    end

    // --- Kombinačná logika ---
    always_comb begin
        logic can_issue_write, can_issue_read;
        logic [SDRAM_ADDR_WIDTH-1:0] current_write_base, current_read_base;

        current_write_base = (write_buf_sel == 0) ? BUFFER0_BASE_ADDR : BUFFER1_BASE_ADDR;
        current_read_base  = (read_buf_sel  == 0) ? BUFFER0_BASE_ADDR : BUFFER1_BASE_ADDR;

        s_axis_tready = !write_frame_done;
        can_issue_write = (w_buffer_fill_count == BURST_LEN) && !write_frame_done;
        can_issue_read = buffer_ready_to_read[read_buf_sel] && !read_frame_done && (read_addr_offset < PACKET_LEN_WORDS);

        issue_write_cmd = 1'b0;
        issue_read_cmd  = 1'b0;
        cmd_fifo_valid  = 1'b0;
        cmd_fifo_data   = '{default:'0};

        // Arbitrácia prístupu ku Command FIFO (čítanie má prioritu)
        if (cmd_fifo_ready) begin
            if (can_issue_read) begin
                issue_read_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: current_read_base + read_addr_offset, rw: READ_CMD};
            end else if (can_issue_write) begin
                issue_write_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data   = '{addr: current_write_base + write_addr_offset, rw: WRITE_CMD};
            end
        end

        wdata_valid = (w_burst_sent_count > 0) || (issue_write_cmd && cmd_fifo_ready);
        wdata       = w_data_buffer[w_burst_sent_count];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid;
        m_axis_tdata  = resp_data;
        m_axis_tlast  = m_axis_tvalid && (read_words_sent_count == PACKET_LEN_WORDS - 1);
        resp_ready    = m_axis_tready;
    end

    // Logika pre plnenie interného burst buffera
    always_ff @(posedge clk) begin
        if (s_axis_tready && s_axis_tvalid) begin
            w_data_buffer[w_buffer_fill_count] <= s_axis_tdata;
        end
    end

endmodule

`endif

