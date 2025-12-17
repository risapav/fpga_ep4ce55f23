/**
 * @file        axis_stream_checker.sv
 * @brief       Checker pre AXI4-Stream protokol (TUSER, TLAST, Frame Dimensions).
 * @details     Overuje integritu video streamu. Detekuje chýbajúci TLAST,
 * nesprávny SOF (TUSER[0]), a nezhodu rozmerov snímky.
 * Obsahuje diagnostické počítadlá a latchovanie prvej chyby.
 *
 * @param FRAME_WIDTH      Očakávaná šírka snímky.
 * @param FRAME_HEIGHT     Očakávaná výška snímky.
 * @param C_ENABLE_CHECKS  Povolenie logiky checkera (0 = optimalizácia pre syntézu).
 * @param C_ENABLE_ASSERTS Povolenie simulačných správ.
 * @param C_STRICT_MODE    1 = $error (Stop), 0 = $warning.
 */

`default_nettype none

`ifndef AXIS_STREAM_CHECKER_SV
`define AXIS_STREAM_CHECKER_SV

module axis_stream_checker #(
    parameter int FRAME_WIDTH      = 800,
    parameter int FRAME_HEIGHT     = 600,
    parameter bit C_ENABLE_CHECKS  = 1,
    parameter bit C_ENABLE_ASSERTS = 1,
    parameter bit C_STRICT_MODE    = 1
)(
    input  wire logic clk_i,
    input  wire logic rst_ni,

    // AXI4-Stream Interface
    axi4s_if.slave    s_axis,

    // Control
    input  wire logic clear_errors_i,

    // Status / Diagnostics
    output logic      error_any,
    output logic [7:0] error_flags,
    output logic [$clog2(FRAME_WIDTH)-1:0]  error_x_o,
    output logic [$clog2(FRAME_HEIGHT)-1:0] error_y_o,
    output logic [31:0] frame_cnt_o,
    output logic [31:0] error_frame_o,
    output logic        frame_valid_o
);

    // -------------------------------------------------------------------------
    // 1. Definície Chýb (Bitmasky)
    // -------------------------------------------------------------------------
    typedef enum logic [7:0] {
        ERR_NONE                 = 8'h00,
        ERR_TUSER_POS_BIT        = 8'h01, // SOF na zlej pozícii (nie 0,0)
        ERR_TLAST_POS_BIT        = 8'h02, // EOL predčasne
        ERR_TLAST_MISS_BIT       = 8'h04, // EOL chýba na konci riadku
        ERR_TUSER_MISS_BIT       = 8'h08, // SOF chýba na začiatku snímky (0,0)
        ERR_FRAME_END_NO_SOF_BIT = 8'h10, // Koniec snímky bez resete (pretečenie Y)
        ERR_RESERVED_20          = 8'h20,
        ERR_RESERVED_40          = 8'h40,
        ERR_UNKNOWN_BIT          = 8'h80
    } error_map_t;

    // -------------------------------------------------------------------------
    // 2. Signály
    // -------------------------------------------------------------------------
    logic [$clog2(FRAME_WIDTH)-1:0]  x_cnt;
    logic [$clog2(FRAME_HEIGHT)-1:0] y_cnt;
    
    // Error Registers
    logic [7:0]                      errors_reg;
    logic [7:0]                      errors_next;
    
    // Capture Registers
    logic [$clog2(FRAME_WIDTH)-1:0]  error_x_reg;
    logic [$clog2(FRAME_HEIGHT)-1:0] error_y_reg;
    logic [31:0]                     frame_cnt_reg;
    logic [31:0]                     error_frame_reg;

    // -------------------------------------------------------------------------
    // 3. Implementácia Checkera
    // -------------------------------------------------------------------------
    generate if (C_ENABLE_CHECKS) begin : gen_axi_checker

        // Dekompozícia AXI signálov
        logic s_tvalid;
        logic s_tready;
        logic s_tlast;
        logic s_tuser_sof;

        assign s_tvalid = s_axis.TVALID;
        assign s_tready = s_axis.TREADY;
        assign s_tlast  = s_axis.TLAST;

        // Bezpečné získanie TUSER (SOF)
        if (s_axis.USER_WIDTH > 0) begin : gen_has_user
            assign s_tuser_sof = s_axis.TUSER[0];
        end else begin : gen_no_user
            assign s_tuser_sof = 1'b0;
        end

        // ---------------------------------------------------------------------
        // Sekvenčná Logika: Počítadlá a Registre
        // ---------------------------------------------------------------------
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                x_cnt           <= '0;
                y_cnt           <= '0;
                errors_reg      <= '0;
                error_x_reg     <= '0;
                error_y_reg     <= '0;
                frame_cnt_reg   <= '0;
                error_frame_reg <= '0;
            end else begin
                // A. Reset Logic (Soft Reset)
                if (clear_errors_i) begin
                    errors_reg      <= '0;
                    error_x_reg     <= '0;
                    error_y_reg     <= '0;
                    error_frame_reg <= '0;
                    // frame_cnt_reg neresetujeme, aby sme videli celkový uptime, 
                    // alebo ho resetujeme podľa požiadavky (v1.8 požiadavka bola resetovať)
                    frame_cnt_reg   <= '0; 
                end 
                // B. Error Capture (Latch first error)
                else if (|errors_next && !(|errors_reg)) begin
                    error_x_reg     <= x_cnt;
                    error_y_reg     <= y_cnt;
                    error_frame_reg <= frame_cnt_reg;
                    errors_reg      <= errors_next;
                end 
                // C. Error Accumulation
                else begin
                    errors_reg <= errors_next;
                end

                // D. Counters Logic (X/Y Movement)
                if (s_tvalid && s_tready) begin
                    // SOF Reset (Hard Sync)
                    if (s_tuser_sof) begin
                        x_cnt <= '0;
                        y_cnt <= '0;
                        frame_cnt_reg <= frame_cnt_reg + 1'b1;
                    end 
                    // EOL Logic
                    else if (s_tlast) begin
                        x_cnt <= '0;
                        if (y_cnt == FRAME_HEIGHT - 1) begin
                            y_cnt <= '0;
                            // Tu by sme mohli inkrementovať frame_cnt ak SOF chýba,
                            // ale spoliehame sa primárne na SOF.
                        end else begin
                            y_cnt <= y_cnt + 1'b1;
                        end
                    end 
                    // Normal Pixel
                    else begin
                        if (x_cnt < FRAME_WIDTH - 1) begin
                            x_cnt <= x_cnt + 1'b1;
                        end
                        // Ak x_cnt dosiahne limit bez TLAST, držíme ho (saturácia)
                        // alebo necháme pretiecť. Saturácia je bezpečnejšia pre debug.
                    end
                end
            end
        end

        // ---------------------------------------------------------------------
        // Kombinačná Logika: Detekcia Chýb
        // ---------------------------------------------------------------------
        always_comb begin
            logic [7:0] new_err;
            new_err = ERR_NONE;

            // Checkers bežia len pri platnom transfere
            if (s_tvalid && s_tready) begin
                
                // 1. TUSER Checks
                if (s_tuser_sof) begin
                    if (x_cnt != 0 || y_cnt != 0)
                        new_err |= ERR_TUSER_POS_BIT; // Using Bitwise OR
                end else begin
                    if (x_cnt == 0 && y_cnt == 0 && frame_cnt_reg > 0) 
                        // Ignorujeme chýbajúci SOF na úplnom začiatku simulácie pred prvým frame
                        new_err |= ERR_TUSER_MISS_BIT;
                end

                // 2. TLAST Checks
                if (s_tlast) begin
                    if (x_cnt != FRAME_WIDTH - 1)
                        new_err |= ERR_TLAST_POS_BIT;
                    
                    if (y_cnt == FRAME_HEIGHT - 1 && !s_tuser_sof) begin
                         // Tu je to tricky: Posledný pixel snímky. 
                         // Ďalší takt by mal byť SOF (ak je back-to-back) alebo medzera.
                         // Tento bit indikuje skôr "koniec výšky bez resetu"
                    end
                end else begin
                    if (x_cnt == FRAME_WIDTH - 1)
                        new_err |= ERR_TLAST_MISS_BIT;
                end
            end

            // 3. Error Next Logic
            if (clear_errors_i) begin
                errors_next = ERR_NONE;
            end else if (s_tvalid && s_tready && s_tuser_sof && (x_cnt == 0 && y_cnt == 0)) begin
                // Nový frame bez chyby na začiatku -> zachováme staré chyby alebo resetujeme?
                // Podľa zadania "Robustná verzia" akumulujeme, kým nepríde clear.
                errors_next = errors_reg | new_err; 
            end else begin
                errors_next = errors_reg | new_err;
            end
        end

        // ---------------------------------------------------------------------
        // Simulačné Asserty (Simulation Only)
        // ---------------------------------------------------------------------
        // `ifndef SYNTHESIS je lepšie ako `ifdef SIMULATION
        `ifndef SYNTHESIS
        always_ff @(posedge clk_i) begin
            if (rst_ni && (s_tvalid && s_tready) && C_ENABLE_ASSERTS) begin
                if (errors_next != errors_reg && |errors_next) begin
                    if (C_STRICT_MODE) begin
                        $error("[%0t] AXIS_CHECKER: Error! Flags: 0x%h at [%0d,%0d] Frame: %0d", 
                                $time, errors_next, x_cnt, y_cnt, frame_cnt_reg);
                    end else begin
                        $warning("[%0t] AXIS_CHECKER: Warning! Flags: 0x%h at [%0d,%0d] Frame: %0d", 
                                 $time, errors_next, x_cnt, y_cnt, frame_cnt_reg);
                    end
                end
            end
        end
        `endif

    end else begin : gen_axi_checker_disabled
        // Disabled logic
        always_comb begin
            x_cnt           = '0;
            y_cnt           = '0;
            errors_reg      = '0;
            errors_next     = '0;
            error_x_reg     = '0;
            error_y_reg     = '0;
            frame_cnt_reg   = '0;
            error_frame_reg = '0;
        end
    end endgenerate

    // -------------------------------------------------------------------------
    // 4. Výstupy
    // -------------------------------------------------------------------------
    assign error_any     = |errors_reg;
    assign error_flags   = errors_reg;
    assign error_x_o     = error_x_reg;
    assign error_y_o     = error_y_reg;
    assign frame_cnt_o   = frame_cnt_reg;
    assign error_frame_o = error_frame_reg;
    assign frame_valid_o = (frame_cnt_reg != 0);

endmodule

`default_nettype wire

`endif // AXIS_STREAM_CHECKER_SV
