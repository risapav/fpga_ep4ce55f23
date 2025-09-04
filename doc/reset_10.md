Jasné, ukážem ti synchronizáciu oboch typov synchrónnych resetov aj s jednoduchým synchronizérom — pre `reset_n` (aktívne nízky) a `reset` (aktívne vysoký).

---

# Synchrónna reset synchronizácia – príklady

---

## 1) Synchronizér pre synchrónny **aktívne nízky reset (`reset_n`)**

```systemverilog
module resetn_sync (
    input  logic clk,
    input  logic reset_n_async,  // asynchrónny reset aktívny LOW
    output logic reset_n_sync    // synchronizovaný reset aktívny LOW
);

    logic [1:0] sync_ff;

    always_ff @(posedge clk) begin
        sync_ff[0] <= reset_n_async;
        sync_ff[1] <= sync_ff[0];
    end

    assign reset_n_sync = sync_ff[1];

endmodule
```

* Tu sa asynchrónny reset `reset_n_async` synchronizuje do clock domény.
* Výstup `reset_n_sync` je tiež aktívne nízky a už synchronizovaný.

---

## 2) Synchronizér pre synchrónny **aktívne vysoký reset (`reset`)**

```systemverilog
module reset_sync (
    input  logic clk,
    input  logic reset_async,    // asynchrónny reset aktívny HIGH
    output logic reset_sync      // synchronizovaný reset aktívny HIGH
);

    logic [1:0] sync_ff;

    always_ff @(posedge clk) begin
        sync_ff[0] <= reset_async;
        sync_ff[1] <= sync_ff[0];
    end

    assign reset_sync = sync_ff[1];

endmodule
```

* Rovnaký princíp, len signály sú aktívne HIGH.

---

## Ako používať v logike?

Pre `reset_n_sync`:

```systemverilog
always_ff @(posedge clk) begin
    if (!reset_n_sync) // reset aktívny LOW
        state <= IDLE;
    else
        state <= next_state;
end
```

Pre `reset_sync`:

```systemverilog
always_ff @(posedge clk) begin
    if (reset_sync) // reset aktívny HIGH
        state <= IDLE;
    else
        state <= next_state;
end
```

---

## Prečo synchronizovať reset?

* Asynchrónny reset môže prísť v hociktorom okamihu a spôsobiť metastabilitu.
* Synchronizácia resetu do príslušnej clock domény zaručuje čisté, stabilné prechody a eliminuje metastabilitu.

---

### Ak chceš, môžem ti pripraviť aj komplexnejší modul, ktorý na vstupe berie asynchrónny reset (aktívne LOW či HIGH) a na výstupe dá synchronizovaný reset podľa požiadaviek.

Chceš? Alebo pokračujeme rovno na asynchrónny reset a jeho synchronizáciu?
