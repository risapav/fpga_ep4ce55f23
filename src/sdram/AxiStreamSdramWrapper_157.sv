// AxiStreamSdramWrapper.sv - Verzia 1.57 - Frame-Aware Streaming DMA Engine
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny (v1.57):
// 1. ARCHITEKTÚRA (Frame-Aware): Modul je teraz priamo riadený veľkosťou celej snímky
//    (`FRAME_LEN_WORDS`). Odstránené boli abstraktné parametre `PACKET_LEN_WORDS` a
//    `SUBFRAME_LEN_SEGMENTS`.
// 2. SYNCHRONIZÁCIA (Start-of-Frame): Pridaný vstup `s_axis_tuser_sof` pre robustnú
//    detekciu začiatku novej snímky, čo je štandard vo video aplikáciách.
// 3. RIADENIE: Celková logika bola zjednodušená. Modul teraz funguje v kontinuálnom
//    streaming režime, riadenom začiatkom a dĺžkou snímky, nie umelými paketmi.
// 4. ZACHOVANIE VÝKONU: Všetky nízkoúrovňové optimalizácie z v1.56 (strategický
//    auto-precharge, prediktívne čítanie) sú plne zachované.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    // --- Hlavné Parametre ---
    parameter integer FRAME_LEN_WORDS   = 480000, // VYLEPŠENIE: Celková veľkosť snímky v slovách
    parameter integer SEGMENT_LEN_WORDS = 1024,   // Veľkosť segmentu pre pipelining
    parameter integer NUM_BUFFERS       = 4,
    parameter integer PIPELINE_DEPTH_BURSTS = 4,
    parameter integer PIPELINE_WRITE_THRESHOLD_BURSTS = 2,

    // --- Rozhrania a SDRAM ---
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer BURST_LEN         = 8,
    parameter logic [SDRAM_ADDR_WIDTH-1:0] SDRAM_BASE_ADDR = 24'h0
) (
    // AXI-Stream Interfaces
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,
    input  logic                       s_axis_tuser_sof, // VYLEPŠENIE: Start of Frame

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

    // System Signals
    input  logic                     clk,
    input  logic                     rstn
);

    import sdram_pkg::*;

    // --- Parametre a Odvodené Hodnoty ---
    localparam integer BUFFERS_ADDR_WIDTH = $clog2(NUM_BUFFERS);
    localparam integer PIPELINE_BUFFER_SIZE = PIPELINE_DEPTH_BURSTS * BURST_LEN;
    localparam integer PIPELINE_ADDR_WIDTH = $clog2(PIPELINE_BUFFER_SIZE);
    localparam integer PIPELINE_WRITE_THRESHOLD_WORDS = PIPELINE_WRITE_THRESHOLD_BURSTS * BURST_LEN;

    // --- Hlavný Stavový Automat (Frame-level) ---
    typedef enum logic {IDLE, RECEIVING_FRAME} frame_state_t;
    frame_state_t frame_state, frame_state_next;

    // --- Stavová logika pre každý buffer v kruhu ---
    buffer_state_t buffer_state [0:NUM_BUFFERS-1], buffer_state_next [0:NUM_BUFFERS-1];
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr, read_ptr;
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr_next, read_ptr_next;
    logic read_lookahead_issued[0:NUM_BUFFERS-1], read_lookahead_issued_next[0:NUM_BUFFERS-1];

    // --- Hlboký Pipelined Burst Buffer ---
    logic [AXIS_DATA_WIDTH-1:0] w_pipeline_buffer [0:PIPELINE_BUFFER_SIZE-1];
    logic [PIPELINE_ADDR_WIDTH-1:0] w_pipeline_wptr, w_pipeline_rptr;
    logic [$clog2(PIPELINE_BUFFER_SIZE+1)-1:0] w_pipeline_level;

    // Počítadlá
    logic [$clog2(FRAME_LEN_WORDS)-1:0]  write_frame_word_count, read_frame_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS/BURST_LEN)-1:0] write_bursts_sent_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] read_segment_word_count;

    // Riadiace signály
    logic issue_write_cmd, issue_read_cmd, issue_lookahead_read_cmd;
    logic [BUFFERS_ADDR_WIDTH-1:0] next_empty_buffer_idx, next_full_buffer_idx;
    logic next_empty_buffer_found, next_full_buffer_found;

    // --- Sekvenčná Logika ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            frame_state <= IDLE;
            for (int i = 0; i < NUM_BUFFERS; i++) begin
                buffer_state[i] <= EMPTY;
                read_lookahead_issued[i] <= 1'b0;
            end
            write_ptr <= '0; read_ptr <= '0;
            write_frame_word_count <= '0; read_frame_word_count <= '0;
            write_bursts_sent_count <= '0'; read_segment_word_count <= '0;
            w_pipeline_wptr <= '0; w_pipeline_rptr <= '0; w_pipeline_level <= '0';
        end else begin
            frame_state <= frame_state_next;

            // Ak prechádzame do IDLE, resetujeme všetko pre ďalšiu snímku
            if (frame_state_next == IDLE && frame_state == RECEIVING_FRAME) begin
                for (int i = 0; i < NUM_BUFFERS; i++) begin
                    buffer_state[i] <= EMPTY;
                    read_lookahead_issued[i] <= 1'b0;
                end
                write_ptr <= '0; read_ptr <= '0;
                write_frame_word_count <= '0; read_frame_word_count <= '0;
                write_bursts_sent_count <= '0; read_segment_word_count <= '0;
            end else if (frame_state == RECEIVING_FRAME) begin // Logika beží len počas prenosu
                for (int i = 0; i < NUM_BUFFERS; i++) begin
                    buffer_state[i] <= buffer_state_next[i];
                    read_lookahead_issued[i] <= read_lookahead_issued_next[i];
                end
                write_ptr <= write_ptr_next;
                read_ptr  <= read_ptr_next;
            end

            // Interný pipeline buffer beží vždy, keď je `tready`
            if (s_axis_tready && s_axis_tvalid) begin
                w_pipeline_buffer[w_pipeline_wptr] <= s_axis_tdata;
                w_pipeline_wptr <= w_pipeline_wptr + 1;
            end
            if (wdata_valid && wdata_ready) w_pipeline_rptr <= w_pipeline_rptr + 1;
            logic w_pipeline_write = s_axis_tready && s_axis_tvalid;
            logic w_pipeline_read = wdata_valid && wdata_ready;
            w_pipeline_level <= w_pipeline_level + w_pipeline_write - w_pipeline_read;

            // Počítadlá bežia len počas prenosu
            if (frame_state == RECEIVING_FRAME) begin
                if (s_axis_tready && s_axis_tvalid) write_frame_word_count <= write_frame_word_count + 1;
                if (issue_write_cmd && cmd_fifo_ready) write_bursts_sent_count <= write_bursts_sent_count + 1;
                if (m_axis_tvalid && m_axis_tready) read_frame_word_count <= read_frame_word_count + 1;
                if (m_axis_tvalid && m_axis_tready) read_segment_word_count <= read_segment_word_count + 1;
            end
        end
    end

    // --- Kombinačná Logika ---
    always_comb begin
        // --- Defaultné priradenia ---
        frame_state_next = frame_state;
        for (int i = 0; i < NUM_BUFFERS; i++) begin
            buffer_state_next[i] = buffer_state[i];
            read_lookahead_issued_next[i] = read_lookahead_issued[i];
        end
        write_ptr_next = write_ptr;
        read_ptr_next  = read_ptr;

        // --- Hlavný FSM (Frame-level) ---
        case (frame_state)
            IDLE: if (s_axis_tvalid && s_axis_tuser_sof) frame_state_next = RECEIVING_FRAME;
            RECEIVING_FRAME: if (read_frame_word_count == FRAME_LEN_WORDS - 1 && m_axis_tvalid && m_axis_tready) frame_state_next = IDLE;
        endcase

        // --- Logika pre vyhľadávanie bufferov a zmenu stavov ---
        next_empty_buffer_found = 1'b0; next_full_buffer_found = 1'b0;
        for (int i = 0; i < NUM_BUFFERS; i++) begin
            logic current_idx = write_ptr + i;
            if ((buffer_state[current_idx] == EMPTY || buffer_state[current_idx] == READING) && !next_empty_buffer_found) begin
                next_empty_buffer_idx = current_idx; next_empty_buffer_found = 1'b1;
            end
            current_idx = read_ptr + i;
            if (buffer_state[current_idx] == FULL && !next_full_buffer_found) begin
                next_full_buffer_idx = current_idx; next_full_buffer_found = 1'b1;
            end
        end

        if (frame_state == RECEIVING_FRAME) begin
            // Zmena stavu: Začiatok zápisu -> Koniec zápisu
            if (buffer_state[write_ptr] == EMPTY && s_axis_tready && s_axis_tvalid) buffer_state_next[write_ptr] = FILLING;
            if (buffer_state[write_ptr] == FILLING && write_bursts_sent_count == (SEGMENT_LEN_WORDS / BURST_LEN - 1) && issue_write_cmd && cmd_fifo_ready) begin
                buffer_state_next[write_ptr] = FULL;
                if (next_empty_buffer_found) write_ptr_next = next_empty_buffer_idx;
                write_bursts_sent_count = '0;
            end
            // Zmena stavu: Začiatok čítania -> Koniec čítania
            if (buffer_state[read_ptr] == FULL && (!read_lookahead_issued[read_ptr] || issue_lookahead_read_cmd)) buffer_state_next[read_ptr] = READING;
            if (buffer_state[read_ptr] == READING && read_segment_word_count == SEGMENT_LEN_WORDS - 1 && m_axis_tvalid && m_axis_tready) begin
                buffer_state_next[read_ptr] = EMPTY;
                read_lookahead_issued_next[read_ptr] = 1'b0;
                if (next_full_buffer_found) read_ptr_next = next_full_buffer_idx;
                read_segment_word_count = '0;
            end
        end

        // --- Riadenie AXI-Stream a príkazov ---
        s_axis_tready = (frame_state == RECEIVING_FRAME) && (w_pipeline_level < PIPELINE_BUFFER_SIZE) && (buffer_state[write_ptr] == EMPTY || buffer_state[write_ptr] == FILLING);

        logic last_burst_of_write_segment = (write_bursts_sent_count == (SEGMENT_LEN_WORDS / BURST_LEN - 1));
        logic read_lookahead_trigger = (read_segment_word_count >= (SEGMENT_LEN_WORDS - BURST_LEN*2)); // Spusti lookahead 2 bursty pred koncom

        // Podmienky pre vydanie príkazov
        logic can_issue_write = (w_pipeline_level >= PIPELINE_WRITE_THRESHOLD_WORDS) && (buffer_state[write_ptr] == FILLING) && (frame_state == RECEIVING_FRAME);
        logic can_issue_read  = (buffer_state[read_ptr] == READING);
        logic can_issue_lookahead_read = (buffer_state[read_ptr] == READING) && read_lookahead_trigger && next_full_buffer_found && !read_lookahead_issued[next_full_buffer_idx];

        issue_write_cmd = 1'b0; issue_read_cmd = 1'b0; issue_lookahead_read_cmd = 1'b0;
        cmd_fifo_valid  = 1'b0; cmd_fifo_data   = '{default:'0};

        // Arbiter s prioritou: 1. Prediktívne čítanie, 2. Aktuálne čítanie, 3. Zápis
        if (cmd_fifo_ready) begin
            if (can_issue_lookahead_read) begin
                issue_lookahead_read_cmd = 1'b1;
                read_lookahead_issued_next[next_full_buffer_idx] = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: SDRAM_BASE_ADDR + (next_full_buffer_idx * SEGMENT_LEN_WORDS), rw: READ_CMD, auto_precharge: 1'b0};
            end else if (can_issue_read) begin
                issue_read_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                logic is_last_burst = (read_segment_word_count >= (SEGMENT_LEN_WORDS - BURST_LEN));
                cmd_fifo_data  = '{addr: SDRAM_BASE_ADDR + (read_ptr * SEGMENT_LEN_WORDS) + (read_segment_word_count & ~(BURST_LEN-1)), rw: READ_CMD, auto_precharge: is_last_burst};
            end else if (can_issue_write) begin
                issue_write_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: SDRAM_BASE_ADDR + (write_ptr * SEGMENT_LEN_WORDS) + (write_bursts_sent_count * BURST_LEN), rw: WRITE_CMD, auto_precharge: last_burst_of_write_segment};
            end
        end

        // --- Výstupy ---
        wdata_valid = (w_pipeline_level > 0);
        wdata       = w_pipeline_buffer[w_pipeline_rptr];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid && (buffer_state[read_ptr] == READING || buffer_state[read_ptr] == FULL);
        m_axis_tdata  = resp_data;
        m_axis_tlast  = m_axis_tvalid && (read_frame_word_count == FRAME_LEN_WORDS - 1);
        resp_ready    = m_axis_tready;
    end

endmodule

`endif
