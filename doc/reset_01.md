Tu máš **parametrizovateľný a znovupoužiteľný modul** `ResetSync`, ktorý bezpečne **synchronizuje asynchrónny reset do ľubovoľnej clock domény**:

---

## 📦 `ResetSync.sv` – Modul na synchronizáciu resetu

```systemverilog
//=============================================================================
// Modul: ResetSync
// Popis: Bezpečná synchronizácia asynchrónneho resetu do hodinovej domény
// Parametre:
//   N_STAGES – počet registrov (typicky 2 pre bežnú synchronizáciu)
//=============================================================================
module ResetSync #(
    parameter int N_STAGES = 2  // Môžeš zmeniť na 3 pre vyššiu odolnosť
) (
    input  logic clk,           // Hodiny cieľovej domény
    input  logic resetn_async,  // Asynchrónny reset, aktívne LOW
    output logic reset_sync     // Synchronizovaný reset, aktívne HIGH
);

    // Pole registrov pre synchronizáciu
    logic [N_STAGES-1:0] sync_reg;

    // Inicializácia a synchronizácia
    always_ff @(posedge clk or negedge resetn_async) begin
        if (!resetn_async)
            sync_reg <= '1;  // Reset synchronizérov na 1 (aktívny reset)
        else
            sync_reg <= {sync_reg[N_STAGES-2:0], 1'b0};
    end

    // Výstup – posledný FF v reťazci
    assign reset_sync = sync_reg[N_STAGES-1];

endmodule
```

---

## ✅ Použitie v tvojom top-level module

```systemverilog
logic reset_pix_sync;

ResetSync #(.N_STAGES(2)) reset_sync_inst (
    .clk           (pixel_clk),
    .resetn_async  (RESET_N),
    .reset_sync    (reset_pix_sync)
);
```

---

## 💡 Tipy

* **Pre bežné použitie sú 2 etapy (`N_STAGES = 2`) úplne dostatočné.**
* Pri **veľmi vysokých frekvenciách alebo náročnom časovaní** môžeš zvýšiť na 3.
* Môžeš si vytvoriť aj viacero inštancií – jednu pre každú doménu hodín.

---

Ak chceš, môžem ti k tomuto pridať aj:

* testbench,
* integráciu do Quartus projektu,
* alebo aj verziu s výstupom `resetn_sync` (aktívny LOW).
