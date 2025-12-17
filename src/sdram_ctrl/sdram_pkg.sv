`default_nettype none

`ifndef SDRAM_PKG_SV
`define SDRAM_PKG_SV

/**
 * @file        sdram_pkg.sv
 * @brief       Global definitions and parameters for SDRAM controller.
 */

package sdram_pkg;

    // --- Configuration Parameters ---
    localparam int DATA_WIDTH       = 16;
    localparam int ROW_ADDR_WIDTH   = 13;
    localparam int COL_ADDR_WIDTH   = 9;
    localparam int BANK_ADDR_WIDTH  = 2;

    // --- Timing Parameters (Defaults for 100MHz / 10ns) ---
    // These can be overridden in module instantiation
    localparam int T_RAS_CYCLES           = 5;     // tRAS: Active to Precharge
    localparam int T_RCD_CYCLES           = 2;     // tRCD: Active to Read/Write
    localparam int T_RP_CYCLES            = 2;     // tRP:  Precharge period
    localparam int T_WR_CYCLES            = 2;     // tWR:  Write Recovery
    localparam int T_RFC_CYCLES           = 7;     // tRFC: Auto Refresh
    localparam int T_MRD_CYCLES           = 2;     // tMRD: Mode Register Load
    localparam int C_INIT_WAIT_CYCLES     = 10000; // 100us wait
    localparam int REFRESH_INTERVAL_CYCLES = 780;  // 7.8us

    localparam int CAS_LATENCY            = 2;
    localparam int BURST_LEN              = 4;     // Must match SDRAM Mode Register

    // --- Derived Parameters ---
    localparam int CMRS_VALUE_ADDR        = (CAS_LATENCY << 4) | (3'b010); // Burst=4, Sequential

    // --- Types ---
    typedef enum logic { READ_CMD = 1'b1, WRITE_CMD = 1'b0 } rw_cmd_t;

    typedef struct packed {
        logic [BANK_ADDR_WIDTH-1:0] bank;
        logic [ROW_ADDR_WIDTH-1:0]  row;
        logic [COL_ADDR_WIDTH-1:0]  col;
    } sdram_addr_t;

    typedef struct packed {
        sdram_addr_t addr;
        rw_cmd_t     rw;             // 1 = Write, 0 = Read
        logic        auto_precharge; // 1 = Auto-Precharge enabled
    } sdram_cmd_t;

    typedef enum logic [1:0] { EMPTY, FILLING, FULL, READING } buffer_state_t;

    typedef enum logic [1:0] { STREAM_OK, STREAM_TIMEOUT_ERROR, STREAM_ABORTED } stream_status_t;

endpackage

`endif // SDRAM_PKG_SV

`default_nettype wire
