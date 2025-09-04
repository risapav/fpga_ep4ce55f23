Máte dobré otázky. Poďme si objasniť tieto dva body ohľadom štruktúry nového návrhu.

-----

### 1\. Kde je definovaný modul `TwoFlopSynchronizer`?

Modul `TwoFlopSynchronizer` je kľúčový pomocný modul pre bezpečný prechod signálov medzi hodinovými doménami (Clock Domain Crossing - CDC). Používa sa na minimalizáciu rizika metastability.

Tento modul ste poskytli v rámci súboru `async_fifo.sv`. Je to štandardný nástroj (utility module), ktorý sa často definuje buď v samostatnom súbore (napr. `synchronizers.sv`), alebo priamo spolu s modulom, ktorý ho najviac potrebuje (v tomto prípade `AsyncFIFO`).

V našom novom `vga_driver` ho používame na synchronizáciu pulzu `start_of_frame` z domény `pix_clk` do domény `axi_clk`.

**Pre vašu referenciu, tu je kód modulu `TwoFlopSynchronizer`:**

```systemverilog
//================================================================
// Pomocný modul: Dvojstupňový synchronizátor
// Používa sa v AsyncFIFO a teraz aj vo vga_driver pre synchronizáciu signálov medzi doménami.
//================================================================
module TwoFlopSynchronizer #(
    parameter WIDTH = 8
)(
    input  logic             clk,    // Cieľový hodinový signál
    input  logic             rst_n,  // Reset pre cieľovú doménu
    input  logic [WIDTH-1:0] d,      // Vstupný signál (z inej domény)
    output logic [WIDTH-1:0] q       // Synchronizovaný výstup
);
    logic [WIDTH-1:0] sync1_reg;

    // Dvojstupňová registrácia na minimalizáciu metastability
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1_reg <= '0;
            q         <= '0;
        end else begin
            sync1_reg <= d;          // Prvý stupeň
            q         <= sync1_reg;  // Druhý stupeň
        end
    end
endmodule
```

Aby váš `vga_driver` fungoval, musí byť tento kód dostupný počas kompilácie (napríklad zahrnutý cez `` `include `` alebo ako súčasť súboru, kde je definované `AsyncFIFO`).

-----

### 2\. Je súbor `AxiStreamToVGA.sv` ešte potrebný?

**Krátka odpoveď: Nie, už ho nepotrebujete.**

**Vysvetlenie:**

Cieľom vytvorenia komplexného modulu `vga_driver.sv` bolo zjednotiť a zapuzdriť celú logiku VGA výstupu. Všetka funkcionalita, ktorú predtým vykonával samostatný modul `AxiStreamToVGA`, bola **integrovaná priamo do nového `vga_driver`**.

Pozrime sa na to, čo sa presunulo:

| Funkcionalita | Pôvodne v `AxiStreamToVGA.sv` | Teraz vo `vga_driver.sv` (Verzia 2.0) |
| :--- | :---: | :---: |
| **Príjem AXI-Stream dát** | Áno | Áno |
| **Inštancia `AsyncFIFO`** | Áno | Áno |
| **Inštancia `Vga_timing`** | Áno | Áno |
| **Logika čítania/zápisu FIFO** | Áno | Áno |
| **Detekcia podtečenia (Underflow)** | Áno | Áno |
| **Generovanie finálnej farby pixelu** | Áno | Áno |
| **Synchronizácia snímky (TREADY control)** | Nie | **Pridané** |

Nový `vga_driver` úplne nahrádza a rozširuje funkčnosť starého `AxiStreamToVGA`. Vďaka tejto refaktorizácii môžete súbor `AxiStreamToVGA.sv` z vášho projektu odstrániť, čím sa zjednoduší štruktúra a odstráni duplicita.
