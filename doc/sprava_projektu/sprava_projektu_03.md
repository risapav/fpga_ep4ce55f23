Super! Pokračujme teda s bodom **3: Dokumentácia projektu** – vytvoríme základný systém dokumentácie pre jednoduchú orientáciu v kóde, rozšíriteľný podľa potreby.

---

## 📘 **3.1 README.md – základná dokumentácia projektu**

```markdown
# FPGA Projekt – `project_001`

## 🧾 Popis
Tento projekt implementuje systém s viacerými perifériami na doske **QMTech EP4CE55F23**, vrátane:
- 7-segmentovky
- SDRAM
- VGA
- UART
- Ethernet
- PMOD rozhraní

## 📁 Štruktúra projektu

```

.
├── board/           # QSF podsúbory (pin assign, periférie)
├── cores/           # IP jadrá (napr. ClkGen)
├── db/, incremental\_db/  # Quartus výstupy (ignorované gitom)
├── doc/             # Dokumentácia (markdown)
├── examples/        # Príklady použití
├── lib/             # Knižnice (VHDL/Verilog moduly)
├── rtl/             # RTL kód
├── simulation/      # Simulačné skripty a výsledky
└── scripts/         # Build/simulačné skripty

````

## 🛠️ Build

### Quartus CLI
```sh
./scripts/build.sh
````

Alebo použite:

```sh
make
```

## 🧪 Simulácia

Predpoklad: nainštalovaný ModelSim alebo Questa

```sh
./scripts/simulate.sh
```

## 🔎 Zdroje

* [Altera Quartus Prime](https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/overview.html)
* [QMTech EP4CE55F23 datasheet](https://www.qmtech.com/)

## 📜 Licencia

[MIT License](LICENSE)

```

---

## 📁 **3.2 Doc štruktúra – odporúčané súbory**

Priečinok `doc/` už existuje, len ho systematizujeme. Odporúčané hlavné súbory:

| Súbor                    | Účel |
|--------------------------|------|
| `architecture.md`        | Popis celej architektúry systému |
| `interfaces.md`          | Zoznam a špecifikácia periférií |
| `zbernice_porovnanie.md` | Porovnanie AXI/AXI-Lite/AXIS |
| `TODO.md`                | Plánovanie úloh a rozšírení |
| `troubleshooting.md`     | Známé chyby, problémy a riešenia |
| `board_notes.md`         | Poznámky k fyzickému osadeniu dosky |

> ✅ Môžeme automaticky vygenerovať úvodné verzie týchto súborov, ak chceš.

---

## 🔜 Ďalší krok:  
**4. Zorganizovanie `rtl/`, `lib/`, `examples/` – navrhneme naming štandardy a štruktúru, aby sa projekt dal lepšie škálovať a udržiavať.**

Môžeme?
```
