Jasné, poďme si to rozobrať.

---

## Prečo sa používajú CRC8 a CRC32 v HDMI infoframe a protokoloch?

### CRC8

* **CRC8 (8-bitový Cyclic Redundancy Check)** sa používa predovšetkým v **HDMI infoframe** ako jednoduchý kontrolný súčet pre **každý infoframe** (napr. SPD, AVI infoframe).
* Účel:

  * Overiť integritu **jednotlivých infoframe paketov** (ktoré sú relatívne malé, okolo 25 bajtov).
  * Pomáha príjemcovi zistiť, či infoframe nebol poškodený počas prenosu.
  * Výhodou CRC8 je malá dĺžka (len 1 bajt), čo šetrí šírku pásma.
* Príklad: SPD infoframe má v špecifikácii priamo definovaný 8-bitový CRC na overenie svojich dát.

---

### CRC32

* **CRC32 (32-bitový CRC)** sa využíva vo väčších a komplexnejších dátových paketoch v HDMI alebo DisplayPortu, alebo vo všeobecnosti tam, kde je dôležitá vyššia spoľahlivosť.
* Napríklad:

  * Pri kontrole integrity veľkých dátových blokov (audio streamy, väčšie infoframy).
  * Pri DisplayPortu alebo HDMI 2.0+ môže byť použitý komplexnejší CRC32 pre overenie dátového toku.
* Výhoda je vyššia detekčná schopnosť chýb, ale za cenu väčšej redundancie (4 bajty CRC).

---

## Prečo teda v HDMI infoframe spravidla **CRC8**?

* Infoframe sú malé dátové bloky (max \~25 bajtov).
* CRC8 je postačujúci na odhalenie väčšiny chýb v takomto krátkom bloku.
* Nižšia redundancia znamená menší overhead v dátovom toku.
* Je to štandard definovaný v HDMI špecifikácii.

---

## Presnejší TMDS kódovač — základný príklad v SystemVerilog

TMDS kódovanie prevádza 8-bitové dáta na 10-bitové symboly s minimalizáciou prechodov a vyrovnávaním počtu logických 1 a 0 (DC balancing).

Tu je jednoduchý implementačný príklad (iba základ, bez všetkých optimalizácií):

```systemverilog
module tmds_encoder (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [7:0]  data_in,
    input  logic        video_data_enable,  // 1 = video, 0 = control/infoframe
    output logic [9:0]  tmds_out
);

    // Počítame počet jednotiek v data_in
    function automatic int count_ones(input logic [7:0] d);
        int c;
        int i;
        begin
            c = 0;
            for (i=0; i<8; i++) c += d[i];
            return c;
        end
    endfunction

    logic [8:0] q_m;  // Intermediate 9-bit kódovanie
    logic       disparity;  // Kumulatívny disparity (DC vyváženie)

    // Prvý krok: premena 8 bitov na 9 bitový kód s minimalizáciou prechodov
    always_comb begin
        int ones = count_ones(data_in);
        if ( (ones > 4) || (ones == 4 && data_in[0] == 0)) begin
            // Použiť XOR kódovanie
            q_m[0] = data_in[0];
            for (int i=1; i<8; i++) 
                q_m[i] = q_m[i-1] ^ data_in[i];
            q_m[8] = 0; // bit na indikáciu XOR kódovania
        end else begin
            // Použiť XNOR kódovanie
            q_m[0] = data_in[0];
            for (int i=1; i<8; i++) 
                q_m[i] = ~(q_m[i-1] ^ data_in[i]);
            q_m[8] = 1; // bit na indikáciu XNOR kódovania
        end
    end

    // Druhý krok: vyváženie (disparity) - tu zjednodušene, bez úplnej implementácie
    // V skutočnom kódovači treba sledovať kumulatívnu rovnováhu počtu jednotiek a nútiť výstup k vyrovnaniu

    // Pre zjednodušenie nastavíme tmds_out rovno q_m + ďalšie dva bity na 0
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            tmds_out <= 10'b0;
        else
            tmds_out <= {2'b00, q_m}; // 2 bity control - zatiaľ nula
    end

endmodule
```

---

### Vysvetlenie TMDS kódovania

* 8-bitový vstup sa kóduje do 9-bitového reťazca pomocou XOR alebo XNOR podľa počtu jednotiek.
* 9. bit (`q_m[8]`) indikuje použitý spôsob kódovania.
* Na výstupe sa pridávajú ešte 2 bity na riadenie DC vyváženia (v plnom TMDS implementovaní).
* Kódovanie minimalizuje počet prechodov a udržiava rovnováhu logických 1 a 0 (DC balance).

---

Ak chceš, môžem napísať kompletný TMDS kódovač aj s plným DC vyvažovaním a riadením control bitov, prípadne ukázať ako sa integruje CRC8 do SPD infoframe.

---

Máš záujem o:

* Plnohodnotný TMDS kódovač?
* Implementáciu CRC8 generátora?
* Kompletnú integráciu CRC do SPD infoframe?
* Alebo iné?
