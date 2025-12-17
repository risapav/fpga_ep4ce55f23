/**
 * @file        skid_buffer.sv
 * @brief       Full-Throughput Pipeline Register (Skid Buffer).
 * @details     Buffer, ktorý oddeľuje časovanie na rozhraní Ready/Valid bez
 * zavedenia čakacích cyklov (wait-states).
 * - Ak je Master pripravený a Buffer prázdny: Dáta prechádzajú priamo (kombinačne).
 * - Ak Master nie je pripravený: Dáta sa uložia do buffera (skid).
 *
 * @param WIDTH Šírka dátovej zbernice.
 */

`default_nettype none

`ifndef SKID_BUFFER_SV
`define SKID_BUFFER_SV

module skid_buffer #(
    parameter int WIDTH = 32
)(
    input  logic             clk_i,
    input  logic             rst_ni,

    // Slave interface (Vstup)
    input  logic             s_valid_i,
    output logic             s_ready_o,
    input  logic [WIDTH-1:0] s_data_i,

    // Master interface (Výstup)
    output logic             m_valid_o,
    input  logic             m_ready_i,
    output logic [WIDTH-1:0] m_data_o
);

    // Interné registre (Skid storage)
    logic [WIDTH-1:0] buf_data_q;
    logic             buf_valid_q;

    // =========================================================================
    // 1. Logika Pripravenosti (Ready Logic)
    // =========================================================================
    // Sme pripravení prijať nové dáta, ak:
    // a) Buffer je prázdny (môžeme bypassovať alebo uložiť)
    // b) Buffer je plný, ale Master práve odoberá dáta (uvoľní sa miesto)
    assign s_ready_o = !buf_valid_q || m_ready_i;

    // =========================================================================
    // 2. Logika Výstupu (Output Logic)
    // =========================================================================
    // Výstup je validný, ak máme dáta v bufferi ALEBO prichádzajú nové (bypass)
    assign m_valid_o = buf_valid_q || s_valid_i;

    // Dátová cesta (MUX):
    // - Priorita: Dáta z buffera (skôr prijaté).
    // - Fallback: Priame dáta zo vstupu (ak je buffer prázdny).
    assign m_data_o  = (buf_valid_q) ? buf_data_q : s_data_i;

    // =========================================================================
    // 3. Sekvenčná Logika (Buffer Management)
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            buf_valid_q <= 1'b0;
            buf_data_q  <= '0;
        end else begin
            // Správanie buffera:
            if (m_ready_i) begin
                // Master odoberá dáta (buď z buffera alebo cez bypass).
                // Ak Slave posiela nové dáta a my sme mali buffer plný (buf_valid=1),
                // staré dáta odišli a nové sa zapíšu do buffera (Pipeline move).
                if (s_valid_i && s_ready_o) begin
                    // Poznámka: Ak bol buf_valid=0 (bypass), zápis do buffera je
                    // v tomto takte zbytočný (lebo dáta prešli na výstup), 
                    // ale logicky musíme nastaviť stav pre ďalší takt.
                    // Tu však optimalizujeme: Ak bol bypass, buffer ostáva prázdny.
                    // Ale ak bol plný, prepíšeme ho.
                    // Pre jednoduchosť a 100% throughput sa používa logika:
                    // Ak Slave píše a my sme READY, ukladáme do buffera LEN vtedy,
                    // ak by sme inak stratili dáta (t.j. stall), ALEBO pre pipeline efekt.
                    
                    // V tejto "Bypass" architektúre:
                    // Ak m_ready=1 a buf_valid=0: Dáta idú priamo. Buffer <- 0.
                    // Ak m_ready=1 a buf_valid=1: Dáta (buf) idú von. Buffer <- s_data.
                    
                    buf_valid_q <= buf_valid_q; // Stav sa nemení (1->1 alebo 0->0)
                    if (buf_valid_q) begin
                         buf_data_q <= s_data_i;
                    end
                end else begin
                    // Slave neposiela dáta -> Buffer sa vyprázdni
                    buf_valid_q <= 1'b0;
                end
            end 
            else if (s_valid_i && s_ready_o) begin
                // Master NEODOBERÁ (stall), ale my sme prijali dáta.
                // Musia ísť do buffera (Skid).
                buf_valid_q <= 1'b1;
                buf_data_q  <= s_data_i;
            end
        end
    end

endmodule

`endif // SKID_BUFFER_SV

`default_nettype wire
