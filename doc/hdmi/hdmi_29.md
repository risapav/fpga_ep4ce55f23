Jasné! Tu máš jednoduchý príklad **Packet Picker** s **synchronizáciou na HDMI signály** `active_video` a `data_island`.

---

### Cieľ:

* Počas `active_video = 1` sa posielajú video pakety.
* Počas `data_island = 1` rotujeme medzi infoframe paketmi (SPD, AVI, Audio, Data).
* Inak sa nevysiela žiadny paket (`packet_valid = 0`).

---

```systemverilog
module packet_picker_sync #(
    parameter PACKET_WIDTH = 32
)(
    input logic clk,
    input logic reset,

    // HDMI synchronizačné signály
    input logic active_video,   // vysoký počas zobrazovania pixelov
    input logic data_island,    // vysoký počas infoframe fázy

    // Vstupy paketov
    input logic [PACKET_WIDTH-1:0] video_packet,
    input logic [PACKET_WIDTH-1:0] spd_packet,
    input logic [PACKET_WIDTH-1:0] avi_packet,
    input logic [PACKET_WIDTH-1:0] audio_packet,
    input logic [PACKET_WIDTH-1:0] data_packet,

    // Výstup paketu
    output logic [PACKET_WIDTH-1:0] packet_out,
    output logic packet_valid
);

    typedef enum logic [2:0] {
        PKT_SPD = 3'd0,
        PKT_AVI = 3'd1,
        PKT_AUDIO = 3'd2,
        PKT_DATA = 3'd3
    } pkt_type_t;

    pkt_type_t current_pkt;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_pkt <= PKT_SPD;
            packet_out <= '0;
            packet_valid <= 1'b0;
        end else begin
            if (active_video) begin
                // počas aktívneho videa posielame video pakety
                packet_out <= video_packet;
                packet_valid <= 1'b1;
            end else if (data_island) begin
                // počas fázy infoframe rotujeme medzi paketmi
                packet_valid <= 1'b1;
                case (current_pkt)
                    PKT_SPD: begin
                        packet_out <= spd_packet;
                        current_pkt <= PKT_AVI;
                    end
                    PKT_AVI: begin
                        packet_out <= avi_packet;
                        current_pkt <= PKT_AUDIO;
                    end
                    PKT_AUDIO: begin
                        packet_out <= audio_packet;
                        current_pkt <= PKT_DATA;
                    end
                    PKT_DATA: begin
                        packet_out <= data_packet;
                        current_pkt <= PKT_SPD;
                    end
                    default: begin
                        packet_out <= spd_packet;
                        current_pkt <= PKT_AVI;
                    end
                endcase
            end else begin
                // mimo aktívneho videa a data islandu nevysielame nič
                packet_valid <= 1'b0;
                packet_out <= '0;
            end
        end
    end

endmodule
```

---

### Vysvetlenie:

* Modul dostáva dva HDMI signály `active_video` a `data_island`.
* Ak je `active_video = 1`, posiela sa video paket.
* Ak je `data_island = 1`, postupne sa rotuje medzi infoframe paketmi (SPD, AVI, Audio, Data).
* Ak ani jeden signál nie je aktívny, `packet_valid` je 0 a nevysiela sa žiadny paket.
* `current_pkt` riadi, ktorý infoframe paket sa má poslať ďalší.

---

Ak chceš, môžem ukázať aj, ako sa tieto signály získavajú alebo ich generujú v HDMI kontroléri, alebo môžeme riešiť rozšírenie na FIFO čítačky a stavové automaty. Čo by si chcel teraz?
