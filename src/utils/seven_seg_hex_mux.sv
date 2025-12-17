/**
 * @file        seven_seg_hex_mux.sv
 * @brief       Multiplexovaný 7-segmentový ovládač (HEX dekodér).
 * @details     Ovláda viacmiestny 7-segmentový displej. Podporuje číslice 0-F
 * a desatinné bodky. Konfigurovateľný pre Spoločnú Anódu alebo Katódu.
 *
 * @param NUM_DIGITS       Počet číslic (digitov).
 * @param CLOCK_FREQ_HZ    Frekvencia vstupných hodín.
 * @param DIGIT_REFRESH_HZ Obnovovacia frekvencia na jeden digit.
 * @param COMMON_ANODE     1 = Common Anode (0=ON), 0 = Common Cathode (1=ON).
 *
 * @input  clk_i           Hodinový signál.
 * @input  rst_ni          Asynchrónny reset (active-low).
 * @input  digits_i        Pole hodnôt pre jednotlivé digity (0-F).
 * @input  dots_i          Pole pre desatinné bodky.
 * @output digit_sel_o     Výber digitu (One-Hot).
 * @output segment_sel_o   Výber segmentov (DP,G,F,E,D,C,B,A).
 * @output current_digit_o Index práve aktívneho digitu (pre debug).
 */

`default_nettype none

`ifndef SEVEN_SEG_HEX_MUX_SV
`define SEVEN_SEG_HEX_MUX_SV

module seven_seg_hex_mux #(
    parameter int NUM_DIGITS       = 4,
    parameter int CLOCK_FREQ_HZ    = 50_000_000,
    parameter int DIGIT_REFRESH_HZ = 250,
    parameter bit COMMON_ANODE     = 1
) (
    input  wire logic                     clk_i,
    input  wire logic                     rst_ni, // Premenované z arstn
    input  wire logic [3:0]               digits_i [NUM_DIGITS], // Unpacked array
    input  wire logic                     dots_i   [NUM_DIGITS],
    output      logic [NUM_DIGITS-1:0]    digit_sel_o,
    output      logic [7:0]               segment_sel_o,
    output      logic [$clog2(NUM_DIGITS)-1:0] current_digit_o
);

    // -------------------------------------------------------------------------
    // 1. Výpočty časovania
    // -------------------------------------------------------------------------
    localparam int TicksPerDigit = (DIGIT_REFRESH_HZ == 0 || CLOCK_FREQ_HZ == 0)
                                   ? 1 : CLOCK_FREQ_HZ / DIGIT_REFRESH_HZ;
    localparam int TicksWidth    = $clog2(TicksPerDigit);
    localparam int NumDigitsWidth = $clog2(NUM_DIGITS);

    // -------------------------------------------------------------------------
    // 2. Interné registre
    // -------------------------------------------------------------------------
    logic [TicksWidth-1:0]     tick_counter;
    logic [NumDigitsWidth-1:0] seg_idx;
    logic [NUM_DIGITS-1:0]     digit_sel_next;
    logic [7:0]                segment_sel_next;

    assign current_digit_o = seg_idx;

    // -------------------------------------------------------------------------
    // 3. Časovač a Multiplexovanie (Sequential)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tick_counter <= '0;
            seg_idx      <= '0;
        end else begin
            if (tick_counter == TicksPerDigit - 1) begin
                tick_counter <= '0;
                seg_idx      <= (seg_idx == NUM_DIGITS - 1) ? '0 : seg_idx + 1'b1;
            end else begin
                tick_counter <= tick_counter + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Dekodér 7-segmentovky (Function)
    // -------------------------------------------------------------------------
    function automatic logic [7:0] seg_decoder(
        input logic [3:0] val,
        input logic       dot
    );
        logic [6:0] seg_raw; // Segmenty G-F-E-D-C-B-A
        logic [7:0] seg_full;

        // Tabuľka definovaná ako Active LOW (0 = ON, 1 = OFF)
        // Formát: G F E D C B A
        case (val)
            4'h0: seg_raw = 7'b1000000;
            4'h1: seg_raw = 7'b1111001;
            4'h2: seg_raw = 7'b0100100;
            4'h3: seg_raw = 7'b0110000;
            4'h4: seg_raw = 7'b0011001;
            4'h5: seg_raw = 7'b0010010;
            4'h6: seg_raw = 7'b0000010;
            4'h7: seg_raw = 7'b1111000;
            4'h8: seg_raw = 7'b0000000;
            4'h9: seg_raw = 7'b0010000;
            4'hA: seg_raw = 7'b0001000;
            4'hB: seg_raw = 7'b0000011;
            4'hC: seg_raw = 7'b1000110;
            4'hD: seg_raw = 7'b0100001;
            4'hE: seg_raw = 7'b0000110;
            4'hF: seg_raw = 7'b0001110;
            default: seg_raw = 7'b1111111; // OFF
        endcase

        // Zloženie s desatinnou bodkou (Active Low: ak dot=1, ~dot=0=ON)
        seg_full = {~dot, seg_raw}; 

        // Prispôsobenie polarite displeja
        // Ak Common Anode: 0=ON (vrátime seg_full)
        // Ak Common Cathode: 1=ON (vrátime ~seg_full)
        return (COMMON_ANODE) ? seg_full : ~seg_full;
    endfunction

    // -------------------------------------------------------------------------
    // 5. Logika Výstupov (Combinatorial)
    // -------------------------------------------------------------------------
    always_comb begin
        // Inicializácia (vypnuté)
        digit_sel_next = (COMMON_ANODE) ? {NUM_DIGITS{1'b0}} : {NUM_DIGITS{1'b1}}; 
        // Pozn: Pre digit select (tranzistor) zvyčajne platí:
        // Common Anode (PNP): 0 = Active. Common Cathode (NPN): 1 = Active.
        // Pôvodný kód mal logiku:
        // CA: default 1 (OFF), active 0 (ON).
        // CC: default 0 (OFF), active 1 (ON).
        
        if (COMMON_ANODE) begin
             // Active Low pre PNP tranzistory
             digit_sel_next = {NUM_DIGITS{1'b1}}; 
             if (seg_idx < NUM_DIGITS) digit_sel_next[seg_idx] = 1'b0;
        end else begin
             // Active High pre NPN tranzistory
             digit_sel_next = {NUM_DIGITS{1'b0}};
             if (seg_idx < NUM_DIGITS) digit_sel_next[seg_idx] = 1'b1;
        end

        // Segment data
        if (seg_idx < NUM_DIGITS) begin
            segment_sel_next = seg_decoder(digits_i[seg_idx], dots_i[seg_idx]);
        end else begin
            segment_sel_next = (COMMON_ANODE) ? 8'hFF : 8'h00; // Vypnuté segmenty
        end
    end

    // -------------------------------------------------------------------------
    // 6. Výstupné Registre (Sequential)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Reset do bezpečného stavu (všetko vypnuté)
            digit_sel_o   <= (COMMON_ANODE) ? {NUM_DIGITS{1'b1}} : {NUM_DIGITS{1'b0}};
            segment_sel_o <= (COMMON_ANODE) ? 8'hFF : 8'h00;
        end else begin
            digit_sel_o   <= digit_sel_next;
            segment_sel_o <= segment_sel_next;
        end
    end

endmodule

`endif // SEVEN_SEG_HEX_MUX_SV

`default_nettype wire
