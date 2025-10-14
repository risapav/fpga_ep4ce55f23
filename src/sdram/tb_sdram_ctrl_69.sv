// sdram_controller_tb.sv - Vylepšený testbench pre SdramController v6.9
// Refaktoring: Vylepšený model pamäte, pridaný test pre backpressure, kód rozdelený do úloh.

`timescale 1ns/1ps

// Jednoduchý balíček pre definíciu príkazu
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

module sdram_controller_tb;

    import sdram_pkg::*;

    // --- Parametre ---
    localparam CLOCK_FREQ_HZ = 100_000_000;
    localparam CLK_PERIOD    = 10; // ns, zodpovedá 100 MHz
    localparam DATA_WIDTH    = 16;
    localparam BURST_LEN     = 8;

    // --- Signály ---
    logic                     clk;
    logic                     clk_sh;
    logic                     rstn;
    logic                     cmd_fifo_valid;
    logic                     cmd_fifo_ready;
    sdram_cmd_t               cmd_fifo_data;
    logic                     resp_valid;
    logic                     resp_last;
    logic [DATA_WIDTH-1:0]    resp_data;
    logic                     resp_ready;
    logic                     wdata_valid;
    logic [DATA_WIDTH-1:0]    wdata;
    logic [1:0]               wdata_dqm_i;
    logic                     wdata_ready;
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

    // --- Inštancia DUT (Device Under Test) ---
    SdramController #(
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
        .DATA_WIDTH   (DATA_WIDTH),
        .BURST_LEN    (BURST_LEN),
        .ENABLE_DEBUG (1) // Ponecháme debug aktívny pre testovanie
    ) DUT (.*);

    // --- Emulácia SDRAM pamäte a DQ zbernice ---
    // Vylepšený model pamäte, ktorý správne latchuje adresu riadku pre burst operácie
    // a používa asociatívne pole pre efektívnu simuláciu veľkého adresného priestoru.
    logic [DATA_WIDTH-1:0] mem [*];
    logic [14:0] latched_row_bank_addr; // Latchuje {bank, row}
    logic [DATA_WIDTH-1:0] sdram_dq_o;

    // Testbench (model pamäte) riadi DQ zbernicu len počas čítania. Počas zápisu ju riadi DUT.
    assign sdram_dq = (sdram_cs_n == 1'b0 && sdram_cas_n == 1'b0 && sdram_we_n == 1'b1) ? sdram_dq_o : 'z; 

    // Detekcia príkazov a prístup k pamäti
    always @(negedge sdram_clk) begin
        // Latchovanie adresy riadku pri príkaze ACTIVATE
        if (sdram_cs_n == 1'b0 && sdram_ras_n == 1'b0 && sdram_cas_n == 1'b1) begin
            latched_row_bank_addr <= {sdram_ba, sdram_addr};
        end

        // Zápis do pamäte pri príkaze WRITE
        if (sdram_cs_n == 1'b0 && sdram_cas_n == 1'b0 && sdram_we_n == 1'b0) begin
            mem[{latched_row_bank_addr, sdram_addr[8:0]}] <= sdram_dq;
        end
    end

    // Poskytovanie dát pre čítanie
    always @(posedge sdram_clk) begin
        if (sdram_cs_n == 1'b0 && sdram_cas_n == 1'b0 && sdram_we_n == 1'b1) begin
             if (mem.exists({latched_row_bank_addr, sdram_addr[8:0]})) begin
                sdram_dq_o <= mem[{latched_row_bank_addr, sdram_addr[8:0]}];
             end else begin
                sdram_dq_o <= {DATA_WIDTH{1'bx}}; // Ak adresa neexistuje, vrátime X
                $warning("[%0t] [MEM_MODEL] Reading from uninitialized address: %h", $time, {latched_row_bank_addr, sdram_addr[8:0]});
             end
        end
    end

    // --- Generovanie hodín ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    always @(clk) #1 clk_sh = clk;

    // --- Testovacie úlohy (Tasks) pre čistejší kód ---
    task send_command(input sdram_cmd_t cmd);
        wait (cmd_fifo_ready);
        cmd_fifo_data <= cmd;
        cmd_fifo_valid <= 1'b1;
        @(posedge clk);
        cmd_fifo_valid <= 1'b0;
    endtask

    task send_write_data(input logic [23:0] base_addr, input int unsigned start_val);
        wait (wdata_ready);
        wdata_valid <= 1'b1;
        for (integer i = 0; i < BURST_LEN; i++) begin
            wait(wdata_ready);
            wdata <= start_val + i;
            $display("[%0t] Providing write data: %h for addr %h", $time, wdata, base_addr + i);
            @(posedge clk);
        end
        wdata_valid <= 1'b0;
    endtask

    task receive_read_data(input logic [23:0] base_addr, input int unsigned expect_val, input bit apply_backpressure);
        logic [DATA_WIDTH-1:0] expected_data;
        resp_ready <= 1'b1;
        for (integer i = 0; i < BURST_LEN; i++) begin
            if (apply_backpressure) begin
                if ($urandom_range(0, 3) == 0) begin
                    resp_ready <= 1'b0;
                    $display("[%0t] Applying backpressure...", $time);
                    repeat($urandom_range(1, 4)) @(posedge clk);
                    resp_ready <= 1'b1;
                end
            end
            
            wait(resp_valid);
            expected_data = expect_val + i;
            $display("[%0t] Received read data: %h (Expected: %h, Last: %b)", $time, resp_data, expected_data, resp_last);
            
            if (resp_data !== expected_data) begin
                $error("[%0t] DATA MISMATCH! Addr: %h, Expected %h, got %h", $time, base_addr + i, expected_data, resp_data);
            end
            @(posedge clk);
        end
        resp_ready <= 1'b0;
    endtask

    // --- Hlavná testovacia sekvencia ---
    initial begin
        $display("[%0t] Testbench started.", $time);
        
        // 1. Reset
        rstn = 1'b1;
        cmd_fifo_valid = 1'b0; wdata_valid = 1'b0; resp_ready = 1'b0;
        #10;
        rstn = 1'b0;
        $display("[%0t] Reset asserted.", $time);
        #50;
        rstn = 1'b1;
        $display("[%0t] Reset deasserted. Waiting for init...", $time);

        wait (DUT.debug_state_o == sdram_pkg::IDLE);
        $display("[%0t] Controller is in IDLE state.", $time);

        // 2. Operácia ZÁPISU (Adresa 1)
        $display("[%0t] Starting WRITE operation to ADDR1.", $time);
        send_command('{addr: 24'h00_1000, rw: WRITE_CMD});
        send_write_data(24'h00_1000, 16'hA000);
        $display("[%0t] WRITE data burst sent to ADDR1.", $time);
        wait (DUT.debug_state_o inside {sdram_pkg::IDLE, sdram_pkg::IDLE_WAIT});
        
        // 3. Operácia ČÍTANIA (Adresa 1)
        $display("[%0t] Starting READ operation from ADDR1.", $time);
        send_command('{addr: 24'h00_1000, rw: READ_CMD});
        receive_read_data(24'h00_1000, 16'hA000, 0);
        $display("[%0t] READ data burst received from ADDR1.", $time);
        wait (DUT.debug_state_o inside {sdram_pkg::IDLE, sdram_pkg::IDLE_WAIT});

        #100;

        // 4. Operácia ZÁPISU (Adresa 2)
        $display("[%0t] Starting WRITE operation to ADDR2.", $time);
        send_command('{addr: 24'h80_BEEF, rw: WRITE_CMD});
        send_write_data(24'h80_BEEF, 16'hC000);
        $display("[%0t] WRITE data burst sent to ADDR2.", $time);
        wait (DUT.debug_state_o inside {sdram_pkg::IDLE, sdram_pkg::IDLE_WAIT});
        
        // 5. Operácia ČÍTANIA s BACKPRESSURE (Adresa 2)
        $display("[%0t] Starting READ from ADDR2 with backpressure.", $time);
        send_command('{addr: 24'h80_BEEF, rw: READ_CMD});
        receive_read_data(24'h80_BEEF, 16'hC000, 1);
        $display("[%0t] READ data burst received from ADDR2.", $time);

        #200;
        $display("[%0t] Testbench finished successfully.", $time);
        $finish;
    end

endmodule

