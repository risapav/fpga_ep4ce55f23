`ifndef PIXEL_XY
`define PIXEL_XY

`timescale 1ns/1ns
`default_nettype none

//================================================================
// Modul: PixelCoordinates
// Popis: Generuje súradnice X a Y pre kompletný VGA rámec
//        (vrátane zatemňovacích intervalov - blanking).
//================================================================
module PixelCoordinates #(
    parameter int TIMING_WIDTH = 12,
    // Parametre pre šírku výstupných súradníc
    parameter int X_WIDTH = TIMING_WIDTH,
    parameter int Y_WIDTH = TIMING_WIDTH
)(
    input  logic clk_i,        // Vstupný hodinový signál (pixel clock)
    input  logic rst_ni,       // Synchrónny reset, aktívny v L
    input  logic enable_i,     // Povolenie inkrementácie počítadiel
    input  logic eol_i,        // Vstupný pulz konca riadku (End of Line)
    input  logic eof_i,        // Vstupný pulz konca snímky (End of Frame)

    output logic [X_WIDTH-1:0] x_o, // Výstupná súradnica X
    output logic [Y_WIDTH-1:0] y_o  // Výstupná súradnica Y
);

    //================================================================
    // ==                     Logika Počítadiel                      ==
    // Jeden `always_ff` blok pre oba počítadlá pre lepšiu prehľadnosť.
    //================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            x_o <= '0;
            y_o <= '0;
        end else if (enable_i) begin

            // --- Logika pre X súradnicu ---
            // Počítadlo X sa resetuje na konci každého riadku.
            if (eol_i) begin
                x_o <= '0;
            end else begin
                x_o <= x_o + X_WIDTH'(1);
            end

            // --- Logika pre Y súradnicu ---
            // Počítadlo Y sa inkrementuje iba na konci riadku
            // a resetuje sa na konci celej snímky.
            if (eof_i) begin
                y_o <= '0;
            end else if (eol_i) begin
                y_o <= y_o + Y_WIDTH'(1);
            end

        end
    end

endmodule

`endif // PIXEL_XY