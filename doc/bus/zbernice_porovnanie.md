Skvelá otázka! Porovnanie **AXI4** a **Wishbone** zberníc je dôležité pri návrhu SoC, najmä ak cieliš na implementáciu vo **FPGA**. Obe zbernice slúžia ako **interconnect protokoly** medzi IP blokmi (napr. CPU, periférie, DMA, atď.), ale majú rôznu komplexnosť, schopnosti a podporu.

---

## 🔄 **AXI4 vs. Wishbone – základné porovnanie**

| Vlastnosť                       | **AXI4 (AMBA AXI v4)**                         | **Wishbone (ver. B4)**                |
| ------------------------------- | ---------------------------------------------- | ------------------------------------- |
| **Pôvod**                       | ARM (AMBA štandard)                            | OpenCores (open-source štandard)      |
| **Komplexnosť**                 | Vysoká                                         | Nízka až stredná                      |
| **Typ zbernice**                | Viackanálová, point-to-point                   | Zdieľaná alebo point-to-point         |
| **Podpora burst prenosov**      | Áno (fixed/incr/wrap)                          | Áno (jednoduché bursty)               |
| **Podpora pipeliningu**         | Áno                                            | Čiastočná                             |
| **Podpora out-of-order**        | Áno (ID systém)                                | Nie                                   |
| **Handshake protokol**          | Valid/Ready (decoupled handshake)              | Ack/Strobe/We/Select (tight coupling) |
| **Cache, QoS, ochrana**         | Áno (AXI4 má tieto možnosti)                   | Nie                                   |
| **Latency a deterministickosť** | Nízka, ale menej predvídateľná                 | Nižšia, deterministickejšia           |
| **Ľahká syntéza vo FPGA?**      | Áno, ale potrebuje viac logiky/zdrojov         | Áno, veľmi ľahká pre malé systémy     |
| **Licencia**                    | Open, ale AXI4 nie je úplne open-source        | Open-source, bez obmedzení            |
| **Ekosystém a nástroje**        | Silná podpora v Xilinx (Vivado, IP integrator) | Dobrá podpora v open-source komunite  |

---

## 🧠 **AXI4 – výhody a nevýhody**

### ✅ Výhody:

* **Škálovateľnosť:** Podporuje viac master/slave zariadení.
* **High-performance:** Paralelné kanály (read/write address, read/write data, response).
* **Burst podpora a QoS:** Efektívne pre veľké blokové prenosy.
* **Out-of-order a ID-based prenosy:** Umožňuje sofistikovaný memory traffic.

### ❌ Nevýhody:

* **Komplexnosť protokolu:** Vyžaduje viac riadiacej logiky.
* **Vyššia spotreba zdrojov v FPGA:** Viac FF/LUT a routing.
* **Ťažšie debugovanie:** Viac signálov, viac stavov.

---

## 🔧 **Wishbone – výhody a nevýhody**

### ✅ Výhody:

* **Jednoduchosť:** Ľahko sa implementuje a simuluje.
* **Open-source friendly:** Žiadna licencia alebo NDA.
* **Dobrá čitateľnosť:** Vhodné pre výučbu, výskum, malé SoC dizajny.
* **Efektívne v malých/úzkopásmových aplikáciách:** Zvlášť periférie s jedným masterom.

### ❌ Nevýhody:

* **Slabšia výkonnosť pre veľké systémy:** Bez pipeliningu a pokročilého routingu.
* **Bez podpory QoS, ID, cache:** Nie je vhodný pre pokročilé systémy.
* **Obmedzená podpora v komerčných nástrojoch:** Žiadna natívna podpora vo Vivado, Quartus.

---

## 💡 **Kedy použiť AXI4 vs. Wishbone vo FPGA SoC:**

| Scenár                                                   | Odporúčaná zbernica               |
| -------------------------------------------------------- | --------------------------------- |
| Používam **Xilinx SoC (Zynq, MicroBlaze)**               | **AXI4** – natívna podpora        |
| Staviam **malý softcore SoC (napr. VexRiscv, PicoRV32)** | **Wishbone** alebo **SimpleBus**  |
| Potrebujem **vysokú priepustnosť (DMA, SDRAM)**          | **AXI4**                          |
| Chcem **rýchly prototyp, nízke nároky**                  | **Wishbone**                      |
| Používam **LiteX, Open SoC, open-source nástroje**       | **Wishbone** je často preferovaný |

---

## ✳️ Záver

* **AXI4** je výkonný, moderný, ale náročný. Hodí sa pre **komplexné systémy, high-performance SoC, komerčné nástroje (Vivado, Zynq)**.
* **Wishbone** je jednoduchý, priateľský pre **malé alebo vzdelávacie projekty**, vhodný pre **open-source IP jadra** a **lightweight SoC**.

Ak chceš, môžem ti pripraviť **šablónu modulu periférie s AXI4 aj Wishbone rozhraním**, aby si videl rozdiel v implementácii. Stačí povedať, čo má periféria robiť.
