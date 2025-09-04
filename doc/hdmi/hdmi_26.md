Jasné, tu je detailná bloková schéma a popis **Packet Picker** modulu, ktorý riadi výstup rôznych typov paketov (video, audio, SPD, data island) do TMDS encoderu HDMI linky.

---

## Bloková schéma Packet Picker modulu

```
                        ┌─────────────────────────────┐
                        │       Packet Picker          │
                        │                             │
                        │ ┌─────────────┐             │
         Video Data ────▶│ Video Packet │             │
           (RGB)         │ Generator   │             │
                        └──────┬──────┘             │
                               │                   │
                        ┌──────▼──────┐            │
         Audio Data ───▶│ Audio Packet│            │
                        │ Generator   │            │
                        └──────┬──────┘            │
                               │                   │
                        ┌──────▼──────┐            │
         SPD Info ─────▶│ SPD Packet  │            │
                        │ Generator   │            │
                        └──────┬──────┘            │
                               │                   │
                        ┌──────▼──────┐            │
         AVI Info ─────▶│ AVI Packet  │            │
                        │ Generator   │            │
                        └──────┬──────┘            │
                               │                   │
                        ┌──────▼──────┐            │
       Data Island ─────▶│ Data Packet │            │
                        │ Generator   │            │
                        └──────┬──────┘            │
                               │                   │
                               ▼                   │
                        ┌─────────────────────────┐│
                        │     Packet Multiplexer   ││
                        │  (Selects aktuálny paket)││
                        └──────────┬──────────────┘│
                                   │                │
                                   ▼                │
                        ┌─────────────────────────┐ │
                        │      TMDS Encoder       │ │
                        └─────────────────────────┘ │
                                   │                │
                                   ▼                │
                        ┌─────────────────────────┐ │
                        │ TMDS Serializer & Output│ │
                        └─────────────────────────┘ │
                                   │                │
                                   ▼                │
                            HDMI TMDS link signals
```

---

## Detailné vysvetlenie Packet Picker

### Vstupy:

* **Video Data**: RGB pixelové dáta zo spracovania obrazu.
* **Audio Data**: Digitálne audio vzorky (napr. I2S alebo PCM formát).
* **SPD Info**: SPD (Source Product Description) infoframe dáta.
* **AVI Info**: AVI infoframe (video popis) dáta.
* **Data Island**: Ostatné dátové pakety, ako napr. audio clock regeneration.

### Funkcia Packet Picker:

* **Generátory paketov** vytvárajú jednotlivé HDMI pakety:

  * **Video Packet**: obsahuje aktívne video pixely a riadiace signály (HSYNC, VSYNC, DE).
  * **Audio Packet**: kóduje audio vzorky do HDMI audio paketu.
  * **SPD Packet**: obsahuje informácie o produkte (výrobca, verzia).
  * **AVI Packet**: poskytuje metaúdaje o video signále (rozlíšenie, pomer strán).
  * **Data Packet**: spracúva špeciálne dátové pakety podľa HDMI štandardu.

* **Packet Multiplexer** riadi časovanie a prepína medzi jednotlivými paketmi podľa HDMI špecifikácie.

  * HDMI definuje presné časové intervaly, kedy sa posielajú video pakety, a kedy info/data pakety.
  * Multiplexer prepína zdroje, aby sa vytvoril kontinuálny dátový tok pre TMDS encoder.

---

## Časové rozdelenie HDMI paketov

* **Aktívne video**: väčšinu času sa posiela video pixelová dátová časť.
* **Blanking intervaly (medzi obrazovými rámcami)**: vysielajú sa infoframe a audio pakety.
* **Data Island Periods**: pre audio clock a ďalšie dátové pakety.

---

Ak chceš, môžem pripraviť aj príkladový SystemVerilog kód pre Packet Picker s prepínaním medzi video a info/data paketmi podľa časovača (timer), prípadne základný state machine.

---

Chceš pokračovať v kódovaní, alebo ešte doplniť nejaký iný detail?
