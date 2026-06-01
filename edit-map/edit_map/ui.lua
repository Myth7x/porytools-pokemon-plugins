-- Builds the dockable "Edit Map" panel.
--
-- Tab layout (7 tabs):
--   Header      — tileset, dimensions/music, connection flags
--   Warps       — warp_def / warp entries as a text area
--   NPCs        — object / person_event entries as a text area
--   Signs       — sign / bg_event (+ coord_event for gen-2) as text areas
--   Connections — connection macros as a text area
--   Scripts     — open the events / header file in the editor
--   Map         — colour-coded block-map canvas with event overlays
--
-- Tabs are implemented with the offscreen trick: widgets that belong to an
-- inactive tab are moved to (-9999, -9999) so they disappear, then moved
-- back when the tab becomes active.  This mirrors the edit-pokemon plugin.

local UI = {}

-- ---------------------------------------------------------------
-- Off-screen Section helper
-- ---------------------------------------------------------------

local OFFSCREEN_X = -9999
local OFFSCREEN_Y = -9999

local Section = {}

function Section.new()
  return { entries = {}, visible = true }
end

function Section.add(section, widget, x, y)
  widget:setPosition(x, y)
  table.insert(section.entries, { widget = widget, x = x, y = y })
end

function Section.show(section)
  section.visible = true
  for _, e in ipairs(section.entries) do
    e.widget:setPosition(e.x, e.y)
  end
end

function Section.hide(section)
  section.visible = false
  for _, e in ipairs(section.entries) do
    e.widget:setPosition(OFFSCREEN_X, OFFSCREEN_Y)
  end
end

-- ---------------------------------------------------------------
-- Panel dimensions
-- ---------------------------------------------------------------

local W = 460   -- widget width
local H = 820   -- widget height

-- Row Y positions for the permanent header strip.
local SEL_Y  = 10  -- map selection
local INFO_Y = 44  -- gen / info label
local TAB_Y  = 70  -- tab buttons
local CONT_Y = 108 -- content area start

-- Tab button width: 7 tabs × 60px + 6 × 2px gaps = 432px (fits in W=460).
local TAB_W  = 60
local TAB_H  = 26

-- Content area geometry.
local CX  = 12   -- left margin
local CW  = W - CX * 2  -- content width
local CWH = 420  -- text-area height (most sections)
local CWS = 200  -- short text-area height (signs when two are stacked)

-- Canvas dimensions for the Map tab.
local CANVAS_W = CW        -- full content width
local CANVAS_H = 600       -- fixed height; map is scaled to fit

-- ---------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------

local function makeHintLabel(panel, section, text, y)
  local lbl = panel:addLabel(text)
  lbl:setSize(CW, 20)
  Section.add(section, lbl, CX, y)
  return lbl, y + 24
end

local function makeTextArea(panel, section, height, y)
  local ta = panel:addTextArea("")
  ta:setSize(CW, height)
  Section.add(section, ta, CX, y)
  return ta, y + height + 6
end

local function makeButton(panel, section, label, y)
  local btn = panel:addButton(label)
  btn:setSize(CW, 28)
  Section.add(section, btn, CX, y)
  return btn, y + 34
end

local function makeLabeledInput(panel, section, caption, y)
  local lbl = panel:addLabel(caption .. ":")
  lbl:setSize(110, 22)
  Section.add(section, lbl, CX, y + 3)
  local inp = panel:addLineEdit("")
  inp:setSize(CW - 120, 26)
  Section.add(section, inp, CX + 120, y)
  return inp, y + 32
end

-- ---------------------------------------------------------------
-- Public: create the widget
-- ---------------------------------------------------------------

-- `opts` must contain:
--   isGen2        : bool
--   mapNames      : list of display names for the dropdown
--   genLabel      : string e.g. "Gen 2 (pokecrystal)"
--
-- Callback defaults are no-ops; the controller replaces them after creation.
function UI.create(opts)
  local panel = pt.ui.createWidget("Edit Map")
  panel:setSize(W, H)

  local ui = {
    panel    = panel,
    isGen2   = opts.isGen2,
    sections = {},
    activeTab = nil,

    -- Callbacks (assigned by the controller)
    onSelectionChange  = function(_) end,
    onSaveHeader       = function() end,
    onSaveWarps        = function() end,
    onSaveNpcs         = function() end,
    onSaveSigns        = function() end,
    onSaveConnections  = function() end,
    onOpenEventsFile   = function() end,
    onOpenHeaderFile   = function() end,
    onReload           = function() end,
    onZoomIn           = function() end,
    onZoomOut          = function() end,
  }

  -- ---- Permanent header strip (always visible) -----------------

  local selLabel = panel:addLabel("Map:")
  selLabel:setPosition(CX, SEL_Y + 3)
  selLabel:setSize(40, 22)

  local mapSel = panel:addSelection("Select a map")
  mapSel:setPosition(CX + 44, SEL_Y)
  mapSel:setSize(W - CX - 44 - 8, 26)
  mapSel:setItems(opts.mapNames)
  ui.mapSel = mapSel

  local infoLabel = panel:addLabel(opts.genLabel or "")
  infoLabel:setPosition(CX, INFO_Y)
  infoLabel:setSize(W - CX * 2, 20)
  ui.infoLabel = infoLabel

  -- ---- Tab buttons (always visible) ----------------------------

  local tabDefs = {
    { key = "header",      label = "Header"  },
    { key = "warps",       label = "Warps"   },
    { key = "npcs",        label = "NPCs"    },
    { key = "signs",       label = "Signs"   },
    { key = "connections", label = "Conns"   },
    { key = "scripts",     label = "Scripts" },
    { key = "map",         label = "Map"     },
  }

  local tx = CX
  for _, t in ipairs(tabDefs) do
    local btn = panel:addButton(t.label)
    btn:setPosition(tx, TAB_Y)
    btn:setSize(TAB_W, TAB_H)
    btn:onClick(function() UI.showTab(ui, t.key) end)
    tx = tx + TAB_W + 2
  end

  -- ---- Header section ------------------------------------------
  do
    local sec = Section.new()
    ui.sections.header = sec

    local y = CONT_Y

    if opts.isGen2 then
      -- Gen 2: tileset, music, map const, scene, land
      local tileset, music, mapConst, sceneConst, land
      tileset,  y = makeLabeledInput(panel, sec, "Tileset",  y)
      music,    y = makeLabeledInput(panel, sec, "Music",    y)
      mapConst, y = makeLabeledInput(panel, sec, "Map Const",y)
      sceneConst,y = makeLabeledInput(panel, sec, "Scene",   y)
      land,     y = makeLabeledInput(panel, sec, "Land",     y)
      ui.hdrTileset   = tileset
      ui.hdrMusic     = music
      ui.hdrMapConst  = mapConst
      ui.hdrScene     = sceneConst
      ui.hdrLand      = land
    else
      -- Gen 1: tileset, height, width, connection flags
      local tileset, height, width, connFlags
      tileset,   y = makeLabeledInput(panel, sec, "Tileset",   y)
      height,    y = makeLabeledInput(panel, sec, "Height",     y)
      width,     y = makeLabeledInput(panel, sec, "Width",      y)
      connFlags, y = makeLabeledInput(panel, sec, "Conn Flags", y)
      ui.hdrTileset   = tileset
      ui.hdrHeight    = height
      ui.hdrWidth     = width
      ui.hdrConnFlags = connFlags
    end

    local saveBtn
    saveBtn, y = makeButton(panel, sec, "Save Header", y + 4)
    saveBtn:onClick(function() ui.onSaveHeader() end)
  end

  -- ---- Warps section -------------------------------------------
  do
    local sec = Section.new()
    ui.sections.warps = sec

    local y = CONT_Y
    local hint = opts.isGen2
      and "Format: X Y warpId DEST_MAP  (one warp per line)"
      or  "Format: X Y warpId DEST_MAP  (one warp per line)"
    _, y = makeHintLabel(panel, sec, hint, y)

    local ta
    ta, y = makeTextArea(panel, sec, CWH, y)
    ui.warpsArea = ta

    local btn
    btn, y = makeButton(panel, sec, "Save Warps", y)
    btn:onClick(function() ui.onSaveWarps(ui.warpsArea:text()) end)
  end

  -- ---- NPCs section --------------------------------------------
  do
    local sec = Section.new()
    ui.sections.npcs = sec

    local y = CONT_Y
    local hint = opts.isGen2
      and "Format: SPRITE X Y MOVE range sx sy sight color Script facing"
      or  "Format: SPRITE X Y facing movement ScriptLabel"
    _, y = makeHintLabel(panel, sec, hint, y)

    -- For gen2 we show a shorter format reminder on a second line.
    if opts.isGen2 then
      _, y = makeHintLabel(panel, sec, "(range/sx/sy default -1, sight=0, color=255, facing=-1)", y)
    end

    local ta
    ta, y = makeTextArea(panel, sec, opts.isGen2 and (CWH - 24) or CWH, y)
    ui.npcsArea = ta

    local btn
    btn, y = makeButton(panel, sec, "Save NPCs", y)
    btn:onClick(function() ui.onSaveNpcs(ui.npcsArea:text()) end)
  end

  -- ---- Signs section -------------------------------------------
  do
    local sec = Section.new()
    ui.sections.signs = sec

    local y = CONT_Y

    if opts.isGen2 then
      -- Gen 2: bg_events + coord_events
      _, y = makeHintLabel(panel, sec, "BG Events — Format: X Y BGEVENT_TYPE ScriptLabel", y)
      local bgTa
      bgTa, y = makeTextArea(panel, sec, CWS, y)
      ui.bgArea = bgTa

      _, y = makeHintLabel(panel, sec, "Coord Events — Format: X Y SCENE_CONST ScriptLabel", y)
      local coordTa
      coordTa, y = makeTextArea(panel, sec, CWS, y)
      ui.coordArea = coordTa

      local btn
      btn, y = makeButton(panel, sec, "Save Signs / Events", y)
      btn:onClick(function()
        ui.onSaveSigns(ui.bgArea:text(), ui.coordArea:text())
      end)
    else
      -- Gen 1: signs only
      _, y = makeHintLabel(panel, sec, "Format: X Y ScriptLabel  (one sign per line)", y)
      local ta
      ta, y = makeTextArea(panel, sec, CWH, y)
      ui.signsArea = ta

      local btn
      btn, y = makeButton(panel, sec, "Save Signs", y)
      btn:onClick(function() ui.onSaveSigns(ui.signsArea:text()) end)
    end
  end

  -- ---- Connections section -------------------------------------
  do
    local sec = Section.new()
    ui.sections.connections = sec

    local y = CONT_Y
    local hint = opts.isGen2
      and "Format: DIR DestMapName offset  (e.g. east Route29 5)"
      or  "Format: DIR DestBlocksLabel DestHeaderLabel offset"
    _, y = makeHintLabel(panel, sec, hint, y)

    local ta
    ta, y = makeTextArea(panel, sec, CWH, y)
    ui.connectionsArea = ta

    local btn
    btn, y = makeButton(panel, sec, "Save Connections", y)
    btn:onClick(function() ui.onSaveConnections(ui.connectionsArea:text()) end)
  end

  -- ---- Scripts section -----------------------------------------
  do
    local sec = Section.new()
    ui.sections.scripts = sec

    local y = CONT_Y

    local lbl1 = panel:addLabel("Open map files in the editor:")
    lbl1:setSize(CW, 22)
    Section.add(sec, lbl1, CX, y)
    y = y + 30

    local btnEvents = panel:addButton(opts.isGen2 and "Open maps/ file (events + scripts)" or "Open data/mapObjects/ file")
    btnEvents:setSize(CW, 28)
    Section.add(sec, btnEvents, CX, y)
    btnEvents:onClick(function() ui.onOpenEventsFile() end)
    y = y + 36

    local btnHeader = panel:addButton(opts.isGen2 and "Open data/maps/ header file" or "Open data/mapHeaders/ file")
    btnHeader:setSize(CW, 28)
    Section.add(sec, btnHeader, CX, y)
    btnHeader:onClick(function() ui.onOpenHeaderFile() end)
    y = y + 36

    local reloadBtn = panel:addButton("Reload Map List")
    reloadBtn:setSize(CW, 28)
    Section.add(sec, reloadBtn, CX, y)
    reloadBtn:onClick(function() ui.onReload() end)
  end

  -- ---- Map section --------------------------------------------
  do
    local sec = Section.new()
    ui.sections.map = sec

    local y = CONT_Y

    -- Dimension / scale info label.
    local dimLbl = panel:addLabel("Select a map to render.")
    dimLbl:setSize(CW, 20)
    Section.add(sec, dimLbl, CX, y)
    ui.mapDimLabel = dimLbl
    y = y + 26

    -- Zoom controls.
    local zoomInBtn = panel:addButton("Zoom +")
    zoomInBtn:setSize(80, 26)
    Section.add(sec, zoomInBtn, CX, y)
    zoomInBtn:onClick(function() ui.onZoomIn() end)

    local zoomOutBtn = panel:addButton("Zoom -")
    zoomOutBtn:setSize(80, 26)
    Section.add(sec, zoomOutBtn, CX + 86, y)
    zoomOutBtn:onClick(function() ui.onZoomOut() end)
    y = y + 32

    -- Canvas.
    local canvas = panel:addCanvas(CANVAS_W, CANVAS_H)
    Section.add(sec, canvas, CX, y)
    ui.mapCanvas = canvas
    y = y + CANVAS_H + 4

    -- Click-info label.
    local infoLbl = panel:addLabel("")
    infoLbl:setSize(CW, 20)
    Section.add(sec, infoLbl, CX, y)
    ui.mapInfoLabel = infoLbl
  end

  -- Wire map selection changes.
  mapSel:onChange(function(idx) ui.onSelectionChange(idx) end)

  -- Start on the Header tab.
  UI.showTab(ui, "header")

  return ui
end

-- ---------------------------------------------------------------
-- Tab switching
-- ---------------------------------------------------------------

function UI.showTab(ui, name)
  ui.activeTab = name
  for sectionName, section in pairs(ui.sections) do
    if sectionName == name then
      Section.show(section)
    else
      Section.hide(section)
    end
  end
end

-- ---------------------------------------------------------------
-- Population helpers (called by the controller when a map loads)
-- ---------------------------------------------------------------

function UI.show(ui)
  ui.panel:show()
end

function UI.setInfo(ui, text)
  ui.infoLabel:setText(text)
end

-- Fill the Header tab from a parsed header table.
-- `headerData` shape:
--   Gen1: { tileset, height, width, connFlags }
--   Gen2: { tileset, music, mapConst, sceneConst, land }
function UI.fillHeader(ui, headerData)
  if not headerData then return end
  if ui.isGen2 then
    if ui.hdrTileset  then ui.hdrTileset:setText(headerData.tileset    or "") end
    if ui.hdrMusic    then ui.hdrMusic:setText(headerData.music      or "") end
    if ui.hdrMapConst then ui.hdrMapConst:setText(headerData.mapConst  or "") end
    if ui.hdrScene    then ui.hdrScene:setText(headerData.sceneConst or "") end
    if ui.hdrLand     then ui.hdrLand:setText(headerData.land       or "0") end
  else
    if ui.hdrTileset   then ui.hdrTileset:setText(headerData.tileset    or "") end
    if ui.hdrHeight    then ui.hdrHeight:setText(headerData.height    or "") end
    if ui.hdrWidth     then ui.hdrWidth:setText(headerData.width     or "") end
    if ui.hdrConnFlags then ui.hdrConnFlags:setText(headerData.connFlags or "0") end
  end
end

-- Read header fields back to an edits table.
function UI.readHeader(ui)
  if ui.isGen2 then
    return {
      tileset    = ui.hdrTileset  and ui.hdrTileset:text()   or nil,
      music      = ui.hdrMusic    and ui.hdrMusic:text()     or nil,
      mapConst   = ui.hdrMapConst and ui.hdrMapConst:text()  or nil,
      sceneConst = ui.hdrScene    and ui.hdrScene:text()     or nil,
      land       = ui.hdrLand     and ui.hdrLand:text()      or nil,
    }
  else
    return {
      tileset   = ui.hdrTileset   and ui.hdrTileset:text()   or nil,
      height    = ui.hdrHeight    and ui.hdrHeight:text()    or nil,
      width     = ui.hdrWidth     and ui.hdrWidth:text()     or nil,
      connFlags = ui.hdrConnFlags and ui.hdrConnFlags:text() or nil,
    }
  end
end

function UI.setWarpsText(ui, text)
  if ui.warpsArea then ui.warpsArea:setText(text or "") end
end

function UI.setNpcsText(ui, text)
  if ui.npcsArea then ui.npcsArea:setText(text or "") end
end

-- Gen1: signsText is a single string.
-- Gen2: bgText and coordText are two separate strings.
function UI.setSignsText(ui, bgOrSignsText, coordText)
  if ui.isGen2 then
    if ui.bgArea    then ui.bgArea:setText(bgOrSignsText or "") end
    if ui.coordArea then ui.coordArea:setText(coordText or "") end
  else
    if ui.signsArea then ui.signsArea:setText(bgOrSignsText or "") end
  end
end

function UI.setConnectionsText(ui, text)
  if ui.connectionsArea then ui.connectionsArea:setText(text or "") end
end

-- Update the Map tab dimension / scale info label.
function UI.setMapDim(ui, text)
  if ui.mapDimLabel then ui.mapDimLabel:setText(text or "") end
end

-- Update the Map tab block click-feedback label.
function UI.setMapInfo(ui, text)
  if ui.mapInfoLabel then ui.mapInfoLabel:setText(text or "") end
end

return UI
