//------------------------------------------------------------------------------
// VgaCtrl.sv - VGA Controller s generovaním aktívnej zóny a RGB signálu
// Verzia: refaktorovaná, bez current_state, s aktívnym signálom a RGB logikou
//------------------------------------------------------------------------------
// Popis:
// - Synchronný reset (rstn)
// - Využíva dva riadiace moduly pre horizontálne a vertikálne časovanie (h_line_ctrl, v_line_ctrl)
// - Výstup `active` je logická AND z vnútorných stavov oboch časovaní (ACTIVE)
// - Výstup `vga` generuje žltú farbu mimo aktívnej oblasti a modrú v aktívnej
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
import vga_pkg::*;

module VgaCtrl #(
    parameter VGA_mode_e RESOLUTION = VGA_640x480_60
)(
    input  logic       clk,
    input  logic       rstn,
    output logic       hsync,
    output logic       vsync,
    output logic       active,    // aktívna oblasť (true, ak h aj v aktívne)
    output logic [15:0] vga       // RGB565 výstup farby (16 bitov)
);

    //--------------------------------------------------------------------------
    // Interné signály pre časovanie
    //--------------------------------------------------------------------------
    line_t h_line, v_line;

    // Vnútorné stavy FSM pre horizontálne a vertikálne časovanie
    VGA_state_e h_state, v_state;

    // Inicializuj časovanie podľa zvoleného režimu
    initial begin
        get_vga_timing(RESOLUTION, h_line, v_line);
    end

    //--------------------------------------------------------------------------
    // Inštancie riadiacich blokov pre časovanie horizontálne a vertikálne
    // (predpokladám, že máš definované moduly, ktoré generujú hsync, vsync a stav)
    //--------------------------------------------------------------------------

    Line #(.LINE_WIDTH(LINE_WIDTH)) h_line_ctrl (
        .clk(clk), .rstn(rstn),
        .visible_area(h_line.visible_area),
        .front_porch(h_line.front_porch),
        .sync_pulse(h_line.sync_pulse),
        .back_porch(h_line.back_porch),
        .polarity(h_line.polarity),
        .sync(hsync),
        .state(h_state)
    );

    Line #(.LINE_WIDTH(LINE_WIDTH)) v_line_ctrl (
        .clk(clk), .rstn(rstn),
        .visible_area(v_line.visible_area),
        .front_porch(v_line.front_porch),
        .sync_pulse(v_line.sync_pulse),
        .back_porch(v_line.back_porch),
        .polarity(v_line.polarity),
        .sync(vsync),
        .state(v_state)
    );


    //--------------------------------------------------------------------------
    // Generovanie aktívnej oblasti: true iba ak obidva stavy sú ACTIVE
    //--------------------------------------------------------------------------
	always_comb begin
		 active = (h_state == ACTIVE) && (v_state == ACTIVE);
	end


    //--------------------------------------------------------------------------
    // Generovanie RGB signálu
    // - modrá farba v aktívnej oblasti
    // - žltá mimo aktívnej oblasti
    // RGB565 formát: R[4:0], G[5:0], B[4:0]
    //--------------------------------------------------------------------------

    always_comb begin
        if (active) begin
            // Modrá: R=0, G=0, B=max (31)
            vga = 16'h001F; // 00000 000000 11111
        end else begin
            // Žltá: R=max (31), G=max (63), B=0
            vga = 16'hFFE0; // 11111 111111 00000
        end
    end

endmodule
