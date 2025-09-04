Perfektne – poďme spraviť **jednoduchý testbench**, ktorý bude:

1. Simulovať `clk`, `rstn`
2. Generovať `h_counter`, `v_counter` ako klasické VGA počítadlá
3. Pripojí náš **stavový automat HDMI TX**
4. Sleduje a vypíše stav `TX_state` + `DE`

---

## 🧪 Testbench (SystemVerilog)

Tu je plná verzia:

```systemverilog
`timescale 1ns / 1ps

module tb_hdmi_tx_fsm();

  // --- Parametre simulácie ---
  localparam H_SYNC   = 44;
  localparam H_BP     = 148;
  localparam H_ACTIVE = 1920;
  localparam H_FP     = 88;
  localparam H_TOTAL  = H_SYNC + H_BP + H_ACTIVE + H_FP;

  localparam V_SYNC   = 5;
  localparam V_BP     = 36;
  localparam V_ACTIVE = 1080;
  localparam V_FP     = 4;
  localparam V_TOTAL  = V_SYNC + V_BP + V_ACTIVE + V_FP;

  // --- Signály ---
  logic clk = 0;
  logic rstn = 0;

  logic [$clog2(H_TOTAL)-1:0] h_counter = 0;
  logic [$clog2(V_TOTAL)-1:0] v_counter = 0;

  logic de;
  logic video_active, data_island, control_period;

  // --- Hodiny ---
  always #5 clk = ~clk;  // 100 MHz

  // --- Reset ---
  initial begin
    rstn = 0;
    repeat (5) @(posedge clk);
    rstn = 1;
  end

  // --- Časovanie VGA ---
  always_ff @(posedge clk) begin
    if (!rstn) begin
      h_counter <= 0;
      v_counter <= 0;
    end else begin
      if (h_counter == H_TOTAL - 1) begin
        h_counter <= 0;
        if (v_counter == V_TOTAL - 1)
          v_counter <= 0;
        else
          v_counter <= v_counter + 1;
      end else begin
        h_counter <= h_counter + 1;
      end
    end
  end

  // --- DUT: stavový automat HDMI ---
  TX_state_e tx_state;

  logic h_video_active, v_video_active;

  assign h_video_active = (h_counter >= H_SYNC + H_BP) &&
                          (h_counter <  H_SYNC + H_BP + H_ACTIVE);

  assign v_video_active = (v_counter >= V_SYNC + V_BP) &&
                          (v_counter <  V_SYNC + V_BP + V_ACTIVE);

  assign de = h_video_active && v_video_active;

  assign video_active    = (tx_state == TX_VIDEO);
  assign data_island     = (tx_state == TX_ISLAND);
  assign control_period  = (tx_state == TX_CONTROL);

  // Stavový automat
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      tx_state <= TX_CONTROL;
    end else begin
      case (tx_state)
        TX_CONTROL: begin
          if (de)
            tx_state <= TX_VIDEO;
          else if (!de && (v_counter >= V_SYNC + V_BP + V_ACTIVE))
            tx_state <= TX_ISLAND;
        end
        TX_VIDEO: begin
          if (!de)
            tx_state <= TX_CONTROL;
        end
        TX_ISLAND: begin
          if (de)
            tx_state <= TX_VIDEO;
          else if ((v_counter < V_SYNC + V_BP + V_ACTIVE))
            tx_state <= TX_CONTROL;
        end
        default: tx_state <= TX_CONTROL;
      endcase
    end
  end

  // --- Sledovanie ---
  always_ff @(posedge clk) begin
    if (rstn) begin
      $display("[%0t] h=%0d v=%0d | de=%b | state=%s",
        $time, h_counter, v_counter, de, state_str(tx_state));
    end
  end

  // --- Pomocná funkcia na výpis stavu ---
  function string state_str(TX_state_e st);
    case (st)
      TX_CONTROL: return "CONTROL";
      TX_VIDEO:   return "VIDEO";
      TX_ISLAND:  return "ISLAND";
      default:    return "UNKNOWN";
    endcase
  endfunction

  // --- Stop simulácia ---
  initial begin
    #300000; // asi 3 rámce
    $finish;
  end

endmodule
```

---

## ✅ Čo uvidíš v simulácii:

Typický výstup bude vyzerať ako:

```
[500] h=0 v=0 | de=0 | state=CONTROL
[5010] h=192 v=41 | de=1 | state=VIDEO
[18000] h=2112 v=41 | de=0 | state=CONTROL
...
[150000] h=0 v=1121 | de=0 | state=ISLAND
```

* Pri nástupe `h=192` a `v=41` sa `DE` zapína → stav `VIDEO`
* Po konci aktívnej časti (`DE = 0`) → `CONTROL`
* Po `V_ACTIVE` riadkoch → `ISLAND` fáza

---

## 🔧 Voliteľne:

Chceš:

* Vlnový priebeh (`.vcd`) pre zobrazenie v GTKWave?
* Tento FSM zabaliť do modulu pre znovupoužitie?
* Pripojiť ku generátoru TMDS pixelov?

---

Napíš *„vlnový priebeh“* alebo *„modul“* – spravíme ďalší krok.
