// AxiStreamSdramWrapper.sv - Verzia 1.1 - Refaktorovaný na základe analýzy
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny:
// 1. Spoľahlivá detekcia `tlast` pomocou interného príznaku `write_packet_done`.
// 2. Korektná inkrementácia adresy aj počas zápisu.
// 3. `BURST_LEN` je teraz parameter modulu pre vyššiu flexibilitu.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer PACKET_LEN_WORDS  = 1024,
    parameter integer BURST_LEN         = 8, // ZMENA (v1.1): Z `localparam` na `parameter`
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

    // Kontrola, či je dĺžka paketu násobkom dĺžky burstu
    initial begin
        if (PACKET_LEN_WORDS % BURST_LEN != 0) begin
            $fatal(1, "FATAL: PACKET_LEN_WORDS musí byť násobkom BURST_LEN (%0d)", BURST_LEN);
        end
    end

    typedef enum logic [2:0] {
        IDLE,
        WRITE_FILL_BUFFER,
        WRITE_ISSUE_CMD,
        WRITE_SEND_BURST,
        READ_ISSUE_CMD,
        READ_STREAM_DATA
    } state_t;

    state_t state, next_state;

    logic [SDRAM_ADDR_WIDTH-1:0] addr_reg;
    logic [$clog2(PACKET_LEN_WORDS)-1:0] word_count;
    logic write_packet_done; // PRIDANÉ (v1.1): Flag pre spoľahlivú detekciu konca paketu
    
    // Malý buffer na dáta z AXI-Stream pre vytvorenie SDRAM burstu
    logic [AXIS_DATA_WIDTH-1:0] w_data_buffer [0:BURST_LEN-1];
    logic [$clog2(BURST_LEN+1)-1:0] w_buffer_fill_count;
    logic [$clog2(BURST_LEN)-1:0]   w_burst_sent_count;

    // --- Stavový automat (sekvenčná časť) ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            addr_reg <= SDRAM_BASE_ADDR;
            word_count <= '0;
            w_buffer_fill_count <= '0;
            w_burst_sent_count <= '0;
            write_packet_done <= 1'b0;
        end else begin
            state <= next_state;

            // Aktualizácia registrov na základe stavu
            case (state)
                WRITE_FILL_BUFFER: begin
                    if (s_axis_tready && s_axis_tvalid) begin
                        w_buffer_fill_count <= w_buffer_fill_count + 1;
                        if (s_axis_tlast) begin
                            write_packet_done <= 1'b1; // Zaznamenáme koniec paketu
                        end
                    end
                end
                WRITE_ISSUE_CMD: begin
                    if (cmd_fifo_ready) begin
                        w_buffer_fill_count <= 0; // Buffer sa ide posielať, resetujeme počítadlo
                    end
                end
                WRITE_SEND_BURST: begin
                    if (wdata_ready) begin
                        w_burst_sent_count <= w_burst_sent_count + 1;
                        // ZMENA (v1.1): Inkrementácia adresy aj počas zápisu
                        if (w_burst_sent_count == BURST_LEN - 1) begin
                            addr_reg <= addr_reg + BURST_LEN;
                        end
                    end
                end
                READ_ISSUE_CMD: begin
                    if (cmd_fifo_ready) begin
                        word_count <= word_count + BURST_LEN;
                        addr_reg <= addr_reg + BURST_LEN;
                    end
                end
                READ_STREAM_DATA: begin
                    if (resp_valid && resp_ready && resp_last) begin
                        if (word_count == PACKET_LEN_WORDS) begin
                            // Koniec čítania paketu, ideme odznova
                            addr_reg <= SDRAM_BASE_ADDR;
                            word_count <= 0;
                            write_packet_done <= 1'b0; // Reset flagu pre ďalší paket
                        end
                    end
                end
                default: begin
                    // reset počítadiel v IDLE
                    addr_reg <= SDRAM_BASE_ADDR;
                    word_count <= 0;
                    w_buffer_fill_count <= 0;
                    w_burst_sent_count <= 0;
                    write_packet_done <= 1'b0;
                end
            endcase
        end
    end

    // --- Stavový automat (kombinačná časť) ---
    always_comb begin
        next_state = state;

        // Predvolené hodnoty výstupov
        s_axis_tready = 1'b0;
        cmd_fifo_valid = 1'b0;
        cmd_fifo_data = '{default:'0};
        wdata_valid = 1'b0;
        wdata = '0;
        wdata_dqm_i = '0;

        m_axis_tvalid = 1'b0;
        m_axis_tdata = resp_data; // Priame prepojenie
        m_axis_tlast = 1'b0;
        resp_ready = m_axis_tready; // Priame prepojenie pre backpressure

        case (state)
            IDLE: begin
                // Začíname zápisom nového paketu
                next_state = WRITE_FILL_BUFFER;
            end

            WRITE_FILL_BUFFER: begin
                // Sme pripravení prijímať, kým sa nenaplní burst buffer
                s_axis_tready = (w_buffer_fill_count < BURST_LEN);
                if (s_axis_tvalid && (w_buffer_fill_count == BURST_LEN - 1)) begin
                    next_state = WRITE_ISSUE_CMD;
                end
            end

            WRITE_ISSUE_CMD: begin
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data = '{addr: addr_reg, rw: WRITE_CMD};
                if (cmd_fifo_ready) begin
                    next_state = WRITE_SEND_BURST;
                end
            end

            WRITE_SEND_BURST: begin
                wdata_valid = 1'b1;
                wdata = w_data_buffer[w_burst_sent_count];
                if (wdata_ready && (w_burst_sent_count == BURST_LEN - 1)) begin
                    // ZMENA (v1.1): Použitie spoľahlivého flagu `write_packet_done`
                    if (write_packet_done) begin
                        // Koniec zápisu celého paketu, prejdeme na čítanie
                        next_state = READ_ISSUE_CMD;
                    end else begin
                        // Pokračujeme v plnení buffera pre ďalší burst
                        next_state = WRITE_FILL_BUFFER;
                    end
                end
            end
            
            READ_ISSUE_CMD: begin
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data = '{addr: addr_reg, rw: READ_CMD};
                if (cmd_fifo_ready) begin
                    next_state = READ_STREAM_DATA;
                end
            end

            READ_STREAM_DATA: begin
                m_axis_tvalid = resp_valid;
                if (resp_valid && resp_last) begin
                    if (word_count == PACKET_LEN_WORDS) begin
                        // Posledný burst paketu
                        m_axis_tlast = 1'b1;
                        if (resp_ready) begin // Počkáme na odoslanie posledného slova
                           next_state = WRITE_FILL_BUFFER; // Cyklus odznova
                        end
                    end else begin
                        if (resp_ready) begin
                            next_state = READ_ISSUE_CMD;
                        end
                    end
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // --- Logika pre plnenie interného buffera ---
    always_ff @(posedge clk) begin
        if (state == WRITE_FILL_BUFFER && s_axis_tready && s_axis_tvalid) begin
            w_data_buffer[w_buffer_fill_count] <= s_axis_tdata;
        end
    end

endmodule

`endif

