`ifndef SDRAM_PKG_DONE
`define SDRAM_PKG_DONE
(* default_nettype = "none" *)

package sdram_pkg;

  parameter int DATA_WIDTH      = 16;
  parameter int BURST_LEN       = 8;

  parameter int BANK_ADDR_WIDTH = 2;
  parameter int ROW_ADDR_WIDTH  = 13;
  parameter int COL_ADDR_WIDTH  = 9;
  parameter int ADDR_WIDTH      = BANK_ADDR_WIDTH + ROW_ADDR_WIDTH + COL_ADDR_WIDTH;

  parameter int CLOCK_FREQ_HZ   = 100_000_000;
  parameter int CAS_LATENCY     = 3;
  parameter int tRP             = 3;
  parameter int tRCD            = 3;
  parameter int tWR             = 2;
  parameter int tRFC            = 9;
  parameter int tRAS            = 7;

  typedef enum logic { READ_CMD = 1'b1, WRITE_CMD = 1'b0 } rw_cmd_t;

  typedef struct packed {
    logic [BANK_ADDR_WIDTH-1:0] bank;
    logic [ROW_ADDR_WIDTH-1:0]  row;
    logic [COL_ADDR_WIDTH-1:0]  col;
  } sdram_addr_t;

  typedef struct packed {
    rw_cmd_t   rw;
    logic      auto_precharge;
    logic [ADDR_WIDTH-1:0] addr;
  } sdram_cmd_t;

  typedef enum logic [1:0] { EMPTY, FILLING, FULL, READING } buffer_state_t;

  typedef enum logic [1:0] { STREAM_OK, STREAM_TIMEOUT_ERROR, STREAM_ABORTED } stream_status_t;

endpackage
`default_nettype wire
`endif
