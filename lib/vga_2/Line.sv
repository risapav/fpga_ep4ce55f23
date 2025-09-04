//------------------------------------------------------------------------------
// Line.sv - Časovač pre jeden riadok (horizontálny alebo vertikálny)
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
import vga_pkg::*;

module Line #(
    parameter int LINE_WIDTH = 12
)(
    input  logic                 clk,
    input  logic                 rstn,

    // --- Parametre časovania liniek (napr. z h_line alebo v_line) ---
    input  logic [LINE_WIDTH-1:0] visible_area,
    input  logic [LINE_WIDTH-1:0] front_porch,
    input  logic [LINE_WIDTH-1:0] sync_pulse,
    input  logic [LINE_WIDTH-1:0] back_porch,
    input  logic                 polarity,  // 1: aktívny HIGH, 0: aktívny LOW

    // --- Výstupy ---
    output logic                 sync,
    output VGA_state_e          state
);

    //--------------------------------------------------------------------------
    // Lokálne registre a konštanty
    //--------------------------------------------------------------------------

    localparam TOTAL_WIDTH = 14;  // až 14-bitový counter kvôli FullHD

    logic [TOTAL_WIDTH-1:0] counter;
    logic [TOTAL_WIDTH-1:0] total;

    // Výpočet celkovej dĺžky periódy
    always_comb begin
        total = visible_area + front_porch + sync_pulse + back_porch;
    end

    //--------------------------------------------------------------------------
    // Časovanie a stavový automat
    //--------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (!rstn) begin
            counter <= 0;
        end else begin
            if (counter == total - 1)
                counter <= 0;
            else
                counter <= counter + 1;
        end
    end

    // Výpočet aktuálneho stavu podľa countera
    always_comb begin
        if (counter < sync_pulse)
            state = SYNC;
        else if (counter < sync_pulse + back_porch)
            state = BACKPORCH;
        else if (counter < sync_pulse + back_porch + visible_area)
            state = ACTIVE;
        else
            state = FRONTPORCH;
    end

    // Výpočet výstupu sync signálu na základe polarity a aktuálneho stavu
    always_comb begin
        if (state == SYNC)
            sync = polarity;  // aktívny podľa polarity
        else
            sync = ~polarity;
    end

endmodule
