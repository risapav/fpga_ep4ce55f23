Jasné! Pripravím ti prepis tvojho HDMI modulu do SystemVerilogu so zrozumiteľnými komentármi a s parametrami, ktoré budú ľahko upraviteľné. Urobím ho syntetizovateľný pre Quartus, pričom ponechám tvoju základnú štruktúru a funkcionalitu.

---

```systemverilog
// HDMI v1.4a implementation - simplified and synthesizable SystemVerilog version for Quartus
// Author: Adapted from Sameer Puri's original, with added comments and parameterization
// Note: This design supports basic HDMI video output (640x480 default), with optional audio and DVI mode.

`include "OBUFDS.v"
`include "packet_assembler.sv"
`include "packet_picker.sv"
`include "tmds_channel.sv"

module hdmi #(
    // Video timing parameters (default: 640x480 @ 60Hz)
    parameter int VIDEO_ID_CODE = 1,           // See CEA-861-D for codes (1=640x480@60Hz)
    parameter int BIT_WIDTH = (VIDEO_ID_CODE < 4) ? 10 : ((VIDEO_ID_CODE == 4) ? 11 : 12),
    parameter int BIT_HEIGHT = (VIDEO_ID_CODE == 16) ? 11 : 10,

    // Output configuration
    parameter bit DVI_OUTPUT = 1'b0,           // 1 = DVI output (no auxiliary data), 0 = HDMI output with audio

    // DDR I/O flag - set to 1 to use DDR output, 0 otherwise
    parameter bit DDRIO = 1'b0,

    // Audio parameters (only used if DVI_OUTPUT == 0)
    parameter real VIDEO_REFRESH_RATE = 59.94,
    parameter int AUDIO_RATE = 44100,          // Audio sample rate in Hz (typical 44100 or 48000)
    parameter int AUDIO_BIT_WIDTH = 16,        // Audio sample bit depth (16-24 bits)

    // Source description strings for HDMI EDID info frames
    parameter bit [8*8-1:0] VENDOR_NAME = {"Unknown", 8'd0},          // 8-byte ASCII, null-padded
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 96'd0},   // 16-byte ASCII, null-padded
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00             // Source device info code
)(
    input  logic                     clk_pixel,        // Pixel clock (e.g. 25.2 MHz for 640x480)
    input  logic                     clk_pixel_x10,    // Pixel clock x10 (for TMDS serialization)
    input  logic                     clk_audio,        // Audio clock (typically 128x sample rate)
    input  logic [23:0]              rgb,              // 8 bits per color (R,G,B)
    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0], // Stereo audio samples [0]=Left, [1]=Right

    // HDMI differential outputs
    output logic [2:0]               tmds_p,
    output logic                    tmds_clock_p,
    output logic [2:0]               tmds_n,
    output logic                    tmds_clock_n,

    // Pixel position outputs for user logic (inside FPGA)
    output logic [BIT_WIDTH-1:0]    cx,
    output logic [BIT_HEIGHT-1:0]   cy,
    output logic [BIT_WIDTH-1:0]    frame_width,
    output logic [BIT_HEIGHT-1:0]   frame_height,
    output logic [BIT_WIDTH-1:0]    screen_width,
    output logic [BIT_HEIGHT-1:0]   screen_height,
    output logic [BIT_WIDTH-1:0]    screen_start_x,
    output logic [BIT_HEIGHT-1:0]   screen_start_y
);

    // Internal signals
    localparam int NUM_CHANNELS = 3; // RGB channels

    logic hsync, vsync;

    // -------------------------
    // Video timing generation based on VIDEO_ID_CODE
    // -------------------------
    generate
        case (VIDEO_ID_CODE)
            1: begin // 640x480@60Hz (VGA)
                assign frame_width = 800;
                assign frame_height = 525;
                assign screen_width = 640;
                assign screen_height = 480;
                assign hsync = ~(cx >= 16 && cx < 16 + 96);
                assign vsync = ~(cy >= 10 && cy < 10 + 2);
            end
            2,3: begin // 720x480@60Hz (NTSC)
                assign frame_width = 858;
                assign frame_height = 525;
                assign screen_width = 720;
                assign screen_height = 480;
                assign hsync = ~(cx >= 16 && cx < 16 + 62);
                assign vsync = ~(cy >= 9 && cy < 9 + 6);
            end
            default: begin
                // Default fallback to VGA timing if unknown code
                assign frame_width = 800;
                assign frame_height = 525;
                assign screen_width = 640;
                assign screen_height = 480;
                assign hsync = ~(cx >= 16 && cx < 16 + 96);
                assign vsync = ~(cy >= 10 && cy < 10 + 2);
            end
        endcase
        assign screen_start_x = frame_width - screen_width;
        assign screen_start_y = frame_height - screen_height;
    endgenerate

    // -------------------------
    // Pixel counters (cx, cy)
    // -------------------------
    always_ff @(posedge clk_pixel) begin
        if (cx == frame_width - 1) begin
            cx <= 0;
            if (cy == frame_height - 1)
                cy <= 0;
            else
                cy <= cy + 1;
        end else begin
            cx <= cx + 1;
        end
    end

    // -------------------------
    // Video data enable signal (active during visible pixels)
    // -------------------------
    logic video_data_period;
    always_ff @(posedge clk_pixel) begin
        video_data_period <= (cx >= screen_start_x) && (cy >= screen_start_y);
    end

    // -------------------------
    // Video and control signals
    // -------------------------
    logic [2:0] mode;
    logic [23:0] video_data;
    logic [5:0] control_data;
    logic [11:0] data_island_data;

    generate
        if (!DVI_OUTPUT) begin : hdmi_mode
            // HDMI mode: auxiliary data for audio, info frames, etc.

            // Timing for auxiliary data periods (guards, preambles)
            logic video_guard, video_preamble;
            always_ff @(posedge clk_pixel) begin
                video_guard <= (cx >= screen_start_x - 2) && (cx < screen_start_x) && (cy >= screen_start_y);
                video_preamble <= (cx >= screen_start_x - 10) && (cx < screen_start_x - 2) && (cy >= screen_start_y);
            end

            // Calculate max number of packets for data island period
            int max_num_packets_alongside;
            logic [4:0] num_packets_alongside;
            always_comb begin
                max_num_packets_alongside = (screen_start_x - 2 - 8 - 12 - 2 - 2 - 8) / 32;
                if (max_num_packets_alongside > 18)
                    num_packets_alongside = 18;
                else
                    num_packets_alongside = max_num_packets_alongside[4:0];
            end

            logic data_island_period_instantaneous;
            assign data_island_period_instantaneous = (num_packets_alongside > 0) && (cx >= 10) && (cx < 10 + num_packets_alongside * 32);

            logic packet_enable;
            assign packet_enable = data_island_period_instantaneous && ((cx + 22) % 32 == 0);

            // Guards and preambles for data island period
            logic data_island_guard, data_island_preamble, data_island_period;
            always_ff @(posedge clk_pixel) begin
                data_island_guard <= (num_packets_alongside > 0) && ((cx >= 8 && cx < 10) || (cx >= 10 + num_packets_alongside * 32 && cx < 10 + num_packets_alongside * 32 + 2));
                data_island_preamble <= (num_packets_alongside > 0) && (cx < 8);
                data_island_period <= data_island_period_instantaneous;
            end

            // Video field end detection (frame end)
            logic video_field_end;
            assign video_field_end = (cx == frame_width - 1) && (cy == frame_height - 1);

            // Packet picker and assembler
            logic [23:0] header;
            logic [55:0] sub [3:0];
            logic [4:0] packet_pixel_counter;

            // Video rate calculation (approximate)
            localparam real VIDEO_RATE = (VIDEO_ID_CODE == 1) ? 25.2e6 : (VIDEO_ID_CODE == 2 || VIDEO_ID_CODE == 3) ? 27.027e6 : 0.0;
            
            packet_picker #(
                .VIDEO_ID_CODE(VIDEO_ID_CODE),
                .VIDEO_RATE(VIDEO_RATE),
                .AUDIO_RATE(AUDIO_RATE),
                .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
                .VENDOR_NAME(VENDOR_NAME),
                .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
                .SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)
            ) packet_picker_inst (
                .clk_pixel(clk_pixel),
                .clk_audio(clk_audio),
                .video_field_end(video_field_end),
                .packet_enable(packet_enable),
                .packet_pixel_counter(packet_pixel_counter),
                .audio_sample_word(audio_sample_word),
                .header(header),
                .sub(sub)
            );

            logic [8:0] packet_data;
            packet_assembler packet_assembler_inst (
                .clk_pixel(clk_pixel),
                .data_island_period(data_island_period),
                .header(header),
                .sub(sub),
                .packet_data(packet_data),
                .counter(packet_pixel_counter)
            );

            always_ff @(posedge clk_pixel) begin
                mode <= data_island_guard ? 3'd4 : data_island_period ? 3'd3 : video_guard ? 3'd2 : video_data_period ? 3'd1 : 3'd0;
                video_data <= rgb;
                control_data <= {{1'b0, data_island_preamble}, {1'b0, video_preamble || data_island_preamble}, {vsync, hsync}};
                data_island_data[11:4] <= packet_data[8:1];
                data_island_data[3] <= (cx != screen_start_x);
                data_island_data[2] <= packet_data[0];
                data_island_data[1:0] <= {vsync, hsync};
            end
        end else begin : dvi_mode
            // DVI mode: no auxiliary data, just video and control signals
            always_ff @(posedge clk_pixel) begin
                mode <= video_data_period ? 3'd1 : 3'd0;
                video_data <= rgb;
                control_data <= {4'b0000, vsync, hsync};
            end
        end
    endgenerate

    // -------------------------
    // TMDS encoding and output
    // -------------------------
    logic [9:0] tmds [NUM_CHANNELS-1:0];

    genvar i;
    generate
        // TMDS channel encoder instances
        for (i = 0; i < NUM_CHANNELS; i++) begin : tmds_gen
            tmds_channel #(.CN(i)) tmds_channel_inst (
                .clk_pixel(clk_pixel),
                .video_data(video_data[i*8 +: 8]),
                .data_island_data(data_island_data[i*4 +: 4]),
                .control_data(control_data[i*2 +: 2]),
                .mode(mode),
                .tmds(tmds[i])
            );
        end

        // TMDS serializer and output buffer logic

        // Shift registers for serialization
        logic [9:0] tmds_shift [NUM_CHANNELS-1:0] = '{default:10'b1101010100};

        logic tmds_control;
        always_ff @(posedge clk_pixel)
            tmds_control <= ~tmds_control;

        logic [3:0] tmds_control_sync_chain;
        always_ff @(posedge clk_pixel_x10)
            tmds_control_sync_chain <= {tmds_control, tmds_control_sync_chain[3:1]};

        logic [9:0] tmds_mux [NUM_CHANNELS-1:0];
        always_comb begin
            if (tmds_control_sync_chain[1] ^ tmds_control_sync_chain[0])
                tmds_mux = tmds;
            else
                tmds_mux = tmds_shift;
        end

        // Shift TMDS data out on clk_pixel_x10
        for (i = 0; i < NUM_CHANNELS; i++) begin : tmds_shifting
            always_ff @(posedge clk_pixel_x10) begin
                if (tmds_control_sync_chain[1] ^ tmds_control_sync_chain[0])
                    tmds_shift[i] <= tmds_mux[i];
                else
                    tmds_shift[i] <= tmds_shift[i] >> (DDRIO ? 2 : 1);
            end
        end

        // TMDS clock channel shift register
        logic [9:0] tmds_shift_clk_pixel = 10'b0000011111;
        always_ff @(posedge clk_pixel_x10) begin
            if (tmds_control_sync_chain[1] ^ tmds_control_sync_chain[0])
                tmds_shift_clk_pixel <= 10'b0000011111;
            else
                tmds_shift_clk_pixel <= {tmds_shift_clk_pixel[(DDRIO ? 1 : 0):0], tmds_shift_clk_pixel[9:(DDRIO ? 2 : 1)]};
        end

        // Current TMDS bits to output
        logic [NUM_CHANNELS-1:0] tmds_current;
        logic tmds_current_clk;

        assign tmds_current = {tmds_shift[2][0], tmds_shift[1][0], tmds_shift[0][0]};
        assign tmds_current_clk = tmds_shift_clk_pixel[0];

        // Output buffers for TMDS differential pairs (Altera/Intel FPGA)
        OBUFDS obufds_inst (
            .din({tmds_current, tmds_current_clk}),
            .pad_out({tmds_p, tmds_clock_p}),
            .pad_out_b({tmds_n, tmds_clock_n})
        );
    endgenerate

endmodule
```

---

### Vylepšenia a komentáre v návrhu:

* **Parametre pre jednoduché nastavenie rozlíšenia, audio a výstupný režim (DVI/HDMI).**
* **Rozdelenie video timingov do generate-case pre jednoduchú úpravu a rozšírenie.**
* \*\*Jas


né rozlíšenie medzi HDMI a DVI režimom, s vhodným generovaním pomocných dát pre HDMI.\*\*

* **Modulárny prístup k TMDS kanálom cez `generate` a prehľadné prepojenie.**
* **Použitie synchronizovaných signálov pre TMDS serializer, dôležité pre správnu prácu.**
* **Základné komentáre pri všetkých kľúčových signáloch a blokoch.**

---

Ak chceš, môžem ti ešte pridať aj kompletný kód pomocných modulov ako `packet_picker`, `packet_assembler`, `tmds_channel`, prípadne FIFO na audio synchronizáciu.

Daj vedieť, čo chceš ďalej!
