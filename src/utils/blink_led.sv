/**
 * @file        blink_led.sv
 * @brief       Jednoduchý modul na blikanie LED s nastaviteľnou frekvenciou.
 * @details     Modul generuje signál pre LED, ktorá bliká so zadanou frekvenciou.
 * Počet taktov na jednu polperiódu sa vypočíta z parametrov.
 *
 * @param CLOCK_FREQ_HZ Frekvencia vstupného hodinového signálu v Hz.
 * @param BLINK_HZ      Požadovaná frekvencia blikania LED v Hz.
 *
 * @input  clk_i        Vstupný hodinový signál.
 * @input  rst_ni       Asynchrónny reset (aktívny v nule).
 * @output led_o        Výstupný signál pre LED (blikajúci).
 */

`default_nettype none

`ifndef BLINK_LED_SV
`define BLINK_LED_SV

module blink_led #(
    parameter int CLOCK_FREQ_HZ = 50_000_000,
    parameter int BLINK_HZ      = 1
)(
    input  logic clk_i,
    input  logic rst_ni,
    output led_o
);

    // Výpočet deličky: počet taktov pre jednu polperiódu (toggle time)
    // (F_clk / F_blink) / 2
    localparam int BlinkDivider = (CLOCK_FREQ_HZ == 0) ? 1 : CLOCK_FREQ_HZ / (2 * BLINK_HZ);
    localparam int CounterWidth = $clog2(BlinkDivider);
    
    logic [CounterWidth-1:0] counter;

    // Sekvenčná logika s asynchrónnym resetom
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            counter <= '0;
            led_o   <= 1'b0;
        end else begin
            if (counter == BlinkDivider - 1) begin
                counter <= '0;
                led_o   <= ~led_o;
            end else begin
                counter <= counter + CounterWidth'(1);
            end
        end
    end

endmodule

`endif // BLINK_LED_SV

`default_nettype wire
