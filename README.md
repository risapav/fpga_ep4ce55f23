# Dokumentácia modulov

## 🔧 Zoznam

| Názov modulu | Popis | Zdrojový súbor |
|--------------|--------|----------------|
| [axis_checker_generator](modules/axis/axis_checker_generator.md) | - | [axis/axis_checker_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_checker_generator.sv) |
| [axis_frame_streamer](modules/axis/axis_frame_streamer.md) | AXI4-Stream Frame Streamer generujúci súradnice pixelov. | [axis/axis_frame_streamer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_frame_streamer.sv) |
| [axis_gradient_generator](modules/axis/axis_gradient_generator.md) | - | [axis/axis_gradient_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_gradient_generator.sv) |
| [axis_to_vga](modules/axis/axis_to_vga.md) | Premosťuje AXI4-Stream dáta na paralelný VGA výstup. | [axis/axis_to_vga.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_to_vga.sv) |
| [AxiStreamSdramVgaTopDualBuffer](modules/sdram/AxiStreamSdramVgaTopDualBuffer.md) | - | [sdram/axis_sdram_vga_dualbuffer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/axis_sdram_vga_dualbuffer.sv) |
| [AxiStreamToSdramWrite](modules/sdram/AxiStreamToSdramWrite.md) | - | [sdram/axis_to_sdram.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/axis_to_sdram.sv) |
| [cdc_async_fifo](modules/cdc/cdc_async_fifo.md) | Asynchrónny FIFO buffer s oddelenými hodinovými doménami pre zápis a čítanie. | [cdc/cdc_async_fifo.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/cdc/cdc_async_fifo.sv) |
| [cdc_reset_synchronizer](modules/cdc/cdc_reset_synchronizer.md) | Synchronizátor asynchrónneho resetu pre cieľovú hodinovú doménu. | [cdc/cdc_reset_synchronizer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/cdc/cdc_reset_synchronizer.sv) |
| [cdc_two_flop_synchronizer](modules/cdc/cdc_two_flop_synchronizer.md) | Dvojstupňový synchronizátor signálu pre CDC (Clock Domain Crossing). | [cdc/cdc_two_flop_synchronizer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/cdc/cdc_two_flop_synchronizer.sv) |
| [CheckerPattern](modules/axis/CheckerPattern.md) | AXI4-Stream generátor šachovnicového vzoru (checkerboard pattern) | [axis/axis_checker_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_checker_generator.sv) |
| [Fifo](modules/framebuffer/Fifo.md) | - | [framebuffer/framebuffer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/framebuffer/framebuffer.sv) |
| [FramebufferController](modules/framebuffer/FramebufferController.md) | - | [framebuffer/framebuffer.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/framebuffer/framebuffer.sv) |
| [GradientPattern](modules/axis/GradientPattern.md) | Generuje AXI4-Stream výstup s farebným gradientom. | [axis/axis_gradient_generator.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axis/axis_gradient_generator.sv) |
| [my_axi_peripheral](modules/axi/my_axi_peripheral.md) | Definície AXI rozhraní (AXI4, AXI4-Lite, AXI4-Stream) pre použitie v SoC dizajne. | [axi/axi_interfaces.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/axi/axi_interfaces.sv) |
| [parameters](modules/sdram/parameters.md) | - | [sdram/sdram_driver.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/sdram_driver.sv) |
| [SdramCmdArbiter](modules/sdram/SdramCmdArbiter.md) | - | [sdram/sdram_arbiter.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/sdram_arbiter.sv) |
| [SdramController](modules/sdram/SdramController.md) | - | [sdram/sdram_ctrl.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/sdram_ctrl.sv) |
| [SdramDriver](modules/sdram/SdramDriver.md) | - | [sdram/sdram_driver.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/sdram_driver.sv) |
| [SdramToAxiStreamRead](modules/sdram/SdramToAxiStreamRead.md) | - | [sdram/sdram_to_axis.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/sdram_to_axis.sv) |
| [seven_seg_decoder](modules/utils/seven_seg_decoder.md) | - | [utils/seven_seg_decoder.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/utils/seven_seg_decoder.sv) |
| [SimpleSdramTester](modules/sdram/SimpleSdramTester.md) | - | [sdram/simple_sdram_tester.sv](https://github.com/risapav/fpga_ep4ce55f23/blob/main/src/sdram/simple_sdram_tester.sv) |
