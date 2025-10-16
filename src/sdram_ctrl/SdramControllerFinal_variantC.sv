(* default_nettype = "none" *)
module SdramControllerFinal_variantC #(
    parameter int FIFO_DEPTH_BITS = 4
)(
    input  logic                 clk,
    input  logic                 rstn,

    // systémové rozhranie
    input  logic                 cmd_valid,
    input  sdram_pkg::sdram_cmd_t cmd,
    output logic                 cmd_ready,

    input  logic [sdram_pkg::DATA_WIDTH-1:0] wdata_i,
    input  logic                            wdata_valid,
    output logic                            wdata_ready,

    output logic [sdram_pkg::DATA_WIDTH-1:0] rdata_o,
    output logic                            rdata_valid,

    // SDRAM rozhranie
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    inout  logic [sdram_pkg::DATA_WIDTH-1:0] sdram_dq
);

    import sdram_pkg::*;

    // ───────────────────────────────
    // FIFO inštancie
    // ───────────────────────────────
    logic [DATA_WIDTH-1:0] write_data_in, write_data_out, read_data_in, read_data_out;
    logic                  write_fifo_full, write_fifo_empty, read_fifo_full, read_fifo_empty;
    logic                  write_rd_en, read_wr_en;

    assign write_data_in = wdata_i;

    AsyncFifoGeneric #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(FIFO_DEPTH_BITS)
    ) u_write_fifo (
        .wr_clk   (clk),
        .wr_rstn  (rstn),
        .wr_en    (wdata_valid),
        .wr_data  (write_data_in),
        .wr_full  (write_fifo_full),
        .rd_clk   (clk),
        .rd_rstn  (rstn),
        .rd_en    (write_rd_en),
        .rd_data  (write_data_out),
        .rd_empty (write_fifo_empty),
        .wr_count (),
        .rd_count ()
    );

    AsyncFifoGeneric #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(FIFO_DEPTH_BITS)
    ) u_read_fifo (
        .wr_clk   (clk),
        .wr_rstn  (rstn),
        .wr_en    (read_wr_en),
        .wr_data  (read_data_in),
        .wr_full  (read_fifo_full),
        .rd_clk   (clk),
        .rd_rstn  (rstn),
        .rd_en    (rdata_valid && rdata_ready), // voliteľné
        .rd_data  (read_data_out),
        .rd_empty (read_fifo_empty),
        .wr_count (),
        .rd_count ()
    );

    assign wdata_ready = !write_fifo_full;
    assign rdata_o     = read_data_out;
    assign rdata_valid = !read_fifo_empty;

    // ───────────────────────────────
    // Časovače
    // ───────────────────────────────
    logic trp_start, trp_done;
    CountdownTimer #(.WIDTH(8)) u_tRP (
        .clk(clk), .rstn(rstn),
        .start(trp_start),
        .preset(tRP),
        .busy(), .done(trp_done)
    );

    logic trcd_start, trcd_done;
    CountdownTimer #(.WIDTH(8)) u_tRCD (
        .clk(clk), .rstn(rstn),
        .start(trcd_start),
        .preset(tRCD),
        .busy(), .done(trcd_done)
    );

    // ───────────────────────────────
    // Stavový automat (zjednodušený)
    // ───────────────────────────────
    typedef enum logic [3:0] {
        ST_INIT, ST_IDLE, ST_ACTIVATE, ST_WAIT_TRCD,
        ST_RW, ST_WAIT_TRP
    } state_t;

    state_t state, nstate;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) state <= ST_INIT;
        else       state <= nstate;
    end

    always_comb begin
        nstate = state;
        cmd_ready = 1'b0;
        write_rd_en = 1'b0;
        read_wr_en  = 1'b0;
        trp_start   = 1'b0;
        trcd_start  = 1'b0;

        // default SDRAM signály
        sdram_cs_n  = 1'b1;
        sdram_ras_n = 1'b1;
        sdram_cas_n = 1'b1;
        sdram_we_n  = 1'b1;
        sdram_ba    = '0;
        sdram_addr  = '0;

        case (state)
            ST_INIT: nstate = ST_IDLE;

            ST_IDLE: begin
                cmd_ready = 1'b1;
                if (cmd_valid) begin
                    trcd_start = 1'b1;
                    nstate = ST_ACTIVATE;
                end
            end

            ST_ACTIVATE: begin
                sdram_cs_n  = 1'b0;
                sdram_ras_n = 1'b0;
                sdram_cas_n = 1'b1;
                sdram_we_n  = 1'b1;
                if (trcd_done)
                    nstate = ST_RW;
            end

            ST_RW: begin
                if (cmd.rw == WRITE_CMD) begin
                    sdram_cs_n  = 1'b0;
                    sdram_ras_n = 1'b1;
                    sdram_cas_n = 1'b0;
                    sdram_we_n  = 1'b0;
                    write_rd_en = !write_fifo_empty;
                end else begin
                    sdram_cs_n  = 1'b0;
                    sdram_ras_n = 1'b1;
                    sdram_cas_n = 1'b0;
                    sdram_we_n  = 1'b1;
                    read_wr_en  = !read_fifo_full;
                end
                trp_start = 1'b1;
                nstate = ST_WAIT_TRP;
            end

            ST_WAIT_TRP: if (trp_done) nstate = ST_IDLE;

            default: nstate = ST_IDLE;
        endcase
    end

endmodule
`default_nettype wire
