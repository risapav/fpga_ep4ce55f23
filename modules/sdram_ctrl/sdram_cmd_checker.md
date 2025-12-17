# Modul `sdram_cmd_checker`

## Popis

SDRAM Command Validator (Gatekeeper).

Validuje príkazy pred vstupom do radiča.
- Bráni nelegálnym operáciám (Row Conflict, Bank Busy).
- Udržiava "tieňový stav" (Shadow State) bánk pre predikciu konfliktov.
- Rieši deadlocky tým, že chybné príkazy zahodí (akceptuje handshake, ale nepošle ďalej).

## Parametre

- `C_NUM_BANKS`: Počet bánk (automaticky).
- `T_*_CYCLES`: Časovanie pre kontrolu busy stavov.

