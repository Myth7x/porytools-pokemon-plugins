-- gen1_edit_map/tileset_gfx.lua
-- Build a per-block pixel cache from a Gen1 tileset PNG via a scratch canvas.
--
-- Gen1 tileset PNG layout:
--   128 px wide  = 16 tiles × 8 px per tile
--   N  px tall   (varies; typically 48–128 px for 6–16 rows)
--   Color depth  = 2-bit (4 shades); stored as full-colour PNG in pokered
--
-- Pixel cache:
--   buildCache returns blockCache, a 0-indexed table:
--     blockCache[blockId] = { r=..., g=..., b=... }  array indexed 1..1024
--   Each entry covers all 1024 pixels (32×32) of that block at a 1:1
--   source scale.  When rendering at a given canvas scale S, nearest-neighbor
--   downscaling maps each canvas pixel (px,py) in [0,S-1] to source pixel
--   (floor(px*32/S), floor(py*32/S)).
--
-- The scratch canvas (128×128) must be embedded in the main widget at an
-- offscreen position (e.g. –9999,–9999) before calling buildCache.
--
-- Public API:
--   TilesetGfx.tilesetPath(root, tilesetConst)   → path or nil
--   TilesetGfx.buildCache(scratch, root, tilesetConst, blockDefs)
--                                                → (blockCache, err)
--   TilesetGfx.renderBlock(canvas, bx, by, blockId, blockCache, scale)

local TilesetGfx = {}

-- ---------------------------------------------------------------------------
-- Tileset PNG path resolution
-- ---------------------------------------------------------------------------

local TILES_DIR = "gfx/tilesets/"

local function tilesetNameVariants(const)
  local base = const:lower()
  local stripped = base:match("^(.-)_%d+$")
  local variants = { base }
  if stripped and stripped ~= base then table.insert(variants, stripped) end
  return variants
end

function TilesetGfx.tilesetPath(root, tilesetConst)
  if not tilesetConst or tilesetConst == "" then return nil end
  for _, name in ipairs(tilesetNameVariants(tilesetConst)) do
    local p = root .. "/" .. TILES_DIR .. name .. ".png"
    if pt.file.exists(p) then return p end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Pixel cache builder
-- ---------------------------------------------------------------------------

-- Tiles per row in the tileset PNG.
local TILES_PER_ROW = 16
local TILE_PX       = 8   -- 8×8 pixels per raw tile
local BLOCK_TILES   = 4   -- 4×4 raw tiles per block
local BLOCK_PX      = BLOCK_TILES * TILE_PX  -- 32

-- Read all pixels from the scratch canvas into a 2D lookup table.
-- Returns rawPixels[y][x] = {r,g,b}.
-- Width and height describe the region to sample.
local function readAllPixels(canvas, w, h)
  local raw = {}
  for y = 0, h - 1 do
    raw[y] = {}
    for x = 0, w - 1 do
      local r, g, b = canvas:getPixel(x, y)
      raw[y][x] = { r = r or 0, g = g or 0, b = b or 0 }
    end
  end
  return raw
end

-- Build a flat 32×32 pixel array (1-indexed, 1..1024) for one block.
-- tileIds : array 1..16 of tile indices (from blockset)
-- rawPixels: rawPixels[y][x] from the scratch canvas
local function buildBlockPixels(tileIds, rawPixels)
  local pixels = {}
  for row = 0, BLOCK_TILES - 1 do
    for col = 0, BLOCK_TILES - 1 do
      local tileId = tileIds[row * BLOCK_TILES + col + 1]  -- 1-based Lua index
      local tileCol = tileId % TILES_PER_ROW
      local tileRow = math.floor(tileId / TILES_PER_ROW)
      local tileOriginX = tileCol * TILE_PX
      local tileOriginY = tileRow * TILE_PX

      for ty = 0, TILE_PX - 1 do
        for tx = 0, TILE_PX - 1 do
          local srcX = tileOriginX + tx
          local srcY = tileOriginY + ty

          -- Canvas pixel destination within the 32×32 block array.
          local dstX = col * TILE_PX + tx
          local dstY = row * TILE_PX + ty
          local idx  = dstY * BLOCK_PX + dstX + 1  -- 1-based

          local p = rawPixels[srcY] and rawPixels[srcY][srcX]
          pixels[idx] = p or { r = 0, g = 0, b = 0 }
        end
      end
    end
  end
  return pixels
end

-- Build the pixel cache for all unique block IDs used in the map.
-- scratch     : scratch PluginCanvas embedded in the widget (128×128+)
-- root        : project root path
-- tilesetConst: e.g. "OVERWORLD"
-- blockDefs   : table from Blockset.load (blockDefs[blockId] = tileArray)
-- Returns (blockCache, err).
function TilesetGfx.buildCache(scratch, root, tilesetConst, blockDefs)
  if not blockDefs then
    return {}, "No blockset data provided"
  end

  local tilesetPngPath = TilesetGfx.tilesetPath(root, tilesetConst)
  if not tilesetPngPath then
    -- Build a fallback grey-scale placeholder cache.
    local fallback = {}
    for blockId, _ in pairs(blockDefs) do
      local grey = math.floor(30 + (blockId % 16) * 10)
      local pixels = {}
      for i = 1, BLOCK_PX * BLOCK_PX do
        pixels[i] = { r = grey, g = grey, b = grey }
      end
      fallback[blockId] = pixels
    end
    return fallback, "Tileset PNG not found for " .. (tilesetConst or "?")
  end

  -- Draw tileset PNG onto the scratch canvas (full resolution, no scaling).
  scratch:drawImage(0, 0, tilesetPngPath)
  scratch:update()  -- CRITICAL: flush paint context to backing buffer before getPixel

  -- Sample all pixels we could need (worst case 128×128).
  local rawPixels = readAllPixels(scratch, 128, 128)

  -- Build per-block pixel arrays.
  local blockCache = {}
  for blockId, tileIds in pairs(blockDefs) do
    blockCache[blockId] = buildBlockPixels(tileIds, rawPixels)
  end

  return blockCache, nil
end

-- ---------------------------------------------------------------------------
-- Rendering helper: blit one block onto a canvas using nearest-neighbor scale.
-- bx, by  : block-grid coordinates (0-based)
-- scale   : pixels per block (e.g. 16)
-- offsetX, offsetY : canvas pan offset in pixels
-- ---------------------------------------------------------------------------
function TilesetGfx.renderBlock(canvas, bx, by, blockId, blockCache, scale, offsetX, offsetY)
  offsetX = offsetX or 0
  offsetY = offsetY or 0

  local pixels = blockCache[blockId]
  if not pixels then return end

  local canvasOriginX = bx * scale - offsetX
  local canvasOriginY = by * scale - offsetY

  for py = 0, scale - 1 do
    local cy = canvasOriginY + py
    if cy >= 0 then
      -- Map destination pixel row → source pixel row within 32×32 block.
      local srcY = math.floor(py * BLOCK_PX / scale)
      for px = 0, scale - 1 do
        local cx = canvasOriginX + px
        if cx >= 0 then
          local srcX  = math.floor(px * BLOCK_PX / scale)
          local idx   = srcY * BLOCK_PX + srcX + 1
          local pixel = pixels[idx]
          if pixel then
            canvas:setPixel(cx, cy, pixel.r, pixel.g, pixel.b)
          end
        end
      end
    end
  end
end

return TilesetGfx
