# Paranoid Tools — промт-пак для nano banana

Бренд-идентика для опенсорсного приватного тулкита (чистые Bash-утилиты).
Концепция: **engraved instrument** — гравировка по дисциплине часового циферблата
и геометрии клинка. Монохром, монолиния, высокий контраст, ноль украшательства.

> Как пользоваться: всегда вставляй блок **BRAND DNA** в начало каждого промта,
> затем добавляй блок конкретного ассета. Промты — на английском (Gemini рисует
> точнее на нём). Текст/вордмарк генерится ненадёжно — финальные буквы доводи
> в векторном редакторе, не доверяй буквам модели.

---

## 0 · BRAND DNA (вставлять перед каждым промтом)

```
Brand DNA for "Paranoid Tools", a minimalist open-source privacy toolkit of pure
Bash CLI tools. Aesthetic: luxury-clean, engraved-instrument precision — the
restraint of a watch dial and the geometry of a fine blade. Strictly monoline
vector: one uniform hairline stroke weight, mathematically precise, sharp corners
with a micro-radius, perfectly centered, generous negative space. Palette is
monochrome only: ink charcoal #0E0E10 and porcelain bone #F2EFE8. No gradients,
no 3D, no bevels, no drop shadows, no glow, no neon, no photographic texture, no
skeuomorphism, no clutter. Flat, timeless, intentional. Think engraved watch
movement meets a terminal prompt.
```

**Один акцент на всю систему:** `#D8973C` (выдержанный янтарь) — используется
*только* для иконки `panic` и для алертных состояний. Альтернатива — сигнальный
красный `#E5484D`, если янтарь покажется тихим. Это единственная ручка, которую
стоит крутить; всё остальное держи монохромным.

---

## 1 · Мастер-знак (primary mark)

```
[BRAND DNA]
Design the primary logo mark: a single precise square boundary drawn with one
continuous monoline, the perimeter reading as if a line is being drawn closed —
simultaneously a locked box, a self-drawn boundary, and a terminal command frame.
Centered inside: one small solid dot (the secret) and a minimal keyhole notch
integrated cleanly into the lower edge. Uniform hairline stroke, engraved feel.
Porcelain #F2EFE8 mark on a flat solid ink #0E0E10 background. Icon only, no text,
heavily centered with wide empty margins. Square 1:1.
```

Сразу попроси **инверсию**: тот же знак, чернильная линия `#0E0E10` на фарфоровом
фоне `#F2EFE8` — для светлых поверхностей.

---

## 2 · Логотип-локап (знак + вордмарк)

```
[BRAND DNA]
Horizontal logo lockup: the square boundary mark on the left; to its right the
wordmark "paranoid tools", all lowercase, in a refined geometric monospace with
generous tracking. The mark height equals the type's cap height; precise baseline
alignment, watch-dial typographic discipline. Porcelain #F2EFE8 on flat ink
#0E0E10. Lockup centered with wide margins. Square 1:1.
```

> Буквы почти наверняка придётся перенабрать в Figma/Illustrator. Хороший
> монопространственный кандидат под этот характер: JetBrains Mono, Berkeley Mono,
> Commit Mono или Space Mono.

---

## 3 · Набор иконок инструментов (5 шт.)

Лучшая консистентность — сгенерировать **все пять в одной сетке** (промт ниже),
потом нарезать. Если нужны по отдельности — под сеткой даны индивидуальные глифы.

### 3a · Всё семейство одним кадром (рекомендую)

```
[BRAND DNA]
A 2x3 grid of five line-icon glyphs in one identical visual system (last cell
empty), each glyph optically the same size, same hairline stroke, centered in its
cell, porcelain #F2EFE8 on flat ink #0E0E10:
1. ghostdraft — an outlined draft page with a dashed, ghosted edge and a blinking
   text caret inside; weightless, leaves no trace.
2. securetrash — a sealed vault box bisected by one clean diagonal blade-cut;
   honest destruction, precise, not a cartoon trash can.
3. vaultwatch — a small box ringed by a precise perimeter line that pinches inward
   at points; narrowed leak channels, a guarded boundary.
4. panic — a single decisive round kill-switch button, a lid slamming everything
   shut at once; this glyph (and only this one) drawn in alert amber #D8973C.
5. seedsplit — a circle (a seed) cleanly divided into several geometric shares
   radiating slightly apart; Shamir split, any T reassemble.
Strict monoline geometry, uniform spacing, no labels, no background texture.
Square 1:1.
```

### 3b · По отдельности (если нужно)

Бери `[BRAND DNA]` + соответствующую строку, формат `Square 1:1, single centered
monoline glyph, porcelain #F2EFE8 on flat ink #0E0E10`:

- **ghostdraft** — `an outlined draft page with a dashed ghosted edge and a blinking text caret inside; weightless, trackless.`
- **securetrash** — `a sealed vault box bisected by one clean diagonal blade-cut; precise honest destruction.`
- **vaultwatch** — `a small box ringed by a perimeter line that pinches inward at points; narrowed channels, a watchful guarded boundary.`
- **panic** — `a single decisive round kill-switch button, a lid slamming shut over everything; drawn in alert amber #D8973C on ink #0E0E10.`
- **seedsplit** — `a circle divided into several geometric shares radiating slightly apart; a seed split into pieces, any threshold reassembles it.`

---

## 4 · App icon / tile

```
[BRAND DNA]
An app icon: a rounded-square tile filled flat ink #0E0E10, the primary square
boundary mark centered in porcelain #F2EFE8, optically balanced with safe margins,
no text. Crisp, minimal, premium. Square 1:1.
```

## 5 · Favicon (читаемость на 16px)

```
[BRAND DNA]
A favicon-grade reduction of the mark: just the square boundary plus the central
dot, stroke weight increased for legibility at tiny sizes, no keyhole detail.
Porcelain #F2EFE8 on flat ink #0E0E10. Square 1:1, centered.
```

## 6 · OG / соц-баннер (16:9)

```
[BRAND DNA]
A wide hero banner: flat ink #0E0E10 field with vast negative space; the primary
mark and the "paranoid tools" wordmark grouped slightly left of center in
porcelain #F2EFE8; small caps tagline "privacy, not anonymity" set quietly beneath.
Calm, editorial, premium restraint. Aspect ratio 16:9.
```

## 7 · Terminal splash (опционально)

```
[BRAND DNA]
A terminal-style splash: flat ink #0E0E10 background, the mark top-left, and a
clean monospace block beneath reading a short credo, in porcelain #F2EFE8. Looks
like an engraved man-page header — disciplined, monospaced, no decoration. 16:9.
```

## 8 · Спек-лист системы (для презентации / README)

```
[BRAND DNA]
A single brand-system presentation board on flat ink #0E0E10: the primary mark
top-center; below it a precise row of the five tool glyphs (ghostdraft,
securetrash, vaultwatch, panic, seedsplit) in the same monoline system; a small
row of palette swatches (#0E0E10, #F2EFE8, #D8973C); everything porcelain
#F2EFE8, laid out with the rigor of a watch-movement exploded diagram. 16:9.
```

---

## Как держать семейство консистентным в nano banana

1. **Сначала мастер-знак** (раздел 1). Отбери лучший результат — это эталон.
2. **Iterative editing:** загрузи эталон обратно и для каждого ассета пиши
   *"keep this exact stroke weight, corner style and porcelain-on-ink palette;
   now produce …"*. Так глифы наследуют характер мастер-знака.
3. **Иконки — сеткой** (3a), а не по одной: в одном кадре модель сама держит
   единый вес линии и масштаб. Нарежешь потом.
4. **Текст не доверяй модели.** Любой вордмарк/подписи перенабери в Figma/AI.

## Технические заметки

- Проси **flat solid #0E0E10 background, no gradient** — так знак легко выбить в
  альфу; прозрачный PNG Gemini отдаёт ненадёжно.
- Финальные лого/иконки **векторизуй** (Illustrator Image Trace или vectorizer.ai)
  — монолиния трассируется чисто, получишь настоящий SVG.
- Формат: `1:1` для знака/иконок/app icon/favicon, `16:9` для баннеров/спек-листа.
- Промты — на английском; вставляй BRAND DNA целиком каждый раз, модель забывает
  контекст между генерациями.

## Если захочешь свернуть в другую сторону

Альтернативный центральный образ — **прецизионная диафрагма/затвор, который точно
закрывается** (а не ящик). Он лучше ложится на тезис манифеста «privacy, not
anonymity»: тебя видно, но створка заперта. Замени в разделе 1 фигуру на
*"a precise mechanical aperture/shutter caught mid-close, a small dot at its
center"* — остальная система (палитра, линия, иконки) переносится без изменений.
