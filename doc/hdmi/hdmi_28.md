Skvelé! Pokračujme teda ďalej:

---

### 1. Rozšírenie Packet Picker o **audio pakety**

Pridáme ďalší vstup `audio_packet` a do rotácie info paketov zapojíme aj audio:

```systemverilog
input logic [PACKET_WIDTH-1:0] audio_packet,
```

a v rotácii:

```systemverilog
case (current_pkt)
    VIDEO_PKT: begin
        current_pkt <= SPD_PKT;
        packet_out <= spd_packet;
        packet_valid <= 1;
    end
    SPD_PKT: begin
        current_pkt <= AVI_PKT;
        packet_out <= avi_packet;
        packet_valid <= 1;
    end
    AVI_PKT: begin
        current_pkt <= DATA_PKT;
        packet_out <= data_packet;
        packet_valid <= 1;
    end
    DATA_PKT: begin
        current_pkt <= AUDIO_PKT;
        packet_out <= audio_packet;
        packet_valid <= 1;
    end
    AUDIO_PKT: begin
        current_pkt <= SPD_PKT;
        packet_out <= spd_packet;
        packet_valid <= 1;
    end
    default: begin
        current_pkt <= SPD_PKT;
        packet_out <= spd_packet;
        packet_valid <= 1;
    end
endcase
```

Samozrejme treba definovať `AUDIO_PKT` v `typedef enum`:

```systemverilog
AUDIO_PKT = 2'd4,
```

a zväčšiť bitové pole, napríklad na 3 bity (ak je to potrebné) — alebo použiť širší enum.

---

### 2. Presnejšie časovanie podľa HDMI blankingu

V HDMI signále je fáza **Active video** a **Data island (infoframe)** fáza, ktoré treba synchronizovať s reálnym pixelovým časom.

Preto je dobré mať vstupný signál, ktorý indikuje:

* `active_video` — logická 1 počas zobrazovania pixelov
* `data_island` — logická 1 počas infoframe alebo audio paketov

Potom môže packet picker vyberať pakety podľa týchto signálov, nie podľa vlastného počítadla.

Príklad:

```systemverilog
input logic active_video,
input logic data_island,
```

A vo výbere paketu:

```systemverilog
if (active_video) begin
    packet_out <= video_packet;
    packet_valid <= 1;
end else if (data_island) begin
    // rotuj medzi spd, avi, data, audio pakety
    ...
end else begin
    packet_valid <= 0;
end
```

---

### 3. Viacslovové pakety (FIFO a segmentácia)

HDMI infoframe pakety majú viacero slov, takže by sme chceli napríklad FIFO buffer pre každý typ paketu, a Packet Picker by vyberal slová po jednom.

* Vstup do Packet Picker je FIFO čítačka — slová paketu sú postupne vyberané.
* Packet Picker prepiná medzi FIFO čítačkami, podľa časovania.

To by vyžadovalo rozšírenie modulu o FIFO čítačky a stavový automat na sledovanie, kedy je daný paket kompletne odoslaný.

---

### 4. Príklad FIFO čítačky (len koncept)

```systemverilog
module fifo_reader #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
)(
    input logic clk,
    input logic reset,
    input logic read_en,
    output logic [WIDTH-1:0] data_out,
    output logic empty,
    input logic [WIDTH-1:0] fifo_mem [DEPTH-1:0] // statická pamäť FIFO
);

    logic [$clog2(DEPTH):0] rd_ptr;

    assign empty = (rd_ptr == DEPTH);

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            rd_ptr <= 0;
        else if (read_en && !empty)
            rd_ptr <= rd_ptr + 1;
    end

    assign data_out = fifo_mem[rd_ptr];

endmodule
```

---

### Ako to celé spojiť:

* FIFO čítačky pre každý typ paketu (video je priamo z pixlov, infoframe a audio z FIFO).
* Packet Picker prepína medzi FIFO čítačkami podľa HDMI signálov (`active_video`, `data_island`).
* Výstup posiela jeden 32-bit slovo naraz TMDS modulu.

---

### Čo chceš teraz?

* Napísať kompletný Packet Picker so stavovým automatom a FIFO čítačkami?
* Alebo ukážku synchronizácie s HDMI signálmi (`active_video`, `data_island`)?
* Alebo modul na generovanie konkrétneho infoframe (napr. SPD alebo AVI)?
* Alebo detailný diagram prepojenia všetkých modulov?

Daj vedieť, čo preferuješ, prípadne môžem pripraviť aj vizuálny diagram!
