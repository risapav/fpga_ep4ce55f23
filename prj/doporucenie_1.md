Skvelá otázka — teraz sa dostávame k **najdôležitejšej fáze praktickej integrácie**:
👉 analyzovať, **prečo `axis_cdc_fifo` síce syntetizuje, ale v reálnom nasadení neprenáša dáta**.

Tento problém sa často objaví pri CDC FIFO moduloch, ktoré teoreticky fungujú (simulácia OK), ale v reálnom FPGA alebo SoC **„zamrznú“** alebo **nikdy neprepustia validné dáta**.

---

## 🧩 1️⃣ Symptóm: FIFO „neprenáša dáta“

Typicky sa prejaví takto:

* `s_axis.TVALID = 1`, ale `s_axis.TREADY` je **stále 0** → zápis nikdy nezačne,
* alebo naopak, `m_axis.TVALID` je **vždy 0** → čítacia doména nikdy nevidí platné dáta,
* `level_o` = 0 (FIFO prázdne), hoci sa má napĺňať.

---

## ⚠️ 2️⃣ Potenciálne príčiny – rozbor podľa architektúry

Rozdelíme ich podľa vrstiev FIFO pipeline:

| Vrstva                                            | Riziko                                                | Prejav                                    |
| ------------------------------------------------- | ----------------------------------------------------- | ----------------------------------------- |
| Reset synchronizácia                              | Resety medzi doménami nie sú CDC bezpečné             | FIFO ostane v "resetovanom" stave         |
| Pointer synchronizácia                            | Metastabilita alebo chyba Gray konverzie              | FIFO nespozná, že niečo bolo zapísané     |
| AXI handshake mapping                             | Nesprávne mapovanie `TREADY`/`TVALID` voči full/empty | Žiadne dáta sa neprenesú                  |
| Typy dát (struct)                                 | Šírka / poradie / balenie payloadu                    | FIFO ukladá nesprávne dáta alebo nič      |
| Reset polarity                                    | Reset aktívny v opačnej polarite                      | FIFO sa nikdy „neuvolní“ z resetu         |
| Parametrizácia `ADDR_WIDTH` vs. `FIFO_DEPTH_BITS` | Nesúlad pri výpočte pointerov                         | FIFO okamžite považuje stav za full/empty |
| RAM implementácia (`RAM_STYLE`)                   | Nevhodná inferencia (napr. distributed RAM)           | FIFO pamäť sa nikdy nezapíše/načíta       |

---

## 🧩 3️⃣ Kritické miesta v **tvojom kóde** a ich návrhy opráv

### 🔸 (A) Reset synchronizácia

V tvojom `axis_cdc_fifo` sú resety **priamo prepojené**:

```systemverilog
.wr_rst_ni ( s_rst_ni ),
.rd_rst_ni ( m_rst_ni ),
```

➡️ Ak `s_rst_ni` a `m_rst_ni` nie sú zaručene stabilné a simultánne **v rámci svojich domén**, môže FIFO ostať "v zámrze".
Príznak: všetky pointery `'0`, `wr_full=1`, `rd_empty=1` navždy.

✅ **Odporúčané riešenie:**

* Vložiť CDC reset synchronizátor pre každú doménu:

```systemverilog
logic s_rst_sync_ni, m_rst_sync_ni;

cdc_reset_synchronizer #(
  .WIDTH(1), .STAGES(2)
) i_rst_sync_wr (
  .clk_i(s_clk_i),
  .rst_ni(s_rst_ni),
  .rst_no(s_rst_sync_ni)
);

cdc_reset_synchronizer #(
  .WIDTH(1), .STAGES(2)
) i_rst_sync_rd (
  .clk_i(m_clk_i),
  .rst_ni(m_rst_ni),
  .rst_no(m_rst_sync_ni)
);
```

A následne použiť:

```systemverilog
.wr_rst_ni ( s_rst_sync_ni ),
.rd_rst_ni ( m_rst_sync_ni ),
```

---

### 🔸 (B) Nesprávne inicializované pointery alebo chýbajúci „release“ po resete

V module `PointerSync` je reset **synchronný**:

```systemverilog
always_ff @(posedge clk) begin
  if (!rst_ni) begin
    bin_ptr_out <= '0;
    other_gray_sync1 <= '0;
    other_gray_sync_out <= '0;
  end else begin
    ...
  end
end
```

➡️ Ak je `rst_ni` prechádzajúce medzi doménami asynchrónne → pointery sa môžu rozísť.
Gray synchronizácia potom **neodštartuje správne** a FIFO vyhodnotí stav ako „plné aj prázdne zároveň“.

✅ **Vylepšenie:**

* Použiť asynchrónny reset (ak HW to dovoľuje):

```systemverilog
always_ff @(posedge clk or negedge rst_ni)
```

* Alebo sa uistiť, že reset je CDC-synchronizovaný (viď bod A).

---

### 🔸 (C) AXI handshake mapping (najčastejší problém!)

Aktuálne:

```systemverilog
wr_en = s_axis.TVALID && !wr_full;
s_axis.TREADY = !wr_full;

rd_en = m_axis.TREADY && !rd_empty;
m_axis.TVALID = !rd_empty;
```

➡️ Tu je **kritická chybička v načasovaní**:

* ak `m_axis.TREADY=0` (napr. downstream je zaneprázdnený), FIFO síce nastaví `m_axis.TVALID=1`,
  ale ak sa `rd_empty` mení o 1 takt neskôr (CDC oneskorenie pointerov), môže dôjsť k **neviditeľnej závade handshake**.

✅ **Odporúčané vylepšenie:**
Zaviesť **1-taktový register** na výstupe pre `m_axis` (tzv. „output staging register“):

```systemverilog
always_ff @(posedge m_clk_i or negedge m_rst_ni) begin
  if (!m_rst_ni) begin
    m_axis.TVALID <= 1'b0;
  end else begin
    if (!m_axis.TVALID || m_axis.TREADY) begin
      m_axis.TVALID <= !rd_empty;
      m_axis.TDATA  <= rd_payload.tdata;
      m_axis.TUSER  <= rd_payload.tuser;
      m_axis.TLAST  <= rd_payload.tlast;
    end
  end
end
```

➡️ Tento jednoduchý register zamedzí hazardom medzi `rd_empty` a `TVALID`.

---

### 🔸 (D) Payload štruktúra a bitové zoradenie

V `AsyncFifoGeneric` sa očakáva obyčajný vektor, ty používaš:

```systemverilog
wr_payload.tlast = s_axis.TLAST;
wr_payload.tuser = s_axis.TUSER;
wr_payload.tdata = s_axis.TDATA;
```

➡️ Závisí od toho, **ako je definovaný vstup `wr_data` v AsyncFifoGeneric**.
Ak tento modul čaká **bitový vektor (`logic [DATA_WIDTH+USER_WIDTH:0]`)**, ale ty posielaš štruktúru,
niektoré nástroje (napr. Vivado) **neprepoja štruktúru korektne** → FIFO má „neznáme“ vstupy.

✅ **Odporúčanie:**
Zmeň payload na explicitný vektor:

```systemverilog
assign wr_data = {s_axis.TLAST, s_axis.TUSER, s_axis.TDATA};
assign {rd_payload.tlast, rd_payload.tuser, rd_payload.tdata} = rd_data;
```

Tým máš 100% istotu správneho zoradenia bitov.

---

### 🔸 (E) `ADDR_WIDTH` vs. `FIFO_DEPTH_BITS`

Aktuálne:

```systemverilog
parameter int FIFO_DEPTH_BITS  = 8, // -> ADDR_WIDTH = 8
...
AsyncFifoGeneric #(
    .ADDR_WIDTH ( FIFO_DEPTH_BITS )
)
```

➡️ V `PointerSync` aj `GrayToBin` sa používa `ADDR_WIDTH+1` pre pointer.
Ak `AsyncFifoGeneric` niekde vnútri deklaruje pointer o 1 bit menej/more,
výsledkom môže byť, že „full“ stav sa aktivuje **hneď po resete**.

✅ **Overenie:**
Skontroluj, že vo `AsyncFifoGeneric` je definícia:

```systemverilog
logic [ADDR_WIDTH:0] wr_ptr, rd_ptr;
```

Nie:

```systemverilog
logic [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
```

---

### 🔸 (F) RAM inferencia (RAM_STYLE)

Ak používaš:

```systemverilog
parameter string RAM_STYLE = "auto"
```

➡️ V niektorých FPGA (napr. Intel/Altera) „auto“ defaultne znamená **register-based memory**,
čo pri veľkom FIFO (napr. 256× šírka 32b) spôsobí, že sa FIFO nespráva správne (zlá latencia alebo prístup).

✅ **Odporúčanie:**
Použiť explicitný atribút:

```systemverilog
(* ram_style = "block" *)  // pre Xilinx
(* ramstyle = "M10K" *)    // pre Intel
```

alebo parameter nastaviť priamo:

```systemverilog
parameter string RAM_STYLE = "block";
```

---

## 🧠 4️⃣ Diagnostický postup – ako chybu potvrdiť

1. V simulácii alebo na FPGA prepojíš tieto výstupy na analyzátor (ILA/SignalTap):

   * `local_wr_ptr_gray_o`
   * `sync_wr_ptr_gray_o`
   * `local_rd_ptr_gray_o`
   * `sync_rd_ptr_gray_o`
   * `wr_full`, `rd_empty`
   * `level_o`

2. Očakávané správanie po resetovaní:

   * všetky pointery = 0,
   * po prvom zápise: `local_wr_ptr_gray_o` sa zmení (napr. `000` → `001`),
   * do 2–3 taktov sa `sync_wr_ptr_gray_o` zmení tiež,
   * následne `rd_empty` klesne a `m_axis.TVALID` ide do `1`.

➡️ Ak sa pointery nikdy nerozídu, problém je v **resetoch alebo synchronizácii**.
Ak `wr_full` je stále `1`, problém v **ADDR_WIDTH** alebo Gray konverzii.

---

## ✅ 5️⃣ Sumár odporúčaných úprav

| Oblasť           | Zlepšenie                                       | Cieľ                            |
| :--------------- | :---------------------------------------------- | :------------------------------ |
| Resety           | Synchronizovať pomocou `cdc_reset_synchronizer` | FIFO sa správne inicializuje    |
| Handshake výstup | Registrovať `m_axis.TVALID/TREADY`              | Eliminácia CDC hazardov         |
| Payload          | Použiť bitový vektor namiesto štruktúry         | Zamedzenie inferenčných chýb    |
| Pointer width    | Overiť `ADDR_WIDTH+1` konzistentne              | Korektná detekcia full/empty    |
| RAM style        | Explicitne nastaviť `block` alebo `M10K`        | Stabilná pamäťová implementácia |
| Debug výstupy    | Použiť celé pointery pre analýzu                | Jednoduché odhalenie chyby      |

---

Ak chceš, môžem ti pripraviť **upravenú, „production-safe“ verziu `axis_cdc_fifo.sv`**,
ktorá zahŕňa všetky tieto opravy (CDC resety, staging register, bitové payloady, a korektné mapovanie handshake).

Chceš, aby som ju napísal?
