// Refaktorovany JTAG bridge pre FT245BM
// Pridany reset, vylepseny stavovy automat, pridane poznamky

module jtag_logic (
    input  logic        CLK,       // 24/25 MHz hlavny hodinovy signal
    input  logic        RESETn,    // Asynchrónny reset (aktivny v nule)

    input  logic        nRXF,      // FT245BM: Receive FIFO not empty (active low)
    input  logic        nTXE,      // FT245BM: Transmit FIFO not full (active low)

    input  logic        B_TDO,     // JTAG input: TDO, AS/PS input: CONF_DONE
    input  logic        B_ASDO,    // AS input: DATAOUT, PS input: nSTATUS

    output logic        B_TCK,     // JTAG output: TCK to chain, AS/PS DCLK
    output logic        B_TMS,     // JTAG output: TMS to chain, AS/PS nCONFIG
    output logic        B_NCE,     // AS output: nCE
    output logic        B_NCS,     // AS output: nCS
    output logic        B_TDI,     // JTAG output: TDI to chain, ASDI, PS: DATA0
    output logic        B_OE,      // LED alebo Output Enable

    output logic        nRD,       // FT245BM: Read enable (active low)
    output logic        WR,        // FT245BM: Write enable

    inout  tri   [7:0]  D          // FT245BM: 8-bit datová zbernica (bidirectional)
);

    // Typ stavoveho automatu
    typedef enum logic [4:0] {
        IDLE,
        READ_PREP,
        READ_DATA,
        INTERPRET,
        SET_PINS,
        READ_PINS,
        SET_BITCOUNT,
        SHIFT_LOAD,
        SHIFT_HIGH,
        SHIFT_KEEP,
        SHIFT_LOW,
        TX_WAIT,
        TX_WR_HIGH,
        TX_DRIVE,
        TX_WR_LOW,
        TX_RELEASE
    } state_t;

    // Stavove premenne
    state_t state, next_state;

    logic [7:0] ioshifter;
    logic [8:0] bitcount;
    logic       do_output;
    logic       carry;

    logic       drive_data;
    logic [7:0] data_out;

    assign data_out = ioshifter;
    assign D = drive_data ? data_out : 8'bz;

    // Logika prechodu medzi stavmi (kombinačná)
    always_comb begin
        next_state = state;
        case (state)
            IDLE:           if (!nRXF)     next_state = READ_PREP;
            READ_PREP:                     next_state = READ_DATA;
            READ_DATA:                     next_state = INTERPRET;

            INTERPRET:
                if (ioshifter[7]) begin
                    if (ioshifter[6]) next_state = READ_PINS;
                    else              next_state = SET_BITCOUNT;
                end else begin
                    next_state = SET_PINS;
                end

            SET_PINS:                      next_state = IDLE;
            READ_PINS:     if (!nTXE)     next_state = TX_WR_HIGH;
            SET_BITCOUNT:                 next_state = IDLE;
            SHIFT_LOAD:                   next_state = SHIFT_HIGH;
            SHIFT_HIGH:                   next_state = SHIFT_KEEP;
            SHIFT_KEEP:                   next_state = SHIFT_LOW;
            SHIFT_LOW:
                if (bitcount != 0)        next_state = SHIFT_LOAD;
                else if (do_output)       next_state = TX_WAIT;
                else                      next_state = IDLE;

            TX_WAIT:       if (!nTXE)     next_state = TX_WR_HIGH;
            TX_WR_HIGH:                   next_state = TX_DRIVE;
            TX_DRIVE:                     next_state = TX_WR_LOW;
            TX_WR_LOW:                    next_state = TX_RELEASE;
            TX_RELEASE:                   next_state = IDLE;

            default:                      next_state = IDLE;
        endcase
    end

    // Sekvenčná logika (na hranu CLK alebo reset)
    always_ff @(posedge CLK or negedge RESETn) begin
        if (!RESETn) begin
            state       <= IDLE;
            ioshifter   <= 8'b0;
            bitcount    <= 9'b0;
            do_output   <= 1'b0;
            carry       <= 1'b0;
            drive_data  <= 1'b0;

            nRD         <= 1'b1;
            WR          <= 1'b0;

            // Default výstupy
            B_TCK       <= 1'b0;
            B_TMS       <= 1'b0;
            B_NCE       <= 1'b0;
            B_NCS       <= 1'b0;
            B_TDI       <= 1'b0;
            B_OE        <= 1'b0;

        end else begin
            state <= next_state;

            // Predvolená deaktivácia výstupov pre každé kolo
            nRD        <= 1'b1;
            WR         <= 1'b0;
            drive_data <= 1'b0;
            B_TCK      <= 1'b0;

            case (state)
                READ_PREP,
                READ_DATA:      nRD <= 1'b0;

                READ_DATA:      ioshifter <= D;

                SET_PINS: begin
                    B_TCK <= ioshifter[0];
                    B_TMS <= ioshifter[1];
                    B_NCE <= ioshifter[2];
                    B_NCS <= ioshifter[3];
                    B_TDI <= ioshifter[4];
                    B_OE  <= ioshifter[5];
                end

                READ_PINS: begin
                    ioshifter <= {6'b0, B_ASDO, B_TDO};
                end

                SET_BITCOUNT: begin
                    bitcount  <= {ioshifter[5:0], 3'b111};
                    do_output <= ioshifter[6];
                end

                SHIFT_LOAD: begin
                    carry     <= (B_NCS == 1'b1) ? B_TDO : B_ASDO;
                    B_TDI     <= ioshifter[0];
                    bitcount  <= bitcount - 1;
                end

                SHIFT_HIGH, SHIFT_KEEP: begin
                    B_TCK <= 1'b1;
                end

                SHIFT_HIGH:
                    ioshifter <= {carry, ioshifter[7:1]};

                TX_WR_HIGH: WR <= 1'b1;
                TX_DRIVE: begin
                    drive_data <= 1'b1;
                end
            endcase
        end
    end

endmodule
