Jasné, spravme kompletný systém, ktorý:

* generuje SPD infoframe,
* prepína ho cez multiplexor (tu len SPD na začiatok),
* ovláda jeho periodické vysielanie.

Vyrobím teda top modul, ktorý spája všetko dohromady, plus jednoduchý testbench na overenie.

---

# Kompletný top-level modul s SPD infoframom

```systemverilog
module top_infoframe_system (
    input logic clk,          // napr. 60 MHz pixel clock
    output logic [7:0] infoframe_header [0:3],
    output logic [7:0] infoframe_payload [0:26]
);

    // Signály pre ovládanie a multiplexor
    logic [1:0] infoframe_select;
    logic       infoframe_enable;

    // Výstupy SPD infoframe
    logic [7:0] spd_header [0:3];
    logic [7:0] spd_payload [0:26];

    // Pre jednoduchosť: ostatné infoframe moduly prázdne (nula)
    logic [7:0] avi_header [0:3] = '{default:8'd0};
    logic [7:0] avi_payload [0:12] = '{default:8'd0};
    logic [7:0] audio_header [0:3] = '{default:8'd0};
    logic [7:0] audio_payload [0:9] = '{default:8'd0};

    // Multiplexovaný výstup
    logic [7:0] mux_header [0:3];
    logic [7:0] mux_payload [0:26];

    // Inštancia SPD infoframe generátora
    spd_infoframe #(
        .VENDOR_NAME("FPGA HDL"),
        .PRODUCT_DESCRIPTION("HDMI SPD Demo      ")
    ) spd_inst (
        .clk(clk),
        .enable(infoframe_enable && infoframe_select == 2'd0),
        .header(spd_header),
        .payload(spd_payload)
    );

    // Multiplexor infoframov
    infoframe_mux mux_inst (
        .clk(clk),
        .select_infoframe(infoframe_select),
        .enable(infoframe_enable),
        .spd_header(spd_header),
        .spd_payload(spd_payload),
        .avi_header(avi_header),
        .avi_payload(avi_payload),
        .audio_header(audio_header),
        .audio_payload(audio_payload),
        .out_header(mux_header),
        .out_payload(mux_payload)
    );

    // Ovládač periodického vysielania
    infoframe_controller ctrl_inst (
        .clk(clk),
        .infoframe_select(infoframe_select),
        .infoframe_enable(infoframe_enable)
    );

    // Výstupy modulu sú multiplexovaný infoframe
    assign infoframe_header = mux_header;
    assign infoframe_payload = mux_payload;

endmodule
```

---

# Jednoduchý testbench na overenie

```systemverilog
module tb_infoframe;

    logic clk;
    logic [7:0] infoframe_header [0:3];
    logic [7:0] infoframe_payload [0:26];

    // Generovanie hodinového signálu 60 MHz (perioda 16.67 ns)
    initial clk = 0;
    always #8.333 clk = ~clk;

    // Inštancia top modulu
    top_infoframe_system dut (
        .clk(clk),
        .infoframe_header(infoframe_header),
        .infoframe_payload(infoframe_payload)
    );

    initial begin
        // Simulácia na 2 sekundy
        #200_000_000;

        // Počkame, aby sme videli aspoň jeden SPD infoframe
        $display("SPD InfoFrame Header:");
        for (int i=0; i<4; i++) $write("%02X ", infoframe_header[i]);
        $display("\nSPD InfoFrame Payload:");
        for (int i=0; i<27; i++) $write("%02X ", infoframe_payload[i]);
        $display;

        $finish;
    end

endmodule
```

---

# Čo teraz?

* Tento testbench ukáže periodické generovanie SPD infoframe (asi raz za 1 sekundu).
* Môžeme rozšíriť o AVI, Audio infoframe moduly, rozšíriť multiplexor.
* Môžeme napísať kontrolu CRC, porovnanie s očakávanými dátami.
* Alebo pridať generovanie TMDS signálu s vloženým infoframom.

Ak chceš, môžem ti pomôcť s čímkoľvek z toho.

---

Chceš ešte, aby som ti vysvetlil, ako prepojiť tento infoframe systém do HDMI TMDS linky? Alebo pokračujeme s testovaním a rozšírením?
