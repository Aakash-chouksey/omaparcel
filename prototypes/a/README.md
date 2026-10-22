# Direction A — Consignment note

A printed docket for a parcel: warm paper, ink, one rubber-stamp accent. The
page is a delivery note for a share, not a web app. Product register, no
decoration beyond the docket.

Signature: the top rule that carries the eyebrow and the share code, plus the
rotated outline `EXPIRES` stamp on the total line. Nothing else is allowed to be
loud.

## Files

```
styles.css     all shared styles
folder.html    5 files, the main state
single.html    1 file
pin.html       code gate
expired.html   dead link
```

Each page carries its own small inline script (countdown + copy, or the PIN
form). No build step, no framework, no external asset besides Google Fonts.
Open any file directly with `file://`.

Every download is a plain `<a href="#">`. The list, sizes, expiry date, stamp
and copy button all render without JavaScript. The script only adds the live
countdown, the copy confirmation, and the inline PIN error.

## Tokens

| token | light | dark |
|---|---|---|
| `--paper` | `#f2eee6` | `#16130f` |
| `--card` | `#fbf9f4` | `#1e1a15` |
| `--ink` | `#191611` | `#f1ebdf` |
| `--muted` | `#6d6659` | `#a49a89` |
| `--rule` | `#d8d1c3` | `#332d25` |
| `--accent` | `#a83a22` | `#e0704f` |
| `--on-accent` | `#fbf9f4` | `#16130f` (added for the Unlock button) |

`prefers-color-scheme` switches the set. Accent is used only for ink-level
signals: the stamp, the `Download →` word, `soon` expiry, focus ring, error, and
the primary button. Text contrast is at least 4.5:1 on both papers.

## Type

- Instrument Serif 400 — the note (`h1`) and page headline only. 34px at 390,
  44px from 600px. Line height 1.06.
- Instrument Sans 400/500 — file names, helper and footer prose, buttons.
- IBM Plex Mono 400/500 — eyebrow, table header, type column, sizes, totals,
  expiry, stamp, devbar. Uppercase labels get 0.16–0.2em tracking.

Fallback stacks: serif → Georgia; sans → system-ui; mono → ui-monospace.

## Layout

One column, max 640px, top padding 32px at 390 and 56px from 600px. The manifest
is a real `<table>` with a hairline `<thead>`; rows are separated by hairlines
only, no card, no radius. A dashed rule separates the total. The stamp sits at
the right of the total, rotated −6°.

Under 560px the table stacks: name on line one, `TYPE / SIZE` in mono on line
two, stamp moves under the total at 0.94 scale.

## Motion

| what | spec |
|---|---|
| row entrance | 240ms `ease-out`, 6px rise, 40ms stagger, max 5 rows |
| hover / press / copy label | 140ms `ease-out` |
| copy label hold | 1600ms before it returns to `Copy link` |
| expiry tick | every 60s; under an hour the value turns accent + 500 weight |

All entrance motion sits inside `@media (prefers-reduced-motion: no-preference)`.
`reduce` also cuts transitions to 1ms. One entrance, one hover, one press — no
other motion.

## What the porter must preserve

1. The top rule composition: mono eyebrow with the share code in ink, copy
   button right, 1px rule under both.
2. Serif note as the single `h1`; every number, size, and expiry in mono.
3. Hairline table, no card, no radius. `item / type / size` column labels.
4. The dashed tear line, the total line, and the rotated double-rule stamp.
5. The size cell reserves width for `Download →` so hover never shifts layout.
6. Rows are 44px minimum tall. The name cell is the link and fills its column; the
   row-wide hover still drives the swap. Do not fake a full-row link with a
   positioned pseudo-element over table cells — Chromium will not hit-test it.
7. Stacked table under 560px, stamp below the total. The `Download →` swap is
   desktop only: there is no hover on touch, and `TYPE / SIZE` stays readable.
8. Devbar is prototype-only: delete everything marked `data-dev`.

## Prototype-only shortcuts

- The countdown anchors to page load (`now + 23h`), so the printed stamp date and
  the live relative time disagree. Real data comes from the share record.
- The PIN form always fails, then locks after 3 tries. With JS off it does a
  normal POST to `#`.
- Copy falls back to selecting the share code when the clipboard API is
  unavailable or does not settle within 1s (a permission prompt can hang), and
  the label reads `Copy failed` for 1.6s.
