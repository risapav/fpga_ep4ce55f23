// AxiStreamSdramWrapper.sv - Verzia 1.52 - Pipelined Double Buffering Architecture
// Modul, ktorý slúži ako most medzi AXI-Stream rozhraním a SDRAM kontrolérom.
// Zmeny (v1.52):
// 1. ARCHITEKTÚRA: Kompletný refaktoring na "Pipelined Double Buffering".
//    Double buffering sa teraz aplikuje na úrovni menších "segmentov", nie celých
//    paketov. Umožňuje to súčasný zápis a čítanie RÔZNYCH ČASTÍ toho istého
//    veľkého paketu (napr. video snímky).
// 2. VÝKON: Architektúra teraz funguje ako skutočný pipelined DMA engine, ktorý
//    maximalizuje priepustnosť SDRAM zbernice pri streamovaní veľkých paketov.
// 3. RIADENIE: Riadiaca logika bola rozšírená na dve úrovne: sleduje dokončenie
//    segmentov pre rýchly "swap" bufferov a zároveň sleduje celkový priebeh
//    paketu pre správne riadenie AXI-Stream `tlast` signálov.

`ifndef AXISTREAM_SDRAM_WRAPPER_SV
`define AXISTREAM_SDRAM_WRAPPER_SV

(* default_nettype = "none" *)

module AxiStreamSdramWrapper #(
    parameter integer AXIS_DATA_WIDTH   = 16,
    parameter integer SDRAM_ADDR_WIDTH  = 24,
    parameter integer PACKET_LEN_WORDS  = 8192, // Celková veľkosť paketu (napr. frame)
    parameter integer SEGMENT_LEN_WORDS = 1024, // VYLEPŠENIE: Veľkosť segmentu pre pipelining
    parameter integer BURST_LEN         = 8,
    parameter logic [SDRAM_ADDR_WIDTH-1:0] SDRAM_BASE_ADDR = 24'h0
) (
    // AXI-Stream Slave Interface (s_axis)
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,

    // AXI-Stream Master Interface (m_axis)
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

    // --- Segmentové Double Buffering Parametre ---
    localparam logic [SDRAM_ADDR_WIDTH-1:0] BUFFER0_BASE_ADDR = SDRAM_BASE_ADDR;
    localparam logic [SDRAM_ADDR_WIDTH-1:0] BUFFER1_BASE_ADDR = SDRAM_BASE_ADDR + SEGMENT_LEN_WORDS;

    initial begin
        if (SEGMENT_LEN_WORDS % BURST_LEN != 0)
            $fatal(1, "FATAL: SEGMENT_LEN_WORDS musí byť násobkom BURST_LEN.");
        if (PACKET_LEN_WORDS % SEGMENT_LEN_WORDS != 0)
            $fatal(1, "FATAL: PACKET_LEN_WORDS musí byť násobkom SEGMENT_LEN_WORDS.");
    end

    // --- Stavové registre pre Double Buffering ---
    logic write_buf_sel;
    logic read_buf_sel;
    logic buffer_ready_to_read[0:1];

    // --- Stavové registre pre ZÁPIS ---
    logic [$clog2(PACKET_LEN_WORDS)-1:0]  write_frame_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] write_segment_word_count;
    logic [SDRAM_ADDR_WIDTH-1:0]          write_segment_addr_offset;
    logic write_segment_done;
    logic write_frame_done; // Prijímanie celého frame je hotové

    // --- Stavové registre pre ČÍTANIE ---
    logic [$clog2(PACKET_LEN_WORDS)-1:0]  read_frame_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] read_segment_word_count;
    logic [SDRAM_ADDR_WIDTH-1:0]          read_segment_addr_offset;
    logic read_segment_done;
    logic read_frame_done; // Odosielanie celého frame je hotové

    // --- Interný Burst Buffer (zápis) ---
    logic [AXIS_DATA_WIDTH-1:0] w_data_buffer [0:BURST_LEN-1];
    logic [$clog2(BURST_LEN+1)-1:0] w_buffer_fill_count;
    logic [$clog2(BURST_LEN)-1:0]   w_burst_sent_count;

    // --- Riadiace signály ---
    logic issue_write_cmd, issue_read_cmd;
    logic do_swap;

    // --- Sekvenčná logika (plne synchrónny reset) ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            write_buf_sel <= 1'b0;
            read_buf_sel  <= 1'b1;
            buffer_ready_to_read[0] <= 1'b0;
            buffer_ready_to_read[1] <= 1'b0;

            write_frame_word_count <= '0;
            write_segment_word_count <= '0;
            write_segment_addr_offset <= '0;
            write_segment_done <= 1'b0;
            write_frame_done <= 1'b0;

            read_frame_word_count <= '0;
            read_segment_word_count <= '0;
            read_segment_addr_offset <= '0;
            read_segment_done <= 1'b1; // Pripravený na prvý swap
            read_frame_done <= 1'b1; // Žiadny frame sa nečíta

            w_buffer_fill_count <= '0;
            w_burst_sent_count <= '0;
        end else begin
            // --- Logika pre výmenu ("swap") bufferov na úrovni segmentov ---
            if (do_swap) begin
                write_buf_sel <= ~write_buf_sel;
                read_buf_sel  <= ~read_buf_sel;

                buffer_ready_to_read[write_buf_sel] <= 1'b1;
                buffer_ready_to_read[read_buf_sel]  <= 1'b0;

                write_segment_done <= 1'b0;
                write_segment_word_count <= '0;
                write_segment_addr_offset <= '0;

                read_segment_done <= 1'b0;
                read_segment_word_count <= '0;
                read_segment_addr_offset <= '0;
            end

            // --- Logika pre reset stavu po dokončení celého frame ---
            if(write_frame_done && read_frame_done) begin
                 write_frame_done <= 1'b0;
                 write_frame_word_count <= '0;
                 read_frame_done <= 1'b0;
                 read_frame_word_count <= '0;
            end

            // --- Zápisová logika ---
            if (!write_frame_done) begin
                if (s_axis_tready && s_axis_tvalid) begin
                    write_frame_word_count <= write_frame_word_count + 1;
                    write_segment_word_count <= write_segment_word_count + 1;
                    w_buffer_fill_count <= w_buffer_fill_count + 1;
                end else if (issue_write_cmd && cmd_fifo_ready) begin
                    w_buffer_fill_count <= 0;
                end

                if (issue_write_cmd && cmd_fifo_ready) begin
                    w_burst_sent_count <= BURST_LEN;
                    write_segment_addr_offset <= write_segment_addr_offset + BURST_LEN;
                end else if (wdata_valid && wdata_ready) begin
                    w_burst_sent_count <= w_burst_sent_count - 1;
                end

                if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
                    write_frame_done <= 1'b1;
                end
            end

            // --- Čítacia logika ---
            if (buffer_ready_to_read[read_buf_sel] && !read_segment_done) begin
                if (issue_read_cmd && cmd_fifo_ready) begin
                    read_segment_addr_offset <= read_segment_addr_offset + BURST_LEN;
                end
                if (m_axis_tvalid && m_axis_tready) begin
                    read_frame_word_count <= read_frame_word_count + 1;
                    read_segment_word_count <= read_segment_word_count + 1;
                end
            end
        end
    end

    // --- Kombinačná logika ---
    always_comb begin
        logic [SDRAM_ADDR_WIDTH-1:0] current_write_base, current_read_base;

        current_write_base = (write_buf_sel == 0) ? BUFFER0_BASE_ADDR : BUFFER1_BASE_ADDR;
        current_read_base  = (read_buf_sel  == 0) ? BUFFER0_BASE_ADDR : BUFFER1_BASE_ADDR;

        // Prijímame dáta, pokiaľ nebol prijatý celý frame a zároveň je priestor na zápis (buffer nie je pripravený na swap)
        s_axis_tready = !write_frame_done && !write_segment_done;

        // Príznak dokončenia zápisu segmentu (keď sa naplní)
        write_segment_done = (write_segment_word_count == SEGMENT_LEN_WORDS);
        // Príznak dokončenia čítania segmentu (keď sa prečíta)
        read_segment_done  = (read_segment_word_count == SEGMENT_LEN_WORDS);
        // Príznak dokončenia čítania celého frame
        read_frame_done = (read_frame_word_count == PACKET_LEN_WORDS);

        // Podmienka na prepnutie bufferov
        do_swap = write_segment_done && read_segment_done;

        // Podmienky pre vydanie príkazov do SDRAM kontroléra
        logic can_issue_write = (w_buffer_fill_count == BURST_LEN) && !write_segment_done;
        logic can_issue_read  = buffer_ready_to_read[read_buf_sel] && !read_segment_done;

        issue_write_cmd = 1'b0;
        issue_read_cmd  = 1'b0;
        cmd_fifo_valid  = 1'b0;
        cmd_fifo_data   = '{default:'0};

        // Arbitrácia prístupu (čítanie má prioritu pre plynulý výstup)
        if (cmd_fifo_ready) begin
            if (can_issue_read) begin
                issue_read_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data  = '{addr: current_read_base + read_segment_addr_offset, rw: READ_CMD, auto_precharge: 1'b0};
            end else if (can_issue_write) begin
                issue_write_cmd = 1'b1;
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data   = '{addr: current_write_base + write_segment_addr_offset, rw: WRITE_CMD, auto_precharge: 1'b0};
            end
        end

        // Výstupy
        wdata_valid = (w_burst_sent_count > 0);
        wdata       = w_data_buffer[BURST_LEN - w_burst_sent_count];
        wdata_dqm_i = '0;

        m_axis_tvalid = resp_valid;
        m_axis_tdata  = resp_data;
        m_axis_tlast  = m_axis_tvalid && (read_frame_word_count == PACKET_LEN_WORDS - 1);
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
