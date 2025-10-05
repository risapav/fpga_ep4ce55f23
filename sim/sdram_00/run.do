# ===================================================================
# == Finálny Simulačný skript pre SDRAM Tester (Verzia 4.1)
# ===================================================================
#
# Kľúčové zmeny v tejto verzii:
# 1. ZMENA MODELU: Odstránená podpora pre chránený Winbond model.
# 2. NOVINKA: Pridaná kompilácia pre generický, nechránený `generic_sdram.v`.
# 3. ZJEDNODUŠENIE: Zjednodušená štruktúra knižníc a `vsim` príkaz.

# --- Konfigurácia Ciest ---
set ROOT "/home/palo/Documents/fpga_ep4ce55f23"
set ALTERA_SIM_LIBS_SRC "/home/palo/intelFPGA_lite/24.1std/quartus/eda/sim_lib"

puts "INFO: Project root = $ROOT"

# --- Príprava Knižníc ---
if {[file isdirectory work]} { file delete -force work }
if {[file isdirectory altera_lib]} { file delete -force altera_lib }

vlib work; vmap work work
vlib altera_lib; vmap altera_lib altera_lib

# --- Zoznamy Zdrojových Súborov ---
set ALTERA_LIBS [list \
    "$ALTERA_SIM_LIBS_SRC/altera_primitives.v" \
    "$ALTERA_SIM_LIBS_SRC/cycloneive_atoms.v" \
    "$ALTERA_SIM_LIBS_SRC/altera_mf.v" \
]
set COMMON_SRC [list \
    "$ROOT/src/utils/seven_seg_decoder.sv" \
    "$ROOT/common/src/utils/blink_led.sv" \
    "$ROOT/common/src/cdc/cdc_reset_synchronizer.sv" \
    "$ROOT/common/src/cdc/cdc_two_flop_synchronizer.sv" \
    "$ROOT/common/src/cdc/cdc_async_fifo.sv" \
    "$ROOT/sim/sdram/generic_sdram.v" \
]
set SDRAM_SRC [list \
    "$ROOT/src/sdram/sdram_pkg.sv" \
    "$ROOT/src/sdram/sdram_arbiter.sv" \
    "$ROOT/src/sdram/sdram_ctrl.sv" \
    "$ROOT/src/sdram/sdram_driver.sv" \
    "$ROOT/src/sdram/simple_sdram_tester.sv" \
]
set IP_CORES [list \
    "$ROOT/cores/ClkPll.v" \
]
set TOP_SRC [list \
    "$ROOT/top.sv" \
    "$ROOT/sim/sdram/tb_top.sv" \
]

# --- Bezpečná Kompilačná procedúra ---
proc safe_vlog {library filename} {
    if {[file exists $filename]} {
        puts "INFO: Compiling [file tail $filename] into library '$library'"
        if {[string match *.sv $filename]} {
            vlog -work $library -sv -vopt +acc $filename
        } else {
            vlog -work $library -vopt +acc $filename
        }
    } else {
        puts "ERROR: Missing file: $filename"
        error "Kompilácia zlyhala, súbor nebol nájdený."
    }
}

# --- Kompilácia ---
puts "\n--- Fáza Kompilácie ---"
# 1. Skompilujeme Altera knižnice do `altera_lib`
puts "INFO: Compiling Altera simulation libraries..."
foreach f $ALTERA_LIBS { safe_vlog altera_lib $f }

# 2. Skompilujeme náš kód a generický SDRAM model do `work`
puts "INFO: Compiling common modules and SDRAM model..."
foreach f $COMMON_SRC { safe_vlog work $f }

puts "INFO: Compiling SDRAM modules..."
foreach f $SDRAM_SRC { safe_vlog work $f }

puts "INFO: Compiling IP cores..."
foreach f $IP_CORES { safe_vlog work $f }

puts "INFO: Compiling top-level & testbench..."
foreach f $TOP_SRC { safe_vlog work $f }

# --- Konfigurácia Simulácie ---
if {![info exists RUN_TIME]} { set RUN_TIME 10us }

# --- Spustenie Simulácie ---
puts "\n--- Fáza Spustenia Simulácie (čas behu = $RUN_TIME) ---"
# Finálny príkaz vsim s pridanou Altera knižnicou
vsim -l sim.log -L altera_lib work.tb_top

# --- Pridanie signálov do Wave okna ---
echo "INFO: Pridávam signály do Wave..."
add wave -divider "Testbench & Top-Level"
add wave sim:/tb_top/SYS_CLK
add wave sim:/tb_top/RESET_N
add wave -radix hex sim:/tb_top/dut/clk_100mhz
add wave -radix hex sim:/tb_top/dut/clk_100mhz_shifted
add wave sim:/tb_top/dut/rstn_sync_axi

add wave -divider "SimpleSdramTester"
add wave -radix unsigned sim:/tb_top/dut/sdram_tester_inst/state_reg
add wave sim:/tb_top/dut/pass_led
add wave sim:/tb_top/dut/fail_led
add wave sim:/tb_top/dut/busy_led

add wave -divider "Tester <-> Driver Handshake"
add wave sim:/tb_top/dut/writer_valid
add wave sim:/tb_top/dut/writer_ready
add wave -radix hex sim:/tb_top/dut/writer_addr
add wave -radix hex sim:/tb_top/dut/writer_data
add wave sim:/tb_top/dut/reader_valid
add wave sim:/tb_top/dut/reader_ready
add wave sim:/tb_top/dut/resp_valid
add wave -radix hex sim:/tb_top/dut/resp_data

add wave -divider "SdramController Internals"
add wave -radix unsigned sim:/tb_top/dut/sdram_driver_inst/controller/state
add wave -radix hex sim:/tb_top/dut/sdram_driver_inst/controller/wait_cnt
add wave -radix hex sim:/tb_top/dut/sdram_driver_inst/controller/burst_cnt
add wave -radix hex sim:/tb_top/dut/sdram_driver_inst/controller/cas_cnt

add wave -divider "SDRAM Physical Pins"
add wave sim:/tb_top/SDRAM_CLK
add wave sim:/tb_top/SDRAM_CKE
add wave sim:/tb_top/SDRAM_CS_N
add wave sim:/tb_top/SDRAM_RAS_N
add wave sim:/tb_top/SDRAM_CAS_N
add wave sim:/tb_top/SDRAM_WE_N
add wave -radix hex sim:/tb_top/SDRAM_BA
add wave -radix hex sim:/tb_top/SDRAM_ADDR
add wave -radix hex sim:/tb_top/SDRAM_DQ

# --- Beh Simulácie ---
puts "--- Beh Simulácie ---"
run $RUN_TIME
puts "--- Simulácia Dokončená ---"

# Pre ukončenie v command-line režime odkomentujte nasledujúci riadok
# quit

