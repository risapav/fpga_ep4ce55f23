Skvelá otázka! Na vytvorenie **parametrizovateľného 7-segmentového multiplexera**, ktorý zvládne ľubovoľný počet digitov a dokáže ovládať aj bodku, je dobré použiť **generický parameter pre počet digitov** a posielať číslice (a prípadne aj bódky) ako pole vstupov.

---

## Návrh modulov so základnou štruktúrou:

```systemverilog
module SevenSegMux #(
    parameter int NUM_DIGITS = 3 // počet 7-segmentových číslic
)(
    input  logic            clk,
    input  logic            rstn,
    input  logic [3:0]      digits   [NUM_DIGITS], // číslice 0..9 pre každý digit
    input  logic            dot      [NUM_DIGITS], // bódka pre každý digit (1 = zapnutá)
    output logic [NUM_DIGITS-1:0] digit_sel,       // aktivácia číslice (aktívne nízke)
    output logic [7:0]      seg_out                   // 7-seg + DP
);

    // Počet taktov na jedno prepnutie číslice (napr. 1 ms)
    localparam int PIXEL_CLOCK_HZ = 50_000_000;  // napr. 50 MHz - daj parameter
    localparam int ONE_MS_TICKS = (PIXEL_CLOCK_HZ == 0) ? 1 : PIXEL_CLOCK_HZ / 1000;

    logic [$clog2(ONE_MS_TICKS)-1:0] ms_counter;
    logic [$clog2(NUM_DIGITS)-1:0] seg_sel_idx;

    // Počítadlo pre multiplexovanie číslic
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ms_counter <= 0;
            seg_sel_idx <= 0;
        end else if (ms_counter == ONE_MS_TICKS - 1) begin
            ms_counter <= 0;
            seg_sel_idx <= (seg_sel_idx == NUM_DIGITS - 1) ? 0 : seg_sel_idx + 1;
        end else begin
            ms_counter <= ms_counter + 1;
        end
    end

    // Výber aktívnej číslice (aktívne nízke)
    always_comb begin
        digit_sel = {NUM_DIGITS{1'b1}};
        digit_sel[seg_sel_idx] = 1'b0;
    end

    // 7-segmentový dekodér vrátane bodky (DP)
    function automatic [7:0] seg_decoder(input logic [3:0] val, input logic dot);
        case (val)
            4'h0: seg_decoder = 8'hC0;
            4'h1: seg_decoder = 8'hF9;
            4'h2: seg_decoder = 8'hA4;
            4'h3: seg_decoder = 8'hB0;
            4'h4: seg_decoder = 8'h99;
            4'h5: seg_decoder = 8'h92;
            4'h6: seg_decoder = 8'h82;
            4'h7: seg_decoder = 8'hF8;
            4'h8: seg_decoder = 8'h80;
            4'h9: seg_decoder = 8'h90;
            default: seg_decoder = 8'hFF;
        endcase
        // Pridanie bodky (LSB na DP)
        seg_decoder[0] = ~dot; // predpoklad common anode, DP na LSB, invertované
    endfunction

    // Výber segmentov pre aktuálnu číslicu
    always_comb begin
        seg_out = seg_decoder(digits[seg_sel_idx], dot[seg_sel_idx]);
    end

endmodule
```

---

## Ako to použiť v tvojej top module:

```systemverilog
logic [3:0] digits_array [2:0] = '{4'd1, 4'd2, 4'd3};
logic       dots_array   [2:0] = '{1'b0, 1'b1, 1'b0}; // napríklad dot zapnutý iba na druhom digit

logic [2:0] SMG_DIG;  // digit select (aktívne nízke)
logic [7:0] SMG_SEG;  // 7-segment + DP

SevenSegMux #(
    .NUM_DIGITS(3)
) seg_mux_inst (
    .clk(pixel_clk),
    .rstn(pix_rstn_sync),
    .digits(digits_array),
    .dot(dots_array),
    .digit_sel(SMG_DIG),
    .seg_out(SMG_SEG)
);
```

---

## Výhody

* Parametrizovateľný počet číslic,
* Podpora bódky pre každý digit zvlášť,
* Čistá a modulárna architektúra,
* Flexibilné vstupy (napr. môžeš pripojiť pole z inej logiky).

Ak chceš, môžem pomôcť aj s doplnením resetov, alebo so zapojením common cathode/anode podľa potreby. Ako sa ti to pozdáva?
