//=============================================================================
// axi_interfaces.sv - Definície AXI interface pre rôzne protokoly
//
// Tento súbor obsahuje všetky `interface` definície a mal by byť
// zahrnutý v top-level module cez `` `include "axi_interfaces.sv" ``.
// Verzia: 3.1
//
// === Popis a vylepšenia ===
// 1. OPRAVA AXI4-FULL: V rozhraní `axi4_if` bola opravená chyba, kde signály
//    AWLEN a ARLEN ignorovali parameter LEN_WIDTH. Teraz je rozhranie
//    plne a správne parametrizovateľné.
//
// 2. DOPLNENIE KOMENTÁROV: Boli pridané a vylepšené komentáre pre lepšiu
//    čitateľnosť a dokumentáciu kódu.
//
// 3. ODDIELENIE OD BALÍČKA: Súbor naďalej obsahuje len `interface` definície
//    pre maximálnu kompatibilitu so syntetizačnými nástrojmi.
//=============================================================================

`ifndef AXI_INTERFACES_SV
`define AXI_INTERFACES_SV

//================================================================
// AXI4-Lite Interface
// Zjednodušená adresná zbernica pre prístup k registrom.
// Nepodporuje burst prenosy (viacnásobné prenosy na jednu adresu).
//================================================================
interface axi4lite_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic ACLK,    // Globálny hodinový signál
    input logic ARESETn  // Globálny asynchrónny reset, aktívny v nule
);
    // Šírka WSTRB sa automaticky odvodzuje z DATA_WIDTH.
    // Každý bit v WSTRB zodpovedá jednému bajtu v WDATA.
    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // --- Write Address Channel (AW) ---
    logic [ADDR_WIDTH-1:0] AWADDR;  // Adresa pre zápis
    logic [2:0]            AWPROT;  // Typ ochrany (napr. privilegovaný, bezpečný prístup)
    logic                  AWVALID; // Master signalizuje platnú adresu a riadiace signály
    logic                  AWREADY; // Slave signalizuje pripravenosť prijať adresu

    // --- Write Data Channel (W) ---
    logic [DATA_WIDTH-1:0] WDATA;   // Zapisované dáta
    logic [STRB_WIDTH-1:0] WSTRB;   // Maska bajtov (určuje, ktoré bajty v WDATA sú platné)
    logic                  WVALID;  // Master signalizuje platné dáta
    logic                  WREADY;  // Slave signalizuje pripravenosť prijať dáta

    // --- Write Response Channel (B) ---
    logic [1:0]            BRESP;   // Odpoveď na zápis (OKAY, EXOKAY, SLVERR, DECERR)
    logic                  BVALID;  // Slave signalizuje platnú odpoveď
    logic                  BREADY;  // Master signalizuje pripravenosť prijať odpoveď

    // --- Read Address Channel (AR) ---
    logic [ADDR_WIDTH-1:0] ARADDR;  // Adresa pre čítanie
    logic [2:0]            ARPROT;
    logic                  ARVALID; // Master signalizuje platnú adresu
    logic                  ARREADY; // Slave signalizuje pripravenosť prijať adresu

    // --- Read Data Channel (R) ---
    logic [DATA_WIDTH-1:0] RDATA;   // Čítané dáta
    logic [1:0]            RRESP;   // Odpoveď na čítanie (status operácie)
    logic                  RVALID;  // Slave signalizuje platné dáta a odpoveď
    logic                  RREADY;  // Master signalizuje pripravenosť prijať dáta

    // Modport definuje smer signálov z pohľadu Master zariadenia
    modport master (
        output AWVALID, AWADDR, AWPROT,
               WVALID, WDATA, WSTRB,
               BREADY,
               ARVALID, ARADDR, ARPROT,
               RREADY,
        input  AWREADY, WREADY, BVALID, BRESP,
               ARREADY, RVALID, RDATA, RRESP
    );

    // Modport definuje smer signálov z pohľadu Slave zariadenia
    modport slave (
        input  AWVALID, AWADDR, AWPROT,
               WVALID, WDATA, WSTRB,
               BREADY,
               ARVALID, ARADDR, ARPROT,
               RREADY,
        output AWREADY, WREADY, BVALID, BRESP,
               ARREADY, RVALID, RDATA, RRESP
    );
endinterface


//================================================================
// AXI4-Full Interface
// Kompletná adresná zbernica s podporou burst prenosov,
// ID transakcií a out-of-order spracovania.
//================================================================
interface axi4_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int LEN_WIDTH  = 8
)(
    input logic ACLK,
    input logic ARESETn
);
    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // --- Write Address Channel ---
    logic [ID_WIDTH-1:0]   AWID;
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [LEN_WIDTH-1:0]  AWLEN;   // Dĺžka burstu (počet prenosov - 1). OPRAVENÉ
    logic [2:0]            AWSIZE;  // Veľkosť jedného prenosu (napr. 2^AWSIZE bajtov)
    logic [1:0]            AWBURST; // Typ burstu (FIXED, INCR, WRAP)
    logic                  AWVALID;
    logic                  AWREADY;

    // --- Write Data Channel ---
    logic [DATA_WIDTH-1:0] WDATA;
    logic [STRB_WIDTH-1:0] WSTRB;
    logic                  WLAST;   // Signalizuje posledný prenos v burst zápise
    logic                  WVALID;
    logic                  WREADY;

    // --- Write Response Channel ---
    logic [ID_WIDTH-1:0]   BID;     // ID transakcie, na ktorú sa odpovedá
    logic [1:0]            BRESP;
    logic                  BVALID;
    logic                  BREADY;

    // --- Read Address Channel ---
    logic [ID_WIDTH-1:0]   ARID;
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [LEN_WIDTH-1:0]  ARLEN;   // Dĺžka burstu (počet prenosov - 1). OPRAVENÉ
    logic [2:0]            ARSIZE;
    logic [1:0]            ARBURST;
    logic                  ARVALID;
    logic                  ARREADY;

    // --- Read Data Channel ---
    logic [ID_WIDTH-1:0]   RID;
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]            RRESP;
    logic                  RLAST;   // Signalizuje posledný prenos v burst čítaní
    logic                  RVALID;
    logic                  RREADY;

    modport master (
        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID,
               WDATA, WSTRB, WLAST, WVALID,
               BREADY,
               ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID,
               RREADY,
        input  AWREADY, WREADY, BID, BRESP, BVALID,
               ARREADY, RID, RDATA, RRESP, RLAST, RVALID
    );

    modport slave (
        input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID,
               WDATA, WSTRB, WLAST, WVALID,
               BREADY,
               ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID,
               RREADY,
        output AWREADY, WREADY, BID, BRESP, BVALID,
               ARREADY, RID, RDATA, RRESP, RLAST, RVALID
    );
endinterface


//================================================================
// AXI4-Stream Interface
// Neadresovaná, dátovo-orientovaná prúdová zbernica.
// Používa jednoduchý valid/ready handshake pre riadenie toku.
//================================================================
interface axi4s_if #(
    parameter int DATA_WIDTH = 16,
    parameter int USER_WIDTH = 1,
    // Parametre pre voliteľné signály. Šírka 0 ich efektívne odstráni.
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int ID_WIDTH   = 0,
    parameter int DEST_WIDTH = 0
)(
    input logic ACLK,
    input logic ARESETn
);

    // Hlavné signály pre riadenie toku a dáta
    logic                  TVALID; // Master signalizuje platné dáta
    logic                  TREADY; // Slave signalizuje pripravenosť prijať dáta
    logic [DATA_WIDTH-1:0] TDATA;  // Dátový payload

    // Voliteľné signály
    logic [KEEP_WIDTH-1:0] TKEEP; // Maska bajtov, podobná WSTRB
    logic                  TLAST; // Signalizuje posledné dáta v pakete/rámci
    logic [USER_WIDTH-1:0] TUSER; // Používateľom definovaný postranný signál
    logic [ID_WIDTH-1:0]   TID;   // Identifikátor prúdu
    logic [DEST_WIDTH-1:0] TDEST; // Cieľový identifikátor pre routing

    modport master (
        output TVALID, TDATA, TLAST, TKEEP, TUSER, TID, TDEST,
        input  TREADY
    );

    modport slave (
        input  TVALID, TDATA, TLAST, TKEEP, TUSER, TID, TDEST,
        output TREADY
    );

endinterface

`endif // AXI_INTERFACES_SV
