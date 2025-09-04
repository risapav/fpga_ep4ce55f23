module jtag_logic (
    input  logic        CLK,       // external 24/25 MHz oscillator
    input  logic        nRXF,      // FT245BM nRXF (active low)
    input  logic        nTXE,      // FT245BM nTXE (active low)
    input  logic        B_TDO,     // JTAG input: TDO, AS/PS input: CONF_DONE
    input  logic        B_ASDO,    // AS input: DATAOUT, PS input: nSTATUS
    output logic        B_TCK,     // JTAG output: TCK to chain, AS/PS DCLK
    output logic        B_TMS,     // JTAG output: TMS to chain, AS/PS nCONFIG
    output logic        B_NCE,     // AS output: nCE
    output logic        B_NCS,     // AS output: nCS
    output logic        B_TDI,     // JTAG output: TDI to chain, AS: ASDI, PS: DATA0
    output logic        B_OE,      // LED output/output driver enable
    output logic        nRD,       // FT245BM nRD
    output logic        WR,        // FT245BM WR
    inout  tri   [7:0]  D          // FT245BM data bus (bi-dir)
);

    // State machine states
    typedef enum logic [4:0] {
        wait_for_nRXF_low,
        set_nRD_low,
        keep_nRD_low,
        latch_data_from_host,
        set_nRD_high,
        bits_set_pins_from_data,
        bits_read_from_pins_and_wait_for_nTXE_low,
        bytes_set_bitcount,
        bytes_get_tdo_set_tdi,
        bytes_clock_high_and_shift,
        bytes_keep_clock_high,
        bytes_clock_finish,
        wait_for_nTXE_low,
        set_WR_high,
        output_enable,
        set_WR_low,
        output_disable
    } state_t;

    state_t state, next_state;

    logic carry;
    logic do_output;
    logic [7:0] ioshifter;
    logic [8:0] bitcount;

    // Internal signals to control output data bus direction
    logic drive_data;
    logic [7:0] data_out;

    assign data_out = ioshifter;
    assign D = drive_data ? data_out : 8'bz;

    // Next state logic (combinational)
    always_comb begin
        next_state = state;
        case (state)
            wait_for_nRXF_low:
                if (nRXF == 1'b0)
                    next_state = set_nRD_low;

            set_nRD_low:
                next_state = keep_nRD_low;

            keep_nRD_low:
                next_state = latch_data_from_host;

            latch_data_from_host:
                next_state = set_nRD_high;

            set_nRD_high:
                if (bitcount[8:3] != 6'b000000)
                    next_state = bytes_get_tdo_set_tdi;
                else if (ioshifter[7] == 1'b1)
                    next_state = bytes_set_bitcount;
                else
                    next_state = bits_set_pins_from_data;

            bytes_set_bitcount:
                next_state = wait_for_nRXF_low;

            bits_set_pins_from_data:
                if (ioshifter[6] == 1'b0)
                    next_state = wait_for_nRXF_low; // read next byte from host
                else
                    next_state = bits_read_from_pins_and_wait_for_nTXE_low; // read pins next cycle

            bytes_get_tdo_set_tdi:
                next_state = bytes_clock_high_and_shift;

            bytes_clock_high_and_shift:
                next_state = bytes_keep_clock_high;

            bytes_keep_clock_high:
                next_state = bytes_clock_finish;

            bytes_clock_finish:
                if (bitcount[2:0] != 3'b111)
                    next_state = bytes_get_tdo_set_tdi; // clock next bit
                else if (do_output == 1'b1)
                    next_state = wait_for_nTXE_low; // output byte to host
                else
                    next_state = wait_for_nRXF_low; // read next byte from host

            wait_for_nTXE_low, bits_read_from_pins_and_wait_for_nTXE_low:
                if (nTXE == 1'b0)
                    next_state = set_WR_high;

            set_WR_high:
                next_state = output_enable;

            output_enable:
                next_state = set_WR_low;

            set_WR_low:
                next_state = output_disable;

            output_disable:
                next_state = wait_for_nRXF_low;

            default:
                next_state = wait_for_nRXF_low;
        endcase
    end

    // State registers and outputs (sequential)
    always_ff @(posedge CLK) begin
        state <= next_state;

        // Default outputs
        nRD <= 1'b1;
        WR <= 1'b0;
        drive_data <= 1'b0;

        // Drive output pins depending on state
        case (state)
            set_nRD_low, keep_nRD_low, latch_data_from_host: nRD <= 1'b0;

            set_WR_high, output_enable: WR <= 1'b1;

            output_enable, set_WR_low: begin
                drive_data <= 1'b1;
            end

            default: begin
                // Default all control pins low
                // Nothing specific here
            end
        endcase

        // Latch data from host on latch_data_from_host
        if (state == latch_data_from_host)
            ioshifter <= D;

        // Drive JTAG / control pins from ioshifter on bits_set_pins_from_data
        if (state == bits_set_pins_from_data) begin
            B_TCK <= ioshifter[0];
            B_TMS <= ioshifter[1];
            B_NCE <= ioshifter[2];
            B_NCS <= ioshifter[3];
            B_TDI <= ioshifter[4];
            B_OE  <= ioshifter[5];
        end

        // Read pins into ioshifter on bits_read_from_pins_and_wait_for_nTXE_low
        if (state == bits_read_from_pins_and_wait_for_nTXE_low)
            ioshifter <= {6'b0, B_ASDO, B_TDO};

        // Set bitcount and do_output on bytes_set_bitcount
        if (state == bytes_set_bitcount) begin
            bitcount <= {ioshifter[5:0], 3'b111};
            do_output <= ioshifter[6];
        end

        // Shift data for byte output on bytes_get_tdo_set_tdi
        if (state == bytes_get_tdo_set_tdi) begin
            carry <= (B_NCS == 1'b1) ? B_TDO : B_ASDO;
            B_TDI <= ioshifter[0];
            bitcount <= bitcount - 1;
        end

        // Clock signals for byte output states
        if (state == bytes_clock_high_and_shift || state == bytes_keep_clock_high)
            B_TCK <= 1'b1;

        if (state == bytes_clock_high_and_shift)
            ioshifter <= {carry, ioshifter[7:1]};

        if (state == bytes_clock_finish)
            B_TCK <= 1'b0;
    end

endmodule
