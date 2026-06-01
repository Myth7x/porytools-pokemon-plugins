-- Edit Pokémon — beginner-friendly multi-file rewrite.
--
-- This file is the entry point for the plugin. PoryTools loads it once
-- and then calls `run()` whenever the user clicks
-- Plugins → Tools → Edit Pokémon.
--
-- The actual logic is split across small modules in the `edit_pokemon/`
-- folder; this file is mostly wiring. Read it top-to-bottom — every
-- step is named after what it does.
--
-- Module layout:
--   edit_pokemon/util.lua              -- tiny string/line helpers
--   edit_pokemon/constants.lua         -- loads project constant lists
--   edit_pokemon/pokemon.lua           -- a Pokemon record + folder scan
--   edit_pokemon/base_stats_file.lua   -- read/write base_stats/*.asm
--   edit_pokemon/evos_attacks_file.lua -- read/write evos_attacks.asm
--   edit_pokemon/egg_moves_file.lua    -- read/write egg_moves.asm
--   edit_pokemon/ui.lua                -- the dockable panel

local Constants    = require("edit_pokemon.constants")
local Pokemon      = require("edit_pokemon.pokemon")
local BaseStats    = require("edit_pokemon.base_stats_file")
local EvosAttacks  = require("edit_pokemon.evos_attacks_file")
local EggMoves     = require("edit_pokemon.egg_moves_file")
local UI           = require("edit_pokemon.ui")

-- ---------------------------------------------------------------
-- Shared state for this plugin instance.
-- ---------------------------------------------------------------
--
-- We keep one table called `state` instead of many separate locals so
-- it's obvious what data the plugin is tracking.

local state = {
  projectRoot     = nil,        -- absolute path to the pokered/pokecrystal repo
  isGen2          = false,      -- true for pokecrystal, false for pokered

  statsDir        = nil,        -- data/pokemon/base_stats/
  evosAttacksPath = nil,        -- data/pokemon/evos_attacks.asm
  eggMovesPath    = nil,        -- data/pokemon/egg_moves.asm  (gen-2 only)
  frontDir        = nil,        -- gfx/pokemon/front/  (or gfx/pokemon/)
  backDir         = nil,        -- gfx/pokemon/back/   (or gfx/pokemon/)

  constants       = nil,        -- result of Constants.loadAll(projectRoot)
  pokemonList     = {},         -- list of Pokemon records
  currentMon      = nil,        -- the one the user has selected
  ui              = nil,        -- the dockable panel
}

-- ---------------------------------------------------------------
-- Project path resolution
-- ---------------------------------------------------------------

local function resolveProjectPath(relative)
  if not state.projectRoot then return nil end
  local guess = state.projectRoot .. "/" .. relative
  if pt.file.exists(guess) then return guess end
  return nil
end

local function locateStatsDir()
  local p = resolveProjectPath("data/pokemon/base_stats")
  if p then return p end
  return pt.ui.pickFolder("Locate data/pokemon/base_stats")
end

local function locateAllPaths()
  state.statsDir = locateStatsDir()
  if not state.statsDir then return false end

  -- If the user picked a folder manually, infer the project root from it.
  if not state.projectRoot then
    state.projectRoot = state.statsDir:gsub("[/\\]data[/\\]pokemon[/\\]base_stats$", "")
  end

  state.frontDir        = resolveProjectPath("gfx/pokemon/front")
                       or resolveProjectPath("gfx/pokemon")
  state.backDir         = resolveProjectPath("gfx/pokemon/back")
                       or resolveProjectPath("gfx/pokemon")
  state.evosAttacksPath = resolveProjectPath("data/pokemon/evos_attacks.asm")
                       or resolveProjectPath("data/pokemon/evos_moves.asm")
  state.eggMovesPath    = resolveProjectPath("data/pokemon/egg_moves.asm")

  return true
end

local function frontSpritePath(id)
  if not state.frontDir then return nil end
  return state.frontDir .. "/" .. id .. ".png"
end

local function backSpritePath(id)
  if not state.backDir then return nil end
  return state.backDir .. "/" .. id .. "b.png"
end

-- ---------------------------------------------------------------
-- Generation detection
-- ---------------------------------------------------------------

-- Count the integers in the first `db N, N, N, ...` line we find inside
-- a base_stats file. 5 numbers => gen-1 (pokered), 6 => gen-2 (pokecrystal).
-- Falls back to "does egg_moves.asm exist?" if the read fails.
local function detectGen()
  state.isGen2 = (state.eggMovesPath ~= nil)

  local firstFile = state.pokemonList[1]
  if not firstFile then return end

  local text = pt.file.read(firstFile.file)
  if not text then return end

  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local code = line:match("^%s*db%s+(.+)$")
    if code then
      local count = 0
      local allNumbers = true
      for part in code:gmatch("([^,]+)") do
        if not tonumber((part:gsub("^%s+", ""):gsub("%s+$", ""))) then
          allNumbers = false
          break
        end
        count = count + 1
      end
      if allNumbers and (count == 5 or count == 6) then
        state.isGen2 = (count == 6)
        return
      end
    end
  end
end

-- ---------------------------------------------------------------
-- Loading one Pokemon into the UI
-- ---------------------------------------------------------------

local function loadStats(mon)
  local parsed, err = BaseStats.read(mon.file, state.constants.types)
  if not parsed then
    pt.ui.alert("Read failed: " .. (err or "unknown"))
    return
  end
  mon.parsedStats = parsed
  UI.setCurrentParsed(state.ui, parsed)
  UI.fillStatsForm(state.ui, parsed)
end

local function loadEvosAttacks(mon)
  if not state.evosAttacksPath then
    UI.setMovesText(state.ui, "(data/pokemon/evos_attacks.asm not found)")
    UI.setEvosText(state.ui,  "(data/pokemon/evos_attacks.asm not found)")
    return
  end

  local block, err = EvosAttacks.read(state.evosAttacksPath, mon.pascal)
  if err then
    UI.setMovesText(state.ui, "Read error: " .. err)
    UI.setEvosText(state.ui,  "Read error: " .. err)
    return
  end
  mon.parsedEvos = block

  if block.missing then
    local msg = "; No `" .. mon.pascal .. "EvosAttacks:` label found in evos_attacks.asm."
    UI.setMovesText(state.ui, msg)
    UI.setEvosText(state.ui,  msg)
    return
  end

  local moveLines = {}
  for _, mv in ipairs(block.moves) do
    table.insert(moveLines, string.format("%d %s", mv.level, mv.move))
  end
  UI.setMovesText(state.ui, table.concat(moveLines, "\n"))

  local evoLines = {}
  for _, evo in ipairs(block.evolutions) do
    table.insert(evoLines, table.concat(evo, " "))
  end
  UI.setEvosText(state.ui, table.concat(evoLines, "\n"))
end

local function loadEggMoves(mon)
  if not state.isGen2 then
    UI.setEggText(state.ui, "(Egg moves are only present in gen-2 / pokecrystal projects.)")
    return
  end
  if not state.eggMovesPath then
    UI.setEggText(state.ui, "(data/pokemon/egg_moves.asm not found)")
    return
  end

  local block, err = EggMoves.read(state.eggMovesPath, mon.pascal)
  if err then
    UI.setEggText(state.ui, "Read error: " .. err)
    return
  end
  mon.parsedEgg = block

  if block.missing then
    UI.setEggText(state.ui,
      "; No `" .. mon.pascal .. "EggMoves:` label found in egg_moves.asm.")
    return
  end
  UI.setEggText(state.ui, table.concat(block.moves, "\n"))
end

local function loadSprites(mon)
  UI.setFrontSprite(state.ui, frontSpritePath(mon.id))
  UI.setBackSprite(state.ui, backSpritePath(mon.id))
end

local function loadPokemon(mon)
  if not mon then return end
  state.currentMon = mon
  UI.setSelectedInfo(state.ui, mon)
  loadStats(mon)
  loadEvosAttacks(mon)
  loadEggMoves(mon)
  loadSprites(mon)
end

-- ---------------------------------------------------------------
-- Save handlers (called from the UI's buttons)
-- ---------------------------------------------------------------

local function saveStats(edits)
  local mon = state.currentMon
  if not mon or not mon.parsedStats then return end

  local ok, err = BaseStats.write(mon.file, mon.parsedStats, edits)
  if not ok then
    pt.ui.alert("Write failed: " .. (err or "unknown"))
    return
  end
  pt.ui.notify("Saved stats for " .. mon.name)
  loadStats(mon)
end

local function saveMovesAndEvos(movesText, evosText)
  local mon = state.currentMon
  if not mon then return end
  if not state.evosAttacksPath then
    pt.ui.alert("data/pokemon/evos_attacks.asm not found in project.")
    return
  end
  if not mon.parsedEvos or mon.parsedEvos.missing then
    pt.ui.alert("No `" .. mon.pascal ..
                "EvosAttacks:` label in evos_attacks.asm — add an empty block manually first.")
    return
  end

  local moves, mErr = EvosAttacks.parseMovesText(movesText)
  if not moves then pt.ui.alert(mErr); return end

  local evos, eErr = EvosAttacks.parseEvosText(evosText, state.isGen2)
  if not evos then pt.ui.alert(eErr); return end

  -- Sort moves by (level, name) so the file stays stable across saves.
  table.sort(moves, function(a, b)
    if a.level == b.level then return a.move < b.move end
    return a.level < b.level
  end)

  local ok, err = EvosAttacks.write(state.evosAttacksPath, mon.parsedEvos, evos, moves)
  if not ok then pt.ui.alert("Write failed: " .. (err or "unknown")); return end

  pt.ui.notify(string.format(
    "Saved %d moves, %d evolutions for %s", #moves, #evos, mon.name))
  loadEvosAttacks(mon)
end

local function saveEgg(text)
  local mon = state.currentMon
  if not state.isGen2 or not mon then return end
  if not state.eggMovesPath then
    pt.ui.alert("data/pokemon/egg_moves.asm not found.")
    return
  end
  if not mon.parsedEgg or mon.parsedEgg.missing then
    pt.ui.alert("No `" .. mon.pascal .. "EggMoves:` label in egg_moves.asm.")
    return
  end

  local moves, err = EggMoves.parseText(text)
  if not moves then pt.ui.alert(err); return end

  local ok, werr = EggMoves.write(state.eggMovesPath, mon.parsedEgg, moves)
  if not ok then pt.ui.alert("Write failed: " .. (werr or "unknown")); return end

  pt.ui.notify(string.format("Saved %d egg moves for %s", #moves, mon.name))
  loadEggMoves(mon)
end

local function replaceSprite(targetPath, kind, refresh)
  if not targetPath then
    pt.ui.alert("Sprite folder not configured.")
    return
  end

  local picked = pt.ui.pickFile({ filters = "PNG images (*.png);;All Files (*)" })
  if not picked then return end

  local question = string.format(
    "Replace %s sprite with:\n%s\n\nDestination:\n%s", kind, picked, targetPath)
  if not pt.ui.confirm(question) then return end

  local ok, err = pt.file.copy(picked, targetPath, true)
  if not ok then
    pt.ui.alert("Copy failed: " .. (err or "unknown"))
    return
  end

  pt.ui.notify(string.format("Replaced %s sprite -> %s", kind, targetPath))
  if refresh then refresh() end
end

local function pokemonNames()
  local names = {}
  for _, mon in ipairs(state.pokemonList) do
    table.insert(names, mon.name)
  end
  return names
end

local function reloadPokemonList()
  state.pokemonList = Pokemon.scanFolder(state.statsDir)
  UI.setPokemonNames(state.ui, pokemonNames())
  UI.setSelectedIndex(state.ui, 1)
  loadPokemon(state.pokemonList[1])
end

-- ---------------------------------------------------------------
-- Entry point: PoryTools calls this when the user clicks the menu item.
-- ---------------------------------------------------------------

function run()
  -- If the panel already exists (the user closed it but the plugin is
  -- still loaded), just bring it back up.
  if state.ui then
    UI.show(state.ui)
    return
  end

  if pt.project.isOpen() then
    state.projectRoot = pt.project.root()
  end

  if not locateAllPaths() then
    pt.ui.alert(
      "No base_stats folder available — open a pokered/pokecrystal project or pick a folder manually.")
    return
  end

  state.constants   = Constants.loadAll(state.projectRoot)
  state.pokemonList = Pokemon.scanFolder(state.statsDir)
  if #state.pokemonList == 0 then
    pt.ui.alert("No .asm files found in:\n" .. state.statsDir)
    return
  end

  detectGen()

  state.ui = UI.create({
    isGen2       = state.isGen2,
    constants    = state.constants,
    pokemonNames = pokemonNames(),
    genLabel     = state.isGen2 and "Gen 2 (pokecrystal)" or "Gen 1 (pokered)",
  })

  -- Wire the UI's callbacks to our save handlers.
  state.ui.onSelectionChange = function(idx)
    loadPokemon(state.pokemonList[idx])
  end

  state.ui.onSaveStats = saveStats
  state.ui.onSaveMoves = saveMovesAndEvos
  state.ui.onSaveEgg   = saveEgg

  state.ui.onReplaceFront = function()
    local mon = state.currentMon
    if not mon then return end
    replaceSprite(frontSpritePath(mon.id), "front", function() loadSprites(mon) end)
  end

  state.ui.onReplaceBack = function()
    local mon = state.currentMon
    if not mon then return end
    replaceSprite(backSpritePath(mon.id), "back", function() loadSprites(mon) end)
  end

  state.ui.onOpenStats = function()
    local mon = state.currentMon
    if not mon then return end
    local ok, err = pt.tabs.open(mon.file)
    if not ok then pt.ui.alert("Open failed: " .. (err or "unknown")) end
  end

  state.ui.onOpenEvos = function()
    if not state.evosAttacksPath then
      pt.ui.alert("evos_attacks.asm not found.")
      return
    end
    pt.tabs.open(state.evosAttacksPath)
  end

  state.ui.onReload = reloadPokemonList

  -- Show the first Pokemon and open the panel.
  UI.setSelectedIndex(state.ui, 1)
  loadPokemon(state.pokemonList[1])
  UI.show(state.ui)

  pt.ui.notify(string.format(
    "Loaded %d Pokémon from %s (%s)",
    #state.pokemonList,
    state.statsDir,
    state.isGen2 and "gen 2" or "gen 1"))
end
