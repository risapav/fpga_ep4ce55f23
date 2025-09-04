#!/bin/bash

# --- Bezpečnostné nastavenia: Skript sa ukončí pri prvej chybe ---
set -e

# --- Definícia farieb pre lepší výstup ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Kontrola vstupného argumentu (cesta k testbenchu) ---
if [ -z "$1" ]; then
    echo -e "${RED}Chyba: Nebol zadaný súbor s testbenchom.${NC}"
    echo "Použitie: $0 <cesta/k/tb_suboru.sv>"
    exit 1
fi

TB_FILE_FULL_PATH="$1"

# --- Zistenie kľúčových ciest ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd)
BUILD_DIR="$PROJECT_ROOT/build"
TB_DIR=$(dirname "$TB_FILE_FULL_PATH")
TB_TOP_MODULE=$(basename "$TB_FILE_FULL_PATH" .sv)

# --- Názov lokálneho zoznamu súborov ---
LOCAL_FILELIST_NAME="sources.f"
LOCAL_FILELIST_PATH="$TB_DIR/$LOCAL_FILELIST_NAME"

# OPRAVA: Premenná VCD_FILE definovaná tu, na začiatku
VCD_FILE="$BUILD_DIR/dump.vcd"

echo -e "${GREEN}===========================================${NC}"
echo -e "${YELLOW} Štartuje sa univerzálna simulácia ${NC}"
echo -e "${GREEN}===========================================${NC}"
echo "Koreň projektu:    $PROJECT_ROOT"
echo "Build adresár:      $BUILD_DIR"
echo "Testbench:          $TB_FILE_FULL_PATH"
echo "Top modul:          $TB_TOP_MODULE"
echo "Cesta k sources.f:  $LOCAL_FILELIST_PATH"
# Váš nový riadok, ktorý teraz bude fungovať správne
echo "Cesta k wavefile:   $VCD_FILE"
echo ""

# --- Príprava build adresára ---
mkdir -p "$BUILD_DIR"

# --- Kompilácia ---
echo -e "\n${YELLOW}Kompilujem s Icarus Verilog...${NC}"

# =================================================================
# Finálna logika: Skontroluj, či existuje lokálny zoznam súborov
# =================================================================
if [ -f "$LOCAL_FILELIST_PATH" ]; then
    # Ak ÁNO, použi lokálny zoznam súborov
    echo -e "Nájdený lokálny zoznam súborov: ${YELLOW}$LOCAL_FILELIST_PATH${NC}."

    if command -v dos2unix &> /dev/null; then
        echo -e "Automaticky konvertujem konce riadkov na formát LF (dos2unix)..."
        dos2unix "$LOCAL_FILELIST_PATH" > /dev/null 2>&1
    fi

    echo "Používam lokálny zoznam súborov na kompiláciu..."
    iverilog -g2012 \
             -o "$BUILD_DIR/compiled_sim.vvp" \
             -s "$TB_TOP_MODULE" \
             -f "$LOCAL_FILELIST_PATH"
else
    # Ak NIE, použi automatické hľadanie súborov
    echo -e "Lokálny zoznam ${YELLOW}$LOCAL_FILELIST_NAME${NC} nenájdený. Hľadám súbory automaticky..."

    FILE_LIST=""
    if [ -d "$PROJECT_ROOT/rtl" ]; then
        FILE_LIST="$FILE_LIST $(find "$PROJECT_ROOT/rtl" -name "*.v" -o -name "*.sv")"
    fi
    if [ -d "$PROJECT_ROOT/lib" ]; then
        FILE_LIST="$FILE_LIST $(find "$PROJECT_ROOT/lib" -name "*.v" -o -name "*.sv")"
    fi
    if [ -d "$PROJECT_ROOT/cores" ]; then
        FILE_LIST="$FILE_LIST $(find "$PROJECT_ROOT/cores" -name "*.v" -o -name "*.sv")"
    fi

    iverilog -g2012 \
             -o "$BUILD_DIR/compiled_sim.vvp" \
             -s "$TB_TOP_MODULE" \
             -I "$PROJECT_ROOT/rtl" \
             -I "$PROJECT_ROOT/lib" \
             $FILE_LIST \
             "$TB_FILE_FULL_PATH"
fi
# =================================================================

echo -e "\n${GREEN}Kompilácia úspešná.${NC}"

# --- Simulácia ---
echo -e "\n${YELLOW}Spúšťam simuláciu (vvp)...${NC}"
(cd "$BUILD_DIR" && vvp compiled_sim.vvp)

echo -e "${GREEN}Simulácia dokončená.${NC}"

# --- Zobrazenie výsledkov ---
if [ -f "$VCD_FILE" ]; then
    echo -e "\n${YELLOW}Otváram GTKWave...${NC}"
    # ZMENA TU: Pridané "DISPLAY=:0 " pred príkaz
    DISPLAY=:0 gtkwave "$VCD_FILE" &
else
    echo -e "\n${YELLOW}Súbor s priebehmi ($VCD_FILE) nebol nájdený.${NC}"
fi

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN} Univerzálna simulácia dokončená. ${NC}"
echo -e "${GREEN}===========================================${NC}"

exit 0