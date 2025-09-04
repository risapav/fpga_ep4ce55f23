Skvelé! Začneme s refaktorovaním modulu **`vga_fsm.sv`**, keďže je priamo prepojený s `vga_timing`. Predpokladám, že modul riadi časovanie signálov (`sync`, `blank`, `active`) pre horizontálnu a vertikálnu os.

---

## ✅ Refaktorovaný a komentovaný `vga_fsm.sv`

> 📝 Predpoklady:
>
> * `line_t` obsahuje: `visible_area`, `front_porch`, `sync_pulse`, `back_porch`, `polarity`
> * Modul `vga_fsm` je parametrizovaný šírkou počítadla
> * Modul má výstup typu `fsm_output_t` so signálmi: `sync`, `blank`, `active`

---

```systemverilog
// vga_fsm.sv - Finite State Machine pre generovanie VGA signálov
//
// Verzia 3.0 - Refaktoring, komentáre a robustnosť

`ifndef VGA_FSM_DONE
`define VGA_FSM_DONE

`default_nettype none

import vga_pkg::*;

module vga_fsm #(
    parameter int WIDTH = 10  // Šírka vstupného počítadla (napr. 10-bit pre 1024)
)(
    input  logic             clk,     // Hodinový signál
    input  logic             rstn,    // Asynchrónny reset (aktívny v L)
    input  logic [WIDTH-1:0] pos,     // Aktuálna pozícia (x alebo y)
    input  line_t            line,    // Parametre časovania
    output fsm_output_t      out      // Výstupné signály: sync, blank, active
    // output state_t        state;   // (voliteľný výstup stavu pre debug)
);

    // === Výpočty hraníc pre každú fázu signálu ===
    logic [WIDTH-1:0] visible_end   = line.visible_area;
    logic [WIDTH-1:0] front_end     = visible_end + line.front_porch;
    logic [WIDTH-1:0] sync_end      = front_end + line.sync_pulse;
    logic [WIDTH-1:0] total_pixels  = sync_end + line.back_porch;

    // === Generovanie výstupných signálov ===

    // Synchronizačný impulz: počas sync_pulse
    always_comb begin
        out.sync   = (pos >= front_end) && (pos < sync_end);
        out.blank  = (pos >= visible_end);   // Blanking mimo viditeľnej oblasti
        out.active = (pos < visible_end);    // Viditeľná oblasť
    end

    // Reset logika - bezpečný stav výstupu
    always_ff @(posedge clk) begin
        if (!rstn) begin
            out.sync   <= 1'b0;
            out.blank  <= 1'b1;
            out.active <= 1'b0;
        end else begin
            out.sync   <= (pos >= front_end) && (pos < sync_end);
            out.blank  <= (pos >= visible_end);
            out.active <= (pos < visible_end);
        end
    end

endmodule

`endif // VGA_FSM_DONE
```

---

## 📌 Poznámky:

| Zložka                                | Popis                                                               |
| ------------------------------------- | ------------------------------------------------------------------- |
| **Segmentácia časovania**             | Logicky rozdelené fázy: `visible → front porch → sync → back porch` |
| **Bezpečný reset**                    | Výstupy idú do neaktívnych stavov pri `!rstn`                       |
| **Parametrizácia**                    | Zabezpečuje prispôsobenie rôznym rozlíšeniam                        |
| **Kombinačná aj registrovaná logika** | Základná kombinácia je okamžitá; výstup sa registruje pre stabilitu |

---

## 🎁 Chceš ešte niečo k tomu?

Môžem ti:

* 🔬 vygenerovať **`vga_pkg.sv`** (ak ho nemáš),
* 🧪 vytvoriť **testbench** pre `vga_timing` alebo `vga_fsm`,
* 📉 pridať **vizualizáciu časovania** ako VCD alebo Waveform šablónu (napr. pre GTKWave).

Stačí povedať.
