Super! Poďme teraz rozšíriť simuláciu o:

---

## 🖼️ **Farebný výstup z RAM** (napr. farebný pruh cez obraz)

---

### 🧱 Čo zmeníme:

* Inicializujeme framebuffer obsahujúci **farebný gradient** (napr. červený pruh odľava doprava)
* Zobrazíme ho cez VGA
* Uvidíme v simulácii, že výstup RGB mení hodnotu podľa `pixel_x`

---

## 🔧 Úprava modulu `vga_pixel_fetch.sv`

➡️ Nahraď `initial begin ... end` v pôvodnom module týmto novým obsahom:

```systemverilog
  // --- Inicializácia framebufferu: horizontálny gradient ---
  initial begin
    for (int y = 0; y < V_ACTIVE; y++) begin
      for (int x = 0; x < H_ACTIVE; x++) begin
        logic [7:0] red   = x[9:2]; // 0..255
        logic [7:0] green = 8'h00;
        logic [7:0] blue  = 8'h00;
        framebuffer[y * H_ACTIVE + x] = {red, green, blue};
      end
    end
  end
```

### Výsledok:

* R = pozícia X (0 → 255)
* G, B = 0
* Výsledok: **červený horizontálny gradient**

---

## 🧪 Čo sledujeme v GTKWave:

* `de_out = 1` → RGB výstup mení hodnotu od `00` po `FF` v R
* `v_counter` → keď sa mení rad (y), `rgb_r` sa opakuje
* `h_counter` → určuje pozíciu x, ktorá ovplyvňuje jas červenej

---

## 📷 Chceš vytvoriť výstup simulácie ako **obrázok (BMP/PNG)**?

➡️ Môžeme:

* Simulovať celý frame
* Exportovať hodnoty `rgb_r`, `rgb_g`, `rgb_b` pre každú pixel pozíciu
* Vytvoriť `.ppm` alebo `.bmp` obrázok zo simulácie

---

### ❓ Pokračovať týmto smerom?

1. ✅ Vygenerovať `.ppm` súbor z výstupu
2. ✅ Pridať do testbenchu export rámika
3. ✅ Ukázať ako to otvoriť ako obrázok (napr. cez GIMP alebo `feh`)

Povedz len „vygeneruj obrázok“ alebo „áno“.
