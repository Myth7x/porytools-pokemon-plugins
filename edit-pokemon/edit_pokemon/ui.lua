-- Builds the dockable "Edit Pokémon" panel and exposes a clean API to
-- the controller (plugin.lua). This module knows nothing about ASM files;
-- it only knows about widgets, form fields, and which tab is showing.
--
-- A note on showing/hiding:
--   PluginLabel has setVisible(), but the other widget types do not.
--   To make a tab "disappear" we just move its widgets way off-screen.
--   The trick lives in the Section helper at the top of this file — the
--   rest of the code uses Section:show() and never sees the magic.

local BaseStats = require("edit_pokemon.base_stats_file")

local UI = {}

local OFFSCREEN_X = -9999
local OFFSCREEN_Y = -9999

-- ---------------------------------------------------------------
-- Section: a group of widgets that show/hide together
-- ---------------------------------------------------------------

local Section = {}

function Section.new()
  return { entries = {}, visible = true }
end

function Section.add(section, widget, x, y)
  widget:setPosition(x, y)
  table.insert(section.entries, { widget = widget, x = x, y = y })
end

function Section.show(section)
  section.visible = true
  for _, entry in ipairs(section.entries) do
    entry.widget:setPosition(entry.x, entry.y)
  end
end

function Section.hide(section)
  section.visible = false
  for _, entry in ipairs(section.entries) do
    entry.widget:setPosition(OFFSCREEN_X, OFFSCREEN_Y)
  end
end

-- ---------------------------------------------------------------
-- Form helpers
-- ---------------------------------------------------------------

-- Build a vertical form of label-and-input rows inside a section.
-- `defs` is a list of { key, label, kind = "int"|"text"|"select", items? }.
-- Returns a `form` table keyed by `key`, plus the next available y-coordinate.
local function buildForm(panel, section, startY, defs)
  local form = {}
  local y = startY

  for _, def in ipairs(defs) do
    local label = panel:addLabel(def.label .. ":")
    label:setSize(110, 22)
    Section.add(section, label, 20, y + 4)

    local input
    if def.kind == "select" then
      input = panel:addSelection(def.label)
      input:setSize(220, 26)
      if def.items then input:setItems(def.items) end
    else
      input = panel:addLineEdit("")
      input:setSize(220, 26)
    end
    Section.add(section, input, 135, y)

    form[def.key] = { input = input, kind = def.kind, label = label }
    y = y + 32
  end

  return form, y
end

-- Set a dropdown to a specific text value. If the value isn't already in
-- the list (because the project's constants file was missing or odd),
-- add it on the fly so the user doesn't lose data.
local function setDropdown(input, value)
  if not value or value == "" then
    input:setCurrentIndex(0)
    return
  end
  input:setCurrentText(value)
  if input:currentText() ~= value then
    input:addItem(value)
    input:setCurrentText(value)
  end
end

-- Read an integer from a form field. Returns:
--   number  on success
--   nil     if the field is empty (caller decides what to do)
--   false   if the field is non-empty but not a valid number (an alert
--           is shown to the user)
local function readInt(form, key)
  local text = form[key].input:text()
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local n = tonumber(text)
  if not n then
    pt.ui.alert("Field '" .. form[key].label:text() ..
                "' must be an integer (got '" .. text .. "').")
    return false
  end
  return n
end

-- ---------------------------------------------------------------
-- Field definitions
-- ---------------------------------------------------------------

local function statsFieldDefs(isGen2, constants)
  if isGen2 then
    return {
      { key = "hp",     label = "HP",          kind = "int"    },
      { key = "atk",    label = "Attack",      kind = "int"    },
      { key = "def",    label = "Defense",     kind = "int"    },
      { key = "spd",    label = "Speed",       kind = "int"    },
      { key = "spa",    label = "Sp. Atk",     kind = "int"    },
      { key = "spdef",  label = "Sp. Def",     kind = "int"    },
      { key = "type1",  label = "Type 1",      kind = "select", items = constants.types },
      { key = "type2",  label = "Type 2",      kind = "select", items = constants.types },
      { key = "catch",  label = "Catch Rate",  kind = "int"    },
      { key = "exp",    label = "Base Exp",    kind = "int"    },
      { key = "growth", label = "Growth",      kind = "select", items = constants.growthRates },
      { key = "gender", label = "Gender",      kind = "select", items = constants.genderRatios },
      { key = "item1",  label = "Item 1",      kind = "select", items = constants.items },
      { key = "item2",  label = "Item 2",      kind = "select", items = constants.items },
      { key = "egg1",   label = "Egg Group 1", kind = "select", items = constants.eggGroups },
      { key = "egg2",   label = "Egg Group 2", kind = "select", items = constants.eggGroups },
    }
  end
  return {
    { key = "hp",     label = "HP",         kind = "int"    },
    { key = "atk",    label = "Attack",     kind = "int"    },
    { key = "def",    label = "Defense",    kind = "int"    },
    { key = "spd",    label = "Speed",      kind = "int"    },
    { key = "spc",    label = "Special",    kind = "int"    },
    { key = "type1",  label = "Type 1",     kind = "select", items = constants.types },
    { key = "type2",  label = "Type 2",     kind = "select", items = constants.types },
    { key = "catch",  label = "Catch Rate", kind = "int"    },
    { key = "exp",    label = "Base Exp",   kind = "int"    },
    { key = "growth", label = "Growth",     kind = "select", items = constants.growthRates },
  }
end

-- ---------------------------------------------------------------
-- Building the panel
-- ---------------------------------------------------------------

-- Create the panel, build every section, and return a `ui` table that
-- the controller can drive. Callbacks default to no-ops; the controller
-- replaces them after creation:
--
--   ui = UI.create(opts)
--   ui.onSelectionChange = function(monIndex) ... end
--   ui.onSaveStats       = function(edits) ... end
--   ...
--
-- `opts` must contain:
--   isGen2          : bool
--   constants       : table from edit_pokemon.constants.loadAll
--   pokemonNames    : list of display names for the dropdown
--   genLabel        : string e.g. "Gen 2 (pokecrystal)"
function UI.create(opts)
  local panel = pt.ui.createWidget("Edit Pokémon")
  panel:setSize(560, 760)

  local ui = {
    panel        = panel,
    isGen2       = opts.isGen2,
    sections     = {},
    activeName   = nil,

    -- Callbacks; the controller assigns these.
    onSelectionChange = function(_) end,
    onSaveStats       = function(_) end,
    onSaveMoves       = function(_, _) end,
    onSaveEgg         = function(_) end,
    onReplaceFront    = function() end,
    onReplaceBack     = function() end,
    onOpenStats       = function() end,
    onOpenEvos        = function() end,
    onReload          = function() end,
  }

  -- ---- Header (always visible) -----------------------------------
  local title = panel:addLabel("Pokémon:")
  title:setPosition(12, 14)
  title:setSize(70, 22)

  local selection = panel:addSelection("Select a Pokémon")
  selection:setPosition(82, 10)
  selection:setSize(280, 26)
  selection:setItems(opts.pokemonNames)
  ui.selection = selection

  local genLabel = panel:addLabel(opts.genLabel)
  genLabel:setPosition(380, 14)
  genLabel:setSize(170, 22)

  local infoLabel = panel:addLabel("Selected: (none)")
  infoLabel:setPosition(12, 42)
  infoLabel:setSize(540, 20)
  ui.infoLabel = infoLabel

  -- ---- Tab buttons (always visible) ------------------------------
  local tabDefs = {
    { key = "stats",   label = "Stats" },
    { key = "moves",   label = "Moves & Evos" },
    { key = "egg",     label = "Egg Moves" },
    { key = "sprites", label = "Sprites" },
  }
  local tabX = 12
  for _, t in ipairs(tabDefs) do
    local btn = panel:addButton(t.label)
    btn:setPosition(tabX, 72)
    btn:setSize(120, 28)
    btn:onClick(function() UI.showSection(ui, t.key) end)
    tabX = tabX + 126
  end

  -- ---- Stats section ---------------------------------------------
  local statsSec = Section.new()
  ui.sections.stats = statsSec

  local statDefs = statsFieldDefs(opts.isGen2, opts.constants)
  local statsForm, nextY = buildForm(panel, statsSec, 110, statDefs)
  ui.statsForm = statsForm

  local saveStatsBtn = panel:addButton("Save Stats")
  saveStatsBtn:setSize(150, 30)
  Section.add(statsSec, saveStatsBtn, 20, nextY + 8)
  saveStatsBtn:onClick(function() UI._submitStats(ui) end)

  -- ---- Moves & Evolutions section --------------------------------
  local movesSec = Section.new()
  ui.sections.moves = movesSec

  local mvLabel = panel:addLabel("Level-up moves (one per line: '<level> <MOVE_CONST>'):")
  mvLabel:setSize(540, 20)
  Section.add(movesSec, mvLabel, 12, 110)

  local movesArea = panel:addTextArea("")
  movesArea:setSize(540, 260)
  Section.add(movesSec, movesArea, 12, 134)
  ui.movesArea = movesArea

  local evLabel = panel:addLabel("Evolutions (one per line: '<METHOD> <param>... <TARGET>'):")
  evLabel:setSize(540, 20)
  Section.add(movesSec, evLabel, 12, 402)

  local evosArea = panel:addTextArea("")
  evosArea:setSize(540, 200)
  Section.add(movesSec, evosArea, 12, 426)
  ui.evosArea = evosArea

  local saveMovesBtn = panel:addButton("Save Moves & Evolutions")
  saveMovesBtn:setSize(220, 30)
  Section.add(movesSec, saveMovesBtn, 12, 634)
  saveMovesBtn:onClick(function() ui.onSaveMoves(ui.movesArea:text(), ui.evosArea:text()) end)

  -- ---- Egg Moves section -----------------------------------------
  local eggSec = Section.new()
  ui.sections.egg = eggSec

  local eggHint = opts.isGen2
    and "Egg moves (one MOVE_CONSTANT per line):"
    or  "Egg moves are gen-2 only; this section is inactive for pokered."

  local eggLabel = panel:addLabel(eggHint)
  eggLabel:setSize(540, 20)
  Section.add(eggSec, eggLabel, 12, 110)

  local eggArea = panel:addTextArea("")
  eggArea:setSize(540, 480)
  Section.add(eggSec, eggArea, 12, 134)
  ui.eggArea = eggArea

  if opts.isGen2 then
    local saveEggBtn = panel:addButton("Save Egg Moves")
    saveEggBtn:setSize(170, 30)
    Section.add(eggSec, saveEggBtn, 12, 622)
    saveEggBtn:onClick(function() ui.onSaveEgg(ui.eggArea:text()) end)
  end

  -- ---- Sprites section -------------------------------------------
  local spritesSec = Section.new()
  ui.sections.sprites = spritesSec

  local frontCap = panel:addLabel("Front")
  Section.add(spritesSec, frontCap, 70, 110)
  local backCap = panel:addLabel("Back")
  Section.add(spritesSec, backCap, 310, 110)

  local frontImg = panel:addImage()
  frontImg:setSize(192, 192)
  Section.add(spritesSec, frontImg, 12, 134)
  ui.frontImg = frontImg

  local backImg = panel:addImage()
  backImg:setSize(192, 192)
  Section.add(spritesSec, backImg, 220, 134)
  ui.backImg = backImg

  local frontBtn = panel:addButton("Replace Front…")
  frontBtn:setSize(192, 28)
  Section.add(spritesSec, frontBtn, 12, 334)
  frontBtn:onClick(function() ui.onReplaceFront() end)

  local backBtn = panel:addButton("Replace Back…")
  backBtn:setSize(192, 28)
  Section.add(spritesSec, backBtn, 220, 334)
  backBtn:onClick(function() ui.onReplaceBack() end)

  local openStatsBtn = panel:addButton("Open base_stats .asm")
  openStatsBtn:setSize(192, 28)
  Section.add(spritesSec, openStatsBtn, 12, 372)
  openStatsBtn:onClick(function() ui.onOpenStats() end)

  local openEvosBtn = panel:addButton("Open evos_attacks.asm")
  openEvosBtn:setSize(192, 28)
  Section.add(spritesSec, openEvosBtn, 220, 372)
  openEvosBtn:onClick(function() ui.onOpenEvos() end)

  local reloadBtn = panel:addButton("Reload Pokémon List")
  reloadBtn:setSize(400, 28)
  Section.add(spritesSec, reloadBtn, 12, 410)
  reloadBtn:onClick(function() ui.onReload() end)

  -- Wire selection changes to the controller's hook.
  selection:onChange(function(idx) ui.onSelectionChange(idx) end)

  -- Start on the Stats tab.
  UI.showSection(ui, "stats")

  return ui
end

-- ---------------------------------------------------------------
-- Public API used by the controller
-- ---------------------------------------------------------------

function UI.show(ui)
  ui.panel:show()
end

function UI.showSection(ui, name)
  ui.activeName = name
  for sectionName, section in pairs(ui.sections) do
    if sectionName == name then
      Section.show(section)
    else
      Section.hide(section)
    end
  end
end

function UI.setSelectedInfo(ui, mon)
  if mon then
    ui.infoLabel:setText(string.format("Selected: %s (%s.asm)", mon.name, mon.id))
  else
    ui.infoLabel:setText("Selected: (none)")
  end
end

-- Show one Pokemon's parsed base stats in the Stats form.
function UI.fillStatsForm(ui, parsed)
  local form = ui.statsForm
  local keys = ui.isGen2 and BaseStats.STAT_KEYS_GEN2 or BaseStats.STAT_KEYS_GEN1

  if parsed.stats then
    for i, key in ipairs(keys) do
      if form[key] then
        form[key].input:setText(tostring(parsed.stats[i] or ""))
      end
    end
  end

  if parsed.types then
    setDropdown(form.type1.input, parsed.types[1])
    setDropdown(form.type2.input, parsed.types[2])
  end

  if form.catch and parsed.catch then
    form.catch.input:setText(tostring(parsed.catch))
  end
  if form.exp and parsed.exp then
    form.exp.input:setText(tostring(parsed.exp))
  end
  if form.growth and parsed.growth then
    setDropdown(form.growth.input, parsed.growth)
  end

  if ui.isGen2 then
    if form.item1 and parsed.items then
      setDropdown(form.item1.input, parsed.items[1])
      setDropdown(form.item2.input, parsed.items[2])
    end
    if form.gender and parsed.gender then
      setDropdown(form.gender.input, parsed.gender)
    end
    if form.egg1 and parsed.eggGroups then
      setDropdown(form.egg1.input, parsed.eggGroups[1])
      setDropdown(form.egg2.input, parsed.eggGroups[2])
    end
  end
end

-- Read the current values out of the Stats form into an `edits` table
-- ready to hand to BaseStats.write. Returns nil if the user typed
-- something invalid (we already alerted them).
--
-- `parsed` is the currently-loaded parse result; we fall back to its
-- values when a field is left blank, so a blank doesn't silently zero.
function UI.readStatsForm(ui, parsed)
  local form = ui.statsForm
  local keys = ui.isGen2 and BaseStats.STAT_KEYS_GEN2 or BaseStats.STAT_KEYS_GEN1

  local stats = {}
  for i, key in ipairs(keys) do
    local n = readInt(form, key)
    if n == false then return nil end                       -- bad input
    stats[i] = n or (parsed.stats and parsed.stats[i]) or 0 -- empty -> keep
  end
  if parsed.stats and #stats ~= #parsed.stats then
    pt.ui.alert(string.format(
      "Stat count mismatch: file has %d stats, UI has %d. Aborting save.",
      #parsed.stats, #stats))
    return nil
  end

  local edits = { stats = stats }

  local t1 = form.type1.input:currentText()
  local t2 = form.type2.input:currentText()
  if t1 ~= "" and t2 ~= "" then
    edits.types = { t1, t2 }
  end

  local catch = readInt(form, "catch")
  if catch == false then return nil end
  if catch then edits.catch = catch end

  local exp = readInt(form, "exp")
  if exp == false then return nil end
  if exp then edits.exp = exp end

  local growth = form.growth.input:currentText()
  if growth ~= "" then edits.growth = growth end

  if ui.isGen2 then
    local i1 = form.item1.input:currentText()
    local i2 = form.item2.input:currentText()
    if i1 ~= "" and i2 ~= "" then edits.items = { i1, i2 } end

    local gender = form.gender.input:currentText()
    if gender ~= "" then edits.gender = gender end

    local e1 = form.egg1.input:currentText()
    local e2 = form.egg2.input:currentText()
    if e1 ~= "" and e2 ~= "" then edits.eggGroups = { e1, e2 } end
  end

  return edits
end

-- Bridge between the Save Stats button and the controller's onSaveStats
-- callback. Reads the form, then hands the edits to the controller.
function UI._submitStats(ui)
  local edits = UI.readStatsForm(ui, ui._currentParsed or {})
  if edits then
    ui.onSaveStats(edits)
  end
end

-- The controller calls this just before/after loading a new Pokemon so
-- that _submitStats has the right `parsed` to fall back to.
function UI.setCurrentParsed(ui, parsed)
  ui._currentParsed = parsed
end

function UI.setMovesText(ui, text)
  ui.movesArea:setText(text)
end

function UI.setEvosText(ui, text)
  ui.evosArea:setText(text)
end

function UI.setEggText(ui, text)
  ui.eggArea:setText(text)
end

function UI.setFrontSprite(ui, path)
  if path and pt.file.exists(path) then
    ui.frontImg:setImage(path)
  else
    ui.frontImg:clear()
  end
end

function UI.setBackSprite(ui, path)
  if path and pt.file.exists(path) then
    ui.backImg:setImage(path)
  else
    ui.backImg:clear()
  end
end

function UI.setPokemonNames(ui, names)
  ui.selection:setItems(names)
end

function UI.setSelectedIndex(ui, idx)
  ui.selection:setCurrentIndex(idx)
end

return UI
