`timescale 1ns / 1ns

import vga_pkg::*;

//======================================================
// Modul: Line
// Popis: FSM generátor riadkového časovania pre video
//======================================================

module Line #(
    parameter WIDTH = TIMING_WIDTH // Šírka počítadla (zvyčajne rovnaká ako LINE_WIDTH)
)(
    input  logic         clk,      // Hodiny
    input  logic         rstn,     // Synchrónny reset (aktívne nízky)
    input  logic         enable,   // Povolenie inkrementácie počítadla (napr. pixel clock tick)
    input  Line_t        line,     // Vstupná štruktúra s časovacími parametrami
    
    output logic         de,       // Data Enable – aktívna zobrazovacia oblasť
    output logic         sync,     // Synchronizačný impulz
    output logic         stop      // Označuje koniec riadku (na konci front porch)
);

    //======================================================
    // Stavový automat typu Moore pre riadkové časovanie
    //======================================================

    typedef enum logic [1:0] {
        SYN,  // Sync Pulse
        BCP,  // Back Porch
        ACT,  // Active Video
        FRP   // Front Porch
    } State_e;

    State_e current_state = SYN;   // Aktuálny stav FSM
    State_e next_state    = SYN;   // Budúci stav FSM

    logic [WIDTH-1:0] state_counter;  // Počítadlo pixelov v rámci aktuálneho stavu


    //======================================================
    // Prechodová logika FSM – závislá len od stavu a počítadla
    //======================================================
    always_comb begin
        next_state = current_state;
        case (current_state)
            SYN: if (state_counter >= line.sync_pulse - 1) next_state = BCP;
            BCP: if (state_counter >= line.back_porch - 1) next_state = ACT;
            ACT: if (state_counter >= line.visible_area - 1) next_state = FRP;
            FRP: if (state_counter >= line.front_porch - 1) next_state = SYN;
        endcase
    end

    //======================================================
    // Sledovanie aktuálneho stavu – zmena na hranici hodinového signálu
    //======================================================
    always_ff @(posedge clk) begin
        if (!rstn)
            current_state <= SYN;
        else
            current_state <= next_state;
    end

    //======================================================
    // Počítadlo pixelov v rámci jedného FSM stavu
    //======================================================
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_counter <= '0;
        end else if (current_state != next_state) begin
            state_counter <= '0;  // Reset počítadla pri prechode na nový stav
        end else if (enable) begin
            state_counter <= state_counter + 1'b1;  // Inkrement len pri enable
        end
    end


    //======================================================
    // Generovanie výstupných signálov podľa aktuálneho stavu
    //======================================================
    always_comb begin
        // Defaultné hodnoty
        de   = 1'b0;
        sync = 1'b0;
        stop = 1'b0;

        case (current_state)
            SYN: begin
                sync = 1'b1;  // Synchronizačný impulz aktívny
            end
            BCP: begin
            end
            ACT: begin
                de = 1'b1;    // Data Enable počas zobrazovania
            end
            FRP: begin
                stop = (current_state == FRP && next_state == SYN);
            end
        endcase
    end

endmodule

module Timing (
    input  logic         clk,       // Hodiny
    input  logic         rstn,      // Synchrónny reset (aktívne nízky)
    input  logic         enable,    // Povolenie inkrementácie pixelového počítadla
    input  Line_t        h_line,    // Parametre horizontálneho časovania
    input  Line_t        v_line,    // Parametre vertikálneho časovania
    
    output logic         line_end,
    output logic         frame_end, // Koniec celej snímky
    output logic         de,        // Data Enable (platný pixel)
    output logic         h_sync,    // Horizontálny synchronizačný impulz
    output logic         v_sync     // Vertikálny synchronizačný impulz
);

    // Interné signály medzi FSM a výstupom
    logic h_de, v_de;               // Aktívne oblasti H a V
    logic h_sy, v_sy;               // Sync signály H a V
    logic v_enable;                 // Povolenie vertikálneho posunu (raz na riadok)

    // Inštancia FSM pre horizontálne časovanie
    Line h_line_inst (
        .clk(clk),
        .rstn(rstn),
        .enable(enable),            // Počítaj na každý pixel tick
        .line(h_line),
        .de(h_de),
        .sync(h_sy),
        .stop(v_enable)             // Vygeneruje 1, keď sa ukončí jeden celý riadok
    );

    // Inštancia FSM pre vertikálne časovanie
    Line v_line_inst (
        .clk(clk),
        .rstn(rstn),
        .enable(v_enable),          // Počítaj raz na každý ukončený riadok
        .line(v_line),
        .de(v_de),
        .sync(v_sy),
        .stop(frame_end)            // Koniec celej snímky
    );

    // Kombinačná logika pre výstupy
    always_comb begin
        de     = h_de & v_de;       // Viditeľný pixel len ak oba FSM sú v active area
        h_sync = h_sy ^ h_line.polarity; // Horizontálny sync
        v_sync = v_sy ^ v_line.polarity; // Vertikálny sync
		  line_end = v_enable;
    end

endmodule


module Vga #(
    // --- Hlavné parametre modulu ---
    
    // MODE: Určuje VGA režim. Ak je nastavený na VGA_CUSTOM, použijú sa vstupy *_custom.
    parameter VGA_mode_e MODE = VGA_640x480_60,
    
    // TEST_MODE: Zapína interný generátor testovacích obrazcov.
    // 0 = Vypnutý (dáta z FIFO)
    // 1 = Vertikálne pruhy
    // 2 = Horizontálne pruhy
    parameter int TEST_MODE = 0,
    
    // Farby pre špeciálne stavy
    parameter VGA_data_t BLANKING_COLOR = YELLOW,
    parameter VGA_data_t UNDERRUN_COLOR = PURPLE
)(
    // --- Hlavné Vstupy ---
    input  logic      clk,         // Systémové hodiny
    input  logic      rstn,        // Asynchrónny reset, aktívny v L
    input  logic      enable,      // Povolenie činnosti modulu
    
    // --- Vstupy pre VLASTNÉ časovanie (použité iba ak MODE == VGA_CUSTOM) ---
    input  Line_t     h_line_custom,
    input  Line_t     v_line_custom,
    
    // --- Vstupy z FIFO ---
    input  VGA_data_t data_in,     // Dáta pixelov z FIFO
    input  logic      fifo_empty,  // Flag signalizujúci prázdne FIFO
    
    // --- Výstupy do fyzického rozhrania ---
    output logic      de,          // Data Enable – indikuje platný pixel
    output VGA_data_t data_out,    // Výstupné RGB dáta
    output VGA_sync_t sync_out,    // Synchronizačné signály (h_sync a v_sync)
    output logic      line_end,    // Pulz na konci aktívneho riadku
    output logic      frame_end    // Pulz na konci aktívnej snímky
);

    // =========================================================================
    // ==                          INTERNÉ SIGNÁLY                          ==
    // =========================================================================
    
    // Surové (neregistrované) signály z generátora časovania
    logic de_raw;
    logic h_sy_raw, v_sy_raw;
    
    // Signály pre riadenie toku dát
    logic valid_pixel, underrun;


    // =========================================================================
    // ==                        GENERÁTOR ČASOVANIA                        ==
    // =========================================================================
    
    // Táto sekcia vyberie zdroj časovacích parametrov podľa parametra MODE.
    generate
        if (MODE == VGA_CUSTOM) begin: custom_timing_logic
            // Ak je režim VLASTNÝ, použijú sa priamo vstupné porty modulu.
            Timing timing_inst (
                .clk      (clk),
                .rstn     (rstn),
                .enable   (enable),
                .h_line   (h_line_custom), // Použijeme vstup
                .v_line   (v_line_custom), // Použijeme vstup
                .de       (de_raw),
                .h_sync   (h_sy_raw),
                .v_sync   (v_sy_raw),
                .line_end (line_end),
                .frame_end(frame_end)
            );
        end else begin: predefined_timing_logic
            // Ak je režim PREDDEFINOVANÝ, parametre sa získajú z funkcie v balíčku.
            localparam VGA_params_t vga_timing = get_vga_params(MODE);
            
            Timing timing_inst (
                .clk      (clk),
                .rstn     (rstn),
                .enable   (enable),
                .h_line   (vga_timing.h_line), // Hodnota z localparam
                .v_line   (vga_timing.v_line), // Hodnota z localparam
                .de       (de_raw),
                .h_sync   (h_sy_raw),
                .v_sync   (v_sy_raw),
                .line_end (line_end),
                .frame_end(frame_end)
            );
        end
    endgenerate
    

    // =========================================================================
    // ==               LOGIKA PRE UNDERRUN A PLATNÉ PIXELY                 ==
    // =========================================================================
    
    // Underrun nastane, ak generátor časovania vyžaduje pixel (de_raw=1), ale FIFO je prázdne.
    assign underrun = de_raw & fifo_empty;
    // Pixel je platný a môže byť zobrazený, ak ho generátor vyžaduje a FIFO NIE JE prázdne.
    assign valid_pixel = de_raw & ~fifo_empty;

    // =========================================================================
    // ==                   GENERÁTOR TESTOVACÍCH VZORCOV                   ==
    // =========================================================================

    // Táto sekcia generuje hardvér pre testovacie obrazce, iba ak je TEST_MODE > 0.
	 // Signál pre farbu z testovacieho generátora
    VGA_data_t test_color;
	 
    generate
        if (TEST_MODE == 0) begin: normal_mode_gen
            // Ak je testovanie vypnuté, iba priradíme defaultnú hodnotu, aby sa predišlo latch-u.
            assign test_color = '0;

        end else begin: any_test_mode_gen // Tento blok sa vygeneruje pre akýkoľvek testovací režim.

            // 1. Deklarujeme interné počítadlá pozície pre generovanie vzorcov.
            // Ich šírka je odvodená z balíčka, čo zvyšuje flexibilitu.
            logic [TIMING_WIDTH-1:0] h_pos_counter;
            logic [TIMING_WIDTH-1:0] v_pos_counter;

            // 2. Definujeme sekvenčnú logiku, ktorá riadi počítadlá.
            always_ff @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    h_pos_counter <= '0;
                    v_pos_counter <= '0;
                end else if (enable) begin
                    // Horizontálne počítadlo: inkrementuje sa pri každom platnom pixeli, resetuje na konci riadku.
                    if (line_end)       h_pos_counter <= '0;
                    else if (de_raw)    h_pos_counter <= h_pos_counter + 1;

                    // Vertikálne počítadlo: inkrementuje sa na konci každého riadku, resetuje na konci snímky.
                    if (frame_end)      v_pos_counter <= '0;
                    else if (line_end)  v_pos_counter <= v_pos_counter + 1;
                end
            end

            // 3. Kombinačná logika, ktorá generuje farbu pixelu na základe pozície a režimu.
            always_comb begin
                case (TEST_MODE)
                    1: begin // Režim 1: Vertikálne pruhy
                        case (h_pos_counter[8:6]) // Farba sa mení podľa horizontálnej pozície
                            3'd0:    test_color = RED;
                            3'd1:    test_color = GREEN;
                            3'd2:    test_color = BLUE;
                            3'd3:    test_color = YELLOW;
                            3'd4:    test_color = CYAN;
                            3'd5:    test_color = PURPLE;
                            3'd6:    test_color = WHITE;
                            3'd7:    test_color = BLACK;
                            default: test_color = BLACK;
                        endcase
                    end

                    2: begin // Režim 2: Horizontálne pruhy
                        case (v_pos_counter[8:6]) // Farba sa mení podľa vertikálnej pozície
                            3'd0:    test_color = RED;
                            3'd1:    test_color = GREEN;
                            3'd2:    test_color = BLUE;
                            3'd3:    test_color = YELLOW;
                            3'd4:    test_color = CYAN;
                            3'd5:    test_color = PURPLE;
                            3'd6:    test_color = WHITE;
                            3'd7:    test_color = BLACK;
                            default: test_color = BLACK;
                        endcase
                    end
                    
                    default: test_color = BLACK; // Pre ostatné (neplatné) testovacie režimy
                endcase
            end
        end
    endgenerate

    // =========================================================================
    // ==                    VÝSTUPNÁ REGISTRAČNÁ LOGIKA                    ==
    // =========================================================================
    logic      de_reg;
    VGA_data_t data_reg;
    VGA_sync_t sync_reg;

    // Tento blok registruje všetky výstupy, aby boli čisté a zosynchronizované s hodinami.
    always_ff @(posedge clk) begin
        if (!rstn) begin
            de_reg   <= 1'b0;
            data_reg <= BLANKING_COLOR;
//            sync_reg <= '{hs: 1'b1, vs: 1'b1}; // Reset do bezpečného neaktívneho stavu
			  // ZMENA: Priradenie každého člena štruktúry zvlášť pre IcarusVerilog
			  sync_reg.hs <= 1'b1;
			  sync_reg.vs <= 1'b1;				
        end else if (enable) begin
            // Registrujeme "surové" signály z generátora časovania
            de_reg   <= de_raw;
            //sync_reg <= '{hs: h_sy_raw, vs: v_sy_raw};
			  // ZMENA: Priradenie každého člena štruktúry zvlášť pre IcarusVerilog
			  sync_reg.hs <= h_sy_raw;
			  sync_reg.vs <= v_sy_raw;				

            // Výber zdroja dát pre výstupný pixel
            if (TEST_MODE > 0) begin
                // V TESTOVACOM REŽIME použijeme farbu z generátora vzorcov
                if (de_raw) begin
                    data_reg <= test_color;
                end else begin
                    data_reg <= BLANKING_COLOR; // Mimo viditeľnej oblasti
                end
            end else begin
                // V NORMÁLNOM REŽIME pracujeme s dátami z FIFO
                if (underrun) begin
                    data_reg <= UNDERRUN_COLOR;
                end else if (valid_pixel) begin
                    data_reg <= data_in;
                end else begin
                    data_reg <= BLANKING_COLOR;
                end
            end
        end
    end


    // =========================================================================
    // ==                         VÝSTUPNÉ PRIRADENIA                       ==
    // =========================================================================
    
    // Priradenie registrovaných signálov na fyzické výstupy modulu
    assign de       = de_raw; //= de_reg;
    assign data_out = data_reg;
    assign sync_out = sync_reg;

endmodule

module PixelCoordinates #(
    parameter int X_WIDTH = TIMING_WIDTH,
    parameter int Y_WIDTH = TIMING_WIDTH
)(
    input  logic clk,
    input  logic rstn,
    input  logic de,        // Data Enable pre X súradnicu
    input  logic line_end,  // Impulz na konci každého riadku (z h_line_inst)
    input  logic frame_end, // Impulz na konci celej snímky (z v_line_inst)

    output logic [X_WIDTH-1:0] x,
    output logic [Y_WIDTH-1:0] y
);

    // X súradnica sa resetuje na konci riadku a počíta počas aktívnej oblasti
    always_ff @(posedge clk) begin
        if (!rstn)              x <= '0;
        else if (line_end)      x <= '0;
        else if (de)            x <= x + 1;
    end

    // Y súradnica sa resetuje na konci snímky a počíta na konci každého riadku
    always_ff @(posedge clk) begin
        if (!rstn)              y <= '0;
        else if (frame_end)     y <= '0;
        else if (line_end)      y <= y + 1; // OPRAVA: Odstránená podmienka 'de'
    end
endmodule

