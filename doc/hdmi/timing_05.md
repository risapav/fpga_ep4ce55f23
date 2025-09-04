Super! Tu je krátky návod, ako spustiť simuláciu a otvoriť vlnový priebeh (predpokladám, že používaš **Icarus Verilog** a **GTKWave**):

---

## 1. Uloženie súborov

* `hdmi_tx_fsm.sv` — tvoj stavový automat
* `tb_hdmi_tx_fsm.sv` — testbench

---

## 2. Kompilácia a simulácia (Linux / Windows s bash)

```bash
iverilog -g2012 -o tb_hdmi_tx_fsm.vvp hdmi_tx_fsm.sv tb_hdmi_tx_fsm.sv
vvp tb_hdmi_tx_fsm.vvp
```

Týmto sa spustí simulácia a vytvorí `.vcd` súbor.

---

## 3. Otvorenie vlnového priebehu v GTKWave

```bash
gtkwave tb_hdmi_tx_fsm.vcd
```

---

## 4. Čo sledovať v GTKWave?

* signály: `de`, `video_active`, `data_island`, `control_period`
* časy prechodu medzi stavmi počas riadkov a rámcov
* `h_counter`, `v_counter` pre overenie načasovania

---

Ak používaš iné prostredie, alebo chceš automatizovať spustenie, kľudne mi napíš, pomôžem s tým skriptom alebo s príkazmi.

---

Pokiaľ chceš pokračovať, napíš, čo ďalej — napríklad integrácia do TMDS kódovania, ďalšie testy, alebo niečo úplne iné.
