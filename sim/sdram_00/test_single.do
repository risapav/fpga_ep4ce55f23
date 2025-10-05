# test_single.do - Skript na test kompilácie jedného súboru

# Najprv vyčistíme a pripravíme knižnicu
if {[file isdirectory work]} { file delete -force work }
vlib work
vmap work work

puts "INFO: === TEST V IZOLÁCII ==="
puts "INFO: Kompilujem IBA súbor seven_seg_decoder.sv..."

# Použijeme presne ten istý príkaz ako v hlavnom skripte
vlog -work work -sv -vopt +acc ../../src/utils/seven_seg_decoder.sv

puts "INFO: === KONIEC TESTU V IZOLÁCII ==="
quit
