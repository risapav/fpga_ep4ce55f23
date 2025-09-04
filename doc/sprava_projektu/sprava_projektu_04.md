Výborne, ideme na **4. Zorganizovanie `rtl/`, `lib/`, `examples/`**!

---

# 4. Organizácia zdrojových kódov a príkladov

---

## 4.1 Naming a štruktúra adresárov

### RTL (primárny projektový kód)

* Adresár `rtl/` necháme na vlastný projektový kód (top-level moduly, vlastné komponenty).
* Každý modul (alebo skupina modulov) v samostatnom podadresári, ak ich pribudne viac.
* Názvy súborov vždy malými písmenami, podčiarkovník (`_`) na oddelenie slov, napr.:

  * `uart_controller.sv`
  * `led_driver.sv`
  * `button_input.sv`

Ak je modul komplexný, je vhodné mať adresár s `src/` a `tb/` (testbench), napr.:

```
rtl/
└── uart_controller/
    ├── src/
    │   └── uart_controller.sv
    └── tb/
        └── uart_controller_tb.sv
```

---

### LIB (knižnice a externé moduly)

* Adresár `lib/` na knižnice a zdieľané moduly (často použiteľné pre viac projektov).
* Podadresáre podľa funkčnej kategórie, napr.:

```
lib/
├── axi/
│   ├── axi_pkg.sv
│   └── axi_master.sv
├── hdmi/
│   └── hdmi.sv
├── spi/
│   ├── spi_master.sv
│   └── spi_slave.sv
```

* Každý modul v samostatnom súbore s názvom podľa hlavnej entity.

---

### EXAMPLES (príklady)

* `examples/` slúži na ukážkové top-level moduly a demo konfigurácie.
* Názvy podľa verzie a funkcie, napr.:

```
examples/
├── top_001_demo_uart.sv
├── top_002_vga_test.sv
├── top_003_sdram_demo.sv
```

* V prípade viacero súborov na demo môže byť aj podadresár:

```
examples/
└── uart_demo/
    ├── top.sv
    └── sim_tb.sv
```

---

## 4.2 Pravidlá názvov

* Súbory s kódom: malé písmená, podčiarkovníky, prípona `.sv` alebo `.vhd` podľa jazyka.
* Testbenche, simulácie: prípona `_tb.sv` alebo `_tb.vhd`.
* Top-level entity: jasný popis funkcie, napr. `top_uart_bridge.sv`.

---

## 4.3 Ďalšie odporúčania

* V každom väčšom adresári (rtl, lib, examples) README.md s krátkym popisom, čo obsahuje.
* Verzionovanie knižníc, ak sú samostatné moduly často aktualizované (napr. v hlavičke súborov).
* Udržiavať separáciu medzi vlastným kódom (rtl/) a knižnicami (lib/), aby sa dal projekt lepšie rozšíriť.

---

Ak chceš, môžem ti pripraviť ukážkové README pre `rtl/`, `lib/`, `examples/` alebo šablónu adresárovej štruktúry na implementáciu. Alebo pokračujeme ďalším bodom?
