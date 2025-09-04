module AxiStreamSwitcher (
  input  logic         clk,
  input  logic         rstn,
  input  logic         btn,        // prepínacie tlačidlo
  input  logic         vsync_blank, // prepnutie povolené počas blankingu

  // AXIS Generator 1
  input  logic         s0_tvalid,
  input  logic [15:0]  s0_tdata,
  input  logic         s0_tlast,
  input  logic         s0_tuser,
  output logic         s0_tready,

  // AXIS Generator 2
  input  logic         s1_tvalid,
  input  logic [15:0]  s1_tdata,
  input  logic         s1_tlast,
  input  logic         s1_tuser,
  output logic         s1_tready,

  // AXIS output (to VGA)
  output logic         m_tvalid,
  output logic [15:0]  m_tdata,
  output logic         m_tlast,
  output logic         m_tuser,
  input  logic         m_tready
);

  logic toggle_req;
  logic toggle_state;

  // Edge detection on button
  logic btn_d, btn_dd;
  always_ff @(posedge clk) begin
    if (!rstn) begin
      btn_d  <= 0;
      btn_dd <= 0;
    end else begin
      btn_d  <= btn;
      btn_dd <= btn_d;
    end
  end

  wire btn_posedge = (btn_d & ~btn_dd);

  // Request toggle during vsync blanking
  always_ff @(posedge clk) begin
    if (!rstn)
      toggle_req <= 0;
    else if (btn_posedge)
      toggle_req <= 1;
    else if (vsync_blank)
      toggle_req <= 0;
  end

  // Toggle active stream only during vsync
  always_ff @(posedge clk) begin
    if (!rstn)
      toggle_state <= 0;
    else if (toggle_req && vsync_blank)
      toggle_state <= ~toggle_state;
  end

  // Output selection based on toggle state
  assign m_tvalid = toggle_state ? s1_tvalid : s0_tvalid;
  assign m_tdata  = toggle_state ? s1_tdata  : s0_tdata;
  assign m_tlast  = toggle_state ? s1_tlast  : s0_tlast;
  assign m_tuser  = toggle_state ? s1_tuser  : s0_tuser;

  assign s0_tready = (!toggle_state) ? m_tready : 0;
  assign s1_tready = ( toggle_state) ? m_tready : 0;

endmodule
