Jasné! Tu je jednoduchý návrh testbench-u pre tvoj poskytnutý kód, ktorý môžeš simulovať v **Icarus Verilog**. Testbench bude testovať základnú funkčnosť modulu `Vga` a pomocného modulu `PixelCoordinates`.

---

## Predpoklady

* Balíček `VgaPkg` je v samostatnom súbore `VgaPkg.sv`
* Moduly `Line`, `Timing`, `Vga` a `PixelCoordinates` sú v samostatných súboroch
* Súbory sa budú kompilovať spolu, napríklad:

```bash
iverilog -g2012 -o simv VgaPkg.sv Line.sv Timing.sv Vga.sv PixelCoordinates.sv Vga_tb.sv
vvp simv
```

---

## Testbench (Vga\_tb.sv)

```systemverilog
`timescale 1ns/1ns

import VgaPkg::*;

module Vga_tb;

    // Hodiny a reset
    logic clk;
    logic rstn;
    logic enable;

    // Vstupy pre VGA modul
    Line_t h_line;
    Line_t v_line;
    VGA_data_t data_in;

    // Výstupy z VGA modulu
    logic de;
    VGA_data_t data_out;
    VGA_sync_t sync_out;

    // Vstupy pre PixelCoordinates
    logic h_sync, v_sync;

    // Výstupy PixelCoordinates
    logic [LINE_WIDTH-1:0] x;
    logic [LINE_WIDTH-1:0] y;

    // Hodinový generátor (pixel clock) - 25 MHz -> perioda 40ns
    initial clk = 0;
    always #20 clk = ~clk;

    // Inicializácia časovacích parametrov pre VGA 640x480 @ 60Hz
    initial begin
        // Horizontálne časovanie (približne)
        h_line.visible_area = 640;
        h_line.front_porch  = 16;
        h_line.sync_pulse   = 96;
        h_line.back_porch   = 48;
        h_line.polarity     = 1'b0; // nevyužité

        // Vertikálne časovanie (približne)
        v_line.visible_area = 480;
        v_line.front_porch  = 10;
        v_line.sync_pulse   = 2;
        v_line.back_porch   = 33;
        v_line.polarity     = 1'b0; // nevyužité
    end

    // Inicializácia vstupov
    initial begin
        rstn = 0;
        enable = 0;
        data_in = '{red: 5'd10, grn: 6'd20, blu: 5'd15}; // Nejaká test farba

        #100;
        rstn = 1;
        enable = 1;
    end

    // Inštancia VGA modulu
    Vga #(
        .BLANKING_COLOR('{red: 5'h1F, grn: 6'h3F, blu: 5'h00}) // žltá
    ) uut (
        .clk(clk),
        .rstn(rstn),
        .enable(enable),
        .h_line(h_line),
        .v_line(v_line),
        .data_in(data_in),
        .de(de),
        .data_out(data_out),
        .sync_out(sync_out)
    );

    // Priraď signály pre PixelCoordinates
    assign h_sync = sync_out.hs;
    assign v_sync = sync_out.vs;

    // Inštancia PixelCoordinates modulu
    PixelCoordinates #(
        .X_WIDTH(LINE_WIDTH),
        .Y_WIDTH(LINE_WIDTH)
    ) pixel_coord (
        .clk(clk),
        .rstn(rstn),
        .de(de),
        .h_sync(h_sync),
        .v_sync(v_sync),
        .enable(enable),
        .x(x),
        .y(y)
    );

    // Monitoring signálov
    initial begin
        $dumpfile("vga_tb.vcd");
        $dumpvars(0, Vga_tb);

        #200000 $finish; // Simulácia beží 200us (5000 taktov pri 25 MHz)
    end

    // Jednoduchý monitoring v konzole
    always @(posedge clk) begin
        if (de) begin
            $display("Time %t | DE=%b | X=%0d Y=%0d | Color R=%0d G=%0d B=%0d",
                      $time, de, x, y, data_out.red, data_out.grn, data_out.blu);
        end
    end

endmodule
```

---

## Čo testbench robí?

* Generuje hodinový signál 25 MHz
* Inicializuje parametre časovania pre VGA 640x480
* Resetuje systém na začiatku simulácie
* Poskytuje jednoduché RGB dáta na vstup (stálu farbu)
* Pripojí moduly `Vga` a `PixelCoordinates`
* Vypisuje súradnice pixelov a farbu pri aktívnych pixeloch (de=1)
* Vytvorí súbor `vga_tb.vcd` pre vizualizáciu vo Waveform viewer (napr. GTKWave)
* Simuláciu ukončí po 200 us

---

Ak chceš, môžem ti pomôcť s ešte detailnejším testovaním (napr. generovanie rôznych farieb, test synchronizácie, boundary conditions). Ale toto je dobrý štartovací bod pre základnú validáciu tvojho VGA modulu a pixlových súradníc.

---

Potrebuješ ešte návod na simuláciu v Icarus? Alebo ako si pozrieť výsledok vo Waveforme?
