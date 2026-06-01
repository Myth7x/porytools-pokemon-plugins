# Edit Pokémon — Developer Guide

A beginner-friendly walk-through of how this plugin is built so you can
read, modify, or copy from it.

If you've never written a PoryTools plugin before, the [PoryTools
Plugin Documentation](https://myth7x.github.io/porytools/plugins/) site
is the host-side reference for everything under the `pt` global —
or read the Markdown sources in [`docs/plugins/`](../../docs/plugins/)
if you've cloned the repo.

---

## What the plugin does

Adds a dockable **Edit Pokémon** panel under **Plugins → Gen 1/2**. It
opens the currently-loaded pokered or pokecrystal disassembly and lets
you edit, per Pokémon:

- base stats, types, catch rate, base exp
- gen-2 only: held items, gender ratio, growth rate, egg groups
- level-up moves and evolutions
- egg moves (gen-2 only)
- front and back sprite images

The gen is auto-detected by counting the integers in the first base
stats file: 5 → gen-1 (pokered), 6 → gen-2 (pokecrystal). Files are
parsed by walking lines and recording the line index of each known
field; saving rewrites only those lines, so comments and anything the
plugin doesn't understand stay verbatim.

---

## File layout

```
edit-pokemon/
├── manifest.json                       -- name, version, menu, entry
├── plugin.lua                          -- entry: run(), state, controller
├── DOC.md                              -- this file
└── edit_pokemon/                       -- all sub-modules live here
    ├── util.lua                        -- string + line helpers
    ├── constants.lua                   -- loads constant lists from constants/*.asm
    ├── pokemon.lua                     -- a Pokémon record + folder scan
    ├── base_stats_file.lua             -- parse / rewrite base_stats/*.asm
    ├── evos_attacks_file.lua           -- parse / rewrite evos_attacks.asm
    ├── egg_moves_file.lua              -- parse / rewrite egg_moves.asm
    └── ui.lua                          -- the dockable panel + form/section helpers
```

The `edit_pokemon/` sub-folder is a **namespace** for our modules.
Because `package.loaded` is shared across every plugin in PoryTools,
nesting our modules under a unique folder name (the same as the plugin's
internal id) keeps them from clashing with sub-modules in other plugins.

---

## How a typical click flows through the code

```
user clicks "Plugins → Gen 1/2 → Edit Pokémon"
  │
  ▼
plugin.lua : run()
  │  - resolves project paths     (resolveProjectPath, locateAllPaths)
  │  - loads constants            (Constants.loadAll)
  │  - scans base_stats/*.asm     (Pokemon.scanFolder)
  │  - autodetects gen            (detectGen)
  │  - builds the panel           (UI.create)
  │  - assigns UI callbacks       (state.ui.onSaveStats = saveStats, …)
  │  - shows first Pokémon        (loadPokemon)
  ▼

user picks a Pokémon in the dropdown
  │
  ▼
ui.lua : selection:onChange  ──► ui.onSelectionChange
  │
  ▼
plugin.lua : loadPokemon(mon)
  ├── loadStats(mon)              ──► BaseStats.read   ──► UI.fillStatsForm
  ├── loadEvosAttacks(mon)        ──► EvosAttacks.read ──► UI.setMovesText / setEvosText
  ├── loadEggMoves(mon)           ──► EggMoves.read    ──► UI.setEggText
  └── loadSprites(mon)            ──► UI.setFrontSprite / setBackSprite

user clicks "Save Stats"
  │
  ▼
ui.lua : saveStatsBtn:onClick  ──► UI._submitStats(ui)
  │     - reads form values via UI.readStatsForm
  │     - calls ui.onSaveStats(edits)
  ▼
plugin.lua : saveStats(edits)
  └── BaseStats.write(mon.file, mon.parsedStats, edits)
        └── pt.file.write(...)
  ▼
plugin.lua : loadStats(mon)     -- re-read to confirm what was written
```

Every "save" path follows the same shape:

1. UI reads/validates → 2. Controller hands to file module → 3. File module rewrites
the file via `pt.file.write` → 4. Controller re-loads from disk so the UI
reflects what's actually on disk.

---

## Module reference

### `plugin.lua`

The entry point and controller. It owns one `state` table:

```lua
state = {
  projectRoot     = nil,      -- pokered/pokecrystal repo root
  isGen2          = false,
  statsDir        = nil,      -- data/pokemon/base_stats/
  evosAttacksPath = nil,
  eggMovesPath    = nil,
  frontDir        = nil,
  backDir         = nil,
  constants       = nil,      -- result of Constants.loadAll(...)
  pokemonList     = {},       -- list of Pokemon records
  currentMon      = nil,
  ui              = nil,      -- the UI object
}
```

`run()` is the function PoryTools calls each time the user clicks the
menu item. It either re-shows the existing panel or builds a fresh one.

### `edit_pokemon/util.lua`

Generic string and line helpers, all plain functions on a single `Util`
table. No metatables, no `self`. Useful subset:

| Function                          | What it does                                  |
| --------------------------------- | --------------------------------------------- |
| `Util.trim(s)`                    | strip leading/trailing whitespace             |
| `Util.titleCase(s)`               | `"bulbasaur"` → `"Bulbasaur"`                |
| `Util.pascalCase(id)`             | `"mr_mime"` → `"MrMime"` (ASM label form)    |
| `Util.splitLines(s)`              | string → list of lines                        |
| `Util.joinLines(lines)`           | list of lines → string with trailing newline |
| `Util.stripComment(line)`         | returns `code, comment` (`;…` is the comment) |
| `Util.indentOf(line)`             | leading whitespace of a line                  |
| `Util.replaceLineKeepingComment`  | replace code, preserve indent + trailing `;…`|

### `edit_pokemon/constants.lua`

Reads the project's `constants/*.asm` files and turns them into plain
lists of names used to populate the dropdowns.

Supports three constant declaration styles:

```
const NORMAL                          -- pokecrystal (const_def macro)
DEF FIRE EQU 1                        -- pokered style
WATER EQU 2                           -- bare EQU
```

Public API:

```lua
Constants.parseFile(path, prefix?)    -- list of names, optional prefix filter
Constants.loadAll(projectRoot)        -- { types, moves, species, items,
                                      --   growthRates, genderRatios,
                                      --   eggGroups } -- missing files
                                      --   leave the matching list empty
```

### `edit_pokemon/pokemon.lua`

A "Pokemon" is just a small table:

```lua
{
  id     = "bulbasaur",                -- file basename
  name   = "Bulbasaur",                -- display name
  pascal = "Bulbasaur",                -- ASM-label form
  file   = "<path>/bulbasaur.asm",
  parsedStats = nil,                   -- filled lazily on load
  parsedEvos  = nil,
  parsedEgg   = nil,
}
```

Public API:

```lua
Pokemon.new(id, file)
Pokemon.scanFolder(dir)                -- sorted list of Pokemon records
```

### `edit_pokemon/base_stats_file.lua`

Parses and rewrites one Pokémon's `base_stats/*.asm` file.

The parser walks the lines looking for shapes it recognises (a `db` with
5 or 6 plain numbers is the stats line, the next `db NAME, NAME` is the
types line, etc.) and records the **line index** of each known field.
The serializer only touches those tracked lines; everything else —
including comments, blank lines, and any unknown directives — survives
unchanged.

Public API:

```lua
BaseStats.STAT_KEYS_GEN1   -- { "hp", "atk", "def", "spd", "spc" }
BaseStats.STAT_KEYS_GEN2   -- { "hp", "atk", "def", "spd", "spa", "spdef" }

BaseStats.read(path, knownTypes?)              -- (parsed, err)
BaseStats.parse(text, knownTypes?)             -- parsed table
BaseStats.serialize(parsed, edits)             -- new file text
BaseStats.write(path, parsed, edits)           -- (ok, err)
```

The `parsed` table contains both the values *and* the line indices:

```lua
{
  lines     = { ... whole file ... },
  stats     = { 45, 49, 49, 45, 65, 65 },  statsLine  = 3,
  types     = { "GRASS", "POISON" },        typesLine  = 4,
  catch     = 45,                           catchLine  = 5,
  exp       = 64,                           expLine    = 6,
  items     = { "NO_ITEM", "NO_ITEM" },     itemsLine  = 7,
  gender    = "GENDER_F12_5",               genderLine = 8,
  growth    = "GROWTH_MEDIUM_SLOW",         growthLine = 14,
  eggGroups = { "EGG_MONSTER", "EGG_PLANT" }, eggLine = 15,
}
```

`edits` is the same shape but contains **only** the fields the user
changed. Missing keys mean "leave this line alone".

### `edit_pokemon/evos_attacks_file.lua`

Same idea for `data/pokemon/evos_attacks.asm` (or pokered's
`evos_moves.asm`). Each Pokémon has a labelled block:

```
BulbasaurEvosAttacks:
    db EVOLVE_LEVEL, 16, IVYSAUR
    db 0                          ; end-of-evolutions terminator
    db 1, TACKLE
    db 1, GROWL
    db 0                          ; end-of-moves terminator
```

`read()` returns the block split into evolutions, moves, and the line
range that block occupies in the file. `rebuild()` swaps the block for a
fresh one built from the user's edited lists; the rest of the file is
untouched.

Method prefixes are normalised when writing: a bare `LEVEL` becomes
`EVOLVE_LEVEL` (gen-2) or `EV_LEVEL` (gen-1), so users don't have to
type the prefix every time.

Public API:

```lua
EvosAttacks.read(path, pascalName)              -- (block, err)
EvosAttacks.parseMovesText(text)                -- (list, errMsg?)
EvosAttacks.parseEvosText(text, isGen2)         -- (list, errMsg?)
EvosAttacks.rebuild(block, evolutions, moves)   -- new file text
EvosAttacks.write(path, block, evolutions, moves) -- (ok, err)
```

### `edit_pokemon/egg_moves_file.lua`

Gen-2 only. Each Pokémon's egg moves are a flat list of move constants
terminated by `db -1` (or `db $ff`). Public API mirrors the previous
module:

```lua
EggMoves.read(path, pascalName)
EggMoves.parseText(text)
EggMoves.rebuild(block, moves)
EggMoves.write(path, block, moves)
```

### `edit_pokemon/ui.lua`

Builds the dockable panel and exposes a clean API. The UI knows nothing
about ASM files — it only knows about widgets, form fields, and which
tab is showing.

Two small ideas live at the top of this file:

**Section helper.** Only `PluginLabel` has `setVisible()` in the current
host API. To make a "tab" disappear, we move every widget in that tab to
off-screen coordinates. The `Section` table at the top of `ui.lua`
wraps that trick so the rest of the code just calls `Section.show()` /
`Section.hide()`.

**buildForm.** A small loop that takes a list of field definitions
(`{ key, label, kind = "int"|"text"|"select", items? }`) and lays them
out as label / input rows. The returned `form` table is keyed by `key`,
so reading a field is `form.hp.input:text()`.

Public API used by the controller:

```lua
ui = UI.create({                                  -- build the panel
  isGen2, constants, pokemonNames, genLabel,
})

UI.show(ui)
UI.showSection(ui, "stats"|"moves"|"egg"|"sprites")

UI.setSelectedInfo(ui, mon)
UI.fillStatsForm(ui, parsed)
UI.readStatsForm(ui, parsed)       -- returns `edits` or nil
UI.setCurrentParsed(ui, parsed)    -- gives the Save button context

UI.setMovesText(ui, text)          UI.setEvosText(ui, text)
UI.setEggText(ui, text)
UI.setFrontSprite(ui, path)        UI.setBackSprite(ui, path)

UI.setPokemonNames(ui, names)      UI.setSelectedIndex(ui, idx)
```

Callbacks the controller assigns after creating the UI:

```lua
ui.onSelectionChange = function(monIndex) end
ui.onSaveStats       = function(edits) end
ui.onSaveMoves       = function(movesText, evosText) end
ui.onSaveEgg         = function(eggText) end
ui.onReplaceFront    = function() end
ui.onReplaceBack     = function() end
ui.onOpenStats       = function() end           -- open base_stats .asm
ui.onOpenEvos        = function() end           -- open evos_attacks.asm
ui.onReload          = function() end           -- rescan base_stats folder
```

---

## How to extend

### Add a new editable field on the Stats tab

1. Add the field's parser line index and value to the result table in
   `base_stats_file.lua : BaseStats.parse`. Pick a stable location to
   search for it — usually a distinctive prefix like `db CATCH_RATE_…`.

2. Add a setter for it in `BaseStats.serialize`:

   ```lua
   if edits.myThing then setLine(parsed.myThingLine, "db " .. edits.myThing) end
   ```

3. Add the field def to the appropriate list in
   `ui.lua : statsFieldDefs`:

   ```lua
   { key = "myThing", label = "My Thing", kind = "int" },
   ```

4. Populate it in `UI.fillStatsForm` and read it back in
   `UI.readStatsForm`. Follow the patterns already there for `catch`,
   `exp`, etc.

You don't need to touch `plugin.lua` for this — the existing save handler
already passes the whole `edits` table through.

### Add a new tab

1. In `ui.lua`'s `UI.create`, add the tab's button to the `tabDefs` list
   and add a new `Section.new()` for it.

2. Place its widgets with `Section.add(yourSection, widget, x, y)`. Wire
   any save button to a new `ui.onSaveYourThing(...)` callback.

3. In `plugin.lua`, write a `saveYourThing(...)` function and assign it
   to `state.ui.onSaveYourThing` near the bottom of `run()`.

4. Add a loader (`loadYourThing(mon)`) and call it from `loadPokemon`.

### Support another disassembly fork

The plugin already supports both pokered and pokecrystal. If a fork
adds a new field shape, extend `BaseStats.parse` to recognise it and add
the matching serializer branch. Try to avoid breaking either of the two
existing flavours — the parser is intentionally tolerant so it can keep
walking past lines it doesn't understand.

---

## Plugin loader contract

This plugin uses two host features beyond the basics covered in the
[main plugin docs](https://myth7x.github.io/porytools/plugins/):

- **`__plugin_dir`** — a global the host sets to the absolute path of
  this plugin's folder before running `plugin.lua`. We don't use it
  directly because:

- **Automatic `package.path` pre-pend** — while `plugin.lua` is being
  loaded, the host prepends `<plugin_dir>/?.lua` and
  `<plugin_dir>/?/init.lua` to `package.path`. That's what lets
  `require("edit_pokemon.util")` resolve to
  `<plugin_dir>/edit_pokemon/util.lua` with no setup code.

After the entry script finishes loading, `package.path` is restored.
That's fine for this plugin because every `require()` happens at the top
of `plugin.lua`, before `run()` is ever called — by the time `run()`
fires, the modules are already cached in `package.loaded`.

If you split your own plugin across files, do the same: `require()` at
the top of your entry file, not inside callbacks.

---

## Manual test plan

1. Open a pokered or pokecrystal project in PoryTools.
2. **Plugins → Gen 1/2 → Edit Pokémon**. Confirm the panel opens, the
   gen label is correct, and Bulbasaur (or whichever is first
   alphabetically) is selected.
3. **Stats tab:** change HP, click *Save Stats*, then open the
   underlying `.asm` (use the *Open base_stats .asm* button on the
   Sprites tab). Confirm only the `db HP, …` line changed and comments
   were preserved.
4. **Moves & Evos tab:** edit one move's level, save, re-open the
   selection. Confirm the change round-tripped through the file.
5. **Egg Moves tab** (gen-2 only): add a move, save, verify the new
   line appears between the label and the `db -1` terminator.
6. **Sprites tab:** swap a front sprite via *Replace Front…* and check
   `gfx/pokemon/<id>/front.png` (or `gfx/pokemon/<id>.png` on pokered)
   updated.
7. Reload the Pokémon list and confirm a freshly-added `.asm` in
   `base_stats/` appears in the dropdown.

Errors show up in the **Output** dock under the **Plugins** channel and
also as message boxes.
