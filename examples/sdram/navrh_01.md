Jasné, navrhnúť takýto modul je typická a veľmi zaujímavá úloha pri práci s videom v FPGA. V podstate potrebujete vytvoriť inteligentný **DMA (Direct Memory Access) radič**, ktorý bude slúžiť ako prostredník medzi zdrojom obrazových dát, SDRAM pamäťou a VGA zobrazovačom.

Tento návrh bude priamo nadväzovať na vami vytvorený `SdramDriver` a `SdramController`.

-----

### Konceptuálny Návrh: Modul `FramebufferController`

Tento modul bude mať na starosti celú logiku spojenú s framebuffermi.

#### 1\. Hlavné Úlohy Modulu

1.  **Prijímať obrazové dáta:** Prijímať 16-bitové (RGB 565) pixely z nejakého zdroja (napr. z kamery, z generátora obrazcov, z CPU).
2.  **Zapisovať do "Back Buffera":** Postupne zapísať celý frame (800x600 pixelov) do jedného z dvoch framebufferov v SDRAM, ktorý je práve neaktívny (back buffer).
3.  **Poskytovať dáta pre VGA:** Súčasne a nezávisle čítať dáta z druhého, aktívneho framebuffera (front buffer) a posielať ich VGA zobrazovaču presne vtedy, keď ich potrebuje.
4.  **Prehadzovať buffre (Swapping):** Na požiadanie prehodiť úlohy bufferov, aby sa novo zapísaný obraz stal viditeľným a starý sa uvoľnil na prepísanie. Týmto sa zabráni "trhaniu" obrazu (screen tearing).

#### 2\. Architektúra a Umiestnenie v Systéme

Váš nový modul `FramebufferController` bude ústredným bodom, ktorý sa pripojí na AXI stranu vášho `SdramDriver`-a.

**Diagram toku dát:**

```
                 +-----------------------+      +-----------------+
[Zdroj Pixelov]----->|                       |----->|                 |----->[SDRAM]
                 |  FramebufferController  |      |   SdramDriver   |
[VGA Zobrazovač]<----|                       |<-----|                 |<-----[SDRAM]
                 +-----------------------+      +-----------------+
```

#### 3\. Pamäťová Mapa v SDRAM

Potrebujeme v SDRAM vyhradiť miesto pre dva framy.

  * **Rozlíšenie:** 800 x 600 pixelov
  * **Veľkosť jedného pixelu:** 16 bitov = 2 bajty
  * **Veľkosť jedného framebuffera:** `800 * 600 * 2 = 960,000` bajtov (`0xE_A600` v hex).
  * Váš `SdramController` pracuje so 16-bitovými slovami, takže adresa sa bude vzťahovať na slová, nie na bajty.
  * **Veľkosť v slovách:** `800 * 600 = 480,000` slov (`0x75300` v hex).

Navrhneme si pamäťovú mapu (adresy sú v 16-bitových slovách):

  * **Framebuffer 0 (FB0) Base Address:** `0x000000`
  * **Framebuffer 1 (FB1) Base Address:** `0x080000` (Zarovnané na peknú hranicu pre jednoduchosť)

Celková potrebná pamäť je menej ako 2 MB, čo je pre väčšinu SDRAM čipov bezproblémové.

#### 4\. Návrh Rozhraní (Portov) Modulu

```systemverilog
module FramebufferController #(
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter FB0_BASE_ADDR = 24'h000000,
    parameter FB1_BASE_ADDR = 24'h080000
)(
    input  logic clk, // Predpokladáme jednu hodinovú doménu (clk_axi z Drivera)
    input  logic rstn,

    // --- Rozhranie pre vstup pixelov (od zdroja obrazu) ---
    input  logic             pixel_in_valid,
    output logic             pixel_in_ready,
    input  logic [15:0]      pixel_in_data, // RGB 565

    // --- Rozhranie pre VGA Zobrazovač ---
    input  logic [9:0]       vga_req_x, // Horizontálna pozícia (0-799)
    input  logic [9:0]       vga_req_y, // Vertikálna pozícia (0-599)
    output logic [15:0]      vga_pixel_data,
    output logic             vga_pixel_valid,

    // --- Riadiace signály ---
    input  logic             ctrl_start_fill, // Impulz na spustenie plnenia back buffera
    input  logic             ctrl_swap_buffers, // Impulz na prehodenie bufferov
    output logic             status_busy_filling, // Indikátor, že prebieha plnenie

    // --- Rozhranie k SdramDriver (AXI strana) ---
    // Writer port
    output logic             sdram_writer_valid,
    input  logic             sdram_writer_ready,
    output logic [23:0]      sdram_writer_addr,
    output logic [15:0]      sdram_writer_data,

    // Reader port
    output logic             sdram_reader_valid,
    input  logic             sdram_reader_ready,
    output logic [23:0]      sdram_reader_addr,

    // Read response port
    input  logic             sdram_resp_valid,
    input  logic             sdram_resp_last,
    input  logic [15:0]      sdram_resp_data,
    output logic             sdram_resp_ready
);
```

#### 5\. Vnútorná Logika a Kľúčové Komponenty

1.  **Logika Dvojitého Buffrovania:**

      * Potrebujete jeden register, napr. `logic front_buffer_idx;`, ktorý bude mať hodnotu 0 alebo 1.
      * Tento register určí, ktorý framebuffer je "front" (na čítanie pre VGA). Druhý je automaticky "back" (na zápis).
      * Signál `ctrl_swap_buffers` jednoducho invertuje tento register: `front_buffer_idx <= ~front_buffer_idx;`.

2.  **Zapisovacia Cesta (Write Path):**

      * Malý stavový automat (FSM) bude riadiť proces zápisu.
      * Stavy: `IDLE`, `SETUP_WRITE`, `SEND_ADDR`, `SEND_DATA`.
      * Po prijatí `ctrl_start_fill` prejde FSM do `SETUP_WRITE`, kde si pripraví počiatočnú adresu back buffera.
      * Následne v cykle posiela požiadavky na zápis do `SdramDriver`-a. Generuje sekvenčné adresy od `base_addr` až po `base_addr + (800*600 - 1)`.
      * Bude prijímať dáta z `pixel_in_*` a posielať ich cez `sdram_writer_data`. Keďže váš `SdramDriver` očakáva najprv adresu a potom burst dát, táto FSM to musí rešpektovať.

3.  **Čítacia Cesta (Read Path) - *Najdôležitejšia a Najzložitejšia Časť***

      * **Problém:** VGA zobrazovač potrebuje pixely v tvrdom reálnom čase – **jeden pixel každý hodinový takt**. SDRAM má však vysokú a variabilnú latenciu (môže byť desiatky cyklov, kým prídu prvé dáta po požiadavke). Priamy preklad X/Y súradníc na požiadavku do SDRAM by nikdy nefungoval.
      * **Riešenie:** **Read-Ahead Line Buffer (FIFO)**. Čítacia cesta musí byť proaktívna.
          * Vytvoríte si interné, rýchle BRAM/FIFO, ktoré bude dostatočne veľké na uloženie aspoň jedného alebo dvoch riadkov obrazu (napr. `2 * 800 = 1600` slov).
          * **Prefetcher:** Ďalší malý FSM (prefetcher) bude sledovať `vga_req_y` (aktuálny zobrazovaný riadok).
          * Keď prefetcher zistí, že VGA sa blíži ku koncu riadku `N`, proaktívne pošle do `SdramDriver`-a sériu burst požiadaviek na prečítanie **celého nasledujúceho riadku `N+1`**.
          * Dáta, ktoré sa vrátia zo `sdram_resp_*` rozhrania, sa uložia do tohto interného **line buffera (FIFO)**.
          * **VGA výstup:** Keď VGA zobrazovač požiada o pixel na súradniciach (X, Y), tento pixel sa **nečíta priamo z SDRAM**, ale bleskovo sa **vytiahne z už pripraveného line buffera**.

Tento mechanizmus (prefetching do line buffera) je absolútne kľúčový pre akýkoľvek video systém pracujúci s externou pamäťou. Oddeľuje real-time požiadavky VGA od pomalej a nespoľahlivej latencie SDRAM.

#### 6\. Pseudokód (Príklad Priebehu)

1.  Systém sa zapne, `front_buffer_idx = 0`. VGA zobrazovač začne čítať (pravdepodobne čierny obraz) z FB0.
2.  Užívateľská logika vydá pulz `ctrl_start_fill`.
3.  `FramebufferController` začne prijímať pixely cez `pixel_in_*` a zapisovať ich do back buffera (FB1) na adresu `0x080000` a vyššie. Počas tohto procesu je `status_busy_filling` aktívny.
4.  Po zapísaní celého framu (480,000 pixelov) sa `status_busy_filling` deaktivuje.
5.  Počas vertikálnej synchronizácie (VBLANK) vydá riadiaca logika pulz `ctrl_swap_buffers`.
6.  `FramebufferController` zmení `front_buffer_idx` na 1.
7.  Od tohto momentu VGA zobrazovač začne čítať novo nakreslený obraz z FB1. FB0 sa stáva back bufferom, pripraveným na ďalší `ctrl_start_fill`.
8.  Cyklus sa opakuje.

-----

### Záver

Navrhovaný `FramebufferController` je komplexný, stavový modul, ktorý slúži ako inteligentný most medzi viacerými rozhraniami. Jeho správna implementácia, najmä **read-ahead line buffer** pre VGA čítanie, je kľúčom k funkčnému a plynulému zobrazovaniu videa z SDRAM pamäte.
