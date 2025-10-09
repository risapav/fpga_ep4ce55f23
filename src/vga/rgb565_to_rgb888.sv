/**
 * @brief       Kombinačný modul, ktorý konvertuje 16-bitovú farbu vo formáte RGB565 na 24-bitovú farbu vo formáte RGB888.
 * @details     Tento modul realizuje prevod medzi dvoma bežnými farebnými formátmi. Vstupom je 16-bitová farba
 * v štruktúre `vga_data_t`, ktorá definuje farbu pomocou 5 bitov pre červenú, 6 bitov pre zelenú a
 * 5 bitov pre modrú zložku (RGB565). Výstupom sú tri samostatné 8-bitové signály pre každú farebnú
 * zložku (RGB888).
 *
 * Konverzia je implementovaná pomocou replikácie najvýznamnejších bitov zo vstupných zložiek
 * do najmenej významných bitov výstupných zložiek, čo je hardvérovo efektívna metóda
 * s dobrými vizuálnymi výsledkami.
 * - R_out[7:0] = { R_in[4:0], R_in[4:2] }
 * - G_out[7:0] = { G_in[5:0], G_in[5:4] }
 * - B_out[7:0] = { B_in[4:0], B_in[4:2] }
 *
 * Modul je čisto kombinačný a nevyžaduje hodinový signál.
 * Pre správnu funkciu je nutné, aby bol dátový typ `vga_data_t` definovaný v dosahu modulu.
 *
 * @param[in]   (žiadne)
 * @param[out]  (žiadne)
 *
 * @input       rgb565_i        Vstupná 16-bitová farba v štruktúre `rgb565_t` (formát RGB565).
 * @output      rgb888_o        Výstupná 24-bitová farba  v štruktúre `rgb888_t` (formát RGB888).
 *
 * @example
 * // Ukážka použitia v inom module.
 * // Predpokladá sa, že `vga_data_t` je definovaný.
 *
 * // Signály pre prepojenie
 * rgb565_t my_rgb565_color;
 * rgb888_t my_rgb888_color;
 *
 * // Priradenie nejakej hodnoty (napr. jasná fialová)
 * assign my_rgb565_color = '{red: 5'b11100, grn: 5'b001001, blu: 5'b11101};
 *
 * // Inštancia modulu
 * rgb565_to_rgb888 u_color_converter (
 * .rgb565_i(my_rgb565_color),
 * .rgb888_o(my_rgb888_color)
 * );
 */
 
`ifndef RGB565_TO_RGB888
`define RGB565_TO_RGB888

`default_nettype none 

import vga_pkg::*;
 
// Modul pre konverziu z RGB565 na RGB888
module rgb565_to_rgb888 (
  input  rgb565_t rgb565_i, // Vstupný 16-bitový signál
  output rgb888_t rgb888_o  // Výstup 24 bitový signál
);

  // Priradenie s replikáciou bitov pre najlepšiu aproximáciu farby
  // V SystemVerilog sa operátor {} používa na spájanie (konkatenáciu) bitov.

  // Konverzia červenej: {5 bitov zdroja, 3 najvýznamnejšie bity zdroja}
  assign rgb888_o.red = { rgb565_i.red, rgb565_i.red[4:2] };

  // Konverzia zelenej: {6 bitov zdroja, 2 najvýznamnejšie bity zdroja}
  assign rgb888_o.grn = { rgb565_i.grn, rgb565_i.grn[5:4] };

  // Konverzia modrej: {5 bitov zdroja, 3 najvýznamnejšie bity zdroja}
  assign rgb888_o.blu = { rgb565_i.blu, rgb565_i.blu[4:2] };

endmodule

`endif
