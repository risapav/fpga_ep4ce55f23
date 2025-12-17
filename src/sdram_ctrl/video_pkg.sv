`default_nettype none

`ifndef VIDEO_PKG_SV
`define VIDEO_PKG_SV

package video_pkg;
    // Rozlíšenie (napr. 640x480)
    localparam int H_RES = 640;
    localparam int V_RES = 480;
    
    // Adresy pre Double Buffering v SDRAM (Linear Offset)
    // Buffer 0 začína na adrese 0
    localparam int FB_BASE_ADDR_0 = 0; 
    // Buffer 1 začína za koncom prvého framu (zaokrúhlené pre zarovnanie)
    localparam int FB_BASE_ADDR_1 = H_RES * V_RES; 

    // Helper pre výpočet celkového počtu pixelov
    localparam int FRAME_PIXELS = H_RES * V_RES;
endpackage

`endif
