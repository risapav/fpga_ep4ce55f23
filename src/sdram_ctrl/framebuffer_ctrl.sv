/**
 * @file        framebuffer_ctrl.sv
 * @brief       Double-Buffered Framebuffer Controller.
 * @details     Most medzi AXI Stream Video a SDRAM Controllerom.
 * - Input: AXI Stream Sink (Zápis do SDRAM).
 * - Output: AXI Stream Source (Čítanie z SDRAM pre displej).
 * - Podporuje Double Buffering (Ping-Pong) pre elimináciu tearingu.
 *
 * @param H_RES            Horizontálne rozlíšenie (pre generovanie TLAST).
 * @param V_RES            Vertikálne rozlíšenie.
 * @param BASE_ADDR_0      Adresa prvého buffera v SDRAM.
 * @param BASE_ADDR_1      Adresa druhého buffera v SDRAM.
 * @param ASYNC_FIFO_DEPTH Hĺbka interných FIFO (musí byť > 2 * BURST_LEN).
 */

`default_nettype none

`ifndef FRAMEBUFFER_CTRL_SV
`define FRAMEBUFFER_CTRL_SV

import sdram_pkg::*;
import video_pkg::*; // Predpokladá definíciu FRAME_PIXELS ak sa nepoužije param

module framebuffer_ctrl #(
    parameter int H_RES            = 800,
    parameter int V_RES            = 600,
    parameter int BASE_ADDR_0      = 32'h0000_0000,
    parameter int BASE_ADDR_1      = 32'h0010_0000, // Offset závisí od veľkosti framu
    parameter int ASYNC_FIFO_DEPTH = 256
)(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    // --- AXI Stream Interfaces ---
    axi4s_if.slave                        s_axis, // Input from Camera/Gen
    axi4s_if.master                       m_axis, // Output to Display

    // --- Interface to SDRAM_TOP (Controller) ---
    // Write Command
    output sdram_cmd_t                    sdram_wr_cmd_o,
    output logic                     sdram_wr_valid_o,
    input  logic                     sdram_wr_ready_i,
    
    // Read Command
    output sdram_cmd_t                    sdram_rd_cmd_o,
    output logic                     sdram_rd_valid_o,
    input  logic                     sdram_rd_ready_i,
    
    // Write Data
    output logic [15:0]              sdram_wdata_o,
    output logic [1:0]               sdram_wdata_be_o,
    output logic                     sdram_wdata_valid_o,
    input  logic                     sdram_wdata_ready_i,
    
    // Read Data
    input  logic [15:0]              sdram_rdata_i,
    input  logic                     sdram_rdata_valid_i
);

    // -------------------------------------------------------------------------
    // 1. Konštanty a Signály
    // -------------------------------------------------------------------------
    localparam int FramePixels    = H_RES * V_RES;
    localparam int FifoAddrWidth  = $clog2(ASYNC_FIFO_DEPTH);
    localparam int BurstLen       = sdram_pkg::BURST_LEN;

    // Buffer Management
    logic        writer_active_buf; // 0 or 1
    logic [31:0] writer_base_addr;
    logic [31:0] reader_base_addr;
    logic        frame_done_pulse;

    // -------------------------------------------------------------------------
    // 2. Buffer Swapping Logic (Ping-Pong)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            writer_active_buf <= 0;
        end else begin
            // Swap na konci zápisu framu (keď writer zapíše posledný pixel)
            if (frame_done_pulse) begin
                writer_active_buf <= ~writer_active_buf;
            end
        end
    end

    // Adresy: Ak Writer píše do 0, Reader číta z 1 a naopak.
    assign writer_base_addr = (writer_active_buf == 0) ? BASE_ADDR_0 : BASE_ADDR_1;
    assign reader_base_addr = (writer_active_buf == 0) ? BASE_ADDR_1 : BASE_ADDR_0;

    // =========================================================================
    // 3. WRITER PATH (AXI Stream Sink -> FIFO -> SDRAM Write)
    // =========================================================================
    
    // FIFO Signály
    logic [15:0]            wr_fifo_dout;
    logic                   wr_fifo_empty, wr_fifo_full;
    logic                   wr_fifo_rd_en;
    logic [FifoAddrWidth:0] wr_fifo_level;

    // Inštancia FIFO (Write Buffer)
    // Ukladá dáta z kamery, kým ich nie je dosť na SDRAM Burst
    sync_fifo #(
        .DATA_WIDTH(16), 
        .BE_WIDTH(2), // Dummy BE (nepoužívame na vstupe z AXI, ale FIFO to má)
        .ADDR_WIDTH(FifoAddrWidth)
    ) u_wr_fifo (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .wr_en_i        (s_axis.TVALID && s_axis.TREADY),
        .wr_data_i      (s_axis.TDATA),
        .wr_be_i        (2'b11), // Všetky bajty platné
        .wr_full_o      (wr_fifo_full),
        .wr_overflow_o  (),
        .rd_en_i        (wr_fifo_rd_en),
        .rd_data_o      (wr_fifo_dout),
        .rd_be_o        (),
        .rd_empty_o     (wr_fifo_empty),
        .rd_underflow_o (),
        .level_o        (wr_fifo_level)
    );
    
    assign s_axis.TREADY = !wr_fifo_full;

    // Writer FSM / Logic
    logic [31:0] wr_pixel_cnt;
    logic [31:0] wr_current_addr;
    sdram_addr_t wr_sdram_addr_struct;
    
    // Adresový prekladač (Linear -> Bank/Row/Col)
    fb_addr_translator u_wr_trans (
        .linear_addr_i (wr_current_addr),
        .sdram_addr_o  (wr_sdram_addr_struct)
    );

    assign wr_current_addr = writer_base_addr + wr_pixel_cnt;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_pixel_cnt        <= 0;
            sdram_wr_valid_o    <= 0;
            sdram_wr_cmd_o      <= '0;
            frame_done_pulse    <= 0;
        end else begin
            // Reset pulzov
            sdram_wr_valid_o <= 0;
            frame_done_pulse <= 0;
            
            // Re-sync na začiatok framu (pomocou TUSER z kamery)
            if (s_axis.TVALID && s_axis.TREADY && s_axis.TUSER[0]) begin
                wr_pixel_cnt <= 0; 
            end

            // 1. Issue Command Logic
            // Ak máme vo FIFO aspoň BURST_LEN dát a SDRAM CMD ready
            if (wr_fifo_level >= BurstLen && sdram_wr_ready_i && !sdram_wr_valid_o) begin
                // Odošli príkaz
                sdram_wr_cmd_o.addr           <= wr_sdram_addr_struct;
                sdram_wr_cmd_o.rw             <= 1'b1; // Write
                sdram_wr_cmd_o.auto_precharge <= 1'b0; 
                sdram_wr_valid_o              <= 1'b1;
                
                // Update počítadla pixelov
                if (wr_pixel_cnt + BurstLen >= FramePixels) begin
                    wr_pixel_cnt     <= 0; // Wrap around (Frame End)
                    frame_done_pulse <= 1; // Signal buffer swap
                end else begin
                    wr_pixel_cnt     <= wr_pixel_cnt + BurstLen;
                end
            end
        end
    end

    // Data Streaming Logic (Burst Data Pump)
    logic [$clog2(BurstLen):0] wdata_burst_cnt;
    logic                      wdata_busy;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wdata_busy          <= 0;
            wdata_burst_cnt     <= 0;
            wr_fifo_rd_en       <= 0;
            sdram_wdata_valid_o <= 0;
            sdram_wdata_o       <= '0;
        end else begin
            // Trigger: Keď odošleme príkaz, spustíme data burst
            if (sdram_wr_valid_o && sdram_wr_ready_i) begin
                wdata_busy      <= 1;
                wdata_burst_cnt <= BurstLen;
            end

            if (wdata_busy) begin
                if (sdram_wdata_ready_i) begin
                    // Čítame z FIFO
                    wr_fifo_rd_en       <= 1; 
                    sdram_wdata_valid_o <= 1;
                    // V sync_fifo sme použili asynchrónne čítanie pre dáta, ale logiku rd_en synchrónne.
                    // Pre bezpečnosť: Ak FIFO vracia dáta v rovnakom takte ako rd_en (FWFT), toto je OK.
                    // Ak FIFO má latenciu 1 takt, dáta budú oneskorené. 
                    // SDRAM kontroler očakáva dáta spolu s valid signálom.
                    // Tu predpokladáme, že sync_fifo v tomto projekte má 'assign data = mem[...]'.
                    sdram_wdata_o       <= wr_fifo_dout; 
                    
                    wdata_burst_cnt <= wdata_burst_cnt - 1;
                    if (wdata_burst_cnt == 1) begin
                        wdata_busy    <= 0;
                        wr_fifo_rd_en <= 0;
                    end
                end else begin
                    // Wait state
                    wr_fifo_rd_en       <= 0;
                    sdram_wdata_valid_o <= 0;
                end
            end else begin
                sdram_wdata_valid_o <= 0;
                wr_fifo_rd_en       <= 0;
            end
        end
    end
    
    assign sdram_wdata_be_o = 2'b11; // 16-bit write always full

    // =========================================================================
    // 4. READER PATH (SDRAM Read -> FIFO -> AXI Stream Source)
    // =========================================================================

    // FIFO Signály
    logic [15:0]            rd_fifo_din;
    logic                   rd_fifo_wr_en;
    logic                   rd_fifo_full, rd_fifo_empty;
    logic [FifoAddrWidth:0] rd_fifo_level;
    
    // SDRAM Read Data -> FIFO Input
    assign rd_fifo_din   = sdram_rdata_i;
    assign rd_fifo_wr_en = sdram_rdata_valid_i;

    // Inštancia FIFO (Read Buffer)
    sync_fifo #(
        .DATA_WIDTH(16), 
        .BE_WIDTH(2), 
        .ADDR_WIDTH(FifoAddrWidth)
    ) u_rd_fifo (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .wr_en_i        (rd_fifo_wr_en),
        .wr_data_i      (rd_fifo_din),
        .wr_be_i        (2'b00),
        .wr_full_o      (rd_fifo_full),
        .wr_overflow_o  (),
        // Čítame, ak AXI Slave je ready a my máme dáta
        .rd_en_i        (m_axis.TREADY && !rd_fifo_empty),
        .rd_data_o      (m_axis.TDATA),
        .rd_be_o        (),
        .rd_empty_o     (rd_fifo_empty),
        .rd_underflow_o (),
        .level_o        (rd_fifo_level)
    );

    assign m_axis.TVALID = !rd_fifo_empty;
    
    // --- TLAST/TUSER Generation Logic for AXI Output ---
    // Potrebujeme sledovať, ktorý pixel práve posielame von z FIFO.
    logic [31:0] axis_out_pixel_cnt;
    logic [31:0] axis_out_x_cnt;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            axis_out_pixel_cnt <= 0;
            axis_out_x_cnt     <= 0;
        end else begin
            if (m_axis.TVALID && m_axis.TREADY) begin
                // Inkrementácia počítadiel pri úspešnom prenose
                if (axis_out_pixel_cnt == FramePixels - 1) begin
                    axis_out_pixel_cnt <= 0;
                    axis_out_x_cnt     <= 0;
                end else begin
                    axis_out_pixel_cnt <= axis_out_pixel_cnt + 1;
                    
                    if (axis_out_x_cnt == H_RES - 1)
                        axis_out_x_cnt <= 0;
                    else
                        axis_out_x_cnt <= axis_out_x_cnt + 1;
                end
            end
        end
    end

    assign m_axis.TLAST    = (axis_out_x_cnt == H_RES - 1);
    assign m_axis.TUSER[0] = (axis_out_pixel_cnt == 0);
    
    // Fixné signály
    assign m_axis.TKEEP = 2'b11;
    assign m_axis.TID   = '0;
    assign m_axis.TDEST = '0;

    // --- Reader Controller Logic (Prefetching from SDRAM) ---
    logic [31:0] rd_pixel_cnt;
    logic [31:0] rd_current_addr;
    sdram_addr_t rd_sdram_addr_struct;

    fb_addr_translator u_rd_trans (
        .linear_addr_i (rd_current_addr),
        .sdram_addr_o  (rd_sdram_addr_struct)
    );
    
    assign rd_current_addr = reader_base_addr + rd_pixel_cnt;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_pixel_cnt     <= 0;
            sdram_rd_valid_o <= 0;
            sdram_rd_cmd_o   <= '0;
        end else begin
            sdram_rd_valid_o <= 0;
            
            // Prefetch Logic:
            // Ak je vo FIFO miesto pre aspoň jeden BURST a SDRAM CMD je ready
            // Space = DEPTH - level.
            if ((ASYNC_FIFO_DEPTH - rd_fifo_level) >= BurstLen && sdram_rd_ready_i && !sdram_rd_valid_o) begin
                
                // Odošli Read Command
                sdram_rd_cmd_o.addr           <= rd_sdram_addr_struct;
                sdram_rd_cmd_o.rw             <= 1'b0; // Read
                sdram_rd_cmd_o.auto_precharge <= 1'b0;
                sdram_rd_valid_o              <= 1'b1;

                // Update Address Counter
                if (rd_pixel_cnt + BurstLen >= FramePixels) begin
                    rd_pixel_cnt <= 0;
                end else begin
                    rd_pixel_cnt <= rd_pixel_cnt + BurstLen;
                end
            end
        end
    end

endmodule

`endif // FRAMEBUFFER_CTRL_SV

`default_nettype wire
