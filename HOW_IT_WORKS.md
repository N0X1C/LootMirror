# Wie LootMirror funktioniert

Diese Doku ist für dich als Autor des Addons, nicht für andere Nutzer (dafür gibt es die `README.md`). Ziel: Du sollst jede Datei aufmachen können und verstehen, *was* dort passiert und *warum* es so und nicht anders gebaut ist — auch ohne Lua-Vorkenntnisse.

Sie ist in fünf Teile gegliedert:

0. Die absoluten Grundlagen (WoW-Addons & Lua in Kurzform)
1. Die große Übersicht: welche Datei macht was
2. Der Lebensweg eines Loot-Events — Schritt für Schritt durchs ganze System
3. Jede Datei im Detail
4. Wie Einstellungen gespeichert werden
5. Mini-Glossar zum Nachschlagen

Wenn du nur *eine* Sache aus dieser Doku mitnimmst: **Kapitel 2** (der Lebensweg eines Loot-Events) ist das Herzstück. Alles andere sind Bausteine, die dort zusammenlaufen.

---

## Kapitel 0: Die absoluten Grundlagen

### Was ist ein WoW-Addon technisch gesehen?

Ein Ordner mit einer `.toc`-Datei (Table of Contents) und ein paar `.lua`-Dateien. Wenn du WoW startest, liest der Client die `.toc`, lädt darin aufgelisteten `.lua`-Dateien **in genau der angegebenen Reihenfolge** und führt sie einmal komplett von oben nach unten aus — wie ein Skript. Es gibt keinen "Einstiegspunkt" wie `main()` in anderen Sprachen; der gesamte oberste Code in jeder Datei läuft einfach los, sobald die Datei an der Reihe ist.

Unsere `LootMirror.toc`:

```
## Interface: 120100
## Title: LootMirror
## Notes: Lightweight party/raid loot feed styled to match the native WoW UI.
## Author: N0X1C
## Version: 2.0
## SavedVariables: LootMirrorDB
## SavedVariablesPerCharacter: LootMirrorCharDB

LootFrame.lua
Wishlist.lua
Options.lua
Core.lua
```

- Die `##`-Zeilen sind Metadaten (Name, Version, welche Spielversion, und — wichtig — welche globalen Variablen zwischen Logins gespeichert werden sollen, dazu mehr in Kapitel 4).
- Die vier Dateizeilen am Ende sind die Ladereihenfolge. **Das ist kein Zufall**: `Wishlist.lua` lädt vor `Options.lua`, weil `Options.lua` beim eigenen Laden eine Funktion aus `Wishlist.lua` aufruft (`LootMirror.Wishlist.BuildUI(...)`) — die muss zu dem Zeitpunkt schon existieren.

### Lua in 10 Sätzen

- Kommentare beginnen mit `--` (einzeilig) oder `--[[ ... ]]` (mehrzeilig).
- Variablen sind entweder `local` (nur in der aktuellen Datei/Funktion sichtbar) oder global (überall sichtbar, auch aus anderen Dateien — **absichtlich sparsam genutzt**, siehe unten).
- `nil` ist Luas "nichts da" — vergleichbar mit `null`/`None` in anderen Sprachen. Eine nicht gesetzte Variable ist `nil`.
- Ein `table` ist Luas einziger zusammengesetzter Datentyp — je nachdem, wie man ihn befüllt, ist er mal eine Liste (`{1, 2, 3}`), mal ein Objekt mit benannten Feldern (`{ id = 5, name = "Foo" }`), oder beides gemischt. Du wirst beide Varianten ständig sehen.
- Funktionen sind Werte wie alles andere: `local function Foo() ... end` ist eigentlich nur Kurzschreibweise für `local Foo = function() ... end`. Das erklärt, warum man Funktionen als Parameter durchreichen kann (z. B. ein Klick-Handler).
- `and`/`or` werden oft als Kurzform für "wenn/sonst" benutzt: `x and a or b` heißt sinngemäß "wenn `x` wahr ist, nimm `a`, sonst `b`". Extrem häufig im Code, z. B. `LootMirrorDB.maxRows or 5` heißt "benutze den gespeicherten Wert, oder falls der nicht existiert (`nil`), nimm 5 als Standard".
- `self` ist in Methodenaufrufen wie `frame:SetPoint(...)` implizit das Objekt vor dem Doppelpunkt (`frame`). `frame:Foo(x)` ist gleichbedeutend mit `frame.Foo(frame, x)`.
- Es gibt kein eingebautes Klassensystem — "Objekte" sind einfach Tables, an die man Funktionen und Felder dranhängt.
- Tabellenindizes fangen bei **1** an, nicht bei 0 (anders als in den meisten anderen Sprachen).

### WoW-spezifische Konzepte, die überall vorkommen

- **Frame**: Jedes sichtbare UI-Element (Fenster, Button, Textfeld, Icon, …) ist ein `Frame`-Objekt, erzeugt mit `CreateFrame("Frame", ...)` bzw. `CreateFrame("Button", ...)` usw. Frames können ineinander verschachtelt werden (Eltern/Kind-Beziehung über `parent`), das steuert u. a. Sichtbarkeit und Position.
- **Event**: Das Spiel selbst "ruft" dein Addon bei bestimmten Ereignissen auf — z. B. `CHAT_MSG_LOOT` (jemand hat etwas gelootet), `ADDON_LOADED` (dein Addon ist fertig geladen), `GROUP_ROSTER_UPDATE` (die Gruppe hat sich geändert). Ein Frame meldet sich für Events an (`frame:RegisterEvent("XYZ")`) und bekommt sie über einen `OnEvent`-Handler zugestellt.
- **Script/Handler**: Ein Frame kann auf UI-Interaktionen reagieren — `OnClick`, `OnEnter`/`OnLeave` (Maus drüber/weg), `OnShow`/`OnHide`, `OnValueChanged` (Regler bewegt), `OnUpdate` (läuft **jeden einzelnen Frame** — also sehr sparsam einsetzen). Gesetzt über `frame:SetScript("OnClick", function(self) ... end)`.
- **SavedVariables**: Normale Lua-Variablen verschwinden, sobald du WoW schließt. Variablen, die in der `.toc` unter `## SavedVariables` gelistet sind, schreibt der Client beim Logout/Reload automatisch in eine Datei auf der Festplatte und lädt sie beim nächsten Login wieder rein — das ist die einzige Art, wie ein Addon sich "merkt", was du eingestellt hast.

### Der `LootMirror`-Namensraum

Ganz oben in `LootFrame.lua` steht:

```lua
LootMirror = {}
```

Das ist eine **globale** Tabelle — absichtlich die einzige globale Variable, die dieses Addon anlegt. Jede Funktion, die eine andere Datei aufrufen können soll, hängt daran: `LootMirror.RefreshLayout`, `LootMirror.Wishlist.Add`, `LootMirror.Options.Toggle`, usw. Alles andere (die meisten Funktionen) ist `local` und nur innerhalb der eigenen Datei sichtbar. Das ist der übliche Lua-Addon-Stil: ein einziger globaler "Namensraum", darunter so viel `local` wie möglich, damit man nicht aus Versehen mit einem anderen Addon kollidiert (zwei Addons, die beide eine globale Funktion `Foo()` definieren, würden sich gegenseitig überschreiben).

---

## Kapitel 1: Die große Übersicht

| Datei | Rolle | Lädt... |
|---|---|---|
| `LootFrame.lua` | Fundament: Anker-Leiste, Frame-Pool für Loot-Zeilen, geteilte Scroll-Liste | zuerst |
| `Wishlist.lua` | Merkliste: Datenhaltung + eigener Tab im Options-Fenster + Adventure-Guide-Integration | zweitens |
| `Options.lua` | Das komplette Optionsfenster (UI) | drittens |
| `Core.lua` | Das "Gehirn": Loot-Events abfangen, filtern, Zeilen anzeigen | zuletzt |

Warum `Core.lua` als **letztes** lädt, obwohl es das Herzstück ist: Es ruft an mehreren Stellen Funktionen aus den anderen drei Dateien auf (`LootMirror.AcquireRow`, `LootMirror.Wishlist.IsWishlisted`, …) — die müssen also vorher schon existieren. `Core.lua` selbst wird von niemandem beim Laden aufgerufen, es registriert nur Events und wartet.

Grobes Bild, wer mit wem redet:

```
                 ┌───────────────┐
  WoW-Loot-Event │   Core.lua    │  liest Einstellungen aus LootMirrorDB
 ───────────────>│  (das Gehirn) │<──────────────────────────────┐
                 └───────┬───────┘                               │
                         │ ruft auf                               │
                         v                                        │
                 ┌───────────────┐        baut Zeilen aus         │
                 │ LootFrame.lua │<────────────────────────────── │
                 │ (Fundament)   │                                │
                 └───────────────┘                                │
                                                                   │
                 ┌───────────────┐   schreibt Einstellungen        │
                 │  Options.lua  │──────────────────────────────>─┘
                 │ (Bedienfeld)  │   ruft LootMirror.Refresh*() auf
                 └───────┬───────┘   (Core.lua), damit's sofort wirkt
                         │ baut UI innerhalb von
                         v
                 ┌───────────────┐
                 │ Wishlist.lua  │
                 │ (Merkliste)   │
                 └───────────────┘
```

---

## Kapitel 2: Der Lebensweg eines Loot-Events

Das ist der wichtigste Teil. Alles andere im Addon existiert, damit dieser eine Ablauf funktioniert. Nehmen wir an: Ein Gruppenmitglied namens "Anduin" lootet ein episches Schwert.

### Schritt 1 — WoW feuert ein Chat-Event

WoW schickt für jeden Loot-Vorgang eine (unsichtbare) Chat-Nachricht über das Event `CHAT_MSG_LOOT`. `Core.lua` hat sich dafür angemeldet:

```lua
core:RegisterEvent("CHAT_MSG_LOOT")
```

und bekommt den rohen Nachrichtentext geliefert, z. B. sinngemäß *"Anduin erhält Gegenstand: [Cord of the Earth]."* — aber eben in der Sprache des Clients.

### Schritt 2 — Die Nachricht wird sprachunabhängig zerlegt

WoW liefert für so ziemlich jede Systemnachricht eine sogenannte **GlobalString**-Vorlage mit — eine Art Textbaustein mit Platzhaltern, den Blizzard selbst benutzt, um die Nachricht in *deiner* Client-Sprache anzuzeigen (z. B. `LOOT_ITEM = "%s erhält Beute: %s."`). `MakePattern()` in `Core.lua` nimmt diese Vorlage und baut sich daraus automatisch ein Lua-Suchmuster mit Platzhaltern für "wer" und "was". **Dadurch ist die Erkennung komplett sprachunabhängig** — das Addon muss selbst nicht wissen, ob der Client auf Deutsch, Englisch oder sonst was läuft, es liest sich die Vorlage einfach vom Spiel selbst ab.

Ergebnis: aus der rohen Nachricht werden zwei Werte extrahiert — der Spielername (`"Anduin"`) und der Item-Link (ein spezieller, klickbarer Text-Code, der die Item-ID und alle Bonus-Infos enthält, z. B. `|cffa335ee|Hitem:9449::::::::70:::::|h[Cord of the Earth]|h|r`).

### Schritt 3 — `DisplayLoot` wird aufgerufen

```lua
DisplayLoot(p, link, tonumber(n))
```

`DisplayLoot` ist absichtlich nur eine dünne Hülle um die eigentliche Funktion `DisplayLootImpl` — sie ruft diese in einem `pcall` (**p**rotected **call**) auf. Das bedeutet: falls `DisplayLootImpl` irgendwo abstürzt (z. B. weil ein Item-Link kaputt ist), fängt `pcall` den Fehler ab, statt dass WoW ihn einfach verschluckt. WoW zeigt Lua-Fehler nämlich standardmäßig **gar nicht an** ("Show Lua Errors" ist per Default aus) — ohne diesen Wrapper würde ein Bug hier komplett lautlos das ganze Feature lahmlegen, ohne dass du je einen Hinweis bekommst. Deshalb gilt im ganzen Projekt: alles, was auf einem echten Loot-Event landet, läuft durch so einen Wrapper.

### Schritt 4 — Gefiltert wird schon *bevor* überhaupt eine Zeile entsteht

`DisplayLootImpl` liest zuerst die Item-ID aus dem Link heraus und prüft: *Steht dieses Item auf der Wishlist?* (`LootMirror.Wishlist.IsWishlisted(itemID)`). Das ist wichtig für das, was als Nächstes passiert:

```lua
if quality and not bypassFilter and not isRealWishlistMatch and ShouldFilterLoot(quality, itemClassID) then return end
```

`ShouldFilterLoot` (auch in `Core.lua`) ist die ganze Filterlogik des Addons, hartcodiert statt als Option — **absichtlich**, siehe `CLAUDE.md` ("Scope decision"): LootMirror zeigt grundsätzlich nur Ausrüstung (Waffen/Rüstung/Berufswerkzeug), niemals Verbrauchsgegenstände/Reagenzien/Questitems, und niemals Ramsch-Qualität ("Poor"). Zusätzlich kann der Nutzer im Options-Fenster einzelne Qualitätsstufen (Selten, Episch, …) ausblenden.

Ein wishlisted Item **umgeht diesen ganzen Filter** — genau deshalb wird die Wishlist-Prüfung zuerst gemacht: Wenn du explizit nach einem Item Ausschau hältst, soll es dir angezeigt werden, egal ob es eigentlich als "Ramsch" oder "falsche Kategorie" rausgefiltert würde (z. B. Mounts oder Transmog-Items, die keine "Ausrüstung" im engeren Sinne sind, aber trotzdem wishlist-fähig sein sollen).

### Schritt 5 — Eine Zeile wird "ausgeliehen", nicht neu gebaut

```lua
local row = LootMirror.AcquireRow()
```

Hier kommt ein zentrales Performance-Muster ins Spiel: der **Frame-Pool** (`LootFrame.lua`). Statt bei jedem Loot-Event ein brandneues UI-Element zu erzeugen (relativ teuer) und es Sekunden später wieder wegzuwerfen (Garbage Collection), hält das Addon eine kleine Sammlung bereits gebauter, aber gerade unsichtbarer Zeilen vor. `AcquireRow()` nimmt sich eine davon (oder baut eine neue, falls der Vorrat leer ist), `ReleaseRow()` gibt sie später zurück in den Vorrat statt sie zu zerstören. Das ist besonders wichtig, weil ein Mythic+-Loot-Burst am Ende eines Runs plötzlich 10+ Items auf einmal auswerfen kann — genau der Moment, in dem man *keine* teuren Frame-Neuerstellungen will.

### Schritt 6 — Die Zeile wird befüllt

Mehrere kleine Helferfunktionen aus `LootFrame.lua`, alle mit dem Muster `SetRowXyz(row, ...)`, schreiben Text/Farbe/Icon auf die Zeile:

- `SetRowWishlist(row, isWishlisted)` — goldener Rand + Stern-Icon, falls Wishlist-Treffer
- `SetRowPlayer(row, player, r, g, b)` — Spielername in seiner Klassenfarbe (siehe Kapitel 3, `classCache`)
- `SetRowLoading(row)` — Platzhalter ("Loading..."), falls die Item-Details noch nicht da sind (siehe nächster Schritt!)
- `SetRowItem(row, itemName, quality, itemTexture, count)` — Itemname in Qualitätsfarbe, Icon, Stapelanzahl

### Schritt 7 — Der Sonderfall: Item-Infos sind manchmal noch nicht da

Das ist die kniffligste Stelle im ganzen Addon. `C_Item.GetItemInfo(itemLink)` liefert Name/Qualität/Icon eines Items — **aber nur, wenn der Client die Daten schon vom Server hat**. Für ein Item, das gerade zum ersten Mal in dieser Session auftaucht, kann das fehlschlagen (die Funktion gibt dann `nil` zurück) — der Client muss die Info erst asynchron nachladen.

Deshalb:
1. Zeile bekommt sofort einen "Loading…"-Platzhalter (`SetRowLoading`), damit optisch sofort etwas passiert.
2. Falls `C_Item.GetItemInfo` gerade `nil` liefert, landet ein kleiner Eintrag `{row, count, itemLink, bypassFilter}` in einer Warteliste namens `pendingItems` (indiziert nach Item-ID).
3. Sobald der Client die Daten nachgeladen hat, feuert WoW von selbst das Event `GET_ITEM_INFO_RECEIVED`. Der `Core.lua`-Event-Handler schaut dann in `pendingItems` nach, ob für diese Item-ID noch offene Zeilen warten, füllt sie nachträglich mit den jetzt verfügbaren Daten — **und prüft an dieser Stelle den Filter noch einmal**, weil man beim ersten Mal (Schritt 4) die Qualität ja noch gar nicht kannte. Das ist der Grund, warum `bypassFilter`/die Wishlist-Prüfung an **zwei** Stellen im Code vorkommt: einmal für den "Daten sind schon da"-Fall, einmal für den "Daten kommen später nach"-Fall. Wenn du je einen neuen Filter oder eine neue Ausnahme einbaust: **beide Stellen anfassen**, sonst funktioniert sie nur zufällig, je nachdem ob der Client das Item schon kannte.

### Schritt 8 — Position berechnen, Zeile anzeigen

`UpdateRowPositions()` (`Core.lua`) ordnet alle aktuell sichtbaren Zeilen (`activeRows`, eine einfache Liste) unter- oder übereinander an, je nachdem ob "Grow Direction" auf Runter oder Hoch steht, mit dem eingestellten Abstand/Skalierung. Wird nach *jeder* Änderung an der Zeilenliste neu aufgerufen (neue Zeile rein, alte raus).

### Schritt 9 — Automatisches Verschwinden

```lua
C_Timer.After(LootMirrorDB.duration or 15, function()
    -- Zeile aus activeRows entfernen, ReleaseRow() (zurück in den Pool)
end)
```

Nach der eingestellten Anzeigedauer verschwindet die Zeile von selbst und wandert zurück in den Frame-Pool aus Schritt 5.

**Ausnahme:** Falls die Zeile Teil der Live-Vorschau ist (`noExpire`-Flag, siehe Kapitel 3 → Options.lua/Preview), wird dieser Timer komplett übersprungen — die Zeile bleibt stehen, bis der Preview-Toggle sie explizit wieder einsammelt (`StopPreview`).

Damit ist der komplette Kreislauf einmal durch: **Event rein → Text zerlegen → filtern → Zeile aus dem Pool holen → befüllen (ggf. verzögert) → positionieren → nach Ablauf zurück in den Pool.**

---

## Kapitel 3: Jede Datei im Detail

### `LootFrame.lua` — das Fundament

Enthält alles, was *aussieht*, aber nicht *entscheidet*. Kein Event-Handling, keine Filterlogik — nur "male mir ein UI-Element und gib mir Funktionen, um seinen Inhalt zu ändern".

- **Anker-Leiste** (`anchor`): ein verschiebbares kleines Fenster, das nur den Startpunkt markiert, an dem die Loot-Zeilen wachsen. Wird per `/lm move` ein-/ausgeblendet, per Maus verschoben, Position landet in `LootMirrorDB` (siehe Kapitel 4).
- **`LootMirror.CreateScrollList(parent, opts)`**: ein wiederverwendbarer Baustein für "scrollbarer Bereich + eigene dünne Scrollbar mit Maus-Rad- und Drag-Unterstützung". Sowohl das Options-Fenster als auch der Wishlist-Tab benutzen exakt diese eine Funktion, statt dass jede Datei ihre eigene Scroll-Logik nachbaut. Der Grund steht auch im Code: Genau das ist beim ersten Mal auseinandergedriftet (zwei leicht unterschiedliche Scroll-Geschwindigkeiten), deshalb wurde es hier zentralisiert.
- **`CreateLootRow()` + `AcquireRow`/`ReleaseRow`**: der Frame-Pool aus Kapitel 2, Schritt 5. Eine Zeile besteht aus mehreren Kind-Elementen (Icon, Rahmen um das Icon, Spielername-Text, Item-Text, Stapelzahl, Wishlist-Stern), alle als Felder direkt auf dem `row`-Frame-Objekt abgelegt (`row.Icon`, `row.PlayerText`, …) — das ist der übliche Weg in WoW-Addons, "Unterelemente" eines zusammengesetzten UI-Bausteins zu organisieren.
- **Tooltip beim Hovern**: `row:SetScript("OnEnter", ...)` zeigt den echten Item-Tooltip an der Maus. Hältst du zusätzlich Shift, wird der Ausrüstungsvergleich eingeblendet — bewusst an die Shift-Taste gekoppelt statt an die globale Client-Einstellung "Items immer vergleichen", damit sich das Verhalten unabhängig davon konsistent anfühlt.

### `Core.lua` — das Gehirn

Der komplette Kapitel-2-Ablauf lebt hier, plus:

- **`classCache`**: eine einfache Tabelle `Spielername -> Klassenfarbe`, damit nicht bei *jedem* Loot-Event neu durch die Gruppe iteriert werden muss, um herauszufinden, welche Klasse jemand spielt. Wird bei `GROUP_ROSTER_UPDATE` (Gruppe geändert) und beim Login neu aufgebaut. `/lm test` und der Preview-Toggle missbrauchen diese Cache kurzzeitig, um ihren erfundenen Test-Spielernamen (Thrall, Jaina, …) eine plausible Klassenfarbe zu geben — **mit expliziter Absicherung** (`SeedDemoClassCache`/`RestoreDemoClassCache`), damit das nicht dauerhaft die Farbe eines echten Gruppenmitglieds verfälscht, falls das zufällig genauso heißt. Das war tatsächlich ein Bug, der erst im Review vor dem CurseForge-Release gefunden wurde — ein gutes Beispiel dafür, wie leicht sich ein "nur für den Test gedachter" Seiteneffekt in echten Code einschleicht, wenn man ihn nicht explizit wieder rückgängig macht.
- **`ShouldFilterLoot`**: die hartcodierte Filterlogik aus Kapitel 2, Schritt 4.
- **`RunTest` / `StartPreview` / `StopPreview`**: drei verschiedene "Zeig mir Demo-Loot"-Funktionen, die sich einen gemeinsamen Item-Pool (`DEMO_POOL`) teilen, aber unterschiedlich lange leben:
  - `RunTest` (per `/lm test` oder war früher der "Test"-Button): zeigt die Zeilen zeitversetzt (alle 0,3s eine mehr) und lässt sie nach der normalen Anzeigedauer automatisch verschwinden — simuliert einen echten Loot-Burst.
  - `StartPreview`/`StopPreview`: das, was jetzt hinter dem **Preview**-Button im Options-Fenster steckt. Zeigt alle Demo-Zeilen sofort (kein Zeitversatz) und lässt sie **nicht** automatisch verschwinden (`noExpire`), solange die Vorschau aktiv ist — genau dafür gebaut, dass du in Ruhe an Reglern/Farben drehen kannst, ohne ständig neu auf einen Button klicken zu müssen.

### `Options.lua` — das Bedienfeld

Mit Abstand die größte Datei, weil das komplette Options-Fenster von Grund auf selbst gebaut ist — **bewusst ohne** die eingebauten Blizzard-UI-Vorlagen (`UIDropDownMenuTemplate` & Co.). Warum: Beim ursprünglichen Versuch mit diesen Vorlagen tat das Fenster einfach gar nichts, weil eine dieser Vorlagen auf diesem Client offenbar beim Erzeugen abstürzt — und weil in Lua ein Fehler mitten in einer Datei den kompletten Rest der Datei stoppt, wurden dadurch auch alle nachfolgenden Funktionen nie definiert. Seitdem: nur noch einfache, generische Bausteine (`Frame`, `Button`, `Slider`, `EditBox`) plus `BackdropTemplate` (für Hintergrund/Rahmen-Farben) — die sind seit Jahren stabil und werden von praktisch jedem Addon benutzt.

Grober Aufbau von oben nach unten im Fenster:

1. **Kopf** (fixiert, nicht Teil des Scroll-Bereichs): Titel, Panel-Scale-/Opacity-Regler.
2. **Tab-Leiste**: "Options" / "Wishlist" — schaltet nur um, *welcher* Inhaltsbereich sichtbar ist (`ShowTab`), beide existieren die ganze Zeit, nur einer ist jeweils per `:Show()`/`:Hide()` sichtbar.
3. **Scrollbarer Inhaltsbereich** (nur im Options-Tab): alle Regler/Dropdowns/Checkboxen/Farbfelder, gebaut über kleine wiederverwendbare Hilfsfunktionen (`CreateModernSlider`, `CreateModernDropdown`, `CreateQualityCheckbox`, `CreateColorSwatchRow`) — jede kümmert sich um Layout + Optik, damit der Rest des Codes nicht bei jedem einzelnen Regler das Gleiche neu hinschreiben muss.
4. **Fuß** (fixiert): Move Anchor / Preview / Save.

**Wie eine Änderung tatsächlich wirkt:** `ApplySettings()` ist die eine zentrale Funktion, die den aktuellen Stand *aller* Bedienelemente ausliest und in `LootMirrorDB` schreibt, dann `LootMirror.Refresh*()`-Funktionen aus `Core.lua` aufruft, damit bereits sichtbare Zeilen sich sofort optisch anpassen. Jeder Regler/jedes Dropdown/jede Checkbox/jedes Farbfeld ruft diese Funktion bei jeder Änderung live auf (`LiveApply()`) — das ist neueren Datums und der Grund, warum der Preview-Button überhaupt nützlich ist: du musst nicht erst "Save" drücken, um das Ergebnis zu sehen.

Das brachte allerdings einen echten Bug mit sich, den du selbst gemeldet hast: Beim Öffnen des Fensters werden alle Regler in einer Reihe nacheinander auf ihren gespeicherten Wert gesetzt (`OnShow`-Handler). Da `ApplySettings()` aber *immer alle* Regler gleichzeitig ausliest, hat jeder einzelne Wiederherstellungs-Schritt zwischendurch die noch nicht wiederhergestellten Regler mit ihren *alten* Werten zurück in die Datenbank geschrieben — die Einstellungen "resetteten" sich scheinbar bei jedem Öffnen nach einem `/reload`. Behoben mit einer simplen Sperre (`suppressLiveApply`): Während der Wiederherstellung ist Live-Apply kurz komplett deaktiviert. Gutes Beispiel dafür, dass "bei jeder Änderung sofort speichern" und "beim Öffnen die gespeicherten Werte wiederherstellen" sich gegenseitig in die Quere kommen können, wenn man nicht aufpasst.

**Der eigene Farbwähler**: Statt Blizzards eingebautes `ColorPickerFrame` wiederzuverwenden (das ist ein einziges globales Fenster, das sich *jedes* Addon teilt — würde man es umstylen, würde es überall anders aussehen), baut das Addon sein eigenes Sättigung/Helligkeit-Quadrat + Farbton-Balken komplett aus einzelnen einfarbigen Kacheln (`SetColorTexture`). Auch das hat einen konkreten Grund: `Texture:SetGradient` (der eigentlich naheliegende Weg für einen Farbverlauf) funktioniert auf diesem Client nachweislich nicht — der Aufruf wirft keinen Fehler, färbt aber auch einfach nichts ein. Deshalb wird im ganzen Addon überall dort, wo es aussieht wie ein Verlauf, tatsächlich ein Raster aus vielen kleinen einfarbigen Rechtecken gezeichnet.

### `Wishlist.lua` — die Merkliste

- **Datenmodell**: jeder Eintrag ist `{ id = ItemID, link = vollständiger Item-Link oder nil, source = Dungeon/Raid-Name oder nil }`. Der Abgleich beim Looten (`IsWishlisted`) prüft **nur** `id` — bewusst so, weil dasselbe Basis-Item in unterschiedlichen Qualitätsstufen droppen kann (Champion/Hero/Myth-Schmiedestufen) und "dieses Item, auf jeder Stufe" gemeint ist, nicht eine exakte Variante. `link`/`source` dienen nur dazu, den Eintrag in der Verwaltungsliste mit dem richtigen Icon/Namen/Dungeon anzuzeigen.
- **Hinzufügen** geht auf zwei Wegen: Link/ID manuell ins Textfeld im Wishlist-Tab einfügen, oder **Shift + Rechtsklick** auf ein Item im Adventure Guide.
- **Die Adventure-Guide-Integration ist der interessanteste Teil dieser Datei**, weil sie zeigt, wie man mit *fremder* UI (Blizzards eigenem Encounter-Journal-Fenster) umgeht, ohne sie kaputt zu machen. Drei Anläufe wurden gebraucht:
  1. Direkt die Klick-Funktion der Loot-Buttons im Journal "hooken" (`hooksecurefunc`) → hat auf diesem Client für die neuere Loot-Browser-Ansicht nie ausgelöst.
  2. Den Tooltip hooken (`GameTooltip:HookScript("OnTooltipSetItem", ...)`) und dynamisch einen Maus-Handler draufsetzen → hat einen echten Fehler beim `/reload` verursacht.
  3. **Was tatsächlich funktioniert**: gar nichts hooken. Stattdessen ein `OnUpdate` (läuft jeden Frame — **aber nur, solange das Adventure-Guide-Fenster überhaupt offen ist**, an- und abgeschaltet über dessen eigenes `OnShow`/`OnHide`), das schlicht abfragt "ist gerade die rechte Maustaste heruntergedrückt worden, ist Shift gehalten, und zeigt der Tooltip gerade ein Item?" — falls ja, wird genau dieses Item zur Wishlist hinzugefügt. Das liest nur Zustand ab, verändert nie etwas an Blizzards eigenen Elementen, kann also prinzipiell nichts kaputt machen, egal wie deren interner Aufbau sich in Zukunft ändert.
  
  Die Lehre daraus, falls du hier je wieder ansetzt: **Lieber Zustand abfragen (Polling) als fremde Funktionen/Scripts hooken**, wenn du dir bei deren interner Stabilität nicht sicher bist.
- **Dungeon-/Raid-Name auslesen**: Es gibt keine saubere API-Funktion dafür auf diesem Client (`EJ_GetCurrentInstance` existiert schlicht nicht mehr). Stattdessen wird der Name direkt aus einem bereits vorhandenen Textfeld in der Breadcrumb-Leiste des Adventure Guide gelesen (`EncounterJournalNavBarButton2Text:GetText()`) — auch das ist nur ein Lesezugriff, kein Hook.

---

## Kapitel 4: Wie Einstellungen gespeichert werden

Zwei separate gespeicherte Tabellen, in der `.toc` deklariert:

```
## SavedVariables: LootMirrorDB
## SavedVariablesPerCharacter: LootMirrorCharDB
```

- **`LootMirrorDB`** — pro **Account** (gilt für alle deine Charaktere gleich): alle sichtbaren Einstellungen aus dem Options-Fenster (Anzahl Balken, Dauer, Farben, Textur, Fensterposition, …).
- **`LootMirrorCharDB`** — pro **Charakter** (jeder Charakter hat seine eigene): aktuell nur die Wishlist, weil es Sinn ergibt, dass dein Magier und dein Krieger unterschiedliche Dinge suchen.

Beide sind zunächst ganz normale, leere Lua-Tabellen, bis der Client sie beim Login mit dem füllt, was beim letzten Logout/Reload gespeichert wurde (falls überhaupt schon etwas gespeichert war — beim allerersten Start sind sie leer/`nil`). Deshalb siehst du im gesamten Code dieses Muster ständig wieder:

```lua
LootMirrorDB.maxRows or 5
```

*"Nimm den gespeicherten Wert, falls vorhanden — sonst diesen Standardwert."* Das ist nötig, weil man nie sicher sein kann, dass ein bestimmtes Feld schon existiert (neuer Nutzer, neues Feld nach einem Update, …). Beim Laden des Addons (`ADDON_LOADED`-Event in `Core.lua`) werden zusätzlich einmalig alle fehlenden Felder mit sinnvollen Standardwerten aufgefüllt, damit man das `or Standardwert` nicht wirklich *überall* im Code wiederholen müsste — passiert an ein paar zentralen Stellen trotzdem noch als zusätzliche Absicherung.

**Geschrieben** wird in diese Tabellen ausschließlich aus `Options.lua` (`ApplySettings()`, live bei jeder Änderung — siehe Kapitel 3) bzw. aus `Wishlist.lua` (`Add`/`Remove`). **Gelesen** wird überall dort, wo eine Einstellung tatsächlich gebraucht wird — meistens in `Core.lua`, beim Anzeigen/Positionieren einer Zeile.

---

## Kapitel 5: Mini-Glossar

| Begriff | Bedeutung |
|---|---|
| **Frame** | Jedes UI-Element (Fenster, Button, Text, …); Grundbaustein der WoW-UI |
| **Event** | Ein Ereignis, das das Spiel selbst auslöst (Loot, Gruppenänderung, Addon geladen, …) |
| **Handler / Script** | Eine Funktion, die auf ein bestimmtes Ereignis oder eine Interaktion reagiert (`OnClick`, `OnEvent`, …) |
| **Table** | Luas einziger zusammengesetzter Datentyp — mal Liste, mal Objekt mit benannten Feldern |
| **`local`** | Eine Variable, die nur in der aktuellen Datei/Funktion existiert |
| **Global (z. B. `LootMirror`)** | Eine Variable, die überall im Spiel sichtbar ist — bewusst sparsam genutzt |
| **`nil`** | "Nichts da" — Luas Version von `null` |
| **`pcall`** | "Protected Call" — ruft eine Funktion auf und fängt Fehler ab, statt dass sie lautlos alles stoppen | 
| **SavedVariables** | Variablen, die der Client automatisch zwischen Logins auf der Festplatte speichert |
| **Frame-Pool** | Bereits gebaute, aktuell unsichtbare UI-Elemente werden wiederverwendet statt neu erzeugt/zerstört |
| **`C_Item.GetItemInfo`** | Liefert Item-Details (Name, Qualität, Icon, …) — kann `nil` liefern, wenn der Client die Daten noch nicht hat |
| **`GET_ITEM_INFO_RECEIVED`** | Event, das feuert, sobald oben genannte fehlende Daten nachgeladen wurden |
| **GlobalString** | Ein von Blizzard selbst definierter, übersetzter Textbaustein mit Platzhaltern (z. B. für Systemnachrichten) |
| **Hook (`hooksecurefunc`/`HookScript`)** | Sich "an" eine fremde Funktion/ein fremdes Script dranhängen, um mitzubekommen, wann sie läuft — riskant bei instabilen/fremden UI-Elementen |
| **Polling** | Wiederholt (z. B. jeden Frame) aktiv nachfragen "ist X gerade der Fall?", statt sich benachrichtigen zu lassen |

---

Für die Entwicklungsgeschichte (welcher Bug wann gefunden wurde, welche Entscheidung warum getroffen wurde, session-übergreifend) sieh dir `CLAUDE.md` an — die ist das laufende Tagebuch dieses Projekts. Diese Datei hier (`HOW_IT_WORKS.md`) ist der ruhigere, strukturierte Gegenpart dazu: einmal verstehen, statt chronologisch nachlesen.
