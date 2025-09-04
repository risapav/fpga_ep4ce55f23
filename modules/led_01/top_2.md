# Modul `top`

## Popis

Testovací modul pre FPGA, ktorý generuje tri nezávislé vizuálne efekty na troch skupinách LED diód v sekundových intervaloch.

Modul implementuje tri odlišné svetelné vzory pre demonštračné a testovacie účely. Hlavný časovač, odvodený od systémových hodín, generuje impulz každú sekundu, ktorý spúšťa zmenu stavu vo všetkých troch efektoch súčasne.
Podporované efekty sú:
1. 6-bitové vstavané LED: Klasické "bežiace svetlo" (cyklický posun).
2. 8-bitové LED na J10: Efekt "plniaceho sa stĺpca", kde sa LED postupne rozsvecujú a po dosiahnutí plného počtu zhasnú.
3. 8-bitové LED na J11: Efekt "Cylon Eye" / "Larson Scanner", kde sa jedna LED pohybuje tam a späť po celej dĺžke.

Vstupy BSW a výstupy pre 7-segmentový displej a VGA sú v návrhu deklarované, ale nie sú aktívne využívané a sú nastavené na log. 0.

## Parametre

- `[in]`: CLK_FREQ         Frekvencia vstupných systémových hodín v Hz. Predvolená hodnota je 50,000,000 (50 MHz).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `SYS_CLK` | Vstupný hodinový signál. |
| `RESET_N` | Aktívny nízky asynchrónny reset signál. |
| `BSW` | 6-bitový vstup z prepínačov (v tomto návrhu nevyužitý). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `LED` | 6-bitový výstup pre vstavané LED diódy (efekt bežiaceho svetla). |
| `LED_J10` | 8-bitový výstup pre externé LED diódy (efekt plniaceho sa stĺpca). |
| `LED_J11` | 8-bitový výstup pre externé LED diódy (efekt 'Cylon Eye'). |
| `SMG_SEG` | Výstup pre segmenty 7-segmentového displeja (nevyužitý, nastavený na 0). |
| `SMG_DIG` | Výstup pre anódy/katódy 7-segmentového displeja (nevyužitý, nastavený na 0). |
| `VGA_R,` | G, B      Výstupy pre farebné zložky VGA (nevyužité, nastavené na 0). |
| `VGA_HS,` | VGA_VS   Výstupy pre VGA synchronizáciu (nevyužité, nastavené na 0). |

## Príklady použitia

```systemverilog
// Ukážka inštancie modulu pre 100 MHz hodiny
top #(
.CLK_FREQ(100_000_000)
) u_led_tester (
.SYS_CLK(i_clk_100mhz),
.RESET_N(i_reset_n),
.LED(o_board_leds),
.LED_J10(o_j10_leds),
.LED_J11(o_j11_leds),
// Ostatné porty môžu byť ponechané nepripojené, ak to kontext dovoľuje
.BSW(),
.SMG_SEG(),
.SMG_DIG(),
.VGA_R(),
.VGA_G(),
.VGA_B(),
.VGA_HS(),
.VGA_VS()
);
```

