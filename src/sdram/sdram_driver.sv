// sdram_driver.sv - Refaktorovaná verzia 3.2 (produkčná kvalita)
//
// Verzia 3.2 - Architektonické vylepšenia a finálne čistenie
//
// Kľúčové zmeny:
// 1. VYLEPŠENIE (Architektúra): Modul teraz prijíma dva oddelené, synchronizované
//    resety (`rstn_axi`, `rstn_sdram`), jeden pre každú hodinovú doménu.
//    Toto je "best practice" pre znovupoužiteľné IP bloky.
// 2. OPRAVA (Logika): Odstránené nadbytočné a chybné priradenie pre `read_data_fifo_din`.
// 3. VYLEPŠENIE (Čitateľnosť): AXI FSM pre zápis bol refaktorovaný do štandardnej
//    dvoj-procesovej formy pre maximálnu prehľadnosť a robustnosť.
//
// Author: refactor by assistant

`include "sdram_pkg.sv"

(* default_nettype = "none" *)

module SdramDriver #(
    parameter ADDR_WIDTH = 24,
    parameter DATA_WIDTH = 16,
    parameter BURST_LENGTH = 8,
    // SDRAM timing parameters (passthrough to controller)
    parameter int tRP        = 3,
    parameter int tRCD       = 3,
    parameter int tWR        = 3,
    parameter int tRFC       = 9,
    parameter int CAS_LATENCY= 3,
    parameter int NUM_BANKS  = 4,

    // FIFO depths as module parameters for configurability
    parameter int CMD_FIFO_DEPTH  = 64,
    parameter int WRITE_DATA_DEPTH= 256,
    parameter int READ_DATA_DEPTH = 256
)(
    input  logic clk_axi,
    input  logic clk_sdram,
    // VYLEPŠENIE: Oddelené, synchronizované resety pre každú doménu
    input  logic rstn_axi,
    input  logic rstn_sdram,

    // -- Reader interface (AXI domain)
    input  logic                   reader_valid,
    output logic                   reader_ready,
    input  logic [ADDR_WIDTH-1:0]  reader_addr,

    // -- Writer interface (AXI domain)
    input  logic                   writer_valid,
    output logic                   writer_ready,
    input  logic [ADDR_WIDTH-1:0]  writer_addr,
    input  logic [DATA_WIDTH-1:0]  writer_data,

    // -- Read response (AXI domain)
    output logic                   resp_valid,
    output logic                   resp_last,
    output logic [DATA_WIDTH-1:0]  resp_data,
    input  logic                   resp_ready,

    // -- Error monitoring (sticky, clearable)
    output logic                   error_overflow_o,
    output logic                   error_underflow_o,
    input  logic                   error_clear_i,

    // -- SDRAM physical pins (SDRAM domain)
    output logic [12:0]            sdram_addr,
    output logic [1:0]             sdram_ba,
    output logic                   sdram_cs_n,
    output logic                   sdram_ras_n,
    output logic                   sdram_cas_n,
    output logic                   sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0]  sdram_dq,
    output logic [1:0]             sdram_dqm,
    output logic                   sdram_cke
);

    import sdram_pkg::*;

    //================================================================
    // FIFO Signály a Inštancie
    //================================================================
    // (Signály pre prepojenie s FIFO modulmi)
    logic read_cmd_fifo_wr_en, read_cmd_fifo_rd_en;
    logic [ADDR_WIDTH-1:0] read_cmd_fifo_dout;
    logic read_cmd_fifo_full, read_cmd_fifo_empty, read_cmd_fifo_almost_full, read_cmd_fifo_overflow;

    logic write_cmd_fifo_wr_en, write_cmd_fifo_rd_en;
    logic [ADDR_WIDTH-1:0] write_cmd_fifo_din, write_cmd_fifo_dout;
    logic write_cmd_fifo_full, write_cmd_fifo_empty, write_cmd_fifo_almost_full, write_cmd_fifo_overflow;

    logic write_data_fifo_wr_en, write_data_fifo_rd_en;
    logic [DATA_WIDTH-1:0] write_data_fifo_dout;
    logic write_data_fifo_full, write_data_fifo_empty, write_data_fifo_almost_full, write_data_fifo_overflow;

    logic read_data_fifo_wr_en, read_data_fifo_rd_en;
    logic [DATA_WIDTH-1:0] read_data_fifo_din, read_data_fifo_dout;
    logic read_data_fifo_last_in, read_data_fifo_last_out;
    logic read_data_fifo_full, read_data_fifo_empty, read_data_fifo_underflow;

    // Inštancie asynchrónnych FIFO pamätí
    cdc_async_fifo #(.DATA_WIDTH(ADDR_WIDTH), .DEPTH(CMD_FIFO_DEPTH)) read_cmd_fifo_inst (
        .wr_clk_i(clk_axi), .wr_rst_ni(rstn_axi), .wr_en_i(read_cmd_fifo_wr_en), .wr_data_i(reader_addr), .full_o(read_cmd_fifo_full), .almost_full_o(read_cmd_fifo_almost_full), .overflow_o(read_cmd_fifo_overflow),
        .rd_clk_i(clk_sdram), .rd_rst_ni(rstn_sdram), .rd_en_i(read_cmd_fifo_rd_en), .rd_data_o(read_cmd_fifo_dout), .empty_o(read_cmd_fifo_empty)
    );
    cdc_async_fifo #(.DATA_WIDTH(ADDR_WIDTH), .DEPTH(CMD_FIFO_DEPTH)) write_cmd_fifo_inst (
        .wr_clk_i(clk_axi), .wr_rst_ni(rstn_axi), .wr_en_i(write_cmd_fifo_wr_en), .wr_data_i(write_cmd_fifo_din), .full_o(write_cmd_fifo_full), .almost_full_o(write_cmd_fifo_almost_full), .overflow_o(write_cmd_fifo_overflow),
        .rd_clk_i(clk_sdram), .rd_rst_ni(rstn_sdram), .rd_en_i(write_cmd_fifo_rd_en), .rd_data_o(write_cmd_fifo_dout), .empty_o(write_cmd_fifo_empty)
    );
    cdc_async_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(WRITE_DATA_DEPTH)) write_data_fifo_inst (
        .wr_clk_i(clk_axi), .wr_rst_ni(rstn_axi), .wr_en_i(write_data_fifo_wr_en), .wr_data_i(writer_data), .full_o(write_data_fifo_full), .almost_full_o(write_data_fifo_almost_full), .overflow_o(write_data_fifo_overflow),
        .rd_clk_i(clk_sdram), .rd_rst_ni(rstn_sdram), .rd_en_i(write_data_fifo_rd_en), .rd_data_o(write_data_fifo_dout), .empty_o(write_data_fifo_empty)
    );
    cdc_async_fifo #(.DATA_WIDTH(DATA_WIDTH + 1), .DEPTH(READ_DATA_DEPTH)) read_data_fifo_inst (
        .wr_clk_i(clk_sdram), .wr_rst_ni(rstn_sdram), .wr_en_i(read_data_fifo_wr_en), .wr_data_i({read_data_fifo_last_in, read_data_fifo_din}), .full_o(read_data_fifo_full),
        .rd_clk_i(clk_axi), .rd_rst_ni(rstn_axi), .rd_en_i(read_data_fifo_rd_en), .rd_data_o({read_data_fifo_last_out, read_data_fifo_dout}), .empty_o(read_data_fifo_empty), .underflow_o(read_data_fifo_underflow)
    );

    //================================================================
    // Sticky error registre (AXI doména)
    //================================================================
    always_ff @(posedge clk_axi or negedge rstn_axi) begin
        if (!rstn_axi) begin
            error_overflow_o  <= 1'b0;
            error_underflow_o <= 1'b0;
        end else begin
            if (error_clear_i) begin
                error_overflow_o  <= 1'b0;
                error_underflow_o <= 1'b0;
            end else begin
                error_overflow_o  <= error_overflow_o  || read_cmd_fifo_overflow || write_cmd_fifo_overflow || write_data_fifo_overflow;
                error_underflow_o <= error_underflow_o || read_data_fifo_underflow;
            end
        end
    end

    //================================================================
    // AXI Logika (AXI doména)
    //================================================================

    // --- AXI Zapisovací FSM (refaktorovaný do štandardnej dvoj-procesovej formy) ---
    typedef enum logic [1:0] { WR_IDLE, WR_COLLECT_DATA } axi_wr_state_t;
    axi_wr_state_t axi_wr_state, axi_wr_state_next;
    logic [$clog2(BURST_LENGTH):0] axi_wr_burst_cnt;
    logic increment_burst_counter, clear_burst_counter;

    // Sekvenčný proces: registruje len stav a počítadlo
    always_ff @(posedge clk_axi or negedge rstn_axi) begin
        if (!rstn_axi) begin
            axi_wr_state     <= WR_IDLE;
            axi_wr_burst_cnt <= '0;
        end else begin
            axi_wr_state <= axi_wr_state_next;
            if (clear_burst_counter) begin
                axi_wr_burst_cnt <= '0;
            end else if (increment_burst_counter) begin
                axi_wr_burst_cnt <= axi_wr_burst_cnt + 1;
            end
        end
    end

    // Kombinačný proces: riadi všetku logiku (nasledujúci stav, výstupy)
    always_comb begin
        // Defaultné hodnoty
        axi_wr_state_next       = axi_wr_state;
        increment_burst_counter = 1'b0;
        clear_burst_counter     = 1'b0;
        writer_ready            = 1'b0;
        write_cmd_fifo_wr_en    = 1'b0;
        write_cmd_fifo_din      = '0;
        write_data_fifo_wr_en   = 1'b0;

        case (axi_wr_state)
            WR_IDLE: begin
                writer_ready = !write_cmd_fifo_almost_full;
                if (writer_valid && writer_ready) begin
                    write_cmd_fifo_wr_en = 1'b1;
                    write_cmd_fifo_din   = writer_addr;
                    axi_wr_state_next    = WR_COLLECT_DATA;
                    clear_burst_counter  = 1'b1;
                end
            end
            WR_COLLECT_DATA: begin
                writer_ready = !write_data_fifo_almost_full;
                if (writer_valid && writer_ready) begin
                    write_data_fifo_wr_en = 1'b1;
                    increment_burst_counter = 1'b1;
                    if (axi_wr_burst_cnt == BURST_LENGTH - 1) begin
                        axi_wr_state_next = WR_IDLE;
                    end
                end
            end
            default: begin
                axi_wr_state_next = WR_IDLE;
            end
        endcase
    end

    // --- AXI Čítacia logika ---
    assign read_cmd_fifo_wr_en = reader_valid && !read_cmd_fifo_almost_full;
    assign reader_ready        = !read_cmd_fifo_almost_full;
    assign resp_valid          = !read_data_fifo_empty;
    assign resp_data           = read_data_fifo_dout;
    assign resp_last           = read_data_fifo_last_out;
    assign read_data_fifo_rd_en= resp_valid && resp_ready;

    //================================================================
    // Inštancie v SDRAM doméne
    //================================================================
    logic                  cmd_fifo_valid;
    logic                  cmd_fifo_ready;
    sdram_pkg::sdram_cmd_t cmd_fifo_data;
    logic                  ctrl_resp_valid, ctrl_resp_last;

    SdramCmdArbiter arbiter (
        .clk(clk_sdram), .rstn(rstn_sdram),
        .reader_valid(!read_cmd_fifo_empty), .reader_addr(read_cmd_fifo_dout),
        .writer_valid(!write_cmd_fifo_empty), .writer_addr(write_cmd_fifo_dout),
        .reader_ready(read_cmd_fifo_rd_en), .writer_ready(write_cmd_fifo_rd_en),
        .cmd_fifo_valid(cmd_fifo_valid), .cmd_fifo_ready(cmd_fifo_ready), .cmd_fifo_data(cmd_fifo_data)
    );

    SdramController #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .BURST_LEN(BURST_LENGTH),
        .NUM_BANKS(NUM_BANKS), .tRP(tRP), .tRCD(tRCD), .tWR(tWR), .tRFC(tRFC), .CAS_LATENCY(CAS_LATENCY)
    ) controller (
        .clk(clk_sdram), .rstn(rstn_sdram),
        .cmd_fifo_valid(cmd_fifo_valid), .cmd_fifo_ready(cmd_fifo_ready), .cmd_fifo_data(cmd_fifo_data),
        .resp_valid(ctrl_resp_valid), .resp_last(ctrl_resp_last), .resp_data(read_data_fifo_din),
        .resp_ready(!read_data_fifo_full),
        .wdata_valid(!write_data_fifo_empty), .wdata(write_data_fifo_dout), .wdata_ready(write_data_fifo_rd_en),
        .sdram_addr(sdram_addr), .sdram_ba(sdram_ba), .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_dq(sdram_dq), .sdram_dqm(sdram_dqm), .sdram_cke(sdram_cke)
    );

    // Prepojenie výstupu z radiča do read_data_fifo
    assign read_data_fifo_wr_en   = ctrl_resp_valid && !read_data_fifo_full;
    assign read_data_fifo_last_in = ctrl_resp_last;
    // OPRAVA: Odstránené nadbytočné a chybné priradenie. `read_data_fifo_din` je riadený
    // výlučne `.resp_data` portom z inštancie `controller`.

endmodule
