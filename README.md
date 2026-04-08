# LootMirror

A lightweight loot feed for World of Warcraft, styled to match the native Blizzard UI.

LootMirror shows what you and your group members loot in a clean, unobtrusive feed — no bloat, no interruptions.

---

## Features

- **Full Loot Feed** — displays your own loot as well as loot received by party and raid members
- **Blizzard-style visuals** — tooltip-styled rows with quality-colored icon borders matching WoW's native look
- **Class colors** — player names are displayed in their class color, resolved live from the group roster
- **Item tooltips** — hover a row to see the full item tooltip with equipped item comparison
- **Item quality filter** — show or hide loot by quality (Poor through Legendary)
- **Configurable row count** — 1 to 10 bars visible at once
- **Configurable duration** — bars stay visible for 5 to 60 seconds
- **Configurable font size** — adjust the text size of loot bars (8–18)
- **Grow direction** — feed can expand downward or upward from the anchor
- **Frame pool** — rows are reused instead of recreated, keeping memory overhead minimal
- **Locale independent** — loot message patterns are built from WoW's own GlobalStrings at runtime

---

## Slash Commands

| Command | Description |
|---|---|
| `/lm` | Open or close the Options window |
| `/lm move` | Show or hide the draggable anchor bar |
| `/lm test` | Spawn test bars (count matches your max bars setting) |

---

## Options

Open with `/lm`.

| Option | Description |
|---|---|
| **Maximum Loot Bars** | How many bars are shown at once (1–10) |
| **Display Duration** | How long each bar stays visible (5–60 seconds, in 5s steps) |
| **Font Size** | Text size of player and item name in each bar (8–18) |
| **Grow Direction** | Whether the feed expands downward or upward from the anchor |
| **Displayed Qualities** | Toggle Poor, Common, Uncommon, Rare, Epic, and Legendary loot on or off |

Settings are saved per account in `LootMirrorDB`.

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
| `LootFrame.lua` | Frame creation, frame pool, visual layout |
| `Options.lua` | Options window UI |
| `Core.lua` | Event handling, loot detection, filtering, slash commands |
| `LootMirror.toc` | Addon metadata |

---

## Compatibility

- **Interface:** 12.0.1 (Midnight)
- **Dependencies:** none
- **Optional:** none
