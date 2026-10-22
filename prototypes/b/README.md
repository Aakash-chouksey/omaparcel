# Direction B — Courier console

A machine that moves parcels. The friend page reads like a dispatch console,
not a download page: code down the spine, expiry on a 1px timeline, manifest on
a hairline grid. Dark, warm, flat. No glow.

## Tokens

| token | value | use |
|---|---|---|
| `--ink` | `#0e1113` | page |
| `--panel` | `#15191c` | row hover, copy button hover, devbar |
| `--panel-2` | `#1b2126` | press states |
| `--text` | `#e9e5dc` | names, values, primary button |
| `--muted` | `#9199a0` | labels, sizes, footer (6.2:1 on panel) |
| `--hairline` | `#262c31` | every rule, 1px, no radii above 2px |
| `--signal` | `#e8a33d` | tick, Download text, urgent expiry, focus ring |
| `--danger` | `#d4634a` | expired timeline, PIN error |

Signal is a state colour: hover affordance, urgent countdown, current devbar
item, focus ring. Never decoration.

## Type

- **Bricolage Grotesque** 600 — `h1` (30px at 390, 40px at 900+), count numeral
  (56px rail / 26px strip), Unlock label. 400 — file names 15px, footer and
  helper 13px.
- **JetBrains Mono** 500 — labels 10px caps, tracking .14–.16em, spine 11px
  tracking .2em, copy button. 400 — index, type, size, sub line 12px,
  timeline value 12px. All numerals `tabular-nums`.

Fonts come from one Google Fonts `<link>` with real fallbacks
(`ui-sans-serif, system-ui` / `ui-monospace, Menlo, Consolas`). Drop the link
and the layout holds.

## Layout

- 1120px page, `200px | 1fr`, 48px gutter, 40px page padding, 48px top.
- Rail: `TUNNELSHARE` and the share code as two vertical columns
  (`writing-mode: vertical-rl`), gauge and count pinned to the bottom. One
  hairline on the rail's right edge is the only vertical rule.
- Manifest: `No. / Item / Type / Size` header, 52px rows, hairlines only, no
  card. Whole row is the anchor.
- Under 900px the rail folds to a two line strip: code and count on line one,
  `EXPIRY —— tick —— value` on line two. Rows stay one line; the name column
  ellipsises.

## Motion

| what | timing |
|---|---|
| row entrance | 40ms stagger, 6px rise, 240ms ease-out, `both` |
| row hover / press | 120ms background, size ↔ `Download →` crossfade |
| chevron hover | 120ms, 1px nudge |
| copy label | flips to `Copied` for 1600ms, then back |
| timeline tick | 60s tick, 600ms linear slide, width 120ms when urgent |

One entrance, one hover, one press. `prefers-reduced-motion: reduce` kills the
stagger and every transition; states still change.

## What the porter must preserve

1. The vertical spine, the 1px expiry timeline with its tick, and the big
   count numeral. That trio is the direction. Everything else is a strict grid.
2. Hairlines, not cards. Square-ish 2px radius maximum, no shadow, no glow, no
   gradient anywhere.
3. Mono for every number, label, and code; Bricolage for names and prose.
4. Row hover replaces the size with `Download →` in a reserved 100px cell
   (88px under 900px). No layout shift on hover, focus, or copy.
5. All facts and downloads in plain HTML: the manifest, sizes, the absolute
   expiry (`<time datetime>`) and every `href` work with JS off. JS only
   upgrades the expiry to a relative tick, the copy button, and the inline PIN
   error. `document.querySelector("[data-expiry]")` is the no-JS fallback text.
6. The rail folds at 900px, not by fluid type.

## Prototype notes

- Expiry is pinned to `2026-10-23T11:35` with a 48h window from
  `2026-10-21T11:35`; JS derives `in 23 hours` / `in 42 min` from the clock and
  moves `--t` from the static 52%. Absolute date shows without JS.
- PIN tries are client-side only (3, 2, 1, then locked) for the demo. The real
  form posts normally.
- `.devbar` is `data-dev`; delete it and the pages are still complete.
- Missing-link state is not built; the brief marks it optional.
