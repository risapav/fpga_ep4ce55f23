// Top_Refactored.sv - Verzia 2.0
// Vrcholový modul pre testovanie SdramController v6.10 a AxiStreamSdramWrapper v2.0
// s konfiguráciou pre double-buffering a veľký paket (800x600 frame).

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
    typedef enum logic [1:0] { EMPTY, FILLING, FULL, READING } buffer_state_t;
endpackage

module Top;

    import sdram_pkg::*;

    // --- Parametre ---
    localparam integer CLOCK_FREQ_HZ    = 100_000_000;
    localparam integer CLK_PERIOD       = 10; // ns
    localparam integer DATA_WIDTH       = 16;
    
    // Konfigurácia pre Wrapper
    localparam integer PACKET_LEN_WORDS = 480_000; // 800 * 600
    localparam integer BURST_LEN        = 8;
    localparam integer NUM_BUFFERS      = 2; // Double-Buffering

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
    
    // Debug porty
    buffer_state_t debug_buffer_state [0:NUM_BUFFERS-1];
    logic [$clog2(NUM_BUFFERS)-1:0] debug_find_empty_start_idx;
    logic [$clog2(NUM_BUFFERS)-1:0] debug_find_full_start_idx;

    // Premenné pre kontrolu dát
    logic [DATA_WIDTH-1:0] frame0_first_word, frame0_last_word;
    logic [DATA_WIDTH-1:0] frame1_first_word, frame1_last_word;

    // --- Inštancia Wrapperu ---
    AxiStreamSdramWrapper #(
        .AXIS_DATA_WIDTH(DATA_WIDTH),
        .PACKET_LEN_WORDS(PACKET_LEN_WORDS),
        .BURST_LEN(BURST_LEN),
        .NUM_BUFFERS(NUM_BUFFERS)
    ) wrapper_inst (
        .clk, .rstn,
        .s_axis_tdata, .s_axis_tvalid, .s_axis_tready, .s_axis_tlast,
        .m_axis_tdata, .m_axis_tvalid, .m_axis_tready, .m_axis_tlast,
        .cmd_fifo_valid, .cmd_fifo_ready, .cmd_fifo_data,
        .wdata_valid, .wdata, .wdata_dqm_i, .wdata_ready,
        .resp_valid, .resp_last, .resp_data, .resp_ready,
        .debug_buffer_state, .debug_find_empty_start_idx, .debug_find_full_start_idx
    );

    // --- Inštancia SDRAM Kontroléra (v6.10 Quartus-Ready) ---
    // Poznámka: sdram_controller.sv musí byť dostupný v projekte
    SdramController #(
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_LEN(BURST_LEN)
    ) sdram_inst (
        .clk, .clk_sh, .rstn,
        .cmd_fifo_valid, .cmd_fifo_ready, .cmd_fifo_data,
        .resp_valid, .resp_last, .resp_data, .resp_ready,
        .wdata_valid, .wdata, .wdata_dqm_i, .wdata_ready,
        .sdram_addr, .sdram_ba, .sdram_cs_n, .sdram_ras_n, .sdram_cas_n, .sdram_we_n,
        .sdram_dq, .sdram_dqm, .sdram_cke, .sdram_clk,
        .* // Pripojenie debug portov pre jednoduchosť
    );
    
    // --- Behaviorálny model SDRAM pamäte ---
    logic [DATA_WIDTH-1:0] sdram_memory [1 << 22];
    
    logic reading, writing;
    logic [$clog2(BURST_LEN)-1:0] burst_counter;
    logic [SDRAM_ADDR_WIDTH-1:0] burst_base_addr;
    logic [2:0] cas_counter;

    logic [DATA_WIDTH-1:0] dq_out;
    logic dq_oe;

    assign sdram_dq = dq_oe ? dq_out : 'z;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            reading <= 1'b0;
            writing <= 1'b0;
            burst_counter <= '0;
            cas_counter <= '0;
            dq_oe <= 1'b0;
        end else begin
            if (writing) begin
                if (!sdram_dqm[0]) sdram_memory[burst_base_addr + burst_counter][7:0] <= sdram_dq[7:0];
                if (!sdram_dqm[1]) sdram_memory[burst_base_addr + burst_counter][15:8] <= sdram_dq[15:8];
                if (burst_counter == BURST_LEN - 1) writing <= 1'b0;
                burst_counter <= burst_counter + 1;
            end
            
            if (reading) begin
                if (cas_counter > 0) begin
                    cas_counter <= cas_counter - 1;
                end else begin
                    dq_out <= sdram_memory[burst_base_addr + burst_counter];
                    if (burst_counter == BURST_LEN - 1) begin
                        reading <= 1'b0;
                        dq_oe <= 1'b0;
                    end
                    burst_counter <= burst_counter + 1;
                end
            end

            if (!sdram_cs_n && sdram_ras_n && !sdram_cas_n) begin
                if (sdram_we_n) begin // READ
                    if (!reading) begin
                        reading <= 1'b1;
                        burst_counter <= '0;
                        cas_counter <= sdram_inst.CAS_LATENCY;
                        dq_oe <= 1'b1;
                        burst_base_addr <= cmd_fifo_data.addr;
                    end
                end else begin // WRITE
                    if (!writing) begin
                        writing <= 1'b1;
                        burst_counter <= '0;
                        burst_base_addr <= cmd_fifo_data.addr;
                    end
                end
            end
        end
    end

    // --- Generovanie hodín ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    always @(posedge clk) #1 clk_sh = clk;

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
                repeat(10) @(posedge clk);
                rstn <= 1'b1;
                $display("[%0t] Test začína: Reset uvoľnený.", $time);
                
                wait(sdram_inst.debug_state_o == IDLE || sdram_inst.debug_state_o == IDLE_WAIT);
                $display("[%0t] SDRAM kontrolér je pripravený.", $time);
                
                // Pošleme dva celé framy
                for (integer frame = 0; frame < 2; frame++) begin
                    $display("[%0t] Generátor: Posielam frame %0d...", $time, frame);
                    if (frame == 0) frame0_first_word = counter;
                    else frame1_first_word = counter;

                    for (integer i = 0; i < PACKET_LEN_WORDS; i++) begin
                        wait(s_axis_tready);
                        s_axis_tvalid <= 1'b1;
                        s_axis_tdata <= counter;
                        s_axis_tlast <= (i == PACKET_LEN_WORDS - 1);
                        @(posedge clk);
                        counter++;
                    end

                    if (frame == 0) frame0_last_word = counter - 1;
                    else frame1_last_word = counter - 1;

                    s_axis_tvalid <= 1'b0;
                    s_axis_tlast <= 1'b0;
                    $display("[%0t] Generátor: Frame %0d odoslaný.", $time, frame);
                end
            end
        join_none;

        // --- Prijímač dát (Data Sink) ---
        fork
            begin
                logic [DATA_WIDTH-1:0] received_first, received_last;
                m_axis_tready <= 1'b0;
                wait(rstn);
                
                for (integer frame = 0; frame < 2; frame++) begin
                    $display("[%0t] Prijímač: Čakám na frame %0d...", $time, frame);
                    logic first_word_received = 1'b0;

                    for (integer i = 0; i < PACKET_LEN_WORDS; i++) begin
                        m_axis_tready <= $urandom_range(0,1);
                        wait(m_axis_tvalid && m_axis_tready);
                        
                        if (!first_word_received) begin
                            received_first = m_axis_tdata;
                            first_word_received = 1'b1;
                        end
                        if (m_axis_tlast) begin
                            received_last = m_axis_tdata;
                        end
                        @(posedge clk);
                    end
                    m_axis_tready <= 1'b0;
                    $display("[%0t] Prijímač: Frame %0d prijatý. Prvé slovo: %h, Posledné slovo: %h", $time, frame, received_first, received_last);
                    
                    if (frame == 0) begin
                        if(received_first != frame0_first_word || received_last != frame0_last_word) $error("Chyba dát vo frame 0!");
                    end else begin
                        if(received_first != frame1_first_word || received_last != frame1_last_word) $error("Chyba dát vo frame 1!");
                    end
                end
                $display("Test prebehol úspešne!");
                $finish;
            end
        join_none;

        #20_000_000;
        $error("Test zlyhal - timeout!");
        $finish;
    end

endmodule
