# Modul `axis_stream_checker`

## Popis

Checker pre AXI4-Stream protokol (TUSER, TLAST, Frame Dimensions).

Overuje integritu video streamu. Detekuje chýbajúci TLAST,
nesprávny SOF (TUSER[0]), a nezhodu rozmerov snímky.
Obsahuje diagnostické počítadlá a latchovanie prvej chyby.

## Parametre

- `FRAME_WIDTH`: Očakávaná šírka snímky.
- `FRAME_HEIGHT`: Očakávaná výška snímky.
- `C_ENABLE_CHECKS`: Povolenie logiky checkera (0 = optimalizácia pre syntézu).
- `C_ENABLE_ASSERTS`: Povolenie simulačných správ.
- `C_STRICT_MODE`: 1 = $error (Stop), 0 = $warning.

