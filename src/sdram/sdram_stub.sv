`ifndef SDRAM_DRIVER_STUB_SV
`define SDRAM_DRIVER_STUB_SV

(* default_nettype = "none" *)

///
/// @brief SdramDriverStub.sv – simulátor SDRAM pomocou internej BRAM.
/// @details Tento modul má identické porty ako SdramDriver,
///          ale dáta ukladá do internej pamäte BRAM.
///          Slúži na ladenie framebufferu, kým nie je reálna SDRAM implementácia hotová.
///
module SdramDriverStub #(
    parameter int ADDR_WIDTH   = 24,
    parameter int DATA_WIDTH   = 16,
    parameter int BURST_LENGTH = 8,
    parameter int LATENCY_CYC  = 3,   ///< oneskorenie čítania, simuluje CAS latency
    parameter int MEM_DEPTH = (1 << 14) // 16k slov = 32kB
//(* ramstyle = "MLAB, no_rw_check" *) logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
)(
    input  logic clk_axi,
    input  logic clk,
    input  logic clk_sh,
    input  logic rstn_axi,
    input  logic rstn,

    // --- Reader rozhranie ---
    input  logic reader_valid,
    output logic reader_ready,
    input  logic [ADDR_WIDTH-1:0] reader_addr,

    // --- Writer rozhranie ---
    input  logic writer_valid,
    output logic writer_ready,
    input  logic [ADDR_WIDTH-1:0] writer_addr,
    input  logic [DATA_WIDTH-1:0] writer_data,
    input  logic [1:0] writer_dqm_i,

    // --- Odpoveď (čítanie z pamäte) ---
    output logic resp_valid,
    output logic resp_last,
    output logic [DATA_WIDTH-1:0] resp_data,
    input  logic resp_ready,

    // --- Diagnostické výstupy (ponechané kvôli kompatibilite) ---
    output logic error_overflow_o,
    output logic error_underflow_o,
    input  logic error_clear_i,

    // --- Simulované SDRAM piny (nepoužité, len pre kompatibilitu) ---
    output logic [12:0] sdram_addr,
    output logic [1:0]  sdram_ba,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    inout  wire [15:0]  sdram_dq,
    output logic [1:0]  sdram_dqm,
    output logic        sdram_cke,
    output logic        sdram_clk,

    // --- Stavový výstup (len dummy pre debug LED) ---
    output logic [7:0] controller_state_o
);

    // ===============================================================
    // ==               Interná BRAM ako simulovaná SDRAM           ==
    // ===============================================================
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // --- Výstupné riadiace signály SDRAM (vždy neaktívne) ---
    assign sdram_dq    = 16'bz;
    assign sdram_addr  = 13'b0;
    assign sdram_ba    = 2'b0;
    assign sdram_cs_n  = 1'b1;
    assign sdram_ras_n = 1'b1;
    assign sdram_cas_n = 1'b1;
    assign sdram_we_n  = 1'b1;
    assign sdram_dqm   = 2'b0;
    assign sdram_cke   = 1'b0;
    assign sdram_clk   = 1'b0;
    assign controller_state_o = 8'hAA; // Len indikácia že beží BRAM stub

    // ===============================================================
    // ==                       Writer sekcia                       ==
    // ===============================================================
    assign writer_ready = 1'b1; // BRAM je vždy pripravená

    always_ff @(posedge clk_axi) begin
        if (writer_valid && writer_ready) begin
            if (writer_addr < MEM_DEPTH)
                mem[writer_addr] <= writer_data;
        end
    end

    // ===============================================================
    // ==                       Reader sekcia                       ==
    // ===============================================================
    assign reader_ready = 1'b1;

    // FIFO pipeline pre oneskorenie čítania
    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic valid;
    } read_req_t;

    read_req_t read_pipe [0:LATENCY_CYC];

    always_ff @(posedge clk_axi or negedge rstn_axi) begin
        if (!rstn_axi) begin
            for (int i = 0; i <= LATENCY_CYC; i++) begin
                read_pipe[i].addr  <= '0;
                read_pipe[i].valid <= 1'b0;
            end
        end else begin
            // posun pipeline
            for (int i = LATENCY_CYC; i > 0; i--) begin
                read_pipe[i] <= read_pipe[i-1];
            end
            // vloženie nového požiadavku
            read_pipe[0].addr  <= reader_addr;
            read_pipe[0].valid <= reader_valid;
        end
    end

    // výstup dát z oneskoreného cyklu
    assign resp_data  = mem[read_pipe[LATENCY_CYC].addr];
    assign resp_valid = read_pipe[LATENCY_CYC].valid;
    assign resp_last  = 1'b0; // stub netrackuje bursty

    // ===============================================================
    // ==                  Diagnostika / chybové signály            ==
    // ===============================================================
    assign error_overflow_o  = 1'b0;
    assign error_underflow_o = 1'b0;

endmodule

`endif
