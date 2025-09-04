Výborne, pustíme sa teda do integrácie — pripravím základný HDMI modul, ktorý:

* Na základe pixelového časovania prepína medzi **video dátami** a **SPD infoframe**
* Použije predchádzajúce moduly: `spd_infoframe`, `data_island_controller`, `tmds_data_mux`, `tmds_channel`
* Bude mať jednoduchý stavový automat na spustenie SPD infoframe periodicky (napr. každú sekundu)

---

# Kompletný príklad základného HDMI modulu v SystemVerilog

```systemverilog
module hdmi_top #(
    parameter FRAME_WIDTH  = 800,
    parameter FRAME_HEIGHT = 525,
    parameter SCREEN_START_X = 160,
    parameter SCREEN_START_Y = 45,
    parameter PIXEL_CLK_FREQ_HZ = 25175000  // napr. 25.175 MHz pre 640x480 @60Hz
)(
    input  logic clk_pixel,
    input  logic reset_n,
    
    // Pixelová pozícia (cx, cy) - očakávame z vonkajšieho pixel countera
    input  logic [15:0] cx,
    input  logic [15:0] cy,
    
    // Video dáta (napríklad 8-bitová farba pre daný kanál)
    input  logic [7:0] video_data,
    
    // Výstup TMDS
    output logic [9:0] tmds_out
);

    // -------------------------------------------------------
    // 1. Data Island Controller: určuje, kedy idú video dáta vs infoframe
    logic video_period, data_island_period;
    data_island_controller #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .SCREEN_START_X(SCREEN_START_X),
        .SCREEN_START_Y(SCREEN_START_Y)
    ) dip_ctrl (
        .clk_pixel(clk_pixel),
        .cx(cx),
        .cy(cy),
        .video_data_period(video_period),
        .data_island_period(data_island_period)
    );

    // -------------------------------------------------------
    // 2. SPD infoframe generátor
    logic spd_start;
    logic [7:0] spd_data;
    logic spd_valid, spd_done;

    spd_infoframe spd_inst (
        .clk(clk_pixel),
        .start(spd_start),
        .data_out(spd_data),
        .valid(spd_valid),
        .done(spd_done)
    );

    // -------------------------------------------------------
    // 3. Stavový automat na spúšťanie SPD infoframe raz za sekundu
    typedef enum logic [1:0] {IDLE, SEND_SPD} spd_state_t;
    spd_state_t spd_state, spd_next;

    // Čítač pixelových taktov pre cca 1 sekundu
    localparam int ONE_SEC_CNT = PIXEL_CLK_FREQ_HZ;
    int sec_counter;

    always_ff @(posedge clk_pixel or negedge reset_n) begin
        if (!reset_n) begin
            sec_counter <= 0;
            spd_state <= IDLE;
            spd_start <= 0;
        end else begin
            // Čítač 1 sekundy
            if (sec_counter < ONE_SEC_CNT-1)
                sec_counter <= sec_counter + 1;
            else
                sec_counter <= 0;

            spd_state <= spd_next;

            // Štart SPD infoframe pri nábehu do SEND_SPD
            if (spd_next == SEND_SPD && spd_state == IDLE)
                spd_start <= 1;
            else
                spd_start <= 0;
        end
    end

    always_comb begin
        spd_next = spd_state;
        case (spd_state)
            IDLE: if (sec_counter == ONE_SEC_CNT-1) spd_next = SEND_SPD;
            SEND_SPD: if (spd_done) spd_next = IDLE;
        endcase
    end

    // -------------------------------------------------------
    // 4. Multiplexor dát: video_data alebo spd_data podľa režimu
    logic [7:0] mux_data;
    tmds_data_mux mux_inst (
        .video_data(video_data),
        .infoframe_data(spd_data),
        .video_mode(video_period && spd_state == IDLE), // video iba ak nie sme v SPD
        .data_out(mux_data)
    );

    // -------------------------------------------------------
    // 5. TMDS kanál - jednoduchý TMDS kódovač (placeholder)
    tmds_channel tmds_inst (
        .clk_pixel(clk_pixel),
        .data_in(mux_data),
        .tmds_out(tmds_out)
    );

endmodule
```

---

# Čo tento modul robí?

* **`data_island_controller`** rozpozná, či pixel je v aktívnej oblasti (video) alebo v blankingu (data island).
* **`spd_infoframe`** sa spustí raz za sekundu a pošle kompletný SPD infoframe bajt po bajte.
* **Multiplexor** vyberá video dáta, ak neodosielame infoframe, inak ide infoframe dátový tok.
* **`tmds_channel`** kóduje dáta do TMDS výstupu (tu iba placeholder).
* Stavový automat riadi spúšťanie SPD infoframe a prepínanie režimu.

---

Ak chceš, môžem pridať aj:

* Presnejší TMDS kódovač
* CRC32 generátor a jeho integráciu do infoframe
* Podporu ďalších HDMI infoframov (AVI, Audio)
* Riadenie časovania podľa HDMI špecifikácie (Data Island Period, Control Period, atď.)

---

Chceš pokračovať niektorým z týchto smerov? Alebo si želáš nejaké vysvetlenie ku kódu?
