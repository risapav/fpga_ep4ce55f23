// axi_7seg_driver.sv - Vylepšený, flexibilný a konzistentný AXI ovládač
//
// Verzia 2.0 - Opravy a vylepšenia
//
// Kľúčové zmeny:
// 1. OPRAVA (Konzistentnosť): Zjednotené názvoslovie (veľké písmená pre AXI),
//    pridaný import `axi_pkg` a aktualizované parametre pre invertovanie.
// 2. VYLEPŠENIE (Flexibilita): Všetka logika pre prácu s registrami bola
//    prepísaná pomocou `for` cyklov, aby bola plne generická a závislá
//    od parametra `DIGITS`.
// 3. VYLEPŠENIE (Čitateľnosť): Kód bol uprataný a doplnený o komentáre.

`default_nettype none

import axi_pkg::*;
import vga_pkg::*; // Potrebné pre seg7_driver_if, ak je v ňom

module axi_7seg_driver #(
    // --- Konfiguračné parametre ---
    // Tieto parametre sa prenášajú do inštancie seg7_driver
    parameter bit INVERT_SEGS     = 1,
    parameter bit INVERT_DIGIT_EN = 1,
    parameter int DIGITS          = 3,
    parameter int DIGIT_MAP [DIGITS-1:0] = '{default: 0},
    parameter int CLK_FREQ_HZ     = 50_000_000,
    parameter int REFRESH_HZ      = 1000
)(
    input  logic clk,
    input  logic rstn,

    axi4lite_if.slave          axi_if,
    seg7_driver_if.output_port seg_if
);

    // --- Register map - definícia adries registrov ---
    // Adresy sú v bytoch
    localparam int ADDR_REG_DIGITS = 32'h00;
    localparam int ADDR_REG_DOTS   = 32'h04;

    // --- Interné registre na ukladanie hodnôt číslic a bodiek ---
    logic [3:0] digits_reg [DIGITS-1:0];
    logic       dots_reg   [DIGITS-1:0];

    //================================================================
    // AXI Write Logic
    //================================================================
    always_ff @(posedge clk) begin
        if (!rstn) begin
            axi_if.AWREADY <= 1'b0;
            axi_if.WREADY  <= 1'b0;
            axi_if.BVALID  <= 1'b0;
            axi_if.BRESP   <= 2'b00; // OKAY
            for (int i = 0; i < DIGITS; i++) begin
                digits_reg[i] <= 4'hF; // Defaultne 'F'
                dots_reg[i]   <= 1'b0;
            end
        end else begin
            // FSM pre zápis nie je striktne potrebný, dá sa to riešiť kombinačne.
            // Ponechávam jednoduchšiu logiku pre prehľadnosť.

            // Adresný kanál je pripravený, ak dátový kanál nie je zaneprázdnený
            axi_if.AWREADY <= axi_if.WREADY;
            // Dátový kanál je pripravený, ak adresný kanál nie je zaneprázdnený
            axi_if.WREADY  <= axi_if.AWREADY;

            // Spracovanie zápisu
            if (axi_if.AWVALID && axi_if.AWREADY && axi_if.WVALID && axi_if.WREADY) begin
                case (axi_if.AWADDR)
                    ADDR_REG_DIGITS: begin
                        // Generický zápis do registra s číslicami
                        for (int i = 0; i < DIGITS; i++) begin
                            // Každá číslica zaberá 4 bity
                            if (i * 4 < 32) begin // Ochrana proti pretečeniu WDATA
                                digits_reg[i] <= axi_if.WDATA[i*4 +: 4];
                            end
                        end
                        axi_if.BRESP <= 2'b00; // OKAY
                    end
                    ADDR_REG_DOTS: begin
                        // Generický zápis do registra s bodkami
                        for (int i = 0; i < DIGITS; i++) begin
                           if (i < 32) begin // Ochrana proti pretečeniu WDATA
                                dots_reg[i] <= axi_if.WDATA[i];
                           end
                        end
                        axi_if.BRESP <= 2'b00; // OKAY
                    end
                    default: begin
                        axi_if.BRESP <= 2'b10; // Slave Error pre neplatnú adresu
                    end
                endcase
                axi_if.BVALID <= 1'b1;
            end else if (axi_if.BVALID && axi_if.BREADY) begin
                axi_if.BVALID <= 1'b0;
            end
        end
    end

    //================================================================
    // AXI Read Logic
    //================================================================
    always_ff @(posedge clk) begin
        if (!rstn) begin
            axi_if.ARREADY <= 1'b0;
            axi_if.RVALID  <= 1'b0;
            axi_if.RRESP   <= 2'b00;
            axi_if.RDATA   <= '0;
        end else begin
            // Adresný kanál je vždy pripravený, ak nečakáme na odoslanie dát
            axi_if.ARREADY <= !axi_if.RVALID;

            if (axi_if.ARVALID && axi_if.ARREADY) begin
                // Pripravíme dáta na odoslanie v ďalšom cykle
                axi_if.RVALID <= 1'b1;
                case (axi_if.ARADDR)
                    ADDR_REG_DIGITS: begin
                        // Generické čítanie z registra s číslicami
                        logic [31:0] temp_rdata = '0;
                        for (int i = 0; i < DIGITS; i++) begin
                            if (i * 4 < 32) begin
                                temp_rdata[i*4 +: 4] = digits_reg[i];
                            end
                        end
                        axi_if.RDATA <= temp_rdata;
                        axi_if.RRESP <= 2'b00; // OKAY
                    end
                    ADDR_REG_DOTS: begin
                        // Generické čítanie z registra s bodkami
                        logic [31:0] temp_rdata = '0;
                        for (int i = 0; i < DIGITS; i++) begin
                            if (i < 32) begin
                                temp_rdata[i] = dots_reg[i];
                            end
                        end
                        axi_if.RDATA <= temp_rdata;
                        axi_if.RRESP <= 2'b00; // OKAY
                    end
                    default: begin
                        axi_if.RDATA <= 32'hDEADBEEF;
                        axi_if.RRESP <= 2'b10; // Slave Error
                    end
                endcase
            end else if (axi_if.RVALID && axi_if.RREADY) begin
                // Master prijal dáta, môžeme zrušiť validitu
                axi_if.RVALID <= 1'b0;
            end
        end
    end

    //================================================================
    // Inštancia 7-segmentového drivera
    //================================================================
    seg7_driver #(
        .DIGITS(DIGITS),
        .INVERT_SEGS(INVERT_SEGS),
        .INVERT_DIGIT_EN(INVERT_DIGIT_EN),
        .DIGIT_MAP(DIGIT_MAP),
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .REFRESH_HZ(REFRESH_HZ)
    ) driver_inst (
        .clk    (clk),
        .rstn   (rstn),
        .digits (digits_reg),
        .dots   (dots_reg),
        .seg_if (seg_if)
    );

endmodule
