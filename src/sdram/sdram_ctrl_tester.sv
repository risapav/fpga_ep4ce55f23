`ifndef SDRAM_CTRL_TESTER_SV
`define SDRAM_CTRL_TESTER_SV

(* default_nettype = "none" *)
import vga_pkg::*;
import axi_pkg::*;
import sdram_pkg::*;

module sdram_ctrl_tester #(
    parameter int DATA_WIDTH = 16
)(
    input  logic clk_i,
    input  logic clk_sh_i,
    input  logic rst_ni,
    output logic [7:0] leds_o
);

    localparam BRAM_DEPTH = 1024;
    localparam BRAM_ADDR_WIDTH = $clog2(BRAM_DEPTH);
    logic [DATA_WIDTH-1:0] bram_mem [0:BRAM_DEPTH-1];

    logic [12:0] sdram_addr;
    logic [1:0]  sdram_ba;
    logic sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
    wire [DATA_WIDTH-1:0] sdram_dq;
    logic [1:0]  sdram_dqm;
    logic sdram_cke, sdram_clk;

    logic [DATA_WIDTH-1:0] data_to_controller;
    assign sdram_dq = (~sdram_we_n) ? {DATA_WIDTH{1'bz}} : data_to_controller;

    logic [BRAM_ADDR_WIDTH-1:0] bram_addr;
    logic [14:0] full_controller_addr;
    assign full_controller_addr = {sdram_ba, sdram_addr};
    assign bram_addr = full_controller_addr[BRAM_ADDR_WIDTH-1:0];

    // --- Zápis do BRAM ---
    always_ff @(posedge clk_sh_i) begin
        if (~sdram_cs_n && ~sdram_cas_n && ~sdram_we_n) begin
            bram_mem[bram_addr] <= sdram_dq;
        end
    end

    // ==========================================================
    // ==                          OPRAVA                        ==
    // ==========================================================
    // Register, ktorý si "zapamätá" adresu pri príkaze na čítanie
    logic [BRAM_ADDR_WIDTH-1:0] read_addr_latch;

    always_ff @(posedge clk_i) begin
        // Príkaz READ je aktívny, keď CS, CAS sú v nule a WE je v jednotke
        if (~sdram_cs_n && ~sdram_cas_n && sdram_we_n) begin
            read_addr_latch <= bram_addr;
        end
    end

    // --- Čítanie z BRAM ---
    // Čítame vždy z naposledy "zapamätanej" adresy
    assign data_to_controller = bram_mem[read_addr_latch];
    // ==========================================================

    logic cmd_valid, cmd_ready, resp_valid, resp_last;
    sdram_pkg::sdram_cmd_t cmd_data;
    logic [DATA_WIDTH-1:0] resp_data;
    logic [4:0] ctrl_state;

    SdramController #( .DATA_WIDTH(DATA_WIDTH), .CAS_LATENCY(3) )
    u_controller (
        .clk(clk_i), .clk_sh(clk_sh_i), .rstn(rst_ni),
        .cmd_fifo_valid(cmd_valid), .cmd_fifo_ready(cmd_ready), .cmd_fifo_data(cmd_data),
        .resp_valid(resp_valid), .resp_last(resp_last), .resp_data(resp_data), .resp_ready(1'b1),
        .wdata_valid(1'b1), .wdata(cmd_data.wdata), .wdata_dqm_i(2'b00), .wdata_ready(),
        .sdram_addr, .sdram_ba, .sdram_cs_n, .sdram_ras_n, .sdram_cas_n, .sdram_we_n,
        .sdram_dq(sdram_dq), .sdram_dqm, .sdram_cke, .sdram_clk, .debug_state_o(ctrl_state)
    );

    typedef enum { IDLE, SEND_WRITE, WAIT_WRITE, SEND_READ, WAIT_READ, CHECK, SUCCESS, FAIL } state_t;
    state_t state;
    localparam TEST_ADDR  = 24'd100;
    localparam TEST_DATA  = 16'hABCD;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin state <= IDLE; cmd_valid <= 1'b0; end
        else begin
            case (state)
                IDLE:       if (ctrl_state == 4) state <= SEND_WRITE;
                SEND_WRITE: begin cmd_valid <= 1'b1; cmd_data.rw <= WRITE_CMD; cmd_data.addr <= TEST_ADDR; cmd_data.wdata <= TEST_DATA; state <= WAIT_WRITE; end
                WAIT_WRITE: if (cmd_ready) begin cmd_valid <= 1'b0; state <= SEND_READ; end
                SEND_READ:  begin cmd_valid <= 1'b1; cmd_data.rw <= READ_CMD; cmd_data.addr <= TEST_ADDR; state <= WAIT_READ; end
                WAIT_READ:  if (cmd_ready) begin cmd_valid <= 1'b0; state <= CHECK; end
                CHECK:      if (resp_valid) state <= (resp_data == TEST_DATA) ? SUCCESS : FAIL;
                SUCCESS:    state <= SUCCESS;
                FAIL:       state <= FAIL;
            endcase
        end
    end

    assign leds_o[0] = (state == SUCCESS);
    assign leds_o[1] = (state == FAIL);
    assign leds_o[6:2] = ctrl_state;
    assign leds_o[7] = |ctrl_state;

endmodule

`endif
