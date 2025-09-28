// tb_top.sv - Testbench pre SDRAM Tester
`timescale 1ns / 1ps

(* default_nettype = "none" *)

module tb_top;

    // --- Generovanie hodín a resetu ---
    localparam CLK_PERIOD = 20ns; // 50 MHz
    logic SYS_CLK;
    logic RESET_N;

    initial begin
        SYS_CLK = 1'b0;
        forever #(CLK_PERIOD / 2) SYS_CLK = ~SYS_CLK;
    end

    initial begin
        $display("[%0t] INFO: Simulácia sa spúšťa...", $time);
        RESET_N = 1'b0;
        #(CLK_PERIOD * 10);
        RESET_N = 1'b1;
        $display("[%0t] INFO: Reset uvoľnený.", $time);
    end

    // --- Signály pre prepojenie s DUT (Device Under Test) ---
    logic [7:0] SMG_SEG;
    logic [2:0] SMG_DIG;
    logic [5:0] LED;
    logic [5:0] BSW = 6'b0; // Vstupné prepínače, pre test ich nepotrebujeme

    // SDRAM signály
    wire [15:0] SDRAM_DQ; // Musí byť `wire` pre inout
    logic [12:0] SDRAM_ADDR;
    logic [1:0]  SDRAM_BA;
    logic        SDRAM_CAS_N, SDRAM_CKE, SDRAM_CLK, SDRAM_CS_N;
    logic        SDRAM_WE_N, SDRAM_RAS_N, SDRAM_UDQM, SDRAM_LDQM;

    // --- Inštancia DUT (váš `top.sv` v testovacom režime) ---
    top dut (
        .SYS_CLK(SYS_CLK),
        .RESET_N(RESET_N),
        .SMG_SEG(SMG_SEG),
        .SMG_DIG(SMG_DIG),
        .LED(LED),
        .BSW(BSW),
        // VGA/HDMI sú v teste nepoužité
        .VGA_R(), .VGA_G(), .VGA_B(), .VGA_HS(), .VGA_VS(),
        .HDMI_P_J11(),
        // SDRAM piny
        .SDRAM_DQ(SDRAM_DQ),
        .SDRAM_ADDR(SDRAM_ADDR),
        .SDRAM_BA(SDRAM_BA),
        .SDRAM_CAS_N(SDRAM_CAS_N),
        .SDRAM_CKE(SDRAM_CKE),
        .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CS_N(SDRAM_CS_N),
        .SDRAM_WE_N(SDRAM_WE_N),
        .SDRAM_RAS_N(SDRAM_RAS_N),
        .SDRAM_UDQM(SDRAM_UDQM),
        .SDRAM_LDQM(SDRAM_LDQM)
    );

    // --- Inštancia simulačného modelu SDRAM pamäte ---
    // Inštancia nového generického modelu
    generic_sdram sdram_model (
        .DQ(SDRAM_DQ),
        .A(SDRAM_ADDR),
        .BA(SDRAM_BA), // Názov portu je teraz `BA`
        .CLK(SDRAM_CLK),
        .CKE(SDRAM_CKE),
        .CS_n(SDRAM_CS_N),
        .RAS_n(SDRAM_RAS_N),
        .CAS_n(SDRAM_CAS_N),
        .WE_n(SDRAM_WE_N),
        .DQM({SDRAM_UDQM, SDRAM_LDQM})
    );

endmodule
