//navrhneme modul
// Documents
// FramebufferController.sv
// Autor: Vasilyev Denis
// Popis: Modul na riadenie dvojitého framebufferu s AXI rozhraním k SDRAM
//         Podporuje režimy 800x600 @60Hz, 640x480 @60Hz
//         a jednoduché FIFO pre line buffer
// Verzia: 1.0
// Dátum: 2024-06-15
module FramebufferController #(
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter FB0_BASE_ADDR = 24'h000000,
    parameter FB1_BASE_ADDR = 24'h080000
)(
    input  logic clk, // Predpokladáme jednu hodinovú doménu (clk_axi z Drivera)
    input  logic rstn,

    // --- Rozhranie pre vstup pixelov (od zdroja obrazu) ---
    input  logic             pixel_in_valid_i,
    output logic             pixel_in_ready_o,
    input  logic [15:0]      pixel_in_data_i, // RGB 565

    // --- Rozhranie pre VGA Zobrazovač ---
    input  logic [9:0]       vga_req_x_i, // Horizontálna pozícia (0-799)
    input  logic [9:0]       vga_req_y_i, // Vertikálna pozícia (0-599)
    output logic [15:0]      vga_pixel_data_o,
    output logic             vga_pixel_valid_o,

    // --- Riadiace signály ---
    input  logic             ctrl_start_fill_i, // Impulz na spustenie plnenia back buffera
    input  logic             ctrl_swap_buffers_i, // Impulz na prehodenie bufferov
    output logic             status_busy_filling_o, // Indikátor, že prebieha plnenie

    // --- Rozhranie k SdramDriver (AXI strana) ---
    // Writer port
    output logic             sdram_writer_valid_o,
    input  logic             sdram_writer_ready_i,
    output logic [23:0]      sdram_writer_addr_o,
    output logic [15:0]      sdram_writer_data_o,

    // Reader port
    output logic             sdram_reader_valid_o,
    input  logic             sdram_reader_ready_i,
    output logic [23:0]      sdram_reader_addr_o,

    // Read response port
    input  logic             sdram_resp_valid_i,
    input  logic             sdram_resp_last_i,
    input  logic [15:0]      sdram_resp_data_i,
    output logic             sdram_resp_ready_o
);

   import sdram_pkg::*;

    // --- Konštanty ---
    localparam FRAME_SIZE = H_RES * V_RES;
    localparam int NUM_WRITE_BURSTS = (FRAME_SIZE + BURST_LEN - 1) / BURST_LEN;

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
        else if (ctrl_swap_buffers_i) front_buffer_idx <= ~front_buffer_idx;
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
                    if (ctrl_start_fill_i) begin
                        wr_state <= WR_SEND_ADDR;
                        wr_burst_count <= '0;
                    end
                end
                WR_SEND_ADDR: begin
                    if (sdram_writer_valid_o && sdram_writer_ready_i) begin
                        wr_state <= WR_SEND_DATA;
                        wr_data_count <= '0;
                    end
                end
                WR_SEND_DATA: begin
                    if (sdram_writer_valid_o && sdram_writer_ready_i) begin
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
    assign sdram_writer_addr_o = back_buffer_addr + (wr_burst_count * BURST_LEN);
    assign sdram_writer_data_o = pixel_in_data_i;
    assign pixel_in_ready_o = (wr_state == WR_SEND_DATA) && sdram_writer_ready_i;
    assign sdram_writer_valid_o = (wr_state == WR_SEND_ADDR) || (wr_state == WR_SEND_DATA && pixel_in_valid_i);
    assign status_busy_filling_o = (wr_state != WR_IDLE);

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
    assign line_fifo_wdata = sdram_resp_data_i;
    assign line_fifo_wr_en = sdram_resp_valid_i && !line_fifo_full;
    assign sdram_resp_ready_o = !line_fifo_full;

    // Priame prepojenie FIFO -> VGA
    assign vga_pixel_data_o  = line_fifo_rdata;
    assign vga_pixel_valid_o = !line_fifo_empty;
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
                    if (vga_req_y_i != prefetched_y && !line_fifo_full) begin
                        rd_state <= RD_PREFETCH;
                        prefetched_y <= vga_req_y_i;
                        prefetch_burst_count <= '0;
                    end
                end
                RD_PREFETCH: begin
                    if (sdram_reader_valid_o && sdram_reader_ready_i) begin
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
    assign sdram_reader_addr_o = fb_base_addr[front_buffer_idx] + (prefetched_y * H_RES) + (prefetch_burst_count * BURST_LEN);
    assign sdram_reader_valid_o = (rd_state == RD_PREFETCH);

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