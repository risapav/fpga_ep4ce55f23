Výborne! Pokračujme teda:

---

## 🎯 Cieľ

Spojiť **SPD InfoFrame generátor** s **TMDS Data Island enkodérom**, aby sme mohli:

1. Vygenerovať platný SPD InfoFrame (už máme),
2. Zakódovať každý bajt do TMDS formátu (používajú sa pri data island packetoch),
3. Výsledok pripraviť na sériový výstup do HDMI streamu.

---

## 🧱 Pomocný modul: TMDS enkóder (na 8b → 10b)

V HDMI sa pre každý bajt používa špeciálny **TMDS 8b/10b enkóder**. Tu je základný, syntetizovateľný a komentovaný variant:

```systemverilog
module tmds_encoder (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [7:0]  data_in,
    input  logic        de,       // data enable: 1 = valid data
    output logic [9:0]  tmds_out
);

    logic [3:0] num_ones;
    logic       invert;
    logic [8:0] q_m; // intermediate 9-bit word

    // Count number of ones in input
    always_comb begin
        num_ones = 0;
        for (int i = 0; i < 8; i++)
            if (data_in[i])
                num_ones++;
    end

    // Encode into intermediate format q_m
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            q_m <= 9'd0;
        end else if (de) begin
            // Transition minimization logic
            if (num_ones > 4 || (num_ones == 4 && !data_in[0]))
                invert = 1;
            else
                invert = 0;

            for (int i = 0; i < 8; i++)
                q_m[i] <= (invert ? ~data_in[i] : data_in[i]);

            q_m[8] <= invert;
        end
    end

    // Add two control bits at the front (here simplified)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tmds_out <= 10'd0;
        end else if (de) begin
            tmds_out <= {2'b01, q_m}; // Control bits 01 = data island
        end
    end

endmodule
```

📝 *Toto je zjednodušený 8b/10b kóder vhodný pre infoframes a data islands.*

---

## 🔗 Prepojenie: SPD InfoFrame + TMDS encoder

```systemverilog
module hdmi_spd_island_encoder (
    input  logic        clk,
    input  logic        reset_n,
    output logic [9:0]  tmds_out,
    output logic        valid
);

    logic [8*27-1:0] spd_raw;
    logic            spd_valid;

    spd_infoframe_generator spd_gen (
        .clk(clk),
        .reset_n(reset_n),
        .spd_frame(spd_raw),
        .valid(spd_valid)
    );

    // Rozbaľ SPD frame na bajty
    logic [7:0] spd_bytes [0:26];
    for (genvar i = 0; i < 27; i++) begin
        assign spd_bytes[i] = spd_raw[i*8 +: 8];
    end

    logic [4:0] byte_idx;
    logic       de;

    tmds_encoder encoder (
        .clk(clk),
        .reset_n(reset_n),
        .data_in(spd_bytes[byte_idx]),
        .de(de),
        .tmds_out(tmds_out)
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            byte_idx <= 0;
            de <= 0;
            valid <= 0;
        end else begin
            if (spd_valid) begin
                de <= 1;
                valid <= 1;
                if (byte_idx < 27)
                    byte_idx <= byte_idx + 1;
                else begin
                    byte_idx <= 0;
                    valid <= 0;
                    de <= 0;
                end
            end
        end
    end

endmodule
```

---

## ✅ Zhrnutie

➡️ Teraz máme:

* SPD InfoFrame generátor (vytvára 27 bajtov s CRC8)
* TMDS enkóder (zakóduje každý bajt do 10-bitového HDMI TMDS formátu)
* Top modul `hdmi_spd_island_encoder` spojí tieto dva

---

## 🔜 Ďalšie kroky

Chceš pokračovať:

1. **Testbenchom pre overenie výstupu?**
2. **Pridaním ďalších InfoFrames (AVI, Audio)?**
3. **TMDS Video packet enkodér (CRC32 + guard bands)?**
4. **Vytvorením Data Island Packet Sendera (s riadením slotov)?**

Alebo máš špecifické FPGA použitie (napr. Intel/Altera HDMI TX IP core)?
