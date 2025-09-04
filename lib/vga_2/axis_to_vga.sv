// axistream_to_vga.sv - Vylepšený a konzistentný modul
//
// Verzia 2.2 - Plná konzistentnosť s finálnym axi_pkg
//
// Kľúčové zmeny:
// 1. OPRAVA (Konzistentnosť): Pridaný nevyhnutný `import axi_pkg::*;`.
// 2. VYLEPŠENIE (Štruktúra): Odstránená lokálna definícia `fifo_pixel_data_t`.
//    Modul teraz používa centrálnu štruktúru `axi4s_payload_t` z balíčka `axi_pkg`.
// 3. OPRAVA (Názvoslovie): Všetky signály AXI-Stream sú teraz písané veľkými
//    písmenami (TVALID, TDATA, atď.), aby zodpovedali finálnemu balíčku.

`default_nettype none

// Potrebné importy balíčkov
import vga_pkg::*;
import axi_pkg::*;

module AxiStreamToVGA #(
    parameter FIFO_DEPTH = 1024
)(
    input  logic axi_clk,
    input  logic axi_rstn,
    input  logic pix_clk,
    input  logic pix_rstn,

    // AXI Stream interface (slave prijímač)
    axi4s_if.slave s_axis,

    // VGA časovanie
    input  vga_pkg::line_t h_line,
    input  vga_pkg::line_t v_line,

    // Výstup na VGA konektor
    output vga_pkg::VGA_565_output_t vga_out,

    output logic [31:0] pixel_count // Debug počítadlo
);

    // -- FIFO rozhranie
    // Používame typ `axi4s_payload_t` priamo z balíčka axi_pkg
    logic           wr_en;
    axi4s_payload_t fifo_wr_data;
    logic           full;

    logic           rd_en;
    axi4s_payload_t fifo_rd_data;
    logic           empty;

    // -- Zápis dát do FIFO – AXI domain
    assign wr_en = s_axis.TVALID && !full;
    // Priame priradenie signálov do štruktúry
    assign fifo_wr_data = '{TUSER: s_axis.TUSER, TLAST: s_axis.TLAST, TDATA: s_axis.TDATA};
    assign s_axis.TREADY = !full;

    // Počítanie pixelov zapísaných do FIFO
    always_ff @(posedge axi_clk) begin
        if (!axi_rstn) begin
            pixel_count <= 32'd0;
        end else if (wr_en) begin
            pixel_count <= pixel_count + 1;
        end
    end

    // -- Asynchrónny FIFO
    AsyncFIFO #(
        .DATA_WIDTH($bits(axi4s_payload_t)), // Šírka sa automaticky určí zo štruktúry
        .DEPTH(FIFO_DEPTH)
    ) fifo_inst (
        .wr_clk(axi_clk),
        .wr_rstn(axi_rstn),
        .wr_en(wr_en),
        .wr_data(fifo_wr_data),
        .full(full),
        .overflow(),

        .rd_clk(pix_clk),
        .rd_rstn(pix_rstn),
        .rd_en(rd_en),
        .rd_data(fifo_rd_data),
        .empty(empty),
        .underflow()
    );

    // -- VGA časovanie
    position_t pos;
    signal_t   signal;

    Vga_timing vga_timing_inst (
        .clk_pix(pix_clk),
        .rstn(pix_rstn),
        .h_line(h_line),
        .v_line(v_line),
        .pos(pos),
        .signal(signal)
    );

    // -- Logika čítania z FIFO a detekcia podtečenia
    logic underflow_detected;
    assign underflow_detected = signal.active && empty;
    assign rd_en = signal.active && !empty;

    // -- Registrovanie pixelu z FIFO
    axi4s_payload_t pixel_reg;

    always_ff @(posedge pix_clk) begin
        if (!pix_rstn) begin
            pixel_reg <= '{default:0};
        end else if (rd_en) begin
            pixel_reg <= fifo_rd_data;
        end
    end

    // -- Finálny VGA výstup s ochranou proti podtečeniu
    logic [15:0] pixel_color;
    
    always_comb begin
        if (signal.active) begin
            if (underflow_detected) begin
                pixel_color = PURPLE; // Debug farba pre underflow
            end else begin
                // Príklad logiky: TUSER prepíše farbu na bielu
                if (pixel_reg.TUSER) begin
                    pixel_color = WHITE;
                end else begin
                    pixel_color = pixel_reg.TDATA;
                end
            end
        end else begin
            pixel_color = BLACK;
        end
    end

    assign vga_out.red = pixel_color[15:11];
    assign vga_out.grn = pixel_color[10:5];
    assign vga_out.blu = pixel_color[4:0];
    assign vga_out.hs  = signal.h_sync;
    assign vga_out.vs  = signal.v_sync;

endmodule
