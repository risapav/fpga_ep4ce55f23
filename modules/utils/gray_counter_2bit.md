# Modul `gray_counter_2bit`

## Popis

Synchrónny 2-bitový čítač s Grayovým kódom.

Modul implementuje 2-bitový čítač, ktorý prechádza sekvenciou
Grayovho kódu: 00 -> 01 -> 11 -> 10 -> 00 ...
Čítač má asynchrónny reset (aktívny v nule) a synchrónne povolenie (enable).
Pri resete je výstup nastavený na 2'b00.
Ak je povolenie neaktívne, čítač si drží svoju aktuálnu hodnotu.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Vstupný hodinový signál. |
| `rst_ni` | Asynchrónny reset, aktívny v nule. |
| `en_i` | Synchrónne povolenie čítania. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `gray_count_o` | Výstupná 2-bitová hodnota Grayovho kódu. |

