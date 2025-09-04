Výborná otázka — odpoveď znie:

> **Áno, aj pri VGA výstupe je dôležité načasovanie**, ale požiadavky na **synchronizáciu dát** sú menej prísne než pri HDMI. Závisí to hlavne od toho, **ako** VGA signál generuješ.

---

## 📺 VGA vs HDMI – hlavné rozdiely v požiadavkách na synchronizáciu:

| Vlastnosť                           | VGA                                                   | HDMI                                       |
| ----------------------------------- | ----------------------------------------------------- | ------------------------------------------ |
| Fyzická vrstva                      | Analógová (RGB, HSYNC, VSYNC)                         | Digitálna (TMDS, PLL, DDR)                 |
| Kedy musí byť platný obrazový pixel | V **čase zmeny HSYNC/DE**, ale s určitým „rozmazaním“ | Presne v daný clock edge (bitová presnosť) |
| Vysielanie obrazu                   | Sústava DAC + HSYNC/VSYNC                             | TMDS linky so špecifickým kódom            |
| Tolerancia na fázové posuny         | Vysoká (signály sú analógové)                         | Nízka (bitový timing dôležitý)             |
| Potreba predprípravy dát            | Nízka až stredná                                      | Vysoká – každý pixel musí byť včas         |

---

## 🧠 Čo to znamená pre VGA výstup?

### ➤ Ak generuješ VGA „natvrdo“ z čítačiek (napr. `h_line`, `v_line`) a výstupy priamo dávajú RGB:

* **Stačí** držať sa toho, že RGB výstup je platný iba vtedy, keď `DE=1`
* Nemusíš pripravovať dáta 1 cyklus vopred
* Väčšinou môžeš použiť `if (de) rgb_out <= framebuffer_data`

### ➤ Ak používaš **video pamäť** alebo generuješ dáta cez pipeline:

* Musíš **synchronizovať načítanie pixelu** tak, aby RGB hodnota bola pripravená **v tom cykle**, keď `DE` je aktívny
* Tu môže byť potrebná predikcia (napr. `read_address <= current_pixel + 1;`)

---

## ✅ Zhrnutie

* **VGA nepotrebuje tak prísnu synchronizáciu ako HDMI**
* Ale **ak máš latency (napr. RAM, pipelina)**, **musíš synchronizovať adresovanie alebo načítanie dát**
* Nie je nutné mať lookahead signál `next_video` ako pri HDMI, ale **adresy do pamäte** by mali byť pripravené skôr, aby bol RGB pixel pripravený vo „video“ cykle

---

Ak chceš, môžem ti:

* Pomôcť navrhnúť VGA výstup z RAMky
* Ukázať, ako má vyzerať logika `read_en`, `read_addr`, aby RGB išlo von vo chvíli `DE=1`

Chceš príklad VGA pixel fetch z pamäte so synchronizáciou?
