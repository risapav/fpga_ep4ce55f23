Perfektne! Poďme krok za krokom. Začneme teda **bodom 1: štruktúra projektu a adresárov**.

---

## 🔧 **1. Návrh adresárovej štruktúry pre FPGA projekt**

Tu je odporúčaná štruktúra (v štýle Unix `tree`). Zohľadňuje Quartus, HDL kód, IP jadrá, simuláciu, dokumentáciu aj build skripty:

```plaintext
projekt/
├── .gitignore
├── README.md
├── fpga/                  # Quartus projekt
│   ├── project.qpf
│   ├── project.qsf
│   ├── board/             # špecifické nastavenia (napr. pinout)
│   │   └── de10-lite.qsf
│   └── constraints/       # SDC a fyzické constrainty
│       └── top.sdc
│
├── rtl/                   # HDL zdrojový kód (top-level a základné moduly)
│   ├── top.sv
│   ├── reset_gen.sv
│   └── clocking.sv
│
├── lib/                   # opakovane použiteľné moduly
│   ├── axi/
│   │   └── axi_master.sv
│   ├── sdram/
│   │   └── controller.sv
│   └── video/
│       └── hdmi_tx.sv
│
├── cores/                 # generované IP jadrá
│   ├── sdram_controller/
│   │   ├── sdram_controller.qip
│   │   ├── synthesis/
│   │   └── simulation/
│   └── pll/
│       └── ...
│
├── sim/                   # simulácie a testbenche
│   ├── questa/            # konfiguračné súbory, vmap atď.
│   └── tb_top.sv
│
├── doc/                   # dokumentácia v markdown
│   ├── architektura.md
│   ├── signal_map.md
│   └── sdram_config.md
│
├── scripts/               # build skripty a spúšťanie
│   ├── build.tcl
│   ├── build.sh
│   └── simulate.sh
│
└── out/                   # výstupné súbory (sof, logy, reporty)
    ├── top.sof
    ├── build.log
    └── timing_summary.rpt
```

---

## 🔹 Poznámky:

* **`fpga/`** – obsahuje iba nutné veci pre Quartus: `.qsf`, `.qpf`, SDC, pinout. Nepatria sem výstupy (`db/`, `.sof`, atď.).
* **`rtl/`** – hlavné moduly a top-level dizajn.
* **`lib/`** – opakovane použiteľné HDL moduly, logicky rozdelené.
* **`cores/`** – generované IP jadrá (napr. cez IP Catalog).
* **`sim/`** – testbenche, simulačné knižnice a nastavenia.
* **`scripts/`** – build/simulačné skripty, tcl, bash.
* **`out/`** – všetko, čo vznikne počas buildu a nemá byť v Gite.
* **`doc/`** – stručná, ale jasná dokumentácia.

---

## ✅ Ďalší krok

Ak súhlasíš s touto štruktúrou, môžeme prejsť na **bod 2: build a simulačné skripty**.

Chceš:

1. **Quartus TCL skript (`build.tcl`)** – na automatickú kompiláciu?
2. **Makefile**, ktorý spustí Quartus build, simuláciu atď.?
3. **Bash skripty (`build.sh`, `simulate.sh`)**?

Alebo všetky tri?
