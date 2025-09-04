# Dokumentácia modulov

## 🔧 Zoznam

| Názov modulu | Popis | Zdrojový súbor |
|--------------|--------|----------------|
| [axis_checker_generator](modules/axis/axis_checker_generator.md) | - | [axis/axis_checker_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_checker_generator.sv) |
| [axis_frame_streamer](modules/axis/axis_frame_streamer.md) | AXI4-Stream Frame Streamer generujúci súradnice pixelov. | [axis/axis_frame_streamer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_frame_streamer.sv) |
| [axis_gradient_generator](modules/axis/axis_gradient_generator.md) | - | [axis/axis_gradient_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_gradient_generator.sv) |
| [axis_to_vga](modules/axis/axis_to_vga.md) | Premosťuje AXI4-Stream dáta na paralelný VGA výstup. | [axis/axis_to_vga.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_to_vga.sv) |
| [cdc_async_fifo](modules/cdc/cdc_async_fifo.md) | Asynchrónny FIFO buffer s oddelenými hodinovými doménami pre zápis a čítanie. | [cdc/cdc_async_fifo.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/cdc/cdc_async_fifo.sv) |
| [cdc_reset_synchronizer](modules/cdc/cdc_reset_synchronizer.md) | Synchronizátor asynchrónneho resetu pre cieľovú hodinovú doménu. | [cdc/cdc_reset_synchronizer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/cdc/cdc_reset_synchronizer.sv) |
| [cdc_two_flop_synchronizer](modules/cdc/cdc_two_flop_synchronizer.md) | Dvojstupňový synchronizátor signálu pre CDC (Clock Domain Crossing). | [cdc/cdc_two_flop_synchronizer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/cdc/cdc_two_flop_synchronizer.sv) |
| [CheckerPattern](modules/axis/CheckerPattern.md) | AXI4-Stream generátor šachovnicového vzoru (checkerboard pattern) | [axis/axis_checker_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_checker_generator.sv) |
| [GradientPattern](modules/axis/GradientPattern.md) | Generuje AXI4-Stream výstup s farebným gradientom. | [axis/axis_gradient_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_gradient_generator.sv) |
| [my_axi_peripheral](modules/axi/my_axi_peripheral.md) | Definície AXI rozhraní (AXI4, AXI4-Lite, AXI4-Stream) pre použitie v SoC dizajne. | [axi/axi_interfaces.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axi/axi_interfaces.sv) |
| [top](modules/vga_01/top.md) | - | [vga_01/top.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/vga_01/top.sv) |
| [top](modules/led_01/top_2.md) | Testovací modul pre FPGA, ktorý generuje tri nezávislé vizuálne efekty na troch skupinách LED diód v sekundových intervaloch. | [led_01/top.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/led_01/top.sv) |
