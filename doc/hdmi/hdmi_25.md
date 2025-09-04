Jasné, tu je jednoduchá bloková schéma a popis, ako by mohol vyzerať systém HDMI výstupu s AXIS rozhraním a všetkými kľúčovými modulmi, ktoré sme riešili:

---

## Bloková schéma HDMI modulu s AXIS vstupom a internými modulmi

```
 ┌────────────────────┐
 │   AXIS Slave       │
 │ (AXIS prijímač)    │
 │  tdata[23:0], tvalid, tready │
 └─────────┬──────────┘
           │ (pixel data + valid)
           │
           ▼
 ┌────────────────────┐
 │    FIFO buffer      │  <──────────── Buffer medzi AXIS a video časovaním
 │   (synchronný)      │
 │ wr_en = tvalid      │
 │ wr_data = tdata     │
 │ rd_en = pixel_req   │
 │ full, empty signals │
 └─────────┬──────────┘
           │
           ▼
 ┌───────────────────────────────┐
 │      Video Timing Generator   │
 │   (Generuje cx, cy, hsync,    │
 │    vsync, data_enable signály)│
 └─────────┬─────────────────────┘
           │
           ▼
 ┌───────────────────────────────┐
 │ Pixel Data Controller          │
 │ (Číta FIFO ak je data_enable) │
 │ Výstup: rgb [23:0]             │
 └─────────┬─────────────────────┘
           │
           ▼
 ┌───────────────────────────────┐
 │ HDMI Packet Picker             │
 │ (Generuje infoframes SPD, AVI,│
 │  audio pakety, audio clock)   │
 └─────────┬─────────────────────┘
           │
           ▼
 ┌───────────────────────────────┐
 │ TMDS Encoder                  │
 │ (kóduje video, kontrolné,     │
 │  data island signály do TMDS) │
 └─────────┬─────────────────────┘
           │
           ▼
 ┌───────────────────────────────┐
 │ TMDS Serializer + Output      │
 │ (Serializuje TMDS dáta do    │
 │  signálov tmds_p, tmds_n,    │
 │  tmds_clock_p, tmds_clock_n) │
 └───────────────────────────────┘
```

---

## Vysvetlenie dátového toku a modulov

1. **AXIS Slave (input):**
   Prijíma pixelové dáta cez štandardné AXIS signály (tdata, tvalid, tready).

   * `tdata` obsahuje RGB pixel, napr. 24 bitov (8b pre každý kanál).
   * FIFO medzi AXIS a video časovaním vyrovnáva rýchlosti.

2. **FIFO buffer:**
   Ukladá pixely prijaté z AXIS a vydáva ich na požiadanie video časovania.

3. **Video Timing Generator:**
   Generuje horizontálne a vertikálne sync signály, aktuálne súradnice pixela (`cx`, `cy`), a `data_enable` signal, ktorý indikuje aktívnu oblasť obrazu.

4. **Pixel Data Controller:**
   Na základe `data_enable` číta FIFO a pripravuje aktuálny RGB pixel pre HDMI moduly.

5. **HDMI Packet Picker (InfoFrames + Audio):**
   Produkuje pomocné dátové pakety (SPD, AVI infoframe, audio infoframe, audio clock regeneration packet), ktoré sa v HDMI prenášajú v časových intervaloch mimo video dát.

6. **TMDS Encoder:**
   Kóduje video dáta a riadiace signály do 10-bitových TMDS kódov podľa HDMI špecifikácie.

7. **TMDS Serializer + Output:**
   Serializuje TMDS kódy do dátových a hodinových diferenciálnych signálov (`tmds_p/n` a `tmds_clock_p/n`) pripravených na pripojenie k HDMI konektoru.

---

## Ako AXIS prepojiť do HDMI modulu?

* AXIS master vysiela pixely postupne, ktoré FIFO uloží.
* FIFO poskytuje dáta podľa video časovania a `data_enable`.
* Tým sa zabezpečí správne načasovanie a plynulý výstup pixelov do HDMI.

---

Ak chceš, môžem ti pripraviť aj kód pre AXIS slave časť, ktorý bude napájať FIFO a bude súčasťou celého modulu HDMI. Alebo môžeš chcieť detailnejšie zapracovať audio a infoframe generáciu — daj vedieť!
