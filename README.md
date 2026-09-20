# LootMirror

A lightweight loot feed for World of Warcraft, styled to match the native Blizzard UI.

LootMirror shows what you and your group members loot in a clean, unobtrusive feed — no bloat, no interruptions.

---

## Features

- **Equipment-only loot feed** — built specifically for group loot in dungeons/raids and, especially, the loot burst at the end of a Mythic+ run (where Blizzard's own display is easy to miss). Only weapons/armor/profession gear ever show up; consumables, trade goods, quest items and Poor-quality junk are always filtered out, no toggle needed
- **Full Loot Feed** — displays your own loot as well as loot received by party and raid members
- **Blizzard-style visuals** — tooltip-styled rows with quality-colored icon borders matching WoW's native look; alternatively a fully customizable flat style (border width/color, background color/opacity)
- **Class colors** — player names are displayed in their class color, resolved live from the group roster
- **Item tooltips at the cursor** — hover a row for the full item tooltip; hold **Shift** to also show the equipped-item comparison (independent of the client's "always compare items" setting)
- **Item quality filter** — show or hide loot by quality (Common through Legendary), with an in-game toggle for each
- **Configurable row count** — 1 to 10 bars visible at once
- **Configurable duration** — bars stay visible for 5 to 60 seconds
- **Configurable font size** — adjust the text size of loot bars (8–18)
- **Configurable bar scale & spacing** — scale bars 0.8x–1.6x; spacing between bars scales proportionally
- **Grow direction** — feed can expand downward or upward from the anchor
- **Modern dark Options window** — scrollable, resizable and adjustable opacity (Panel Scale / Panel Opacity sliders), with a fully custom color picker (no dependency on Blizzard's shared color picker)
- **Game Menu integration** — shows up under Game Menu → Options → AddOns with a quick-access button to the options window
- **Frame pool** — rows are reused instead of recreated, keeping memory overhead minimal
- **Locale independent** — loot message patterns are built from WoW's own GlobalStrings at runtime, with a safe fallback if a GlobalString is ever missing/renamed

---

## Slash Commands

| Command | Description |
|---|---|
| `/lm` | Open the Options panel (Game Menu → Options → Addons → LootMirror) |
| `/lm move` | Show or hide the draggable anchor bar |
| `/lm test` | Spawn test bars (count matches your max bars setting) |

---

## Options

Open via **Game Menu → Options → Addons → LootMirror** or with `/lm`. The window is scrollable (mouse wheel or the scrollbar on the right); the **Panel Scale** and **Panel Opacity** sliders at the top adjust the window itself (size and background transparency), separate from the loot bar styling below.

### Display
| Option | Description |
|---|---|
| **Max Loot Bars** | How many bars are shown at once (1–10) |
| **Display Duration** | How long each bar stays visible (5–60 seconds, in 5s steps) |
| **Font Size** | Text size of player and item name in each bar (8–18) |
| **Bar Scale** | Size of each bar (0.8x–1.6x) |
| **Bar Spacing** | Gap between bars (0–20px); scales proportionally with Bar Scale, so 0px always means bars touch exactly, at any scale |

### Appearance
| Option | Description |
|---|---|
| **Bar Texture** | **Blizzard** (native tooltip-style skin, fixed proportions) or **Flat** (solid color, fully customizable below) |
| **Grow Direction** | Whether the feed expands downward or upward from the anchor |

### Bar Style
| Option | Description |
|---|---|
| **Border Width** | 1–6px. Only visibly affects the **Flat** texture — the Blizzard skin is a fixed-proportion tooltip graphic |
| **Border Color** | Opens the built-in color picker |
| **Background Color** | Opens the built-in color picker |
| **Background Opacity** | 0–100% |

### Displayed Qualities
Toggle Common, Uncommon, Rare, Epic, and Legendary loot on or off individually. Poor-quality items are always hidden and non-equipment items (consumables, trade goods, quest items, etc.) are never shown — LootMirror is scoped to gear.

Settings are saved per account in `LootMirrorDB`.

---

## Color Picker

Border/Background colors open a self-contained picker (not Blizzard's shared `ColorPickerFrame`, which can't be restyled per-addon and whose internal layout has changed across expansions):

- Saturation/Value square (drag to pick) + vertical hue bar
- **New**/**Prev** swatches — click **Prev** to revert to the color you opened the picker with
- **Hex#** field — type a 6-digit hex code and press Enter
- **Cancel** discards changes, **OK** keeps them

---

## Positioning

1. Type `/lm move` to reveal the anchor bar
2. Drag it to the desired position
3. Type `/lm move` again to hide the anchor

The anchor position is saved and restored automatically across sessions.

---

## Files

| File | Purpose |
|---|---|
| `LootFrame.lua` | Frame creation, frame pool, visual layout, row content helpers |
| `Options.lua` | Options window UI (sliders, dropdowns, checkboxes, scrollable layout, custom color picker) |
| `Core.lua` | Event handling, loot detection, filtering, slash commands |
| `LootMirror.toc` | Addon metadata |
| `PROGRESS.md` | Session notes / dev log — read this before making further changes |

---

## Compatibility

- **Interface:** 12.1 (Midnight)
- **Dependencies:** none
- **Optional:** none
