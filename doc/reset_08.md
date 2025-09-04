Dobre, rozoberme si rozdiel medzi **synchrónnym aktívne nízkym resetom (`reset_n`)** a **synchrónnym aktívne vysokým resetom (`reset`)** v kontexte:

```systemverilog
always_ff @(posedge pixel_clk) begin
    if (reset_n == 0) begin
        // reset logika
    end else begin
        // bežný chod
    end
end
```

vs.

```systemverilog
always_ff @(posedge pixel_clk) begin
    if (reset == 1) begin
        // reset logika
    end else begin
        // bežný chod
    end
end
```

---

### 1. **Logický význam**

* **reset\_n** (aktívne nízky reset):
  Reset je aktívny, keď je signál `0` (LOW).
  **Bežný stav je `1` (HIGH)** – teda systém beží.
  Tento štýl je bežný v hardvéri, často nazývaný "active-low reset".

* **reset** (aktívne vysoký reset):
  Reset je aktívny, keď je signál `1` (HIGH).
  **Bežný stav je `0` (LOW)** – teda systém beží.

---

### 2. **Vplyv na kód**

Logika resetu je v oboch prípadoch úplne rovnaká, len sa invertuje podmienka:

* Pre `reset_n` sa píše `if (!reset_n)` alebo `if (reset_n == 0)`
* Pre `reset` sa píše `if (reset == 1)`

---

### 3. **Konvencia a kompatibilita**

* **Reset\_n** sa často používa v dizajnoch, kde reset signál je fyzicky aktívny na nízkej úrovni (napr. tlačidlo pripojené k GND).
* **Reset (aktívny HIGH)** sa často používa v situáciách, kde reset je generovaný logickou úrovňou HIGH (napr. systémový watchdog, softvérový reset).

---

### 4. **Syntéza a funkčnosť**

Syntetizéry s tým nemajú problém, dôležité je, aby podmienka bola korektná podľa toho, ako reset signál funguje.
Dôležité je, aby reset bol správne synchronizovaný (pri synchrónnom resete) a použité správne logické hodnoty.

---

### 5. **Príklad:**

```systemverilog
// Synchrónny aktívne nízky reset
always_ff @(posedge clk) begin
    if (!reset_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end
```

```systemverilog
// Synchrónny aktívne vysoký reset
always_ff @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end
```

---

### **Zhrnutie:**

* Rozdiel je len v logickej úrovni, pri ktorej je reset aktívny (LOW pre `reset_n`, HIGH pre `reset`).
* Je dôležité konzistentne používať zvolený typ resetu v celom dizajne.
* Pre synchrónny reset vždy používame kontrolu **vo vnútri `posedge clk`**.

---

Ak chceš, môžem ti ukázať konkrétne príklady implementácie a synchronizácie pre oba typy! Alebo chceš vedieť, ktorý typ je vhodnejší pre dané použitie?
