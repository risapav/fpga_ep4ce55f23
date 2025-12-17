/**
 * @file        vga_timing_generator.sv
 * @brief       Generátor časovania pre VGA (HSync, VSync, Blanking).
 * @details     Generuje synchronizačné signály a súradnice pixelov na základe
 * parametrov časovania. Podporuje nastaviteľnú polaritu.
 *
 * @param H_VISIBLE     Viditeľná šírka (pixely).
 * @param H_FRONT_PORCH Predná veranda (H).
 * @param H_SYNC_PULSE  Sync pulz (H).
 * @param H_BACK_PORCH  Zadná veranda (H).
 * @param H_POLARITY    Polarita HSync (1 = Active High).
 * @param COORD_WIDTH   Šírka výstupných súradníc (default 12 pre podporu do 4095).
 */

`default_nettype none

`ifndef VGA_TIMING_GENERATOR_SV
`define VGA_TIMING_GENERATOR_SV

import vga_pkg::*; // Predpokladá existenciu vga_sync_t

module vga_timing_generator #(
    // --- Horizontálne časovanie (800x600 default) ---
    parameter int H_VISIBLE     = 800,
    parameter int H_FRONT_PORCH = 40,
    parameter int H_SYNC_PULSE  = 128,
    parameter int H_BACK_PORCH  = 88,
    parameter bit H_POLARITY    = 1'b1,

    // --- Vertikálne časovanie (800x600 default) ---
    parameter int V_VISIBLE     = 600,
    parameter int V_FRONT_PORCH = 1,
    parameter int V_SYNC_PULSE  = 4,
    parameter int V_BACK_PORCH  = 23,
    parameter bit V_POLARITY    = 1'b1,
    
    // --- Šírka súradníc ---
    // 10 bitov nestačí pre 1280 alebo 1920. 12 bitov stačí do 4095.
    parameter int COORD_WIDTH   = 12
)(
    input  logic clk_i,
    input  logic rst_ni,

    output vga_sync_t                sync_o, // Struct z vga_pkg
    output logic                     hde_o,  // Horizontal Data Enable
    output logic                     vde_o,  // Vertical Data Enable
    output logic [COORD_WIDTH-1:0]   x_o,    // Súradnica X
    output logic [COORD_WIDTH-1:0]   y_o     // Súradnica Y
);

    // ---------------------------------------------------------------------
    // 1. Výpočet limitov (Localparams)
    // ---------------------------------------------------------------------
    localparam int H_TOTAL = H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam int V_TOTAL = V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    // Automatický výpočet potrebnej šírky čítačov
    localparam int H_WIDTH = ($clog2(H_TOTAL) > 0) ? $clog2(H_TOTAL) : 1;
    localparam int V_WIDTH = ($clog2(V_TOTAL) > 0) ? $clog2(V_TOTAL) : 1;

    // ---------------------------------------------------------------------
    // 2. Interné čítače
    // ---------------------------------------------------------------------
    logic [H_WIDTH-1:0] h_count;
    logic [V_WIDTH-1:0] v_count;

    // ---------------------------------------------------------------------
    // 3. Sekvenčná logika (Čítače)
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
                    v_count <= v_count + 1'b1;
                end
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------------
    // 4. Kombinačná logika (Výstupy)
    // ---------------------------------------------------------------------
    
    // Mapovanie čítačov na výstupy (s pretypovaním šírky)
    assign x_o = COORD_WIDTH'(h_count);
    assign y_o = COORD_WIDTH'(v_count);

    // Data Enable (Aktívna oblasť)
    assign hde_o = (h_count < H_VISIBLE);
    assign vde_o = (v_count < V_VISIBLE);

    // Generovanie Sync pulzov (Unpolarized)
    logic h_sync_active_unpol;
    logic v_sync_active_unpol;

    assign h_sync_active_unpol =
        (h_count >= (H_VISIBLE + H_FRONT_PORCH)) &&
        (h_count <  (H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE));

    assign v_sync_active_unpol =
        (v_count >= (V_VISIBLE + V_FRONT_PORCH)) &&
        (v_count <  (V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE));

    // Aplikácia polarity (Ternárny operátor pre runtime alebo compile-time)
    assign sync_o.hs = (H_POLARITY) ? h_sync_active_unpol : ~h_sync_active_unpol;
    assign sync_o.vs = (V_POLARITY) ? v_sync_active_unpol : ~v_sync_active_unpol;

endmodule

`endif // VGA_TIMING_GENERATOR_SV

`default_nettype wire
