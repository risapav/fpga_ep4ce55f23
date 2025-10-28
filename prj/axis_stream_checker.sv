// ============================================================================
// Modul: axis_stream_checker
// Účel: Overenie korektnosti AXI-Stream video signálov (TUSER, TLAST)
// Verzia: 1.8 (Robustná verzia s vylepšenou detekciou chýb a diagnostikou)
// Dátum: 28. október 2025
// Autor: [Tvoj projekt]
//
// Zmeny v1.8 (na základe expertnej analýzy v1.7):
// - VYLEPŠENIE (Reset): 'clear_errors_i' teraz resetuje aj 'errors_next' (kombinačne)
//   pre 100% deterministický reset.
// - VYLEPŠENIE (Diagnostika): Pridaný výstup 'frame_valid_o' (detekuje prvý frame).
//
// Zmeny v1.7:
// - VYLEPŠENIE (Diagnostika): Počítadlo 'frame_cnt' sa teraz resetuje
//   aj signálom 'clear_errors_i'.
// - VYLEPŠENIE (Robustnosť): 'error_map_t' rozšírená o budúce chyby.
// - VYLEPŠENIE (Simulácia): Pridaný parameter 'C_STRICT_MODE' na prepínanie
//   medzi $error a $warning.
// - VYLEPŠENIE (Syntéza): 'ifdef SIMULATION' nahradený za 'ifndef SYNTHESIS'.
// ============================================================================

`ifndef AXIS_STREAM_CHECKER_SV
`define AXIS_STREAM_CHECKER_SV
`default_nettype none

// Import rozhrania (ak je v samostatnom súbore, inak nie je potrebný)
// import axi_pkg::*; // Potrebné, ak axi_interfaces.sv nie je zahrnutý

module axis_stream_checker #(
    parameter int FRAME_WIDTH  = 800,
    parameter int FRAME_HEIGHT = 600,
    parameter bit C_ENABLE_CHECKS = 1,  // umožňuje vypnutie pre produkčné buildy
    parameter bit C_ENABLE_ASSERTS = 1, // umožňuje vypnutie $error/$warning v simulácii
    parameter bit C_STRICT_MODE = 1     // 1 = $error (zastaví simuláciu), 0 = $warning
)(
    input  logic clk_i,
    input  logic rst_ni,

    // AXI4-Stream vstup, ktorý chceme kontrolovať
    axi4s_if.slave s_axis, // Používa AXI4-Stream rozhranie

    // Nový vstup pre soft reset chýb
    input  logic clear_errors_i,

    // Výstupné príznaky chýb
    output logic        error_any,
    output logic [7:0]  error_flags,
    // Nové výstupy pre súradnice prvej chyby
    output logic [$clog2(FRAME_WIDTH)-1:0]  error_x_o,
    output logic [$clog2(FRAME_HEIGHT)-1:0] error_y_o,
    // Nové výstupy pre počítadlo snímok
    output logic [31:0] frame_cnt_o,
    output logic [31:0] error_frame_o,
    // NOVÝ VÝSTUP (v1.8)
    output logic        frame_valid_o  // 1, ak bol prijatý aspoň jeden frame
);

    // VYLEPŠENIE (Čitateľnosť): Mapa chybových bitov
    typedef enum logic [7:0] {
        ERR_NONE                 = 8'h00,
        ERR_TUSER_POS_BIT        = 8'h01, // TUSER prišiel na zlej pozícii (nie 0,0)
        ERR_TLAST_POS_BIT        = 8'h02, // TLAST prišiel pred koncom riadku
        ERR_TLAST_MISS_BIT       = 8'h04, // TLAST chýbal na konci riadku
        ERR_TUSER_MISS_BIT       = 8'h08, // TUSER chýbal na pozícii (0,0)
        ERR_FRAME_END_NO_SOF_BIT = 8'h10, // Koniec snímku bez TUSER
        // --- Rozšírenie pre budúce použitie ---
        ERR_FRAME_LEN_MISMATCH_BIT = 8'h20, // Rezervované
        ERR_DATA_GAP_BIT         = 8'h40, // Rezervované
        ERR_UNKNOWN_BIT          = 8'h80  // Rezervované
    } error_map_t;

    // Lokálne registre
    logic [$clog2(FRAME_WIDTH)-1:0]  x_cnt = '0;
    logic [$clog2(FRAME_HEIGHT)-1:0] y_cnt = '0;
    logic [7:0]                      errors;
    logic [7:0]                      errors_next = '0;

    // Registre pre uloženie súradníc prvej chyby
    logic [$clog2(FRAME_WIDTH)-1:0]  error_x;
    logic [$clog2(FRAME_HEIGHT)-1:0] error_y;
    // Registre pre počítanie snímok
    logic [31:0]                     frame_cnt;
    logic [31:0]                     error_frame;

generate if (C_ENABLE_CHECKS) begin : gen_axi_checker

    // Lokálne priradenie signálov z AXI rozhrania
    logic s_tvalid;
    logic s_tready;
    logic s_tuser_sof;
    logic s_tlast;

    assign s_tvalid    = s_axis.TVALID;
    assign s_tready    = s_axis.TREADY;
    assign s_tlast     = s_axis.TLAST;

    // VYLEPŠENIE (Robustnosť): Ochrana pre TUSER_WIDTH = 0
    localparam int TUSER_W = s_axis.USER_WIDTH;
    generate
        if (TUSER_W > 0) begin : gen_tuser_check
            assign s_tuser_sof = s_axis.TUSER[0];
        end else begin : gen_tuser_check
            assign s_tuser_sof = 1'b0; // Ak TUSER neexistuje, nikdy nie je SOF
        end
    endgenerate

    // Sekvenčná logika pre počítadlá, chyby a súradnice
    always_ff @(posedge clk_i or negedge rst_ni) begin // Použitý asynchrónny reset
        if (!rst_ni) begin
            x_cnt       <= '0;
            y_cnt       <= '0;
            errors      <= '0;
            error_x     <= '0;
            error_y     <= '0;
            frame_cnt   <= '0;
            error_frame <= '0;
        end
        else begin
            // Soft reset
            if (clear_errors_i) begin
                errors      <= '0;
                error_x     <= '0;
                error_y     <= '0;
                error_frame <= '0;
                frame_cnt   <= '0; // Resetujeme aj počítadlo snímok
            end
            // Zaznamenanie súradníc prvej chyby
            else if (|errors_next & ~|errors) begin
                error_x <= x_cnt;
                error_y <= y_cnt;
                error_frame <= frame_cnt; // Zachytenie čísla snímky
                errors  <= errors_next;
            end else begin
                errors <= errors_next;
            end

            // Logika posunu počítadiel (len pri platnom prenose)
            if (s_tvalid && s_tready) begin
                if (s_tuser_sof) begin
                    x_cnt <= '0;
                    y_cnt <= '0;
                    frame_cnt <= frame_cnt + 1'b1; // Inkrementácia počítadla snímok
                end
                else if (s_tlast) begin
                    x_cnt <= '0;
                    if (y_cnt == FRAME_HEIGHT - 1)
                        y_cnt <= '0;
                    else
                        y_cnt <= y_cnt + 1'b1;
                end
                else if (x_cnt < FRAME_WIDTH - 1) begin
                    x_cnt <= x_cnt + 1'b1;
                end
            end
        end
    end

    // Kombinačná logika pre výpočet chýb (pre nasledujúci takt)
    always_comb begin
        logic [7:0] new_err;
        new_err = 8'h00;

        // Kontrolujeme nové chyby len pri platnom prenose
        if (s_tvalid && s_tready) begin

            if (s_tuser_sof) begin
                if (x_cnt != 0 || y_cnt != 0)
                    new_err[ERR_TUSER_POS_BIT] = 1'b1;
            end
            else begin
                if (x_cnt == 0 && y_cnt == 0)
                    new_err[ERR_TUSER_MISS_BIT] = 1'b1;
            end

            if (s_tlast) begin
                if (x_cnt != FRAME_WIDTH - 1)
                    new_err[ERR_TLAST_POS_BIT] = 1'b1;

                if (y_cnt == FRAME_HEIGHT - 1 && !s_tuser_sof)
                    new_err[ERR_FRAME_END_NO_SOF_BIT] = 1'b1;
            end
            else begin
                if (x_cnt == FRAME_WIDTH - 1)
                    new_err[ERR_TLAST_MISS_BIT] = 1'b1;
            end
        end

        // Logika resetu a akumulácie chýb
        // OPRAVA (v1.8): clear_errors_i teraz nuluje aj errors_next
        if (clear_errors_i) begin
            errors_next = 8'h00;
        end
        else if (s_tvalid && s_tready && s_tuser_sof && (x_cnt == 0 && y_cnt == 0)) begin
            errors_next = new_err; // Reset a zaznamenanie prípadnej TUSER_POS chyby
        end
        else begin
            errors_next = errors | new_err; // Akumulácia chýb
        end
    end

    // Simulačné aserty
    `ifndef SYNTHESIS
    always_ff @(posedge clk_i) begin
        if (rst_ni && (s_tvalid && s_tready) && C_ENABLE_ASSERTS) begin
            if (errors_next != errors && |errors_next) begin
                if (C_STRICT_MODE)
                    $error("[%0t] AXIS_STREAM_CHECKER: Nová chyba detekovaná! Flags: %b (Predchádzajúce: %b) na (x=%0d, y=%0d, frame=%0d)",
                           $time, errors_next, errors, x_cnt, y_cnt, frame_cnt);
                else
                    $warning("[%0t] AXIS_STREAM_CHECKER: Nová chyba detekovaná! Flags: %b (Predchádzajúce: %b) na (x=%0d, y=%0d, frame=%0d)",
                             $time, errors_next, errors, x_cnt, y_cnt, frame_cnt);
            end
        end
    end
    `endif // `ifndef SYNTHESIS

end else begin : gen_axi_checker_disabled
    // Ak sú kontroly vypnuté, priradíme nuly
    always_comb begin
        errors      = '0;
        errors_next = '0;
        x_cnt       = '0;
        y_cnt       = '0;
        error_x     = '0;
        error_y     = '0;
        frame_cnt   = '0;
        error_frame = '0;
    end
end endgenerate

// Priradenie výstupov
assign error_any     = |errors;
assign error_flags   = errors;
assign error_x_o     = error_x;
assign error_y_o     = error_y;
assign frame_cnt_o   = frame_cnt;
assign error_frame_o = error_frame;
assign frame_valid_o = (frame_cnt != 0); // NOVÝ VÝSTUP (v1.8)

endmodule

`default_nettype wire
`endif // AXIS_STREAM_CHECKER_SV

