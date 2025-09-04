Toto je analýza poskytnutého modulu `AsyncFIFO.sv`. Tento modul je kritickou súčasťou celkového návrhu, pretože zabezpečuje bezpečný prenos dát medzi dvoma asynchrónnymi hodinovými doménami (Clock Domain Crossing - CDC) – konkrétne medzi `axi_clk` (125 MHz) a `pix_clk` (75 MHz) v predchádzajúcom projekte.

### Analýza Modulu `AsyncFIFO`

Modul `AsyncFIFO` je implementovaný štandardným a robustným spôsobom, využívajúc Grayov kód pre pointre, aby sa zabezpečila spoľahlivosť pri synchronizácii medzi hodinovými doménami.

#### Kľúčové Dizajnové Princípy

1.  **Použitie Grayovho Kódu:**

      * Pri prenose viacerých bitov (ako sú pointre FIFO) medzi asynchrónnymi doménami hrozí riziko, že ak sa viacero bitov zmení naraz, synchronizátor zachytí niektoré bity z novej hodnoty a niektoré zo starej, čo vedie k úplne nesprávnej adrese.
      * Grayov kód mení pri inkrementácii vždy iba jeden bit. Ak aj dôjde k metastabilite na tomto jednom bite počas synchronizácie, zachytená hodnota bude buď stará alebo nová adresa, nikdy nie chybná medzihodnota.
      * Implementácia používa funkcie `bin2gray` a `gray2bin`, ktoré sú správne definované.

2.  **Šírka Pointrov (N+1 bitov):**

      * Pointre (`wr_ptr_*`, `rd_ptr_*`) majú šírku `ADDR_WIDTH + 1` ($$log_2(DEPTH) + 1$$). Tento extra bit je kľúčový. Samotná adresa do pamäte používa len spodných `ADDR_WIDTH` bitov. Extra MSB (Most Significant Bit) sa používa na rozlíšenie medzi stavom "plné" a "prázdne", keď sa adresy po pretečení (wrap-around) rovnajú.

3.  **Synchronizácia Pointrov (`TwoFlopSynchronizer`):**

      * Predtým, než môže jedna doména skontrolovať stav druhej, musí synchronizovať pointer druhej strany. `rd_ptr_gray` sa synchronizuje do `wr_clk` domény a `wr_ptr_gray` sa synchronizuje do `rd_clk` domény.
      * Modul `TwoFlopSynchronizer` je štandardný dvojstupňový synchronizátor, ktorý minimalizuje pravdepodobnosť metastablity. Toto je správny prístup.

4.  **Synchronizácia Resetov:**

      * Kód obsahuje logiku na synchronizáciu externých asynchrónnych resetov (`wr_rstn`, `rd_rstn`) do ich príslušných hodinových domén. To zaisťuje, že uvoľnenie resetu prebehne synchrónne s hodinovým signálom, čo je nevyhnutné pre spoľahlivý štart systému.

#### Analýza Logiky `Full` a `Empty`

Detekcia stavov plný/prázdny musí byť pesimistická, pretože synchronizované pointre sú vždy mierne oneskorené oproti realite.

  * **Empty (Prázdne):**

    ```systemverilog
    assign empty = (rd_ptr_gray == wr_ptr_gray_rdclk_sync);
    ```

    FIFO je prázdne, ak sa lokálny čítací pointer (v Gray kóde) rovná synchronizovanému zápisovému pointeru. Toto je správne a pesimistické v čítacej doméne (môže ukázať `empty` o niečo skôr, ak práve prebieha zápis, čo je bezpečné).

  * **Full (Plné):**

    ```systemverilog
    assign full = (wr_ptr_gray == {~rd_ptr_gray_wrclk_sync[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_wrclk_sync[ADDR_WIDTH-2:0]});
    ```

    Toto je štandardná a správna metóda detekcie stavu "plné" pomocou Gray kódu. FIFO je plné, ak sa zápisový pointer rovná synchronizovanému čítaciemu pointeru, pričom dva najvyššie bity (MSB a MSB-1) sú invertované. Toto správne zohľadňuje extra bit a vlastnosti Grayovho kódu pri pretečení.

#### Vylepšenia a Robustnosť (Podľa komentárov V2.0)

1.  **Výpočet `almost_full` / `almost_empty`:**

      * Staršie alebo jednoduchšie implementácie FIFO sa snažia odvodiť tieto stavy priamo z Gray kódu, čo je zložité a náchylné na chyby.
      * Tento kód používa robustnejší prístup:
        1.  Synchronizuje Gray pointer z druhej domény.
        2.  Konvertuje tento synchronizovaný Gray pointer späť na binárny (`gray2bin`).
        3.  Vypočíta rozdiel medzi lokálnym binárnym pointerom a synchronizovaným binárnym pointerom (`wr_fill_count` alebo `rd_fill_count`).
        <!-- end list -->
        ```systemverilog
        logic [ADDR_WIDTH:0] wr_fill_count;
        assign wr_fill_count = wr_ptr_bin - rd_ptr_sync_wr_bin;
        assign almost_full = (wr_fill_count >= (DEPTH - ALMOST_FULL_THRESHOLD));
        ```
      * Toto poskytuje presný (hoci pesimistický) počet prvkov vo FIFO v danej hodinovej doméne, čo umožňuje spoľahlivé nastavenie prahových hodnôt.

2.  **Latencia Čítania:**

      * Dáta sú registrované hneď po prečítaní z pamäte:

    <!-- end list -->

    ```systemverilog
    always_ff @(posedge rd_clk) begin
        if (rd_en && !empty) begin
            rd_data_reg <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end
    assign rd_data = rd_data_reg;
    ```

      * Toto je štandardná implementácia pre dual-port RAM v FPGA, ktorá poskytuje latenciu 2 hodinových cyklov od požiadavky `rd_en` po platnosť dát na `rd_data`. Je to efektívne a zodpovedá vylepšeniu spomenutému v komentároch.

### Záver Analýzy `AsyncFIFO`

Implementácia modulu `AsyncFIFO` je **korektná, robustná a nasleduje osvedčené postupy** pre návrh asynchrónnych FIFO.

  * **CDC je riešené správne** pomocou Gray kódu a dvojstupňových synchronizátorov.
  * **Logika pre `full` a `empty` je štandardná** a správna pre N+1 bitové pointre.
  * **Výpočet úrovne naplnenia** pre `almost_full/empty` je robustný vďaka konverzii späť do binárneho kódu.
  * **Reset a latencia** sú riešené efektívne.

Tento modul je bezpečný na použitie v module `AxiStreamToVGA` z predchádzajúcej analýzy a zabezpečí spoľahlivý prenos AXI-Stream dát medzi 125 MHz a 75 MHz hodinovými doménami v prostredí Quartus. Syntetizačný nástroj by mal byť schopný efektívne implementovať pamäť FIFO pomocou blokovej RAM (BRAM) na cieľovom FPGA.
