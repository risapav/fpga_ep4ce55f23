# Modul `gray_counter_2bit`

## Popis

Synchronny 2-bitovy citac s Grayovym kodom.

Modul implementuje 2-bitovy citac, ktory prechadza sekvenciou
Grayovho kodu: 00 -> 01 -> 11 -> 10 -> 00 ...
Citac ma asynchronny aktivny v nule reset a synchronne povolenie (enable).
Pri resete je vystup nastaveny na 2'b00.
Ak je povolenie neaktivne, citac si drzi svoju aktualnu hodnotu.

