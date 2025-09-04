// seg7_driver.sv - Vylepšený a univerzálny ovládač pre 7-segmentový displej
//
// Verzia 2.0 - Vylepšenia
//
// Kľúčové zmeny:
// 1. VYLEPŠENIE (Flexibilita): Pridaný nový parameter `INVERT_DIGIT_EN` na
//    nezávislé riadenie polarity signálov pre výber číslice. To umožňuje
//    priame pripojenie displejov so spoločnou anódou (active-low enable).
// 2. VYLEPŠENIE (Robustnosť): Mierne upravená logika počítadla pre ešte
//    väčšiu robustnosť.
// 3. VYLEPŠENIE (Čitateľnosť): Pridané komentáre vysvetľujúce nové parametre.

`default_nettype none

module seg7_driver #(
    // --- Konfiguračné parametre ---
    parameter bit INVERT_SEGS    = 1, // 1: Invertuje seg+dp (pre spoločnú anódu)
    parameter bit INVERT_DIGIT_EN= 1, // 1: Invertuje digit_en (pre spoločnú anódu)
    parameter int DIGITS         = 3,
    // Mapa fyzického pripojenia. Príklad: '{2, 1, 0} pre obrátené poradie
    parameter int DIGIT_MAP [DIGITS-1:0] = '{default: 0}, 
    parameter int CLK_FREQ_HZ    = 50_000_000,
    parameter int REFRESH_HZ     = 1000
)(
    input  logic clk,
    input  logic rstn,
    // Vstupné dáta: pole 4-bitových čísel (0-15) a pole bitov pre desatinné bodky
    input  logic [3:0]           digits [DIGITS-1:0],
    input  logic                 dots   [DIGITS-1:0],
    // Výstupný interface
    seg7_driver_if.output_port   seg_if
);

    // --- Počítadlo pre multiplexovanie ---
    // Vypočíta počet taktov hodín na jeden cyklus obnovenia jednej číslice
    localparam int COUNT_MAX = CLK_FREQ_HZ / (REFRESH_HZ * DIGITS);
    logic [$clog2(COUNT_MAX)-1:0] refresh_cnt;
    logic [$clog2(DIGITS)-1:0]     current_digit;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            refresh_cnt   <= '0;
            current_digit <= '0;
        end else begin
            if (refresh_cnt >= COUNT_MAX - 1) begin
                refresh_cnt <= '0;
                // Bezpečne prejde na ďalšiu číslicu a preklopí sa na nulu
                if (current_digit >= DIGITS - 1) begin
                    current_digit <= '0;
                end else begin
                    current_digit <= current_digit + 1;
                end
            end else begin
                refresh_cnt <= refresh_cnt + 1;
            end
        end
    end

    // --- Výber aktuálnej číslice a bodky podľa mapovania ---
    logic [3:0] digit_val;
    logic       dot_val;

    always_comb begin
        // Použije mapu na výber správnych dát pre aktuálne aktívnu fyzickú číslicu
        digit_val = digits[DIGIT_MAP[current_digit]];
        dot_val   = dots[DIGIT_MAP[current_digit]];
    end

    // --- Segmentový dekóder ako funkcia (mapovanie 0-F na segmenty g-a) ---
    function automatic logic [6:0] digit_to_seg(input logic [3:0] d);
        case (d)
            4'h0: return 7'b0111111; // 0
            4'h1: return 7'b0000110; // 1
            4'h2: return 7'b1011011; // 2
            4'h3: return 7'b1001111; // 3
            4'h4: return 7'b1100110; // 4
            4'h5: return 7'b1101101; // 5
            4'h6: return 7'b1111101; // 6
            4'h7: return 7'b0000111; // 7
            4'h8: return 7'b1111111; // 8
            4'h9: return 7'b1101111; // 9
            4'hA: return 7'b1110111; // A
            4'hB: return 7'b1111100; // b
            4'hC: return 7'b0111001; // C
            4'hD: return 7'b1011110; // d
            4'hE: return 7'b1111001; // E
            4'hF: return 7'b1110001; // F
            default: return 7'b0000000; // Vypnuté
        endcase
    endfunction

    logic [6:0] raw_seg;
    assign raw_seg = digit_to_seg(digit_val);

    // --- Výstupná logika s podporou invertovania ---
    // Invertuje segmenty a desatinnú bodku, ak je to potrebné (pre spoločnú anódu)
    assign seg_if.seg = INVERT_SEGS ? ~raw_seg : raw_seg;
    assign seg_if.dp  = INVERT_SEGS ? ~dot_val : dot_val;

    // Generovanie aktivácie číslic (one-hot)
    logic [DIGITS-1:0] digit_sel_onehot;
    always_comb begin
        digit_sel_onehot = '0;
        digit_sel_onehot[current_digit] = 1'b1;
    end
    
    // Invertuje signál pre výber číslice, ak je to potrebné (pre spoločnú anódu)
    assign seg_if.digit_en = INVERT_DIGIT_EN ? ~digit_sel_onehot : digit_sel_onehot;

endmodule
