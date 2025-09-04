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