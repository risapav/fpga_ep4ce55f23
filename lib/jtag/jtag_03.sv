//-----------------------------------------------------------------------------
// Modul: jtag_logic
// Popis: Implementácia JTAG bitbanging logiky riadenej cez FT245 USB FIFO.
//        Moore FSM, synchronizovaný reset, prehľadné rozdelenie výstupných stavov.
//-----------------------------------------------------------------------------

module jtag_logic (
    input  logic        CLK,       // Systémový hodinový signál (napr. 24/25 MHz)
    input  logic        rst_n,     // Asynchrónny aktívne nízky reset

    input  logic        nRXF,      // FT245 signalizuje dostupné dáta (aktívne nízka)
    input  logic        nTXE,      // FT245 signalizuje, že je pripravený prijímať (aktívne nízka)

    // Pripojenie k JTAG/AS/PS signálom
    input  logic        B_TDO,     // JTAG: TDO vstup (data from target)
    input  logic        B_ASDO,    // AS/PS: readback lines (nSTATUS, DATAOUT)

    output logic        B_TCK,     // JTAG/AS/PS: clock
    output logic        B_TMS,     // JTAG: TMS, PS: nCONFIG
    output logic        B_NCE,     // AS: chip enable
    output logic        B_NCS,     // AS: chip select
    output logic        B_TDI,     // JTAG: data to target
    output logic        B_OE,      // LED alebo výstupný driver enable

    output logic        nRD,       // FT245: čítací signál
    output logic        WR,        // FT245: zápisový signál

    inout  tri [7:0]    D          // Dátová zbernica FT245 (bi-direkčná)
);

    //=========================================================================
    // Deklarácie signálov
    //=========================================================================

    typedef enum logic [4:0] {
        IDLE,
        READ_REQUEST,
        READ_LATCH,
        DECODE_COMMAND,
        EXECUTE_CMD,
        READBACK_REQUEST,
        READBACK_WAIT,
        READBACK_OUTPUT,
        WRITE_TO_DEVICE
    } fsm_state_t;

    fsm_state_t state, next_state;

    logic [7:0] data_reg;           // Registre na uloženie prijatých dát
    logic [8:0] bit_count;          // Počet bitov na spracovanie
    logic [7:0] shift_reg;          // Shift register pre bitbang
    logic       do_output;          // Indikácia, že máme odoslať byte späť
    logic       carry_bit;

    // Bidirectional D zbernica
    logic       drive_bus;
    assign D = drive_bus ? shift_reg : 8'bz;

    // Synchronizovaný reset
    logic rst_sync;
    ResetSynchronizer rst_sync_inst (
        .clk(CLK),
        .rst_n_in(rst_n),
        .rst_n_out(rst_sync)
    );

    //=========================================================================
    // Výber ďalšieho stavu FSM (kombinačná logika)
    //=========================================================================

    always_comb begin
        next_state = state;

        unique case (state)
            IDLE: begin
                if (!nRXF) next_state = READ_REQUEST;
            end

            READ_REQUEST:    next_state = READ_LATCH;
            READ_LATCH:      next_state = DECODE_COMMAND;
            DECODE_COMMAND:  next_state = EXECUTE_CMD;

            EXECUTE_CMD: begin
                // Príklad: ak chceme posielať odpoveď, pôjdeme do READBACK
                if (do_output) next_state = READBACK_REQUEST;
                else           next_state = IDLE;
            end

            READBACK_REQUEST:
                if (!nTXE) next_state = READBACK_WAIT;

            READBACK_WAIT:    next_state = READBACK_OUTPUT;
            READBACK_OUTPUT:  next_state = IDLE;

            default:          next_state = IDLE;
        endcase
    end

    //=========================================================================
    // Sekvenčná logika FSM a výstupov (Moore FSM)
    //=========================================================================

    always_ff @(posedge CLK or negedge rst_sync) begin
        if (!rst_sync) begin
            state       <= IDLE;
            nRD         <= 1'b1;
            WR          <= 1'b0;
            drive_bus   <= 1'b0;
            shift_reg   <= 8'h00;
            bit_count   <= 9'd0;
            do_output   <= 1'b0;
            {B_TCK, B_TMS, B_TDI, B_NCE, B_NCS, B_OE} <= '0;
        end else begin
            state <= next_state;

            // Výstupy viazané na stav FSM
            unique case (next_state)
                IDLE: begin
                    nRD       <= 1'b1;
                    WR        <= 1'b0;
                    drive_bus <= 1'b0;
                end

                READ_REQUEST: begin
                    nRD <= 1'b0;
                end

                READ_LATCH: begin
                    data_reg <= D;
                    nRD      <= 1'b1;
                end

                DECODE_COMMAND: begin
                    // Príklad spracovania príkazu
                    if (data_reg[7] == 1) begin
                        // Komunikačný rámec obsahuje počet bitov
                        bit_count <= {data_reg[5:0], 3'b111};
                        do_output <= data_reg[6];
                    end else begin
                        // Neposielame dáta, iba nastavujeme výstupy
                        {B_TCK, B_TMS, B_NCE, B_NCS, B_TDI, B_OE} <= data_reg[5:0];
                    end
                    shift_reg <= data_reg;
                end

                EXECUTE_CMD: begin
                    if (bit_count != 0) begin
                        B_TCK <= 1'b1;
                        carry_bit <= (B_NCS == 1) ? B_TDO : B_ASDO;
                        shift_reg <= {carry_bit, shift_reg[7:1]};
                        B_TDI <= shift_reg[0];
                        bit_count <= bit_count - 1;
                    end else begin
                        B_TCK <= 1'b0;
                    end
                end

                READBACK_REQUEST: begin
                    WR <= 1'b1;
                end

                READBACK_WAIT: begin
                    drive_bus <= 1'b1;
                end

                READBACK_OUTPUT: begin
                    WR <= 1'b0;
                end
            endcase
        end
    end

endmodule
