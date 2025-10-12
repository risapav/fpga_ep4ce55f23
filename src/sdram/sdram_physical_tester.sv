// =============================================================================
// Súbor: sdram_physical_tester.sv
// Verzia: 1.0
// Popis:
// Samostatný modul na otestovanie základnej operácie ZÁPISU a ČÍTANIA
// z FYZICKEJ SDRAM pamäte. Inštanciuje SdramController a riadi ho
// jednoduchým stavovým automatom. Výsledok testu signalizuje na LED.
// =============================================================================

`ifndef SDRAM_PHYSICAL_TESTER_SV
`define SDRAM_PHYSICAL_TESTER_SV

(* default_nettype = "none" *)
import sdram_pkg::*;

module sdram_physical_tester #(
    parameter int DATA_WIDTH = 16
)(
    // Vstupy z top modulu
    input  logic clk_i,      // Hlavné hodiny (napr. 100 MHz)
    input  logic clk_sh_i,   // Fázovo posunuté hodiny
    input  logic rst_ni,     // Asynchrónny reset (aktívny v nule)

    // Výstupy pre diagnostiku
    output logic [7:0] leds_o,
    output logic [15:0] read_data_o, // Výstup pre zobrazenie prečítaných dát

    // Výstupy na fyzické SDRAM piny
    output logic [12:0] sdram_addr,
    output logic [1:0]  sdram_ba,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    inout  wire [DATA_WIDTH-1:0]  sdram_dq,
    output logic [1:0]  sdram_dqm,
    output logic        sdram_cke,
    output logic        sdram_clk
);

    // Signály pre komunikáciu medzi FSM a Controllerom
    logic cmd_valid, cmd_ready, resp_valid, resp_last;
    sdram_cmd_t cmd_data;
    logic [DATA_WIDTH-1:0] resp_data;
    logic [4:0] ctrl_state;

    // Inštancia SDRAM radiča - srdce testera
    SdramController #(
        .DATA_WIDTH(DATA_WIDTH),
        .CAS_LATENCY(3)
        // Ostatné parametre si ponechajú predvolené hodnoty
    ) u_controller (
        .clk(clk_i), .clk_sh(clk_sh_i), .rstn(rst_ni),
        .cmd_fifo_valid(cmd_valid), .cmd_fifo_ready(cmd_ready), .cmd_fifo_data(cmd_data),
        .resp_valid(resp_valid), .resp_last(resp_last), .resp_data(resp_data), .resp_ready(1'b1),
        .wdata_valid(1'b1), .wdata(cmd_data.wdata), .wdata_dqm_i(2'b00), .wdata_ready(),

        // Pripojenie na výstupné porty tohto modulu
        .sdram_addr, .sdram_ba, .sdram_cs_n, .sdram_ras_n, .sdram_cas_n, .sdram_we_n,
        .sdram_dq, .sdram_dqm, .sdram_cke, .sdram_clk,
        .debug_state_o(ctrl_state)
    );

    // Testovací FSM
    typedef enum { IDLE, SEND_WRITE, WAIT_WRITE, SEND_READ, WAIT_READ, CHECK, SUCCESS, FAIL } state_t;
    state_t state;
    localparam TEST_ADDR  = 24'h00_01_00; // Adresa mimo prvých pár riadkov
    localparam TEST_DATA  = 16'hABCD;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            cmd_valid <= 1'b0;
        end else begin
            case (state)
                IDLE:       if (ctrl_state == 4) state <= SEND_WRITE; // Čaká na IDLE stav radiča (4)
                SEND_WRITE: begin
                    cmd_valid <= 1'b1;
                    cmd_data.rw    <= WRITE_CMD;
                    cmd_data.addr  <= TEST_ADDR;
                    cmd_data.wdata <= TEST_DATA;
                    state <= WAIT_WRITE;
                end
                WAIT_WRITE: if (cmd_ready) begin
                    cmd_valid <= 1'b0;
                    state <= SEND_READ;
                end
                SEND_READ:  begin
                    cmd_valid <= 1'b1;
                    cmd_data.rw    <= READ_CMD;
                    cmd_data.addr  <= TEST_ADDR;
                    state <= WAIT_READ;
                end
                WAIT_READ:  if (cmd_ready) begin
                    cmd_valid <= 1'b0;
                    state <= CHECK;
                end
                CHECK:      if (resp_valid) begin
                    state <= (resp_data == TEST_DATA) ? SUCCESS : FAIL;
                end
                SUCCESS:    state <= SUCCESS; // Zostane v úspešnom stave
                FAIL:       state <= FAIL;    // Zostane v neúspešnom stave
            endcase
        end
    end

    // Priradenie výsledkov na diagnostické výstupy
    assign leds_o[0] = (state == SUCCESS);
    assign leds_o[1] = (state == FAIL);
    assign leds_o[6:2] = ctrl_state;
    assign leds_o[7] = cmd_valid; // Ukazuje, kedy FSM posiela príkaz

    assign read_data_o = resp_data;

endmodule

`endif
