Paráda, začneme teda s **Krokom 1 – pridanie waveform dumpu do testbenchu**.

Tu je upravený testbench s vloženým VCD dumpom, ktorý môžeš hneď simulovať a následne si pozrieť waveform vo **GTKWave** alebo inom simulátore:

```systemverilog
module ResetController_tb;
    parameter int N_DOMAINS = 3;
    logic [N_DOMAINS-1:0] clk;
    logic [N_DOMAINS-1:0] resetn_sync;

    logic RESET_N;
    logic pll_locked;

    // Generate different clocks
    initial begin
        clk[0] = 0;
        forever #5 clk[0] = ~clk[0]; // 100 MHz
    end

    initial begin
        clk[1] = 0;
        forever #7 clk[1] = ~clk[1]; // ~71 MHz
    end

    initial begin
        clk[2] = 0;
        forever #11 clk[2] = ~clk[2]; // ~45 MHz
    end

    // Dump waves for viewing in GTKWave or other tools
    initial begin
        $dumpfile("reset_controller_tb.vcd");
        $dumpvars(0, ResetController_tb);
    end

    // DUT
    ResetController #(
        .N_DOMAINS(N_DOMAINS),
        .N_STAGES(2)
    ) dut (
        .RESET_N      (RESET_N),
        .pll_locked   (pll_locked),
        .clk          (clk),
        .resetn_sync  (resetn_sync)
    );

    // Stimulus
    initial begin
        $display("=== Začínam test reset synchronizácie ===");

        RESET_N = 0;
        pll_locked = 0;
        #50;

        RESET_N = 1;
        pll_locked = 0;
        #50;

        RESET_N = 1;
        pll_locked = 1;
        #200;

        RESET_N = 0;
        #30;

        RESET_N = 1;
        #200;

        $display("=== Test hotový ===");
        $finish;
    end

    // Monitor
    always @(posedge clk[0]) begin
        $display("[clk0] resetn_sync = %b", resetn_sync[0]);
    end
endmodule
```

---

### Čo spraviť ďalej?

1. Spusti simuláciu (napr. v Icarus Verilog, ModelSim, Questa, Vivado simulator...)
2. Otvor súbor `reset_controller_tb.vcd` vo waveform prehliadači (GTKWave, ModelSim, Vivado)
3. Sleduj signály: `RESET_N`, `pll_locked`, `resetn_sync[0..2]`, `clk[0..2]`

---

Ak chceš, môžem ti pomôcť so simuláciou alebo vysvetliť, ako interpretovať výsledky v waveform.

Chceš pokračovať priamo na **Krok 2 – časovanie oneskorenia resetu**? Alebo by si chcel najskôr prebrať simuláciu a waveform?
