-- gen1_edit_map/canvas_map.lua
-- Interactive map canvas for the Gen1 editor.
--
-- Rendering pipeline:
--   1. Iterate all map blocks (state.mapData.blocks).
--   2. For each block, blit blockCache[blockId] pixels via setPixel with
--      nearest-neighbor scaling at state.scale px/block.
--   3. Draw event overlays: warps (blue), signs (yellow), NPCs (sprite PNG).
--   4. Draw selection highlight on the active block or selected event.
--
-- Coordinate systems:
--   Block coords (bx,by): integer, origin top-left, 0-based.
--   Step  coords (sx,sy): event X/Y in the objects file (2 steps per block).
--   Canvas pixels (cx,cy): 0-based, include pan offset.
--
--   blockToCanvas(bx, by, scale, offX, offY) = (bx*scale - offX, by*scale - offY)
--   stepToCanvas (sx, sy, scale, offX, offY) = (sx/2*scale - offX, sy/2*scale - offY)
--
-- Mouse tools:
--   "select"   – click block or event → populate state.selectedEvent / state.selectedBlock
--   "paint"    – click/drag → write state.activeBlock to blocks array, mark dirty
--   "erase"    – click/drag → write block 0
--   "add_warp" – click → append warp with block coords at cursor
--   "add_npc"  – click → append NPC with default sprite at cursor
--   "add_sign" – click → append bg_event at cursor
--
-- Pan: right-button drag or middle-button drag.
-- Zoom: state.scale increased/decreased externally (re-render required).
--
-- Public API:
--   CanvasMap.init(canvas, state, callbacks)  – wire mouse events
--   CanvasMap.render(canvas, state)           – full redraw
--   CanvasMap.pixelToBlock(cx, cy, state)     – canvas pixel → {bx, by}

local TilesetGfx = require("gen1_edit_map.tileset_gfx")

local CanvasMap = {}

-- ---------------------------------------------------------------------------
-- Coordinate helpers
-- ---------------------------------------------------------------------------

-- Canvas origin (top-left pixel) of a block.
local function blockOriginC(bx, by, scale, offX, offY)
  return bx * scale - offX, by * scale - offY
end

-- Canvas origin of a step-space coordinate (event coords).
local function stepOriginC(sx, sy, scale, offX, offY)
  local bxF = sx / 2.0
  local byF = sy / 2.0
  return bxF * scale - offX, byF * scale - offY
end

function CanvasMap.pixelToBlock(cx, cy, state)
  local scale = state.scale or 16
  local offX  = state.viewOffX or 0
  local offY  = state.viewOffY or 0
  local bx = math.floor((cx + offX) / scale)
  local by = math.floor((cy + offY) / scale)
  return bx, by
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------

-- Fill a rectangle on the canvas.
local function fillRect(canvas, x, y, w, h, r, g, b)
  for py = y, y + h - 1 do
    for px = x, x + w - 1 do
      if px >= 0 and py >= 0 then
        canvas:setPixel(px, py, r, g, b)
      end
    end
  end
end

-- Draw the outline of a rectangle.
local function drawRect(canvas, x, y, w, h, r, g, b)
  for px = x, x + w - 1 do
    if px >= 0 then
      if y >= 0     then canvas:setPixel(px, y,         r, g, b) end
      if y+h-1 >= 0 then canvas:setPixel(px, y + h - 1, r, g, b) end
    end
  end
  for py = y + 1, y + h - 2 do
    if py >= 0 then
      if x >= 0     then canvas:setPixel(x,         py, r, g, b) end
      if x+w-1 >= 0 then canvas:setPixel(x + w - 1, py, r, g, b) end
    end
  end
end

-- Draw a crosshair/diamond overlay for a step-space event position.
local function drawEventMark(canvas, cx, cy, size, r, g, b)
  local half = math.max(2, math.floor(size / 4))
  for d = -half, half do
    local x1, y1 = cx + d,    cy
    local x2, y2 = cx,        cy + d
    if x1 >= 0 and y1 >= 0 then canvas:setPixel(x1, y1, r, g, b) end
    if x2 >= 0 and y2 >= 0 then canvas:setPixel(x2, y2, r, g, b) end
  end
end

-- ---------------------------------------------------------------------------
-- Main render
-- ---------------------------------------------------------------------------

function CanvasMap.render(canvas, state)
  if not state.mapData or not state.mapData.blocks then return end

  local blocks    = state.mapData.blocks
  local mapW      = state.mapData.mapW or 1
  local mapH      = state.mapData.mapH or 1
  local scale     = state.scale or 16
  local offX      = state.viewOffX or 0
  local offY      = state.viewOffY or 0
  local blockCache = state.blockCache or {}

  -- Determine canvas dimensions live from the widget (adapts if resized).
  local cw = canvas:width()
  local ch = canvas:height()

  -- Clear canvas with dark background (native clear — much faster than setPixel loop).
  canvas:clear(30, 30, 30)

  -- Blit blocks that are at least partially visible.
  for by = 0, mapH - 1 do
    for bx = 0, mapW - 1 do
      local ox, oy = blockOriginC(bx, by, scale, offX, offY)

      -- Cull fully off-screen blocks.
      if ox < cw and oy < ch and ox + scale >= 0 and oy + scale >= 0 then
        local idx     = by * mapW + bx + 1  -- 1-based
        local blockId = blocks[idx] or 0

        if blockCache[blockId] then
          TilesetGfx.renderBlock(canvas, bx, by, blockId, blockCache, scale, offX, offY)
        else
          -- Fallback: grey square.
          local grey = 60 + (blockId % 8) * 10
          canvas:setFillColor(grey, grey, grey)
          canvas:fillRect(math.max(0, ox), math.max(0, oy),
            math.min(scale, cw - math.max(0,ox)),
            math.min(scale, ch - math.max(0,oy)))
        end
      end
    end
  end

  -- Event overlays.
  local parsedObj = state.parsedObj
  if parsedObj then
    -- Warps – blue fill with brighter border.
    for _, w in ipairs(parsedObj.warps or {}) do
      local sx, sy = tonumber(w.x) or 0, tonumber(w.y) or 0
      local cx, cy = stepOriginC(sx, sy, scale, offX, offY)
      local size   = math.max(4, scale / 2)
      canvas:setFillColor(40, 80, 220)
      canvas:fillRect(math.floor(cx), math.floor(cy), math.ceil(size), math.ceil(size))
      canvas:setPenColor(80, 130, 255)
      canvas:drawRect(math.floor(cx), math.floor(cy), math.ceil(size), math.ceil(size))
    end

    -- Signs / bg_events – yellow diamond (crosshair via setPixel).
    for _, b in ipairs(parsedObj.bgEvents or {}) do
      local sx, sy = tonumber(b.x) or 0, tonumber(b.y) or 0
      local cx, cy = stepOriginC(sx, sy, scale, offX, offY)
      drawEventMark(canvas, math.floor(cx + scale/4), math.floor(cy + scale/4), scale, 240, 220, 50)
    end

    -- NPCs – try to use sprite PNG; fall back to green square.
    for _, obj in ipairs(parsedObj.people or {}) do
      local sx, sy = tonumber(obj.x) or 0, tonumber(obj.y) or 0
      local cx, cy = stepOriginC(sx, sy, scale, offX, offY)
      local icx    = math.floor(cx)
      local icy    = math.floor(cy)
      local isize  = math.max(8, scale)

      local spritePaths = state.spritePaths or {}
      local spritePath  = spritePaths[obj.sprite]
      if spritePath then
        canvas:drawImage(icx, icy, spritePath, isize, isize)
      else
        -- Fallback: green square.
        canvas:setFillColor(50, 180, 50)
        canvas:fillRect(icx, icy, isize, isize)
        canvas:setPenColor(100, 255, 100)
        canvas:drawRect(icx, icy, isize, isize)
      end
    end
  end

  -- Selection highlight.
  if state.selectedBlock then
    local bx, by = state.selectedBlock.bx, state.selectedBlock.by
    local ox, oy = blockOriginC(bx, by, scale, offX, offY)
    canvas:setPenColor(255, 255, 255)
    canvas:drawRect(math.floor(ox), math.floor(oy), scale, scale)
  end

  -- Tool cursor: show outline of active block position when in paint mode.
  if state.tool == "paint" and state.hoverBlock and state.blockCache then
    local bx, by = state.hoverBlock.bx, state.hoverBlock.by
    local ox, oy = blockOriginC(bx, by, scale, offX, offY)
    canvas:setPenColor(255, 200, 0)
    canvas:drawRect(math.floor(ox), math.floor(oy), scale, scale)
  end

  -- Tile grid overlay.
  canvas:setPenColor(180, 180, 180, 50)
  for gx = 0, mapW do
    local px = gx * scale - offX
    if px >= 0 and px <= cw then
      canvas:drawLine(px, 0, px, math.min(mapH * scale - offY, ch - 1))
    end
  end
  for gy = 0, mapH do
    local py = gy * scale - offY
    if py >= 0 and py <= ch then
      canvas:drawLine(0, py, math.min(mapW * scale - offX, cw - 1), py)
    end
  end

  canvas:update()
end

-- ---------------------------------------------------------------------------
-- Mouse event wiring
-- ---------------------------------------------------------------------------

-- Paint / erase / add-event at canvas position (cx, cy).
local function applyTool(cx, cy, state, callbacks)
  local bx, by = CanvasMap.pixelToBlock(cx, cy, state)
  local mapW = state.mapData and state.mapData.mapW or 0
  local mapH = state.mapData and state.mapData.mapH or 0

  if bx < 0 or by < 0 or bx >= mapW or by >= mapH then return end

  local tool = state.tool or "select"

  if tool == "paint" then
    local idx = by * mapW + bx + 1
    if state.mapData.blocks[idx] ~= state.activeBlock then
      state.mapData.blocks[idx] = state.activeBlock
      state.dirty = true
      if callbacks and callbacks.onBlockPaint then
        callbacks.onBlockPaint(bx, by, state.activeBlock)
      end
    end

  elseif tool == "erase" then
    local idx = by * mapW + bx + 1
    if state.mapData.blocks[idx] ~= 0 then
      state.mapData.blocks[idx] = 0
      state.dirty = true
    end

  elseif tool == "select" then
    state.selectedBlock = { bx = bx, by = by }
    if callbacks and callbacks.onBlockSelect then
      callbacks.onBlockSelect(bx, by)
    end

  elseif tool == "add_warp" then
    local sx = tostring(bx * 2)
    local sy = tostring(by * 2)
    if state.parsedObj then
      table.insert(state.parsedObj.warps, {
        x = sx, y = sy, dest = "MAP_NONE", warpId = "1", line = nil
      })
      state.dirty = true
      if callbacks and callbacks.onEventsChanged then callbacks.onEventsChanged() end
    end

  elseif tool == "add_npc" then
    local sx = tostring(bx * 2)
    local sy = tostring(by * 2)
    if state.parsedObj then
      local sprite = (state.constants and state.constants.sprites[1]) or "SPRITE_NONE"
      table.insert(state.parsedObj.people, {
        sprite = sprite, x = sx, y = sy,
        movement = "STAY", dir = "NONE",
        script = "TEXT_DUMMY", line = nil
      })
      state.dirty = true
      if callbacks and callbacks.onEventsChanged then callbacks.onEventsChanged() end
    end

  elseif tool == "add_sign" then
    local sx = tostring(bx * 2)
    local sy = tostring(by * 2)
    if state.parsedObj then
      table.insert(state.parsedObj.bgEvents, {
        x = sx, y = sy, script = "TEXT_DUMMY", line = nil
      })
      state.dirty = true
      if callbacks and callbacks.onEventsChanged then callbacks.onEventsChanged() end
    end
  end
end

-- Register all mouse callbacks on the canvas widget.
-- callbacks = { onBlockPaint, onBlockSelect, onEventsChanged, onRender }
function CanvasMap.init(canvas, state, callbacks)
  local isDragging  = false
  local isPanning   = false
  local lastPanX, lastPanY = 0, 0

  canvas:onMousePress(function(x, y, button)
    if button == 2 or button == 4 then
      -- Right / middle mouse → start pan.
      isPanning  = true
      lastPanX   = x
      lastPanY   = y
    elseif button == 1 then
      isDragging = true
      applyTool(x, y, state, callbacks)
      if callbacks and callbacks.onRender then callbacks.onRender() end
    end
  end)

  canvas:onMouseMove(function(x, y)
    local bx, by = CanvasMap.pixelToBlock(x, y, state)
    state.hoverBlock = { bx = bx, by = by }
    if callbacks and callbacks.onHover then callbacks.onHover(bx, by, x, y) end

    if isPanning then
      state.viewOffX = (state.viewOffX or 0) - (x - lastPanX)
      state.viewOffY = (state.viewOffY or 0) - (y - lastPanY)
      -- Clamp to map bounds.
      local scale = state.scale or 16
      local cw    = canvas:width()
      local ch    = canvas:height()
      local maxX  = math.max(0, (state.mapData and state.mapData.mapW or 1) * scale - cw)
      local maxY  = math.max(0, (state.mapData and state.mapData.mapH or 1) * scale - ch)
      state.viewOffX = math.max(0, math.min(state.viewOffX, maxX))
      state.viewOffY = math.max(0, math.min(state.viewOffY, maxY))
      lastPanX, lastPanY = x, y
      if callbacks and callbacks.onRender then callbacks.onRender() end

    elseif isDragging and (state.tool == "paint" or state.tool == "erase") then
      applyTool(x, y, state, callbacks)
      if callbacks and callbacks.onRender then callbacks.onRender() end
    end
  end)

  canvas:onMouseRelease(function(_, _, _)
    isDragging = false
    isPanning  = false
  end)
end

return CanvasMap
