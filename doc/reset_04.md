Perfektne! Tu je pripravený a **znovupoužiteľný modul `ResetController.sv`**, ktorý:

* **Spojí** signály `RESET_N` a `pll_locked` do jedného globálneho resetu,
* **Synchronizuje ho do 3 rôznych hodinových domén**: `pixel_clk`, `axi_clk`, `sdram_clk`,
* A poskytne **aktívne LOW výstupy**: `pixel_rstn_sync`, `axi_rstn_sync`, `sdram_rstn_sync`.

---

## 📦 `ResetController.sv`

```systemverilog
//=============================================================================
// Modul: ResetController
// Popis: Kombinuje externý reset a pll_locked a vytvára synchrónne
//        resety pre viacero clock domén (aktívne LOW).
//=============================================================================
`timescale 1ns/1ps
module ResetController #(
    parameter int N_STAGES = 2
)(
    input  logic RESET_N,        // Asynchrónny externý reset (tlačidlo)
    input  logic pll_locked,     // PLL LOCKED signál

    // Clock signály jednotlivých domén
    input  logic pixel_clk,
    input  logic axi_clk,
    input  logic sdram_clk,

    // Synchronizované výstupné resety (aktívne LOW)
    output logic pixel_rstn_sync,
    output logic axi_rstn_sync,
    output logic sdram_rstn_sync
);

    // Kombinovaný asynchrónny reset (aktívne LOW)
    logic global_resetn_async;
    assign global_resetn_async = RESET_N & pll_locked;

    // Synchronizované resety cez ResetSync moduly
    ResetSync #(.N_STAGES(N_STAGES)) u_pixel_reset_sync (
        .clk           (pixel_clk),
        .resetn_async  (global_resetn_async),
        .resetn_sync   (pixel_rstn_sync)
    );

    ResetSync #(.N_STAGES(N_STAGES)) u_axi_reset_sync (
        .clk           (axi_clk),
        .resetn_async  (global_resetn_async),
        .resetn_sync   (axi_rstn_sync)
    );

    ResetSync #(.N_STAGES(N_STAGES)) u_sdram_reset_sync (
        .clk           (sdram_clk),
        .resetn_async  (global_resetn_async),
        .resetn_sync   (sdram_rstn_sync)
    );

endmodule
```

---

## 📦 Ešte raz: `ResetSync.sv` (použitý vyššie)

Uisti sa, že máš aj tento modul (ak ho nemáš, tu je):

```systemverilog
module ResetSync #(
    parameter int N_STAGES = 2
) (
    input  logic clk,
    input  logic resetn_async,
    output logic resetn_sync
);
    logic [N_STAGES-1:0] sync_reg;

    always_ff @(posedge clk or negedge resetn_async) begin
        if (!resetn_async)
            sync_reg <= '0;
        else
            sync_reg <= {sync_reg[N_STAGES-2:0], 1'b1};
    end

    assign resetn_sync = sync_reg[N_STAGES-1];
endmodule
```

---

## 🧪 Príklad použitia v `top.sv`:

```systemverilog
logic pixel_rstn_sync, axi_rstn_sync, sdram_rstn_sync;

ResetController reset_ctrl_inst (
    .RESET_N         (RESET_N),
    .pll_locked      (pll_locked),
    .pixel_clk       (pixel_clk),
    .axi_clk         (axi_clk),
    .sdram_clk       (sdram_clk),
    .pixel_rstn_sync (pixel_rstn_sync),
    .axi_rstn_sync   (axi_rstn_sync),
    .sdram_rstn_sync (sdram_rstn_sync)
);
```

---

## 🔧 Možné rozšírenia:

* Podpora viac než 3 clock domén (pomocou `generate`),
* Výber medzi `resetn_sync` (LOW) a `reset_sync` (HIGH),
* Testbench s náhodným RESET\_N a `pll_locked`.

Chceš aj testbench alebo rozšírenú verziu?
