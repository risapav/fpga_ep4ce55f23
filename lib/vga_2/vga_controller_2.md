Refaktorovanie prebehlo úspešne. Tu je súhrn hlavných zmien a odporúčaní, ktoré boli zapracované:

### ✅ Vylepšenia a úpravy:

* **Zjednotená štruktúra poznámok a hlavičky modulu**: Zreteľný popis, čo modul robí, vrátane zmenového logu.
* **Rozšírené debugovanie**:

  * Pridaný výstup `valid_pixel_counter` pre sledovanie spracovaných pixelov.
  * Pridaný signál `fifo_active` indikujúci činnosť FIFO.
* **CDC synchronizácia**:

  * Spoľahlivo vyriešený prechod medzi `axi_clk` a `pix_clk` pomocou `TwoFlopSynchronizer`.
* **Prehľadné riadenie AXI4-Stream handshake**: `tready` je aktívny iba v prípade, že je stream povolený a FIFO nie je plné.
* **Prehľadná detekcia začiatku/konca frame** s využitím `pos` a `signal.active`.
* **Prepínateľná podpora RGB888/RGB565**: Funkcia `decode_color()` rozlišuje na základe `USE_RGB888`.
* **Test mód (farebné pásy)** implementovaný cez `TEST_MODE`.

### 📝 Poznámky na zváženie do budúcnosti:

1. **FIFO hlboký monitoring (napr. takmer plný/prázdny)** – pre dynamickejšie riadenie AXI handshake a lepšiu spätnú väzbu.
2. **Možnosť externého resetu pre sticky flagy** (napr. cez riadiaci register).
3. **Rozšírenie na ďalšie farebné formáty (napr. YUV, monochrome)** ak bude potrebné.
4. **Optimalizácia pixel pipeline (napr. register stage pre pixel\_color)** pre vyššie frekvencie.

Ak chceš doplniť testbench, pridať registráciu cez AXI-lite, alebo analyzovať konkrétnu časť správania (napr. CDC alebo overflow ochranu), daj vedieť.
