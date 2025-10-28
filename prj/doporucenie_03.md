💯 Presne tak — to je **najčistejšie, najudržateľnejšie a časovo najbezpečnejšie riešenie.**
Tvoja úvaha je úplne profesionálna – a presne zodpovedá tomu, ako by sa to riešilo v reálnych FPGA projektoch s väčšou architektúrou.

---

## 🧩 Dôvody, prečo je vhodné zapúzdriť kontrolu do samostatného modulu

| Dôvod                            | Vysvetlenie                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------- |
| 🧱 **Modulárnosť a čitateľnosť** | `framebuffer_ctrl` ostane čistý – rieši len dátový tok a SDRAM logiku.                            |
| ⚙️ **Znovupoužiteľnosť**         | Kontrolu AXI streamov možno použiť aj pri iných moduloch (napr. kamera, scaler, DMA).             |
| 🕒 **Časovanie a syntéza**       | Quartus bude môcť umiestniť checker do samostatnej oblasti, mimo kritických ciest.                |
| 🔄 **Konfigurovateľnosť**        | Checker sa dá zapnúť/vypnúť parametrom bez úpravy hlavného modulu.                                |
| 🔍 **Simulácia a debug**         | Checker sa dá jednoducho monitorovať počas testbench simulácií bez zasahovania do hlavnej logiky. |

---

## 🧠 Návrh modulu: `axi4s_stream_checker.sv`

Tu je kompletný návrh samostatného modulu, ktorý môžeš zaradiť do projektu a inštanciovať ho vo `framebuffer_ctrl`.

---

### 📄 **axi4s_stream_checker.sv**

```systemverilog
// ============================================================================
// Modul: axi4s_stream_checker
// Účel: Overenie korektnosti AXI4-Stream video signálov (TUSER, TLAST)
// Verzia: 1.0
// Dátum: 28. október 2025
// Autor: [Tvoj projekt]
// ============================================================================

`ifndef AXI4S_STREAM_CHECKER_SV
`define AXI4S_STREAM_CHECKER_SV
`default_nettype none

module axi4s_stream_checker #(
    parameter int FRAME_WIDTH  = 800,
    parameter int FRAME_HEIGHT = 600,
    parameter bit C_ENABLE_CHECKS = 1  // umožňuje vypnutie pre produkčné buildy
)(
    input  logic clk,
    input  logic rstn,

    // AXI4-Stream vstup, ktorý chceme kontrolovať
    input  logic        s_tvalid,
    input  logic        s_tready,
    input  logic        s_tuser,
    input  logic        s_tlast,

    // Výstupné príznaky chýb
    output logic        error_any,
    output logic [7:0]  error_flags
);

    // Lokálne registre
    logic [$clog2(FRAME_WIDTH)-1:0]  x_cnt;
    logic [$clog2(FRAME_HEIGHT)-1:0] y_cnt;
    logic [7:0]                      errors;

generate if (C_ENABLE_CHECKS) begin : gen_axi_checker

    always_ff @(posedge clk) begin
        if (!rstn) begin
            x_cnt  <= '0;
            y_cnt  <= '0;
            errors <= '0;
        end
        else if (s_tvalid && s_tready) begin
            // TUSER – začiatok frame-u
            if (s_tuser) begin
                if (x_cnt != 0 || y_cnt != 0)
                    errors[0] <= 1'b1; // TUSER mimo pozície (x=0, y=0)
                x_cnt <= 0;
                y_cnt <= 0;
            end
            else begin
                // Inkrement pozície
                if (s_tlast) begin
                    // TLAST má byť presne na konci riadku
                    if (x_cnt != FRAME_WIDTH - 1)
                        errors[1] <= 1'b1; // TLAST v nesprávnej pozícii
                    x_cnt <= 0;
                    if (y_cnt == FRAME_HEIGHT - 1)
                        y_cnt <= 0;
                    else
                        y_cnt <= y_cnt + 1'b1;
                end
                else begin
                    x_cnt <= x_cnt + 1'b1;
                end
            end
        end
    end

end else begin : gen_axi_checker_disabled
    always_comb begin
        errors = '0;
        x_cnt  = '0;
        y_cnt  = '0;
    end
end endgenerate

assign error_any   = |errors;
assign error_flags = errors;

endmodule

`default_nettype wire
`endif
```

---

## 🧱 Inštancia v `framebuffer_ctrl.sv`

Stačí vložiť v časti **gen_framebuffer_active** (napr. pod SDRAM instanciou):

```systemverilog
// --------------------------------------------------
// AXI Stream vstupný checker (voliteľný)
// --------------------------------------------------
axi4s_stream_checker #(
    .FRAME_WIDTH(FRAME_WIDTH),
    .FRAME_HEIGHT(FRAME_HEIGHT),
    .C_ENABLE_CHECKS(1)
) s_axis_checker_inst (
    .clk(clk),
    .rstn(rstn),
    .s_tvalid(s_axis.TVALID),
    .s_tready(s_axis.TREADY),
    .s_tuser(s_axis.TUSER),
    .s_tlast(s_axis.TLAST),
    .error_any(debug_led_1_o[7]),
    .error_flags(debug_led_0_o[7:0])
);
```

Tým sa:

* checker aktivuje iba pri `C_ENABLE_CHECKS=1`,
* výsledky zobrazia na LEDkách (alebo môžeš pripojiť na soft-monitor),
* Quartus ho vie samostatne časovať a v prípade potreby optimalizovať.

---

## ⚙️ Výhody tohto riešenia

| Vlastnosť              | Výhoda                                                  |
| ---------------------- | ------------------------------------------------------- |
| 🧩 Zapúzdrenie         | Oddelený kód, ľahko sa testuje a znovu používa          |
| ⏱️ Časovanie           | Žiadna väzba na kritické signály, všetko registrované   |
| 🧠 Jednoduché vypnutie | Parameter `C_ENABLE_CHECKS`                             |
| 💡 Prehľadný dizajn    | `framebuffer_ctrl` ostáva čitateľný a čistý             |
| 🧾 Možnosť rozšírenia  | Dá sa pridať kontrola počtu pixelov, výšky frame-u atď. |

---

## 🔧 Odporúčanie pre FPGA build

* Počas **simulácie / vývoja** → `C_ENABLE_CHECKS = 1`
* Pre **final syntézu / nasadenie** → `C_ENABLE_CHECKS = 0`
  (Quartus vtedy checker úplne odstráni)

---

Ak chceš, môžem ti pripraviť aj:

* 📊 *verziu tohto modulu s AXI4-Stream Interface (`axi4s_if`)* – aby sa pripojil priamo ako `.slave s_axis`,
  namiesto explicitných signálov (to by bolo elegantnejšie a kompatibilné s tvojím rozhraním).

Chceš, aby som ti to upravil tak, že checker používa priamo `axi4s_if.slave` interface?
