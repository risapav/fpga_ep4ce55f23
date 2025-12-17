/**
 * @file        axi_interfaces.sv
 * @brief       Definície AXI rozhraní (AXI4, AXI4-Lite, AXI4-Stream).
 * @details     Obsahuje SystemVerilog interface definície pre štandardné zbernice.
 * - axi4lite_if: Register access.
 * - axi4_if:     Memory mapped burst access.
 * - axi4s_if:    Streaming data.
 *
 * @input       ACLK    Globálny hodinový signál.
 * @input       ARESETn Globálny asynchrónny reset (active-low).
 */

`default_nettype none

`ifndef AXI_INTERFACES_SV
`define AXI_INTERFACES_SV

import axi_pkg::*; // Dôležité: Sprístupňuje typy a konštanty pre všetky interfejsy

// ================================================================
// AXI4-Lite Interface
// Zjednodušená adresná zbernica pre prístup k registrom.
// Nepodporuje burst prenosy.
// ================================================================
interface axi4lite_if #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned STRB_WIDTH = DATA_WIDTH / 8
) (
    input wire logic ACLK,
    input wire logic ARESETn
);

    // --- Write Address Channel (AW) ---
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [2:0]            AWPROT;
    logic                  AWVALID;
    logic                  AWREADY;

    // --- Write Data Channel (W) ---
    logic [DATA_WIDTH-1:0] WDATA;
    logic [STRB_WIDTH-1:0] WSTRB;
    logic                  WVALID;
    logic                  WREADY;

    // --- Write Response Channel (B) ---
    logic [1:0]            BRESP;
    logic                  BVALID;
    logic                  BREADY;

    // --- Read Address Channel (AR) ---
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [2:0]            ARPROT;
    logic                  ARVALID;
    logic                  ARREADY;

    // --- Read Data Channel (R) ---
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]            RRESP;
    logic                  RVALID;
    logic                  RREADY;

    // Modporty
    modport master (
        output AWVALID, AWADDR, AWPROT,
               WVALID, WDATA, WSTRB,
               BREADY,
               ARVALID, ARADDR, ARPROT,
               RREADY,
        input  AWREADY, WREADY, BVALID, BRESP,
               ARREADY, RVALID, RDATA, RRESP
    );

    modport slave (
        input  AWVALID, AWADDR, AWPROT,
               WVALID, WDATA, WSTRB,
               BREADY,
               ARVALID, ARADDR, ARPROT,
               RREADY,
        output AWREADY, WREADY, BVALID, BRESP,
               ARREADY, RVALID, RDATA, RRESP
    );
endinterface


// ================================================================
// AXI4-Full Interface
// Kompletná adresná zbernica s podporou burst prenosov.
// ================================================================
interface axi4_if #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 64,
    parameter int unsigned ID_WIDTH   = 4,
    parameter int unsigned LEN_WIDTH  = 8,
    parameter int unsigned STRB_WIDTH = DATA_WIDTH / 8
)(
    input wire logic ACLK,
    input wire logic ARESETn
);

    // --- Write Address Channel ---
    logic [ID_WIDTH-1:0]   AWID;
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [LEN_WIDTH-1:0]  AWLEN;
    logic [2:0]            AWSIZE;
    logic [1:0]            AWBURST;
    logic                  AWVALID;
    logic                  AWREADY;

    // --- Write Data Channel ---
    logic [DATA_WIDTH-1:0] WDATA;
    logic [STRB_WIDTH-1:0] WSTRB;
    logic                  WLAST;
    logic                  WVALID;
    logic                  WREADY;

    // --- Write Response Channel ---
    logic [ID_WIDTH-1:0]   BID;
    logic [1:0]            BRESP;
    logic                  BVALID;
    logic                  BREADY;

    // --- Read Address Channel ---
    logic [ID_WIDTH-1:0]   ARID;
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [LEN_WIDTH-1:0]  ARLEN;
    logic [2:0]            ARSIZE;
    logic [1:0]            ARBURST;
    logic                  ARVALID;
    logic                  ARREADY;

    // --- Read Data Channel ---
    logic [ID_WIDTH-1:0]   RID;
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]            RRESP;
    logic                  RLAST;
    logic                  RVALID;
    logic                  RREADY;

    modport master (
        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID,
               WDATA, WSTRB, WLAST, WVALID,
               BREADY,
               ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID,
               RREADY,
        input  AWREADY, WREADY, BID, BRESP, BVALID,
               ARREADY, RID, RDATA, RRESP, RLAST, RVALID
    );

    modport slave (
        input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID,
               WDATA, WSTRB, WLAST, WVALID,
               BREADY,
               ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID,
               RREADY,
        output AWREADY, WREADY, BID, BRESP, BVALID,
               ARREADY, RID, RDATA, RRESP, RLAST, RVALID
    );
endinterface


// ================================================================
// AXI4-Stream Interface
// Prúdová zbernica (Point-to-Point).
// ================================================================
interface axi4s_if #(
    parameter int unsigned DATA_WIDTH = 16,
    parameter int unsigned USER_WIDTH = 1,
    parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int unsigned ID_WIDTH   = 0,
    parameter int unsigned DEST_WIDTH = 0
)(
    input wire logic ACLK,
    input wire logic ARESETn
);

    // Hlavné signály
    logic                  TVALID;
    logic                  TREADY;
    logic [DATA_WIDTH-1:0] TDATA;

    // Voliteľné signály
    logic [KEEP_WIDTH-1:0] TKEEP;
    logic                  TLAST;
    logic [USER_WIDTH-1:0] TUSER;
    logic [ID_WIDTH-1:0]   TID;
    logic [DEST_WIDTH-1:0] TDEST;

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

`default_nettype wire
