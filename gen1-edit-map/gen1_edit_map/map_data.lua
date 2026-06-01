-- gen1_edit_map/map_data.lua
-- Loads .blk binary map files and resolves map dimensions.
--
-- In the current pret/pokered format, dimensions are NOT stored in the header
-- file.  They come from constants/map_constants.asm via map_const NAME, W, H.
-- The MAP_CONST from the header (e.g. PALLET_TOWN) is used as the lookup key.
--
-- Public API:
--   MapData.readBlk(path)                          → bytes[] or nil
--   MapData.resolve(mapConst, blkPath, constants)  → {blocks, mapW, mapH, total}

local MapData = {}

-- Read a .blk binary and return a 1-based array of block byte values.
function MapData.readBlk(path)
  if not path or not pt.file.exists(path) then return nil end
  local data, err = pt.file.read(path)
  if not data or #data == 0 then return nil end
  local blocks = {}
  for i = 1, #data do
    blocks[i] = string.byte(data, i)
  end
  return blocks
end

-- Write a .blk file from a 1-based array of block byte values.
-- Returns (ok, err).
function MapData.writeBlk(path, blocks)
  local chars = {}
  for _, b in ipairs(blocks) do
    table.insert(chars, string.char(b))
  end
  return pt.file.write(path, table.concat(chars))
end

-- Best-guess integer factorisation closest to a square, preferring w ≤ h.
local function inferSquarish(total)
  if total <= 0 then return 1, total end
  local bestW, bestH, bestDiff = 1, total, total - 1
  for w = 2, math.floor(math.sqrt(total)) do
    if total % w == 0 then
      local h   = total / w
      local diff = math.abs(w - h)
      if diff < bestDiff then
        bestW, bestH, bestDiff = w, h, diff
      end
    end
  end
  if bestW > bestH then bestW, bestH = bestH, bestW end
  return bestW, bestH
end

-- Resolve map dimensions and return the structured map data record.
--   mapConst  : string like "PALLET_TOWN" (from parsed header)
--   blkPath   : path to the .blk file
--   constants : result of Constants.loadAll (contains mapDims)
-- Returns: { blocks, mapW, mapH, total } or nil if blk not found.
function MapData.resolve(mapConst, blkPath, constants)
  local blocks = MapData.readBlk(blkPath)
  if not blocks then return nil end

  local total = #blocks
  local mapW, mapH

  -- 1. Try map_const dimensions from constants.
  if mapConst and constants and constants.mapDims then
    local dims = constants.mapDims[mapConst]
    if dims and dims.w and dims.h and dims.w * dims.h == total then
      mapW, mapH = dims.w, dims.h
    end
  end

  -- 2. Fall back to square-ish factorisation.
  if not mapW then
    mapW, mapH = inferSquarish(total)
  end

  return {
    blocks = blocks,
    mapW   = mapW,
    mapH   = mapH,
    total  = total,
  }
end

return MapData
