// ============================================================================
// Modul: axis_stream_checker_tb
// Účel: Testbench pre 'axis_stream_checker' (v1.7)
// Verzia: 1.0
// Dátum: 28. október 2025
// Autor: [Tvoj projekt]
//
// Popis:
// Tento testbench overuje funkčnosť 'axis_stream_checker' generovaním
// správnych aj chybných AXI-Stream video snímok.
// Testuje detekciu chýb TUSER/TLAST a funkciu soft resetu.
// ============================================================================

`default_nettype none
`timescale 1ns/1ps

// Importujeme testované balíčky
import axi_pkg::*;
import vga_pkg::*; // Potrebné pre rgb565_t, ak by sme testovali dáta

module axis_stream_checker_tb;

    // --- Parametre simulácie ---
    localparam int CLK_PERIOD_NS = 10; // 100 MHz hodiny
    localparam int FRAME_W       = 800;
    localparam int FRAME_H       = 600;

    // --- Signály pre pripojenie DUT (Device Under Test) ---
    logic clk_i;
    logic rst_ni;
    logic clear_errors_i;

    // AXI4-Stream rozhranie na pripojenie k DUT
    // (Používame axi_interfaces.sv, predpokladáme, že je v include path)
    axi4s_if #(
        .DATA_WIDTH(axi_pkg::AXI_TDATA_WIDTH),
        .USER_WIDTH(axi_pkg::AXI_TUSER_WIDTH)
    ) tb_axis_if ();

    // Výstupy z DUT
    logic       error_any;
    logic [7:0] error_flags;
    logic [$clog2(FRAME_W)-1:0] error_x_o;
    logic [$clog2(FRAME_H)-1:0] error_y_o;
    logic [31:0] frame_cnt_o;
    logic [31:0] error_frame_o;

    // ========================================================================
    // Inštancia DUT (Device Under Test)
    // ========================================================================
    axis_stream_checker #(
        .FRAME_WIDTH(FRAME_W),
        .FRAME_HEIGHT(FRAME_H),
        .C_ENABLE_CHECKS(1),
        .C_ENABLE_ASSERTS(1), // Povolíme $error výpisy
        .C_STRICT_MODE(0)      // Nastavíme na $warning (0), aby simulácia nezastala
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axis(tb_axis_if.slave), // Pripojíme slave port DUT na TB master
        .clear_errors_i(clear_errors_i),
        .error_any(error_any),
        .error_flags(error_flags),
        .error_x_o(error_x_o),
        .error_y_o(error_y_o),
        .frame_cnt_o(frame_cnt_o),
        .error_frame_o(error_frame_o)
    );

    // ========================================================================
    // Hodiny a Reset
    // ========================================================================
    always #(CLK_PERIOD_NS / 2) clk_i = ~clk_i;

    task automatic reset_dut();
        $display("[%0t] INFO: Spúšťam reset...", $time);
        rst_ni         <= 1'b0;
        clear_errors_i <= 1'b0;
        tb_axis_if.TVALID <= 1'b0;
        tb_axis_if.TUSER  <= '0;
        tb_axis_if.TLAST  <= 1'b0;
        tb_axis_if.TDATA  <= '0;
        repeat (5) @(posedge clk_i);
        rst_ni <= 1'b1;
        @(posedge clk_i);
        $display("[%0t] INFO: Reset uvoľnený.", $time);
    endtask

    // ========================================================================
    // AXI Stream Master (Stimuly)
    // ========================================================================

    // TREADY (prijímač) - simulujeme, že je vždy pripravený
    assign tb_axis_if.TREADY = 1'b1;

    // Task na poslanie jedného pixela
    task automatic drive_pixel(
        input logic tuser = 1'b0,
        input logic tlast = 1'b0,
        input logic [axi_pkg::AXI_TDATA_WIDTH-1:0] tdata = '0
    );
        tb_axis_if.TVALID <= 1'b1;
        tb_axis_if.TUSER  <= {{(axi_pkg::AXI_TUSER_WIDTH-1){1'b0}}, tuser};
        tb_axis_if.TLAST  <= tlast;
        tb_axis_if.TDATA  <= tdata;
        @(posedge clk_i);
        tb_axis_if.TVALID <= 1'b0;
    endtask

    // Task na poslanie celého (potenciálne chybného) frame-u
    task automatic drive_frame(
        input string desc,
        input int    err_tuser_x = -1, // Kde poslať TUSER (ak nie 0)
        input int    err_tlast_x = -1, // Kde poslať TLAST (ak nie koniec)
        input bit    err_omit_tuser = 0, // Neodoslať TUSER na (0,0)
        input bit    err_omit_tlast = 0  // Neodoslať TLAST na konci riadkov
    );
        $display("[%0t] INFO: --- Začínam test: %s ---", $time, desc);
        logic tuser, tlast;

        for (int y = 0; y < FRAME_H; y++) begin
            for (int x = 0; x < FRAME_W; x++) begin
                // Výpočet TUSER a TLAST
                tuser = (x == 0 && y == 0 && !err_omit_tuser) || (x == err_tuser_x && y == 0);
                tlast = (x == FRAME_W - 1 && !err_omit_tlast) || (x == err_tlast_x && y == 0);

                // Poslanie pixela
                drive_pixel(tuser, tlast, x + y);

                // Ak sme poslali TLAST, ukončíme riadok
                if (tlast) begin
                    break; // 'break' ukončí 'for (int x...)' slučku
                end
            end
        end
        $display("[%0t] INFO: --- Koniec testu: %s ---", $time, desc);
    endtask

    // ========================================================================
    // Hlavná sekvencia testu
    // ========================================================================
    initial begin
        clk_i = 0;
        reset_dut();

        // 1. Správny frame
        drive_frame("Spravny Frame");
        @(posedge clk_i);
        assert (error_any == 0) else $fatal(1, "Chyba: Spravny frame bol oznaceny ako chybny!");

        // 2. Chyba [0]: TUSER na zlej pozícii
        drive_frame("Chyba 0: TUSER na (5,0)", .err_tuser_x(5));
        @(posedge clk_i);
        assert (error_flags[0] == 1'b1) else $fatal(1, "Chyba: ERR_TUSER_POS_BIT [0] nebola detekovana!");
        $display("[%0t] OK: Chyba TUSER_POS detekovana na (x=%0d, y=%0d)", $time, error_x_o, error_y_o);

        // 3. Chyba [1]: TLAST príliš skoro
        drive_frame("Chyba 1: TLAST na (100,0)", .err_tlast_x(100));
        @(posedge clk_i);
        assert (error_flags[1] == 1'b1) else $fatal(1, "Chyba: ERR_TLAST_POS_BIT [1] nebola detekovana!");
        $display("[%0t] OK: Chyba TLAST_POS detekovana na (x=%0d, y=%0d)", $time, error_x_o, error_y_o);

        // 4. Chyba [3]: Chýbajúci TUSER na (0,0)
        drive_frame("Chyba 3: Chybajuci TUSER", .err_omit_tuser(1));
        @(posedge clk_i);
        assert (error_flags[3] == 1'b1) else $fatal(1, "Chyba: ERR_TUSER_MISS_BIT [3] nebola detekovana!");
        $display("[%0t] OK: Chyba TUSER_MISS detekovana na (x=%0d, y=%0d)", $time, error_x_o, error_y_o);

        // 5. Test clear_errors_i
        $display("[%0t] INFO: Testujem clear_errors_i...", $time);
        clear_errors_i <= 1'b1;
        @(posedge clk_i);
        clear_errors_i <= 1'b0;
        @(posedge clk_i);
        assert (error_any == 0 && frame_cnt_o == 0 && error_frame_o == 0) else $fatal(1, "Chyba: clear_errors_i nevynuloval stav!");
        $display("[%0t] OK: Stav vynulovany.", $time);

        // 6. Chyba [2]: Chýbajúci TLAST (pošleme celý riadok bez TLAST)
        drive_frame("Chyba 2: Chybajuci TLAST", .err_omit_tlast(1));
        @(posedge clk_i);
        // Chyba [2] sa objaví až na konci riadku, súradnice budú (799, Y)
        assert (error_flags[2] == 1'b1) else $fatal(1, "Chyba: ERR_TLAST_MISS_BIT [2] nebola detekovana!");
        $display("[%0t] OK: Chyba TLAST_MISS detekovana na (x=%0d, y=%0d)", $time, error_x_o, error_y_o);

        $display("[%0t] INFO: Vsetky testy uspesne dokoncene.", $time);
        $finish;
    end

endmodule

`default_nettype wire
