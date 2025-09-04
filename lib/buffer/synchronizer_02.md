Tvoj modul `AsyncFIFO` je veľmi dobre navrhnutý – ide o **robustné asynchrónne FIFO**, ktoré prenáša dáta medzi dvoma nezávislými hodinovými doménami (`wr_clk` a `rd_clk`) pomocou **gray kódovaných pointerov** a **synchronizátorov**. Z hľadiska použitia **resetov** je modul korektne ošetrený – a nasleduje best-practices pre **CDC dizajn**.

Tu je analýza zameraná konkrétne na **resety** (synchronný vs. asynchrónny), a ich **vhodnosť v rôznych častiach** kódu.

---

## 🧠 Základné pojmy

### Čo je problém v CDC FIFO:

* `wr_clk` a `rd_clk` bežia nezávisle – nesmú sa spojiť priamo.
* Reset sa tiež môže uplatniť v rôznom čase v rôznych doménach.
* Aby bol návrh **robustný a analyzovateľný** (napr. pomocou Intel Quartus TimeQuest), musíš resety a pointery **synchronizovať** rovnako starostlivo ako dáta.

---

## 🔧 Resety v tvojom dizajne

### 🟩 VSTUP: `wr_rstn`, `rd_rstn` = externé asynchrónne resety pre FIFO

→ Môžu byť privedené zo systému (napr. z globálneho resetu alebo od PLL locked).

### 🛠️ **ResetSynchronizer moduly**

```systemverilog
ResetSynchronizer wr_reset_sync_inst (.clk(wr_clk), .rst_n_in(wr_rstn), .rst_n_out(wr_rstn_sync));
ResetSynchronizer rd_reset_sync_inst (.clk(rd_clk), .rst_n_in(rd_rstn), .rst_n_out(rd_rstn_sync));
```

Tieto moduly konvertujú **asynchrónny reset** na **synchronizovaný** do každej domény – presne ako má byť.

✅ **Správne a odporúčané riešenie**.

---

## 🧩 Ako sa používajú synchronizované resety

### V zápisovej doméne:

```systemverilog
always_ff @(posedge wr_clk) begin
    if (!wr_rstn_sync) begin
        wr_ptr_bin  <= 'd0;
        wr_ptr_gray <= 'd0;
```

### V čítacej doméne:

```systemverilog
always_ff @(posedge rd_clk) begin
    if (!rd_rstn_sync) begin
        rd_ptr_bin  <= 'd0;
        rd_ptr_gray <= 'd0;
```

### ➕ Výhody použitia **synchronizovaného resetu** tu:

| Výhoda                                                  | Vysvetlenie                                                                                      |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| 🕒 Reset je zarovnaný s hodinovým signálom              | čo je nevyhnutné na to, aby sa zabránilo **metastabilite** počas resetovania.                    |
| 🔄 Reset funguje spoľahlivo aj pri nízkych frekvenciách | pretože výstup `wr_rstn_sync`/`rd_rstn_sync` je stabilný iba po dvoch cykloch `wr_clk`/`rd_clk`. |
| ✅ Umožňuje nástroju analyzovať časovanie správne        | asynchrónne resety by inak mohli spôsobovať **neuzavreté časové cesty (timing violations)**.     |

---

## 🤔 Použitie resetov v synchronizátoroch

```systemverilog
TwoFlopSynchronizer #(.WIDTH(ADDR_WIDTH + 1))
    rd_ptr_sync_inst (.clk(wr_clk), .rst_n(wr_rstn_sync), .d(rd_ptr_gray), .q(rd_ptr_gray_wrclk_sync));
```

Tu sa používa výstup `wr_rstn_sync` ako `rst_n`, čo je výborné – pretože:

* reset v synchronizátore musí byť **zarovnaný s cieľovou doménou (clk)**,
* pri použití `async_reg` je nevyhnutné, aby flip-flopy neboli resetované *asynchrónne mimo svojej domény*, inak hrozí **metastabilita resetu**.

✅ Správne použitie synchronizovaného resetu aj v `TwoFlopSynchronizer`.

---

## ❓ Čo by sa stalo, keby sa resety **nepoužili alebo boli asynchrónne**?

| Scenár                                                  | Následok                                                                  |
| ------------------------------------------------------- | ------------------------------------------------------------------------- |
| Asynchrónny reset priamo do logiky (bez synchronizácie) | ❌ Hrozí **metastabilita** vo flip-flopoch → **nepredvídateľné správanie** |
| Žiadny reset                                            | ⚠️ FIFO môže začať v náhodnom stave, môže sa javiť ako plné alebo prázdne |
| Reset nepochádza z domény, do ktorej sa aplikuje        | ❌ Hrozí CDC glitch aj počas resetu samotného                              |

---

## ✅ Záver: Hodnotenie resetu v tomto Async FIFO

| Oblasť                                  | Hodnotenie | Odôvodnenie                                                          |
| --------------------------------------- | ---------- | -------------------------------------------------------------------- |
| **Synchronizácia resetov**              | ✅ Výborná  | Použitie `ResetSynchronizer` pre každú doménu je správne riešenie    |
| **Reset synchronizátorov**              | ✅ Správne  | Synchronizované do správnej clock domény                             |
| **FIFO logika (pointre, RAM)**          | ✅ OK       | Synchronizovaný reset zaručuje deterministický štart                 |
| **CDC štruktúry (TwoFlopSynchronizer)** | ✅ Robustné | Použitie `async_reg` + synchronizovaný reset = odporúčaný Intel štýl |

---

Ak chceš, môžem ti ukázať aj návrh modulu `ResetSynchronizer`, alebo pripraviť testbench pre túto FIFO, ktorý overí resety, zápis a čítanie medzi rôznymi hodinovými doménami.

Chceš pokračovať v tomto smere?
