// sdram_driver.sv - Finálna verzia s robustným AXI rozhraním
//
// Verzia 3.0 - Vylepšenie AXI rozhrania
//
// Kľúčové zmeny:
// 1. VYLEPŠENIE (Protokol): Implementovaný stavový automat na strane AXI (clk_axi)
//    pre správne spracovanie zápisových transakcií.
// 2. VYLEPŠENIE (Handshake): Logika teraz správne oddeľuje prijatie príkazu na zápis
//    (adresy) od následného zberu burstu dát. To presnejšie modeluje správanie
//    štandardných zberníc ako AXI.
// 3. VYLEPŠENIE (Robustnosť): Celý write-path je teraz robustnejší a lepšie
//    pripravený na integráciu do reálneho systému.

`include "sdram_pkg.sv"

module SdramDriver #(
    parameter ADDR_WIDTH = 24,
    parameter DATA_WIDTH = 16,
    parameter BURST_LENGTH = 8,
    // SDRAM timing parameters
    parameter int tRP        = 3,
    parameter int tRCD       = 3,
    parameter int tWR        = 3,
    parameter int tRFC       = 9,
    parameter int CAS_LATENCY= 3,
    parameter int NUM_BANKS  = 4
)(
    input  logic clk_axi,
    input  logic clk_sdram,
    input  logic rstn,

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
    // Asynchrónne FIFOs pre prechod medzi hodinovými doménami
    //================================================================

    // -- 1. FIFO pre príkazy na čítanie (AXI -> SDRAM)
    logic [ADDR_WIDTH-1:0] read_cmd_fifo_din, read_cmd_fifo_dout;
    logic                  read_cmd_fifo_wr_en, read_cmd_fifo_rd_en;
    logic                  read_cmd_fifo_full, read_cmd_fifo_empty;

    AsyncFIFO #( .DATA_WIDTH(ADDR_WIDTH), .DEPTH(64) )
    read_cmd_fifo_inst (
        .wr_clk(clk_axi),   .wr_rstn(rstn), .wr_en(read_cmd_fifo_wr_en), .wr_data(reader_addr), .full(read_cmd_fifo_full),
        .rd_clk(clk_sdram), .rd_rstn(rstn), .rd_en(read_cmd_fifo_rd_en), .rd_data(read_cmd_fifo_dout), .empty(read_cmd_fifo_empty)
    );

    // -- 2. FIFO pre príkazy na zápis (AXI -> SDRAM)
    logic [ADDR_WIDTH-1:0] write_cmd_fifo_din, write_cmd_fifo_dout;
    logic                  write_cmd_fifo_wr_en, write_cmd_fifo_rd_en;
    logic                  write_cmd_fifo_full, write_cmd_fifo_empty;

    AsyncFIFO #( .DATA_WIDTH(ADDR_WIDTH), .DEPTH(64) )
    write_cmd_fifo_inst (
        .wr_clk(clk_axi),   .wr_rstn(rstn), .wr_en(write_cmd_fifo_wr_en), .wr_data(write_cmd_fifo_din), .full(write_cmd_fifo_full),
        .rd_clk(clk_sdram), .rd_rstn(rstn), .rd_en(write_cmd_fifo_rd_en), .rd_data(write_cmd_fifo_dout), .empty(write_cmd_fifo_empty)
    );

    // -- 3. FIFO pre dáta na zápis (AXI -> SDRAM)
    logic [DATA_WIDTH-1:0] write_data_fifo_din, write_data_fifo_dout;
    logic                  write_data_fifo_wr_en, write_data_fifo_rd_en;
    logic                  write_data_fifo_full, write_data_fifo_empty;

    AsyncFIFO #( .DATA_WIDTH(DATA_WIDTH), .DEPTH(256) )
    write_data_fifo_inst (
        .wr_clk(clk_axi),   .wr_rstn(rstn), .wr_en(write_data_fifo_wr_en), .wr_data(writer_data), .full(write_data_fifo_full),
        .rd_clk(clk_sdram), .rd_rstn(rstn), .rd_en(write_data_fifo_rd_en), .rd_data(write_data_fifo_dout), .empty(write_data_fifo_empty)
    );

    // -- 4. FIFO pre čítané dáta (SDRAM -> AXI)
    logic [DATA_WIDTH-1:0] read_data_fifo_din, read_data_fifo_dout;
    logic                  read_data_fifo_wr_en, read_data_fifo_rd_en;
    logic                  read_data_fifo_full, read_data_fifo_empty;
    logic                  read_data_fifo_last_in, read_data_fifo_last_out;

    AsyncFIFO #( .DATA_WIDTH(DATA_WIDTH + 1), .DEPTH(256) ) // +1 bit for `last`
    read_data_fifo_inst (
        .wr_clk(clk_sdram), .wr_rstn(rstn), .wr_en(read_data_fifo_wr_en), .wr_data({read_data_fifo_last_in, read_data_fifo_din}), .full(read_data_fifo_full),
        .rd_clk(clk_axi),   .rd_rstn(rstn), .rd_en(read_data_fifo_rd_en), .rd_data({read_data_fifo_last_out, read_data_fifo_dout}), .empty(read_data_fifo_empty)
    );

    //================================================================
    // Logika prepojenia (AXI doména)
    //================================================================

    // -- AXI-strana: Zápis do read_cmd_fifo
    assign read_cmd_fifo_wr_en = reader_valid && !read_cmd_fifo_full;
    assign reader_ready        = !read_cmd_fifo_full;

    // -- AXI-strana: Stavový automat pre robustné spracovanie zápisov
    typedef enum logic [1:0] { WR_IDLE, WR_COLLECT_CMD, WR_COLLECT_DATA } axi_wr_state_t;
    axi_wr_state_t axi_wr_state;
    logic [$clog2(BURST_LENGTH):0] axi_wr_burst_cnt;

    always_ff @(posedge clk_axi or negedge rstn) begin
        if (!rstn) begin
            axi_wr_state     <= WR_IDLE;
            axi_wr_burst_cnt <= '0;
        end else begin
            case (axi_wr_state)
                WR_IDLE: begin
                    // V IDLE čakáme na platný príkaz na zápis
                    if (writer_valid && writer_ready) begin
                        axi_wr_state <= WR_COLLECT_DATA;
                    end
                end
                WR_COLLECT_DATA: begin
                    // Zbierame dáta pre prijatý príkaz
                    if (writer_valid && writer_ready) begin
                        if (axi_wr_burst_cnt == BURST_LENGTH - 1) begin
                            // Prijali sme posledné slovo burstu, vraciame sa do IDLE
                            axi_wr_state     <= WR_IDLE;
                            axi_wr_burst_cnt <= '0;
                        end else begin
                            axi_wr_burst_cnt <= axi_wr_burst_cnt + 1;
                        end
                    end
                end
                default: axi_wr_state <= WR_IDLE;
            endcase
        end
    end

    // Kombinačná logika pre riadenie AXI zápisu
    always_comb begin
        writer_ready = 1'b0;
        write_cmd_fifo_wr_en = 1'b0;
        write_cmd_fifo_din = '0;
        write_data_fifo_wr_en = 1'b0;

        case (axi_wr_state)
            WR_IDLE: begin
                // Sme pripravení prijať nový príkaz na zápis (adresu)
                writer_ready = !write_cmd_fifo_full;
                if (writer_valid && writer_ready) begin
                    write_cmd_fifo_wr_en = 1'b1;
                    write_cmd_fifo_din   = writer_addr;
                end
            end
            WR_COLLECT_DATA: begin
                // Sme pripravení prijímať dáta pre burst
                writer_ready = !write_data_fifo_full;
                if (writer_valid && writer_ready) begin
                    write_data_fifo_wr_en = 1'b1;
                end
            end
        endcase
    end

    // -- AXI-strana: Čítanie z read_data_fifo
    assign resp_valid           = !read_data_fifo_empty;
    assign resp_data            = read_data_fifo_dout;
    assign resp_last            = read_data_fifo_last_out;
    assign read_data_fifo_rd_en = resp_valid && resp_ready;

    //================================================================
    // Inštancie Arbitra a Radiča (v SDRAM hodinovej doméne)
    //================================================================

    logic                  cmd_fifo_valid;
    logic                  cmd_fifo_ready;
    sdram_pkg::sdram_cmd_t cmd_fifo_data;
    logic ctrl_resp_valid, ctrl_resp_last;

    // -- Arbiter
    SdramCmdArbiter arbiter (
        .clk(clk_sdram), .rstn(rstn),
        .reader_valid(!read_cmd_fifo_empty), .reader_addr(read_cmd_fifo_dout),
        .writer_valid(!write_cmd_fifo_empty), .writer_addr(write_cmd_fifo_dout),
        .reader_ready(read_cmd_fifo_rd_en), .writer_ready(write_cmd_fifo_rd_en),
        .cmd_fifo_valid(cmd_fifo_valid), .cmd_fifo_ready(cmd_fifo_ready), .cmd_fifo_data(cmd_fifo_data)
    );

    // -- Radič
    SdramController #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .BURST_LEN(BURST_LENGTH),
        .NUM_BANKS(NUM_BANKS), .tRP(tRP), .tRCD(tRCD), .tWR(tWR), .tRFC(tRFC), .CAS_LATENCY(CAS_LATENCY)
    ) controller (
        .clk(clk_sdram), .rstn(rstn),
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

endmodule
