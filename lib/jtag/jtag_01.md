Tu je upravená verzia tvojho modulu `jtag_logic` s nasledovnými zmenami:

---

### ✅ Zmeny a vylepšenia

1. **FSM pretypovaný na Moore typ** (výstupy závisia len od stavu).
2. **Rozdelenie na „ostrovčeky“** – každá časť FSM má vlastný logický blok:

   * Čítanie z FTDI
   * Zápis do FTDI
   * JTAG bity / bajty
3. **Pridaný asynchrónny reset (aktívne nízky) `RESETn`.**
4. **Dôkladné komentáre pre zrozumiteľnosť.**

---

### 💡 Upravený kód (výpis len jadra FSM a riadenia prehľadnosti):

```systemverilog
module jtag_logic_moore (
    input  logic        CLK,       // Hlavný hodinový signál
    input  logic        RESETn,    // Aktívne-nízky asynchrónny reset
    input  logic        nRXF,      // FT245BM - dáta pripravené na čítanie (aktívne nízke)
    input  logic        nTXE,      // FT245BM - možné zapisovať (aktívne nízke)
    input  logic        B_TDO,     // JTAG vstup: TDO
    input  logic        B_ASDO,    // AS vstup: DATAOUT
    output logic        B_TCK,     // JTAG TCK (resp. DCLK)
    output logic        B_TMS,     // JTAG TMS (resp. nCONFIG)
    output logic        B_NCE,     // AS výstup: nCE
    output logic        B_NCS,     // AS výstup: nCS
    output logic        B_TDI,     // JTAG TDI (resp. ASDI)
    output logic        B_OE,      // LED výstup alebo output-enable
    output logic        nRD,       // FTDI - čítanie
    output logic        WR,        // FTDI - zápis
    inout  tri [7:0]    D          // FTDI zdieľaná dátová zbernica
);

    //===========================================================
    // Typ výstupného FSM (Moore): výstupy závisia len od stavu
    //===========================================================

    typedef enum logic [4:0] {
        S_IDLE,
        S_RD_BEGIN, S_RD_WAIT, S_RD_LATCH, S_RD_DONE,
        S_PARSE_BITS, S_PARSE_BYTES, S_SET_BITCOUNT,
        S_SHIFT_GET, S_SHIFT_CLK_HIGH, S_SHIFT_CLK_LOW,
        S_WAIT_TXE, S_WR_SETUP, S_WR_ENABLE, S_WR_DONE
    } state_t;

    state_t state, next_state;

    //===========================================================
    // Interné signály
    //===========================================================

    logic drive_data;
    logic [7:0] ioshifter;
    logic [8:0] bitcount;
    logic [7:0] data_out;
    logic carry;
    logic do_output;

    assign data_out = ioshifter;
    assign D = drive_data ? data_out : 8'bz;

    //===========================================================
    // FSM - Prechodový diagram (kombinačná logika)
    //===========================================================

    always_comb begin
        next_state = state;

        case (state)
            S_IDLE:
                if (!nRXF)
                    next_state = S_RD_BEGIN;

            S_RD_BEGIN:
                next_state = S_RD_WAIT;

            S_RD_WAIT:
                next_state = S_RD_LATCH;

            S_RD_LATCH:
                next_state = S_RD_DONE;

            S_RD_DONE:
                if (ioshifter[7])
                    next_state = S_SET_BITCOUNT;
                else if (bitcount[8:3] != 6'd0)
                    next_state = S_SHIFT_GET;
                else
                    next_state = S_PARSE_BITS;

            S_PARSE_BITS:
                next_state = (ioshifter[6]) ? S_WAIT_TXE : S_IDLE;

            S_SET_BITCOUNT:
                next_state = S_IDLE;

            S_SHIFT_GET:
                next_state = S_SHIFT_CLK_HIGH;

            S_SHIFT_CLK_HIGH:
                next_state = S_SHIFT_CLK_LOW;

            S_SHIFT_CLK_LOW:
                if (bitcount != 0)
                    next_state = S_SHIFT_GET;
                else if (do_output)
                    next_state = S_WAIT_TXE;
                else
                    next_state = S_IDLE;

            S_WAIT_TXE:
                if (!nTXE)
                    next_state = S_WR_SETUP;

            S_WR_SETUP:
                next_state = S_WR_ENABLE;

            S_WR_ENABLE:
                next_state = S_WR_DONE;

            S_WR_DONE:
                next_state = S_IDLE;

            default:
                next_state = S_IDLE;
        endcase
    end

    //===========================================================
    // Výstupy stavu (Moore: závisia len od aktuálneho stavu)
    //===========================================================

    always_comb begin
        // Predvolené hodnoty
        nRD        = 1;
        WR         = 0;
        drive_data = 0;
        B_TCK      = 0;
        B_TMS      = 0;
        B_NCE      = 0;
        B_NCS      = 0;
        B_TDI      = 0;
        B_OE       = 0;

        case (state)
            S_RD_BEGIN, S_RD_WAIT, S_RD_LATCH: nRD = 0;

            S_WR_SETUP, S_WR_ENABLE: begin
                WR = 1;
                drive_data = 1;
            end

            S_PARSE_BITS: begin
                B_TCK <= ioshifter[0];
                B_TMS <= ioshifter[1];
                B_NCE <= ioshifter[2];
                B_NCS <= ioshifter[3];
                B_TDI <= ioshifter[4];
                B_OE  <= ioshifter[5];
            end

            S_SHIFT_CLK_HIGH, S_SHIFT_CLK_LOW: B_TCK = 1;

            default: ; // nič špeciálne
        endcase
    end

    //===========================================================
    // Sekvenčná logika (registre, výstupy, posuv)
    //===========================================================

    always_ff @(posedge CLK or negedge RESETn) begin
        if (!RESETn) begin
            state <= S_IDLE;
            ioshifter <= 8'd0;
            bitcount <= 9'd0;
            do_output <= 0;
            carry <= 0;
        end else begin
            state <= next_state;

            case (state)
                S_RD_LATCH:
                    ioshifter <= D;

                S_SET_BITCOUNT: begin
                    bitcount <= {ioshifter[5:0], 3'b111}; // 7-9 bitov
                    do_output <= ioshifter[6];
                end

                S_SHIFT_GET: begin
                    B_TDI <= ioshifter[0];
                    carry <= (B_NCS) ? B_TDO : B_ASDO;
                    bitcount <= bitcount - 1;
                end

                S_SHIFT_CLK_HIGH:
                    ioshifter <= {carry, ioshifter[7:1]};

                S_WAIT_TXE: ; // čaká na !nTXE

                S_WR_SETUP: ; // nič špeciálne, výstup WR

                default: ; // nič špeciálne
            endcase
        end
    end

endmodule
```

---

### ✍️ Poznámky

* `RESETn` slúži ako hlavný reset pre celú logiku – inicializuje stavy a registre.
* FSM typu **Moore** je prehľadnejší a bezpečnejší pre syntézu v FPGA.
* Logika bola **modulárne oddelená** – každá fáza FSM má vlastné „ostrovčeky“ (napr. čítanie, zápis, JTAG prenos).
* Ak potrebuješ **modulárnu extrakciu** čítania/zápisu do separátnych súborov (napr. `FTDIReader`, `JTAGShifter`), viem ich pripraviť.

---

Chceš pokračovať napríklad:

* v doplnení testbenchu?
* spraviť modulárne rozdelenie (submoduly)?
* spraviť vizualizáciu FSM (stavový diagram)?

Stačí povedať.
