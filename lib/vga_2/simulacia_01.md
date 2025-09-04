Výborne! Tu je **kompletný testbench pre `Line.sv`**, ktorý:

* simuluje riadiaci modul pre horizontálne alebo vertikálne časovanie VGA signálu,
* kontroluje výstupné stavy `sync` a `state` (očakávané zmeny stavov),
* využíva `640x480_60` horizontálne časovanie zo `vga_pkg`.

---

### ✅ `tb_Line.sv` – Testbench

```systemverilog
//------------------------------------------------------------------------------
// tb_Line.sv – Testbench pre Line modul (časovanie VGA)
//------------------------------------------------------------------------------

`timescale 1ns/1ps
import vga_pkg::*;

module tb_Line;

    //--------------------------------------------------------------------------
    // Signály a testovacie premenné
    //--------------------------------------------------------------------------

    logic clk = 0;
    logic rstn;

    // Parametre horizontálneho časovania pre 640x480@60Hz
    line_t h_line;

    logic hsync;
    VGA_state_e state;

    localparam int CLK_PERIOD = 40; // 25 MHz (typický pixel clock pre 640x480)

    //--------------------------------------------------------------------------
    // Hodiny (25 MHz)
    //--------------------------------------------------------------------------

    always #(CLK_PERIOD/2) clk = ~clk;

    //--------------------------------------------------------------------------
    // DUT – zariadenie pod testom
    //--------------------------------------------------------------------------

    Line #(.LINE_WIDTH(LINE_WIDTH)) dut (
        .clk         (clk),
        .rstn        (rstn),
        .visible_area(h_line.visible_area),
        .front_porch (h_line.front_porch),
        .sync_pulse  (h_line.sync_pulse),
        .back_porch  (h_line.back_porch),
        .polarity    (h_line.polarity),
        .sync        (hsync),
        .state       (state)
    );

    //--------------------------------------------------------------------------
    // Simulácia
    //--------------------------------------------------------------------------

    initial begin
        $display("=== Spúšťam test Line modul pre VGA 640x480@60 ===");

        // Načítaj časovanie
        get_vga_timing(VGA_640x480_60, h_line, /*v_line=*/h_line);

        rstn = 0;
        repeat (2) @(posedge clk);
        rstn = 1;

        // Spusti test na niekoľko riadkov
        for (int i = 0; i < 3 * (h_line.visible_area + h_line.front_porch +
                                 h_line.sync_pulse + h_line.back_porch); i++) begin
            @(posedge clk);
            $display("t=%0t | counter: %0d | state=%s | sync=%b",
                     $time, dut.counter, state.name(), hsync);
        end

        $display("=== Test ukončený ===");
        $finish;
    end

endmodule
```

---

### ✅ Spustenie v simulátore

Ak používaš **ModelSim / QuestaSim / Verilator**, spusti simuláciu takto:

```bash
vlog vga_pkg.sv Line.sv tb_Line.sv
vsim tb_Line
run -all
```

alebo v prípade Verilatoru:

```bash
verilator --cc --exe --build Line.sv vga_pkg.sv tb_Line.sv
```

---

### ✅ Čo sleduje testbench:

* či `state` cyklicky prechádza stavmi: `SYNC → BACKPORCH → ACTIVE → FRONTPORCH`
* či sa `sync` správa podľa polarity (low počas sync, inak high)
* že po `rstn` = 0 sa counter vráti na 0

---

Chceš aj:

* test pre **vertikálne riadenie**?
* alebo **celý VGA výstup do framebufferu** (top-level render test)?
