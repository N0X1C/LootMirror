# LootMirror — Dev Notes / Progress Log

Read this before making further changes. It captures *why* things are built the way they are, not just *what* — several design decisions here were forced by real bugs found through trial and error in-game (I — Claude — cannot run WoW myself; everything was verified via the user's screenshots and reports).

Current version: **2.0** (see `LootMirror.toc`). Interface: 120100 (WoW 12.1, Midnight).

---

## Status

Addon is feature-complete for its current scope and was just put through a full review/cleanup pass (see "Session 2" below). Options window is a fully custom dark/flat-themed UI (no Blizzard XML templates), scrollable, resizable, with a custom color picker and its own Game Menu → Options → AddOns entry. Loot filtering is deliberately narrow: **equipment only**, Poor quality always hidden, no per-item-type toggle — see "Scope decision" below, don't re-add a general item-type filter without re-reading that.

---

## Scope decision — read this before adding filters

LootMirror is **not** a general loot log. It exists specifically to catch group loot in dungeons/raids and, above all, the loot burst at the end of a Mythic+ run, where Blizzard's own loot display is easy to miss. Two things follow from that, both hardcoded in `ShouldFilterLoot` (Core.lua), not exposed as options:

1. **Equipment only.** Only `Enum.ItemClass` Weapon(2)/Armor(4)/Profession equipment(19) ever show up. Consumables, trade goods, quest items, reagents, etc. are always filtered, unconditionally.
2. **Poor quality is always hidden.** It's never worth flagging and equipment is essentially never Poor quality anyway.

An earlier version of this session added a full "Item Type" filter section (Equipment/Consumable/Trade Goods/Quest/Other checkboxes, mirroring the Quality filter). The user explicitly said this was too much (`"Ich glaube das ist zu viel... Ich brauche keine Filter für die items. Auch das poor kann weg."`) and asked for the simpler hardcoded behavior instead. That section was fully removed again. **Don't re-add a togglable item-type filter unless the user asks for it again** — the hardcoded equipment-only behavior is the intended design, not a placeholder.

---

## Hard-won architecture rules — don't undo these without a reason

1. **No legacy Blizzard XML templates in Options.lua.**
   `UIDropDownMenuTemplate`, `OptionsSliderTemplate`, `UIRadioButtonTemplate`, `GameMenuButtonTemplate` are NOT used. The original Options.lua used them and the window silently did nothing (`/lm` toggled nothing) — most likely because on this client one of these templates errors out during creation, which aborts the rest of the Lua file, so `LootMirror.Options.Toggle` and the slash-command handler never got defined. Everything is built from native widget types (`Frame`, `Slider`, `Button`, `EditBox`, `ScrollFrame`) + `BackdropTemplate` (which *is* safe — extremely widely used, not deprecated). The one exception is `UIPanelButtonTemplate`, used only for the "Open Options" button on the Game Menu → AddOns category page (Blizzard's own canvas page, a different context — that template is standard there).

2. **No `Texture:SetGradient`.**
   Confirmed broken on this client: the call doesn't error, but the texture never gets colored. Broke the color picker's SV square/hue bar and the header accent lines. Fixed everywhere by using `SetColorTexture` on many small solid-colored regions instead. Don't use `SetGradient` for anything new.

3. **No Blizzard `ColorPickerFrame` reuse.** Built a fully custom picker instead (SV square + hue bar + New/Prev + Hex) — it's a shared global frame, reskinning it would affect every addon, and its internal structure isn't stable across expansions.

4. **Dropdown menus and the color picker popup are parented to `optFrame`, not `content`.** `content` is the scrollable area's scroll-child; anything popped up from inside it must NOT be a descendant of the ScrollFrame or it gets clipped past the visible viewport. Parented to `optFrame` directly, positioned via `SetPoint` against the triggering widget, with `SetFrameLevel(optFrame:GetFrameLevel() + 50)`.

5. **ScrollFrame's scroll-child needs exactly one anchor + explicit `SetSize`.** Anchoring both TOPLEFT and TOPRIGHT to auto-match width breaks it — the ScrollFrame manages the child's position internally and a second competing anchor fights that.

6. **`row:SetPoint()` offsets already get multiplied by the row's own `SetScale()`.** Don't pre-multiply spacing by `scale` in `UpdateRowPositions` — that double-applies it.

7. **Loot bars and the anchor render at `"FULLSCREEN"` strata**, one tier above the Options window's `"DIALOG"` strata (but below `"TOOLTIP"`, so item-compare tooltips stay on top).

8. **`DisplayLoot` in Core.lua is `pcall`-wrapped** (`DisplayLootImpl` is the real body). WoW doesn't print Lua errors to chat unless "Show Lua Errors" is enabled, so an unguarded error here fails completely silently. Keep this wrapper on any future changes to that function.

9. **Filtering state (quality + item-class) has to be threaded through both the sync AND async paths.** `ShouldFilterLoot(quality, itemClassID)` is called both in `DisplayLootImpl` (item already in client cache) and in the `GET_ITEM_INFO_RECEIVED` handler (item wasn't cached yet at loot time, resolved later). If you add a new filter dimension, make sure it's checked in *both* places — the same applies to `bypassFilter` (see rule 10).

10. **`bypassFilter` (used by `/lm test`) must be threaded through the pending-item queue too, not just the initial synchronous check.** `RunLootTest` calls `DisplayLoot(..., true)` so Test always fills `Max Loot Bars` regardless of the user's quality filter. If the test item isn't cached yet, it goes through `pendingItems` and gets re-checked in `GET_ITEM_INFO_RECEIVED` — that path used to re-apply the normal filter and silently drop the bypass. Fixed by storing `bypassFilter` on the pending entry itself and checking `entry.bypassFilter` there too. If you add other one-off entry points that need to skip filtering, follow the same pattern.

11. **Don't add a wrapper function that just calls another function with no added behavior.** `RefreshBarScale` used to duplicate `UpdateRowPositions`'s per-row `SetScale` call, then also call `RefreshLayout` (which does the exact same `SetScale` again). Removed entirely — callers now call `LootMirror.RefreshLayout()` directly, which already re-applies scale *and* spacing *and* position in one pass over `activeRows`.

---

## Session 2 (v1.3 → v2.0) summary

Picked up after the Options window rebuild (Session 1, see git history / old bug table below). Work this session, roughly in order:

1. **Game Menu integration** — added a minimal canvas page under Game Menu → Options → AddOns (`Settings.RegisterCanvasLayoutCategory`), showing name/version/slash-commands + an "Open Options" button. Deliberately a separate small canvas, not `optFrame` itself — `optFrame` is a free-floating draggable window sized to its own content, and the Blizzard settings canvas controls its own size/scroll, so embedding it directly would fight on both.
2. **Visual redesign** — replaced the purple/cyan palette with blue+green pulled from the user's "NOXIC" logo (`C.accent` / `C.header` in Options.lua, `ANCHOR_*` in LootFrame.lua — kept in sync manually, no shared palette module). Iteratively made borders/scrollbar/sliders thinner and flatter (borderless cards/buttons/track, round pill slider thumb via `Interface\Masks\CircleMaskScalable`, hover feedback via color-mixing instead of border swaps — see `MixColor` in Options.lua), taller window (600px → 720px).
3. **Panel Opacity slider** — added next to Panel Scale in the fixed header (`BuildSliderRow` gained optional `leftX`/`rightX` params so two sliders fit side by side). Applies live on every drag tick (unlike Scale, which only applies on mouse-up to avoid a resize flicker).
4. **Move Anchor / Test button styling** — iterated a few times per user feedback: tried accent-tinted, user said not accent-colored; tried plain gray, user said not gray, should match the rest of the panel. Landed on `MixColor(C.control, C.border, 0.5)` — brightened toward the same muted blue-green hairline color used for card borders elsewhere, not toward white/gray or the loud accent color.
5. **Tooltip behavior** — anchored to cursor (`ANCHOR_CURSOR`) instead of a fixed screen-corner anchor. Item comparison now requires holding **Shift**, checked explicitly via `IsShiftKeyDown()` rather than relying on `GameTooltip_ShowCompareItem`'s internal `alwaysCompareItems` CVar check (which is why it was comparing immediately before, regardless of Shift). While a row is hovered, an `OnUpdate` poll toggles the compare panels live as Shift is pressed/released, without needing to re-hover.
6. **Item filtering redesign** — first added a full "Item Type" filter (Equipment/Consumable/Trade Goods/Quest/Other), then reverted it per user feedback in favor of a hardcoded equipment-only scope. See "Scope decision" above — don't redo this without re-reading that section. Also removed "Poor" from the Quality filter entirely (always hidden now, not a togglable option).
7. **Test button now bypasses filters** — `/lm test` used to run real loot items through the real filter pipeline, so with a narrow quality filter (e.g. only Epic checked) most of the hardcoded classic-legendary test pool (Ashbringer, Sulfuras, Atiesh, Benediction, Warglaive — all actually Legendary quality in the item DB, regardless of the color codes hardcoded in the test strings) got filtered out, and the user saw far fewer test bars than `Max Loot Bars`. Test is meant to preview layout, not exercise filter settings, so `DisplayLoot`/`DisplayLootImpl` gained a `bypassFilter` param (see rule 10 above for the async-path gotcha that was found and fixed).
8. **Full review/cleanup pass** (this was requested explicitly: *"schau dass nichts unnötig ist, nichts doppelt, alles gut funktioniert, das Addon lightweight ist"*) — found and fixed the `RefreshBarScale` double-scale-application bug (rule 11) and the `bypassFilter` async-path gap (rule 10). Everything else checked out: no dead code, no duplicate event registrations, OnUpdate handlers all properly scoped to only run while actually needed (drag/hover), frame pooling intact.
9. **README rewritten** to match all of the above — equipment-only scope, Panel Opacity, cursor tooltip + Shift-compare, Game Menu entry, updated Quality list (no Poor).
10. **Version bump** — `LootMirror.toc`: 1.3 → 2.0, Interface 120001 → 120100 (WoW 12.1).

## Bugs found earlier (Session 1, root cause → fix) — still useful if similar symptoms reappear

| Symptom | Root cause | Fix |
|---|---|---|
| Options window did nothing (`/lm` no-op) | Legacy XML templates errored during creation, aborting the rest of Options.lua | Rebuilt with native widgets only (see rule 1) |
| Test bars invisible even though logic ran | Options window (`DIALOG` strata) painted over loot bars at default overlapping screen positions | Bars/anchor bumped to `FULLSCREEN` strata |
| Test never displayed anything, no error | `LOOT_ITEM_PATTERN` built unguarded from a GlobalString; if missing, aborted the whole file before `LootMirror.RunTest` got defined | `MakePattern` now returns `nil` safely for non-string input |
| Test ran fully but zero bars appeared | `LootMirrorDB.filterQuality` had all qualities disabled — leftover state from a prior version | Added the Quality checkbox UI + a login warning if all qualities end up disabled |
| Color picker: hue bar white, SV square flat | `Texture:SetGradient` silently does nothing on this client | Rewrote as grids/strips of solid `SetColorTexture` regions |
| Bar Spacing had no consistent effect across Bar Scale | Double-scaling bug in `UpdateRowPositions` | Removed the redundant `* scale` (see rule 6) |
| Options content area completely empty after adding scrolling | Scroll-child had two competing anchors instead of one + explicit size | Single TOPLEFT anchor + `SetSize` (see rule 5) |
| Whole window flickered while dragging Panel Scale | `optFrame:SetScale()` fired on every `OnValueChanged` tick during drag | Scale now applies once on `OnMouseUp` |

---

## Current file map

- **`LootFrame.lua`** — anchor bar (draggable, dark-themed, blue/green accent split to match Options.lua), frame pool (`AcquireRow`/`ReleaseRow`), `CreateLootRow` (includes cursor-anchored tooltip + Shift-gated comparison), row-content helpers (`SetRowLoading`/`SetRowPlayer`/`SetRowItem`), `ApplyTextureToRow`/`ApplyColorsToRow`.
- **`Core.lua`** — `CHAT_MSG_LOOT` parsing (locale-independent via GlobalStrings), `ShouldFilterLoot` (hardcoded equipment-only + Poor-hidden, plus the user's Quality toggle), `DisplayLoot`/`DisplayLootImpl` (with `bypassFilter`), `UpdateRowPositions`/`RefreshLayout`, `Refresh*` functions called by Options.lua after Save, `RunTest`, ADDON_LOADED defaults for `LootMirrorDB`.
- **`Options.lua`** — everything UI: fixed header (title/subtitle/Panel Scale+Opacity), scrollable `content` area (shared `currentY` cursor), fixed footer (Move Anchor/Test/Save). Reusable builders: `BuildSliderRow`/`CreateModernSlider` (side-by-side capable via `leftX`/`rightX`), `CreateModernDropdown`, `CreateQualityCheckbox`, `CreateColorSwatchRow` + the color popup (`OpenColorPopup`), `CreateModernButton`/`MixColor` for the flat borderless buttons. Also owns the Game Menu → Options → AddOns category page at the bottom of the file.

## Not done / explicitly skipped

- Color picker has no **Favorites**/**Recent Colors** row. Not requested beyond the original reference image; would need a small persisted list in `LootMirrorDB` if wanted later.
- Border Width slider only visibly affects the **Flat** texture (documented in README) — the Blizzard-skin border is a fixed-proportion art asset.
- No togglable item-type filter (see "Scope decision" above — this is intentional, not missing).
- No sound alerts, session loot history/log, money/currency display, minimum-ilvl filter, or minimap/LDB icon — all were suggested to the user as possible next features but none picked yet.

## For the next session

- No automated tests exist (can't run the WoW client in this environment) — all verification is manual, via the user's screenshots/reports. When changing rendering/interaction code, ask the user to `/reload` and report back rather than assuming it works.
- If the user picks one of the previously-suggested features (sound alerts, loot history, currency/money display, min-ilvl filter, minimap icon, profiles, combat-hide), start there. Otherwise ask what's next — no open TODOs beyond that right now.
