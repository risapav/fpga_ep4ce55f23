Tu je **detailná analýza a návrhy vylepšení** pre daný UART vysielač (`uart_tx`) s cieľom zvýšiť **spoľahlivosť, čitateľnosť, syntetizovateľnosť** a zabezpečiť **kompatibilitu so syntézou v Quartus** a ďalších nástrojoch (napr. Vivado).

---

## ✅ Čo kód robí správne:

* Používa **stavový automat (FSM)** na riadenie sekvencie: `IDLE → START → DATA → STOP → CLEANUP`.
* Správne generuje **start/stop bit**, **sériové vysielanie** 8 dátových bitov.
* Výstupy `o_Tx_Done` a `o_Tx_Active` sú dobre oddelené.
* Pracuje s `CLKS_PER_BIT` na časovanie jednotlivých bitov podľa UART baudovej rýchlosti.

---

## ⚠️ **Návrhy na vylepšenie:**

### 1. ❗ **Chýba asynchrónny (alebo synchrónny) reset**

* V praxi sa FPGA inicializuje reset signálom. Aktuálny kód sa spolieha na počiatočné priradenia registrov, čo **nie je bezpečné ani prenositeľné**.
* **Riešenie**: Pridať `i_Rst_n` vstup a `always @(posedge i_Clock or negedge i_Rst_n)`.

---

### 2. ⚠️ **Počiatočné priradenia registrov (`= 0`) nemusia fungovať správne pri syntéze**

* V Quartuse sú *počiatočné hodnoty registrov po zapnutí* často ignorované.
* Lepšie riešenie je vyčistiť ich v rámci resetovacej vetvy.

---

### 3. ⚠️ **Výstup `o_Tx_Serial` by nemal byť `reg` ak je priamo riadený z FSM**

* V SystemVerilog by sa mal namiesto `output reg` používať jednoducho `logic`.

---

### 4. ✅ **Mierne zjednodušenie FSM**:

* V `s_TX_DATA_BITS` sa opakuje `r_SM_Main <= s_TX_DATA_BITS;` → to tam nie je potrebné (výraz sa nemení).
* `default` vetva môže byť zjednodušená.

---

### 5. ✅ **Komentáre v FSM by sa dali zhutniť a prehľadne odlíšiť sekcie**

---

## 🔧 **Vylepšený kód: Quartus-kompatibilný, s komentármi, resetom a čistým zápisom**

```systemverilog
module uart_tx 
#(
    parameter CLKS_PER_BIT = 87  // napr. 10 MHz / 115200 baud
)
(
    input        i_Clock,       // systémový clock
    input        i_Rst_n,       // aktívne nízky reset
    input        i_Tx_DV,       // požiadavka na prenos
    input  [7:0] i_Tx_Byte,     // bajt na odoslanie
    output logic o_Tx_Active,   // aktívny prenos (1 = prenášame)
    output logic o_Tx_Serial,   // sériový výstup na UART TX
    output logic o_Tx_Done      // HIGH na 1 takt po dokončení
);

  // Stavový automat
  typedef enum logic [2:0] {
    s_IDLE,
    s_TX_START_BIT,
    s_TX_DATA_BITS,
    s_TX_STOP_BIT,
    s_CLEANUP
  } state_t;

  state_t r_SM_Main;

  // Interné registre
  logic [7:0] r_Clock_Count;
  logic [2:0] r_Bit_Index;
  logic [7:0] r_Tx_Data;

  //--------------------------------------------------
  // FSM – UART vysielanie (so synchronizovaným resetom)
  //--------------------------------------------------
  always_ff @(posedge i_Clock or negedge i_Rst_n) begin
    if (!i_Rst_n) begin
      r_SM_Main     <= s_IDLE;
      r_Clock_Count <= 0;
      r_Bit_Index   <= 0;
      r_Tx_Data     <= 8'd0;
      o_Tx_Serial   <= 1'b1;
      o_Tx_Done     <= 1'b0;
      o_Tx_Active   <= 1'b0;
    end else begin
      case (r_SM_Main)

        // Čaká sa na požiadavku na vysielanie
        s_IDLE: begin
          o_Tx_Serial   <= 1'b1;
          o_Tx_Done     <= 1'b0;
          r_Clock_Count <= 0;
          r_Bit_Index   <= 0;

          if (i_Tx_DV) begin
            o_Tx_Active <= 1'b1;
            r_Tx_Data   <= i_Tx_Byte;
            r_SM_Main   <= s_TX_START_BIT;
          end
        end

        // START bit = 0
        s_TX_START_BIT: begin
          o_Tx_Serial <= 1'b0;
          if (r_Clock_Count < CLKS_PER_BIT - 1)
            r_Clock_Count <= r_Clock_Count + 1;
          else begin
            r_Clock_Count <= 0;
            r_SM_Main     <= s_TX_DATA_BITS;
          end
        end

        // Vysielanie 8 dátových bitov
        s_TX_DATA_BITS: begin
          o_Tx_Serial <= r_Tx_Data[r_Bit_Index];

          if (r_Clock_Count < CLKS_PER_BIT - 1) begin
            r_Clock_Count <= r_Clock_Count + 1;
          end else begin
            r_Clock_Count <= 0;

            if (r_Bit_Index < 7)
              r_Bit_Index <= r_Bit_Index + 1;
            else begin
              r_Bit_Index <= 0;
              r_SM_Main   <= s_TX_STOP_BIT;
            end
          end
        end

        // STOP bit = 1
        s_TX_STOP_BIT: begin
          o_Tx_Serial <= 1'b1;
          if (r_Clock_Count < CLKS_PER_BIT - 1)
            r_Clock_Count <= r_Clock_Count + 1;
          else begin
            r_Clock_Count <= 0;
            o_Tx_Done     <= 1'b1;
            o_Tx_Active   <= 1'b0;
            r_SM_Main     <= s_CLEANUP;
          end
        end

        // Krátky prechod späť do IDLE
        s_CLEANUP: begin
          o_Tx_Done <= 1'b0;
          r_SM_Main <= s_IDLE;
        end

        default: r_SM_Main <= s_IDLE;
      endcase
    end
  end

endmodule
```

---

## 📝 Záver – Výhody vylepšenej verzie:

| Vylepšenie                     | Prínos                                        |
| ------------------------------ | --------------------------------------------- |
| Reset (`i_Rst_n`)              | bezpečná inicializácia, Quartus-kompatibilita |
| `logic` namiesto `reg`         | moderný SystemVerilog štýl                    |
| Oddelené výstupy v `always_ff` | zrozumiteľnosť, čistý kód                     |
| Lepšie komentáre               | ľahšia údržba                                 |
| `typedef enum` pre FSM         | prehľadný FSM kód                             |

---

Ak chceš aj testbench, FIFO verziu, alebo verziu s paritou, rád pripravím – stačí povedať.
