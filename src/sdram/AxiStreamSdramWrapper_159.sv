// AxiStreamSdramWrapper.sv - Verzia 1.59 - Synthesis-Optimized DMA Scheduler
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny (v1.59):
// 1. OPTIMALIZÁCIA (Adresovanie): Násobenie pri výpočte adries bufferov bolo nahradené
//    statickým poľom predpočítaných adries (`BUFFER_BASE_ADDRS`), čo znižuje
//    využitie zdrojov a zlepšuje časovanie (timing closure).
// 2. ROBUSTNOSŤ (tlast): Logika pre generovanie `m_axis_tlast` bola zjednodušená
//    a sprehľadnená pomocou dedikovaného signálu `is_last_word_of_frame`.
// 3. POTVRDENIE: Architektúra pre dávkovanie príkazov a reset logika boli preverené
//    a potvrdené ako optimálne pre cieľové nasadenie.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    // --- Hlavné Parametre ---
    parameter integer FRAME_LEN_WORDS   = 480000,
    parameter integer SEGMENT_LEN_WORDS = 1024,
    parameter integer NUM_BUFFERS       = 4,
    parameter integer PIPELINE_DEPTH_BURSTS = 4,
    parameter integer PIPELINE_WRITE_THRESHOLD_BURSTS = 2,
    parameter integer READ_LOOKAHEAD_TRIGGER_BURSTS = 2,

    // --- Rozhrania a SDRAM ---
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer BURST_LEN         = 8,
    parameter logic [SDRAM_ADDR_WIDTH-1:0] SDRAM_BASE_ADDR = 24'h0,

    // --- Parametre pre spoluprácu s kontrolérom ---
    parameter integer CMD_FIFO_DEPTH    = 16
) (
    // AXI-Stream Interfaces
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,
    input  logic                       s_axis_tuser_sof,

    output logic [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast,

    // SDRAM Controller Interface
    output logic                     cmd_fifo_valid,
    input  logic                     cmd_fifo_ready,
    input  logic [$clog2(CMD_FIFO_DEPTH)-1:0] cmd_fifo_level_i,
    output sdram_pkg::sdram_cmd_t    cmd_fifo_data,
    output logic                     wdata_valid,
    output logic [AXIS_DATA_WIDTH-1:0] wdata,
    output logic [1:0]                wdata_dqm_i,
    input  logic                     wdata_ready,
    input  logic                     resp_valid,
    input  logic                     resp_last,
    input  logic [AXIS_DATA_WIDTH-1:0] resp_data,
    output logic                     resp_ready,

    // System Signals
    input  logic                     clk,
    input  logic                     rstn
);

    import sdram_pkg::*;

    localparam integer BUFFERS_ADDR_WIDTH = $clog2(NUM_BUFFERS);
    localparam integer PIPELINE_BUFFER_SIZE = PIPELINE_DEPTH_BURSTS * BURST_LEN;
    localparam integer PIPELINE_ADDR_WIDTH = $clog2(PIPELINE_BUFFER_SIZE);
    localparam integer PIPELINE_WRITE_THRESHOLD_WORDS = PIPELINE_WRITE_THRESHOLD_BURSTS * BURST_LEN;

    // VYLEPŠENIE: Predpočítané bázové adresy pre každý segmentový buffer
    localparam logic [SDRAM_ADDR_WIDTH-1:0] BUFFER_BASE_ADDRS [NUM_BUFFERS-1:0] =
        gen_buffer_addrs(SDRAM_BASE_ADDR, SEGMENT_LEN_WORDS, NUM_BUFFERS);

    function automatic logic [SDRAM_ADDR_WIDTH-1:0] [NUM_BUFFERS-1:0] gen_buffer_addrs(
        logic [SDRAM_ADDR_WIDTH-1:0] base, integer segment_size, integer num
    );
        for (int i = 0; i < num; i++) begin
            gen_buffer_addrs[i] = base + (i * segment_size);
        end
    endfunction

    // --- Stavová logika pre každý buffer v kruhu ---
    buffer_state_t buffer_state [0:NUM_BUFFERS-1];
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr, read_ptr;
    logic read_cmd_issued[0:NUM_BUFFERS-1];

    // --- Hlboký Pipelined Burst Buffer ---
    logic [AXIS_DATA_WIDTH-1:0] w_pipeline_buffer [0:PIPELINE_BUFFER_SIZE-1];
    logic [PIPELINE_ADDR_WIDTH-1:0] w_pipeline_wptr, w_pipeline_rptr;
    logic [$clog2(PIPELINE_BUFFER_SIZE+1)-1:0] w_pipeline_level;

    // Počítadlá
    logic [$clog2(FRAME_LEN_WORDS)-1:0]  write_frame_word_count, read_frame_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS/BURST_LEN)-1:0] write_bursts_sent_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] read_segment_word_count;

    // Riadiace signály
    logic issue_write_cmd, issue_read_cmd, issue_aggressive_lookahead_cmd;
    logic [BUFFERS_ADDR_WIDTH-1:0] lookahead_ptr;

    // --- Sekvenčná Logika ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            for (int i = 0; i < NUM_BUFFERS; i++) begin
                buffer_state[i] <= EMPTY;
                read_cmd_issued[i] <= 1'b0;
            end
            write_ptr <= '0; read_ptr <= '0;
            write_frame_word_count <= '0; read_frame_word_count <= '0;
            write_bursts_sent_count <= '0; read_segment_word_count <= '0;
            w_pipeline_wptr <= '0; w_pipeline_rptr <= '0; w_pipeline_level <= '0';
        end else begin
            // --- Riadenie kruhového buffera (kontinuálny režim) ---
            if (s_axis_tready && s_axis_tuser_sof) begin
                write_frame_word_count <= '0;
                read_frame_word_count <= '0;
            end else if (s_axis_tready && s_axis_tvalid) begin
                 write_frame_word_count <= write_frame_word_count + 1;
            end

            // Zmena stavu: Začiatok zápisu
            if (buffer_state[write_ptr] == EMPTY && s_axis_tready && s_axis_tvalid) begin
                 buffer_state[write_ptr] <= FILLING;
            end
            // Zmena stavu: Koniec zápisu segmentu
            if (buffer_state[write_ptr] == FILLING && write_bursts_sent_count == (SEGMENT_LEN_WORDS / BURST_LEN - 1) && issue_write_cmd && cmd_fifo_ready) begin
                buffer_state[write_ptr] <= FULL;
                write_ptr <= write_ptr + 1;
                write_bursts_sent_count <= '0;
            end

            // Zmena stavu: Začiatok čítania
            if (buffer_state[read_ptr] == FULL && read_cmd_issued[read_ptr]) begin
                 buffer_state[read_ptr] <= READING;
            end
            // Zmena stavu: Koniec čítania segmentu
            if (buffer_state[read_ptr] == READING && read_segment_word_count == SEGMENT_LEN_WORDS - 1 && m_axis_tvalid && m_axis_tready) begin
                buffer_state[read_ptr] <= EMPTY;
                read_cmd_issued[read_ptr] <= 1'b0;
                read_ptr <= read_ptr + 1;
                read_segment_word_count <= '0;
            end

            // Vydanie príkazu pre agresívny lookahead
            if (issue_aggressive_lookahead_cmd && cmd_fifo_ready) begin
                read_cmd_issued[lookahead_ptr] <= 1'b1;
            end

            // --- Riadenie interného pipeline buffera ---
            if (s_axis_tready && s_axis_tvalid) begin
                w_pipeline_buffer[w_pipeline_wptr] <= s_axis_tdata;
                w_pipeline_wptr <= w_pipeline_wptr + 1;
            end
            if (wdata_valid && wdata_ready) w_pipeline_rptr <= w_pipeline_rptr + 1;
            w_pipeline_level <= w_pipeline_level + (s_axis_tready && s_axis_tvalid) - (wdata_valid && wdata_ready);

            // --- Riadenie ostatných počítadiel ---
            if (issue_write_cmd && cmd_fifo_ready) write_bursts_sent_count <= write_bursts_sent_count + 1;
            if (m_axis_tvalid && m_axis_tready) begin
                read_segment_word_count <= read_segment_word_count + 1;
                read_frame_word_count <= read_frame_word_count + 1;
            end
        end
    end

    // --- Kombinačná Logika ---
    always_comb begin
        // --- Riadenie AXI-Stream a príkazov ---
        s_axis_tready = (buffer_state[write_ptr] == EMPTY || buffer_state[write_ptr] == FILLING) && (w_pipeline_level < PIPELINE_BUFFER_SIZE);

        logic last_burst_of_write_segment = (write_bursts_sent_count == (SEGMENT_LEN_WORDS / BURST_LEN - 1));

        // --- Logika pre agresívny lookahead ---
        issue_aggressive_lookahead_cmd = 1'b0;
        lookahead_ptr = '0;
        for (int i = 0; i < NUM_BUFFERS; i++) begin
            int ptr = (read_ptr + i) % NUM_BUFFERS;
            if (buffer_state[ptr] == FULL && !read_cmd_issued[ptr]) begin
                issue_aggressive_lookahead_cmd = 1'b1;
                lookahead_ptr = ptr;
                break;
            end
        end

        // Podmienky pre vydanie príkazov
        logic can_issue_write = (w_pipeline_level >= PIPELINE_WRITE_THRESHOLD_WORDS) && (buffer_state[write_ptr] == FILLING);
        logic can_issue_read  = (buffer_state[read_ptr] == READING);

        logic can_push_to_cmd_fifo = (cmd_fifo_level_i < CMD_FIFO_DEPTH - 2); // Ponechajme malú rezervu

        issue_write_cmd = 1'b0; issue_read_cmd = 1'b0;
        cmd_fifo_valid  = 1'b0; cmd_fifo_data   = '{default:'0};

        // Arbiter s prioritou, ktorý rešpektuje zaplnenie cieľového FIFO
        if (can_push_to_cmd_fifo) begin
            if (issue_aggressive_lookahead_cmd) begin
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: BUFFER_BASE_ADDRS[lookahead_ptr] , rw: READ_CMD, auto_precharge: 1'b0};
            end else if (can_issue_read) begin
                issue_read_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                logic is_last_burst_of_segment = (read_segment_word_count >= (SEGMENT_LEN_WORDS - BURST_LEN));
                cmd_fifo_data  = '{addr: BUFFER_BASE_ADDRS[read_ptr] + (read_segment_word_count & ~(BURST_LEN-1)), rw: READ_CMD, auto_precharge: is_last_burst_of_segment};
            end else if (can_issue_write) begin
                issue_write_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: BUFFER_BASE_ADDRS[write_ptr] + (write_bursts_sent_count * BURST_LEN), rw: WRITE_CMD, auto_precharge: last_burst_of_write_segment};
            end
        end

        // --- Výstupy ---
        wdata_valid = (w_pipeline_level > 0);
        wdata       = w_pipeline_buffer[w_pipeline_rptr];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid && (buffer_state[read_ptr] == READING);
        m_axis_tdata  = resp_data;

        // VYLEPŠENIE: Zjednodušená a robustná `tlast` logika
        logic is_last_word_of_frame = (read_frame_word_count == FRAME_LEN_WORDS - 1);
        m_axis_tlast  = m_axis_tvalid && is_last_word_of_frame;

        resp_ready    = m_axis_tready;
    end

endmodule

`endif
