// AxiStreamSdramWrapper.sv - Verzia 1.7 - Multi-Buffering Architecture
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny:
// 1. ARCHITEKTÚRA: Refaktoring na plne parametrizovateľný "multi-buffering".
//    Počet bufferov (NUM_BUFFERS) je teraz možné konfigurovať, čo umožňuje
//    škálovanie výkonu podľa požiadaviek aplikácie (napr. triple, quad buffering).
// 2. SCHEDULER: Pôvodný prioritný enkodér bol nahradený robustným "round-robin"
//    schedulerom, ktorý spravodlivo prideľuje voľné a plné buffery, čím sa
//    predchádza zbytočnému opotrebovaniu jednej pamäťovej oblasti.
// 3. EFEKTIVITA: Architektúra je optimalizovaná pre maximálnu priepustnosť
//    a minimálnu latenciu vďaka plnému oddeleniu zápisových a čítacích operácií.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer PACKET_LEN_WORDS  = 1024,
    parameter integer BURST_LEN         = 8,
    parameter integer NUM_BUFFERS       = 3, // PRIDANÉ (v1.7): Konfigurovateľný počet bufferov
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

    // Systémové signály
    input  logic                     clk,
    input  logic                     rstn
);

    import sdram_pkg::*;

    initial begin
        if (PACKET_LEN_WORDS % BURST_LEN != 0) begin
            $fatal(1, "FATAL: PACKET_LEN_WORDS musí byť násobkom BURST_LEN (%0d)", BURST_LEN);
        end
        if (SDRAM_BASE_ADDR + (NUM_BUFFERS * PACKET_LEN_WORDS) > (1 << SDRAM_ADDR_WIDTH)) begin
            $fatal(1, "FATAL: Nedostatok adresného priestoru v SDRAM pre %0d buffery.", NUM_BUFFERS);
        end
    end

    // --- Stavové registre pre Buffery ---
    typedef enum logic [1:0] { EMPTY, FILLING, FULL, READING } buffer_state_t;
    buffer_state_t buffer_state [0:NUM_BUFFERS-1];

    logic [$clog2(NUM_BUFFERS)-1:0] write_buf_idx;
    logic [$clog2(NUM_BUFFERS)-1:0] read_buf_idx;

    // --- Stavové registre pre Zápisovú cestu ---
    logic [SDRAM_ADDR_WIDTH-1:0] write_addr_offset;
    logic writing_active;

    // --- Stavové registre pre Čítaciu cestu ---
    logic [SDRAM_ADDR_WIDTH-1:0] read_addr_offset;
    logic [$clog2(PACKET_LEN_WORDS)-1:0] read_words_sent_count;
    logic reading_active;

    // --- Buffer pre jeden burst (zápis) ---
    logic [AXIS_DATA_WIDTH-1:0] w_data_buffer [0:BURST_LEN-1];
    logic [$clog2(BURST_LEN+1)-1:0] w_buffer_fill_count;
    logic [$clog2(BURST_LEN)-1:0]   w_burst_sent_count;

    // --- Riadiace signály ---
    logic issue_write_cmd, issue_read_cmd;
    logic next_empty_buf_valid;
    logic [$clog2(NUM_BUFFERS)-1:0] next_empty_buf_idx;
    logic next_full_buf_valid;
    logic [$clog2(NUM_BUFFERS)-1:0] next_full_buf_idx;
    
    // Ukazovatele pre Round-Robin scheduler
    logic [$clog2(NUM_BUFFERS)-1:0] find_empty_start_idx;
    logic [$clog2(NUM_BUFFERS)-1:0] find_full_start_idx;

    // --- Sekvenčná logika ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            // Počiatočný stav: Všetky buffery sú prázdne
            for (int i = 0; i < NUM_BUFFERS; i++) begin
                buffer_state[i] <= EMPTY;
            end

            write_buf_idx <= '0;
            writing_active <= 1'b0;
            write_addr_offset <= '0;

            read_buf_idx <= '0;
            reading_active <= 1'b0;
            read_addr_offset <= '0;
            read_words_sent_count <= '0;

            w_buffer_fill_count <= '0;
            w_burst_sent_count <= '0;
            
            find_empty_start_idx <= '0;
            find_full_start_idx  <= '0;
        end else begin
            // --- Zápisová logika ---
            if (!writing_active && next_empty_buf_valid) begin
                writing_active <= 1'b1;
                write_buf_idx  <= next_empty_buf_idx;
                buffer_state[next_empty_buf_idx] <= FILLING;
                write_addr_offset <= '0;
                find_empty_start_idx <= next_empty_buf_idx + 1; // Posun štartu pre ďalšie hľadanie
            end

            if (writing_active) begin
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
                    writing_active <= 1'b0;
                    buffer_state[write_buf_idx] <= FULL;
                end
            end

            // --- Čítacia logika ---
            if (!reading_active && next_full_buf_valid) begin
                reading_active <= 1'b1;
                read_buf_idx <= next_full_buf_idx;
                buffer_state[next_full_buf_idx] <= READING;
                read_addr_offset <= '0;
                read_words_sent_count <= '0;
                find_full_start_idx <= next_full_buf_idx + 1; // Posun štartu pre ďalšie hľadanie
            end

            if (reading_active) begin
                if (issue_read_cmd) begin
                    read_addr_offset <= read_addr_offset + BURST_LEN;
                end
                if (m_axis_tvalid && m_axis_tready) begin
                    read_words_sent_count <= read_words_sent_count + 1;
                end
                
                if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                    reading_active <= 1'b0;
                    buffer_state[read_buf_idx] <= EMPTY;
                end
            end
        end
    end
    
    // --- Kombinačná logika ---
    // Round-Robin scheduler pre hľadanie voľného/plného buffera
    always_comb begin
        next_empty_buf_valid = 1'b0;
        next_empty_buf_idx = '0;
        next_full_buf_valid = 1'b0;
        next_full_buf_idx = '0;
        
        for (int i = 0; i < NUM_BUFFERS; i++) begin
            logic [$clog2(NUM_BUFFERS)-1:0] empty_idx = find_empty_start_idx + i;
            if (buffer_state[empty_idx] == EMPTY) begin
                next_empty_buf_valid = 1'b1;
                next_empty_buf_idx = empty_idx;
                break;
            end
        end

        for (int i = 0; i < NUM_BUFFERS; i++) begin
            logic [$clog2(NUM_BUFFERS)-1:0] full_idx = find_full_start_idx + i;
            if (buffer_state[full_idx] == FULL) begin
                next_full_buf_valid = 1'b1;
                next_full_buf_idx = full_idx;
                break;
            end
        end
    end

    always_comb begin
        logic can_issue_write, can_issue_read;
        logic [SDRAM_ADDR_WIDTH-1:0] current_write_base, current_read_base;

        current_write_base = SDRAM_BASE_ADDR + (write_buf_idx * PACKET_LEN_WORDS);
        current_read_base  = SDRAM_BASE_ADDR + (read_buf_idx  * PACKET_LEN_WORDS);
        
        s_axis_tready = writing_active && (w_buffer_fill_count < BURST_LEN);
        can_issue_write = writing_active && (w_buffer_fill_count == BURST_LEN);
        can_issue_read = reading_active && (read_addr_offset < PACKET_LEN_WORDS);

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
        
        m_axis_tvalid = resp_valid && reading_active;
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

