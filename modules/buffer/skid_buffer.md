# Modul `skid_buffer`

## Popis

Full-Throughput Pipeline Register (Skid Buffer).

Buffer, ktorý oddeľuje časovanie na rozhraní Ready/Valid bez
zavedenia čakacích cyklov (wait-states).
- Ak je Master pripravený a Buffer prázdny: Dáta prechádzajú priamo (kombinačne).
- Ak Master nie je pripravený: Dáta sa uložia do buffera (skid).

## Parametre

- `WIDTH`: Šírka dátovej zbernice.

