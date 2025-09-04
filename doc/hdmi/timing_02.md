Super! Poďme spraviť **kompletný stavový automat** pre HDMI výstup, ktorý rozlišuje medzi tromi hlavnými obdobiami v HDMI rámci:

---

## 🎯 Cieľ:

Vyrobiť **stavový automat**, ktorý bude prepínať medzi:

1. `CONTROL` – mimo aktívneho obrazu, neodosiela sa nič (alebo Guard Band)
2. `VIDEO` – vysiela sa obraz, `DE = 1`
3. `ISLAND` – čas na audio alebo iné dátové pakety, `DE = 0`, ale **mimo porchu**

---

## 🧱 Predpoklady:

Používame dva počítadlá:

* `h_counter` – horizontálne pixely (riadky)
* `v_counter` – vertikálne riadky (snímky)

A máme načítané tieto hodnoty:

* `H_SYNC`, `H_BP`, `H_ACTIVE`, `H_FP`
* `V_SYNC`, `V_BP`, `V_ACTIVE`, `V_FP`

---

## 🧠 Stavový automat (`TX_state_e`)

```systemverilog
typedef enum logic [1:0] {
    TX_CONTROL,   // mimo aktívneho obrazu
    TX_VIDEO,     // aktívne video (DE = 1)
    TX_ISLAND     // audio / info packets
} TX_state_e;
```

---

## 📘 Definícia logiky

### Horizontálna fáza:

```systemverilog
assign h_video_active = (h_counter >= H_SYNC + H_BP) &&
                        (h_counter <  H_SYNC + H_BP + H_ACTIVE);
```

### Vertikálna fáza:

```systemverilog
assign v_video_active = (v_counter >= V_SYNC + V_BP) &&
                        (v_counter <  V_SYNC + V_BP + V_ACTIVE);
```

### Data Enable:

```systemverilog
assign de = h_video_active && v_video_active;
```

---

## 🧠 Stavový automat:

```systemverilog
TX_state_e tx_state;

always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tx_state <= TX_CONTROL;
    end else begin
        case (tx_state)
            TX_CONTROL: begin
                if (de)
                    tx_state <= TX_VIDEO;
                else if (!de && (v_counter >= V_SYNC + V_BP + V_ACTIVE))
                    tx_state <= TX_ISLAND; // voliteľná podmienka
            end

            TX_VIDEO: begin
                if (!de)
                    tx_state <= TX_CONTROL;
            end

            TX_ISLAND: begin
                if (de)
                    tx_state <= TX_VIDEO;
                else if ((v_counter < V_SYNC + V_BP + V_ACTIVE))
                    tx_state <= TX_CONTROL;
            end

            default: tx_state <= TX_CONTROL;
        endcase
    end
end
```

---

## 🧪 Výstupy:

Môžeme si z toho spraviť výstupné signály:

```systemverilog
assign video_active = (tx_state == TX_VIDEO);
assign data_island  = (tx_state == TX_ISLAND);
assign control_period = (tx_state == TX_CONTROL);
assign de = video_active;
```

---

## 🧩 Voliteľné zlepšenie:

Ak budeš chcieť generovať HDMI TMDS kódovanie neskôr, stav `TX_STATE` sa používa v encoderi na výber:

* `VIDEO`: TMDS z RGB (pixel data)
* `ISLAND`: TMDS z packetov (napr. audio, SPD)
* `CONTROL`: TMDS control codes (porch, guard bands)

---

## ✅ Zhrnutie

| Stav    | DE | HDMI TMDS obsah            |
| ------- | -- | -------------------------- |
| CONTROL | 0  | Control period             |
| VIDEO   | 1  | RGB dáta (video)           |
| ISLAND  | 0  | Data islands (audio, info) |

---

## Ďalší krok:

Ak chceš, môžeme hneď:

* 💾 Vytvoriť testbench (stimuly: `h_counter`, `v_counter`)
* 📈 Generovať waveform (napr. v GTKWave)
* 🧪 Overiť, že `TX_state` sa mení podľa očakávaní

Stačí napísať *„pokračuj simuláciou“* a rovno to rozbeháme.
