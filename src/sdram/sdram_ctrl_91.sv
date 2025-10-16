`ifndef SDRAM_PKG_DONE
`define SDRAM_PKG_DONE

(* default_nettype = "none" *)

package sdram_pkg;

  // --- Globálne parametre ---
  // Tieto parametre definujú fyzickú a logickú štruktúru SDRAM a systému.
  // Sú jediným zdrojom pravdy (Single Source of Truth) pre všetky moduly.
  parameter int ADDR_WIDTH      = 24;
  parameter int DATA_WIDTH      = 16;
  parameter int BURST_LEN       = 8;
  parameter int ROW_ADDR_WIDTH  = 13;
  parameter int COL_ADDR_WIDTH  = 9;
  parameter int BANK_ADDR_WIDTH = 2;

  // --- OPRAVA (v9.1): Odstránený duplicitný blok s parametrami adresovania ---
  // Pôvodné duplicitné deklarácie boli odstránené, aby sa predišlo chybe pri kompilácii.

  // --- Typ operácie (read/write) ---
  typedef enum logic {
    READ_CMD  = 1'b1,
    WRITE_CMD = 1'b0
  } rw_cmd_t;

  // --- Typ adresy SDRAM ---
  // Rozdeľuje systémovú adresu na časti pre banku, riadok a stĺpec.
  typedef struct packed {
    logic [BANK_ADDR_WIDTH-1:0] bank;
    logic [ROW_ADDR_WIDTH-1:0]  row;
    logic [COL_ADDR_WIDTH-1:0]  col;
  } sdram_addr_t;

  // --- Príkaz pre SDRAM kontrolér ---
  // Štruktúra, ktorú používa užívateľská logika na komunikáciu s kontrolérom.
  typedef struct packed {
    rw_cmd_t   rw;              // READ_CMD alebo WRITE_CMD
    logic      auto_precharge;  // 1 = READA/WRITEA
    logic [ADDR_WIDTH-1:0] addr; // 24-bitová systémová adresa
  } sdram_cmd_t;

  // --- Pomocný enum pre FIFO/buffer stav ---
  typedef enum logic [1:0] {
    EMPTY, FILLING, FULL, READING
  } buffer_state_t;

endpackage

`default_nettype wire
`endif
