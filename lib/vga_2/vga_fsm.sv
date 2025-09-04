// vga_fsm.sv - Univerzálny stavový automat pre jednu VGA dimenziu
//
// Popis:
// Tento modul implementuje robustný stavový automat (FSM), ktorý prechádza
// štyrmi fázami VGA signálu (SYNC, BACKPORCH, ACTIVE, FRONTPORCH).
// Je plne konfigurovateľný pomocou vstupnej štruktúry `line_t` a je navrhnutý
// pre znovupoužitie pre horizontálnu aj vertikálnu os.

`ifndef VGA_FSM_DONE
`define VGA_FSM_DONE

`default_nettype none

import vga_pkg::*;

module vga_fsm #(
    parameter WIDTH = 12 // Šírka počítadla pozície
)(
    input  logic             clk,
    input  logic             rstn,
    input  logic [WIDTH-1:0] pos,     // Aktuálna pozícia (počet pixelov alebo riadkov)
    input  line_t            line,    // Časovacie parametre pre danú dimenziu
    output fsm_output_t      out,     // Výstupné signály (sync, active, blank)
    output VGA_state_e       state    // Aktuálny stav (pre diagnostiku)
);

    VGA_state_e state_s, state_n;

    // --- Výpočet koncových bodov pre jednotlivé fázy VGA signálu ---
    logic [WIDTH-1:0] sync_end, backporch_end, active_end, frontporch_end;

    always_comb begin
        sync_end       = line.sync_pulse - 1;
        backporch_end  = sync_end + line.back_porch;
        active_end     = backporch_end + line.visible_area;
        frontporch_end = active_end + line.front_porch;
    end

    // --- Stavový register (sekvenčná časť FSM) ---
    always_ff @(posedge clk) begin
        if (!rstn) state_s <= SYNC;
        else       state_s <= state_n;
    end
    assign state = state_s;

    // --- Prechodová logika (kombinačná časť FSM) ---
    // Používa sa `>=` namiesto `==` pre robustnosť voči preskočeniu stavu.
    always_comb begin
        state_n = state_s;
        case (state_s)
            SYNC:       if (pos >= sync_end)       state_n = BACKPORCH;
            BACKPORCH:  if (pos >= backporch_end)  state_n = ACTIVE;
            ACTIVE:     if (pos >= active_end)     state_n = FRONTPORCH;
            FRONTPORCH: if (pos >= frontporch_end) state_n = SYNC;
            default:    state_n = SYNC;
        endcase
    end

    // --- Výstupná logika (kombinačná časť FSM, Mealyho automat) ---
    always_comb begin
        unique case (state_s)
            SYNC:       out = '{sync: 1, active: 0, blank: 1};
            BACKPORCH:  out = '{sync: 0, active: 0, blank: 1};
            ACTIVE:     out = '{sync: 0, active: 1, blank: 0};
            FRONTPORCH: out = '{sync: 0, active: 0, blank: 1};
            default:    out = '{sync: 1, active: 0, blank: 1}; // Bezpečný predvolený stav
        endcase
    end

endmodule

`endif // VGA_FSM_DONE
