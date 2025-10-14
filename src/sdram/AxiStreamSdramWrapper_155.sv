// AxiStreamSdramWrapper.sv - Verzia 1.55 - Adaptive, Deeply Pipelined DMA Engine
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny (v1.55):
// 1. ARCHITEKTÚRA (Overlapping I/O): Riadenie kruhového buffera bolo vylepšené tak,
//    aby umožňovalo "overlapping" operácie. Zápis do nového segmentu môže začať
//    aj v bufferi, z ktorého sa ešte číta (stav READING), čím sa maximalizuje
//    využitie bufferov a eliminuje čakanie.
// 2. VÝKON (Threshold-based Writes): Pridaná prahová hodnota pre interný pipeline
//    buffer. Príkazy na zápis sa vydávajú až po prekročení tohto prahu, čo
//    dávkuje prístup na zápis a implicitne prioritizuje plynulý tok na čítanie (QoS).
// 3. ROBUSTNOSŤ (FIFO Logic): Logika pre riadenie pipeline buffera a signálu
//    `wdata_valid` bola zjednodušená na kanonický a robustnejší tvar.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    parameter integer NUM_BUFFERS       = 4,
    parameter integer PIPELINE_DEPTH_BURSTS = 4,
    parameter integer PIPELINE_WRITE_THRESHOLD_BURSTS = 2, // VYLEPŠENIE: Prah pre vydanie príkazu na zápis
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

    // Debugging Outputs
    output sdram_pkg::buffer_state_t debug_buffer_state [0:NUM_BUFFERS-1],
    output logic [$clog2(NUM_BUFFERS)-1:0] debug_write_ptr_o,
    output logic [$clog2(NUM_BUFFERS)-1:0] debug_read_ptr_o,
    output logic [$clog2(PIPELINE_DEPTH_BURSTS*BURST_LEN+1)-1:0] debug_pipeline_level_o,

    // System Signals
    input  logic                     clk,
    input  logic                     rstn
);

    import sdram_pkg::*;

    // --- Ring Buffer Parameters ---
    localparam integer BUFFERS_ADDR_WIDTH = $clog2(NUM_BUFFERS);
    localparam integer PIPELINE_BUFFER_SIZE = PIPELINE_DEPTH_BURSTS * BURST_LEN;
    localparam integer PIPELINE_ADDR_WIDTH = $clog2(PIPELINE_BUFFER_SIZE);
    localparam integer PIPELINE_WRITE_THRESHOLD_WORDS = PIPELINE_WRITE_THRESHOLD_BURSTS * BURST_LEN;

    // --- Stavová logika pre každý buffer v kruhu ---
    buffer_state_t buffer_state [0:NUM_BUFFERS-1], buffer_state_next [0:NUM_BUFFERS-1];
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr, read_ptr;
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr_next, read_ptr_next;

    // --- Hlboký Pipelined Burst Buffer ---
    logic [AXIS_DATA_WIDTH-1:0] w_pipeline_buffer [0:PIPELINE_BUFFER_SIZE-1];
    logic [PIPELINE_ADDR_WIDTH-1:0] w_pipeline_wptr, w_pipeline_rptr;
    logic [$clog2(PIPELINE_BUFFER_SIZE+1)-1:0] w_pipeline_level;

    // Počítadlá na úrovni segmentov a paketov
    logic [$clog2(PACKET_LEN_WORDS)-1:0]  write_frame_word_count, read_frame_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS/BURST_LEN)-1:0] write_bursts_sent_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] read_segment_word_count;
    logic [SDRAM_ADDR_WIDTH-1:0]          read_segment_addr_offset;

    // Riadiace signály
    logic issue_write_cmd, issue_read_cmd;
    logic [BUFFERS_ADDR_WIDTH-1:0] next_empty_buffer_idx, next_full_buffer_idx;
    logic next_empty_buffer_found, next_full_buffer_found;

    // --- Sekvenčná Logika ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            for (int i = 0; i < NUM_BUFFERS; i++) buffer_state[i] <= EMPTY;
            write_ptr <= '0; read_ptr <= '0;
            write_frame_word_count <= '0; read_frame_word_count <= '0;
            write_bursts_sent_count <= '0'; read_segment_word_count <= '0;
            read_segment_addr_offset <= '0';
            w_pipeline_wptr <= '0; w_pipeline_rptr <= '0; w_pipeline_level <= '0';
        end else begin
            for (int i = 0; i < NUM_BUFFERS; i++) buffer_state[i] <= buffer_state_next[i];
            write_ptr <= write_ptr_next;
            read_ptr  <= read_ptr_next;

            // --- Riadenie interného pipeline buffera ---
            if (s_axis_tready && s_axis_tvalid) begin
                w_pipeline_buffer[w_pipeline_wptr] <= s_axis_tdata;
                w_pipeline_wptr <= w_pipeline_wptr + 1;
            end
            if (wdata_valid && wdata_ready) begin
                w_pipeline_rptr <= w_pipeline_rptr + 1;
            end
            logic w_pipeline_write = s_axis_tready && s_axis_tvalid;
            logic w_pipeline_read = wdata_valid && wdata_ready;
            w_pipeline_level <= w_pipeline_level + w_pipeline_write - w_pipeline_read;

            // --- Riadenie ostatných počítadiel ---
            if (s_axis_tready && s_axis_tvalid) write_frame_word_count <= write_frame_word_count + 1;
            if (issue_write_cmd && cmd_fifo_ready) write_bursts_sent_count <= write_bursts_sent_count + 1;
            if (m_axis_tvalid && m_axis_tready) read_segment_word_count <= read_segment_word_count + 1;
            if (issue_read_cmd && cmd_fifo_ready) read_segment_addr_offset <= read_segment_addr_offset + BURST_LEN;

            // Reset počítadiel po dokončení frame
            if (s_axis_tvalid && s_axis_tlast) write_frame_word_count <= '0;
            if (m_axis_tvalid && m_axis_tlast) read_frame_word_count <= '0;
        end
    end

    // --- Kombinačná Logika ---
    always_comb begin
        // --- Defaultné priradenia ---
        for (int i = 0; i < NUM_BUFFERS; i++) buffer_state_next[i] = buffer_state[i];
        write_ptr_next = write_ptr;
        read_ptr_next  = read_ptr;

        // --- Logika pre vyhľadávanie bufferov a zmenu stavov ---
        next_empty_buffer_found = 1'b0;
        next_full_buffer_found  = 1'b0;
        for (int i = 0; i < NUM_BUFFERS; i++) begin
            logic current_idx = write_ptr + i;
            // VYLEPŠENIE (Overlapping I/O): Buffer je voľný na zápis, ak je EMPTY alebo sa z neho už len ČÍTA
            if ((buffer_state[current_idx] == EMPTY || buffer_state[current_idx] == READING) && !next_empty_buffer_found) begin
                next_empty_buffer_idx = current_idx;
                next_empty_buffer_found = 1'b1;
            end
            current_idx = read_ptr + i;
            if (buffer_state[current_idx] == FULL && !next_full_buffer_found) begin
                next_full_buffer_idx = current_idx;
                next_full_buffer_found = 1'b1;
            end
        end

        // Zmena stavu: Začiatok zápisu
        if (buffer_state[write_ptr] == EMPTY && s_axis_tready && s_axis_tvalid) buffer_state_next[write_ptr] = FILLING;

        // Zmena stavu: Koniec zápisu segmentu
        if (buffer_state[write_ptr] == FILLING && write_bursts_sent_count == (SEGMENT_LEN_WORDS / BURST_LEN)) begin
            buffer_state_next[write_ptr] = FULL;
            if (next_empty_buffer_found) write_ptr_next = next_empty_buffer_idx;
            write_bursts_sent_count = '0; // Reset pre nový segment
        end

        // Zmena stavu: Začiatok čítania
        if (buffer_state[read_ptr] == FULL) buffer_state_next[read_ptr] = READING;

        // Zmena stavu: Koniec čítania segmentu
        if (buffer_state[read_ptr] == READING && read_segment_word_count == SEGMENT_LEN_WORDS) begin
            buffer_state_next[read_ptr] = EMPTY;
            if (next_full_buffer_found) read_ptr_next = next_full_buffer_idx;
            read_segment_word_count = '0; // Reset pre nový segment
            read_segment_addr_offset = '0;
        end

        // --- Riadenie AXI-Stream a príkazov ---
        s_axis_tready = (w_pipeline_level < PIPELINE_BUFFER_SIZE) && (buffer_state[write_ptr] == EMPTY || buffer_state[write_ptr] == FILLING);

        // VYLEPŠENIE (Threshold-based Writes): Príkaz sa vydá až po prekročení prahu
        logic can_issue_write = (w_pipeline_level >= PIPELINE_WRITE_THRESHOLD_WORDS) && (buffer_state[write_ptr] == FILLING);
        logic can_issue_read  = (buffer_state[read_ptr] == READING || buffer_state[read_ptr] == FULL) && (read_segment_word_count < SEGMENT_LEN_WORDS);

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
                cmd_fifo_data   = '{addr: SDRAM_BASE_ADDR + (write_ptr * SEGMENT_LEN_WORDS) + (write_bursts_sent_count * BURST_LEN), rw: WRITE_CMD, auto_precharge: 1'b0};
            end
        end

        // --- Výstupy ---
        wdata_valid = (w_pipeline_level > 0); // VYLEPŠENIE (Robust FIFO Logic)
        wdata       = w_pipeline_buffer[w_pipeline_rptr];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid && (buffer_state[read_ptr] == READING || buffer_state[read_ptr] == FULL);
        m_axis_tdata  = resp_data;
        m_axis_tlast  = m_axis_tvalid && (read_frame_word_count == PACKET_LEN_WORDS - 1);
        resp_ready    = m_axis_tready;

        // --- Ladiace Výstupy ---
        debug_buffer_state = buffer_state;
        debug_write_ptr_o = write_ptr;
        debug_read_ptr_o = read_ptr;
        debug_pipeline_level_o = w_pipeline_level;
    end

endmodule

`endif
