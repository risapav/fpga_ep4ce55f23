# Modul `gray_to_bin`

## Popis

Kombinačný prevodník z Gray kódu na binárny.

Čisto kombinačný prevod pointera v Gray kóde na binárny.
Algoritmus: b[N] = g[N], b[i] = b[i+1] ^ g[i].

## Parametre

- `ADDR_WIDTH`: Počet adresových bitov (šírka zbernice = ADDR_WIDTH+1).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `gray_i` | Vstupný vektor v Gray kóde. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `bin_o` | Výstupný vektor v binárnom kóde. |

