Skvelé, pustíme sa teda do **video timing generatora** pre štandardné rozlíšenie (napríklad 640x480 @60Hz). Ten bude generovať:

* **hsync** (horizontálny sync)
* **vsync** (vertikálny sync)
* **data enable (DE)** (signál, ktorý označuje, kedy sa posielajú platné video pixely)
* **pixel counters** (x a y súradnice aktuálneho pixela v rámci rámca)

---

### 1. Video Timing Generator - SystemVerilog

```systemverilog
/**
 * Video Timing Generator for 640x480 @ 60Hz (VGA standard timing)
 * Generates hsync, vsync, data enable, and pixel counters
 *
 * Parameters can be adjusted for iných rozlíšení.
 */
module video_timing_gen #(
    parameter H_ACTIVE    = 640,   // Active horizontal pixels
    parameter H_FRONT_PORCH = 16,
    parameter H_SYNC_PULSE = 96,
    parameter H_BACK_PORCH = 48,
    parameter V_ACTIVE    = 480,   // Active vertical pixels
    parameter V_FRONT_PORCH = 10,
    parameter V_SYNC_PULSE = 2,
    parameter V_BACK_PORCH = 33
)(
    input logic clk,
    input logic reset_n,

    output logic hsync,
    output logic vsync,
    output logic data_enable,
    output logic [$clog2(H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH)-1:0] pixel_x,
    output logic [$clog2(V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH)-1:0] pixel_y
);

    // Calculate total horizontal and vertical pixels
    localparam H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    // Horizontal pixel counter
    logic [$clog2(H_TOTAL)-1:0] h_count;
    // Vertical line counter
    logic [$clog2(V_TOTAL)-1:0] v_count;

    // Horizontal counter increments each clock cycle
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            h_count <= 0;
        else if (h_count == H_TOTAL - 1)
            h_count <= 0;
        else
            h_count <= h_count + 1;
    end

    // Vertical counter increments at end of each line (h_count wraps)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            v_count <= 0;
        else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1)
                v_count <= 0;
            else
                v_count <= v_count + 1;
        end
    end

    // Generate hsync signal (active low during sync pulse)
    assign hsync = ~((h_count >= H_ACTIVE + H_FRONT_PORCH) && (h_count < H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE));

    // Generate vsync signal (active low during sync pulse)
    assign vsync = ~((v_count >= V_ACTIVE + V_FRONT_PORCH) && (v_count < V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE));

    // Data enable is high during active video region
    assign data_enable = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

    // Current pixel coordinates during active video period
    assign pixel_x = h_count;
    assign pixel_y = v_count;

endmodule
```

---

### Popis

* **H\_TOTAL** a **V\_TOTAL** definujú celkový počet pixelov v riadku a riadkov v rámci rámca (vrátane sync a porch).
* `h_count` a `v_count` sú čítače pozície pixelu na vodorovnej a zvislej osi.
* `hsync` a `vsync` sú generované podľa štandardu VGA, kde sú aktívne nízke (negované počas sync pulzu).
* `data_enable` je vysoko len keď sa posielajú platné pixely, teda v aktívnej oblasti obrazu.
* `pixel_x` a `pixel_y` indikujú aktuálnu pozíciu pixela.

---

### Použitie:

Tento modul je vstupom pre generátor videa (napr. RGB pixely sa mapujú podľa `pixel_x`, `pixel_y`) a pre ďalšie moduly (napr. TMDS kódovanie v HDMI pipeline).

---

Chceš, aby som ti vytvoril aj jednoduchý **testbench** pre tento modul? Alebo pokračujeme s **FIFO medzi AXIS a video\_timing**?
