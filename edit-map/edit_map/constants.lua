-- Loads lists of ASM constants useful for map editing from the open project.
--
-- Both pokered and pokecrystal have a `constants/` folder with files like
-- `sprite_constants.asm`, `music_constants.asm`, and `map_constants.asm`.
-- Each file declares constants in one of several formats:
--
--   const SPRITE_PLAYER            ; pokecrystal-style
--   DEF SPRITE_PLAYER EQU 0        ; pokered-style
--   SPRITE_PLAYER EQU 0            ; bare EQU
--
-- This module parses those files into plain lists of names used to fill
-- dropdowns and validate user input.

local Util = require("edit_map.util")

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

-- Resolve a project-relative path; returns nil if file doesn't exist.
local function resolve(projectRoot, relative)
  if not projectRoot then return nil end
  local p = projectRoot .. "/" .. relative
  return pt.file.exists(p) and p or nil
end

-- Build a set (table keyed by value) from a list for fast membership tests.
local function toSet(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

-- Names that are markers or counts rather than real sprites / maps — skip them.
local SPRITE_SKIP = toSet({
  "NUM_SPRITES", "SPRITE_NONE",
})

local MAP_SKIP = toSet({
  "MAP_NONE", "NUM_MAPS", "MAPS_END",
})

-- Read every constants file we care about for map editing.
-- Returns:
--   {
--     sprites       = { "SPRITE_PLAYER", "SPRITE_POKE_BALL", ... },
--     music         = { "MUSIC_PALLET_TOWN", ... },
--     maps          = { "PALLET_TOWN", "VIRIDIAN_CITY", ... },
--     tilesets      = { "OVERWORLD", "FOREST", ... },    -- gen1 only (may be empty)
--     movements     = { "WALK_UP", "STAY", ... },         -- gen1 map_object_constants
--     spriteMoveData= { "SPRITEMOVEDATA_STANDING_DOWN", ... },  -- gen2
--     scenes        = { "MAP_SCENE_PALLET_TOWN", ... },   -- gen2
--     bgEventTypes  = { "BGEVENT_READ", "BGEVENT_TRAINER_TIP", ... }, -- gen2
--   }
function Constants.loadAll(projectRoot)
  local result = {
    sprites       = {},
    music         = {},
    maps          = {},
    tilesets      = {},
    movements     = {},
    spriteMoveData= {},
    scenes        = {},
    bgEventTypes  = {},
  }

  -- Sprites -------------------------------------------------------
  local spritePath = resolve(projectRoot, "constants/sprite_constants.asm")
  if spritePath then
    for _, name in ipairs(Constants.parseFile(spritePath, "SPRITE_")) do
      if not SPRITE_SKIP[name] then
        table.insert(result.sprites, name)
      end
    end
    -- Gen2 SPRITEMOVEDATA_* lives in the same file
    result.spriteMoveData = Constants.parseFile(spritePath, "SPRITEMOVEDATA_")
  end

  -- Music ---------------------------------------------------------
  local musicPath = resolve(projectRoot, "constants/music_constants.asm")
                 or resolve(projectRoot, "audio/music_constants.asm")
  if musicPath then
    result.music = Constants.parseFile(musicPath, "MUSIC_")
  end

  -- Maps ----------------------------------------------------------
  local mapPath = resolve(projectRoot, "constants/map_constants.asm")
  if mapPath then
    for _, name in ipairs(Constants.parseFile(mapPath)) do
      if not MAP_SKIP[name] then
        table.insert(result.maps, name)
      end
    end
    -- Gen2 MAP_SCENE_* is also in map_constants.asm
    result.scenes = Constants.parseFile(mapPath, "MAP_SCENE_")
  end

  -- Tilesets (gen1 pokered) ---------------------------------------
  local tilesetPath = resolve(projectRoot, "constants/tileset_constants.asm")
  if tilesetPath then
    result.tilesets = Constants.parseFile(tilesetPath)
  end

  -- Movements (gen1 map_object_constants) -------------------------
  local movPath = resolve(projectRoot, "constants/map_object_constants.asm")
  if movPath then
    result.movements = Constants.parseFile(movPath)
  end

  -- BG event types (gen2) -----------------------------------------
  local bgPath = resolve(projectRoot, "constants/map_constants.asm")
  if bgPath then
    result.bgEventTypes = Constants.parseFile(bgPath, "BGEVENT_")
  end

  return result
end

return Constants
