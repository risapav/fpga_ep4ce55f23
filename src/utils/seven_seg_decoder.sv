
(* default_nettype = "none" *)

// seven_seg_decoder.sv - SystemVerilog verzia
// Prevodník hex čísla (4-bit) na 7-segmentový displej (8-bit, vrátane bodky).
// Určené pre spoločnú anódu (0 = svieti).
module seven_seg_decoder (
    input  logic [3:0] hex_i,   // 4-bit vstup (hex číslo)
    output logic [7:0] seg_o    // 8-bit výstup na segmenty
);

    // Kombinačná logika pre dekódovanie čísla na segmenty
    always_comb begin
        unique case (hex_i)
            4'h0: seg_o = 8'b11000000; // 0
            4'h1: seg_o = 8'b11111001; // 1
            4'h2: seg_o = 8'b10100100; // 2
            4'h3: seg_o = 8'b10110000; // 3
            4'h4: seg_o = 8'b10011001; // 4
            4'h5: seg_o = 8'b10010010; // 5
            4'h6: seg_o = 8'b10000010; // 6
            4'h7: seg_o = 8'b11111000; // 7
            4'h8: seg_o = 8'b10000000; // 8
            4'h9: seg_o = 8'b10010000; // 9
            4'hA: seg_o = 8'b10001000; // A
            4'hB: seg_o = 8'b10000011; // b
            4'hC: seg_o = 8'b11000110; // C
            4'hD: seg_o = 8'b10100001; // d
            4'hE: seg_o = 8'b10000110; // E
            4'hF: seg_o = 8'b10001110; // F
            default: seg_o = 8'b11111111; // všetko vypnuté
        endcase
    end

endmodule

