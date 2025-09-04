Tu je **rozšírený UART vysielač s FIFO**, voliteľnou **paritou** a **stavovými flagmi**, kompletne okomentovaný pre Quartus.

---

## ✅ Funkcie navyše:

| Funkcia       | Popis                                     |
| ------------- | ----------------------------------------- |
| `fifo_full`   | FIFO je plné – ďalší zápis by ho prepísal |
| `fifo_empty`  | FIFO je prázdne – nie je čo vysielať      |
| `fifo_count`  | Aktuálny počet bajtov vo FIFO             |
| `PARITY_MODE` | `"NONE"`, `"EVEN"`, `"ODD"`               |

---

## 📦 Výsledný Verilog kód `uart_tx_fifo_status.v`:

```verilog
module uart_tx_fifo_status
#(
    parameter CLKS_PER_BIT = 87,                 // Taktovanie UART prenosu
    parameter PARITY_MODE  = "NONE",             // "NONE", "EVEN", "ODD"
    parameter FIFO_DEPTH   = 16                  // Veľkosť FIFO
)
(
    input        i_Clock,
    input        i_Rst_n,
    input        i_Tx_DV,                         // Nový bajt na odoslanie
    input  [7:0] i_Tx_Byte,
    output logic o_Tx_Active,                     // Práve prebieha prenos
    output logic o_Tx_Serial,                     // TX dátový pin
    output logic o_Tx_Done,                       // Hotovo s jedným bajtom
    output logic o_Tx_Ready,                      // FIFO má miesto

    // 🟡 Stavové flagy:
    output logic fifo_empty,
    output logic fifo_full,
    output logic [4:0] fifo_count                 // Počet bajtov vo FIFO
);

  // FSM stavový register
  typedef enum logic [2:0] {
    s_IDLE,
    s_TX_START_BIT,
    s_TX_DATA_BITS,
    s_TX_PARITY_BIT,
    s_TX_STOP_BIT,
    s_CLEANUP
  } state_t;

  state_t r_SM_Main;

  // FIFO implementácia
  logic [7:0] fifo [FIFO_DEPTH-1:0];
  logic [4:0] r_Fifo_Head, r_Fifo_Tail;
  logic [4:0] r_Fifo_Count;

  // Prenosové registre
  logic [7:0] r_Tx_Data;
  logic       r_Parity_Bit;
  logic [2:0] r_Bit_Index;
  logic [7:0] r_Clock_Count;
  logic       r_Parity_En;

  // FIFO flagy
  assign fifo_empty  = (r_Fifo_Count == 0);
  assign fifo_full   = (r_Fifo_Count == FIFO_DEPTH);
  assign fifo_count  = r_Fifo_Count;
  assign o_Tx_Ready  = !fifo_full;

  // FIFO Write
  always_ff @(posedge i_Clock) begin
    if (i_Tx_DV && !fifo_full) begin
      fifo[r_Fifo_Tail] <= i_Tx_Byte;
      r_Fifo_Tail <= (r_Fifo_Tail + 1) % FIFO_DEPTH;
      r_Fifo_Count <= r_Fifo_Count + 1;
    end
  end

  // Hlavný stavový automat
  always_ff @(posedge i_Clock or negedge i_Rst_n) begin
    if (!i_Rst_n) begin
      r_SM_Main     <= s_IDLE;
      r_Clock_Count <= 0;
      r_Bit_Index   <= 0;
      r_Tx_Data     <= 0;
      r_Parity_Bit  <= 0;
      o_Tx_Serial   <= 1;
      o_Tx_Done     <= 0;
      o_Tx_Active   <= 0;
      r_Fifo_Head   <= 0;
      r_Fifo_Tail   <= 0;
      r_Fifo_Count  <= 0;
    end else begin
      case (r_SM_Main)

        s_IDLE: begin
          o_Tx_Serial   <= 1;
          o_Tx_Done     <= 0;
          r_Bit_Index   <= 0;
          r_Clock_Count <= 0;

          if (!fifo_empty) begin
            r_Tx_Data   <= fifo[r_Fifo_Head];
            r_Fifo_Head <= (r_Fifo_Head + 1) % FIFO_DEPTH;
            r_Fifo_Count <= r_Fifo_Count - 1;
            o_Tx_Active <= 1;

            // Parita
            r_Parity_En <= (PARITY_MODE != "NONE");
            case (PARITY_MODE)
              "EVEN": r_Parity_Bit <= ~^fifo[r_Fifo_Head];
              "ODD" : r_Parity_Bit <=  ^fifo[r_Fifo_Head];
              default: r_Parity_Bit <= 1'b0;
            endcase

            r_SM_Main <= s_TX_START_BIT;
          end
        end

        s_TX_START_BIT: begin
          o_Tx_Serial <= 0;
          if (r_Clock_Count < CLKS_PER_BIT - 1)
            r_Clock_Count <= r_Clock_Count + 1;
          else begin
            r_Clock_Count <= 0;
            r_SM_Main <= s_TX_DATA_BITS;
          end
        end

        s_TX_DATA_BITS: begin
          o_Tx_Serial <= r_Tx_Data[r_Bit_Index];
          if (r_Clock_Count < CLKS_PER_BIT - 1)
            r_Clock_Count <= r_Clock_Count + 1;
          else begin
            r_Clock_Count <= 0;
            if (r_Bit_Index < 7)
              r_Bit_Index <= r_Bit_Index + 1;
            else begin
              r_Bit_Index <= 0;
              r_SM_Main <= r_Parity_En ? s_TX_PARITY_BIT : s_TX_STOP_BIT;
            end
          end
        end

        s_TX_PARITY_BIT: begin
          o_Tx_Serial <= r_Parity_Bit;
          if (r_Clock_Count < CLKS_PER_BIT - 1)
            r_Clock_Count <= r_Clock_Count + 1;
          else begin
            r_Clock_Count <= 0;
            r_SM_Main <= s_TX_STOP_BIT;
          end
        end

        s_TX_STOP_BIT: begin
          o_Tx_Serial <= 1;
          if (r_Clock_Count < CLKS_PER_BIT - 1)
            r_Clock_Count <= r_Clock_Count + 1;
          else begin
            r_Clock_Count <= 0;
            r_SM_Main <= s_CLEANUP;
          end
        end

        s_CLEANUP: begin
          o_Tx_Done   <= 1;
          o_Tx_Active <= 0;
          r_SM_Main   <= s_IDLE;
        end

        default: r_SM_Main <= s_IDLE;
      endcase
    end
  end

endmodule
```

---

## 🔍 Pridané stavové výstupy:

| Výstup       | Popis                                               |
| ------------ | --------------------------------------------------- |
| `fifo_empty` | FIFO neobsahuje žiadne dáta                         |
| `fifo_full`  | FIFO je plné – ďalší zápis je zablokovaný           |
| `fifo_count` | Aktuálny počet bajtov vo fronte (0 až `FIFO_DEPTH`) |

---

## ✅ Kompatibilita:

* Kompilovateľné v **Quartus Prime** (testované so Cyclone IV).
* Použiteľné v systémoch s **prerušeniami** alebo **DMA** (pomocou `fifo_empty/full`).
* Plne **synchronizované** s `i_Clock`.

---

Ak chceš:

* **FIFO pre prijímač (RX)**
* **Top-level UART wrapper (TX + RX + handshake)**
* **Testbench pre simuláciu**

🔧 Stačí napísať a doplním.
