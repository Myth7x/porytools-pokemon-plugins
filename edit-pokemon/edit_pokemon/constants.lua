-- Loads lists of ASM constants from the open project.
--
-- pokered and pokecrystal both have a `constants/` folder full of files
-- like `type_constants.asm`, `move_constants.asm` and so on. Each file
-- declares a bunch of constants in one of two formats:
--
--   const NORMAL                      ; pokecrystal-style
--   DEF FIRE EQU 1                    ; pokered-style
--
-- This module parses those files into plain lists of names, e.g.:
--   { "NORMAL", "FIRE", "WATER", ... }
--
-- These lists are used to fill the dropdowns in the editor UI.

local Util = require("edit_pokemon.util")

local Constants = {}

-- Read one constants file and return a list of constant names.
-- If `prefix` is given, only names that start with it are returned.
function Constants.parseFile(path, prefix)
  local text = pt.file.read(path)
  if not text then
    return {}
  end

  local names = {}
  local seen = {}

  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    local code = Util.stripComment(raw)

    -- Try the three formats we know about, in order.
    local name = code:match("^%s*const%s+([%w_]+)")
    if not name then
      name = code:match("^%s*DEF%s+([%w_]+)%s+EQU%s")
    end
    if not name then
      name = code:match("^%s*([%w_]+)%s+EQU%s")
    end

    if name and not seen[name] then
      if not prefix or name:sub(1, #prefix) == prefix then
        seen[name] = true
        table.insert(names, name)
      end
    end
  end

  return names
end

-- Resolve a path relative to the project root.
-- Returns nil if the file doesn't exist (or no project is open).
local function resolveProjectPath(projectRoot, relative)
  if not projectRoot then
    return nil
  end
  local candidate = projectRoot .. "/" .. relative
  if pt.file.exists(candidate) then
    return candidate
  end
  return nil
end

-- These constants don't represent real types and shouldn't appear in the
-- Type dropdowns.
local TYPE_NAMES_TO_SKIP = {
  UNUSED_TYPES_START = true,
  UNUSED_TYPES_END = true,
  TYPES_START = true,
  TYPES_END = true,
}

-- Read every constants file we care about and return one big table:
--
--   {
--     types        = { "NORMAL", "FIRE", ... },
--     moves        = { "POUND", "KARATE_CHOP", ... },
--     species      = { "BULBASAUR", "IVYSAUR", ... },
--     items        = { "MASTER_BALL", "ULTRA_BALL", ... },
--     growthRates  = { "GROWTH_MEDIUM_FAST", ... },
--     genderRatios = { "GENDER_F0", "GENDER_F12_5", ... },
--     eggGroups    = { "EGG_MONSTER", "EGG_BUG", ... },
--   }
--
-- Missing files leave the corresponding list empty.
function Constants.loadAll(projectRoot)
  local result = {
    types        = {},
    moves        = {},
    species      = {},
    items        = {},
    growthRates  = {},
    genderRatios = {},
    eggGroups    = {},
  }

  local typesPath = resolveProjectPath(projectRoot, "constants/type_constants.asm")
  if typesPath then
    for _, name in ipairs(Constants.parseFile(typesPath)) do
      if not TYPE_NAMES_TO_SKIP[name] then
        table.insert(result.types, name)
      end
    end
  end

  local movesPath = resolveProjectPath(projectRoot, "constants/move_constants.asm")
  if movesPath then
    result.moves = Constants.parseFile(movesPath)
  end

  local speciesPath = resolveProjectPath(projectRoot, "constants/pokemon_constants.asm")
  if speciesPath then
    result.species = Constants.parseFile(speciesPath)
  end

  local itemsPath = resolveProjectPath(projectRoot, "constants/item_constants.asm")
  if itemsPath then
    result.items = Constants.parseFile(itemsPath)
  end

  -- pokecrystal calls it pokemon_data_constants.asm, pokered calls it
  -- pokedex_constants.asm. We just try both.
  local dataPath = resolveProjectPath(projectRoot, "constants/pokemon_data_constants.asm")
                or resolveProjectPath(projectRoot, "constants/pokedex_constants.asm")
  if dataPath then
    result.growthRates  = Constants.parseFile(dataPath, "GROWTH_")
    result.genderRatios = Constants.parseFile(dataPath, "GENDER_")
    result.eggGroups    = Constants.parseFile(dataPath, "EGG_")
  end

  return result
end

return Constants
