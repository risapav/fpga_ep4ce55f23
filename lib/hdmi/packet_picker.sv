// packet_picker.sv
// Modul pre výber HDMI paketov (infoframe, audio, atď.) počas data island period
module packet_picker #(
    parameter int VIDEO_ID_CODE = 1,
    parameter real VIDEO_RATE = 25.2e6,
    parameter int AUDIO_RATE = 44100,
    parameter int AUDIO_BIT_WIDTH = 16,
    parameter bit [8*8-1:0] VENDOR_NAME = "Unknown",
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = "FPGA",
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00
)(
    input  logic            clk_pixel,
    input  logic            clk_audio,
    input  logic            video_field_end,
    input  logic            packet_enable,
    output logic [4:0]      packet_pixel_counter,
    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0], // stereo samples
    output logic [23:0]     header,
    output logic [55:0]     sub [3:0]
);

    // Packet counter (counts from 0 to 31, wraps)
    always_ff @(posedge clk_pixel) begin
        if (video_field_end || !packet_enable)
            packet_pixel_counter <= 0;
        else if (packet_enable)
            packet_pixel_counter <= packet_pixel_counter + 1;
    end

    // Vzory pre HDMI infoframes a audio pakety:
    // Toto je zjednodušené, napr. AVI infoframe header + data

    // Predpripravené infoframe hlavičky - pre ilustráciu
    // Skutočná implementácia by mala obsahovať aj kontrolné súčty, CRC atď.
    localparam [23:0] AVI_INFOFRAME_HEADER = 24'h82_02_0D; // Example: type=0x82, version=2, length=13
    localparam [55:0] AVI_INFOFRAME_DATA = {56'h00_00_00_00_00_00_00}; // Dátová časť 13 bajtov (zjednodušenie)

    // Výber dát podľa čísla paketu (len príklad)
    always_comb begin
        case (packet_pixel_counter)
            5'd0: header = AVI_INFOFRAME_HEADER;
            default: header = 24'd0;
        endcase
    end

    // Podmoduly dát - tu je jednoduché nastavenie nulových dát (doplniť podľa potreby)
    genvar i;
    generate
        for (i=0; i<4; i++) begin : subgen
            always_comb sub[i] = 56'd0;
        end
    endgenerate

endmodule
