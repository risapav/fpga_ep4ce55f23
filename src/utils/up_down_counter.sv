/**
 * @file        up_down_counter.sv
 * @brief       8-bitový synchrónny reverzibilný (up/down) čítač.
 * @details     Tento modul implementuje synchrónny čítač s povolením (enable),
 * asynchrónnym resetom a voľbou smeru čítania.
 * - Ak je 'rst_ni' aktívny (log. 0), výstup 'count_o' je asynchrónne vynulovaný.
 * - Ak je 'en_i' neaktívny (log. 0), čítač si drží svoju hodnotu.
 * - Vstup 'up_down_i' určuje smer: 1 = hore (inc), 0 = dole (dec).
 *
 * @param WIDTH Šírka čítača v bitoch.
 *
 * @input  clk_i      Hodinový signál.
 * @input  rst_ni     Asynchrónny reset (active-low).
 * @input  en_i       Povolenie čítania.
 * @input  up_down_i  Smer čítania (1=Up, 0=Down).
 * @output count_o    Hodnota čítača.
 */

`default_nettype none

`ifndef UP_DOWN_COUNTER_SV
`define UP_DOWN_COUNTER_SV

module up_down_counter #(
    parameter int WIDTH = 8
) (
    // Clock and Reset
    input  wire logic             clk_i,
    input  wire logic             rst_ni,

    // Control inputs
    input  wire logic             en_i,
    input  wire logic             up_down_i,

    // Data output
    output      logic [WIDTH-1:0] count_o
);

    // Synchronous logic for the counter with asynchronous active-low reset.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Asynchronous reset to zero
            count_o <= '0;
        end else begin
            // Synchronous logic on positive clock edge
            if (en_i) begin
                if (up_down_i) begin
                    // Count up
                    count_o <= count_o + 1'b1;
                end else begin
                    // Count down
                    count_o <= count_o - 1'b1;
                end
            end
            // If enable is low, the value of count_o is preserved implicitly.
        end
    end

endmodule

`endif // UP_DOWN_COUNTER_SV

`default_nettype wire
