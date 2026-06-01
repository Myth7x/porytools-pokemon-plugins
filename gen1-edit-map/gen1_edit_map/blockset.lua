-- gen1_edit_map/blockset.lua
-- Parse binary .bst blockset files for Gen1 (pokered) tilesets.
--
-- A .bst file is a flat binary where every 16 consecutive bytes define one
-- block (metatile).  Each byte is a tile index referencing the tileset's
-- 8×8-pixel tile data.  Blocks are 4×4 tiles = 32×32 pixels.
--
--   Block layout (tile indices):
--     [ t0  t1  t2  t3  ]   row 0 (top)
--     [ t4  t5  t6  t7  ]   row 1
--     [ t8  t9  t10 t11 ]   row 2
--     [ t12 t13 t14 t15 ]   row 3 (bottom)
--
-- Typical path: {root}/gfx/blocksets/{tileset_lowercase}.bst
-- Multiple path variants are tried to handle naming conventions.
--
-- Public API:
--   Blockset.findPath(root, tilesetConst)   → path or nil
--   Blockset.load(path)                    → blocks or nil
--   Blockset.loadForTileset(root, tilesetConst) → (blocks, resolvedPath, err)
--
-- Returns:
--   blocks = { [0]=tileArray, [1]=tileArray, ... }
--   where tileArray = {t0,t1,...,t15}  (1-based Lua table, 16 entries)

local Blockset = {}

-- Convert a tileset constant to the candidate file base names to try.
-- OVERWORLD         → { "overworld" }
-- REDS_HOUSE_1      → { "reds_house_1", "reds_house" }
-- FOREST_GATE       → { "forest_gate", "forest" }
local function tilesetCandidates(const)
  local base = const:lower()
  local candidates = { base }

  -- Strip trailing _1, _2 etc. as a fallback.
  local stripped = base:match("^(.-)_%d+$")
  if stripped and stripped ~= base then
    table.insert(candidates, stripped)
  end

  -- Also try with 'gfx_' prefix stripped (some roms store as 'overworld_gfx').
  local nofx = base:gsub("_gfx$", "")
  if nofx ~= base then table.insert(candidates, nofx) end

  return candidates
end

-- Locate the .bst file for a tileset constant.
function Blockset.findPath(root, tilesetConst)
  if not tilesetConst or tilesetConst == "" then return nil end
  local basesDir = root .. "/gfx/blocksets/"
  for _, name in ipairs(tilesetCandidates(tilesetConst)) do
    local p = basesDir .. name .. ".bst"
    if pt.file.exists(p) then return p end
  end
  return nil
end

-- Load a .bst file from a known path.
-- Returns 0-indexed table of tile arrays, or nil on failure.
function Blockset.load(path)
  local data, err = pt.file.read(path)
  if not data or #data == 0 then return nil, err end

  local blocks = {}
  local numBlocks = math.floor(#data / 16)

  for b = 0, numBlocks - 1 do
    local base = b * 16 + 1   -- string.byte is 1-indexed
    local tiles = {}
    for t = 0, 15 do
      tiles[t + 1] = string.byte(data, base + t)
    end
    blocks[b] = tiles
  end

  return blocks, nil
end

-- Convenience: locate AND load in one call.
-- Returns (blocks, resolvedPath, err).
function Blockset.loadForTileset(root, tilesetConst)
  local path = Blockset.findPath(root, tilesetConst)
  if not path then
    return nil, nil, "Blockset not found for tileset: " .. (tilesetConst or "?")
  end
  local blocks, err = Blockset.load(path)
  return blocks, path, err
end

return Blockset
