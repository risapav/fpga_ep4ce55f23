// seg7_driver_if.sv
// Interface pre ovládanie 7-segmentového displeja s podporou invertovania výstupov
`default_nettype none

interface seg7_driver_if #(
    parameter int DIGITS = 3,        // počet číslic (pre digit_en)
    parameter bit INVERT_DIGITS = 0, // 1 pre common anode
    parameter bit INVERT_SEGS   = 0  // 1 pre common anode
) ();

  // Výstupy do displeja
  logic [6:0] seg;         // Segmenty A-G (bit 0 = A, bit 6 = G)
  logic       dp;          // Desatinná bodka
  logic [DIGITS-1:0] digit_en;  // Výber číslice (napr. anódy/katódy)

  // Modport pre pripojenie výstupov z ovládača
  modport output_port (
    output seg,
    output dp,
    output digit_en
  );

  // Voliteľne: Modport pre čítanie v testbench
  modport monitor_port (
    input seg,
    input dp,
    input digit_en
  );

endinterface
