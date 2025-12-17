/**
 * @file        sync_fifo.sv
 * @brief       Synchrónne FIFO s podporou Byte Enable.
 * @details     Single-clock FIFO. Optimalizované pre Intel M10K (no_rw_check).
 *
 * @param DATA_WIDTH Šírka dát.
 * @param BE_WIDTH   Šírka Byte Enable.
 * @param ADDR_WIDTH Šírka adresy (Hĺbka = 2^ADDR_WIDTH).
 */

`default_nettype none

`ifndef SYNC_FIFO_SV
`define SYNC_FIFO_SV

module sync_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int BE_WIDTH   = DATA_WIDTH / 8,
    parameter int ADDR_WIDTH = 6
)(
    input  logic                  clk_i,
    input  logic                  rst_ni, // Asynchrónny reset

    // Write Port
    input  logic                  wr_en_i,
    input  logic [DATA_WIDTH-1:0] wr_data_i,
    input  logic [BE_WIDTH-1:0]   wr_be_i,
    output logic                  wr_full_o,
    output logic                  wr_overflow_o,
    
    // Read Port
    input  logic                  rd_en_i,
    output logic [DATA_WIDTH-1:0] rd_data_o,
    output logic [BE_WIDTH-1:0]   rd_be_o,
    output logic                  rd_empty_o,
    output logic                  rd_underflow_o,
    
    // Status
    output logic [ADDR_WIDTH:0]   level_o
);

    localparam int DEPTH     = 1 << ADDR_WIDTH;
    localparam int MEM_WIDTH = DATA_WIDTH + BE_WIDTH;

    // Quartus Hint: M10K blocks
    (* ramstyle = "no_rw_check, M10K" *)
    logic [MEM_WIDTH-1:0] mem [0:DEPTH-1];

    logic [ADDR_WIDTH:0] wr_ptr;
    logic [ADDR_WIDTH:0] rd_ptr;

    // -------------------------------------------------------------------------
    // 1. Stavové Signály (Combinatorial)
    // -------------------------------------------------------------------------
    // Full: MSB rozdielne, zvyšok rovnaký
    assign wr_full_o    = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                          (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    
    assign rd_empty_o   = (wr_ptr == rd_ptr);
    assign level_o      = wr_ptr - rd_ptr;
    
    assign wr_overflow_o  = wr_en_i && wr_full_o;
    assign rd_underflow_o = rd_en_i && rd_empty_o;

    // -------------------------------------------------------------------------
    // 2. Write Logic (Sequential)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_ptr <= '0;
        end else if (wr_en_i && !wr_full_o) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= {wr_be_i, wr_data_i};
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 3. Read Logic (Sequential)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_ptr <= '0;
        end else if (rd_en_i && !rd_empty_o) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 4. Output Mapping (Asynchronous Read)
    // -------------------------------------------------------------------------
    // Poznámka: Pre inferenciu M10K bloku bez extra logiky by mal byť tento
    // výstup ideálne registrovaný. Pri asynchrónnom čítaní Quartus často
    // použije MLAB/LUTRAM, ak sa mu nepodarí retiming.
    assign {rd_be_o, rd_data_o} = mem[rd_ptr[ADDR_WIDTH-1:0]];

endmodule

`endif // SYNC_FIFO_SV

`default_nettype wire
