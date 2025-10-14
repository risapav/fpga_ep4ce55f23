// AxiStreamSdramWrapper.sv - Verzia 1.53 - N-Stage Ring Buffering DMA Engine
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny (v1.53):
// 1. ARCHITEKTÚRA: Kompletný refaktoring z "ping-pong" (2 buffery) na N-stupňový
//    kruhový buffer (NUM_BUFFERS >= 2). Toto je najvýznamnejšia zmena, ktorá
//    umožňuje nepretržitý DMA tok dát bez idle cyklov.
// 2. RIADENIE: Implementovaná robustná stavová logika pre každý buffer v kruhu
//    (EMPTY, FILLING, FULL, READING) riadená pomocou `write_ptr` a `read_ptr`.
//    Zápis môže okamžite pokračovať do ďalšieho voľného buffera, zatiaľ čo
//    jeden alebo viacero plných bufferov čaká na prečítanie.
// 3. MONITORING: Pridané ladiace výstupy, ktoré monitorujú stav každého buffera
//    a pozície ukazovateľov, čo výrazne zjednodušuje ladenie a analýzu výkonu.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    parameter integer NUM_BUFFERS       = 4,  // VYLEPŠENIE: Počet bufferov v kruhu (3-4 je ideálne)
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer PACKET_LEN_WORDS  = 8192,
    parameter integer SEGMENT_LEN_WORDS = 1024,
    parameter integer BURST_LEN         = 8,
    parameter logic [SDRAM_ADDR_WIDTH-1:0] SDRAM_BASE_ADDR = 24'h0
) (
    // AXI-Stream Interfaces
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,
    output logic [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast,

    // SDRAM Controller Interface
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

    // --- Ladiace výstupy (VYLEPŠENIE) ---
    output sdram_pkg::buffer_state_t debug_buffer_state [0:NUM_BUFFERS-1],
    output logic [$clog2(NUM_BUFFERS)-1:0] debug_write_ptr_o,
    output logic [$clog2(NUM_BUFFERS)-1:0] debug_read_ptr_o,

    // System Signals
    input  logic                     clk,
    input  logic                     rstn
);

    import sdram_pkg::*;

    // --- Ring Buffer Parametre ---
    localparam integer BUFFERS_ADDR_WIDTH = $clog2(NUM_BUFFERS);

    // --- Stavová logika pre každý buffer v kruhu ---
    buffer_state_t buffer_state [0:NUM_BUFFERS-1], buffer_state_next [0:NUM_BUFFERS-1];
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr, read_ptr; // Ukazovatele do kruhového buffera
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr_next, read_ptr_next;

    // Počítadlá na úrovni segmentov a paketov
    logic [$clog2(PACKET_LEN_WORDS)-1:0]  write_frame_word_count, read_frame_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] write_segment_word_count, read_segment_word_count;
    logic [SDRAM_ADDR_WIDTH-1:0]          write_segment_addr_offset, read_segment_addr_offset;

    // Interný burst buffer
    logic [AXIS_DATA_WIDTH-1:0] w_data_buffer [0:BURST_LEN-1];
    logic [$clog2(BURST_LEN+1)-1:0] w_buffer_fill_count;
    logic [$clog2(BURST_LEN)-1:0]   w_burst_sent_count;

    // Riadiace signály
    logic issue_write_cmd, issue_read_cmd;
    logic write_is_stalled, read_is_stalled;
    logic find_empty_buffer, find_full_buffer;
    logic [BUFFERS_ADDR_WIDTH-1:0] next_empty_buffer_idx, next_full_buffer_idx;
    logic next_empty_buffer_found, next_full_buffer_found;

    // --- Sekvenčná Logika (plne synchrónna) ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            for (int i = 0; i < NUM_BUFFERS; i++) buffer_state[i] <= EMPTY;
            write_ptr <= '0;
            read_ptr  <= '0;
            write_frame_word_count <= '0;
            read_frame_word_count  <= '0;
            write_segment_word_count <= '0;
            read_segment_word_count  <= '0;
            write_segment_addr_offset <= '0;
            read_segment_addr_offset  <= '0;
            w_buffer_fill_count <= '0;
            w_burst_sent_count  <= '0;
        end else begin
            for (int i = 0; i < NUM_BUFFERS; i++) buffer_state[i] <= buffer_state_next[i];
            write_ptr <= write_ptr_next;
            read_ptr  <= read_ptr_next;

            // Zápisové počítadlá
            if (s_axis_tready && s_axis_tvalid) begin
                write_frame_word_count <= write_frame_word_count + 1;
                write_segment_word_count <= write_segment_word_count + 1;
                w_buffer_fill_count <= w_buffer_fill_count + 1;
            end else if (issue_write_cmd && cmd_fifo_ready) begin
                w_buffer_fill_count <= 0;
            end
            if (find_empty_buffer) write_segment_word_count <= '0; // Reset pre nový segment

            // Čítacie počítadlá
            if (m_axis_tvalid && m_axis_tready) begin
                read_frame_word_count <= read_frame_word_count + 1;
                read_segment_word_count <= read_segment_word_count + 1;
            end
            if (find_full_buffer) read_segment_word_count <= '0; // Reset pre nový segment

            // Adresné offsety a burst počítadlo
            if (issue_write_cmd && cmd_fifo_ready) write_segment_addr_offset <= write_segment_addr_offset + BURST_LEN;
            if (find_empty_buffer) write_segment_addr_offset <= '0;
            if (issue_read_cmd && cmd_fifo_ready) read_segment_addr_offset <= read_segment_addr_offset + BURST_LEN;
            if (find_full_buffer) read_segment_addr_offset <= '0;
            if (issue_write_cmd && cmd_fifo_ready) w_burst_sent_count <= BURST_LEN;
            else if (wdata_valid && wdata_ready) w_burst_sent_count <= w_burst_sent_count - 1;

            // Reset počítadiel celého frame
            if (s_axis_tvalid && s_axis_tlast) write_frame_word_count <= '0;
            if (m_axis_tvalid && m_axis_tlast) read_frame_word_count <= '0;
        end
    end

    // --- Kombinačná Logika (Riadenie Ring Buffera) ---
    always_comb begin
        // --- Defaultné priradenia ---
        for (int i = 0; i < NUM_BUFFERS; i++) buffer_state_next[i] = buffer_state[i];
        write_ptr_next = write_ptr;
        read_ptr_next  = read_ptr;

        // --- Logika pre vyhľadávanie voľných/plných bufferov ---
        find_empty_buffer = 1'b0;
        find_full_buffer  = 1'b0;
        next_empty_buffer_idx = '0;
        next_full_buffer_idx  = '0;
        next_empty_buffer_found = 1'b0;
        next_full_buffer_found  = 1'b0;

        for (int i = 0; i < NUM_BUFFERS; i++) begin
            logic ptr = write_ptr + i + 1;
            if (buffer_state[ptr] == EMPTY && !next_empty_buffer_found) begin
                next_empty_buffer_idx = ptr;
                next_empty_buffer_found = 1'b1;
            end
            ptr = read_ptr + i + 1;
            if (buffer_state[ptr] == FULL && !next_full_buffer_found) begin
                next_full_buffer_idx = ptr;
                next_full_buffer_found = 1'b1;
            end
        end

        // --- Zmena stavov bufferov ---
        // Zápisová strana
        if (buffer_state[write_ptr] == EMPTY && s_axis_tready && s_axis_tvalid) buffer_state_next[write_ptr] = FILLING;
        if (buffer_state[write_ptr] == FILLING && write_segment_word_count == SEGMENT_LEN_WORDS - 1 && s_axis_tready && s_axis_tvalid) begin
            buffer_state_next[write_ptr] = FULL;
            find_empty_buffer = 1'b1;
            if (next_empty_buffer_found) write_ptr_next = next_empty_buffer_idx;
        end

        // Čítacia strana
        if (buffer_state[read_ptr] == FULL) begin
             buffer_state_next[read_ptr] = READING;
        end
        if (buffer_state[read_ptr] == READING && read_segment_word_count == SEGMENT_LEN_WORDS - 1 && m_axis_tvalid && m_axis_tready) begin
            buffer_state_next[read_ptr] = EMPTY;
            find_full_buffer = 1'b1;
            if (next_full_buffer_found) read_ptr_next = next_full_buffer_idx;
        end

        // --- Riadenie AXI-Stream a príkazov ---
        write_is_stalled = (buffer_state[write_ptr] == FILLING && write_segment_word_count == SEGMENT_LEN_WORDS - 1) && !next_empty_buffer_found;
        s_axis_tready = (buffer_state[write_ptr] == EMPTY || buffer_state[write_ptr] == FILLING) && !write_is_stalled;

        logic can_issue_write = (w_buffer_fill_count == BURST_LEN) && (buffer_state[write_ptr] == FILLING);
        logic can_issue_read  = (buffer_state[read_ptr] == READING) && (read_segment_word_count < SEGMENT_LEN_WORDS);

        issue_write_cmd = 1'b0;
        issue_read_cmd  = 1'b0;
        cmd_fifo_valid  = 1'b0;
        cmd_fifo_data   = '{default:'0};

        if (cmd_fifo_ready) begin
            if (can_issue_read) begin
                issue_read_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: SDRAM_BASE_ADDR + (read_ptr * SEGMENT_LEN_WORDS) + read_segment_addr_offset, rw: READ_CMD, auto_precharge: 1'b0};
            end else if (can_issue_write) begin
                issue_write_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data   = '{addr: SDRAM_BASE_ADDR + (write_ptr * SEGMENT_LEN_WORDS) + write_segment_addr_offset, rw: WRITE_CMD, auto_precharge: 1'b0};
            end
        end

        // --- Výstupy ---
        wdata_valid = (w_burst_sent_count > 0);
        wdata       = w_data_buffer[BURST_LEN - w_burst_sent_count];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid && (buffer_state[read_ptr] == READING);
        m_axis_tdata  = resp_data;
        m_axis_tlast  = m_axis_tvalid && (read_frame_word_count == PACKET_LEN_WORDS - 1);
        resp_ready    = m_axis_tready;

        debug_buffer_state = buffer_state;
        debug_write_ptr_o = write_ptr;
        debug_read_ptr_o = read_ptr;
    end

    // Plnenie interného burst buffera
    always_ff @(posedge clk) begin
        if (s_axis_tready && s_axis_tvalid) begin
            w_data_buffer[w_buffer_fill_count] <= s_axis_tdata;
        end
    end

endmodule

`endif
