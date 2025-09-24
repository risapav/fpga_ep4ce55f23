module AxiStreamSdramVgaTopDualBuffer #(
  parameter DATA_WIDTH = 16,
  parameter ADDR_WIDTH = 24,
  parameter BUFFER_SIZE = 1024*768 // počet pixelov na buffer (napr. 640*480)
)(
  input  logic axi_clk,
  input  logic axi_rstn,
  input  logic sdram_clk,
  input  logic sdram_rstn,
  input  logic pix_clk,
  input  logic pix_rstn,

  // AXI Stream input (write path)
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic                  s_axis_tlast,

  // AXI Stream output (read path)
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic                  m_axis_tlast,

  // VGA output signals
  output logic [4:0] vga_red,
  output logic [5:0] vga_green,
  output logic [4:0] vga_blue,
  output logic       vga_hs,
  output logic       vga_vs
);

  typedef enum logic {BUF0 = 0, BUF1 = 1} buf_sel_e;

  // --- Buffer select signals ---
  logic write_buffer_select;   // 0 alebo 1
  logic read_buffer_select;    // opačný k write_buffer_select

  // Počiatočný stav
  initial begin
    write_buffer_select = BUF0;
    read_buffer_select = BUF1;
  end

  // Signály pre prepínanie bufferov (zjednodušené)
  logic swap_buffers_req;    // vyvola prepnutie
  logic swap_buffers_ack;

  // Stavový stroj pre správu bufferov
  always_ff @(posedge axi_clk or negedge axi_rstn) begin
    if(!axi_rstn) begin
      write_buffer_select <= BUF0;
      read_buffer_select <= BUF1;
      swap_buffers_ack <= 0;
    end else begin
      if(swap_buffers_req) begin
        write_buffer_select <= ~write_buffer_select;
        read_buffer_select <= ~read_buffer_select;
        swap_buffers_ack <= 1;
      end else begin
        swap_buffers_ack <= 0;
      end
    end
  end

  //---------------------------------------------------
  // Adresy bufferov v SDRAM

  localparam BUFFER0_BASE_ADDR = 0;
  localparam BUFFER1_BASE_ADDR = BUFFER_SIZE;

  // Vyber adresy pre zápis a čítanie podľa buffer_select
  logic [ADDR_WIDTH-1:0] axi_write_base_addr;
  logic [ADDR_WIDTH-1:0] axi_read_base_addr;

  assign axi_write_base_addr = (write_buffer_select == BUF0) ? BUFFER0_BASE_ADDR : BUFFER1_BASE_ADDR;
  assign axi_read_base_addr  = (read_buffer_select  == BUF0) ? BUFFER0_BASE_ADDR : BUFFER1_BASE_ADDR;

  //---------------------------------------------------
  // AXI Stream Write path: axi_clk -> FIFO -> sdram_clk -> SDRAM (write_buffer_select)

  AxiStreamToSdramWrite #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .FIFO_DEPTH(1024)
  ) axi_write_inst (
    .axi_clk(axi_clk),
    .axi_rstn(axi_rstn),
    .sdram_clk(sdram_clk),
    .sdram_rstn(sdram_rstn),

    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),

    .sdram_cmd_valid(sdram_cmd_valid),
    .sdram_cmd_rw(sdram_cmd_rw),
    .sdram_cmd_addr(sdram_cmd_addr),
    .sdram_cmd_wdata(sdram_cmd_wdata),
    .sdram_cmd_ready(sdram_cmd_ready),

    .sdram_resp_valid(sdram_resp_valid),
    .sdram_resp_ready(sdram_resp_ready),

    // pridaná offsetová adresa
    .base_addr(axi_write_base_addr),

    // signál prepnutia bufferu z axi_write_inst späť do top-u
    .buffer_full(swap_buffers_req)
  );

  //---------------------------------------------------
  // AXI Stream Read path: SDRAM -> FIFO -> axi_clk -> AXI Stream output (read_buffer_select)

  SdramToAxiStreamRead #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .FIFO_DEPTH(1024)
  ) axi_read_inst (
    .axi_clk(axi_clk),
    .axi_rstn(axi_rstn),
    .sdram_clk(sdram_clk),
    .sdram_rstn(sdram_rstn),

    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),

    .sdram_cmd_valid(sdram_cmd_valid),
    .sdram_cmd_rw(sdram_cmd_rw),
    .sdram_cmd_addr(sdram_cmd_addr),
    .sdram_cmd_rdata(sdram_cmd_rdata),
    .sdram_resp_valid(sdram_resp_valid),
    .sdram_resp_ready(sdram_resp_ready),

    // pridaná offsetová adresa pre čítanie
    .base_addr(axi_read_base_addr)
  );

  //---------------------------------------------------
  // AXI Stream output -> FIFO CDC -> pix_clk -> VGA (tak ako predtým)

// Prepokladám že VGA modul a vga_pkg sú už k dispozícii (ako si zadal)
// Najskôr konvertujeme AXI Stream dátový tok na VGA stream dátový tok

import vga_pkg::*;

logic [15:0] vga_pixel_data;
logic       vga_pixel_valid;
logic       vga_pixel_ready;
logic       vga_pixel_sof, vga_pixel_eol;

vstream_t vga_stream;

// Pripojenie AXI stream čítania do VGA stream

assign vga_pixel_data = m_axis_tdata;
assign vga_pixel_valid = m_axis_tvalid;
assign m_axis_tready = vga_pixel_ready;
assign vga_stream.data = vga_pixel_data;
assign vga_stream.sof = vga_pixel_sof;
assign vga_stream.eol = vga_pixel_eol;

// potrebujeme posun do pix_clk domény, takže ďalšie FIFO CDC:

logic fifo_wr_en_vga, fifo_rd_en_vga;
logic [15:0] fifo_din_vga, fifo_dout_vga;
logic fifo_full_vga, fifo_empty_vga;

// fifo: axi_clk -> pix_clk

DualClockFifo #(
  .DATA_WIDTH(16),
  .DEPTH(512)
) fifo_axi2pix (
  .wr_clk(axi_clk),
  .wr_rstn(axi_rstn),
  .wr_en(vga_pixel_valid && vga_pixel_ready),
  .din(vga_pixel_data),
  .full(fifo_full_vga),

  .rd_clk(pix_clk),
  .rd_rstn(pix_rstn),
  .rd_en(fifo_rd_en_vga),
  .dout(fifo_dout_vga),
  .empty(fifo_empty_vga)
);

assign vga_pixel_ready = !fifo_full_vga;

logic [15:0] pixel_data_pix;
logic pixel_valid_pix;
assign pixel_valid_pix = !fifo_empty_vga;
assign fifo_rd_en_vga = pixel_valid_pix; // čítaj, keď môže VGA spracovať

assign pixel_data_pix = fifo_dout_vga;

//---------------------------------------------------
// VGA timing signals + output

// Pre použitie Vga_timing modulu potrebujeme nastaviť line parametre a volať ho s pix_clk

line_t h_line = '{visible_area: 640, front_porch: 16, sync_pulse: 96, back_porch: 48, polarity: 1};
line_t v_line = '{visible_area: 480, front_porch: 10, sync_pulse: 2, back_porch: 33, polarity: 1};

position_t pos;
signal_t signal;

Vga_timing vga_timing_inst (
  .clk_pix(pix_clk),
  .rstn(pix_rstn),
  .h_line(h_line),
  .v_line(v_line),
  .pos(pos),
  .signal(signal)
);

// Logika pre mapovanie pixelov na RGB565, kde pixel_data_pix je 16-bit (5:6:5)

assign vga_red   = pixel_data_pix[15:11];
assign vga_green = pixel_data_pix[10:5];
assign vga_blue  = pixel_data_pix[4:0];
assign vga_hs    = signal.h_sync;
assign vga_vs    = signal.v_sync;

endmodule
