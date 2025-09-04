Ideme na **5. Dokumentácia projektu**!

---

# 5. Dokumentácia projektu

---

## 5.1 README.md na koreňovej úrovni

* Mala by obsahovať:

  * Krátky popis projektu (čo to je, účel)
  * Použité technológie (napr. FPGA model, jazyk, toolchain)
  * Štruktúru projektu (krátky prehľad hlavných adresárov)
  * Inštrukcie na build a simuláciu
  * Ako pridať nové moduly alebo príklady
  * Kontakty a licenciu

---

## 5.2 README.md v podadresároch

* **rtl/** – čo je tam obsiahnuté, prípadne hlavné entity
* **lib/** – aké knižnice sú, prečo sa používajú
* **examples/** – krátky popis príkladov, ako ich spustiť alebo simulovať

---

## 5.3 Použitie Markdown a odkazy

* Odkazy medzi dokumentmi (napr. README v koreňi odkazuje na `doc/` alebo na `rtl/README.md`)
* Zrozumiteľné popisy, použitie formátovania (odseky, zoznamy, kódové bloky)
* Možnosť pridať diagramy (napr. blokové schémy), môžeš ich generovať externými nástrojmi a ukladať ako obrázky v `doc/images/`

---

## 5.4 Dokumentácia modulov a kódu

* Komentáre v kóde štandardizované (napr. `///` alebo `/** ... */` pre systémové komentáre)
* Ak používaš systém dokumentácie (napr. Doxygen, Sphinx), udržiavaj konfiguráciu a generované dokumenty v adresári `doc/`
* Popis vstupov/výstupov, parametrov modulov v komentároch priamo v HDL

---

## 5.5 Pravidelná aktualizácia

* Dokumentáciu aktualizovať spolu s kódom, nenechávať ju „zastaralú“
* Môžeš zaradiť checklist do PR (pull request) – „Dokumentácia je aktuálna“

---

Ak chceš, môžem ti rovno pripraviť vzorový README.md pre koreňový adresár alebo podadresár. Alebo pokračujeme ďalším bodom?
