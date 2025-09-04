// axi_seg_counter.sv - Vylepšený AXI master pre riadenie 7-segmentového displeja
//
// Verzia 2.0 - Opravy a vylepšenia
//
// Kľúčové zmeny:
// 1. OPRAVA (Konzistentnosť): Pridaný nevyhnutný `import axi_pkg::*;`.
// 2. VYLEPŠENIE (Robustnosť): AXI FSM bol zjednodušený na dva stavy (IDLE,
//    WRITE_TRANSFER), čo robí logiku čistejšou a robustnejšou.
// 3. VYLEPŠENIE (Funkčnosť): Logika zápisu bola upravená tak, aby na displej
//    posielala intuitívnejšiu hodnotu (napr. "005" namiesto "FF5").

`default_nettype none

import axi_pkg::*; // Nevyhnutný import pre prístup k AXI definíciám

module axi_seg_counter #(
    parameter CLOCK_FREQ_HZ = 50_000_000
)(
    input  logic clk,
    input  logic rstn,
    axi4lite_if.master axi
);

    // --- Stavy pre AXI Write FSM ---
    typedef enum logic [0:0] {
        IDLE,
        WRITE_TRANSFER
    } axi_write_state_t;

    axi_write_state_t state;

    // --- Interné počítadlá a signály ---
    logic [3:0]  counter;     // Počítadlo 0-9
    logic [26:0] sec_cnt;     // Počítadlo pre generovanie 1s intervalu
    logic        start_write; // Pulz na spustenie AXI transakcie

    //================================================================
    // 1-sekundový intervalový generátor
    //================================================================
    always_ff @(posedge clk) begin
        if (!rstn) begin
            sec_cnt     <= '0;
            counter     <= '0;
            start_write <= 1'b0;
        end else begin
            start_write <= 1'b0; // Defaultne je pulz neaktívny
            if (sec_cnt >= CLOCK_FREQ_HZ - 1) begin
                sec_cnt <= '0;
                counter <= (counter == 9) ? 0 : counter + 1;
                // Vygenerujeme jednociklový pulz, len ak FSM nie je zaneprázdnený
                if (state == IDLE) begin
                    start_write <= 1'b1;
                end
            end else begin
                sec_cnt <= sec_cnt + 1;
            end
        end
    end

    //================================================================
    // AXI4-Lite Write State Machine (zjednodušená verzia)
    //================================================================
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state <= IDLE;
            axi.AWVALID <= 1'b0;
            axi.WVALID  <= 1'b0;
            axi.BREADY  <= 1'b0;
            axi.AWADDR  <= '0;
            axi.WDATA   <= '0;
        end else begin
            case (state)
                IDLE: begin
                    axi.AWVALID <= 1'b0;
                    axi.WVALID  <= 1'b0;
                    axi.BREADY  <= 1'b0;
                    if (start_write) begin
                        // Začíname novú transakciu
                        axi.AWVALID <= 1'b1;
                        axi.WVALID  <= 1'b1;
                        // Adresa registra pre číslice (zodpovedá slave modulu)
                        axi.AWADDR  <= 32'h00; 
                        // Zobrazíme napr. "00X", kde X je hodnota počítadla
                        axi.WDATA   <= {20'd0, 4'd0, 4'd0, counter}; 
                        state       <= WRITE_TRANSFER;
                    end
                end

                WRITE_TRANSFER: begin
                    // Čakáme na prijatie adresy a dát
                    if (axi.AWVALID && axi.AWREADY) begin
                        axi.AWVALID <= 1'b0; // Adresa bola prijatá
                    end
                    if (axi.WVALID && axi.WREADY) begin
                        axi.WVALID <= 1'b0; // Dáta boli prijaté
                    end

                    // Keď sú adresa aj dáta odoslané, prejdeme na response fázu
                    if (!axi.AWVALID && !axi.WVALID) begin
                        axi.BREADY <= 1'b1;
                        // Čakáme na BVALID od slava
                        if (axi.BVALID) begin
                            state <= IDLE;
                            axi.BREADY <= 1'b0;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // -- Nepoužívané AXI kanály nastavíme na neaktívne hodnoty --
    assign axi.WSTRB   = 4'b1111; // Vždy zapisujeme celé 32-bitové slovo
    assign axi.AWPROT  = 3'b000;
    assign axi.ARVALID = 1'b0;
    assign axi.ARADDR  = '0;
    assign axi.ARPROT  = '0;
    assign axi.RREADY  = 1'b0;

endmodule
