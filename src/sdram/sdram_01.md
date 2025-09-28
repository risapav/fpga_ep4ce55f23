Perfektne! Tu je prehľadný **blokový diagram zápisov a čítania SDRAM** vo forme textovej schémy so všetkými kľúčovými signálmi a pipeline, ktorý vysvetľuje aj časovače a auto-precharge. Je to určené na pochopenie logiky pre simulácie alebo dokumentáciu:

---

### SDRAM Controller – Bloková schéma (logická)

```
              +-------------------------+
              |       CMD FIFO          |
              |-------------------------|
              | cmd_fifo_valid          |
              | cmd_fifo_data[sdram_cmd_t]
              | cmd_fifo_ready          |
              +-----------+-------------+
                          |
                          v
             +--------------------------+
             |       FSM / Control      |
             |--------------------------|
             | state / next_state       |
             | load_trcd / next_trcd    |
             | load_trp / next_trp      |
             | load_twr / next_twr      |
             | load_trfc / next_trfc    |
             | load_burst_cnt / next_bc |
             | auto_precharge_pending_next |
             | auto_precharge_bank_next |
             +-----------+--------------+
                         |
        +----------------+----------------+
        |                                 |
        v                                 v
+------------------+             +------------------+
| SDRAM Addressing |             |   Data Pipeline  |
|-----------------|             |-----------------|
| sdram_addr       |<------------| read_pipe_data   |
| sdram_ba         |             | read_pipe_valid  |
| sdram_cs_n       |             | resp_valid       |
| sdram_ras_n      |             | resp_last        |
| sdram_cas_n      |             | resp_data        |
| sdram_we_n       |             | dq_write_enable  |
| sdram_dqm        |             | wdata_ready      |
| sdram_cke        |             | wdata_valid      |
+------------------+             +-----------------+
        |
        v
+------------------+
|      SDRAM       |
|------------------|
| sdram_dq [DATA_WIDTH] |
+------------------+
```

---

### Popis hlavných blokov

1. **CMD FIFO**

   * Prijíma príkazy typu `sdram_cmd_t` (READ/WRITE + adresy + auto-precharge).
   * FIFO handshake: `cmd_fifo_valid` / `cmd_fifo_ready`.

2. **FSM / Control**

   * Riadi **stavový stroj**: INIT_WAIT → INIT_PRECHARGE → INIT_REFRESH1/2 → IDLE → ACTIVE_CMD → RW_CMD → READ/WRITE_BURST → PRECHARGE_CMD → REFRESH_CMD.
   * Vypočítava **next_* signály pre časovače** a burst počítadlo.
   * Spravuje **auto-precharge pending**, aby sa vyhol multiple drivers.

3. **SDRAM Addressing**

   * Riadi výstupy `sdram_addr`, `sdram_ba`, `sdram_cs_n`, `sdram_ras_n`, `sdram_cas_n`, `sdram_we_n`, `sdram_dqm`, `sdram_cke`.
   * Hodnoty sú generované podľa stavu FSM a príkazu.

4. **Data Pipeline**

   * Posúva dáta z čítania cez registrovanú pipeline (`read_pipe_data`) podľa `CAS_LATENCY`.
   * Výstupy `resp_valid`, `resp_last` a `resp_data` sú z pipeline.
   * Pri zápise riadi `dq_write_enable`, `wdata_ready`, `sdram_dqm` a sleduje burst.

5. **SDRAM**

   * Pripojená cez `sdram_dq`, `sdram_addr`, `sdram_ba`, riadiace signály a DQM.
   * Čítanie a zápis sú synchronizované s pipeline a časovačmi FSM.

---

### Časovače a ich úloha

| Časovač           | Popis                                  |
| ----------------- | -------------------------------------- |
| `trcd_timer`      | Čas medzi ACTIVE a READ/WRITE príkazom |
| `trp_timer`       | Precharge čas                          |
| `twr_timer`       | Write Recovery (po zápise)             |
| `trfc_timer`      | Refresh cyklus                         |
| `refresh_counter` | Periodický refresh interval            |
| `burst_cnt`       | Počítadlo dátových beatov              |

---

### Auto-Precharge logika

* Pri príkaze READ/WRITE s `auto_precharge_en` sa nastaví:

  ```verilog
  auto_precharge_pending_next = 1'b1;
  auto_precharge_bank_next = current_cmd.addr[23:22];
  ```
* Po dokončení burstu FSM prejde do stavu `PRECHARGE_CMD`, kde sa pre konkrétnu banku vykoná precharge.

---

Ak chceš, môžem ti urobiť aj **ASCII diagram pipeline čítania a zápisu so všetkými časovačmi a CAS_LATENCY**, kde bude vidieť presne, v ktorom cykle sa dáta čítajú a posúvajú – veľmi vhodné na simulácie a debug.

Chceš, aby som urobil aj tento diagram?
