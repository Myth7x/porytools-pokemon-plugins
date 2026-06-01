-- gen1_edit_map/ui.lua
-- Full UI layout for the Gen1 map editor.
--
-- Widget: 820 × 740 px  (dockable)
--
-- ┌── HEADER (y=8) ─────────────────────────────────────────────────────────┐
-- │  "Map:"  [dropdown 480px]   [Save]  [Reload]  [map-const label]         │
-- ├── LEFT PANEL (x=0, w=268) ──── RIGHT PANEL (x=273, w=540) ─────────────┤
-- │  Tool row  (y=46)           │  Map canvas  (y=46, 540×560)              │
-- │  Tab buttons (y=80)         │                                           │
-- │  Tab content (y=106, h=550) │  Status bar  (y=612, h=28)               │
-- └─────────────────────────────┴───────────────────────────────────────────┘
--
-- Left panel tabs: Header | Events | Connections | Scripts | Blocks
--
-- Public API:
--   UI.create(state, callbacks) → ui
--
-- `ui` fields:
--   panel, mapSel, statusLabel, coordLabel, blockLabel
--   headerTab, eventsTab, connectionsTab, scriptsTab, blocksTab
--   tilesetEdit, connFlagsEdit, connectionsArea
--   eventTypeSel, eventListSel, eventProps
--   mapCanvas, tileCanvas, scratchCanvas

local Objects = require("gen1_edit_map.objects")

local UI = {}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local TOOL_NAMES = { "Select", "Paint", "Erase", "Add Warp", "Add NPC", "Add Sign" }
local TOOL_KEYS  = { "select", "paint", "erase", "add_warp", "add_npc", "add_sign" }
local TAB_NAMES  = { "Header", "Events", "Connections", "Scripts", "Blocks" }

local CANVAS_X = 275
local CANVAS_Y = 46
local CANVAS_W = 770
local CANVAS_H = 576

local PANEL_W  = 1060
local PANEL_H  = 720
local INFO_H   = 58   -- height of hover-info bar below the map canvas

local SCRATCH_SIZE = 128  -- px; tileset PNGs are 128px wide

-- ---------------------------------------------------------------------------
-- Section visibility helpers (move off-screen to hide, restore to show)
-- ---------------------------------------------------------------------------
local function showSection(widgets, visible)
  for _, w in ipairs(widgets) do
    if visible then
      w.widget:setPosition(w.x, w.y)
    else
      w.widget:setPosition(-9999, -9999)
    end
  end
end

-- ---------------------------------------------------------------------------
-- UI creation
-- ---------------------------------------------------------------------------

function UI.create(state, callbacks)
  callbacks = callbacks or {}

  local panel = pt.ui.createWidget("Gen1 Edit Map")
  panel:setSize(PANEL_W, PANEL_H)

  local ui = {
    panel        = panel,
    mapSel       = nil,
    statusLabel  = nil,
    coordLabel   = nil,
    blockLabel   = nil,
    toolButtons  = {},
    tabSections  = {},  -- { header={widgets}, events=..., ... }
    -- Header tab
    tilesetEdit      = nil,
    connFlagsEdit    = nil,
    connectionsArea  = nil,
    -- Events tab
    eventTypeSel  = nil,
    eventListSel  = nil,
    eventProps    = {},   -- { kindLabel, xEdit, yEdit, ... }
    -- Canvases
    mapCanvas     = nil,
    tileCanvas    = nil,
    scratchCanvas = nil,
  }

  -- ─── HEADER ROW ─────────────────────────────────────────────────────────
  local mapLabel = panel:addLabel("Map:")
  mapLabel:setPosition(8, 14)
  mapLabel:setSize(40, 20)

  local mapSel = panel:addSelection("Select a map")
  mapSel:setPosition(52, 10)
  mapSel:setSize(698, 26)
  ui.mapSel = mapSel

  local saveBtn = panel:addButton("Save")
  saveBtn:setPosition(758, 10)
  saveBtn:setSize(70, 26)
  saveBtn:onClick(function()
    if callbacks.onSave then callbacks.onSave() end
  end)
  ui.saveBtn = saveBtn

  local reloadBtn = panel:addButton("Reload")
  reloadBtn:setPosition(836, 10)
  reloadBtn:setSize(76, 26)
  reloadBtn:onClick(function()
    if callbacks.onReload then callbacks.onReload() end
  end)
  ui.reloadBtn = reloadBtn

  local mapConstLabel = panel:addLabel("")
  mapConstLabel:setPosition(920, 14)
  mapConstLabel:setSize(135, 20)
  ui.mapConstLabel = mapConstLabel

  -- ─── TOOL BUTTONS ───────────────────────────────────────────────────────
  local toolBtnW = 42
  local toolBtnH = 24
  for i, name in ipairs(TOOL_NAMES) do
    local btn = panel:addButton(name)
    btn:setPosition((i - 1) * (toolBtnW + 2), 44)
    btn:setSize(toolBtnW, toolBtnH)
    local key = TOOL_KEYS[i]
    btn:onClick(function()
      state.tool = key
      ui.statusLabel:setText("Tool: " .. name)
    end)
    table.insert(ui.toolButtons, btn)
  end

  -- ─── TAB BUTTONS ────────────────────────────────────────────────────────
  local tabBtnW = 50
  local activeTab = "header"

  local tabBtns = {}

  local function showTab(tabKey)
    activeTab = tabKey
    for tKey, section in pairs(ui.tabSections) do
      showSection(section, tKey == tabKey)
    end
  end

  for i, name in ipairs(TAB_NAMES) do
    local btn = panel:addButton(name)
    btn:setPosition((i - 1) * (tabBtnW + 2), 73)
    btn:setSize(tabBtnW, 22)
    local key = name:lower()
    btn:onClick(function() showTab(key) end)
    table.insert(tabBtns, btn)
  end
  ui.tabBtns = tabBtns

  -- ─── LEFT PANEL CONTENT ─────────────────────────────────────────────────
  -- Content area starts at y=100, height ~610, width ~268.
  local contentX = 0
  local contentY = 100
  local contentW = 268

  -- ··· HEADER TAB ···
  do
    local section = {}

    local function reg(widget, x, y)
      table.insert(section, { widget = widget, x = x, y = y })
    end

    local lbl1 = panel:addLabel("")
    lbl1:setText("Tileset:")
    lbl1:setPosition(contentX + 4, contentY)
    lbl1:setSize(60, 20)
    reg(lbl1, contentX + 4, contentY)

    local tilesetEdit = panel:addLineEdit()
    tilesetEdit:setPosition(contentX + 70, contentY)
    tilesetEdit:setSize(190, 24)
    reg(tilesetEdit, contentX + 70, contentY)
    ui.tilesetEdit = tilesetEdit

    local lbl2 = panel:addLabel("")
    lbl2:setText("Conn flags:")
    lbl2:setPosition(contentX + 4, contentY + 30)
    lbl2:setSize(65, 20)
    reg(lbl2, contentX + 4, contentY + 30)

    local connFlagsEdit = panel:addLineEdit()
    connFlagsEdit:setPosition(contentX + 72, contentY + 30)
    connFlagsEdit:setSize(188, 24)
    reg(connFlagsEdit, contentX + 72, contentY + 30)
    ui.connFlagsEdit = connFlagsEdit

    local lbl3 = panel:addLabel("")
    lbl3:setText("Connections (dir, dest, const, offset — one per line):")
    lbl3:setPosition(contentX + 4, contentY + 60)
    lbl3:setSize(260, 20)
    reg(lbl3, contentX + 4, contentY + 60)

    local connectionsArea = panel:addTextArea("")
    connectionsArea:setPosition(contentX + 4, contentY + 82)
    connectionsArea:setSize(260, 200)
    reg(connectionsArea, contentX + 4, contentY + 82)
    ui.connectionsArea = connectionsArea

    local applyHdrBtn = panel:addButton("")
    applyHdrBtn:setText("Apply Header Changes")
    applyHdrBtn:setPosition(contentX + 4, contentY + 290)
    applyHdrBtn:setSize(260, 26)
    applyHdrBtn:onClick(function()
      if callbacks.onApplyHeader then callbacks.onApplyHeader() end
    end)
    reg(applyHdrBtn, contentX + 4, contentY + 290)

    ui.tabSections["header"] = section
  end

  -- ··· EVENTS TAB ···
  do
    local section = {}
    local function reg(widget, x, y)
      table.insert(section, { widget = widget, x = x, y = y })
    end

    local lbl = panel:addLabel("")
    lbl:setText("Event type:")
    lbl:setPosition(contentX + 4, contentY)
    lbl:setSize(80, 20)
    reg(lbl, contentX + 4, contentY)

    local typeSel = panel:addSelection()
    typeSel:setItems({"All", "Warps", "Signs", "NPCs"})
    typeSel:setPosition(contentX + 86, contentY)
    typeSel:setSize(176, 24)
    reg(typeSel, contentX + 86, contentY)
    ui.eventTypeSel = typeSel

    local listLbl = panel:addLabel("")
    listLbl:setText("Events:")
    listLbl:setPosition(contentX + 4, contentY + 30)
    listLbl:setSize(260, 20)
    reg(listLbl, contentX + 4, contentY + 30)

    local eventListSel = panel:addSelection()
    eventListSel:setPosition(contentX + 4, contentY + 50)
    eventListSel:setSize(260, 26)
    reg(eventListSel, contentX + 4, contentY + 50)
    ui.eventListSel = eventListSel

    -- Property form (shows fields for the selected event).
    local propY = contentY + 82

    local function mkPropRow(label, defVal, y)
      local lbl = panel:addLabel("")
      lbl:setText(label)
      lbl:setPosition(contentX + 4, y)
      lbl:setSize(64, 20)
      reg(lbl, contentX + 4, y)

      local edit = panel:addLineEdit()
      edit:setText(defVal or "")
      edit:setPosition(contentX + 70, y)
      edit:setSize(192, 22)
      reg(edit, contentX + 70, y)

      return lbl, edit
    end

    local _, xEdit = mkPropRow("X:",  "0",  propY)
    local _, yEdit = mkPropRow("Y:",  "0",  propY + 28)
    ui.eventProps.xEdit = xEdit
    ui.eventProps.yEdit = yEdit

    -- Warp-specific
    local _, destEdit   = mkPropRow("Dest:",   "",  propY + 56)
    local _, warpIdEdit = mkPropRow("Warp ID:", "1", propY + 84)
    ui.eventProps.destEdit   = destEdit
    ui.eventProps.warpIdEdit = warpIdEdit

    -- NPC-specific
    local spriteLbl = panel:addLabel("")
    spriteLbl:setText("Sprite:")
    spriteLbl:setPosition(contentX + 4, propY + 112)
    spriteLbl:setSize(64, 20)
    reg(spriteLbl, contentX + 4, propY + 112)

    local spriteSel = panel:addSelection()
    spriteSel:setPosition(contentX + 70, propY + 112)
    spriteSel:setSize(192, 24)
    reg(spriteSel, contentX + 70, propY + 112)
    ui.eventProps.spriteSel = spriteSel

    local _, movEdit = mkPropRow("Move:",   "STAY",  propY + 140)
    local _, dirEdit  = mkPropRow("Dir:",    "NONE",  propY + 168)
    ui.eventProps.movEdit = movEdit
    ui.eventProps.dirEdit = dirEdit

    -- Shared
    local _, scriptEdit = mkPropRow("Script:", "", propY + 196)
    ui.eventProps.scriptEdit = scriptEdit

    -- Apply button
    local applyBtn = panel:addButton("")
    applyBtn:setText("Apply Event")
    applyBtn:setPosition(contentX + 4, propY + 224)
    applyBtn:setSize(120, 24)
    applyBtn:onClick(function()
      if callbacks.onApplyEvent then callbacks.onApplyEvent() end
    end)
    reg(applyBtn, contentX + 4, propY + 224)

    -- Remove button
    local removeBtn = panel:addButton("")
    removeBtn:setText("Remove")
    removeBtn:setPosition(contentX + 132, propY + 224)
    removeBtn:setSize(80, 24)
    removeBtn:onClick(function()
      if callbacks.onRemoveEvent then callbacks.onRemoveEvent() end
    end)
    reg(removeBtn, contentX + 132, propY + 224)

    -- Add buttons row
    local addWarpBtn = panel:addButton("")
    addWarpBtn:setText("+Warp")
    addWarpBtn:setPosition(contentX + 4, propY + 256)
    addWarpBtn:setSize(78, 22)
    addWarpBtn:onClick(function()
      state.tool = "add_warp"
      ui.statusLabel:setText("Click map to place warp.")
    end)
    reg(addWarpBtn, contentX + 4, propY + 256)

    local addNpcBtn = panel:addButton("")
    addNpcBtn:setText("+NPC")
    addNpcBtn:setPosition(contentX + 88, propY + 256)
    addNpcBtn:setSize(78, 22)
    addNpcBtn:onClick(function()
      state.tool = "add_npc"
      ui.statusLabel:setText("Click map to place NPC.")
    end)
    reg(addNpcBtn, contentX + 88, propY + 256)

    local addSignBtn = panel:addButton("")
    addSignBtn:setText("+Sign")
    addSignBtn:setPosition(contentX + 174, propY + 256)
    addSignBtn:setSize(78, 22)
    addSignBtn:onClick(function()
      state.tool = "add_sign"
      ui.statusLabel:setText("Click map to place sign.")
    end)
    reg(addSignBtn, contentX + 174, propY + 256)

    ui.tabSections["events"] = section
  end

  -- ··· CONNECTIONS TAB ···
  do
    local section = {}
    local function reg(widget, x, y)
      table.insert(section, { widget = widget, x = x, y = y })
    end

    local lbl = panel:addLabel("")
    lbl:setText("Connections (dir, dest, const, offset — one per line):")
    lbl:setPosition(contentX + 4, contentY)
    lbl:setSize(260, 36)
    reg(lbl, contentX + 4, contentY)

    local area = panel:addTextArea("")
    area:setPosition(contentX + 4, contentY + 40)
    area:setSize(260, 220)
    reg(area, contentX + 4, contentY + 40)
    ui.connectionsArea2 = area

    local applyBtn = panel:addButton("")
    applyBtn:setText("Apply Connections")
    applyBtn:setPosition(contentX + 4, contentY + 268)
    applyBtn:setSize(260, 26)
    applyBtn:onClick(function()
      if callbacks.onApplyConnections then callbacks.onApplyConnections() end
    end)
    reg(applyBtn, contentX + 4, contentY + 268)

    ui.tabSections["connections"] = section
  end

  -- ··· SCRIPTS TAB ···
  do
    local section = {}
    local function reg(widget, x, y)
      table.insert(section, { widget = widget, x = x, y = y })
    end

    local lbl = panel:addLabel("")
    lbl:setText("Open source files for the current map:")
    lbl:setPosition(contentX + 4, contentY)
    lbl:setSize(260, 30)
    reg(lbl, contentX + 4, contentY)

    local openHdrBtn = panel:addButton("")
    openHdrBtn:setText("Open Header (.asm)")
    openHdrBtn:setPosition(contentX + 4, contentY + 36)
    openHdrBtn:setSize(260, 26)
    openHdrBtn:onClick(function()
      if callbacks.onOpenHeader then callbacks.onOpenHeader() end
    end)
    reg(openHdrBtn, contentX + 4, contentY + 36)

    local openObjBtn = panel:addButton("")
    openObjBtn:setText("Open Objects (.asm)")
    openObjBtn:setPosition(contentX + 4, contentY + 70)
    openObjBtn:setSize(260, 26)
    openObjBtn:onClick(function()
      if callbacks.onOpenObjects then callbacks.onOpenObjects() end
    end)
    reg(openObjBtn, contentX + 4, contentY + 70)

    local openBlkBtn = panel:addButton("")
    openBlkBtn:setText("Open Blocks (.blk)")
    openBlkBtn:setPosition(contentX + 4, contentY + 104)
    openBlkBtn:setSize(260, 26)
    openBlkBtn:onClick(function()
      if callbacks.onOpenBlk then callbacks.onOpenBlk() end
    end)
    reg(openBlkBtn, contentX + 4, contentY + 104)

    ui.tabSections["scripts"] = section
  end

  -- ··· BLOCKS TAB ···
  do
    local section = {}
    local function reg(widget, x, y)
      table.insert(section, { widget = widget, x = x, y = y })
    end

    local hint = panel:addLabel("")
    hint:setText("Click a block to select it for painting.")
    hint:setPosition(contentX + 4, contentY)
    hint:setSize(260, 20)
    reg(hint, contentX + 4, contentY)
    ui.blocksTabHint = hint

    local activeBlockLbl = panel:addLabel("")
    activeBlockLbl:setText("Active block: 0")
    activeBlockLbl:setPosition(contentX + 4, contentY + 22)
    activeBlockLbl:setSize(260, 20)
    reg(activeBlockLbl, contentX + 4, contentY + 22)
    ui.activeBlockLbl = activeBlockLbl

    -- Tile canvas will be added below and positioned here.
    -- We record the target position and size; actual creation is below.
    ui.tileCanvasX = contentX + 4
    ui.tileCanvasY = contentY + 46

    ui.tabSections["blocks"] = section
  end

  -- ─── MAP CANVAS ─────────────────────────────────────────────────────────
  local mapCanvas = panel:addCanvas(CANVAS_W, CANVAS_H)
  mapCanvas:setPosition(CANVAS_X, CANVAS_Y)
  ui.mapCanvas = mapCanvas

  -- ─── TILE PICKER CANVAS (in Blocks tab) ─────────────────────────────────
  local tileCanvas = panel:addCanvas(240, 160)
  tileCanvas:setPosition(ui.tileCanvasX, ui.tileCanvasY)
  -- Register it in the blocks section so it hides/shows with the tab.
  table.insert(ui.tabSections["blocks"], {
    widget = tileCanvas, x = ui.tileCanvasX, y = ui.tileCanvasY
  })
  ui.tileCanvas = tileCanvas

  -- ─── SCRATCH CANVAS (off-screen for pixel reading) ────────────────────
  local scratchCanvas = panel:addCanvas(SCRATCH_SIZE, SCRATCH_SIZE)
  scratchCanvas:setPosition(-9999, -9999)
  ui.scratchCanvas = scratchCanvas

  -- Store canvas origin so plugin.lua can compute panel-absolute tooltip coords.
  ui.canvasX = CANVAS_X
  ui.canvasY = CANVAS_Y

  -- ─── STATUS BAR (right panel, below map canvas) ──────────────────────
  local statusY = CANVAS_Y + CANVAS_H + 4

  local zoomOutBtn = panel:addButton("")
  zoomOutBtn:setText("-")
  zoomOutBtn:setPosition(CANVAS_X, statusY)
  zoomOutBtn:setSize(24, 24)
  zoomOutBtn:onClick(function()
    if callbacks.onZoomOut then callbacks.onZoomOut() end
  end)

  local zoomLabel = panel:addLabel("")
  zoomLabel:setText("16px")
  zoomLabel:setPosition(CANVAS_X + 28, statusY + 4)
  zoomLabel:setSize(40, 18)
  ui.zoomLabel = zoomLabel

  local zoomInBtn = panel:addButton("")
  zoomInBtn:setText("+")
  zoomInBtn:setPosition(CANVAS_X + 72, statusY)
  zoomInBtn:setSize(24, 24)
  zoomInBtn:onClick(function()
    if callbacks.onZoomIn then callbacks.onZoomIn() end
  end)

  local coordLabel = panel:addLabel("")
  coordLabel:setText("Block: –,–")
  coordLabel:setPosition(CANVAS_X + 102, statusY + 4)
  coordLabel:setSize(130, 18)
  ui.coordLabel = coordLabel

  local blockLabel = panel:addLabel("")
  blockLabel:setText("ID: –")
  blockLabel:setPosition(CANVAS_X + 238, statusY + 4)
  blockLabel:setSize(80, 18)
  ui.blockLabel = blockLabel

  local statusLabel = panel:addLabel("")
  statusLabel:setText("Open a map to begin.")
  statusLabel:setPosition(CANVAS_X + 324, statusY + 4)
  statusLabel:setSize(440, 18)
  ui.statusLabel = statusLabel

  -- ─── HOVER INFO CANVAS (below status bar) ────────────────────────────
  local infoCanvas = panel:addCanvas(CANVAS_W, INFO_H)
  infoCanvas:setPosition(CANVAS_X, statusY + 30)
  -- Seed with placeholder content.
  infoCanvas:clear(22, 26, 34)
  infoCanvas:setPenColor(60, 70, 90)
  infoCanvas:drawRect(0, 0, CANVAS_W, INFO_H)
  infoCanvas:setPenColor(90, 100, 120)
  infoCanvas:drawText(8, 14, "Hover over the map to inspect a block.", 11)
  infoCanvas:update()
  ui.infoCanvas = infoCanvas

  -- ─── INITIAL STATE: show header tab, hide others ──────────────────────
  for tKey, section in pairs(ui.tabSections) do
    showSection(section, tKey == "header")
  end

  -- mapSel onChange wired externally by plugin.lua.

  return ui
end

-- ---------------------------------------------------------------------------
-- Helpers the plugin calls to populate fields from parsed data
-- ---------------------------------------------------------------------------

-- Populate the Header tab from a parsed header record.
function UI.fillHeader(ui, parsedHdr)
  if not parsedHdr then return end
  ui.tilesetEdit:setText(parsedHdr.tileset or "")
  ui.connFlagsEdit:setText(parsedHdr.connFlags or "0")

  -- Connections area: one per line as "dir dest destConst offset"
  local lines = {}
  for _, dir in ipairs({"north","south","east","west"}) do
    local c = parsedHdr.connections and parsedHdr.connections[dir]
    if c then
      table.insert(lines, string.format("%s, %s, %s, %s",
        c.dir, c.dest, c.destConst, c.offset))
    end
  end
  if ui.connectionsArea then
    ui.connectionsArea:setText(table.concat(lines, "\n"))
  end
  if ui.connectionsArea2 then
    ui.connectionsArea2:setText(table.concat(lines, "\n"))
  end
end

-- Populate the Events list from a parsed objects record.
function UI.fillEvents(ui, parsedObj, filterKind)
  if not parsedObj then return end
  local items = Objects.eventList(parsedObj)
  local labels = {}
  for _, item in ipairs(items) do
    if not filterKind or filterKind == "all"
        or (filterKind == "warps" and item.kind == "warp")
        or (filterKind == "signs" and item.kind == "bg")
        or (filterKind == "npcs"  and item.kind == "npc") then
      table.insert(labels, item.label)
    end
  end
  ui.eventListSel:setItems(labels)
end

-- Populate event property fields from a single event data table.
function UI.fillEventProps(ui, item)
  if not item then return end
  local d = item.data
  if not d then return end

  if ui.eventProps.xEdit then ui.eventProps.xEdit:setText(tostring(d.x or "0")) end
  if ui.eventProps.yEdit then ui.eventProps.yEdit:setText(tostring(d.y or "0")) end
  if ui.eventProps.scriptEdit then
    ui.eventProps.scriptEdit:setText(d.script or "")
  end

  if item.kind == "warp" then
    if ui.eventProps.destEdit   then ui.eventProps.destEdit:setText(d.dest or "")   end
    if ui.eventProps.warpIdEdit then ui.eventProps.warpIdEdit:setText(d.warpId or "1") end
  elseif item.kind == "npc" then
    if ui.eventProps.movEdit    then ui.eventProps.movEdit:setText(d.movement or "STAY") end
    if ui.eventProps.dirEdit    then ui.eventProps.dirEdit:setText(d.dir or "NONE")      end
    -- spriteSel text matching
    if ui.eventProps.spriteSel  then ui.eventProps.spriteSel:setCurrentText(d.sprite or "") end
  end
end

-- Populate the sprite dropdown from a constants list.
function UI.fillSpriteOptions(ui, sprites)
  if ui.eventProps.spriteSel and sprites then
    ui.eventProps.spriteSel:setItems(sprites)
  end
end

return UI
