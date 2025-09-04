Jasné, poďme na to — pripravím ti jednoduchý **synchronný FIFO buffer** v SystemVerilogu, ktorý môže byť použitý na medzikrok medzi AXIS vstupom a video timing generátorom.

---

### FIFO Buffer (Sync, parametrický, pre Quartus)

```systemverilog
/**
 * Simple synchronous FIFO buffer
 * Parametrický: šírka dát a hĺbka FIFO
 * Použitie: Bufferovanie dát medzi AXIS a video moduly
 */
module simple_fifo #(
    parameter DATA_WIDTH = 24,   // napr. RGB888
    parameter DEPTH = 512        // veľkosť FIFO
)(
    input logic clk,
    input logic reset_n,

    // Write interface
    input logic wr_en,
    input logic [DATA_WIDTH-1:0] wr_data,
    output logic full,

    // Read interface
    input logic rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic empty
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
    logic [ADDR_WIDTH:0] count;

    // Write pointer & write operation
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            wr_ptr <= 0;
        else if (wr_en && !full)
            wr_ptr <= wr_ptr + 1;
    end

    // Read pointer & read operation
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            rd_ptr <= 0;
        else if (rd_en && !empty)
            rd_ptr <= rd_ptr + 1;
    end

    // Write data into memory
    always_ff @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_ptr] <= wr_data;
    end

    // Output data from memory (combinational read)
    assign rd_data = mem[rd_ptr];

    // Count items in FIFO
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            count <= 0;
        else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: count <= count;
            endcase
        end
    end

    assign full = (count == DEPTH);
    assign empty = (count == 0);

endmodule
```

---

### Vysvetlenie

* FIFO je **synchronný** (všetko na jeden hodinový signál).
* `wr_en` a `rd_en` ovládajú zápis a čítanie.
* FIFO neprepíše, keď je plný, ani nečíta, keď je prázdny.
* Výstup `rd_data` je **combinational** (čítaný z pamäte priamo).
* Parametre umožňujú zmeniť šírku dát a hĺbku FIFO.

---

### Ako to použiť medzi AXIS a Video Timing

* AXIS prijíma dáta (`tdata`) a podľa `tvalid` + `tready` ich zapisuje do FIFO (`wr_en` = `tvalid`, `wr_data` = `tdata`).
* Video timing generátor použije FIFO výstup ako zdroj pixelov (`rd_en` sa môže aktivovať počas `data_enable`).
* FIFO stará sa o vyrovnanie časovania medzi AXIS zdrojom a pixel hodinami.

---

Ak chceš, môžem ti pripraviť aj príklad, ako prepojiť tento FIFO modul s AXIS signálmi alebo video timing signálmi — len daj vedieť!
