// tmds_channel.sv
// TMDS kanál pre kódovanie 8-bitového video dátového slova do 10-bit TMDS kódu
module tmds_channel #(
    parameter int CN = 0 // číslo kanálu (0=modrý,1=zelený,2=červený)
)(
    input  logic         clk_pixel,
    input  logic [7:0]   video_data,
    input  logic [3:0]   data_island_data,
    input  logic [1:0]   control_data,
    input  logic [2:0]   mode,
    output logic [9:0]   tmds
);

    // Interné premenné pre TMDS kódovanie
    logic [3:0] nb1s;         // počet 1-bitov v video_data
    logic [8:0] q_m;          // medzikódovanie (9-bit)
    logic [3:0] cnt_ones;     // pomocný počítadlo
    logic       invert_q_m;   // invertovanie bitov

    // Krok 1: Spočítať počet 1-bitov v video_data
    function automatic [3:0] count_ones(input logic [7:0] val);
        int i;
        count_ones = 0;
        for (i=0; i<8; i++) count_ones += val[i];
    endfunction

    always_comb begin
        nb1s = count_ones(video_data);
    end

    // Krok 2: TMDS 8b->9b kódovanie
    // - podľa TMDS špecifikácie (HDMI 1.4a)
    always_comb begin
        int i;
        q_m[0] = video_data[0];
        for (i=1; i<8; i++)
            q_m[i] = q_m[i-1] ^ video_data[i];

        // invertovanie ak počet 1-bitov väčší ako počet 0-bitov alebo rovnosť a q_m[0] == 0
        if ((nb1s > 4) || (nb1s == 4 && video_data[0] == 0))
            invert_q_m = 1;
        else
            invert_q_m = 0;
        
        for (i=0; i<8; i++)
            q_m[i] = invert_q_m ? ~q_m[i] : q_m[i];

        q_m[8] = ~invert_q_m; // pridanie invert bitu
    end

    // Krok 3: Výber výstupu podľa režimu (video, control, data island)
    always_comb begin
        case (mode)
            3'd0: tmds = 10'b1101010100; // predvolený stav (blanc)
            3'd1: tmds = {q_m[8], q_m[7:0], 1'b0}; // video_data kódovanie (simplified)
            3'd2: tmds = {8'b10101010, control_data}; // control kódovanie (simplified)
            3'd3: tmds = {2'b00, data_island_data, 5'b00000}; // data island kódovanie (simplified)
            3'd4: tmds = 10'b1111111111; // guard band (simplified)
            default: tmds = 10'b1101010100;
        endcase
    end

endmodule
