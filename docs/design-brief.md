# Friend page design brief

Two candidate directions. Each prototype is a bakeoff artifact, not production
code. One wins, then gets ported into Flask templates.

Read `/home/codejack/.agents/skills-parked/misc/anti-ui-slop/SKILL.md` first.
Product UI register: the task is download one or more files. Familiar controls,
no decoration that does not serve the task. Spend the distinction in one place
per direction and keep the rest quiet.

## Shared rules

- No framework. Plain HTML and CSS. Small vanilla JS only for the countdown,
  copy, and inline PIN error.
- The page must work with JavaScript disabled. Every download is a plain link.
- No icon font, no emoji, no external images, no SVG illustrations. Type, rules,
  and space do the work.
- No purple or blue gradient, no glass blur, no glow, no 24px pill cards, no
  centered hero with a gradient headline, no stock "secure" copy.
- Motion: one entrance, one hover, one press. Respect
  `prefers-reduced-motion: reduce`.
- Accessible: 4.5:1 text contrast, visible `:focus-visible`, 44px touch targets,
  semantic landmarks, `lang`, `title`, one `h1`.
- Responsive: design at 390px first. Check 390, 768, 1280.
- CSS under 12KB. No layout shift. Fonts via `<link>` to Google Fonts for the
  prototype only, with a real fallback stack.
- Include a tiny fixed `.devbar` at the bottom left with links between states.
  Mark it `data-dev` so it is easy to delete.

## Content, use exactly

Folder share, the main state:

```
eyebrow:  TUNNELSHARE / 7KQ2M4
note:     Riverside, October
sub:      5 files / 486 MB / expires in 23 hours
files:
  drone-pass.mp4      MP4    412.6 MB
  IMG_2041.HEIC       HEIC    24.8 MB
  IMG_2042.HEIC       HEIC    25.1 MB
  locations.pdf       PDF      1.2 MB
  packing-list.md     MD          3 KB
footer:   Served from the sender's laptop. If the link stops working, ask for
          a new one.
```

Single file state:

```
eyebrow:  TUNNELSHARE / 3WQ9XP
note:     Contract, signed
sub:      1 file / 840 KB / expires in 23 hours
file:     contract-final.pdf    PDF    840 KB
```

PIN state:

```
eyebrow:  TUNNELSHARE / 7KQ2M4
h1:       This link needs a code
sub:      Riverside, October / 5 files / 486 MB
label:    6 digit code
button:   Unlock
helper:   Ask the sender for the code. It travels separately from the link.
error:    That code is not right. 3 tries left.
locked:   Too many tries. Ask the sender for a new link.
```

Expired state:

```
h1:    This link has expired
sub:   It worked until 23 Oct, 18:40. Ask the sender for a new one.
```

Missing state (optional, small):

```
h1:    This link does not exist
sub:   Check the address, or ask the sender for a new link.
```

## Interaction set, both directions

1. File rows enter with a 40ms stagger, 6px rise, 240ms ease-out. Off under
   reduced motion.
2. Row hover and focus: the row background lifts by one step and the size cell
   becomes `Download` with an arrow. No layout shift. Reserve the width.
3. Copy link button: text becomes `Copied` for 1.6 seconds. Fallback to select
   the text if the clipboard API fails.
4. Expiry ticks every 60 seconds. Under one hour it reads `in 42 min` and the
   accent gains weight. Without JS the absolute time is shown.
5. PIN submit: normal form post. With JS, submit without a reload and show the
   error inline. The button must not stay disabled.
6. Press states are real, not just hover.

## Direction A: Consignment note

A printed docket for a parcel. Warm paper, ink, one rubber-stamp accent.

- Palette light: paper `#f2eee6`, card `#fbf9f4`, ink `#191611`,
  muted `#6d6659`, rule `#d8d1c3`, accent `#a83a22`.
- Palette dark: paper `#16130f`, card `#1e1a15`, ink `#f1ebdf`,
  muted `#a49a89`, rule `#332d25`, accent `#e0704f`.
- Type: Instrument Serif for the note and headline. Instrument Sans for body.
  IBM Plex Mono for eyebrow, type column, sizes, expiry. Tight but generous.
- Layout: one column, max 640px, top aligned at 56px. A top rule carries the
  eyebrow and the share code. The note is the `h1` in serif, 34 to 44px.
  The manifest is a table with header `item / type / size` in mono caps, hairlines
  only, no card. A dashed tear line above the total. A rotated outline stamp
  reads `EXPIRES` and the date, sitting at the right of the total.
- Signature: the docket header plus the stamp. Everything else is quiet.
- Mobile: the table becomes stacked rows, name then `TYPE / SIZE`, the stamp
  moves under the total and stays small.

## Direction B: Courier console

A machine that moves parcels. Dark, precise, warm, no glow.

- Palette: ink `#0e1113`, panel `#15191c`, text `#e9e5dc`, muted `#9199a0`,
  hairline `#262c31`, signal `#e8a33d`, danger `#d4634a`.
- Type: Bricolage Grotesque 600 for headings, JetBrains Mono for all metadata
  and numerals. Body can use Bricolage 400 at 15px.
- Layout: a two column grid at 1280. Left rail 200px with the share code set
  vertically, the expiry as a 1px horizontal timeline with a moving tick, and
  the count as a large numeral. Right column is the manifest. At 390 the rail
  becomes a two line strip above the list.
- Rows: leading 2 digit index in mono, name, size right aligned, chevron. 1px
  hairlines only. The whole row is the link.
- Signature: the vertical rail and the expiry timeline. Everything else is a
  strict grid.
- Keep it warm and flat. No glowing borders, no rounded cards, no neon.

## Deliverables per direction

```
prototypes/<a|b>/
  README.md      direction name, tokens, font families and weights, motion
                 timings, what the porter must preserve
  styles.css
  folder.html
  single.html
  pin.html
  expired.html
```

Every page links the shared stylesheet and the devbar. Use real anchors with
`href="#"` for downloads in the prototype.

## Check before reporting

- Screenshot at 390x844 and 1280x900 with
  `chromium --headless --screenshot=/tmp/x.png --window-size=W,H file://...`
  and look at the PNG. Fix clipping, overflow, and weak hierarchy.
- Disable JS in the page source mentally: the list, sizes, expiry time, and
  every download link must still be there. The countdown may be static.
- Keyboard only: tab reaches every link and button, focus is visible.
- Nothing in the page would look the same in a different file sharing product.
  If it would, the direction failed. Say so in the report instead of hiding it.
