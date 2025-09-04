Áno – veľmi dobrá otázka.

Ak máš **viacero dátových streamov** (napr. pre Video, Data Islands, Guard Bands) a každý z nich poskytuje svoje dáta na základe stavu `TX_FSM`, **synchronizácia je nutná**.

---

## 🔄 Prečo treba synchronizáciu?

Signál ako `video_active` alebo `data_island` sa **zmení v danom cykle**, ale to už je **neskoro na prípravu dát** v tom istom cykle, ak:

* Dátový stream má **latenciu 1 cyklus alebo viac** (napr. pipeliny, FIFO)
* Chceš v tom istom cykle multiplexovať správny obsah do výstupu

### ➤ Preto: musíš vedieť, **že zmena stavu nastane o 1 cyklus dopredu**.

---

## ✅ Ako to riešiť?

Existujú 2 hlavné prístupy:

### 1. **Lookahead signál** – teda “o jeden cyklus dopredu bude VIDEO/ISLAND”

* FSM generuje aj signály `next_video`, `next_island`, `next_control`
* Dátové moduly (napr. TMDS encoder) si tak pripravia svoje dáta vopred

```systemverilog
// V FSM
next_video   = (next_state == TX_VIDEO);
next_island  = (next_state == TX_ISLAND);
next_control = (next_state == TX_CONTROL);
```

### 2. **Pracovať s pipeline delay** – zapísať stavy do registra, oneskoriť `video_active` o 1 cyklus

```systemverilog
logic video_active_d;

always_ff @(posedge clk) begin
  video_active_d <= video_active;
end
```

Potom sa `video_active_d` používa pre rozhodovanie o výstupe.

---

## 🧠 Odporúčanie:

Ak buduješ **HDMI vysielač**, ktorý má:

* TMDS kódovače
* Rôzne zdroje dát (video, islands, nulls, guard bands)

... tak je **nevyhnutné**:

* mať stavový automat s možnosťou predpovedať `next_state`
* alebo použiť oneskorený FSM stav, aby sa príprava dát mohla synchronizovať

---

## ✳️ Záver

> Áno, je potrebné synchronizovať. A pokiaľ výstupné dáta závisia na stave, je potrebné:

* buď vedieť **vopred**, čo bude nasledovať
* alebo **súčasný stav** oneskoriť, aby sa dáta stihli pripraviť

---

Môžem ti pomôcť upraviť FSM tak, aby produkoval aj `next_state` signály alebo pripraviť ukážku, ako to prepojiť s TMDS kodérom. Chceš pokračovať tým smerom?
