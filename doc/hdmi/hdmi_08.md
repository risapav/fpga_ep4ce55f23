Jasné, rád ti to ozrejmím!

---

## Ako sa infoframe integruje do HDMI TMDS linky?

1. **Čo je infoframe?**
   Infoframe je dátový paket, ktorý HDMI používa na prenos dodatočných informácií (napr. SPD — source product description, AVI — video info, audio infoframe, atď). Tieto pakety sú posielané v špeciálnych časoch — tzv. *Data Island Periods*, ktoré sú mimo bežného video signálu.

2. **Kde sa infoframe posiela?**

   * Video sa prenáša počas *Video Data Period* (typicky v aktívnej časti obrazovky).
   * Infoframe sa posiela počas *Data Island Period* (medzi rámcami, keď sa neposiela aktívny video obsah).
   * V HDMI sa kódovanie dát a infoframov rieši pomocou TMDS (Transition Minimized Differential Signaling), kde sa každá farba a doplnkové dáta transformujú na 10-bitové TMDS kódy.

3. **Ako sa to deje v kóde?**

   * **Generátor infoframe** (ako je SPD v príklade) pripraví záhlavie a payload infoframu.
   * **Multiplexor infoframov** rozhodne, ktorý infoframe sa práve posiela (napr. SPD, AVI, Audio alebo nič).
   * **Ovládač infoframe** rozhoduje *kedy* a *ktorý* infoframe sa posiela na základe časovania (napríklad raz za sekundu SPD, často AVI atď).
   * **TMDS kanály** prijímajú video dáta alebo tieto infoframe dáta podľa signálu režimu a potom ich kódujú do TMDS 10-bitového formátu.
   * Nakoniec sa signály posielajú cez HDMI konektor ako diferencované signály.

4. **Prepojenie do HDMI modulu**

   * V HDMI module existuje *časovač* alebo *stavový automat*, ktorý sleduje kde sme v rámci snímky (pixelová pozícia, riadok, rámec).
   * Na základe toho vie, kedy nastáva Data Island Period (prázdne časti medzi video rámcami).
   * Vtedy *prepne* výstup dát z video dát na infoframe dáta (SPD, AVI...).
   * TMDS kódovač potom tieto dáta skompresuje a zakóduje podľa HDMI špecifikácie.

---

## Prečo to takto rozdeliť?

* Modularita — rôzne infoframe moduly (SPD, AVI, audio) môžu byť nezávisle vyvíjané a potom multiplexované.
* Jednoduchosť — HDMI signálova linka nemusí riešiť podrobnosti infoframe, stačí dostávať správne „pakety“ pripravené vyššími vrstvami.
* Synchronizácia — ovládač vie, kedy treba infoframe vložiť, a kedy zas video.

---

## Čo ešte treba pre úplnú integráciu?

* **Časovanie HDMI** — určiť presné pixely/riady, kedy je Data Island Period.
* **Prepínač dát** — ktorý prepne video dátové linky na infoframe dáta a späť.
* **CRC kontrola infoframe** — HDMI vyžaduje CRC32 checksum pre každý infoframe, treba ho vypočítať a pridať do paketov.
* **TMDS kódovanie** — rozšíriť TMDS kanály, aby podporovali aj kódovanie infoframe dát.
* **Testovanie a simulácia** — overiť správnosť časovania, dát a signálov v simulácii i na reálnom HW.

---

Ak chceš, môžem ti vyrobiť príklad takéhoto prepínača dát alebo stavu Data Island Period, prípadne aj TMDS kanál s podporou infoframe. Alebo môžeme rozobrať CRC generátor, prípadne prípadné laditeľné parametre (intervaly vysielania infoframe).

---

Chceš, aby som pripravil niektorú z týchto častí? Alebo potrebuješ niečo ozrejmiť detailnejšie?
