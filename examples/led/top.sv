/**
 * @brief      Testovací modul pre FPGA, ktorý generuje tri nezávislé vizuálne efekty na troch skupinách LED diód v sekundových intervaloch.
 * @details    Modul implementuje tri odlišné svetelné vzory pre demonštračné a testovacie účely. Hlavný časovač, odvodený od systémových hodín, generuje impulz každú sekundu, ktorý spúšťa zmenu stavu vo všetkých troch efektoch súčasne.
 * Podporované efekty sú:
 * 1. 6-bitové vstavané LED: Klasické "bežiace svetlo" (cyklický posun).
 * 2. 8-bitové LED na J10: Efekt "plniaceho sa stĺpca", kde sa LED postupne rozsvecujú a po dosiahnutí plného počtu zhasnú.
 * 3. 8-bitové LED na J11: Efekt "Cylon Eye" / "Larson Scanner", kde sa jedna LED pohybuje tam a späť po celej dĺžke.
 *
 * Vstupy BSW a výstupy pre 7-segmentový displej a VGA sú v návrhu deklarované, ale nie sú aktívne využívané a sú nastavené na log. 0.
 *
 * @param[in]  CLK_FREQ         Frekvencia vstupných systémových hodín v Hz. Predvolená hodnota je 50,000,000 (50 MHz).
 *
 * @input      SYS_CLK          Vstupný hodinový signál.
 * @input      RESET_N          Aktívny nízky asynchrónny reset signál.
 * @input      BSW              6-bitový vstup z prepínačov (v tomto návrhu nevyužitý).
 *
 * @output     LED              6-bitový výstup pre vstavané LED diódy (efekt bežiaceho svetla).
 * @output     LED_J10          8-bitový výstup pre externé LED diódy (efekt plniaceho sa stĺpca).
 * @output     LED_J11          8-bitový výstup pre externé LED diódy (efekt 'Cylon Eye').
 * @output     SMG_SEG          Výstup pre segmenty 7-segmentového displeja (nevyužitý, nastavený na 0).
 * @output     SMG_DIG          Výstup pre anódy/katódy 7-segmentového displeja (nevyužitý, nastavený na 0).
 * @output     VGA_R, G, B      Výstupy pre farebné zložky VGA (nevyužité, nastavené na 0).
 * @output     VGA_HS, VGA_VS   Výstupy pre VGA synchronizáciu (nevyužité, nastavené na 0).
 *
 * @example
 * // Ukážka inštancie modulu pre 100 MHz hodiny
 * top #(
 * .CLK_FREQ(100_000_000)
 * ) u_led_tester (
 * .SYS_CLK(i_clk_100mhz),
 * .RESET_N(i_reset_n),
 * .LED(o_board_leds),
 * .LED_J10(o_j10_leds),
 * .LED_J11(o_j11_leds),
 * // Ostatné porty môžu byť ponechané nepripojené, ak to kontext dovoľuje
 * .BSW(),
 * .SMG_SEG(),
 * .SMG_DIG(),
 * .VGA_R(),
 * .VGA_G(),
 * .VGA_B(),
 * .VGA_HS(),
 * .VGA_VS()
 * );
 */


`timescale 1ns/1ps

module top #(
    parameter int CLK_FREQ = 50_000_000 // Frekvencia hodín v Hz
) (
    // ANSI-C štýl portov, upravené šírky pre J10 a J11
    input  logic        SYS_CLK,
    input  logic        RESET_N,
    output logic [7:0] SMG_SEG,
    output logic [2:0] SMG_DIG,
    output logic [5:0] LED,
    output logic [7:0] LED_J10,
    output logic [7:0] LED_J11,
    input  logic [5:0] BSW,
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic        VGA_HS,
    output logic        VGA_VS
);

    // Vypočítame si hodnotu pre 1 sekundu
    localparam int OneSecondCount = CLK_FREQ - 1;

    // --- Hlavný čítač a generátor 1-sekundového impulzu ---
    logic [$clog2(CLK_FREQ)-1:0] counter;
    logic one_sec_tick;

    assign one_sec_tick = (counter == OneSecondCount);

    always_ff @(posedge SYS_CLK or negedge RESET_N) begin
        if (!RESET_N) begin
            counter <= '0;
        end else begin
            if (one_sec_tick) begin
                counter <= '0;
            end else begin
                counter <= counter + 1;
            end
        end
    end

    // --- Logika pre 6 vstavaných LED (bez zmeny) ---
    logic [5:0] led_reg;
    always_ff @(posedge SYS_CLK or negedge RESET_N) begin
        if (!RESET_N) begin
            led_reg <= 6'd1;
        end else if (one_sec_tick) begin
            led_reg <= {led_reg[4:0], led_reg[5]};
        end
    end
    assign LED = led_reg;


    // --- Logika pre J10 (Fill Bar / Plniaci sa stĺpec) ---
    logic [3:0] fill_counter; // 4 bity stále stačia na počítanie do 8
    always_ff @(posedge SYS_CLK or negedge RESET_N) begin
        if (!RESET_N) begin
            fill_counter <= '0;
        end else if (one_sec_tick) begin
            if (fill_counter == 8) begin
                fill_counter <= '0;
            end else begin
                fill_counter <= fill_counter + 1;
            end
        end
    end
    // << ZMENA: Maska a posun upravené pre 8 bitov
    assign LED_J10 = (8'hFF >> (8 - fill_counter));


    // --- Logika pre J11 (Cylon Eye / Larson Scanner) ---

    typedef enum logic {RIGHT, LEFT} direction_t;

    logic [7:0]   cylon_pos;
    direction_t   cylon_dir;

    always_ff @(posedge SYS_CLK or negedge RESET_N) begin
        if (!RESET_N) begin
            cylon_pos <= 8'd1;
            cylon_dir <= RIGHT;
        end else if (one_sec_tick) begin
            if (cylon_dir == RIGHT) begin
                if (cylon_pos[7]) begin
                    cylon_dir <= LEFT;
                    cylon_pos <= cylon_pos >> 1;
                end else begin
                    cylon_pos <= cylon_pos << 1;
                end
            end else begin // cylon_dir == LEFT
                if (cylon_pos[0]) begin // Kontrola bitu 0 zostáva rovnaká
                    cylon_dir <= RIGHT;
                    cylon_pos <= cylon_pos << 1;
                end else begin
                    cylon_pos <= cylon_pos >> 1;
                end
            end
        end
    end
    assign LED_J11 = cylon_pos;


    // --- Priradenie pre nepoužívané výstupy ---
    assign {SMG_SEG, SMG_DIG} = '0;
    assign {VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS} = '0;

endmodule
