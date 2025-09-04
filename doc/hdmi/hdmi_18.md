Výborne! Zvolil si možnosť **D: Generovať Quartus-ready projekt**, čiže pripravíme:

---

## ✅ Quartus-ready HDMI InfoFrame projekt

Tento balík bude obsahovať všetko potrebné pre implementáciu v Quartuse:

---

### 🧾 1. **Zoznam súborov**

Projekt bude obsahovať tieto SystemVerilog moduly:

| Súbor                           | Účel                                  |
| ------------------------------- | ------------------------------------- |
| `infoframe_top.sv`              | Top modul, výber AVI/SPD infoframe    |
| `spd_infoframe_generator.sv`    | SPD InfoFrame (Type 0x83) payload     |
| `avi_infoframe_generator.sv`    | AVI InfoFrame (Type 0x82) payload     |
| `crc8_generator.sv`             | Výpočet CRC-8 podľa HDMI špecifikácie |
| `infoframe_tb.sv` *(voliteľné)* | Testbench pre simuláciu               |

---

### 📁 2. **Quartus projektový súbor – `infoframe.qsf`**

Tu je základný `.qsf` súbor pre Quartus Prime:

```tcl
# Quartus Project File
set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE22F17C6
set_global_assignment -name TOP_LEVEL_ENTITY infoframe_top
set_global_assignment -name VERILOG_FILE infoframe_top.sv
set_global_assignment -name VERILOG_FILE spd_infoframe_generator.sv
set_global_assignment -name VERILOG_FILE avi_infoframe_generator.sv
set_global_assignment -name VERILOG_FILE crc8_generator.sv

# Optional testbench file (commented out)
# set_global_assignment -name VERILOG_FILE infoframe_tb.sv

# TimeQuest Timing Constraints
set_global_assignment -name SDC_FILE infoframe.sdc

# Assign Clock Pin (example: clock input on PIN_23)
set_location_assignment PIN_23 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

# Reset signal (active low)
set_location_assignment PIN_24 -to rst_n
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rst_n

# Optional select_infoframe input
set_location_assignment PIN_25 -to select_infoframe
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to select_infoframe

# Example output pins for infoframe_data[0..7] (expand as needed)
set_location_assignment PIN_30 -to infoframe_data[0]
set_location_assignment PIN_31 -to infoframe_data[1]
set_location_assignment PIN_32 -to infoframe_data[2]
set_location_assignment PIN_33 -to infoframe_data[3]
set_location_assignment PIN_34 -to infoframe_data[4]
set_location_assignment PIN_35 -to infoframe_data[5]
set_location_assignment PIN_36 -to infoframe_data[6]
set_location_assignment PIN_37 -to infoframe_data[7]

# Output valid flag
set_location_assignment PIN_38 -to infoframe_valid
```

---

### 🕒 3. **Časové obmedzenia – `infoframe.sdc`**

```sdc
create_clock -name clk -period 20.000 [get_ports clk]
set_input_delay -clock clk 5 [get_ports rst_n]
set_input_delay -clock clk 5 [get_ports select_infoframe]
set_output_delay -clock clk 5 [get_ports {infoframe_data[*]}]
set_output_delay -clock clk 5 [get_ports infoframe_valid]
```

---

### 📁 4. **Štruktúra adresárov**

```
infoframe_project/
├── infoframe_top.sv
├── spd_infoframe_generator.sv
├── avi_infoframe_generator.sv
├── crc8_generator.sv
├── infoframe_tb.sv             # (voliteľné)
├── infoframe.qsf
└── infoframe.sdc
```

---

## 🛠️ 5. Pokyny pre Quartus

1. **Spusť Quartus Prime**
2. `File > New Project Wizard`
3. Vyber priečinok `infoframe_project`
4. Vytvor projekt s názvom `infoframe`
5. Po vygenerovaní `.qsf` → pridaj všetky `.sv` súbory
6. Kompiluj
7. V nástroji Pin Planner nastav podľa potreby výstupy

---

## ➕ Voliteľné: Pridať VHDL Wrapper alebo TMDS výstup?

Chceš teraz:

* 🔁 Vytvoriť VHDL wrapper?
* 🎦 Rozšíriť výstup o TMDS HDMI výstup?
* 🔬 Vytvoriť simuláciu/testbench?
* 📤 Exportovať celý ZIP projekt? *(Potrebujem potvrdenie pred generovaním)*

Alebo máš FPGA konkrétne (napr. DE0-Nano, MAX10)? Môžem prispôsobiť pinout.
