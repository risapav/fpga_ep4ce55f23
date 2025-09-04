//================================================================
// axi_interfaces.sv - Finálna a robustná verzia
//
// Verzia 3.1 - Oprava deklarácie v AXI4-Stream pre zero-width signály
//================================================================

`ifndef AXI_INTERFACES_SV
`define AXI_INTERFACES_SV

//================================================================
// AXI4-Lite Interface
//================================================================
interface axi4lite_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic ACLK,
    input logic ARESETn
);
    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // Signály
    logic [ADDR_WIDTH-1:0] AWADDR, ARADDR;
    logic [2:0]            AWPROT, ARPROT;
    logic                  AWVALID, AWREADY, ARVALID, ARREADY;
    logic [DATA_WIDTH-1:0] WDATA, RDATA;
    logic [STRB_WIDTH-1:0] WSTRB;
    logic                  WVALID, WREADY, RVALID, RREADY;
    logic [1:0]            BRESP, RRESP;
    logic                  BVALID, BREADY;

    modport master (
        output AWVALID, AWADDR, AWPROT, WVALID, WDATA, WSTRB, BREADY, ARVALID, ARADDR, ARPROT, RREADY,
        input  AWREADY, WREADY, BVALID, BRESP, ARREADY, RVALID, RDATA, RRESP
    );

    modport slave (
        input  AWVALID, AWADDR, AWPROT, WVALID, WDATA, WSTRB, BREADY, ARVALID, ARADDR, ARPROT, RREADY,
        output AWREADY, WREADY, BVALID, BRESP, ARREADY, RVALID, RDATA, RRESP
    );
endinterface


//================================================================
// AXI4-Full Interface
//================================================================
interface axi4_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int LEN_WIDTH  = 8
)(
    input logic ACLK,
    input logic ARESETn
);
    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // Signály
    logic [ID_WIDTH-1:0]   AWID, BID, ARID, RID;
    logic [ADDR_WIDTH-1:0] AWADDR, ARADDR;
    logic [7:0]            AWLEN, ARLEN;
    logic [2:0]            AWSIZE, ARSIZE;
    logic [1:0]            AWBURST, ARBURST;
    logic                  AWVALID, AWREADY, WLAST, WVALID, WREADY, BVALID, BREADY, ARVALID, ARREADY, RLAST, RVALID, RREADY;
    logic [DATA_WIDTH-1:0] WDATA, RDATA;
    logic [STRB_WIDTH-1:0] WSTRB;
    logic [1:0]            BRESP, RRESP;

    modport master (
        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID, WDATA, WSTRB, WLAST, WVALID, BREADY, ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID, RREADY,
        input  AWREADY, WREADY, BID, BRESP, BVALID, ARREADY, RID, RDATA, RRESP, RLAST, RVALID
    );

    modport slave (
        input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID, WDATA, WSTRB, WLAST, WVALID, BREADY, ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID, RREADY,
        output AWREADY, WREADY, BID, BRESP, BVALID, ARREADY, RID, RDATA, RRESP, RLAST, RVALID
    );
endinterface


//================================================================
// AXI4-Stream Interface
//================================================================
interface axi4s_if #(
    parameter int DATA_WIDTH = 16,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int ID_WIDTH   = 0,
    parameter int DEST_WIDTH = 0
)(
    input logic ACLK,
    input logic ARESETn
);
    logic                  TVALID, TREADY, TLAST;
    logic [DATA_WIDTH-1:0] TDATA;

    // SPRÁVNY SPÔSOB: Podmienečná deklarácia pomocou `generate`
    generate if (KEEP_WIDTH > 0) begin : gen_tkeep logic [KEEP_WIDTH-1:0] TKEEP; end endgenerate
    generate if (USER_WIDTH > 0) begin : gen_tuser logic [USER_WIDTH-1:0] TUSER; end endgenerate
    generate if (ID_WIDTH > 0)   begin : gen_tid   logic [ID_WIDTH-1:0]   TID;   end endgenerate
    generate if (DEST_WIDTH > 0) begin : gen_tdest logic [DEST_WIDTH-1:0] TDEST; end endgenerate

    // SPRÁVNY SPÔSOB: Jednoduchý zoznam v modporte.
    // Kompilátor automaticky ignoruje signály, ktoré neboli vygenerované.
    modport master (
        output TVALID, TDATA, TLAST, TKEEP, TUSER, TID, TDEST,
        input  TREADY
    );

    modport slave (
        input  TVALID, TDATA, TLAST, TKEEP, TUSER, TID, TDEST,
        output TREADY
    );
endinterface

`endif // AXI_INTERFACES_SV
