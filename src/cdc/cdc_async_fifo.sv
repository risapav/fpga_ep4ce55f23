/**
 * @brief       Asynchrónny FIFO buffer s oddelenými hodinovými doménami pre zápis a čítanie.
 * @details     Modul implementuje FIFO s nezávislými hodinovými doménami zápisu a čítania,
 *              ktorý zabezpečuje správnu synchronizáciu medzi doménami pomocou gray kódu a
 *              dvojstupňových synchronizátorov. Podporuje signály almost_full a almost_empty
 *              s nastaviteľnými prahmi, vrátane detekcie pretečenia a podtečenia.
 *
 * @param[in]   DATA_WIDTH                Šírka dátového slova vo FIFO (bity).
 * @param[in]   DEPTH                     Hĺbka FIFO, počet uložených prvkov.
 * @param[in]   ALMOST_FULL_THRESHOLD     Prah pre signál almost_full (počet voľných miest).
 * @param[in]   ALMOST_EMPTY_THRESHOLD    Prah pre signál almost_empty (počet obsadených miest).
 * @param[in]   ADDR_WIDTH                Počet bitov na adresovanie FIFO (vypočítané z DEPTH).
 *
 * @input       wr_clk_i                  Hodinový signál zápisovej domény.
 * @input       wr_rst_ni                 Asynchrónny reset zápisovej domény, aktívny v log.0.
 * @input       wr_en_i                   Povolenie zápisu dát do FIFO.
 * @input       wr_data_i                 Dáta pre zápis do FIFO.
 *
 * @output      full_o                    Indikácia plného FIFO v zápisovej doméne.
 * @output      almost_full_o             Indikácia takmer plného FIFO.
 * @output      overflow_o                Indikácia pretečenia FIFO pri zápise.
 *
 * @input       rd_clk_i                  Hodinový signál čítacej domény.
 * @input       rd_rst_ni                 Asynchrónny reset čítacej domény, aktívny v log.0.
 * @input       rd_en_i                   Povolenie čítania dát z FIFO.
 *
 * @output      rd_data_o                 Dáta čítané z FIFO.
 * @output      empty_o                   Indikácia prázdneho FIFO v čítacej doméne.
 * @output      almost_empty_o            Indikácia takmer prázdneho FIFO.
 * @output      underflow_o               Indikácia podtečenia FIFO pri čítaní.
 *
 * @example
 *   cdc_async_fifo #(
 *     .DATA_WIDTH(32),
 *     .DEPTH(512),
 *     .ALMOST_FULL_THRESHOLD(32),
 *     .ALMOST_EMPTY_THRESHOLD(32)
 *   ) u_async_fifo (
 *     .wr_clk_i(wr_clk),
 *     .wr_rst_ni(wr_rst_n),
 *     .wr_en_i(wr_en),
 *     .wr_data_i(wr_data),
 *     .full_o(full),
 *     .almost_full_o(almost_full),
 *     .overflow_o(overflow),
 *     .rd_clk_i(rd_clk),
 *     .rd_rst_ni(rd_rst_n),
 *     .rd_en_i(rd_en),
 *     .rd_data_o(rd_data),
 *     .empty_o(empty),
 *     .almost_empty_o(almost_empty),
 *     .underflow_o(underflow)
 *   );
 */



`ifndef ASYNCFIFO
`define ASYNCFIFO

`default_nettype none

module cdc_async_fifo #(
  parameter int unsigned DATA_WIDTH = 16,
  parameter int unsigned DEPTH      = 1024,
  parameter int unsigned ALMOST_FULL_THRESHOLD  = 16,
  parameter int unsigned ALMOST_EMPTY_THRESHOLD = 16,
  // Počet bitov potrebných pre adresovanie hĺbky FIFO
  parameter int unsigned ADDR_WIDTH = $clog2(DEPTH);
)(
  // Zápisová doména (write clock domain)
  input  logic               wr_clk_i,
  input  logic               wr_rst_ni,
  input  logic               wr_en_i,
  input  logic [DATA_WIDTH-1:0] wr_data_i,
  output logic               full_o,
  output logic               almost_full_o,
  output logic               overflow_o,

  // Čítacia doména (read clock domain)
  input  logic               rd_clk_i,
  input  logic               rd_rst_ni,
  input  logic               rd_en_i,
  output logic [DATA_WIDTH-1:0] rd_data_o,
  output logic               empty_o,
  output logic               almost_empty_o,
  output logic               underflow_o
);

  // Pamäť FIFO - pole s veľkosťou DEPTH a šírkou DATA_WIDTH
  // Atribút `ramstyle` môže pomôcť syntetizátoru vybrať správny typ pamäte
  (* ramstyle = "no_rw_check" *)
  logic [DATA_WIDTH-1:0] mem [DEPTH];

  // --- Pointery a synchronizované signály ---
  logic [ADDR_WIDTH:0] wr_ptr_bin, rd_ptr_bin;
  logic [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
  logic [ADDR_WIDTH:0] wr_ptr_gray_rdclk_sync;
  logic [ADDR_WIDTH:0] rd_ptr_gray_wrclk_sync;

  // Synchronizované reset signály pre obe domény
  wire wr_rstn_sync, rd_rstn_sync;

  //================================================================
  // Synchronizácia resetov (predpokladá existenciu modulu `cdc_reset_synchronizer`)
  //================================================================
  cdc_reset_synchronizer wr_reset_sync_inst (
    .clk_i(wr_clk_i),
    .rst_ni(wr_rst_ni),
    .rst_no(wr_rstn_sync)
  );

  cdc_reset_synchronizer rd_reset_sync_inst (
    .clk_i(rd_clk_i),
    .rst_ni(rd_rst_ni),
    .rst_no(rd_rstn_sync)
  );

  //================================================================
  // Pomocné funkcie pre konverziu medzi binárnym a gray kódom
  //================================================================
  function automatic logic [ADDR_WIDTH:0] bin2gray(input logic [ADDR_WIDTH:0] bin);
    return (bin >> 1) ^ bin;
  endfunction

  function automatic logic [ADDR_WIDTH:0] gray2bin(input logic [ADDR_WIDTH:0] gray);
    logic [ADDR_WIDTH:0] bin;
    bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
    for (int i = ADDR_WIDTH - 1; i >= 0; i--) begin
      bin[i] = bin[i+1] ^ gray[i];
    end
    return bin;
  endfunction

  //================================================================
  // ==                     Zápisová doména (wr_clk)               ==
  //================================================================
  always_ff @(posedge wr_clk_i) begin
    if (!wr_rstn_sync) begin
      wr_ptr_bin  <= '0;
      wr_ptr_gray <= '0;
    end else if (wr_en_i && !full_o) begin
      // Zápis dát do pamäte na aktuálnu adresu
      mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data_i;
      // Inkrementácia binárneho pointera pre ďalší cyklus
      wr_ptr_bin  <= wr_ptr_bin + 1;
      // Aktualizácia gray pointera na základe budúcej hodnoty binárneho
      wr_ptr_gray <= bin2gray(wr_ptr_bin + 1);
    end
  end

  // Synchronizácia čítacieho pointera do zápisovej domény
  cdc_two_flop_synchronizer #(.WIDTH(ADDR_WIDTH + 1)) rd_ptr_sync_inst (
    .clk_i(wr_clk_i), .rst_ni(wr_rstn_sync), .d(rd_ptr_gray), .q(rd_ptr_gray_wrclk_sync)
  );

  // Prevod synchronizovaného gray pointera na binárny pre výpočty
  wire [ADDR_WIDTH:0] rd_ptr_sync_wr_bin = gray2bin(rd_ptr_gray_wrclk_sync);

  // Výpočet zaplnenia FIFO v zápisovej doméne
  wire [ADDR_WIDTH:0] wr_fill_count = wr_ptr_bin - rd_ptr_sync_wr_bin;

  // Logika pre stavy: plné, takmer plné, pretečenie
  assign full_o = (wr_ptr_gray == {
    ~rd_ptr_gray_wrclk_sync[ADDR_WIDTH:ADDR_WIDTH-1],
    rd_ptr_gray_wrclk_sync[ADDR_WIDTH-2:0]
    });
  assign almost_full_o = (wr_fill_count >= (DEPTH - ALMOST_FULL_THRESHOLD));
  assign overflow_o = wr_en_i && full_o;

  //================================================================
  // ==                      Čítacia doména (rd_clk)               ==
  //================================================================

  // OPRAVA: Zlúčená a opravená logika pre čítanie dát a inkrementáciu pointera
  always_ff @(posedge rd_clk_i) begin
    if (!rd_rstn_sync) begin
      rd_ptr_bin  <= '0;
      rd_ptr_gray <= '0;
      rd_data_o   <= '0; // Resetujeme aj výstupný register
    end else if (rd_en_i && !empty_o) begin
      // 1. Čítanie dát: Dáta z aktuálnej adresy `rd_ptr_bin` sa načítajú do výstupného registra.
      rd_data_o   <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
      // 2. Inkrementácia pointera: Až potom sa pointer pripraví na ďalší cyklus.
      rd_ptr_bin  <= rd_ptr_bin + 1;
      rd_ptr_gray <= bin2gray(rd_ptr_bin + 1);
    end
  end

  // Synchronizácia zápisového pointera do čítacej domény
  cdc_two_flop_synchronizer #(.WIDTH(ADDR_WIDTH + 1)) wr_ptr_sync_inst (
    .clk_i(rd_clk_i), .rst_ni(rd_rstn_sync), .d(wr_ptr_gray), .q(wr_ptr_gray_rdclk_sync)
  );

  // Prevod synchronizovaného gray pointera na binárny pre výpočty
  wire [ADDR_WIDTH:0] wr_ptr_sync_rd_bin = gray2bin(wr_ptr_gray_rdclk_sync);

  // Výpočet zaplnenia FIFO v čítacej doméne
  wire [ADDR_WIDTH:0] rd_fill_count = wr_ptr_sync_rd_bin - rd_ptr_bin;

  // Logika pre stavy: prázdne, takmer prázdne, podtečenie
  assign empty_o = (rd_ptr_gray == wr_ptr_gray_rdclk_sync);
  assign almost_empty_o = (rd_fill_count <= ALMOST_EMPTY_THRESHOLD);
  assign underflow_o = rd_en_i && empty_o;

endmodule

`endif // ASYNCFIFO
