-- gen1_edit_map/constants.lua
-- Loads Gen1 (pokered) ASM constants needed for map editing.
--
-- Parses:
--   constants/sprite_constants.asm  → SPRITE_* names
--   constants/tileset_constants.asm → tileset names
--   constants/map_constants.asm     → map const names + {w,h} dimensions
--                                     via map_const NAME, WIDTH, HEIGHT
--   constants/map_object_constants.asm → movement constants (STAY, WALK, ...)

local Util = require("gen1_edit_map.util")

local Constants = {}

-- Parse a constants file for names matching optional prefix.
-- Handles: `const NAME`, `DEF NAME EQU N`, `NAME EQU N`
function Constants.parseFile(path, prefix)
  local text, _ = pt.file.read(path)
  if not text then return {} end
  local names, seen = {}, {}
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    local code = Util.stripComment(raw)
    local name = code:match("^%s*const%s+([%w_]+)")
    if not name then name = code:match("^%s*DEF%s+([%w_]+)%s+EQU%s") end
    if not name then name = code:match("^%s*([%w_]+)%s+EQU%s") end
    if name and not seen[name] then
      if not prefix or name:sub(1, #prefix) == prefix then
        seen[name] = true
        table.insert(names, name)
      end
    end
  end
  return names
end

-- Parse map_const entries from map_constants.asm.
-- Returns: { MAP_CONST = { w = width, h = height }, ... }
-- Two formats are handled:
--   map_const MAP_NAME, WIDTH, HEIGHT          (newer pokered)
--   MAP_NAME_WIDTH  EQU N / MAP_NAME_HEIGHT EQU N  (older constant pairs)
function Constants.parseMapDims(path)
  local text, _ = pt.file.read(path)
  if not text then return {} end
  local dims = {}
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    local code = Util.stripComment(raw)
    -- map_const NAME, W, H
    local name, w, h = code:match("map_const%s+([%w_]+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if name then
      dims[name] = { w = tonumber(w), h = tonumber(h) }
    end
  end
  return dims
end

local SPRITE_SKIP = { NUM_SPRITES=true, SPRITE_NONE=true, FIRST_STILL_SPRITE=true }
local MAP_SKIP    = { MAP_NONE=true, NUM_MAPS=true, MAPS_END=true }

local function resolve(root, rel)
  local p = root .. "/" .. rel
  return pt.file.exists(p) and p or nil
end

-- Load all constants for a pokered project.
-- Returns:
--   {
--     sprites     = { "SPRITE_OAK", ... },
--     tilesets    = { "OVERWORLD", "FOREST", ... },
--     maps        = { "PALLET_TOWN", ... },
--     mapDims     = { PALLET_TOWN = {w=10,h=18}, ... },
--     movements   = { "STAY", "WALK", "ANY_DIR", ... },
--   }
function Constants.loadAll(root)
  local result = {
    sprites   = {},
    tilesets  = {},
    maps      = {},
    mapDims   = {},
    movements = {},
  }

  -- Sprites
  local sp = resolve(root, "constants/sprite_constants.asm")
  if sp then
    for _, name in ipairs(Constants.parseFile(sp, "SPRITE_")) do
      if not SPRITE_SKIP[name] then
        table.insert(result.sprites, name)
      end
    end
  end

  -- Tilesets
  local ts = resolve(root, "constants/tileset_constants.asm")
  if ts then
    result.tilesets = Constants.parseFile(ts)
    -- filter out non-tileset entries (numbers, NUM_TILESETS, etc.)
    local filtered = {}
    for _, n in ipairs(result.tilesets) do
      if not n:match("^%d") and n ~= "NUM_TILESETS" and not n:match("^DEF") then
        table.insert(filtered, n)
      end
    end
    result.tilesets = filtered
  end

  -- Maps + dimensions
  local mc = resolve(root, "constants/map_constants.asm")
  if mc then
    for _, name in ipairs(Constants.parseFile(mc)) do
      if not MAP_SKIP[name] and not name:match("^%d") then
        table.insert(result.maps, name)
      end
    end
    result.mapDims = Constants.parseMapDims(mc)
  end

  -- Movement constants (STAY, WALK, ANY_DIR, NONE, UP, DOWN, etc.)
  local mv = resolve(root, "constants/map_object_constants.asm")
  if mv then
    result.movements = Constants.parseFile(mv)
  end
  -- Always include the basic Gen1 directions as fallback
  if #result.movements == 0 then
    result.movements = { "STAY", "WALK", "ANY_DIR", "UP", "DOWN", "LEFT", "RIGHT", "NONE" }
  end

  return result
end

return Constants
