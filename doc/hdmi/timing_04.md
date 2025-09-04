Jasné, poďme na to!

---

## 1. Zabalenie FSM do modulu

Najskôr urobíme samostatný modul `hdmi_tx_fsm.sv`, ktorý dostane ako vstupy `clk`, `rstn`, `h_counter`, `v_counter` a parametre sync, a na výstupe bude stav aj `de`.

```systemverilog
// hdmi_tx_fsm.sv
`timescale 1ns / 1ps

module hdmi_tx_fsm #(
  parameter int H_SYNC   = 44,
  parameter int H_BP     = 148,
  parameter int H_ACTIVE = 1920,
  parameter int V_SYNC   = 5,
  parameter int V_BP     = 36,
  parameter int V_ACTIVE = 1080
)(
  input  logic clk,
  input  logic rstn,
  input  logic [$clog2(H_SYNC+H_BP+H_ACTIVE+100)-1:0] h_counter,
  input  logic [$clog2(V_SYNC+V_BP+V_ACTIVE+100)-1:0] v_counter,

  output logic de,
  output logic video_active,
  output logic data_island,
  output logic control_period
);

  typedef enum logic [1:0] {
    TX_CONTROL,
    TX_VIDEO,
    TX_ISLAND
  } TX_state_e;

  TX_state_e tx_state;

  logic h_video_active, v_video_active;

  assign h_video_active = (h_counter >= H_SYNC + H_BP) &&
                          (h_counter <  H_SYNC + H_BP + H_ACTIVE);

  assign v_video_active = (v_counter >= V_SYNC + V_BP) &&
                          (v_counter <  V_SYNC + V_BP + V_ACTIVE);

  assign de = h_video_active && v_video_active;

  assign video_active   = (tx_state == TX_VIDEO);
  assign data_island    = (tx_state == TX_ISLAND);
  assign control_period = (tx_state == TX_CONTROL);

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

endmodule
```

---

## 2. Upravený testbench s generovaním vlnového priebehu (.vcd)

```systemverilog
`timescale 1ns / 1ps

module tb_hdmi_tx_fsm();

  // Parametre
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

  logic clk = 0;
  logic rstn = 0;

  logic [$clog2(H_TOTAL)-1:0] h_counter = 0;
  logic [$clog2(V_TOTAL)-1:0] v_counter = 0;

  logic de, video_active, data_island, control_period;

  // Hodiny
  always #5 clk = ~clk;  // 100 MHz

  // Reset
  initial begin
    rstn = 0;
    repeat (5) @(posedge clk);
    rstn = 1;
  end

  // VGA timing counters
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

  // Inštancia FSM
  hdmi_tx_fsm #(
    .H_SYNC(H_SYNC), .H_BP(H_BP), .H_ACTIVE(H_ACTIVE),
    .V_SYNC(V_SYNC), .V_BP(V_BP), .V_ACTIVE(V_ACTIVE)
  ) uut (
    .clk(clk),
    .rstn(rstn),
    .h_counter(h_counter),
    .v_counter(v_counter),
    .de(de),
    .video_active(video_active),
    .data_island(data_island),
    .control_period(control_period)
  );

  // Výpis stavov pre kontrolu
  always_ff @(posedge clk) begin
    if (rstn) begin
      $display("[%0t] h=%0d v=%0d | de=%b | state=%s %s %s",
        $time, h_counter, v_counter, de,
        (video_active ? "VIDEO" : ""),
        (data_island ? "ISLAND" : ""),
        (control_period ? "CONTROL" : ""));
    end
  end

  // Generovanie vcd súboru pre GTKWave
  initial begin
    $dumpfile("tb_hdmi_tx_fsm.vcd");
    $dumpvars(0, tb_hdmi_tx_fsm);
  end

  // Ukončenie simulácie po cca 3 rámcoch
  initial begin
    #300000;
    $finish;
  end

endmodule
```

---

### 🟢 Čo spraviť ďalej?

1. Skopíruj tieto dva súbory (`hdmi_tx_fsm.sv` a `tb_hdmi_tx_fsm.sv`) do tvojho projektu
2. Skopaj a spusti simuláciu (napr. v Icarus Verilogu, ModelSim, Questa)
3. Otvor `tb_hdmi_tx_fsm.vcd` v GTKWave a skontroluj signály `de`, `video_active`, `data_island`, `control_period`

Ak chceš, môžem ti pomôcť aj so skriptom na spustenie simulácie.

---

Napíš, či chceš, aby som pomohol s tým, alebo s ďalšími krokmi (napr. integrácia do TMDS kódovania, pridanie testov atď.)
