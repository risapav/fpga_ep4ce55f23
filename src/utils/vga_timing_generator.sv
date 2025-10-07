// vga_timing_generator.sv - Verzia 1.4 - Kompatibilita pre Quartus
(* default_nettype = "none" *)
import vga_pkg::*; // predpokladá, že line_t/vga_sync_t definície sú v balíčku

module vga_timing_generator #(
    // --- Horizontálne časovanie (800x600 default)
    parameter int H_VISIBLE   = 800,
    parameter int H_FRONT_PORCH = 40,
    parameter int H_SYNC_PULSE  = 128,
    parameter int H_BACK_PORCH  = 88,
    parameter bit H_POLARITY    = 1'b1,

    // --- Vertikálne časovanie (800x600 default)
    parameter int V_VISIBLE   = 600,
    parameter int V_FRONT_PORCH = 1,
    parameter int V_SYNC_PULSE  = 4,
    parameter int V_BACK_PORCH  = 23,
    parameter bit V_POLARITY    = 1'b1
)(
    input  logic clk_i,
    input  logic rst_ni,

    output vga_sync_t sync_o,
    output logic      hde_o,
    output logic      vde_o,
    output logic [9:0] x_o, // vonkajšie šírky 10 bitov: podporuje až 1024
    output logic [9:0] y_o
);

    // ---------------------------------------------------------------------
    // Vypočítané miestne parametre (konštantné pri elaborácii)
    // ---------------------------------------------------------------------
    localparam int H_TOTAL = H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam int V_TOTAL = V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    // šírky čítačov (bezpečne aspoň 1 bit)
    localparam int H_WIDTH = ($clog2(H_TOTAL) > 0) ? $clog2(H_TOTAL) : 1;
    localparam int V_WIDTH = ($clog2(V_TOTAL) > 0) ? $clog2(V_TOTAL) : 1;

    // vnútorné čítače s odvodzenou šírkou
    logic [H_WIDTH-1:0] h_count;
    logic [V_WIDTH-1:0] v_count;

    // ---------------------------------------------------------------------
    // Sekvenčná logika: horizontálny a vertikálny čítač
    // ---------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            h_count <= '0;
            v_count <= '0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= '0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= '0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    // ---------------------------------------------------------------------
    // Výstupy - mapovanie čítačov na vonkajšie signály
    // ---------------------------------------------------------------------
    // x_o/y_o sú deklarované ako 10-bitové výstupy: obmedzujú maximálnu hodnotu,
    // ak potrebuješ väčšie rozlíšenie, zväčši šírku výstupov.
    assign x_o = h_count;
    assign y_o = v_count;

    assign hde_o = (h_count < H_VISIBLE);
    assign vde_o = (v_count < V_VISIBLE);

    // HSYNC: generujeme aktívny pulz podľa polarity
    // Ak je polarity == 1 => aktívne vysoko, inak aktívne nízko
    logic h_sync_active_unpol;
    logic v_sync_active_unpol;

    assign h_sync_active_unpol =
        (h_count >= (H_VISIBLE + H_FRONT_PORCH)) &&
        (h_count <  (H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE));

    assign v_sync_active_unpol =
        (v_count >= (V_VISIBLE + V_FRONT_PORCH)) &&
        (v_count <  (V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE));

    assign sync_o.hs = (H_POLARITY) ? h_sync_active_unpol : ~h_sync_active_unpol;
    assign sync_o.vs = (V_POLARITY) ? v_sync_active_unpol : ~v_sync_active_unpol;

endmodule

`default_nettype wire
