Super, ideme teda pokračovať bodom **2: build a simulačné skripty**. Navrhnem všetky tri typy (TCL, Makefile, Bash), tak aby sa dali použiť jednotlivo alebo v kombinácii. 🎯

---

## 🔧 **2.1: Quartus build skript – `scripts/build.tcl`**

Tento `.tcl` skript vieš spustiť v Quartus prostredí cez `quartus_sh --tcl_script`.

```tcl
# scripts/build.tcl
project_open fpga/project.qpf
execute_flow -compile
project_close
```

> 💡 Doplniteľné o ďalšie kroky: napr. `export_assignments`, `write_qsf`, `report_timing`.

---

## 🧰 **2.2: Makefile**

Univerzálny `Makefile`, ktorý:

* Spustí build cez Quartus TCL
* Spustí ModelSim simuláciu
* Vytvorí výstupný adresár

```makefile
# Makefile – v root priečinku

PROJECT_NAME = project
PROJECT_DIR = fpga
OUT_DIR = out
SCRIPT_DIR = scripts
SIM_DIR = sim

all: build

build:
	mkdir -p $(OUT_DIR)
	quartus_sh --tcl_script $(SCRIPT_DIR)/build.tcl

sim:
	cd $(SIM_DIR) && vsim -do simulate.do

clean:
	rm -rf $(OUT_DIR) $(PROJECT_DIR)/db $(PROJECT_DIR)/incremental_db
```

---

## 🖥️ **2.3: Bash skript – `scripts/build.sh`**

Pre tých, čo nepoužívajú `make`, ale chcú jednoduchý shell príkaz:

```bash
#!/bin/bash
# scripts/build.sh

set -e

echo "==> Building Quartus project..."
quartus_sh --tcl_script scripts/build.tcl

echo "==> Done."
```

> 🛡️ Pridaj `chmod +x scripts/build.sh` aby bol spustiteľný.

---

## 🧪 (Bonus) `scripts/simulate.sh` – spustenie ModelSim

```bash
#!/bin/bash
# scripts/simulate.sh

cd sim
vsim -do simulate.do
```

---

## ✅ Pripravené

Týmto máme:

* Automatizáciu buildu v **Quartuse**
* Skriptovateľný **simulačný beh**
* **Makefile** ako "zastrešujúci" kontrolér

---

## 🔜 Ďalší krok: **3. Dokumentácia projektu (README + `doc/`)**?

Môžeme vytvoriť:

* Obsahovo bohatý `README.md` s build/sim inštrukciami
* Šablóny pre `doc/`, napríklad `architektura.md`, `rozhrania.md`, `TODO.md`

Môžeme?
