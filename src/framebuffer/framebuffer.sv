`ifndef FRAMEBUFFER_CTRL_SV
`define FRAMEBUFFER_CTRL_SV

(* default_nettype = "none" *)
import vga_pkg::*;
import axi_pkg::*;
import axis_streamer_pkg::*;
//`include "sdram_driver.sv" // Vložíme driver priamo sem pre jednoduchosť

module framebuffer_ctrl #(
    parameter int H_RES = 800,
    parameter int V_RES = 600,
    // Parametre pre SDRAM časovanie (môžu sa líšiť podľa čipu)
    parameter int tRP        = 3,
    parameter int tRCD       = 3,
    parameter int tWR        = 2,
    parameter int tRFC       = 9,
    parameter int tRAS       = 7,
    parameter int CAS_LATENCY= 3
)(
    // --- Hodinové domény a resety ---
    input  logic axi_clk_i,
    input  logic axi_rst_ni,
    input  logic sdram_clk_i,
    input  logic sdram_rst_ni,

    // --- Video Stream Porty ---
    axi4s_if.slave  s_axis_video_in,
    axi4s_if.master m_axis_video_out,

    // --- SDRAM Porty ---
    output logic [12:0]  sdram_addr,
    output logic [1:0]   sdram_ba,
    output logic         sdram_cs_n,
    output logic         sdram_ras_n,
    output logic         sdram_cas_n,
    output logic         sdram_we_n,
    inout  wire  [15:0]  sdram_dq,
    output logic [1:0]   sdram_dqm,
    output logic         sdram_cke,
    output logic         sdram_clk,

    // --- Diagnostika ---
    output logic [7:0] debug_led_o
);

    // =========================================================================
    // Konfigurácia Double Bufferingu
    // =========================================================================
    localparam int ADDR_WIDTH = 24;
    localparam int FRAME_SIZE = H_RES * V_RES;
    localparam logic [ADDR_WIDTH-1:0] BUFFER_0_BASE_ADDR = 0;
    localparam logic [ADDR_WIDTH-1:0] BUFFER_1_BASE_ADDR = FRAME_SIZE;

    // Register, ktorý určuje, do ktorého bufferu sa zapisuje (0 alebo 1)
    logic write_buffer_is_0_reg;
    logic [ADDR_WIDTH-1:0] write_buffer_base_addr;
    logic [ADDR_WIDTH-1:0] read_buffer_base_addr;

    // =========================================================================
    // Inštancia SDRAM Drivera
    // =========================================================================
    // Signály prepojenia na driver
    logic                  sdram_reader_valid, sdram_reader_ready;
    logic [ADDR_WIDTH-1:0] sdram_reader_addr;
    logic                  sdram_writer_valid, sdram_writer_ready;
    logic [ADDR_WIDTH-1:0] sdram_writer_addr;
    logic [15:0]           sdram_writer_data;
    logic                  sdram_resp_valid, sdram_resp_last;
    logic [15:0]           sdram_resp_data;

    SdramDriver #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(16),
        .BURST_LENGTH(8),
        .tRP(tRP), .tRCD(tRCD), .tWR(tWR), .tRFC(tRFC), .tRAS(tRAS), .CAS_LATENCY(CAS_LATENCY)
    ) u_sdram_driver (
        .clk_axi(axi_clk_i),
        .clk_sdram(sdram_clk_i),
        .rstn_axi(axi_rst_ni),
        .rstn_sdram(sdram_rst_ni),

        // Reader interface
        .reader_valid(sdram_reader_valid),
        .reader_ready(sdram_reader_ready),
        .reader_addr(sdram_reader_addr),

        // Writer interface
        .writer_valid(sdram_writer_valid),
        .writer_ready(sdram_writer_ready),
        .writer_addr(sdram_writer_addr),
        .writer_data(sdram_writer_data),
        .writer_dqm_i(2'b00), // DQM nevyužívame

        // Read response
        .resp_valid(sdram_resp_valid),
        .resp_last(sdram_resp_last),
        .resp_data(sdram_resp_data),
        .resp_ready(m_axis_video_out.TREADY),

        // Error monitoring
        .error_overflow_o(debug_led_o[6]),
        .error_underflow_o(debug_led_o[7]),
        .error_clear_i(1'b0),

        // SDRAM physical pins
        .sdram_addr,
        .sdram_ba,
        .sdram_cs_n,
        .sdram_ras_n,
        .sdram_cas_n,
        .sdram_we_n,
        .sdram_dq,
        .sdram_dqm,
        .sdram_cke,

        //diagnostika
        .controller_state_o(debug_led_o[4:0])
    );
    // Priame priradenie hodín na SDRAM pin
    assign sdram_clk = sdram_clk_i;


    // =========================================================================
    // Logika Zapisovania (Writer) - (AXI Stream -> SDRAM)
    // =========================================================================
    logic [$clog2(H_RES)-1:0] wr_x_cnt;
    logic [$clog2(V_RES)-1:0] wr_y_cnt;
    logic frame_write_done;

    always_ff @(posedge axi_clk_i or negedge axi_rst_ni) begin
        if (!axi_rst_ni) begin
            wr_x_cnt <= '0;
            wr_y_cnt <= '0;
            write_buffer_is_0_reg <= 1'b1; // Začíname zapisovať do buffera 0
        end else begin
            // Logika počítadiel X a Y pre zápis
            if (s_axis_video_in.TVALID && s_axis_video_in.TREADY) begin
                if (wr_x_cnt == H_RES - 1) begin
                    wr_x_cnt <= 0;
                    if (wr_y_cnt == V_RES - 1) begin
                        wr_y_cnt <= 0;
                    end else begin
                        wr_y_cnt <= wr_y_cnt + 1;
                    end
                end else begin
                    wr_x_cnt <= wr_x_cnt + 1;
                end
            end

            // Prehodenie bufferov po dokončení zápisu snímku
            if (frame_write_done) begin
                write_buffer_is_0_reg <= ~write_buffer_is_0_reg;
            end
        end
    end

    assign frame_write_done = s_axis_video_in.TVALID && s_axis_video_in.TREADY && s_axis_video_in.TLAST;

    // Kombinačná logika pre Writer
    assign sdram_writer_addr = write_buffer_base_addr + (wr_y_cnt * H_RES) + wr_x_cnt;
    assign sdram_writer_data = s_axis_video_in.TDATA;

    // Handshake
    assign sdram_writer_valid = s_axis_video_in.TVALID;
    assign s_axis_video_in.TREADY = sdram_writer_ready;

    // =========================================================================
    // Logika Čítania (Reader) - (SDRAM -> AXI Stream)
    // =========================================================================
    logic [$clog2(H_RES)-1:0] rd_x_cnt;
    logic [$clog2(V_RES)-1:0] rd_y_cnt;
    logic reading_active;

    always_ff @(posedge axi_clk_i or negedge axi_rst_ni) begin
        if (!axi_rst_ni) begin
            rd_x_cnt <= '0;
            rd_y_cnt <= '0;
            reading_active <= 1'b0;
        end else begin
            // Aktivujeme čítanie, keď je downstream modul pripravený po prvýkrát
            if (m_axis_video_out.TREADY && !reading_active) begin
                reading_active <= 1'b1;
            end

            // Logika počítadiel X a Y pre čítanie
            // Posúvame sa na ďalší pixel, keď boli aktuálne dáta úspešne poslané
            if (m_axis_video_out.TVALID && m_axis_video_out.TREADY) begin
                if (rd_x_cnt == H_RES - 1) begin
                    rd_x_cnt <= 0;
                    if (rd_y_cnt == V_RES - 1) begin
                        rd_y_cnt <= 0;
                        reading_active <= 1'b0; // Dokončili sme čítanie, čakáme na ďalší frame
                    end else begin
                        rd_y_cnt <= rd_y_cnt + 1;
                    end
                end else begin
                    rd_x_cnt <= rd_x_cnt + 1;
                end
            end
        end
    end

    // Kombinačná logika pre Reader
    assign sdram_reader_addr = read_buffer_base_addr + (rd_y_cnt * H_RES) + rd_x_cnt;

    // Handshake
    assign sdram_reader_valid = reading_active && !sdram_resp_valid; // Žiadame o dáta, ak sme aktívni a nemáme platné dáta

    // Výstupný stream je priamo riadený odpoveďou z SDRAM drivera
    assign m_axis_video_out.TVALID = sdram_resp_valid;
    assign m_axis_video_out.TDATA  = sdram_resp_data;
    assign m_axis_video_out.TLAST  = (rd_x_cnt == H_RES - 1) && (rd_y_cnt == V_RES - 1);
    assign m_axis_video_out.TUSER  = 1'b0; // TUSER sa zvyčajne nepoužíva pre VGA


    // =========================================================================
    // Logika výberu bufferov
    // =========================================================================
    assign write_buffer_base_addr = (write_buffer_is_0_reg) ? BUFFER_0_BASE_ADDR : BUFFER_1_BASE_ADDR;
    assign read_buffer_base_addr  = (write_buffer_is_0_reg) ? BUFFER_1_BASE_ADDR : BUFFER_0_BASE_ADDR;


    // =========================================================================
    // Diagnostika
    // =========================================================================
/*
    assign debug_led_o[0] = s_axis_video_in.TVALID;
    assign debug_led_o[1] = s_axis_video_in.TREADY;
    assign debug_led_o[2] = m_axis_video_out.TVALID;
    assign debug_led_o[3] = m_axis_video_out.TREADY;
    assign debug_led_o[4] = write_buffer_is_0_reg;
    assign debug_led_o[5] = reading_active;
*/

    assign debug_led_o[5] = reading_active;

endmodule

`endif