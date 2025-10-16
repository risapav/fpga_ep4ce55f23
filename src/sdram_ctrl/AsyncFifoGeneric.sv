// AsyncFifoGeneric.sv
// Asynchrónny parametrizovaný FIFO pre Quartus (Gray pointer-based)

`ifndef ASYNC_FIFO_GENERIC_SV
`define ASYNC_FIFO_GENERIC_SV

(* default_nettype = "none" *)

module AsyncFifoGeneric #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                 wr_clk,
    input  logic                 wr_rstn,
    input  logic                 wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic                 wr_full,

    input  logic                 rd_clk,
    input  logic                 rd_rstn,
    input  logic                 rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                 rd_empty,

    output logic [ADDR_WIDTH:0]  wr_count,
    output logic [ADDR_WIDTH:0]  rd_count
);

    // memory
    logic [DATA_WIDTH-1:0] mem[(1<<ADDR_WIDTH)];

    // pointers
    logic [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_bin_next;
    logic [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_bin_next;
    logic [ADDR_WIDTH:0] wr_ptr_gray, wr_ptr_gray_next;
    logic [ADDR_WIDTH:0] rd_ptr_gray, rd_ptr_gray_next;

    // synchronized pointers
    logic [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;

    // write side
    always_ff @(posedge wr_clk or negedge wr_rstn) begin
        if (!wr_rstn) begin
            wr_ptr_bin <= '0;
            wr_ptr_gray <= '0;
        end else begin
            wr_ptr_bin <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            if (wr_en && !wr_full)
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    assign wr_ptr_bin_next  = wr_ptr_bin + ((wr_en && !wr_full) ? 1 : 0);
    assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    // read side
    always_ff @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            rd_ptr_bin <= '0;
            rd_ptr_gray <= '0;
        end else begin
            rd_ptr_bin <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    assign rd_ptr_bin_next  = rd_ptr_bin + ((rd_en && !rd_empty) ? 1 : 0);
    assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    // cross-domain pointer sync
    always_ff @(posedge wr_clk or negedge wr_rstn) begin
        if (!wr_rstn) {rd_ptr_gray_sync1, rd_ptr_gray_sync2} <= '0;
        else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) {wr_ptr_gray_sync1, wr_ptr_gray_sync2} <= '0;
        else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // convert Gray -> binary
    function automatic [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
        automatic logic [ADDR_WIDTH:0] b;
        b[ADDR_WIDTH] = g[ADDR_WIDTH];
        for (int i=ADDR_WIDTH-1; i>=0; i--) b[i] = b[i+1] ^ g[i];
        return b;
    endfunction

    logic [ADDR_WIDTH:0] rd_ptr_bin_sync, wr_ptr_bin_sync;
    assign rd_ptr_bin_sync = gray2bin(rd_ptr_gray_sync2);
    assign wr_ptr_bin_sync = gray2bin(wr_ptr_gray_sync2);

    // full/empty logic
    assign wr_full  = (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                            rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign rd_empty = (rd_ptr_gray_next == wr_ptr_gray_sync2);

    // count approximations
    assign wr_count = wr_ptr_bin - rd_ptr_bin_sync;
    assign rd_count = wr_ptr_bin_sync - rd_ptr_bin;

endmodule

`endif
