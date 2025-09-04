//================================================================
// Knižnica generátorov obrazu pre AXI4-Stream
// Verzia: 2.0 (Optimalizovaná)
//
// === Popis Zmien ===
// 1. FrameStreamer: Opravená logika generovania TLAST tak, aby zodpovedala
//    AXI-Stream video protokolu (TLAST len na konci snímky).
// 2. CheckerPattern: Ponechaná optimalizácia s bitovým posunom namiesto
//    pomalého delenia.
// 3. Hlavné Generátory: Moduly CheckerboardGenerator a GradientGenerator
//    boli architektonicky prepracované. Pridaný bol výstupný register
//    (pipeline stage), ktorý odstraňuje dlhé kombinačné cesty a zaručuje
//    splnenie časových požiadaviek pri vysokých frekvenciách.
//
`default_nettype none

import axi_pkg::*; // Nevyhnutný import pre prístup k AXI definíciám

//================================================================
// Modul: FrameStreamer
// Účel: Generuje raster-scan súradnice (x, y) a AXI-Stream riadiace signály.
//================================================================
module FrameStreamer #(
    parameter int H_RES = 1024,
    parameter int V_RES = 768,
    parameter int DATA_WIDTH = 16,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int ID_WIDTH   = 0,
    parameter int DEST_WIDTH = 0
)(
    input  logic         clk,
    input  logic         rstn,
    output logic [11:0]  x,
    output logic [11:0]  y,
    output logic         TVALID,
    input  logic         TREADY,
    output logic [USER_WIDTH-1:0] TUSER,
    output logic         TLAST,
    output logic [KEEP_WIDTH-1:0] TKEEP,
    output logic [ID_WIDTH-1:0]   TID,
    output logic [DEST_WIDTH-1:0] TDEST
);
    logic [11:0] x_reg, y_reg;
    assign x = x_reg;
    assign y = y_reg;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            x_reg  <= '0;
            y_reg  <= '0;
            TVALID <= 1'b0;
            TUSER  <= '0;
            TLAST  <= 1'b0;
        end else begin
            // Po resete je streamer vždy pripravený posielať dáta
            TVALID <= 1'b1;

            // Inkrementujeme súradnice len pri úspešnom prenose dát
            if (TVALID && TREADY) begin
                // TUSER (Start-of-Frame) je aktívny len pre prvý pixel (0,0)
                TUSER <= (x_reg == 0 && y_reg == 0);

                // OPRAVENÉ: TLAST (End-of-Frame) je aktívny len pre posledný pixel snímky
                TLAST <= (x_reg == H_RES - 1) && (y_reg == V_RES - 1);
                
                if (x_reg == H_RES - 1) begin
                    x_reg <= 0;
                    y_reg <= (y_reg == V_RES - 1) ? 0 : y_reg + 1;
                end else begin
                    x_reg <= x_reg + 1;
                end
            end
        end
    end

    // Predvolené hodnoty pre nepoužívané signály
    generate if (KEEP_WIDTH > 0) assign TKEEP = '1; else assign TKEEP = '0; endgenerate
    generate if (ID_WIDTH > 0)   assign TID   = '0; else assign TID = '0; endgenerate
    generate if (DEST_WIDTH > 0) assign TDEST = '0; else assign TDEST = '0; endgenerate

endmodule


//================================================================
// Modul: CheckerPattern (Verzia 2.1 - Opravená syntax pre staršie nástroje)
//================================================================
module CheckerPattern #(
    parameter int H_RES       = 1024,
    parameter int V_RES       = 768,
    parameter int CELL_W_BITS = 7, 
    parameter int CELL_H_BITS = 6, 
    parameter logic [15:0] COLOR_1 = 16'hFFFF,
    parameter logic [15:0] COLOR_2 = 16'h0000
)(
    input  logic [11:0]  x,
    input  logic [11:0]  y,
    output logic [15:0]  color
);
    logic cell_x_is_odd;
    logic cell_y_is_odd;
    
    // ---- OPRAVA SYNTAXE ----
    // Krok 1: Výsledok bitového posunu uložíme do pomocných signálov.
    // Šírka musí zodpovedať šírke vstupných signálov x a y.
    logic [11:0] shifted_x;
    logic [11:0] shifted_y;
    
    assign shifted_x = x >> CELL_W_BITS;
    assign shifted_y = y >> CELL_H_BITS;

    // Krok 2: Až teraz vyberieme najnižší bit z pomocných signálov.
    assign cell_x_is_odd = shifted_x[0];
    assign cell_y_is_odd = shifted_y[0];

    // Finálna farba zostáva rovnaká.
    assign color = (cell_x_is_odd ^ cell_y_is_odd) ? COLOR_1 : COLOR_2;
endmodule


//================================================================
// Modul: CheckerboardGenerator (Verzia 2.0 - Výstup je registrovaný)
// Účel: Spája streamer a pattern do funkčného generátora s AXI-Stream výstupom.
//================================================================
module CheckerboardGenerator #(
    // ... Parametre ...
    parameter int DATA_WIDTH = 16,
    parameter int USER_WIDTH = 1,
    parameter int ID_WIDTH   = 0,
    parameter int DEST_WIDTH = 0,
    parameter int H_RES      = 1024,
    parameter int V_RES      = 768
)(
    input  logic         clk,
    input  logic         rstn,
    axi4s_if.master    m_axis
);
    // Interné signály na prepojenie sub-modulov
    logic        streamer_tvalid, streamer_tready, streamer_tuser, streamer_tlast;
    logic [11:0] x, y;
    logic [15:0] pattern_color;

    // Inštancia generátora súradníc a AXI riadenia
    FrameStreamer #(
        .H_RES(H_RES), .V_RES(V_RES), .DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)
    ) streamer (
        .clk(clk), .rstn(rstn),
        .x(x), .y(y),
        .TVALID(streamer_tvalid), .TREADY(streamer_tready),
        .TUSER(streamer_tuser), .TLAST(streamer_tlast)
        // Ostatné AXI signály (TKEEP, atď.) sú nepodstatné a nastavené na default
    );

    // Inštancia generátora vzoru (šachovnice)
    CheckerPattern pattern (
        .x(x), .y(y), .color(pattern_color)
    );

    // --- KĽÚČOVÁ OPRAVA ČASOVANIA: REGISTROVANÝ VÝSTUP ---
    // Namiesto priameho priradenia `assign m_axis.TDATA = pattern_color;` použijeme
    // registračný stupeň (pipeline), ktorý rozdelí dlhú kombinačnú cestu na dve kratšie.
    // Týmto sa zabezpečí splnenie časovania aj pri vysokých frekvenciách.
    always_ff @(posedge clk) begin
        if (!rstn) begin
            m_axis.TVALID <= 1'b0;
            m_axis.TDATA  <= '0;
            m_axis.TLAST  <= 1'b0;
            m_axis.TUSER  <= 1'b0;
        end else begin
            // Preberáme platnosť dát zo streameru
            m_axis.TVALID <= streamer_tvalid;
            
            // Ak sú dáta platné, zaregistrujeme všetky signály
            if(streamer_tvalid) begin
                m_axis.TDATA <= pattern_color; // Zaregistrujeme vypočítanú farbu
                m_axis.TLAST <= streamer_tlast;
                m_axis.TUSER <= streamer_tuser;
            end
        end
    end
    
    // Signál TREADY posielame späť do streameru. Ak je náš odberateľ pripravený, aj my sme.
    assign streamer_tready = m_axis.TREADY;

endmodule


//================================================================
// Modul: GradientPattern
// Účel: Kombinačne vypočíta farbu pre diagonálny prechod.
//================================================================
module GradientPattern(
    input  logic [11:0]  x,
    input  logic [11:0]  y,
    output logic [15:0]  color
);
    logic [12:0] sum;

    // Logika je dostatočne jednoduchá a rýchla, optimalizácia nie je nutná.
    assign sum = x + y;
    assign color = {sum[10:6], sum[9:4], sum[8:3]};
endmodule


//================================================================
// Modul: GradientGenerator (Verzia 2.0 - Výstup je registrovaný)
// Účel: Spája streamer a pattern do funkčného generátora s AXI-Stream výstupom.
//================================================================
module GradientGenerator #(
    // ... Parametre ...
    parameter int DATA_WIDTH = 16,
    parameter int USER_WIDTH = 1,
    parameter int ID_WIDTH   = 0,
    parameter int DEST_WIDTH = 0,
    parameter int H_RES = 1024,
    parameter int V_RES = 768
)(
    input  logic         clk,
    input  logic         rstn,
    axi4s_if.master    m_axis
);
    // Interné signály na prepojenie sub-modulov
    logic        streamer_tvalid, streamer_tready, streamer_tuser, streamer_tlast;
    logic [11:0] x, y;
    logic [15:0] pattern_color;

    // Inštancia generátora súradníc a AXI riadenia
    FrameStreamer #(
        .H_RES(H_RES), .V_RES(V_RES), .DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)
    ) streamer (
        .clk(clk), .rstn(rstn),
        .x(x), .y(y),
        .TVALID(streamer_tvalid), .TREADY(streamer_tready),
        .TUSER(streamer_tuser), .TLAST(streamer_tlast)
    );

    // Inštancia generátora vzoru (prechod)
    GradientPattern pattern (
        .x(x), .y(y), .color(pattern_color)
    );

    // Rovnaká oprava časovania ako pri CheckerboardGenerator
    always_ff @(posedge clk) begin
        if (!rstn) begin
            m_axis.TVALID <= 1'b0;
            m_axis.TDATA  <= '0;
            m_axis.TLAST  <= 1'b0;
            m_axis.TUSER  <= 1'b0;
        end else begin
            m_axis.TVALID <= streamer_tvalid;
            
            if(streamer_tvalid) begin
                m_axis.TDATA <= pattern_color;
                m_axis.TLAST <= streamer_tlast;
                m_axis.TUSER <= streamer_tuser;
            end
        end
    end
    
    assign streamer_tready = m_axis.TREADY;

endmodule
