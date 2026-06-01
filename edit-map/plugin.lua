-- Edit Map — entry point for pokered (Gen 1) and pokecrystal (Gen 2).
--
-- PoryTools loads this file once and calls `run()` each time the user
-- clicks Plugins → Gen 1/2 → Edit Map.
--
-- Module layout:
--   edit_map/util.lua          — string / line helpers
--   edit_map/constants.lua     — loads sprite, music, map constants
--   edit_map/map_list.lua      — discovers maps by scanning project folders
--   edit_map/map_data.lua      — loads .blk binary + resolves dimensions
--   edit_map/map_render.lua    — renders block map onto a PluginCanvas
--   edit_map/gen1_header.lua   — parse / write data/mapHeaders/*.asm
--   edit_map/gen1_objects.lua  — parse / write data/mapObjects/*.asm
--   edit_map/gen2_header.lua   — parse / write data/maps/*.asm
--   edit_map/gen2_events.lua   — parse / write maps/*.asm
--   edit_map/ui.lua            — dockable 7-tab panel

local MapList   = require("edit_map.map_list")
local MapData   = require("edit_map.map_data")
local MapRender = require("edit_map.map_render")
local Constants = require("edit_map.constants")
local Gen1Hdr   = require("edit_map.gen1_header")
local Gen1Obj   = require("edit_map.gen1_objects")
local Gen2Hdr   = require("edit_map.gen2_header")
local Gen2Ev    = require("edit_map.gen2_events")
local UI        = require("edit_map.ui")

-- ---------------------------------------------------------------
-- Shared state
-- ---------------------------------------------------------------

local state = {
  projectRoot  = nil,
  isGen2       = false,

  maps         = {},      -- list of { id, name, headerPath, objectsPath, blkPath }
  currentMap   = nil,     -- selected map record
  parsedHeader = nil,     -- Gen1Header or Gen2Header parse result
  parsedEvents = nil,     -- Gen1Objects or Gen2Events parse result

  constants    = nil,
  ui           = nil,

  mapData      = nil,     -- { blocks, mapW, mapH, total } loaded by MapData
  mapScale     = nil,     -- current zoom in px/block (nil = auto)
  mapClickWired = false,  -- whether the canvas click handler has been registered
}

-- ---------------------------------------------------------------
-- Path helpers
-- ---------------------------------------------------------------

local function resolve(rel)
  if not state.projectRoot then return nil end
  local p = state.projectRoot .. "/" .. rel
  return pt.file.exists(p) and p or nil
end

-- ---------------------------------------------------------------
-- Generation detection
-- ---------------------------------------------------------------
-- Gen 2 (pokecrystal) keeps its event files under maps/ and has
-- a data/maps/ folder for headers.  Gen 1 uses data/mapObjects/
-- and data/mapHeaders/ (old layout) or data/maps/objects/ and
-- data/maps/headers/ (new pokered layout).
local function detectGen()
  local root = state.projectRoot
  -- Old Gen 1 (pokered): data/mapObjects/ has per-map .asm files.
  local gen1Files = pt.file.list(root .. "/data/mapObjects", { glob = "*.asm" })
  if gen1Files and #gen1Files > 0 then
    state.isGen2 = false
    return
  end
  -- New Gen 1 (pokered): data/maps/objects/ has per-map .asm files.
  local newGen1Files = pt.file.list(root .. "/data/maps/objects", { glob = "*.asm" })
  if newGen1Files and #newGen1Files > 0 then
    state.isGen2 = false
    return
  end
  -- Gen 2 (pokecrystal): maps/*.asm has per-map event+connection files.
  local gen2Files = pt.file.list(root .. "/maps", { glob = "*.asm" })
  state.isGen2 = (gen2Files ~= nil and #gen2Files > 0)
end

-- ---------------------------------------------------------------
-- Project setup
-- ---------------------------------------------------------------

local function locateDirs()
  -- For gen1, make sure at least one of the expected dirs exists.
  if not state.isGen2 then
    local objDir = resolve("data/mapObjects")
                or resolve("data/maps/objects")
    if not objDir then
      pt.ui.alert(
        "Could not find data/mapObjects/ or data/maps/objects/ in the project.\n" ..
        "Make sure you have a pokered project open.")
      return false
    end
  else
    local mapsDir = resolve("data/maps") or resolve("maps")
    if not mapsDir then
      pt.ui.alert(
        "Could not find data/maps/ or maps/ in the project.\n" ..
        "Make sure you have a pokecrystal project open.")
      return false
    end
  end
  return true
end

-- ---------------------------------------------------------------
-- Loading a map
-- ---------------------------------------------------------------

local function loadHeader(map)
  if not pt.file.exists(map.headerPath) then
    UI.setInfo(state.ui, map.name .. "  [header file not found]")
    return
  end

  if state.isGen2 then
    local parsed, err = Gen2Hdr.read(map.headerPath)
    if not parsed then
      pt.ui.notify("Header read error for " .. map.name .. ": " .. (err or ""))
      return
    end
    state.parsedHeader = parsed
    UI.fillHeader(state.ui, {
      tileset    = parsed.tileset,
      music      = parsed.music,
      mapConst   = parsed.mapConst,
      sceneConst = parsed.sceneConst,
      land       = parsed.land,
    })
  else
    local parsed, err = Gen1Hdr.read(map.headerPath)
    if not parsed then
      pt.ui.notify("Header read error for " .. map.name .. ": " .. (err or ""))
      return
    end
    state.parsedHeader = parsed
    UI.fillHeader(state.ui, {
      tileset   = parsed.tileset,
      height    = parsed.height,
      width     = parsed.width,
      connFlags = parsed.connFlags,
    })
  end
end

local function loadEvents(map)
  if not pt.file.exists(map.objectsPath) then
    UI.setWarpsText(state.ui, "; events file not found: " .. map.objectsPath)
    return
  end

  if state.isGen2 then
    local parsed, err = Gen2Ev.read(map.objectsPath)
    if not parsed then
      pt.ui.notify("Events read error for " .. map.name .. ": " .. (err or ""))
      return
    end
    state.parsedEvents = parsed
    UI.setWarpsText(state.ui,       Gen2Ev.warpsToText(parsed))
    UI.setNpcsText(state.ui,        Gen2Ev.peopleToText(parsed))
    UI.setSignsText(state.ui,       Gen2Ev.bgEventsToText(parsed),
                                    Gen2Ev.coordsToText(parsed))
    UI.setConnectionsText(state.ui, Gen2Ev.connectionsToText(parsed))
  else
    local parsed, err = Gen1Obj.read(map.objectsPath)
    if not parsed then
      pt.ui.notify("Objects read error for " .. map.name .. ": " .. (err or ""))
      return
    end
    state.parsedEvents = parsed
    UI.setWarpsText(state.ui,       Gen1Obj.warpsToText(parsed))
    UI.setNpcsText(state.ui,        Gen1Obj.peopleToText(parsed))
    UI.setSignsText(state.ui,       Gen1Obj.signsToText(parsed))

    -- Connections live in the header for gen1; show them there.
    local connLines = {}
    if state.parsedHeader then
      for _, dir in ipairs({"north","south","east","west"}) do
        local c = state.parsedHeader.connections[dir]
        if c then
          table.insert(connLines, string.format("%s %s %s %s",
            c.dir, c.destBlocks, c.destHeader, c.offset))
        end
      end
    end
    UI.setConnectionsText(state.ui, table.concat(connLines, "\n"))
  end
end

local renderMap  -- forward declaration (defined after save handlers)

local function loadMap(map)
  if not map then return end
  state.currentMap = map
  state.mapScale   = nil   -- reset zoom when switching maps
  UI.setInfo(state.ui, map.name .. "  (" .. map.id .. ")")
  loadHeader(map)
  loadEvents(map)
  renderMap()
end

-- ---------------------------------------------------------------
-- Map rendering
-- ---------------------------------------------------------------

local ZOOM_STEPS = { 4, 6, 8, 10, 12, 14, 16, 20, 24, 32 }

renderMap = function()
  local canvas = state.ui and state.ui.mapCanvas
  if not canvas then return end

  local map = state.currentMap
  if not map then
    canvas:clear(18, 18, 22)
    canvas:setPenColor(140, 140, 140)
    canvas:drawText(10, 28, "No map selected.", 13)
    canvas:update()
    UI.setMapDim(state.ui, "Select a map to render.")
    return
  end

  -- Build dimension hint from header data.
  local headerDims = nil
  if state.parsedHeader then
    headerDims = {
      width  = state.parsedHeader.width,
      height = state.parsedHeader.height,
    }
  end

  local data = MapData.load(map, headerDims, state.projectRoot)
  state.mapData = data

  if not data then
    canvas:clear(18, 18, 22)
    canvas:setPenColor(160, 100, 100)
    canvas:drawText(10, 28, "Block map not found.", 13)
    canvas:setPenColor(130, 130, 130)
    local tryPath = map.blkPath or (state.projectRoot .. "/maps/" .. map.id .. ".blk")
    canvas:drawText(10, 52, "Expected: " .. tryPath, 10)
    canvas:update()
    UI.setMapDim(state.ui, "No .blk file for: " .. map.id)
    return
  end

  -- Build event overlay from parsed events.
  local events = nil
  if state.parsedEvents then
    if state.isGen2 then
      events = {
        warps    = state.parsedEvents.warps,
        people   = state.parsedEvents.people,
        bgEvents = state.parsedEvents.bgEvents,
      }
    else
      events = {
        warps   = state.parsedEvents.warps,
        people  = state.parsedEvents.people,
        signs   = state.parsedEvents.signs,
      }
    end
  end

  local scale = MapRender.render(canvas, data, events, { scale = state.mapScale })
  state.mapScale = scale

  UI.setMapDim(state.ui, string.format(
    "%d\xc3\x97%d blocks \xe2\x80\x94 %dpx/block \xe2\x80\x94 %d bytes",
    data.mapW, data.mapH, scale, data.total))
  UI.setMapInfo(state.ui, "")

  -- Wire click handler for block info (only once per canvas instance).
  if not state.mapClickWired then
    state.mapClickWired = true
    canvas:onMousePress(function(x, y, btn)
      if btn ~= 1 or not state.mapData then return end
      local s  = state.mapScale or 1
      local bx = math.floor(x / s)
      local by = math.floor(y / s)
      local d  = state.mapData
      if bx < 0 or bx >= d.mapW or by < 0 or by >= d.mapH then return end
      local idx     = by * d.mapW + bx + 1
      local blockId = d.blocks[idx]
      if blockId then
        UI.setMapInfo(state.ui, string.format(
          "Block 0x%02X (%d) at block (%d,%d) \xe2\x80\x94 tile (%d,%d)",
          blockId, blockId, bx, by, bx * 2, by * 2))
      end
    end)
  end
end

-- ---------------------------------------------------------------
-- Save handlers
-- ---------------------------------------------------------------

local function saveHeader()
  local map = state.currentMap
  if not map then return end

  local edits = UI.readHeader(state.ui)

  if state.isGen2 then
    if not state.parsedHeader then
      pt.ui.alert("No header loaded for " .. map.name .. ".")
      return
    end
    local ok, err = Gen2Hdr.write(map.headerPath, state.parsedHeader, edits)
    if not ok then pt.ui.alert("Write failed: " .. (err or "")); return end
    pt.ui.notify("Saved header for " .. map.name)
    loadHeader(map)
  else
    if not state.parsedHeader then
      pt.ui.alert("No header loaded for " .. map.name .. ".")
      return
    end
    -- For gen1, connFlags lives in the header file. Keep the existing value
    -- unless the user explicitly changed it.
    local ok, err = Gen1Hdr.write(map.headerPath, state.parsedHeader, edits)
    if not ok then pt.ui.alert("Write failed: " .. (err or "")); return end
    pt.ui.notify("Saved header for " .. map.name)
    loadHeader(map)
  end
end

local function saveWarps(text)
  local map = state.currentMap
  if not map or not state.parsedEvents then return end

  local ok, err
  if state.isGen2 then
    ok, err = Gen2Ev.writeWarps(map.objectsPath, state.parsedEvents, text)
  else
    ok, err = Gen1Obj.writeWarps(map.objectsPath, state.parsedEvents, text)
  end
  if not ok then pt.ui.alert("Write failed: " .. (err or "")); return end
  pt.ui.notify("Saved warps for " .. map.name)
  loadEvents(map)
end

local function saveNpcs(text)
  local map = state.currentMap
  if not map or not state.parsedEvents then return end

  local ok, err
  if state.isGen2 then
    ok, err = Gen2Ev.writePeople(map.objectsPath, state.parsedEvents, text)
  else
    ok, err = Gen1Obj.writePeople(map.objectsPath, state.parsedEvents, text)
  end
  if not ok then pt.ui.alert("Write failed: " .. (err or "")); return end
  pt.ui.notify("Saved NPCs for " .. map.name)
  loadEvents(map)
end

-- Gen1: signsText only.  Gen2: bgText, coordText.
local function saveSigns(bgOrSignsText, coordText)
  local map = state.currentMap
  if not map or not state.parsedEvents then return end

  if state.isGen2 then
    local ok, err = Gen2Ev.writeBgEvents(map.objectsPath, state.parsedEvents, bgOrSignsText)
    if not ok then pt.ui.alert("Write failed (bg events): " .. (err or "")); return end
    -- Re-read before writing coords (the file changed).
    local fresh, rerr = Gen2Ev.read(map.objectsPath)
    if not fresh then pt.ui.alert("Re-read failed: " .. (rerr or "")); return end
    ok, err = Gen2Ev.writeCoords(map.objectsPath, fresh, coordText)
    if not ok then pt.ui.alert("Write failed (coord events): " .. (err or "")); return end
  else
    local ok, err = Gen1Obj.writeSigns(map.objectsPath, state.parsedEvents, bgOrSignsText)
    if not ok then pt.ui.alert("Write failed: " .. (err or "")); return end
  end
  pt.ui.notify("Saved signs/events for " .. map.name)
  loadEvents(map)
end

local function saveConnections(text)
  local map = state.currentMap
  if not map then return end

  if state.isGen2 then
    if not state.parsedEvents then return end
    local ok, err = Gen2Ev.writeConnections(map.objectsPath, state.parsedEvents, text)
    if not ok then pt.ui.alert("Write failed: " .. (err or "")); return end
    pt.ui.notify("Saved connections for " .. map.name)
    loadEvents(map)
  else
    -- Gen1: connections are in the header file.
    if not state.parsedHeader then return end

    -- Parse the connections text area into a connections edits table.
    -- Format: DIR DestBlocksLabel DestHeaderLabel offset
    local connEdits = {}
    local seen = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      local s = line:gsub("^%s+",""):gsub("%s+$","")
      if s ~= "" and not s:match("^;") then
        local t = {}
        for tok in s:gmatch("%S+") do table.insert(t, tok) end
        if #t >= 4 then
          local dir = t[1]:lower()
          if not seen[dir] then
            seen[dir] = true
            connEdits[dir] = {
              destBlocks = t[2],
              destHeader = t[3],
              offset     = t[4],
            }
          end
        elseif #t > 0 then
          pt.ui.alert(string.format(
            "Connection line needs 4 tokens (DIR DestBlocks DestHeader offset): '%s'", s))
          return
        end
      end
    end

    -- Mark removed directions as false.
    local DIRS = {"north","south","east","west"}
    for _, dir in ipairs(DIRS) do
      if state.parsedHeader.connections[dir] and not connEdits[dir] then
        connEdits[dir] = false
      end
    end

    local ok, err = Gen1Hdr.write(map.headerPath, state.parsedHeader, { connections = connEdits })
    if not ok then pt.ui.alert("Write failed: " .. (err or "")); return end
    pt.ui.notify("Saved connections for " .. map.name)
    -- Re-read header to update state.
    local fresh = Gen1Hdr.read(map.headerPath)
    if fresh then state.parsedHeader = fresh end
    -- Refresh connections display.
    local connLines = {}
    for _, dir in ipairs(DIRS) do
      local c = state.parsedHeader.connections[dir]
      if c then
        table.insert(connLines, string.format("%s %s %s %s",
          c.dir, c.destBlocks, c.destHeader, c.offset))
      end
    end
    UI.setConnectionsText(state.ui, table.concat(connLines, "\n"))
  end
end

-- ---------------------------------------------------------------
-- Reload map list
-- ---------------------------------------------------------------

local function reloadMapList()
  state.maps = MapList.scan(state.projectRoot, state.isGen2)
  if #state.maps == 0 then
    pt.ui.alert("No maps found in project.")
    return
  end
  state.ui.mapSel:setItems(MapList.names(state.maps))
  state.ui.mapSel:setCurrentIndex(1)
  loadMap(state.maps[1])
end

-- ---------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------

function run()
  if not pt.project.isOpen() then
    pt.ui.alert("No project is open.\n\nOpen a pokered or pokecrystal project first.")
    return
  end

  state.projectRoot = pt.project.root()
  detectGen()

  if not locateDirs() then return end

  state.constants = Constants.loadAll(state.projectRoot)

  state.maps = MapList.scan(state.projectRoot, state.isGen2)
  if #state.maps == 0 then
    pt.ui.alert("No maps found.\n\n" ..
      (state.isGen2 and "Expected maps/*.asm files." or "Expected data/mapObjects/*.asm files."))
    return
  end

  local genLabel = state.isGen2 and "Gen 2 (pokecrystal)" or "Gen 1 (pokered)"

  -- If the widget already exists, just show and reload it.
  if state.ui then
    UI.show(state.ui)
    state.ui.mapSel:setItems(MapList.names(state.maps))
    state.ui.mapSel:setCurrentIndex(1)
    loadMap(state.maps[1])
    return
  end

  state.ui = UI.create({
    isGen2   = state.isGen2,
    mapNames = MapList.names(state.maps),
    genLabel = genLabel,
  })

  -- Wire callbacks.
  state.ui.onSelectionChange = function(idx)
    local map = state.maps[idx]
    if map then loadMap(map) end
  end
  state.ui.onSaveHeader      = saveHeader
  state.ui.onSaveWarps       = saveWarps
  state.ui.onSaveNpcs        = saveNpcs
  state.ui.onSaveSigns       = saveSigns
  state.ui.onSaveConnections = saveConnections
  state.ui.onOpenEventsFile  = function()
    local map = state.currentMap
    if map and pt.file.exists(map.objectsPath) then
      pt.tabs.open(map.objectsPath)
    end
  end
  state.ui.onOpenHeaderFile  = function()
    local map = state.currentMap
    if map and pt.file.exists(map.headerPath) then
      pt.tabs.open(map.headerPath)
    end
  end
  state.ui.onReload = reloadMapList
  state.ui.onZoomIn = function()
    if not state.mapData then return end
    for _, s in ipairs(ZOOM_STEPS) do
      if s > (state.mapScale or 0) then
        state.mapScale = s
        renderMap()
        return
      end
    end
  end
  state.ui.onZoomOut = function()
    if not state.mapData then return end
    for i = #ZOOM_STEPS, 1, -1 do
      if ZOOM_STEPS[i] < (state.mapScale or 999) then
        state.mapScale = ZOOM_STEPS[i]
        renderMap()
        return
      end
    end
  end

  UI.show(state.ui)
  loadMap(state.maps[1])
end
