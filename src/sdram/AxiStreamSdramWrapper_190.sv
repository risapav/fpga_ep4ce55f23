// AxiStreamSdramWrapper.sv - Verzia 1.90 - Advanced Control & Debug
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny (v1.90):
// 1. VYLEPŠENIE (Soft Reset): Pridaný externý vstup `soft_reset_i` pre možnosť
//    resetovania modulu bez nutnosti globálneho hardvérového resetu.
// 2. VYLEPŠENIE (Ladenie): Pridané nové ladiace výstupy na detailné monitorovanie
//    stavu pipeline buffera, príkazového FIFO a kruhových ukazovateľov.
//
// Zmeny (v1.80):
// 1. Implementovaný "watchdog" časovač pre detekciu zaseknutého streamu.
// 2. Pridané `assert` príkazy pre aktívnu kontrolu počas simulácie.
// 3. Parameterizovaná prahová hodnota pre odosielanie príkazov do FIFO.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    // --- Hlavné Parametre ---
    parameter integer SEGMENT_LEN_WORDS = 1024,
    parameter integer NUM_BUFFERS       = 4,
    parameter integer PIPELINE_DEPTH_BURSTS = 4,
    parameter integer PIPELINE_WRITE_THRESHOLD_BURSTS = 2,
    parameter integer STREAM_TIMEOUT_CYCLES = 1_000_000,
    parameter integer CMD_FIFO_THRESHOLD = 4,

    // --- Rozhrania a SDRAM ---
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer BURST_LEN         = 8,
    parameter logic [SDRAM_ADDR_WIDTH-1:0] SDRAM_BASE_ADDR = 24'h0,
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
    output logic [AXIS_DATA_WIDTH/8-1:0] wdata_dqm_i,
    input  logic                     wdata_ready,
    input  logic                     resp_valid,
    input  logic                     resp_last,
    input  logic [AXIS_DATA_WIDTH-1:0] resp_data,
    output logic                     resp_ready,

    // System Signals
    input  logic                     clk,
    input  logic                     rstn,
    input  logic                     soft_reset_i, // REFAKTORING (v1.90)

    // Status and Debug ports
    output logic                       stream_timeout_error,
    output logic [$clog2(NUM_BUFFERS+1)-1:0] active_reads,
    output logic [$clog2(NUM_BUFFERS+1)-1:0] active_writes,
    // REFAKTORING (v1.90): Nové ladiace porty
    output logic [$clog2(PIPELINE_BUFFER_SIZE+1)-1:0] debug_pipeline_level_o,
    output logic [$clog2(CMD_FIFO_DEPTH)-1:0]         debug_cmd_fifo_level_o,
    output logic [BUFFERS_ADDR_WIDTH-1:0]             debug_write_ptr_o,
    output logic [BUFFERS_ADDR_WIDTH-1:0]             debug_read_ptr_o
);

    import sdram_pkg::*;

    localparam integer BUFFERS_ADDR_WIDTH = $clog2(NUM_BUFFERS);
    localparam integer PIPELINE_BUFFER_SIZE = PIPELINE_DEPTH_BURSTS * BURST_LEN;
    localparam integer PIPELINE_ADDR_WIDTH = $clog2(PIPELINE_BUFFER_SIZE);
    localparam integer PIPELINE_WRITE_THRESHOLD_WORDS = PIPELINE_WRITE_THRESHOLD_BURSTS * BURST_LEN;
    localparam integer WORDS_PER_BURST = BURST_LEN;

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
    logic [$clog2(SEGMENT_LEN_WORDS+1)-1:0] segment_actual_len_words [0:NUM_BUFFERS-1];
    logic write_frame_finished;
    logic [BUFFERS_ADDR_WIDTH-1:0] last_write_ptr_for_frame;

    // --- Hlboký Pipelined Burst Buffer ---
    logic [AXIS_DATA_WIDTH-1:0] w_pipeline_buffer [0:PIPELINE_BUFFER_SIZE-1];
    logic [PIPELINE_ADDR_WIDTH-1:0] w_pipeline_wptr, w_pipeline_rptr;
    logic [$clog2(PIPELINE_BUFFER_SIZE+1)-1:0] w_pipeline_level;

    // Počítadlá
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] write_segment_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS/BURST_LEN)-1:0] write_segment_burst_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] read_segment_word_count;

    // Riadiace signály
    logic issue_write_cmd, issue_read_cmd;
    logic internal_reset;

    // Watchdog časovač pre stream
    logic [$clog2(STREAM_TIMEOUT_CYCLES)-1:0] timeout_counter;
    logic timeout_active;

    // Debug counters
    logic [$clog2(NUM_BUFFERS+1)-1:0] dbg_active_reads, dbg_active_writes;

    // --- Sekvenčná Logika ---
    always_ff @(posedge clk) begin
        // Kombinovaný reset (externý hardvérový, softvérový alebo interný z timeoutu)
        if (!rstn || internal_reset || soft_reset_i) begin
            for (int i = 0; i < NUM_BUFFERS; i++) begin
                buffer_state[i] <= EMPTY;
                read_cmd_issued[i] <= 1'b0;
                segment_actual_len_words[i] <= '0;
            end
            write_ptr <= '0; read_ptr <= '0;
            write_segment_word_count <= '0; write_segment_burst_count <= '0;
            read_segment_word_count <= '0;
            w_pipeline_wptr <= '0; w_pipeline_rptr <= '0; w_pipeline_level <= '0';
            write_frame_finished <= 1'b0; last_write_ptr_for_frame <= '0;
            timeout_active <= 1'b0;
            timeout_counter <= '0;
            dbg_active_reads <= '0; dbg_active_writes <= '0;
        end else begin
            logic word_accepted = s_axis_tready && s_axis_tvalid;

            // --- Logika Timeout časovača ---
            if (s_axis_tuser_sof && word_accepted) begin
                timeout_active <= 1'b1;
                timeout_counter <= STREAM_TIMEOUT_CYCLES - 1;
            end else if (timeout_active) begin
                if (word_accepted) begin
                    timeout_counter <= STREAM_TIMEOUT_CYCLES - 1;
                end else begin
                    timeout_counter <= timeout_counter - 1;
                end
                if (s_axis_tlast && word_accepted) begin
                    timeout_active <= 1'b0;
                end
            end

            // --- Logika prijímania dát a uzatvárania segmentov ---
            logic close_write_segment = word_accepted && (s_axis_tlast || (write_segment_word_count == SEGMENT_LEN_WORDS - 1));

            if (word_accepted) begin
                `ifndef SYNTHESIS
                assert(buffer_state[write_ptr] == EMPTY || buffer_state[write_ptr] == FILLING)
                else $error("AXI Wrapper FATAL: Pokus o zápis do neprázdneho buffera! Stav: %s", buffer_state[write_ptr].name());
                `endif
                write_segment_word_count <= write_segment_word_count + 1;
            end

            if (buffer_state[write_ptr] == EMPTY && word_accepted) begin
                buffer_state[write_ptr] <= FILLING;
            end

            if (buffer_state[write_ptr] == FILLING && close_write_segment) begin
                buffer_state[write_ptr] <= FULL;
                segment_actual_len_words[write_ptr] <= write_segment_word_count + 1;
                if (s_axis_tlast) begin
                    write_frame_finished <= 1'b1;
                    last_write_ptr_for_frame <= write_ptr;
                end
            end

            logic is_last_write_burst = (issue_write_cmd && cmd_fifo_ready &&
                                        (write_segment_burst_count == (segment_actual_len_words[write_ptr] + WORDS_PER_BURST - 1) / WORDS_PER_BURST - 1));

            if (buffer_state[write_ptr] == FULL && is_last_write_burst) begin
                write_ptr <= write_ptr + 1;
                write_segment_burst_count <= '0;
                write_segment_word_count <= '0;
            end

            // --- Logika čítacej cesty ---
            logic last_word_of_read_segment = m_axis_tvalid && m_axis_tready && (read_segment_word_count == segment_actual_len_words[read_ptr] - 1);

            if (buffer_state[read_ptr] == FULL && read_cmd_issued[read_ptr])
                buffer_state[read_ptr] <= READING;

            if (buffer_state[read_ptr] == READING && last_word_of_read_segment) begin
                buffer_state[read_ptr] <= EMPTY;
                read_cmd_issued[read_ptr] <= 1'b0;
                read_ptr <= read_ptr + 1;
                read_segment_word_count <= '0;
            end

            if (issue_read_cmd && cmd_fifo_ready)
                read_cmd_issued[read_ptr] <= 1'b1;

            // --- Pipeline buffer a počítadlá ---
            if (word_accepted) begin
                w_pipeline_buffer[w_pipeline_wptr] <= s_axis_tdata;
                w_pipeline_wptr <= w_pipeline_wptr + 1;
            end
            if (wdata_valid && wdata_ready) w_pipeline_rptr <= w_pipeline_rptr + 1;
            w_pipeline_level <= w_pipeline_level + word_accepted - (wdata_valid && wdata_ready);

            if (issue_write_cmd && cmd_fifo_ready) write_segment_burst_count <= write_segment_burst_count + 1;
            if (m_axis_tvalid && m_axis_tready) read_segment_word_count <= read_segment_word_count + 1;

            // --- Debug counters ---
            dbg_active_reads <= $countones(read_cmd_issued);
            dbg_active_writes <= $countones({buffer_state[3] inside {FILLING, FULL},
                                             buffer_state[2] inside {FILLING, FULL},
                                             buffer_state[1] inside {FILLING, FULL},
                                             buffer_state[0] inside {FILLING, FULL}});
        end
    end

    // --- Kombinačná Logika ---
    always_comb begin
        logic can_push_to_cmd_fifo;
        logic can_issue_write;
        logic is_last_write_burst_of_segment;
        logic can_issue_read_lookahead;
        logic [BUFFERS_ADDR_WIDTH-1:0] lookahead_ptr;
        logic can_issue_active_read;
        logic is_last_read_burst_of_segment;
        logic is_last_word_of_frame;

        // --- Riadenie Timeoutu a Resetu ---
        stream_timeout_error = timeout_active && (timeout_counter == 0);
        internal_reset = stream_timeout_error; // V budúcnosti sa tu môžu pridať ďalšie podmienky

        s_axis_tready = (buffer_state[write_ptr] == EMPTY || buffer_state[write_ptr] == FILLING) && (w_pipeline_level < PIPELINE_BUFFER_SIZE) && !internal_reset && !soft_reset_i;

        // --- Logika Plánovača Príkazov (Command Scheduler) ---
        can_push_to_cmd_fifo = (cmd_fifo_level_i < CMD_FIFO_DEPTH - CMD_FIFO_THRESHOLD);

        can_issue_write = ((w_pipeline_level >= PIPELINE_WRITE_THRESHOLD_WORDS) || (buffer_state[write_ptr] == FULL && w_pipeline_level > 0)) &&
                          (buffer_state[write_ptr] == FILLING || buffer_state[write_ptr] == FULL);

        is_last_write_burst_of_segment = (write_segment_burst_count == (segment_actual_len_words[write_ptr] + WORDS_PER_BURST - 1) / WORDS_PER_BURST - 1);

        can_issue_read_lookahead = 1'b0;
        lookahead_ptr = '0;
        for (int i = 0; i < NUM_BUFFERS; i++) begin
            logic [BUFFERS_ADDR_WIDTH-1:0] ptr = read_ptr + i;
            if (buffer_state[ptr] == FULL && !read_cmd_issued[ptr]) begin
                can_issue_read_lookahead = 1'b1;
                lookahead_ptr = ptr;
                break;
            end
        end

        can_issue_active_read = (buffer_state[read_ptr] == READING);
        is_last_read_burst_of_segment = (read_segment_word_count >= (segment_actual_len_words[read_ptr] - WORDS_PER_BURST));

        issue_write_cmd = 1'b0; issue_read_cmd = 1'b0;
        cmd_fifo_valid  = 1'b0; cmd_fifo_data   = '{default:'0};

        if (can_push_to_cmd_fifo && !internal_reset && !soft_reset_i) begin
            if (can_issue_read_lookahead) begin
                issue_read_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: BUFFER_BASE_ADDRS[lookahead_ptr], rw: READ_CMD, auto_precharge: 1'b0};
            end else if (can_issue_active_read) begin
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: BUFFER_BASE_ADDRS[read_ptr] + read_segment_word_count, rw: READ_CMD, auto_precharge: is_last_read_burst_of_segment};
            end else if (can_issue_write) begin
                issue_write_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: BUFFER_BASE_ADDRS[write_ptr] + (write_segment_burst_count * WORDS_PER_BURST), rw: WRITE_CMD, auto_precharge: is_last_write_burst_of_segment};
            end
        end

        // --- Dátová cesta (Write a Read) ---
        wdata_valid = (w_pipeline_level > 0) && !internal_reset && !soft_reset_i;
        wdata       = w_pipeline_buffer[w_pipeline_rptr];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid && (buffer_state[read_ptr] == READING) && !internal_reset && !soft_reset_i;
        m_axis_tdata  = resp_data;

        is_last_word_of_frame = write_frame_finished && (read_ptr == last_write_ptr_for_frame) &&
                               (read_segment_word_count == segment_actual_len_words[read_ptr] - 1);
        m_axis_tlast  = m_axis_tvalid && is_last_word_of_frame;
        resp_ready    = m_axis_tready;

        // --- Debug výstupy ---
        active_reads  = dbg_active_reads;
        active_writes = dbg_active_writes;
        debug_pipeline_level_o = w_pipeline_level;
        debug_cmd_fifo_level_o = cmd_fifo_level_i;
        debug_write_ptr_o      = write_ptr;
        debug_read_ptr_o       = read_ptr;
    end

endmodule

`endif

