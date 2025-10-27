/**
 * @file        axis_to_vga.sv
 * @brief       AXI-Stream na VGA prevodník s časovaním a registrovaným výstupom.
 * @details     Modul číta AXI4-Stream dáta (TDATA, TVALID) a generuje farebné (RGB)
 * a synchronizačné (HS, VS) signály pre VGA monitor na základe
 * parametrizovateľného VGA časovania.
 * Implementuje AXI4-Stream slave rozhranie s back-pressure (TREADY)
 * riadeným aktívnou zobrazovacou oblasťou VGA.
 * Výstupné VGA signály (vga_color_o, vga_hs_o, vga_vs_o) sú registrované
 * pre zlepšenie časovania na výstupe z FPGA.
 *
 * @param H_ACT, H_FP, ...    Parametre VGA časovania pre horizontálnu os (aktívna oblasť, predná veranda, sync pulz, zadná veranda).
 * @param V_ACT, V_FP, ...    Parametre VGA časovania pre vertikálnu os.
 * @param H_SYNC_POLARITY     Polarita HSync (1=Aktívna HIGH, 0=Aktívna LOW). Importované z vga_pkg.
 * @param V_SYNC_POLARITY     Polarita VSync. Importované z vga_pkg.
 * @param OUTPUT_FORMAT       Dátový formát výstupnej farby (konštanta 888 alebo 565).
 * @param AXI_DATA_WIDTH      Šírka AXI TDATA (musí zodpovedať OUTPUT_FORMAT a axi_pkg).
 * @param AXI_USER_WIDTH      Šírka AXI TUSER (v tejto verzii sa nepoužíva, ale parameter zostáva pre kompatibilitu rozhrania).
 * @param BLANKING_COLOR_...  Farba zobrazovaná počas blankingových intervalov (mimo aktívnej oblasti).
 */

`ifndef AXIS_TO_VGA_SV
`define AXIS_TO_VGA_SV

`default_nettype none

// Importy potrebných balíčkov
import axi_pkg::*; // Pre AXI parametre (aj keď sa tu explicitne nepoužívajú, rozhranie ich očakáva)
import vga_pkg::*; // Pre VGA konštanty (polarita) a typy (LineCounterWidth)

module axis_to_vga #(
    // --- Parametre VGA časovania ---
    // Tieto hodnoty definujú rozlíšenie a synchronizáciu.
    // Mali by byť nastavené podľa požadovaného VGA režimu (napr. pomocou funkcií z vga_pkg v top module).
    parameter int H_ACT = 800, // Počet pixelov v aktívnom riadku
    parameter int H_FP  = 40,  // Dĺžka prednej verandy (pixely)
    parameter int H_SP  = 128, // Dĺžka HSync pulzu (pixely)
    parameter int H_BP  = 88,  // Dĺžka zadnej verandy (pixely)
    parameter int V_ACT = 600, // Počet aktívnych riadkov
    parameter int V_FP  = 1,   // Dĺžka prednej verandy (riadky)
    parameter int V_SP  = 4,   // Dĺžka VSync pulzu (riadky)
    parameter int V_BP  = 23,  // Dĺžka zadnej verandy (riadky)

    // --- Parametre polarity ---
    // Určujú, či je synchronizačný pulz aktívny pri log. 1 alebo log. 0.
    parameter bit H_SYNC_POLARITY = vga_pkg::PulseActiveHigh,
    parameter bit V_SYNC_POLARITY = vga_pkg::PulseActiveHigh,

    // --- Parameter výstupného formátu ---
    // Určuje šírku a formát výstupného farebného signálu.
    parameter int OUTPUT_FORMAT = 565, // Možnosti: 565 (pre RGB565) alebo 888 (pre RGB888)

    // --- Parametre AXI Streamu (pre kompatibilitu rozhrania) ---
    // Tieto definujú šírku vstupného AXI streamu. Musia zodpovedať pripojenému zdroju.
    parameter int AXI_DATA_WIDTH = 16, // Musí byť >= 16 pre 565, >= 24 pre 888
    parameter int AXI_USER_WIDTH = 1,  // V tejto verzii sa TUSER nevyužíva

    // --- Parametre farieb ---
    // Definuje farbu zobrazovanú mimo aktívnej oblasti.
    parameter logic [23:0] BLANKING_COLOR_888  = 24'h101010, // Tmavá sivá pre RGB888
    parameter logic [15:0] BLANKING_COLOR_565  = 16'h1082  // Tmavá sivá pre RGB565
)(
    // --- Hodiny a Reset ---
    // Modul pracuje v hodinovej doméne pixelového taktu (Pixel Clock).
    input  logic clk_i,    // Pixel Clock
    input  logic rst_ni,   // Reset (aktívny v nule), synchrónny voči clk_i

    // --- AXI Stream Slave Interface ---
    // Vstup dát z predchádzajúceho modulu (napr. FIFO, generátor).
    // Očakáva sa, že tento stream beží v rovnakej hodinovej doméne (clk_i).
    axi4s_if.slave s_axis,

    // --- VGA Výstup ---
    // Výstupné signály pre VGA monitor. Šírka farby závisí od OUTPUT_FORMAT.
    output logic [ (OUTPUT_FORMAT == 565) ? 15 : 23 : 0 ] vga_color_o, // RGB dáta
    output logic vga_hs_o, // Horizontálny Sync
    output logic vga_vs_o, // Vertikálny Sync

    // --- Diagnostický výstup ---
    // Signalizuje, kedy je modul v aktívnej zobrazovacej oblasti.
    output logic hde_o     // Horizontal Data Enable
);

    // --- Lokálne parametre ---
    // Vypočítané celkové dĺžky cyklov pre jednoduchšie porovnanie.
    localparam int CHTotal = H_ACT + H_FP + H_SP + H_BP; // Celkový počet pixelových taktov na riadok
    localparam int CVTotal = V_ACT + V_FP + V_SP + V_BP; // Celkový počet riadkov na snímok

    // --- Interné signály ---

    // Počítadlá pre generovanie VGA časovania
    logic [vga_pkg::LineCounterWidth-1:0] h_count_reg; // Počítadlo pixelov v riadku
    logic [vga_pkg::LineCounterWidth-1:0] v_count_reg; // Počítadlo riadkov v snímku

    // Kombinačné signály pre synchronizáciu a aktívnu oblasť
    logic h_sync_comb;      // Indikuje HSync pulz (pred aplikáciou polarity)
    logic v_sync_comb;      // Indikuje VSync pulz (pred aplikáciou polarity)
    logic active_area_comb; // Indikuje aktívnu zobrazovaciu oblasť (HDE/VDE)

    // Signály pre výstupný register (pipeline stage pre zlepšenie časovania)
    logic [ (OUTPUT_FORMAT == 565) ? 15 : 23 : 0 ] vga_color_next; // Vypočítaná farba pred registrom
    logic vga_hs_next;    // Vypočítaný HSync pred registrom
    logic vga_vs_next;    // Vypočítaný VSync pred registrom

    logic [ (OUTPUT_FORMAT == 565) ? 15 : 23 : 0 ] vga_color_reg; // Registrovaná výstupná farba
    logic vga_hs_reg;     // Registrovaný výstupný HSync
    logic vga_vs_reg;     // Registrovaný výstupný VSync

    // =========================================================================
    // Blok 1: Generátor VGA Časovania
    // =========================================================================
    // Dva vnorené počítadlá (h_count_reg, v_count_reg), ktoré bežia neustále
    // a generujú základné časovanie VGA signálu.

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            // Reset počítadiel na začiatok snímku
            h_count_reg <= '0;
            v_count_reg <= '0;
        end else begin
            // Inkrementácia horizontálneho počítadla
            if (h_count_reg == CHTotal - 1) begin
                h_count_reg <= '0; // Pretečenie na konci riadku
                // Inkrementácia vertikálneho počítadla na konci riadku
                if (v_count_reg == CVTotal - 1) begin
                    v_count_reg <= '0; // Pretečenie na konci snímku
                end else begin
                    v_count_reg <= v_count_reg + 1'b1; // Posun na ďalší riadok
                end
            end else begin
                h_count_reg <= h_count_reg + 1'b1; // Posun na ďalší pixel
            end
        end
    end

    // Kombinačná logika na dekódovanie stavu počítadiel a generovanie
    // pomocných signálov pre HSync, VSync a aktívnu oblasť.
    always_comb begin
        // HSync pulz je aktívny počas H_SP periódy
        h_sync_comb = (h_count_reg >= H_ACT + H_FP) && (h_count_reg < H_ACT + H_FP + H_SP);
        // VSync pulz je aktívny počas V_SP periódy
        v_sync_comb = (v_count_reg >= V_ACT + V_FP) && (v_count_reg < V_ACT + V_FP + V_SP);
        // Aktívna oblasť je tam, kde sú obe súradnice v rámci viditeľného rozsahu
        active_area_comb = (h_count_reg < H_ACT) && (v_count_reg < V_ACT);
    end

    // =========================================================================
    // Blok 2: AXI-Stream Handshake
    // =========================================================================
    // Riadenie spätného tlaku (back-pressure) na vstupný AXI stream.
    // Prijímame dáta (TREADY=1) iba vtedy, keď sme v aktívnej oblasti,
    // inak (počas blankingu) zastavíme prísun dát (TREADY=0).
    assign s_axis.TREADY = active_area_comb;

    // =========================================================================
    // Blok 3: Kombinačná Logika pre Výstupné Signály
    // =========================================================================
    // Táto časť vypočíta hodnoty pre výstupné registre na základe aktuálneho
    // stavu časovania a vstupných AXI dát.

    // Generate blok vyberie správnu logiku podľa požadovaného formátu (565 alebo 888)
    generate
        // --- Vetva pre RGB888 ---
        if (OUTPUT_FORMAT == 888) begin : gen_rgb888
            always_comb begin
                // Ak sme v aktívnej oblasti A zároveň prichádzajú platné dáta z AXI
                if (active_area_comb && s_axis.TVALID) begin
                    vga_color_next = s_axis.TDATA[23:0]; // Použijeme AXI dáta
                end else begin
                    // Inak (počas blankingu alebo ak dáta nie sú platné - underrun)
                    vga_color_next = BLANKING_COLOR_888; // Zobrazíme farbu pozadia
                end
            end
        // --- Vetva pre RGB565 ---
        end else begin : gen_rgb565
            always_comb begin
                // Ak sme v aktívnej oblasti A zároveň prichádzajú platné dáta z AXI
                if (active_area_comb && s_axis.TVALID) begin
                    vga_color_next = s_axis.TDATA[15:0]; // Použijeme AXI dáta
                end else begin
                    // Inak (počas blankingu alebo ak dáta nie sú platné - underrun)
                    vga_color_next = BLANKING_COLOR_565; // Zobrazíme farbu pozadia
                end
            end
        end
    endgenerate

    // Vypočítame finálne hodnoty HSync a VSync s aplikovanou polaritou
    assign vga_hs_next = h_sync_comb ^ ~H_SYNC_POLARITY; // XOR s negovanou polaritou
    assign vga_vs_next = v_sync_comb ^ ~V_SYNC_POLARITY; // (Ak je polarita 0 (Low), signál sa invertuje)

    // =========================================================================
    // Blok 4: Registrácia Výstupných Signálov
    // =========================================================================
    // Tento blok pridáva jeden takt oneskorenia na všetky VGA výstupy,
    // čím zlepšuje časovanie (umožňuje dlhšie kombinačné cesty pred registrom).

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            // Reset výstupných registrov na definovaný stav
            vga_color_reg <= '0; // Reset na čiernu
            vga_hs_reg    <= 1'b1 ^ ~H_SYNC_POLARITY; // Reset na neaktívny stav HSync
            vga_vs_reg    <= 1'b1 ^ ~V_SYNC_POLARITY; // Reset na neaktívny stav VSync
        end else begin
            // V normálnom behu preklápame hodnoty z kombinačnej logiky
            vga_color_reg <= vga_color_next;
            vga_hs_reg    <= vga_hs_next;
            vga_vs_reg    <= vga_vs_next;
        end
    end

    // =========================================================================
    // Blok 5: Finálne Priradenie Výstupov
    // =========================================================================
    // Pripojíme výstupy z registrov na fyzické porty modulu.
    assign vga_color_o = vga_color_reg;
    assign vga_hs_o    = vga_hs_reg;
    assign vga_vs_o    = vga_vs_reg;

    // Diagnostický výstup HDE je priamo kombinačný signál aktívnej oblasti
    assign hde_o       = active_area_comb;
    // Underrun už nedetekujeme v tejto zjednodušenej verzii

endmodule

`default_nettype wire // Obnovenie predvoleného typu siete

`endif // AXIS_TO_VGA_SV

