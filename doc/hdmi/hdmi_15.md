Skvelé! Budeme teda pokračovať – nasleduje **doplnkový kontext a implementácia**, ktorá ozrejmí:

---

## 🔍 Prečo sa používa CRC8 a CRC32 v HDMI InfoFrames?

### 🎯 Kontext:

HDMI používa rôzne typy paketov (InfoFrames, Video Data, Audio Data, atď.). Na zabezpečenie integrity údajov sa používajú:

| Typ rámca    | Dĺžka         | Kontrola integrity               |
| ------------ | ------------- | -------------------------------- |
| InfoFrame    | ≤ 31 B        | **CRC8**                         |
| Video Data   | Mnoho pixelov | **CRC32** (na dátové bloky)      |
| Audio Packet | 4 bajty × n   | žiadny CRC (implicitná kontrola) |

---

## ✅ CRC8 pre InfoFrame

Používa sa **iba pri InfoFrame pakete**, konkrétne:

* **Pozícia**: CRC8 je umiestnené na bajte `Header[2]`
* **Účel**: Overenie, že všetky bajty (okrem samotného CRC) neboli poškodené pri prenose

➡️ V našom SPD InfoFrame sme generovali CRC8 cez bežný polynóm `x⁸ + x² + x + 1` (`0x07`), čo je štandardné pre HDMI.

---

## ✅ CRC32 pri Video Data Islande

Používa sa pri:

* **Video timing**: TMDS video linka prenáša dáta cez tzv. **Data Islandy** (pri blankingu)
* **Overenie väčších blokov**: Keď je prenášaný väčší počet bajtov (napr. video zábery), používa sa **CRC32** kvôli vyššej spoľahlivosti

➡️ HDMI špecifikácia definuje CRC32 **pre video guard packet** – slúži na kontrolu integrity pre video sampling clock, nie InfoFrame.

---

## 📦 TL;DR – Kedy použiť ktorý?

| Použitie                | Typ CRC | Dôvod                           |
| ----------------------- | ------- | ------------------------------- |
| SPD/AVI/Audio InfoFrame | CRC8    | Malý rozsah dát, rýchly výpočet |
| Video Guard Packet      | CRC32   | Väčší blok, vyššia spoľahlivosť |

---

## 🛠️ Pokračovanie – čo generujeme ďalej?

Tu sú možnosti:

### 1. 🧪 Testbench

* Overí správnosť CRC8
* Vytlačí TMDS výstup pre SPD rámec
* Simulovateľné v ModelSim alebo Questa

### 2. 🧱 Pridáme AVI InfoFrame (napr. rozlíšenie, pomer strán)

### 3. 🎞️ Video Data Island (CRC32, guard bandy)

### 4. 🧬 TMDS TX so slot manažmentom (Data Island časovanie)

Máš preferenciu, ktorou cestou pokračujeme? Alebo chceš pokračovať kompletizáciou SPD+AVI v spoločnom top module s pridaným testbenchom?
