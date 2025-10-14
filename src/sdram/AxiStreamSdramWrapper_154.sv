// AxiStreamSdramWrapper.sv - Verzia 1.54 - Deeply Pipelined DMA Engine
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny (v1.54):
// 1. ARCHITEKTÚRA: Implementovaný hlboký interný pipeline buffer (`w_pipeline_buffer`)
//    s konfigurovateľnou hĺbkou (`PIPELINE_DEPTH_BURSTS`). Tento buffer slúži ako
//    zásobník pre SDRAM bursty.
// 2. VÝKON (Preemptive Command Issue): Modul teraz vydáva príkazy na zápis do SDRAM
//    preemptívne - hneď ako sa v pipeline bufferi nazbiera dostatok dát pre jeden
//    burst. Nečaká sa na naplnenie celého segmentu, čo maximalizuje vyťaženie
//    SDRAM zbernice a celkovú priepustnosť.
// 3. RIADENIE: Logika bola upravená tak, aby riadila hlboký pipeline buffer pomocou
//    vlastných ukazovateľov a počítadiel, ktoré bežia nezávisle od hlavnej logiky
//    kruhového buffera segmentov.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    parameter integer NUM_BUFFERS       = 4,
    parameter integer PIPELINE_DEPTH_BURSTS = 4, // VYLEPŠENIE: Hĺbka interného pipeline (2-4 je ideálne)
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

    // --- Stavová logika pre každý buffer v kruhu ---
    buffer_state_t buffer_state [0:NUM_BUFFERS-1];
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr, read_ptr;

    // --- Hlboký Pipelined Burst Buffer (VYLEPŠENIE) ---
    logic [AXIS_DATA_WIDTH-1:0] w_pipeline_buffer [0:PIPELINE_BUFFER_SIZE-1];
    logic [PIPELINE_ADDR_WIDTH-1:0] w_pipeline_wptr, w_pipeline_rptr;
    logic [$clog2(PIPELINE_BUFFER_SIZE+1)-1:0] w_pipeline_level;

    // Počítadlá na úrovni segmentov a paketov
    logic [$clog2(PACKET_LEN_WORDS)-1:0]  write_frame_word_count, read_frame_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] write_bursts_sent_count; // Počet odoslaných burstov v segmente
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] read_segment_word_count;
    logic [SDRAM_ADDR_WIDTH-1:0]          write_segment_addr_offset, read_segment_addr_offset;

    // Riadiace signály
    logic issue_write_cmd, issue_read_cmd;
    logic [BUFFERS_ADDR_WIDTH-1:0] find_empty_start_idx, find_full_start_idx;
    logic [BUFFERS_ADDR_WIDTH-1:0] next_empty_buffer_idx, next_full_buffer_idx;
    logic next_empty_buffer_found, next_full_buffer_found;

    // --- Sekvenčná Logika ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            for (int i = 0; i < NUM_BUFFERS; i++) buffer_state[i] <= EMPTY;
            write_ptr <= '0; read_ptr <= '0;
            write_frame_word_count <= '0; read_frame_word_count <= '0;
            write_bursts_sent_count <= '0'; read_segment_word_count <= '0';
            write_segment_addr_offset <= '0'; read_segment_addr_offset <= '0';
            w_pipeline_wptr <= '0; w_pipeline_rptr <= '0; w_pipeline_level <= '0';
        end else begin
            // --- Riadenie kruhového buffera ---
            // Zápisový pointer sa posunie, keď sa aktuálny zapisovaný segment naplní a nájde sa nový voľný
            if (buffer_state[write_ptr] == FILLING && (write_bursts_sent_count * BURST_LEN) == SEGMENT_LEN_WORDS) begin
                buffer_state[write_ptr] <= FULL;
                if (next_empty_buffer_found) begin
                    write_ptr <= next_empty_buffer_idx;
                    buffer_state[next_empty_buffer_idx] <= FILLING;
                    write_bursts_sent_count <= '0;
                    write_segment_addr_offset <= '0';
                end
            end else if (buffer_state[write_ptr] == EMPTY && s_axis_tready && s_axis_tvalid) begin
                buffer_state[write_ptr] <= FILLING;
            end

            // Čítací pointer sa posunie, keď sa aktuálne čítaný segment prečíta a nájde sa nový plný
            if (buffer_state[read_ptr] == READING && read_segment_word_count == SEGMENT_LEN_WORDS) begin
                buffer_state[read_ptr] <= EMPTY;
                if (next_full_buffer_found) begin
                    read_ptr <= next_full_buffer_idx;
                    buffer_state[next_full_buffer_idx] <= READING;
                    read_segment_word_count <= '0;
                    read_segment_addr_offset <= '0';
                end
            end else if (buffer_state[read_ptr] == FULL) begin
                 buffer_state[read_ptr] <= READING;
            end

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
            if (issue_write_cmd && cmd_fifo_ready) begin
                write_bursts_sent_count <= write_bursts_sent_count + 1;
                write_segment_addr_offset <= write_segment_addr_offset + BURST_LEN;
            end
            if (m_axis_tvalid && m_axis_tready) read_segment_word_count <= read_segment_word_count + 1;
            if (issue_read_cmd && cmd_fifo_ready) read_segment_addr_offset <= read_segment_addr_offset + BURST_LEN;

            if (s_axis_tvalid && s_axis_tlast) write_frame_word_count <= '0;
            if (m_axis_tvalid && m_axis_tlast) read_frame_word_count <= '0;
        end
    end

    // --- Kombinačná Logika ---
    always_comb begin
        // --- Vyhľadávanie voľných/plných bufferov ---
        find_empty_start_idx = write_ptr;
        find_full_start_idx  = read_ptr;
        next_empty_buffer_found = 1'b0;
        next_full_buffer_found  = 1'b0;
        for (int i = 0; i < NUM_BUFFERS; i++) begin
            if (buffer_state[find_empty_start_idx + i] == EMPTY && !next_empty_buffer_found) begin
                next_empty_buffer_idx = find_empty_start_idx + i;
                next_empty_buffer_found = 1'b1;
            end
            if (buffer_state[find_full_start_idx + i] == FULL && !next_full_buffer_found) begin
                next_full_buffer_idx = find_full_start_idx + i;
                next_full_buffer_found = 1'b1;
            end
        end

        // --- Riadenie AXI-Stream a príkazov ---
        s_axis_tready = (w_pipeline_level < PIPELINE_BUFFER_SIZE);

        logic can_issue_write = (w_pipeline_level >= BURST_LEN) && (buffer_state[write_ptr] == FILLING);
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
                cmd_fifo_data   = '{addr: SDRAM_BASE_ADDR + (write_ptr * SEGMENT_LEN_WORDS) + write_segment_addr_offset, rw: WRITE_CMD, auto_precharge: 1'b0};
            end
        end

        // --- Výstupy ---
        wdata_valid = (w_pipeline_rptr != (w_pipeline_wptr - w_pipeline_level + (issue_write_cmd ? BURST_LEN : 0))); // Logika pre wdata
        wdata       = w_pipeline_buffer[w_pipeline_rptr];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid && (buffer_state[read_ptr] == READING || buffer_state[read_ptr] == FULL);
        m_axis_tdata  = resp_data;
        m_axis_tlast  = m_axis_tvalid && (read_frame_word_count + read_segment_word_count == PACKET_LEN_WORDS - 1);
        resp_ready    = m_axis_tready;

        debug_buffer_state = buffer_state;
        debug_write_ptr_o = write_ptr;
        debug_read_ptr_o = read_ptr;
        debug_pipeline_level_o = w_pipeline_level;
    end

endmodule

`endif
