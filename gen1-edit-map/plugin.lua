-- Gen1 Edit Map — plugin.lua
-- Entry point.  All sub-modules are loaded lazily on first `run()` call.
-- The UI panel is created once and re-shown on subsequent calls.

local Util        = require("gen1_edit_map.util")
local Constants   = require("gen1_edit_map.constants")
local MapList     = require("gen1_edit_map.map_list")
local MapData     = require("gen1_edit_map.map_data")
local Header      = require("gen1_edit_map.header")
local Objects     = require("gen1_edit_map.objects")
local Blockset    = require("gen1_edit_map.blockset")
local TilesetGfx  = require("gen1_edit_map.tileset_gfx")
local SpriteGfx   = require("gen1_edit_map.sprite_gfx")
local CanvasMap   = require("gen1_edit_map.canvas_map")
local CanvasTiles = require("gen1_edit_map.canvas_tiles")
local UI          = require("gen1_edit_map.ui")

-- ---------------------------------------------------------------------------
-- Shared state
-- ---------------------------------------------------------------------------

local state = {
  root         = nil,
  maps         = {},
  currentMap   = nil,   -- map record from MapList.scan
  mapData      = nil,   -- from MapData.resolve
  parsedHdr    = nil,   -- from Header.parse
  parsedObj    = nil,   -- from Objects.parse
  constants    = nil,   -- from Constants.loadAll
  blockDefs    = nil,   -- from Blockset.load
  blockCache   = nil,   -- from TilesetGfx.buildCache
  spritePaths  = {},    -- from SpriteGfx.allSpritePaths
  tilesetName  = nil,
  scale        = 16,
  viewOffX     = 0,
  viewOffY     = 0,
  canvasW      = 770,
  canvasH      = 576,
  dirty        = false,
  tool         = "select",
  activeBlock  = 0,
  selectedBlock = nil,
  selectedEventIdx  = nil,
  selectedEventKind = nil,
  hoverBlock   = nil,
  ui           = nil,
}

-- Persistent panel (created once).
local panel_created = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function setStatus(msg)
  if state.ui and state.ui.statusLabel then
    state.ui.statusLabel:setText(msg or "")
  end
end

local function renderMap()
  if state.ui and state.ui.mapCanvas then
    CanvasMap.render(state.ui.mapCanvas, state)
  end
end

local function renderTiles()
  if state.ui and state.ui.tileCanvas then
    CanvasTiles.render(state.ui.tileCanvas, state)
  end
end

-- ---------------------------------------------------------------------------
-- Hover info canvas
-- ---------------------------------------------------------------------------

local INFO_W = 770
local INFO_H = 58

local function updateInfoCanvas(bx, by)
  local ic = state.ui and state.ui.infoCanvas
  if not ic then return end

  local bg_r, bg_g, bg_b = 22, 26, 34
  local border_r, border_g, border_b = 60, 70, 90

  ic:clear(bg_r, bg_g, bg_b)
  ic:setPenColor(border_r, border_g, border_b)
  ic:drawRect(0, 0, INFO_W, INFO_H)

  if not state.mapData then
    ic:setPenColor(90, 100, 120)
    ic:drawText(8, 14, "No map loaded.", 11)
    ic:update()
    return
  end

  local mapW = state.mapData.mapW or 1
  local mapH = state.mapData.mapH or 1

  if bx < 0 or by < 0 or bx >= mapW or by >= mapH then
    ic:setPenColor(90, 100, 120)
    ic:drawText(8, 14, "Hover over the map to inspect a block.", 11)
    ic:update()
    return
  end

  local idx     = by * mapW + bx + 1
  local blockId = state.mapData.blocks[idx] or 0

  -- Collect events at this block position (step coords = block * 2).
  local evLines = {}
  if state.parsedObj then
    local stepX = bx * 2
    local stepY = by * 2
    for _, w in ipairs(state.parsedObj.warps or {}) do
      if tonumber(w.x) == stepX and tonumber(w.y) == stepY then
        table.insert(evLines, string.format("Warp → %s (warp %s)", w.dest or "?", w.warpId or "?"))
      end
    end
    for _, b in ipairs(state.parsedObj.bgEvents or {}) do
      if tonumber(b.x) == stepX and tonumber(b.y) == stepY then
        table.insert(evLines, string.format("Sign: %s", b.script or "?"))
      end
    end
    for _, p in ipairs(state.parsedObj.people or {}) do
      if tonumber(p.x) == stepX and tonumber(p.y) == stepY then
        table.insert(evLines, string.format("NPC: %s  move=%s dir=%s", p.sprite or "?", p.movement or "?", p.dir or "?"))
      end
    end
  end

  -- Draw header line.
  ic:setPenColor(210, 220, 240)
  ic:drawText(8, 14, string.format("Block (%d, %d)   ID: %d", bx, by, blockId), 11)

  -- Draw event lines (up to 2).
  if #evLines == 0 then
    ic:setPenColor(110, 120, 140)
    ic:drawText(8, 32, "(no events at this position)", 10)
  else
    ic:setPenColor(160, 200, 160)
    for i = 1, math.min(2, #evLines) do
      ic:drawText(8, 14 + i * 18, evLines[i], 10)
    end
    if #evLines > 2 then
      ic:setPenColor(110, 120, 140)
      ic:drawText(8, 14 + 3 * 18, string.format("(+%d more)", #evLines - 2), 10)
    end
  end

  ic:update()
end
-- ---------------------------------------------------------------------------

local function loadBlockCache()
  if not state.root or not state.tilesetName then return end

  local blockDefs, blkPath, err = Blockset.loadForTileset(state.root, state.tilesetName)
  if not blockDefs then
    setStatus("Blockset not found: " .. (err or ""))
    state.blockDefs  = {}
    state.blockCache = {}
    return
  end
  state.blockDefs = blockDefs

  local cache, cacheErr = TilesetGfx.buildCache(
    state.ui.scratchCanvas,
    state.root,
    state.tilesetName,
    blockDefs
  )
  state.blockCache = cache or {}
  if cacheErr then
    setStatus("Tileset gfx warning: " .. cacheErr)
  end
end

local function loadMap(mapRecord)
  if not mapRecord then return end
  state.currentMap = mapRecord
  state.viewOffX   = 0
  state.viewOffY   = 0
  state.dirty      = false
  state.selectedBlock = nil
  state.selectedEventIdx  = nil

  -- 1. Parse header.
  local parsedHdr, hdrErr = Header.read(mapRecord.headerPath)
  if not parsedHdr then
    setStatus("Header error: " .. (hdrErr or ""))
    return
  end
  state.parsedHdr = parsedHdr

  -- Show map const label.
  if state.ui and state.ui.mapConstLabel then
    state.ui.mapConstLabel:setText(parsedHdr.mapConst or "")
  end

  -- 2. Parse objects.
  local parsedObj, objErr
  if pt.file.exists(mapRecord.objectsPath) then
    parsedObj, objErr = Objects.read(mapRecord.objectsPath)
  else
    -- Synthesise an empty objects record.
    parsedObj = { warps={}, bgEvents={}, people={}, border="$0", warpsTo=parsedHdr.mapConst or "" }
  end
  state.parsedObj = parsedObj

  -- 3. Load map blocks.
  local md = MapData.resolve(parsedHdr.mapConst, mapRecord.blkPath, state.constants)
  if not md then
    setStatus("Blocks not found: " .. (mapRecord.blkPath or ""))
    state.mapData = nil
  else
    state.mapData = md
  end

  -- 4. If tileset changed, rebuild block cache.
  local newTileset = parsedHdr.tileset or ""
  if newTileset ~= (state.tilesetName or "") then
    state.tilesetName = newTileset
    loadBlockCache()
  end

  -- 4b. Auto-fit scale so the map fills the canvas.
  if state.mapData then
    local canW = (state.ui and state.ui.mapCanvas) and state.ui.mapCanvas:width() or state.canvasW
    local canH = (state.ui and state.ui.mapCanvas) and state.ui.mapCanvas:height() or state.canvasH
    local fitW = math.floor(canW / math.max(1, state.mapData.mapW))
    local fitH = math.floor(canH / math.max(1, state.mapData.mapH))
    state.scale = math.max(4, math.min(32, math.min(fitW, fitH)))
    state.viewOffX = 0
    state.viewOffY = 0
    if state.ui and state.ui.zoomLabel then
      state.ui.zoomLabel:setText(state.scale .. "px")
    end
  end

  -- 5. Update sprite paths.
  state.spritePaths = SpriteGfx.allSpritePaths(
    state.constants and state.constants.sprites or {}, state.root)

  -- 6. Populate UI fields.
  UI.fillHeader(state.ui, parsedHdr)
  UI.fillEvents(state.ui, parsedObj)
  if state.constants and state.constants.sprites then
    UI.fillSpriteOptions(state.ui, state.constants.sprites)
  end

  -- 7. Render.
  renderMap()
  renderTiles()

  if state.mapData then
    setStatus(string.format("Loaded %s (%d×%d blocks).",
      mapRecord.name, state.mapData.mapW, state.mapData.mapH))
  else
    setStatus("Loaded " .. mapRecord.name .. " (no block data).")
  end
end

-- ---------------------------------------------------------------------------
-- Save pipeline
-- ---------------------------------------------------------------------------

local function saveCurrentMap()
  if not state.currentMap then return end
  if not state.dirty then
    setStatus("No unsaved changes.")
    return
  end

  local ok, err

  -- Write header if we have parsed data.
  if state.parsedHdr then
    -- Collect edits from UI.
    local edits = {
      tileset   = state.ui.tilesetEdit:text(),
      connFlags = state.ui.connFlagsEdit:text(),
    }
    ok, err = Header.write(state.currentMap.headerPath, state.parsedHdr, edits)
    if not ok then
      pt.ui.alert("Failed to save header: " .. (err or ""))
      return
    end
    -- Re-parse after write.
    state.parsedHdr = Header.read(state.currentMap.headerPath)
  end

  -- Write objects if we have parsed data.
  if state.parsedObj then
    ok, err = Objects.write(state.currentMap.objectsPath, state.parsedObj)
    if not ok then
      pt.ui.alert("Failed to save objects: " .. (err or ""))
      return
    end
    state.parsedObj = Objects.read(state.currentMap.objectsPath)
  end

  -- Write .blk blocks.
  if state.mapData and state.mapData.blocks then
    ok, err = MapData.writeBlk(state.currentMap.blkPath, state.mapData.blocks)
    if not ok then
      pt.ui.alert("Failed to save blocks: " .. (err or ""))
      return
    end
  end

  state.dirty = false
  setStatus("Saved " .. state.currentMap.name)
end

-- ---------------------------------------------------------------------------
-- Event helpers
-- ---------------------------------------------------------------------------

-- Return the currently selected event item from the events list.
local function getSelectedEventItem()
  if not state.parsedObj then return nil end
  local sel = state.ui.eventListSel
  if not sel then return nil end
  local items = Objects.eventList(state.parsedObj)
  local idx = state.selectedEventIdx
  if not idx or idx < 1 or idx > #items then return nil end
  return items[idx]
end

-- Read property fields and write them back into parsedObj.
local function applyEventEdits()
  local item = getSelectedEventItem()
  if not item then return end
  local d   = item.data
  local ep  = state.ui.eventProps

  d.x = ep.xEdit and ep.xEdit:text() or d.x
  d.y = ep.yEdit and ep.yEdit:text() or d.y
  d.script = ep.scriptEdit and ep.scriptEdit:text() or (d.script or "")

  if item.kind == "warp" then
    d.dest   = ep.destEdit   and ep.destEdit:text()   or d.dest
    d.warpId = ep.warpIdEdit and ep.warpIdEdit:text() or d.warpId

  elseif item.kind == "npc" then
    d.sprite   = ep.spriteSel and ep.spriteSel:currentText() or d.sprite
    d.movement = ep.movEdit   and ep.movEdit:text()        or d.movement
    d.dir      = ep.dirEdit   and ep.dirEdit:text()        or d.dir
  end

  state.dirty = true
  UI.fillEvents(state.ui, state.parsedObj)
  renderMap()
end

-- Remove the currently selected event.
local function removeSelectedEvent()
  local item = getSelectedEventItem()
  if not item then return end

  if item.kind == "warp" then
    table.remove(state.parsedObj.warps, item.index)
  elseif item.kind == "bg" then
    table.remove(state.parsedObj.bgEvents, item.index)
  elseif item.kind == "npc" then
    table.remove(state.parsedObj.people, item.index)
  end

  state.selectedEventIdx  = nil
  state.dirty = true
  UI.fillEvents(state.ui, state.parsedObj)
  renderMap()
end

-- ---------------------------------------------------------------------------
-- run() — entry point
-- ---------------------------------------------------------------------------

function run()
  if not pt.project.isOpen() then
    pt.ui.alert("Please open a pokered project first.")
    return
  end

  state.root = pt.project.root()

  -- Re-show existing panel if already built.
  if state.ui then
    state.ui.panel:show()
    return
  end

  -- Load constants (project-level, done once).
  state.constants = Constants.loadAll(state.root)
  state.maps      = MapList.scan(state.root)

  -- Build UI callbacks table.
  local callbacks = {

    onSave = function() saveCurrentMap() end,

    onReload = function()
      if state.currentMap then
        loadMap(state.currentMap)
      end
    end,

    onZoomIn = function()
      local old = state.scale
      state.scale = math.min(state.scale + 4, 32)
      state.viewOffX = math.floor(state.viewOffX * state.scale / old)
      state.viewOffY = math.floor(state.viewOffY * state.scale / old)
      if state.ui and state.ui.zoomLabel then
        state.ui.zoomLabel:setText(state.scale .. "px")
      end
      renderMap()
    end,

    onZoomOut = function()
      local old = state.scale
      state.scale = math.max(state.scale - 4, 8)
      state.viewOffX = math.floor(state.viewOffX * state.scale / old)
      state.viewOffY = math.floor(state.viewOffY * state.scale / old)
      if state.ui and state.ui.zoomLabel then
        state.ui.zoomLabel:setText(state.scale .. "px")
      end
      renderMap()
    end,

    onApplyHeader = function()
      if not state.parsedHdr then return end
      -- Collect edits.
      local newTileset = state.ui.tilesetEdit:text()
      local edits = {
        tileset   = newTileset,
        connFlags = state.ui.connFlagsEdit:text(),
      }
      -- Apply to in-memory header.
      state.parsedHdr.tileset   = edits.tileset
      state.parsedHdr.connFlags = edits.connFlags
      -- Rebuild blockCache if tileset changed.
      if newTileset ~= state.tilesetName then
        state.tilesetName = newTileset
        loadBlockCache()
        renderTiles()
      end
      state.dirty = true
      renderMap()
      setStatus("Header changes staged (not yet saved).")
    end,

    onApplyConnections = function()
      -- Parse connections textarea lines.
      if not state.parsedHdr then return end
      local text = state.ui.connectionsArea2 and state.ui.connectionsArea2:text() or ""
      local newConns = {}
      for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local parts = {}
        for p in raw:gmatch("([^,]+)") do
          table.insert(parts, Util.trim(p))
        end
        if #parts >= 4 then
          local dir = parts[1]:lower()
          newConns[dir] = {
            dir = dir, dest = parts[2], destConst = parts[3], offset = parts[4]
          }
        end
      end
      -- Reset and replace.
      state.parsedHdr.connections = newConns
      state.dirty = true
      setStatus("Connections updated (not yet saved).")
    end,

    onApplyEvent = function()
      applyEventEdits()
    end,

    onRemoveEvent = function()
      removeSelectedEvent()
    end,

    onOpenHeader = function()
      if state.currentMap then
        pt.editor.open(state.currentMap.headerPath)
      end
    end,

    onOpenObjects = function()
      if state.currentMap then
        pt.editor.open(state.currentMap.objectsPath)
      end
    end,

    onOpenBlk = function()
      if state.currentMap then
        pt.editor.open(state.currentMap.blkPath)
      end
    end,

    onRender = function()
      renderMap()
    end,

    onBlockPaint = function(bx, by, blockId)
      -- Optional per-paint-stroke hook (update coord label etc.)
      if state.ui and state.ui.coordLabel then
        state.ui.coordLabel:setText(string.format("Block: %d,%d", bx, by))
      end
    end,

    onBlockSelect = function(bx, by)
      if not state.mapData then return end
      local idx = by * state.mapData.mapW + bx + 1
      local id  = state.mapData.blocks[idx] or 0
      if state.ui and state.ui.blockLabel then
        state.ui.blockLabel:setText(string.format("ID: %d", id))
      end
      if state.ui and state.ui.coordLabel then
        state.ui.coordLabel:setText(string.format("Block: %d,%d", bx, by))
      end
    end,

    onHover = function(bx, by, mx, my)
      if state.ui and state.ui.coordLabel then
        state.ui.coordLabel:setText(string.format("Block: %d,%d", bx, by))
      end
      updateInfoCanvas(bx, by)
    end,

    onEventsChanged = function()
      state.tool = "select"
      UI.fillEvents(state.ui, state.parsedObj)
      renderMap()
    end,
  }

  -- Create UI.
  state.ui = UI.create(state, callbacks)

  -- Wire map canvas mouse events.
  CanvasMap.init(state.ui.mapCanvas, state, callbacks)

  -- Wire tile canvas click → select active block.
  CanvasTiles.init(state.ui.tileCanvas, state, function(blockId)
    state.activeBlock = blockId
    if state.ui.activeBlockLbl then
      state.ui.activeBlockLbl:setText("Active block: " .. blockId)
    end
    renderTiles()
  end)

  -- Populate map selector.
  local mapNames = MapList.names(state.maps)
  state.ui.mapSel:setItems(mapNames)

  -- Wire map selection change.
  state.ui.mapSel:onChange(function(selectedName)
    local mapRecord = MapList.findByName(state.maps, selectedName)
    if mapRecord then
      loadMap(mapRecord)
    end
  end)

  -- Wire events list selection.
  if state.ui.eventListSel then
    state.ui.eventListSel:onChange(function(selectedLabel)
      if not state.parsedObj then return end
      local items = Objects.eventList(state.parsedObj)
      for i, item in ipairs(items) do
        if item.label == selectedLabel then
          state.selectedEventIdx = i
          UI.fillEventProps(state.ui, item)
          break
        end
      end
    end)
  end

  -- Show panel.
  state.ui.panel:show()

  -- Auto-load first map if any.
  if #state.maps > 0 then
    state.ui.mapSel:setCurrentText(state.maps[1].name)
    loadMap(state.maps[1])
  else
    setStatus("No maps found. Is this a pokered project?")
  end
end
