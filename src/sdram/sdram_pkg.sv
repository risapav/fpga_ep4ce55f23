`ifndef SDRAM_PKG_DONE
`define SDRAM_PKG_DONE

(* default_nettype = "none" *)

package sdram_pkg;
  parameter int ADDR_WIDTH = 24;
  parameter int DATA_WIDTH = 16;
  parameter int BURST_LEN  = 8;

/*
  typedef enum logic {
    WRITE_CMD = 1'b0,
    READ_CMD  = 1'b1
  } rw_cmd_e;

  typedef struct packed {
    rw_cmd_e                   rw;               // 1=read, 0=write
    logic [ADDR_WIDTH-1:0]     addr;
    logic [DATA_WIDTH-1:0]     wdata;
    logic                      auto_precharge_en;
  } sdram_cmd_t;
*/
//--------------------

    typedef enum {
      READ_CMD, WRITE_CMD
    } rw_cmd_t;

    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH, INIT_MRS,
        IDLE, IDLE_WAIT,
        ACTIVE_CMD, ACTIVE_WAIT, PREFETCH_WDATA, RW_CMD,
        READ_BURST, WRITE_BURST,
        PRECHARGE_CMD, REFRESH_CMD
    } state_t;

    // Definuje príkaz pre SDRAM kontrolér
    typedef struct packed {
        logic      rw;              // READ_CMD alebo WRITE_CMD
        logic      auto_precharge;  // 1'b1 pre vykonanie auto-precharge (READA/WRITEA)
        logic [23:0] addr;          // Systémová adresa
    } sdram_cmd_t;

    typedef enum logic [1:0] {
      EMPTY, FILLING, FULL, READING
    } buffer_state_t;

endpackage

`endif
