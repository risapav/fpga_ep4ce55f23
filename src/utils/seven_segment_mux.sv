/**
 * @file        seven_segment_mux.sv
 * @brief       Multiplexovaný ovládač 7-segmentového displeja (BCD).
 * @details     Zobrazuje číslice 0-9. Pre HEX (0-F) použite seven_seg_hex_mux.
 * Podporuje Common Anode aj Common Cathode.
 * Výstupy sú registrované pre bezpečné pripojenie na FPGA piny.
 *
 * @param NUM_DIGITS            Počet číslic.
 * @param CLK_FREQ_HZ           Frekvencia hodín (Hz).
 * @param DIGIT_REFRESH_RATE_HZ Obnovovacia frekvencia celého displeja (Hz).
 *
 * @input  clk_i           Hodiny.
 * @input  rst_ni          Asynchrónny reset (active-low).
 * @input  digits_i        Pole BCD hodnôt (packed array [N][3:0]).
 * @input  dp_i            Desatinné bodky.
 * @input  common_anode_i  1 = Common Anode (Active Low), 0 = Common Cathode.
 * @output segments_o      Segmenty (a-g).
 * @output dp_o            Desatinná bodka výstup.
 * @output digit_en_o      Povolenie digitu.
 */

`default_nettype none

`ifndef SEVEN_SEGMENT_MUX_SV
`define SEVEN_SEGMENT_MUX_SV

module seven_segment_mux #(
    parameter int NUM_DIGITS            = 4,
    parameter int CLK_FREQ_HZ           = 100_000_000,
    parameter int DIGIT_REFRESH_RATE_HZ = 200
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,

    // Vstupy dát (Packed array pre jednoduchšie priradenie)
    input  logic [NUM_DIGITS-1:0][3:0]   digits_i,
    input  logic [NUM_DIGITS-1:0]        dp_i,
    input  logic                         common_anode_i,

    // Výstupy (Registrované)
    output logic [6:0]                   segments_o,
    output logic                         dp_o,
    output logic [NUM_DIGITS-1:0]        digit_en_o
);

    // -------------------------------------------------------------------------
    // 1. Výpočty časovania
    // -------------------------------------------------------------------------
    localparam int RefreshPeriodCycles = CLK_FREQ_HZ / (DIGIT_REFRESH_RATE_HZ * NUM_DIGITS);
    localparam int RefreshCounterWidth = $clog2(RefreshPeriodCycles + 1);
    localparam int DigitIdxWidth       = (NUM_DIGITS == 1) ? 1 : $clog2(NUM_DIGITS);

    // -------------------------------------------------------------------------
    // 2. Interné registre
    // -------------------------------------------------------------------------
    logic [RefreshCounterWidth-1:0] refresh_counter_q;
    logic [DigitIdxWidth-1:0]       digit_idx_q;
    
    // Signály pre výstupné registre (Next State)
    logic [6:0]                     segments_next;
    logic                           dp_next;
    logic [NUM_DIGITS-1:0]          digit_en_next;

    // -------------------------------------------------------------------------
    // 3. Časovač obnovovania (Refresh Timer)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            refresh_counter_q <= '0;
            digit_idx_q       <= '0;
        end else begin
            if (refresh_counter_q == RefreshPeriodCycles - 1) begin
                refresh_counter_q <= '0;
                // Cyklický posun indexu digitu
                if (digit_idx_q == NUM_DIGITS - 1)
                    digit_idx_q <= '0;
                else
                    digit_idx_q <= digit_idx_q + 1'b1;
            end else begin
                refresh_counter_q <= refresh_counter_q + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Kombinačný dekodér segmentov
    // -------------------------------------------------------------------------
    logic [3:0] current_digit_val;
    logic       current_dp_val;
    logic [6:0] segments_decoded_cc; // Common Cathode (Active High)

    assign current_digit_val = digits_i[digit_idx_q];
    assign current_dp_val    = dp_i[digit_idx_q];

    always_comb begin
        // Dekódovanie pre Common Cathode (1 = Svieti)
        // Mapovanie: {g, f, e, d, c, b, a}
        case (current_digit_val)
            4'h0: segments_decoded_cc = 7'b0111111;
            4'h1: segments_decoded_cc = 7'b0000110;
            4'h2: segments_decoded_cc = 7'b1011011;
            4'h3: segments_decoded_cc = 7'b1001111;
            4'h4: segments_decoded_cc = 7'b1100110;
            4'h5: segments_decoded_cc = 7'b1101101;
            4'h6: segments_decoded_cc = 7'b1111101;
            4'h7: segments_decoded_cc = 7'b0000111;
            4'h8: segments_decoded_cc = 7'b1111111;
            4'h9: segments_decoded_cc = 7'b1101111;
            default: segments_decoded_cc = 7'b0000000; // Blank pre neplatné BCD
        endcase
    end

    // -------------------------------------------------------------------------
    // 5. Logika výstupov (Polarita a Multiplex)
    // -------------------------------------------------------------------------
    always_comb begin
        // Segmenty
        if (common_anode_i) begin
            // Common Anode: 0 = ON (invertujeme CC logiku)
            segments_next = ~segments_decoded_cc;
            dp_next       = ~current_dp_val;
        end else begin
            // Common Cathode: 1 = ON
            segments_next = segments_decoded_cc;
            dp_next       = current_dp_val;
        end

        // Digit Enable
        if (common_anode_i) begin
            // Common Anode (PNP tranzistor): Active Low
            digit_en_next = ~(1'b1 << digit_idx_q);
        end else begin
            // Common Cathode (NPN tranzistor): Active High
            digit_en_next = (1'b1 << digit_idx_q);
        end
    end

    // -------------------------------------------------------------------------
    // 6. Výstupné registre
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Reset do bezpečného stavu (všetko vypnuté)
            // Ak CA: 1=OFF. Ak CC: 0=OFF.
            segments_o <= common_anode_i ? '1 : '0;
            dp_o       <= common_anode_i ? 1'b1 : 1'b0;
            digit_en_o <= common_anode_i ? '1 : '0; 
        end else begin
            segments_o <= segments_next;
            dp_o       <= dp_next;
            digit_en_o <= digit_en_next;
        end
    end

endmodule

`endif // SEVEN_SEGMENT_MUX_SV

`default_nettype wire
