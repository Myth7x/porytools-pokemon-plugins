-- gen1_edit_map/canvas_tiles.lua
-- Block-picker canvas: renders all blocks from the current blockset at a
-- compact scale so the user can click to select the "active block" for the
-- paint tool.
--
-- Layout:
--   BLOCK_SCALE px per block (default 12).
--   BLOCKS_PER_ROW blocks per row.
--   Canvas width  = BLOCKS_PER_ROW * BLOCK_SCALE
--   Canvas height = ceil(numBlocks / BLOCKS_PER_ROW) * BLOCK_SCALE
--
-- Selected block is highlighted with a white border.
--
-- Public API:
--   CanvasTiles.render(canvas, state)
--   CanvasTiles.init(canvas, state, onChange)   – onChange(blockId)

local TilesetGfx = require("gen1_edit_map.tileset_gfx")

local CanvasTiles = {}

local BLOCK_SCALE    = 12   -- px per block on the picker canvas
local BLOCKS_PER_ROW = 20   -- 20 × 12 = 240 px wide

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function CanvasTiles.render(canvas, state)
  local blockCache = state.blockCache
  local blockDefs  = state.blockDefs
  local active     = state.activeBlock or 0

  if not blockCache or not blockDefs then
    canvas:clear(30, 30, 30)
    canvas:update()
    return
  end

  -- Determine max block ID.
  local maxId = 0
  for id, _ in pairs(blockDefs) do
    if id > maxId then maxId = id end
  end

  local numBlocks = maxId + 1
  local rows = math.ceil(numBlocks / BLOCKS_PER_ROW)
  local totalH = rows * BLOCK_SCALE

  -- Background.
  canvas:clear(30, 30, 30)

  -- Blit each block.
  for blockId = 0, maxId do
    if blockCache[blockId] then
      local col = blockId % BLOCKS_PER_ROW
      local row = math.floor(blockId / BLOCKS_PER_ROW)

      -- Use TilesetGfx.renderBlock with zero offset (picker has no pan).
      TilesetGfx.renderBlock(canvas, col, row, blockId, blockCache, BLOCK_SCALE, 0, 0)
    end
  end

  -- Highlight selected block.
  do
    local col = active % BLOCKS_PER_ROW
    local row = math.floor(active / BLOCKS_PER_ROW)
    local ox  = col * BLOCK_SCALE
    local oy  = row * BLOCK_SCALE
    canvas:setPenColor(255, 255, 255)
    canvas:drawRect(ox, oy, BLOCK_SCALE, BLOCK_SCALE)
  end

  canvas:update()
end

-- ---------------------------------------------------------------------------
-- Mouse init
-- ---------------------------------------------------------------------------

function CanvasTiles.init(canvas, state, onChange)
  canvas:onMousePress(function(x, y, _)
    if not state.blockDefs then return end
    local col     = math.floor(x / BLOCK_SCALE)
    local row     = math.floor(y / BLOCK_SCALE)
    local blockId = row * BLOCKS_PER_ROW + col

    -- Validate.
    local maxId = 0
    for id, _ in pairs(state.blockDefs) do
      if id > maxId then maxId = id end
    end
    if blockId < 0 or blockId > maxId then return end

    state.activeBlock = blockId
    if onChange then onChange(blockId) end
  end)
end

-- Return dimensions for sizing the canvas widget.
function CanvasTiles.dimensions(blockDefs)
  local maxId = 0
  if blockDefs then
    for id, _ in pairs(blockDefs) do
      if id > maxId then maxId = id end
    end
  end
  local numBlocks = maxId + 1
  local rows = math.max(1, math.ceil(numBlocks / BLOCKS_PER_ROW))
  return BLOCKS_PER_ROW * BLOCK_SCALE, rows * BLOCK_SCALE
end

return CanvasTiles
