Výborne, takýto blikajúci LED modul je ideálny kandidát na univerzálny (znovupoužiteľný) modul s parametrami.

Navrhujem vytvoriť samostatný modul, ktorý:

* Má ako vstup hodinový signál (`clk`),
* Aktívny nízky reset (`rstn`),
* Parameter na nastavenie frekvencie blikania (resp. divider podľa clock freq),
* Výstupný signál pre LED (blikajúci).

---

## Príklad univerzálneho modulu pre blikajúcu LED

```systemverilog
module BlinkLed #(
    parameter int CLOCK_FREQ_HZ = 50_000_000,  // predvolená frekvencia hodinového signálu
    parameter int BLINK_HZ      = 1            // frekvencia blikania LED v Hz
)(
    input  logic clk,
    input  logic rstn,
    output logic led_out
);

    // divider = počet taktov pre jeden polperiódu blikania
    localparam int BLINK_DIVIDER = (CLOCK_FREQ_HZ == 0) ? 1 : CLOCK_FREQ_HZ / (2 * BLINK_HZ);
    logic [$clog2(BLINK_DIVIDER)-1:0] counter;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            counter <= 0;
            led_out <= 1'b0;
        end else if (counter == BLINK_DIVIDER - 1) begin
            counter <= 0;
            led_out <= ~led_out;
        end else begin
            counter <= counter + 1;
        end
    end

endmodule
```

---

## Ako ho použiť v tvojom `top` module?

```systemverilog
logic led0_reg;

BlinkLed #(
    .CLOCK_FREQ_HZ(PIXEL_CLOCK_HZ),  // musíš definovať PIXEL_CLOCK_HZ ako integer
    .BLINK_HZ(1)                     // blikanie 1 Hz, môžeš upraviť
) blink_inst (
    .clk(pixel_clk),
    .rstn(pix_rstn_sync),
    .led_out(led0_reg)
);
```

---

## Výhody

* Modul je čitateľný a znovupoužiteľný,
* Parametre umožňujú flexibilne nastaviť frekvenciu blikania podľa konkrétneho hodinového signálu,
* Oddelený od hlavnej logiky, jednoduchšie testovanie a údržba.

---

Ak chceš, môžem pripraviť aj verziu s asynchrónnym resetom, alebo modifikáciu na viacero LED výstupov. Čo povieš?
