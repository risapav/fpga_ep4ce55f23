# run_core_batch.do - Skript pre rýchlu simuláciu v príkazovom riadku

# --- Konfigurácia Ciest ---
set ROOT "/home/palo/Documents/fpga_ep4ce55f23"
puts "INFO: Project root = $ROOT"

# --- Príprava ---
if {[file isdirectory work]} { file delete -force work }
vlib work
vmap work work

# --- Zoznamy Súborov ---
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
        if {[string match *.sv $filename]} {
            vlog -work $library -sv +acc $filename
        } else {
            vlog -work $library +acc $filename
        }
    } else {
        error "ERROR: Missing file: $filename"
    }
}

# --- Kompilácia ---
puts "\n--- Fáza Kompilácie ---"
foreach f $COMMON_SRC { safe_vlog work $f }
foreach f $SDRAM_SRC { safe_vlog work $f }
foreach f $TESTBENCH_SRC { safe_vlog work $f }

# --- Spustenie Simulácie ---
puts "\n--- Fáza Spustenia Simulácie ---"
# -c : command-line mode
# -onfinish exit: automaticky ukončí vsim po skončení `run`
vsim -c -onfinish exit work.tb_sdram_core

# --- Beh Simulácie ---
run 300us
puts "--- Simulácia Dokončená ---"