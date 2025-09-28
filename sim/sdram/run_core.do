# run_core.do - Verzia 1.2 - Finálna oprava ciest pre Waveform

# --- Konfigurácia Ciest ---
set ROOT "/home/palo/Documents/fpga_ep4ce55f23"
puts "INFO: Project root = $ROOT"

# --- Príprava ---
if {[file isdirectory work]} { file delete -force work }
vlib work
vmap work work

# --- Zoznamy Súborov (bez Altera a top.sv) ---
set COMMON_SRC [list \
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
set TESTBENCH_SRC [list \
    "$ROOT/sim/sdram/tb_sdram_core.sv" \
]

# --- Procedúra pre bezpečnú kompiláciu ---
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
foreach f $COMMON_SRC { safe_vlog work $f }
foreach f $SDRAM_SRC { safe_vlog work $f }
foreach f $TESTBENCH_SRC { safe_vlog work $f }

# --- Spustenie Simulácie ---
puts "\n--- Fáza Spustenia Simulácie ---"
vsim -l sim_core.log work.tb_sdram_core

# --- Pridanie Signálov do Wave okna (OPRAVENÉ CESTY) ---
puts "INFO: Pridávam signály do Wave..."
add wave -divider "Clocks & Reset"
add wave sim:/tb_sdram_core/clk_100mhz
add wave sim:/tb_sdram_core/clk_100mhz_shifted
add wave sim:/tb_sdram_core/rstn_axi

add wave -divider "Tester"
add wave -radix unsigned sim:/tb_sdram_core/tester/state_reg
add wave sim:/tb_sdram_core/pass_led
add wave sim:/tb_sdram_core/fail_led
add wave -radix hex sim:/tb_sdram_core/tester/burst_cnt

add wave -divider "Tester <-> Driver Handshake"
add wave sim:/tb_sdram_core/writer_valid
add wave sim:/tb_sdram_core/writer_ready
add wave -radix hex sim:/tb_sdram_core/writer_addr
add wave -radix hex sim:/tb_sdram_core/writer_data
add wave sim:/tb_sdram_core/reader_valid
add wave sim:/tb_sdram_core/reader_ready
add wave sim:/tb_sdram_core/resp_valid
add wave -radix hex sim:/tb_sdram_core/resp_data

add wave -divider "SdramController Internals"
add wave -radix unsigned sim:/tb_sdram_core/sdram_driver/controller/state
add wave -radix hex sim:/tb_sdram_core/sdram_driver/controller/wait_cnt
add wave -radix hex sim:/tb_sdram_core/sdram_driver/controller/cas_cnt
add wave -radix hex sim:/tb_sdram_core/sdram_driver/controller/burst_cnt

add wave -divider "SDRAM Physical Pins"
add wave sim:/tb_sdram_core/sdram_model/CLK
add wave sim:/tb_sdram_core/sdram_model/CKE
add wave sim:/tb_sdram_core/sdram_model/CS_n
add wave sim:/tb_sdram_core/sdram_model/RAS_n
add wave sim:/tb_sdram_core/sdram_model/CAS_n
add wave sim:/tb_sdram_core/sdram_model/WE_n
add wave -radix hex sim:/tb_sdram_core/sdram_model/BA
add wave -radix hex sim:/tb_sdram_core/sdram_model/A
add wave -radix hex sim:/tb_sdram_core/sdram_model/DQ

# --- Beh Simulácie ---
run 300us
puts "--- Simulácia Dokončená ---"