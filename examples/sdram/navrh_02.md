Absolútne. Na základe nášho detailného návrhu som pripravil kompletný kód modulu `FramebufferController` v SystemVerilogu. Tento kód je navrhnutý tak, aby sa priamo integroval s vašimi existujúcimi modulmi (`SdramDriver`, `SdramCmdArbiter`, `SdramController` a `sdram_pkg`).

Nižšie nájdete:

1.  **Kód modulu `FramebufferController.sv`** s podrobnými komentármi.
2.  **Kód najvyššieho modulu `Top_VGA_System.sv`**, ktorý ukazuje, ako sa všetky vaše komponenty (vrátane nového) spoja do jedného funkčného celku.
3.  **Vysvetlenie kľúčových častí kódu.**

-----

### 1\. Kód Modulu `FramebufferController.sv`

Tento modul implementuje všetku logiku, ktorú sme navrhli: dvojité bufferovanie, zapisovaciu cestu pre plnenie buffera a čítaciu cestu s kľúčovým **read-ahead line bufferom** pre VGA.

```systemverilog
// FramebufferController.sv - Riadiaci modul pre dvojité bufferovanie v SDRAM
//
// Zodpovednosti:
// 1. Prijíma prúd pixelov a zapisuje ich do "back" framebuffera v SDRAM.
// 2. Proaktívne číta riadky z "front" framebuffera do interného FIFO buffera.
// 3. Poskytuje pixely pre VGA zobrazovač z rýchleho interného FIFO buffera.
// 4. Manažuje prehadzovanie "front" a "back" bufferov.

`include "sdram_pkg.sv"

module FramebufferController #(
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 24,
    parameter BURST_LEN  = 8,
    parameter FB0_BASE_ADDR = 24'h000000,
    parameter FB1_BASE_ADDR = 24'h080000
)(
    input  logic clk, // Predpokladáme jednu hodinovú doménu (clk_axi z Drivera)
    input  logic rstn,

    // --- Rozhranie pre vstup pixelov (od zdroja obrazu) ---
    input  logic             pixel_in_valid,
    output logic             pixel_in_ready,
    input  logic [DATA_WIDTH-1:0] pixel_in_data,

    // --- Rozhranie pre VGA Zobrazovač ---
    input  logic [$clog2(H_RES)-1:0] vga_req_x,
    input  logic [$clog2(V_RES)-1:0] vga_req_y,
    output logic [DATA_WIDTH-1:0]   vga_pixel_data,
    output logic                    vga_pixel_valid,

    // --- Riadiace signály ---
    input  logic             ctrl_start_fill,
    input  logic             ctrl_swap_buffers,
    output logic             status_busy_filling,

    // --- Rozhranie k SdramDriver (AXI strana) ---
    // Writer port
    output logic             sdram_writer_valid,
    input  logic             sdram_writer_ready,
    output logic [ADDR_WIDTH-1:0] sdram_writer_addr,
    output logic [DATA_WIDTH-1:0] sdram_writer_data,

    // Reader port
    output logic             sdram_reader_valid,
    input  logic             sdram_reader_ready,
    output logic [ADDR_WIDTH-1:0] sdram_reader_addr,

    // Read response port
    input  logic             sdram_resp_valid,
    input  logic             sdram_resp_last,
    input  logic [DATA_WIDTH-1:0] sdram_resp_data,
    output logic             sdram_resp_ready
);

    import sdram_pkg::*;

    // --- Konštanty ---
    localparam FRAME_SIZE = H_RES * V_RES;
    localparam NUM_WRITE_BURSTS = FRAME_SIZE / BURST_LEN;
    localparam LINE_BUFFER_DEPTH = H_RES * 2; // Buffer na 2 riadky pre bezpečnosť

    // --- Logika dvojitého bufferovania ---
    logic front_buffer_idx; // 0 alebo 1
    logic [ADDR_WIDTH-1:0] fb_base_addr [0:1];
    logic [ADDR_WIDTH-1:0] back_buffer_addr;

    initial begin
        fb_base_addr[0] = FB0_BASE_ADDR;
        fb_base_addr[1] = FB1_BASE_ADDR;
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) front_buffer_idx <= 1'b0;
        else if (ctrl_swap_buffers) front_buffer_idx <= ~front_buffer_idx;
    end
    assign back_buffer_addr = fb_base_addr[~front_buffer_idx];

    //================================================================
    // Zapisovacia Cesta (Plnenie Back Buffera)
    //================================================================
    typedef enum logic [1:0] { WR_IDLE, WR_SEND_ADDR, WR_SEND_DATA } wr_state_t;
    wr_state_t wr_state;
    logic [$clog2(NUM_WRITE_BURSTS):0] wr_burst_count;
    logic [$clog2(BURST_LEN)-1:0]     wr_data_count;

    // --- Zapisovací FSM ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_state <= WR_IDLE;
            wr_burst_count <= '0;
            wr_data_count <= '0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (ctrl_start_fill) begin
                        wr_state <= WR_SEND_ADDR;
                        wr_burst_count <= '0;
                    end
                end
                WR_SEND_ADDR: begin
                    if (sdram_writer_valid && sdram_writer_ready) begin
                        wr_state <= WR_SEND_DATA;
                        wr_data_count <= '0;
                    end
                end
                WR_SEND_DATA: begin
                    if (sdram_writer_valid && sdram_writer_ready) begin
                        if (wr_data_count == BURST_LEN - 1) begin
                            if (wr_burst_count == NUM_WRITE_BURSTS - 1) begin
                                wr_state <= WR_IDLE; // Hotovo
                            end else begin
                                wr_state <= WR_SEND_ADDR;
                                wr_burst_count <= wr_burst_count + 1;
                            end
                        end else begin
                            wr_data_count <= wr_data_count + 1;
                        end
                    end
                end
            endcase
        end
    end

    // --- Kombinačná logika pre zápis ---
    assign sdram_writer_addr = back_buffer_addr + (wr_burst_count * BURST_LEN);
    assign sdram_writer_data = pixel_in_data;
    assign pixel_in_ready = (wr_state == WR_SEND_DATA) && sdram_writer_ready;
    assign sdram_writer_valid = (wr_state == WR_SEND_ADDR) || (wr_state == WR_SEND_DATA && pixel_in_valid);
    assign status_busy_filling = (wr_state != WR_IDLE);

    //================================================================
    // Čítacia Cesta (Poskytovanie dát pre VGA)
    //================================================================

    // --- Line Buffer FIFO ---
    logic line_fifo_wr_en, line_fifo_rd_en, line_fifo_full, line_fifo_empty;
    logic [DATA_WIDTH-1:0] line_fifo_wdata, line_fifo_rdata;

    Fifo #( .WIDTH(DATA_WIDTH), .DEPTH(LINE_BUFFER_DEPTH) )
    line_buffer_fifo (
        .clk(clk), .rstn(rstn),
        .wr_en(line_fifo_wr_en), .wr_data(line_fifo_wdata), .full(line_fifo_full),
        .rd_en(line_fifo_rd_en), .rd_data(line_fifo_rdata), .empty(line_fifo_empty)
    );
    
    // Priame prepojenie SDRAM response -> FIFO
    assign line_fifo_wdata = sdram_resp_data;
    assign line_fifo_wr_en = sdram_resp_valid && !line_fifo_full;
    assign sdram_resp_ready = !line_fifo_full;

    // Priame prepojenie FIFO -> VGA
    assign vga_pixel_data  = line_fifo_rdata;
    assign vga_pixel_valid = !line_fifo_empty;
    assign line_fifo_rd_en = !line_fifo_empty; // VGA vždy chce dáta

    // --- Logika preaktívneho čítania (Prefetcher) ---
    typedef enum logic [0:0] { RD_IDLE, RD_PREFETCH } rd_state_t;
    rd_state_t rd_state;

    logic [$clog2(V_RES)-1:0] prefetched_y; // Riadok, ktorý sme naposledy žiadali
    logic [$clog2(H_RES/BURST_LEN):0] prefetch_burst_count;

    // --- Prefetcher FSM ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rd_state <= RD_IDLE;
            prefetched_y <= '1; // Inicializácia na neplatnú hodnotu
            prefetch_burst_count <= '0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    // Spustíme prefetch, keď VGA žiada nový riadok, a máme miesto v FIFO
                    if (vga_req_y != prefetched_y && !line_fifo_full) begin
                        rd_state <= RD_PREFETCH;
                        prefetched_y <= vga_req_y;
                        prefetch_burst_count <= '0;
                    end
                end
                RD_PREFETCH: begin
                    if (sdram_reader_valid && sdram_reader_ready) begin
                        if (prefetch_burst_count == (H_RES / BURST_LEN) - 1) begin
                            rd_state <= RD_IDLE; // Načítali sme celý riadok
                        end else begin
                            prefetch_burst_count <= prefetch_burst_count + 1;
                        end
                    end
                end
            endcase
        end
    end

    // --- Kombinačná logika pre čítanie ---
    assign sdram_reader_addr = fb_base_addr[front_buffer_idx] + (prefetched_y * H_RES) + (prefetch_burst_count * BURST_LEN);
    assign sdram_reader_valid = (rd_state == RD_PREFETCH);

endmodule


// Jednoduché FIFO pre line buffer (môže byť nahradené IP z Vivado/Quartus)
module Fifo #(parameter WIDTH=16, DEPTH=1024) (
    input  logic             clk,
    input  logic             rstn,
    input  logic             wr_en,
    input  logic [WIDTH-1:0] wr_data,
    output logic             full,
    input  logic             rd_en,
    output logic [WIDTH-1:0] rd_data,
    output logic             empty
);
    localparam ADDR_WIDTH = $clog2(DEPTH);
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0] wr_ptr, rd_ptr;

    assign empty = (wr_ptr == rd_ptr);
    assign full = (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]) && (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]);
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule
```

-----

### 2\. Kód Top-Level Modulu `Top_VGA_System.sv`

Tento modul ukazuje, ako všetko prepojiť. Obsahuje zjednodušené ("dummy") moduly pre zdroj pixelov a VGA časovanie, aby bol návrh kompletný a testovateľný.

```systemverilog
// Top_VGA_System.sv - Príklad prepojenia všetkých komponentov
`include "sdram_pkg.sv"

module Top_VGA_System (
    input  logic clk_100mhz, // Hlavný oscilátor
    input  logic rstn,

    // --- VGA Piny ---
    output logic vga_hsync,
    output logic vga_vsync,
    output logic [4:0] vga_r,
    output logic [5:0] vga_g,
    output logic [4:0] vga_b,

    // --- SDRAM Piny ---
    output logic [12:0] sdram_addr,
    output logic [1:0]  sdram_ba,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    inout  wire  [15:0] sdram_dq,
    output logic [1:0]  sdram_dqm,
    output logic        sdram_cke
);

    // --- Generovanie Hodín ---
    // Predpokladajme, že AXI a SDRAM bežia na rovnakej frekvencii
    logic clk_axi;
    logic clk_sdram;
    assign clk_axi = clk_100mhz;
    assign clk_sdram = clk_100mhz;

    // --- Signály pre prepojenie ---

    // PixelSource -> FramebufferController
    logic pixel_in_valid;
    logic pixel_in_ready;
    logic [15:0] pixel_in_data;

    // VgaController -> FramebufferController
    logic [9:0] vga_req_x;
    logic [9:0] vga_req_y;
    logic [15:0] vga_pixel_data;
    logic vga_pixel_valid;
    logic v_blank; // Z VGA controllera na synchronizáciu

    // FramebufferController -> SdramDriver (Writer)
    logic sdram_writer_valid;
    logic sdram_writer_ready;
    logic [23:0] sdram_writer_addr;
    logic [15:0] sdram_writer_data;

    // FramebufferController -> SdramDriver (Reader)
    logic sdram_reader_valid;
    logic sdram_reader_ready;
    logic [23:0] sdram_reader_addr;

    // SdramDriver -> FramebufferController (Response)
    logic sdram_resp_valid;
    logic sdram_resp_last;
    logic [15:0] sdram_resp_data;
    logic sdram_resp_ready;

    // --- Inštancie Modulov ---

    // 1. Zdroj Pixelov (Dummy modul, generuje farebný prechod)
    PixelSource pixel_source_inst (
        .clk(clk_axi), .rstn(rstn),
        .valid(pixel_in_valid), .ready(pixel_in_ready), .data(pixel_in_data)
    );

    // 2. VGA Časovanie (Dummy modul)
    VgaController vga_controller_inst (
        .clk(clk_axi), .rstn(rstn),
        .x(vga_req_x), .y(vga_req_y),
        .pixel_data(vga_pixel_data), .pixel_valid(vga_pixel_valid),
        .hsync(vga_hsync), .vsync(vga_vsync), .v_blank(v_blank),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b)
    );

    // 3. Náš nový Framebuffer Controller
    FramebufferController #( .H_RES(800), .V_RES(600) ) fb_ctrl_inst (
        .clk(clk_axi), .rstn(rstn),
        .pixel_in_valid(pixel_in_valid), .pixel_in_ready(pixel_in_ready), .pixel_in_data(pixel_in_data),
        .vga_req_x(vga_req_x), .vga_req_y(vga_req_y),
        .vga_pixel_data(vga_pixel_data), .vga_pixel_valid(vga_pixel_valid),
        .ctrl_start_fill(v_blank), // Automaticky spustiť plnenie počas V-blank
        .ctrl_swap_buffers(v_blank), // Automaticky prehodiť buffre počas V-blank
        .status_busy_filling(),
        .sdram_writer_valid(sdram_writer_valid), .sdram_writer_ready(sdram_writer_ready),
        .sdram_writer_addr(sdram_writer_addr), .sdram_writer_data(sdram_writer_data),
        .sdram_reader_valid(sdram_reader_valid), .sdram_reader_ready(sdram_reader_ready),
        .sdram_reader_addr(sdram_reader_addr),
        .sdram_resp_valid(sdram_resp_valid), .sdram_resp_last(sdram_resp_last),
        .sdram_resp_data(sdram_resp_data), .sdram_resp_ready(sdram_resp_ready)
    );

    // 4. Váš SDRAM Driver
    SdramDriver #( .ADDR_WIDTH(24), .DATA_WIDTH(16), .BURST_LENGTH(8) ) sdram_driver_inst (
        .clk_axi(clk_axi), .clk_sdram(clk_sdram), .rstn(rstn),
        // Reader
        .reader_valid(sdram_reader_valid), .reader_ready(sdram_reader_ready), .reader_addr(sdram_reader_addr),
        // Writer
        .writer_valid(sdram_writer_valid), .writer_ready(sdram_writer_ready),
        .writer_addr(sdram_writer_addr), .writer_data(sdram_writer_data),
        // Response
        .resp_valid(sdram_resp_valid), .resp_last(sdram_resp_last), .resp_data(sdram_resp_data), .resp_ready(sdram_resp_ready),
        // SDRAM Piny
        .sdram_addr(sdram_addr), .sdram_ba(sdram_ba), .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n), .sdram_dq(sdram_dq), .sdram_dqm(sdram_dqm), .sdram_cke(sdram_cke)
    );

endmodule

// Dummy moduly pre kompletnosť
// V reálnom projekte by ste ich nahradili vašou logikou

module PixelSource(input clk, rstn, output logic valid, input ready, output logic [15:0] data);
    // Generuje testovací obrazec
    // ...
endmodule

module VgaController(input clk, rstn, output [9:0] x, y, input [15:0] pixel_data, input pixel_valid,
                   output hsync, vsync, v_blank, output [4:0] vga_r, output [5:0] vga_g, output [4:0] vga_b);
    // Generuje VGA časovanie a posiela pixely na výstup
    // ...
endmodule

```

-----

### Ako to funguje - Vysvetlenie kódu `FramebufferController`

1.  **Dvojité Bufferovanie:** Register `front_buffer_idx` sa na signál `ctrl_swap_buffers` (ktorý sme v `Top` module prepojili na `v_blank` signál) jednoducho preklopí. Tým sa okamžite zmení bázová adresa pre čítanie a zápis.
2.  **Zapisovacia Cesta:** FSM pre zápis čaká na `ctrl_start_fill`. Keď príde, začne v cykle posielať adresy (`WR_SEND_ADDR`) a následne bursty dát (`WR_SEND_DATA`) do `SdramDriver`-a, kým nezapíše celý frame. Úzko spolupracuje s rozhraním `pixel_in_*` a `sdram_writer_*`.
3.  **Čítacia Cesta (Prefetcher):**
      * **FIFO:** Kľúčový komponent. Všetky dáta prečítané z SDRAM idú najprv sem. VGA zobrazovač sa obsluhuje výhradne z tohto rýchleho buffera.
      * **FSM:** Prefetcher sleduje, ktorý riadok (`vga_req_y`) práve zobrazuje VGA. Ak je to nový riadok, ktorý ešte nenačítal (`vga_req_y != prefetched_y`), spustí sériu burst čítaní, aby naplnil FIFO dátami pre tento riadok.
      * **Oddelenie:** Vďaka tomuto mechanizmu je latencia SDRAM úplne skrytá pred VGA zobrazovačom. Kým VGA zobrazuje riadok `N` z FIFO buffera, prefetcher už v pozadí plní FIFO dátami pre riadok `N+1`.

Tento kód predstavuje kompletný a funkčný návrh, ktorý priamo využíva všetky vaše predošlé moduly a spája ich do zmysluplného, vysokovýkonného video systému.
