Tu je kompletne **rozšírený UART prijímač (`uart_rx_fifo_status.sv`)** v **SystemVerilogu**, ktorý obsahuje:

---

## 🧩 **Rozšírenia:**

| Funkcia         | Popis                                                     |
| --------------- | --------------------------------------------------------- |
| FIFO buffer     | Fronta prijatých bajtov (ochrana pred pretečením)         |
| Parita          | Podpora `"NONE"`, `"EVEN"`, `"ODD"`                       |
| Stavové výstupy | `fifo_empty`, `fifo_full`, `fifo_overrun`, `parity_error` |
| Komentáre       | Detailné vysvetlenie pre každý blok                       |

---

## ✅ **UART RX s FIFO a paritou – SystemVerilog kód**:

```systemverilog
module uart_rx_fifo_status #(
    parameter int CLKS_PER_BIT = 87,                    // UART taktovanie
    parameter string PARITY_MODE = "NONE",              // "NONE", "EVEN", "ODD"
    parameter int FIFO_DEPTH = 16                       // FIFO veľkosť
)(
    input  logic        i_Clock,
    input  logic        i_Rst_n,
    input  logic        i_Rx_Serial,

    // Výstupné dáta
    output logic        o_Rx_DV,
    output logic [7:0]  o_Rx_Byte,

    // Stavové výstupy
    output logic        parity_error,
    output logic        fifo_empty,
    output logic        fifo_full,
    output logic        fifo_overrun,
    output logic [4:0]  fifo_count
);

  // FSM stavy
  typedef enum logic [2:0] {
    s_IDLE,
    s_RX_START_BIT,
    s_RX_DATA_BITS,
    s_RX_PARITY_BIT,
    s_RX_STOP_BIT,
    s_CLEANUP
  } state_t;

  state_t r_SM_Main;

  // FIFO
  logic [7:0] fifo [FIFO_DEPTH-1:0];
  logic [4:0] r_Fifo_Head, r_Fifo_Tail, r_Fifo_Count;

  // Interné registre
  logic [7:0] r_Clock_Count;
  logic [2:0] r_Bit_Index;
  logic [7:0] r_Rx_Byte;
  logic       r_Parity_Bit, r_Parity_Calc;
  logic       r_Rx_DV;
  logic       r_Parity_Error;

  // Synchronizácia RX signálu (metastabilita)
  logic r_Rx_Data_R, r_Rx_Data;

  always_ff @(posedge i_Clock) begin
    r_Rx_Data_R <= i_Rx_Serial;
    r_Rx_Data   <= r_Rx_Data_R;
  end

  // FIFO flagy
  assign fifo_empty     = (r_Fifo_Count == 0);
  assign fifo_full      = (r_Fifo_Count == FIFO_DEPTH);
  assign fifo_count     = r_Fifo_Count;
  assign fifo_overrun   = (r_Fifo_Count == FIFO_DEPTH) && r_Rx_DV;
  assign parity_error   = r_Parity_Error;

  // Výstupy
  assign o_Rx_DV   = !fifo_empty;
  assign o_Rx_Byte = fifo[r_Fifo_Head];

  // FIFO výstup (automatické čítanie po jednom bajte pri o_Rx_DV)
  always_ff @(posedge i_Clock) begin
    if (r_Rx_DV && !fifo_full) begin
      fifo[r_Fifo_Tail] <= r_Rx_Byte;
      r_Fifo_Tail <= (r_Fifo_Tail + 1) % FIFO_DEPTH;
      r_Fifo_Count <= r_Fifo_Count + 1;
    end
  end

  // FIFO čítanie simulované ako automatické čítanie pri každom o_Rx_DV
  always_ff @(posedge i_Clock) begin
    if (!fifo_empty) begin
      r_Fifo_Head <= (r_Fifo_Head + 1) % FIFO_DEPTH;
      r_Fifo_Count <= r_Fifo_Count - 1;
    end
  end

  // Hlavný FSM pre prijímač
  always_ff @(posedge i_Clock or negedge i_Rst_n) begin
    if (!i_Rst_n) begin
      r_SM_Main      <= s_IDLE;
      r_Clock_Count  <= 0;
      r_Bit_Index    <= 0;
      r_Rx_DV        <= 0;
      r_Parity_Error <= 0;
      r_Fifo_Head    <= 0;
      r_Fifo_Tail    <= 0;
      r_Fifo_Count   <= 0;
    end else begin
      r_Rx_DV <= 0;
      case (r_SM_Main)
        s_IDLE: begin
          r_Clock_Count <= 0;
          r_Bit_Index   <= 0;
          r_Parity_Calc <= 0;
          if (r_Rx_Data == 0) begin // Detekcia štart bitu
            r_SM_Main <= s_RX_START_BIT;
          end
        end

        s_RX_START_BIT: begin
          if (r_Clock_Count == (CLKS_PER_BIT - 1)/2) begin
            if (r_Rx_Data == 0) begin
              r_Clock_Count <= 0;
              r_SM_Main <= s_RX_DATA_BITS;
            end else
              r_SM_Main <= s_IDLE;
          end else begin
            r_Clock_Count <= r_Clock_Count + 1;
          end
        end

        s_RX_DATA_BITS: begin
          if (r_Clock_Count < CLKS_PER_BIT - 1) begin
            r_Clock_Count <= r_Clock_Count + 1;
          end else begin
            r_Clock_Count <= 0;
            r_Rx_Byte[r_Bit_Index] <= r_Rx_Data;
            r_Parity_Calc <= r_Parity_Calc ^ r_Rx_Data;

            if (r_Bit_Index < 7) begin
              r_Bit_Index <= r_Bit_Index + 1;
            end else begin
              r_Bit_Index <= 0;
              r_SM_Main <= (PARITY_MODE == "NONE") ? s_RX_STOP_BIT : s_RX_PARITY_BIT;
            end
          end
        end

        s_RX_PARITY_BIT: begin
          if (r_Clock_Count < CLKS_PER_BIT - 1) begin
            r_Clock_Count <= r_Clock_Count + 1;
          end else begin
            r_Clock_Count <= 0;
            r_Parity_Bit <= r_Rx_Data;
            case (PARITY_MODE)
              "EVEN": r_Parity_Error <= (r_Rx_Data != ~r_Parity_Calc);
              "ODD" : r_Parity_Error <= (r_Rx_Data !=  r_Parity_Calc);
              default: r_Parity_Error <= 0;
            endcase
            r_SM_Main <= s_RX_STOP_BIT;
          end
        end

        s_RX_STOP_BIT: begin
          if (r_Clock_Count < CLKS_PER_BIT - 1) begin
            r_Clock_Count <= r_Clock_Count + 1;
          end else begin
            r_Clock_Count <= 0;
            r_SM_Main <= s_CLEANUP;
            r_Rx_DV   <= 1;
          end
        end

        s_CLEANUP: begin
          r_SM_Main <= s_IDLE;
        end

        default: r_SM_Main <= s_IDLE;
      endcase
    end
  end

endmodule
```

---

## 🧪 Testovateľné signály:

* `o_Rx_DV` sa nastaví na `1` vždy, keď sa prijme nový bajt a uloží do FIFO.
* `o_Rx_Byte` ukazuje najnovšie dostupné dáta vo fronte.
* `parity_error` sa nastaví, ak sa paritný bit nezhoduje s výpočtom.
* FIFO sa správa ako ring buffer, umožňujúci plynulé čítanie.

---

## ⚙️ Použitie:

* Tento modul je vhodné **pripojiť k mikroprocesoru, FSM, alebo DMA**, ktorý sleduje `o_Rx_DV`, číta `o_Rx_Byte`, a kontroluje `fifo_empty` a `parity_error`.
* Možno ho spojiť s **rozšíreným TX modulom** z predošlej odpovede.

---

Chceš aj:

* 🧪 **Testbench**
* 🔁 **Top modul UART (TX+RX)**
* 📜 **Logický výpis FIFO obsahu počas simulácie**

Stačí povedať!
