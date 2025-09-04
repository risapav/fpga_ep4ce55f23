Používanie **`posedge`** a **`negedge`** v SystemVerilogu (a VHDL) má **praktické, časovacie a syntetizačné dôsledky**, ktoré sú dôležité najmä pri návrhu pre **FPGA** (napr. Quartus) alebo **ASIC**.

---

## 🔁 `posedge` vs `negedge`: rozdiel

| Signál        | Význam                                                 |
| ------------- | ------------------------------------------------------ |
| `posedge clk` | **pozitívna hrana** hodinového signálu – nábeh (0 → 1) |
| `negedge clk` | **negatívna hrana** hodinového signálu – pád (1 → 0)   |

---

## ✅ **Výhody `posedge`** (štandard v 99 % dizajnov)

* 🧠 **Konzistentné so štandardnou synchronizáciou** v nástrojoch (Quartus, Vivado, Synplify).
* ✔️ **Plne syntetizovateľné** na všetkých FPGA/ASIC platformách.
* 🔧 Lepšia **podpora pre časovaciu analýzu** (timing analysis).
* 🛠️ Ľahšia podpora pre **multi-clock** návrhy (napr. CDC).
* 🧪 Lepšia **simulácia a verifikácia**.

---

## ⚠️ **Nevýhody `negedge`**

* 🚫 **Nie vždy syntetizovateľné** – niektoré FPGA nástroje nemusia správne podporovať logiku na `negedge clk`.
* 📉 **Znižuje výkon**, ak sa kombinuje `posedge` a `negedge` v tom istom module – obvod sa stáva zložitejší.
* ⏱️ Časovanie je ťažšie kontrolovateľné.
* 🔄 **Zvýšené riziko prechodových stavov** a hazardov pri synchronizácii medzi hranami.
* ❌ Nie je vhodné pre **cross-domain synchronizáciu**.

---

## 🧪 Kedy použiť `negedge`?

Použitie `negedge` má **špecifické opodstatnenie**, ale **zriedkavo**:

| Prípad                 | Dôvod                                                                  |
| ---------------------- | ---------------------------------------------------------------------- |
| DDR (double data rate) | Ak je potrebné čítať/zapisovať **na oboch hranách hodinového signálu** |
| Špeciálne protokoly    | Niektoré staré periférie môžu vyžadovať `negedge` synchronizáciu       |
| Asymetrické časovanie  | Ak je návrh časovo optimalizovaný pre špecifické fázy hodinového cyklu |

---

## 💡 Odporúčanie pre **FPGA a Quartus**

> **Používaj výlučne `posedge`**, pokiaľ **naozaj nepotrebuješ** čítať/zapisovať dáta na obe hrany (napr. DDR SDRAM interface).

---

## 📌 Záver

| Kritérium          | `posedge`         | `negedge`               |
| ------------------ | ----------------- | ----------------------- |
| Štandardná voľba   | ✅ Áno             | ❌ Nie                   |
| Syntetizovateľnosť | ✅ Bez problémov   | ⚠️ Potenciálne problémy |
| Časovanie          | ✅ Predvídateľné   | ⚠️ Náchylné na hazardy  |
| Kompatibilita      | ✅ Quartus, Vivado | ⚠️ Môžu byť obmedzenia  |

---

Ak chceš, môžem ti hneď teraz **prepísať celý modul `Rgb`** tak, aby používal **len `posedge`**, bol **plne syntetizovateľný** a čitateľný v **SystemVerilog**. Stačí dať vedieť.
