Jasné, vysvetlím to jednoducho a konkrétne pre FPGA.

---

# Čo je metastabilita?

**Metastabilita** je stav digitálneho obvodu (najmä synchronných prvkov, napríklad flip-flopov), keď signál nie je jednoznačne na logickej úrovni `0` alebo `1`, ale „zasekne“ sa v prechodnom (nestabilnom) stave na nejaký čas.

---

### Prečo k tomu dochádza?

Synchronné obvody prijímajú vstupy presne na hranu hodín (`posedge clk`). Ak ale vstupný signál mení svoju hodnotu veľmi blízko k tejto hrane (v takzvanej *setup* alebo *hold* dobe), flip-flop nemusí stihnúť jednoznačne zachytiť `0` alebo `1`.

Výsledkom je, že výstup flip-flopu môže na chvíľu „plávať“ (nie je stabilný) a až po nejakom čase sa ustáli na správnu hodnotu.

---

# Metastabilita v FPGA obvodoch

* FPGA obsahuje veľa synchronných blokov (flip-flopov, registre, atď.).
* Signály z iných hodín, z vonkajších zdrojov (napr. tlačidlá, komunikácia) často **nie sú synchronizované** na lokálny hodiny FPGA.
* Keď sa takýto nesynchronizovaný signál (asynchrónny vstup) privedie priamo do synchronného bloku, môže spôsobiť metastabilitu.

---

### Čo sa stane, keď nastane metastabilita?

* Výstupný signál z flip-flopu nemusí byť ani `0` ani `1`.
* Môže to spôsobiť chyby v logike, nepredvídateľné správanie, alebo dokonca zamrznutie časti dizajnu.
* Čas trvania metastabilného stavu je náhodný, ale zvyčajne krátky — ale dôležité je, že sa nevie presne predvídať.

---

# Ako sa tomu predchádza v FPGA?

* **Synchronizácia asynchrónnych signálov:** Používajú sa špeciálne synchronizéry — napríklad reťazec 2-3 flip-flopov, ktoré „vyčistia“ signál a minimalizujú pravdepodobnosť metastability.
* **Používanie synchronných resetov** namiesto asynchrónnych, ak je to možné.
* **Oddelenie časových domén** a použitie FIFO alebo handshake protokolov pri prenose dát medzi nimi.

---

# Zhrnutie

|                   | Popis                                                       |
| ----------------- | ----------------------------------------------------------- |
| **Metastabilita** | Prechodný nestabilný stav flip-flopu (ani 0, ani 1)         |
| **Príčina**       | Nesprávne časovanie signálu voči hodinám (setup/hold)       |
| **V FPGA**        | Pri prenose asynchrónnych signálov do synchronnej logiky    |
| **Dôsledky**      | Nepredvídateľné správanie, chyby, zamrznutie dizajnu        |
| **Riešenie**      | Synchronizéry (viacero FF za sebou), správna synchronizácia |

---

Ak chceš, môžem ti nakresliť jednoduchý príklad synchronizéra, ktorý minimalizuje metastabilitu. Alebo chceš vysvetliť, ako to vyzerá v časovej osi?
