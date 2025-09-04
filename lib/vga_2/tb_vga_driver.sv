// tb_vga_driver.sv - Testbench pre refaktorovaný vga_driver
`default_nettype none
`timescale 1ns/1ps

// Vloženie všetkých potrebných súborov pre kompiláciu
`include "vga_driver.sv"
`include "vga_timing.sv"
`include "vga_pkg.sv"
`include "axi_pkg.sv"
`include "async_fifo.sv"

module tb_vga_driver;

    // =======================================================
    // PARAMETRE TESTU
    // =======================================================
    localparam VGA_mode_e RESOLUTION = VGA_800x600;
    localparam int H_RES = 800;
    localparam int V_RES = 600;

    // Periódy hodín, ktoré bude testbench generovať
    localparam int AXI_CLK_PERIOD = 10; // 100 MHz
    localparam int PIX_CLK_PERIOD = 25; // 40 MHz (správna pre 800x600)

    // =======================================================
    // SIGNÁLY A INŠTANCIE
    // =======================================================
    // Hodiny a resety generované v testbenchi
    logic pix_clk, pix_rstn;
    logic axi_clk, axi_rstn;

    // Signály pripojené k DUT
    logic [4:0] vga_r, vga_g, vga_b;
    logic vga_hs, vga_vs;

    // AXI Stream rozhranie na pripojenie k DUT
    axi4s_if #(.DATA_WIDTH(16), .USER_WIDTH(1)) axis_if();

    // Inštancia testovaného modulu (Device Under Test)
    vga_driver #(
        .RESOLUTION(RESOLUTION)
    ) dut (
        // Pripojenie hodín a resetov z testbenchu
        .pix_clk(pix_clk),
        .pix_rstn(pix_rstn),
        .axi_clk(axi_clk),
        .axi_rstn(axi_rstn),

        .s_axis(axis_if.slave),

        .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b),
        .VGA_HS(vga_hs), .VGA_VS(vga_vs)
    );

    // =======================================================
    // GENERÁTORY HODÍN A RESETU
    // =======================================================
    initial axi_clk = 0;
    always #(AXI_CLK_PERIOD/2) axi_clk = ~axi_clk;

    initial pix_clk = 0;
    always #(PIX_CLK_PERIOD/2) pix_clk = ~pix_clk;

    task apply_reset();
        pix_rstn <= 0;
        axi_rstn <= 0;
        repeat(5) @(posedge axi_clk);
        pix_rstn <= 1;
        axi_rstn <= 1;
        $display("[%0t] Systém uvoľnený z resetu.", $time);
    endtask

    // =======================================================
    // AXI-STREAM ZDROJ (STIMULY)
    // =======================================================
    assign axis_if.ACLK    = axi_clk;
    assign axis_if.ARESETn = axi_rstn;

    task drive_axis_frame(int num_pixels);
        @(negedge axi_rstn);
        for (int i = 0; i < num_pixels; i++) begin
            @(posedge axi_clk);
            axis_if.master.TVALID <= 1;
            axis_if.master.TDATA  <= 16'(i);
            axis_if.master.TUSER  <= (i == 0);
            axis_if.master.TLAST  <= ((i+1) % H_RES == 0);
            while (!axis_if.master.TREADY) @(posedge axi_clk);
        end
        axis_if.master.TVALID <= 0;
        $display("[%0t] Stimulus: Dokončené posielanie %0d pixelov.", $time, num_pixels);
    endtask

    // =======================================================
    // HLAVNÝ TESTOVACÍ SCENÁR
    // =======================================================
    initial begin
        $display("--- Štart Testbenchu pre refaktorovaný driver ---");
        axis_if.master.TVALID <= 0;
        apply_reset();

        // Overenie synchronizácie snímky: TREADY by malo byť na začiatku 0
        fork
            begin
                @(posedge axi_clk);
                if (axis_if.master.TREADY == 1'b0) begin
                    $display("[%0t] OK: TREADY je na začiatku neaktívne (0). Čaká na synchronizáciu.", $time);
                end else begin
                    $error("[%0t] CHYBA: TREADY je na začiatku aktívne (1). Synchronizácia zlyhala.", $time);
                end
                wait(axis_if.master.TREADY == 1'b1);
                $display("[%0t] OK: TREADY sa aktivovalo. Stream je povolený.", $time);
            end
        join_none

        // Test normálnej prevádzky
        drive_axis_frame(H_RES * V_RES);

        wait(vga_vs == 0);
        wait(vga_vs == 1);
        $display("[%0t] VGA: Dokončená prvá snímka.", $time);
        
        #10us;
        $display("--- Koniec Testbenchu ---");
        $finish;
    end

endmodule
