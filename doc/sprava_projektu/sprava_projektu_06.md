Ideme na **6. Automatizácia build a test procesu**!

---

# 6. Automatizácia build a test procesu

---

## 6.1 Skripty na build

* Priprav shell alebo Python skripty (`build.sh`, `run_tests.sh`) na spustenie celého procesu buildovania FPGA projektu, kompilácie, syntézy, a generovania bitstreamu.
* Skripty by mali mať základné možnosti, napríklad:

  * `./build.sh clean` — vyčistí predchádzajúce build súbory
  * `./build.sh all` — kompletný build projektu
  * `./build.sh synth` — spustí len syntézu
  * `./build.sh sim` — spustí simuláciu

---

## 6.2 Automatizácia testov

* Ak máš testbenche v `simulation/`, automatizuj ich spúšťanie cez skripty.
* Umiestni základné testy do repozitára, môžeš použiť frameworky (napr. cocotb, Questa command-line tools).

---

## 6.3 Integrácia s CI/CD

* Ak používaš GitHub/GitLab, nastav pipeline, ktorá pri pushi alebo PR automaticky:

  * Spustí build skript
  * Spustí testy (simulácie)
  * Vygeneruje reporty
* Výsledky build/testov sú potom rýchlo dostupné všetkým vývojárom, čo znižuje riziko chýb

---

## 6.4 Udržiavanie skriptov

* Dokumentuj používanie skriptov (README, komentáre)
* Zahrň kontrolu chýb v skriptoch (napr. exit code)
* Udržiavaj ich aktuálne podľa zmien v toolchaine alebo projekte

---

Chceš, aby som ti pomohol navrhnúť konkrétny build skript, alebo pokračujeme ďalším bodom?
