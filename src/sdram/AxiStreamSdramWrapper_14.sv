// AxiStreamSdramWrapper.sv - Verzia 1.4 - Pipelined (Streaming) Architecture
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny:
// 1. ARCHITEKTÚRA: Kompletný refaktoring na "burst-wise pipelining". Modul teraz
//    zapisuje a číta dáta v malých dávkach (burstoch) súčasne, čím sa
//    výrazne znižuje latencia (z celého paketu na jeden burst).
// 2. FSM: Nový stavový automat riadi tri fázy: STREAMING, DRAINING a IDLE.
// 3. SYNCHRONIZÁCIA: Pridané nezávislé ukazovatele pre zápis (`write_addr_reg`) a
//    čítanie (`read_addr_reg`) a synchronizačný čítač (`bursts_in_flight_count`),
//    ktorý sleduje, koľko burstov je zapísaných a pripravených na čítanie.
// 4. EFEKTIVITA: Nároky na interný buffer sú konštantné a nezávisia od veľkosti paketu.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
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

    // Systémové signály
    input  logic                     clk,
    input  logic                     rstn
);

    import sdram_pkg::*;

    initial begin
        if (PACKET_LEN_WORDS % BURST_LEN != 0) begin
            $fatal(1, "FATAL: PACKET_LEN_WORDS musí byť násobkom BURST_LEN (%0d)", BURST_LEN);
        end
    end

    typedef enum logic [1:0] {
        IDLE,
        STREAMING,
        DRAINING
    } state_t;

    state_t state, next_state;

    // Nezávislé ukazovatele pre zápis a čítanie
    logic [SDRAM_ADDR_WIDTH-1:0] write_addr_reg, read_addr_reg;
    
    // Synchronizačný čítač - koľko burstov je zapísaných a čaká na prečítanie
    logic [$clog2(PACKET_LEN_WORDS/BURST_LEN + 1)-1:0] bursts_in_flight_count;

    // Čítač pre generovanie m_axis_tlast
    logic [$clog2(PACKET_LEN_WORDS)-1:0] words_sent_count;

    // Interný buffer pre jeden burst
    logic [AXIS_DATA_WIDTH-1:0] w_data_buffer [0:BURST_LEN-1];
    logic [$clog2(BURST_LEN+1)-1:0] w_buffer_fill_count;
    logic [$clog2(BURST_LEN)-1:0]   w_burst_sent_count;
    
    // Príznaky pre riadenie FSM
    logic write_buffer_full;
    logic issue_write_cmd_pulse, issue_read_cmd_pulse;
    logic last_write_burst_sent;
    logic packet_end_detected;

    // --- Sekvenčná logika ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            write_addr_reg <= SDRAM_BASE_ADDR;
            read_addr_reg  <= SDRAM_BASE_ADDR;
            bursts_in_flight_count <= '0;
            words_sent_count <= '0;
            w_buffer_fill_count <= '0;
            w_burst_sent_count <= '0;
            packet_end_detected <= 1'b0;
        end else begin
            state <= next_state;

            // Čítač naplnenia burst buffera
            if (s_axis_tready && s_axis_tvalid) begin
                w_buffer_fill_count <= w_buffer_fill_count + 1;
            end else if (issue_write_cmd_pulse) begin
                w_buffer_fill_count <= 0;
            end

            // Detekcia konca paketu
            if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
                packet_end_detected <= 1'b1;
            end

            // Odosielanie burstu
            if (issue_write_cmd_pulse) begin
                w_burst_sent_count <= 0;
            end else if (wdata_valid && wdata_ready) begin
                w_burst_sent_count <= w_burst_sent_count + 1;
            end

            // Synchronizačný čítač
            if (last_write_burst_sent && !issue_read_cmd_pulse) begin
                bursts_in_flight_count <= bursts_in_flight_count + 1;
            end else if (!last_write_burst_sent && issue_read_cmd_pulse) begin
                bursts_in_flight_count <= bursts_in_flight_count - 1;
            end else if (last_write_burst_sent && issue_read_cmd_pulse) begin
                // Zápis a čítanie v rovnakom cykle, počítadlo sa nemení
            end

            // Adresné registre
            if (issue_write_cmd_pulse) write_addr_reg <= write_addr_reg + BURST_LEN;
            if (issue_read_cmd_pulse)  read_addr_reg  <= read_addr_reg + BURST_LEN;

            // Čítač odoslaných slov
            if (m_axis_tvalid && m_axis_tready) begin
                words_sent_count <= words_sent_count + 1;
            end
            
            // Reset v IDLE
            if (next_state == IDLE) begin
                write_addr_reg <= SDRAM_BASE_ADDR;
                read_addr_reg  <= SDRAM_BASE_ADDR;
                bursts_in_flight_count <= '0;
                words_sent_count <= '0;
                packet_end_detected <= 1'b0;
                w_buffer_fill_count <= 0;
            end
        end
    end

    // --- Kombinačná logika ---
    always_comb begin
        next_state = state;

        // Riadenie príkazov a dát
        logic can_issue_write, can_issue_read;
        
        write_buffer_full = (w_buffer_fill_count == BURST_LEN);
        
        can_issue_write = write_buffer_full && !packet_end_detected;
        can_issue_read = (bursts_in_flight_count > 0);

        issue_write_cmd_pulse = 1'b0;
        issue_read_cmd_pulse = 1'b0;
        
        cmd_fifo_valid = 1'b0;
        cmd_fifo_data = '{default:'0};

        // Arbitrácia prístupu k command FIFO (priorita pre čítanie)
        if (cmd_fifo_ready) begin
            if (can_issue_read) begin
                issue_read_cmd_pulse = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data = '{addr: read_addr_reg, rw: READ_CMD};
            end else if (can_issue_write) begin
                issue_write_cmd_pulse = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data = '{addr: write_addr_reg, rw: WRITE_CMD};
            end
        end
        
        s_axis_tready = !write_buffer_full && !packet_end_detected && (state == STREAMING);
        
        wdata_valid = (w_burst_sent_count > 0) || (issue_write_cmd_pulse && cmd_fifo_ready);
        wdata = w_data_buffer[w_burst_sent_count];
        wdata_dqm_i = '0;
        last_write_burst_sent = wdata_valid && wdata_ready && (w_burst_sent_count == BURST_LEN - 1);
        
        m_axis_tvalid = resp_valid;
        m_axis_tdata = resp_data;
        m_axis_tlast = m_axis_tvalid && (words_sent_count == PACKET_LEN_WORDS - 1);
        resp_ready = m_axis_tready;

        // FSM prechody
        case (state)
            IDLE: begin
                if (s_axis_tvalid) begin
                    next_state = STREAMING;
                end
            end
            STREAMING: begin
                if (packet_end_detected) begin
                    next_state = DRAINING;
                end
            end
            DRAINING: begin
                // Po odoslaní posledného slova a vyprázdnení pipeline sa vrátime do IDLE
                if (m_axis_tlast && m_axis_tready) begin
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // --- Logika pre plnenie interného buffera ---
    always_ff @(posedge clk) begin
        if (s_axis_tready && s_axis_tvalid) begin
            w_data_buffer[w_buffer_fill_count] <= s_axis_tdata;
        end
    end

endmodule

`endif

