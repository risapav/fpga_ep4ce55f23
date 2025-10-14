// Top.sv - Verzia 1.0
// Príklad vrcholového modulu, ktorý inštancuje SdramController a AxiStreamSdramWrapper.
// Obsahuje jednoduchý generátor a prijímač dát pre simuláciu.

`timescale 1ns/1ps

// Balíček potrebný pre SdramController a Wrapper
package sdram_pkg;
    typedef enum {READ_CMD, WRITE_CMD} rw_cmd_t;
    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH, INIT_MRS,
        IDLE, IDLE_WAIT,
        ACTIVE_CMD, ACTIVE_WAIT, PREFETCH_WDATA, RW_CMD,
        READ_BURST, WRITE_BURST,
        PRECHARGE_CMD, REFRESH_CMD
    } state_t;
    typedef struct packed {
        logic [23:0] addr;
        rw_cmd_t     rw;
    } sdram_cmd_t;
endpackage

module Top;

    import sdram_pkg::*;

    // --- Parametre ---
    localparam integer CLOCK_FREQ_HZ    = 100_000_000;
    localparam integer CLK_PERIOD       = 10; // ns
    localparam integer DATA_WIDTH       = 16;
    localparam integer PACKET_LEN_WORDS = 64; // Kratší paket pre rýchlejšiu simuláciu

    // --- Signály ---
    logic clk;
    logic clk_sh;
    logic rstn;

    // AXI-Stream signály
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic                  s_axis_tvalid;
    logic                  s_axis_tready;
    logic                  s_axis_tlast;

    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic                  m_axis_tvalid;
    logic                  m_axis_tready;
    logic                  m_axis_tlast;

    // SDRAM Controller Interface
    logic                     cmd_fifo_valid;
    logic                     cmd_fifo_ready;
    sdram_cmd_t               cmd_fifo_data;
    logic                     wdata_valid;
    logic [DATA_WIDTH-1:0]    wdata;
    logic [1:0]               wdata_dqm_i;
    logic                     wdata_ready;
    logic                     resp_valid;
    logic                     resp_last;
    logic [DATA_WIDTH-1:0]    resp_data;
    logic                     resp_ready;
    
    // SDRAM Physical Interface
    logic [12:0]              sdram_addr;
    logic [1:0]               sdram_ba;
    logic                     sdram_cs_n;
    logic                     sdram_ras_n;
    logic                     sdram_cas_n;
    logic                     sdram_we_n;
    wire  [DATA_WIDTH-1:0]    sdram_dq;
    logic [1:0]               sdram_dqm;
    logic                     sdram_cke;
    logic                     sdram_clk;

    // --- Inštancia Wrapperu ---
    AxiStreamSdramWrapper #(
        .AXIS_DATA_WIDTH(DATA_WIDTH),
        .PACKET_LEN_WORDS(PACKET_LEN_WORDS)
    ) wrapper_inst (
        .clk, .rstn,
        .s_axis_tdata, .s_axis_tvalid, .s_axis_tready, .s_axis_tlast,
        .m_axis_tdata, .m_axis_tvalid, .m_axis_tready, .m_axis_tlast,
        .cmd_fifo_valid, .cmd_fifo_ready, .cmd_fifo_data,
        .wdata_valid, .wdata, .wdata_dqm_i, .wdata_ready,
        .resp_valid, .resp_last, .resp_data, .resp_ready
    );

    // --- Inštancia SDRAM Kontroléra ---
    SdramController #(
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
        .DATA_WIDTH(DATA_WIDTH)
    ) sdram_inst (
        .clk, .clk_sh, .rstn,
        .cmd_fifo_valid, .cmd_fifo_ready, .cmd_fifo_data,
        .resp_valid, .resp_last, .resp_data, .resp_ready,
        .wdata_valid, .wdata, .wdata_dqm_i, .wdata_ready,
        .sdram_addr, .sdram_ba, .sdram_cs_n, .sdram_ras_n, .sdram_cas_n, .sdram_we_n,
        .sdram_dq, .sdram_dqm, .sdram_cke, .sdram_clk,
        // Debug porty nie sú pripojené v tomto príklade
        .*
    );
    
    // --- Model SDRAM pamäte a zbernice ---
    // (pre jednoduchosť tu nie je zahrnutý, pre testovanie je potrebný plnohodnotný model)
    assign sdram_dq = 'z;

    // --- Generovanie hodín ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    always @(clk) #1 clk_sh = clk;

    // --- Testovacia sekvencia ---
    initial begin
        // --- Generátor dát (Data Source) ---
        fork
            begin
                logic [DATA_WIDTH-1:0] counter = 0;
                rstn <= 1'b0;
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
                s_axis_tdata <= '0;
                repeat(5) @(posedge clk);
                rstn <= 1'b1;
                $display("[%0t] Test začína: Reset uvoľnený.", $time);
                
                wait(sdram_inst.debug_state_o == IDLE); // Počkáme na inicializáciu SDRAM
                
                forever begin
                    $display("[%0t] Generátor: Posielam nový paket...", $time);
                    for (integer i = 0; i < PACKET_LEN_WORDS; i++) begin
                        wait(s_axis_tready);
                        s_axis_tvalid <= 1'b1;
                        s_axis_tdata <= counter;
                        s_axis_tlast <= (i == PACKET_LEN_WORDS - 1);
                        @(posedge clk);
                        counter++;
                    end
                    s_axis_tvalid <= 1'b0;
                    s_axis_tlast <= 1'b0;
                    $display("[%0t] Generátor: Paket odoslaný.", $time);
                    // Pauza pred ďalším paketom
                    repeat(20) @(posedge clk);
                end
            end
        join_none;

        // --- Prijímač dát (Data Sink) ---
        fork
            begin
                logic [DATA_WIDTH-1:0] received_data;
                m_axis_tready <= 1'b0;
                wait(rstn);
                
                forever begin
                    m_axis_tready <= $urandom_range(0,1); // Simulácia náhodného backpressure
                    wait(m_axis_tvalid);
                    if (m_axis_tready) begin
                        received_data = m_axis_tdata;
                        $display("[%0t] Prijímač: Prijaté dáta: %h %s", $time, received_data, m_axis_tlast ? "(LAST)" : "");
                    end
                    @(posedge clk);
                end
            end
        join_none;

        // Dĺžka simulácie
        #50000;
        $display("[%0t] Koniec simulácie.", $time);
        $finish;
    end

endmodule
