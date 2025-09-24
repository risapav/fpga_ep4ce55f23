`ifndef SDRAM_PKG_DONE
`define SDRAM_PKG_DONE

package sdram_pkg;
  parameter int ADDR_WIDTH = 24;
  parameter int DATA_WIDTH = 16;

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

endpackage

`endif
