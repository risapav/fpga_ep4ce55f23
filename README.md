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

├── board/ # QSF podsúbory (pin assign, periférie)
├── cores/ # IP jadrá (napr. ClkGen)
├── db/, incremental_db/ # Quartus výstupy (ignorované gitom)
├── doc/ # Dokumentácia (markdown)
├── examples/ # Príklady použití
├── lib/ # Knižnice (VHDL/Verilog moduly)
├── rtl/ # RTL kód
├── simulation/ # Simulačné skripty a výsledky
└── scripts/ # Build/simulačné skripty

## My SystemVerilog Library

Táto knižnica obsahuje opakovane použiteľné moduly napísané v jazyku SystemVerilog.

### Obsah
- [Začiatok](docs/getting_started.md)
- [Moduly](docs/index.md)
- [Ukážky použitia](examples/)

## 🛠️ Build

### Quartus CLI
```sh
./scripts/build.sh

Alebo použite:

```sh
make


## 🧪 Simulácia

Predpoklad: nainštalovaný ModelSim alebo Questa

./scripts/simulate.sh

🔎 Zdroje

    Altera Quartus Prime

    QMTech EP4CE55F23 datasheet


## 📜 Licencia

MIT License
