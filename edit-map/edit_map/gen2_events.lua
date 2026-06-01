-- Parses and serializes Gen-2 (pokecrystal) map event files.
--
-- These files live at maps/{MapName}.asm and contain:
--
--   MapName_MapEvents:
--       db 0, 0 ; filler
--       db N ; warps
--       warp_def X, Y, warpId, DEST_MAP
--       ...
--       db N ; coords
--       coord_event X, Y, SCENE_CONST, ScriptLabel
--       ...
--       db N ; bgevents
--       bg_event X, Y, BGEVENT_TYPE, ScriptLabel
--       ...
--       db N ; people
--       person_event SPRITE, X, Y, MOVE, range, sx, sy, sight, color, Script, facing
--       ...
--
--   MapName_MapConnections:
--       db N
--       connection DIR, DestMapName, DestMap_MapBlocks, offset, width, strip_ptr
--       ...
--
-- Text-area formats (one entry per line, whitespace-separated):
--   Warp:       X Y warpId DEST_MAP
--   Coord:      X Y SCENE ScriptLabel
--   BgEvent:    X Y BGEVENT_TYPE ScriptLabel
--   Person:     SPRITE X Y MOVE range sx sy sight color Script facing
--               (range/sx/sy default to -1 if omitted; sight/color default to 0/255)
--   Connection: DIR DestMapName offset
--               (DestMap_MapBlocks is auto-derived as DestMapName_MapBlocks;
--                width and strip_ptr default to 0)
--
-- Public API
-- ----------
--   Gen2Events.parse(text)                          -> parsed
--   Gen2Events.warpsToText(parsed)                  -> string
--   Gen2Events.coordsToText(parsed)                 -> string
--   Gen2Events.bgEventsToText(parsed)               -> string
--   Gen2Events.peopleToText(parsed)                 -> string
--   Gen2Events.connectionsToText(parsed)            -> string
--   Gen2Events.serializeWarps(parsed, text)         -> (newText, err)
--   Gen2Events.serializeCoords(parsed, text)        -> (newText, err)
--   Gen2Events.serializeBgEvents(parsed, text)      -> (newText, err)
--   Gen2Events.serializePeople(parsed, text)        -> (newText, err)
--   Gen2Events.serializeConnections(parsed, text)   -> (newText, err)
--   Gen2Events.read(path)                           -> (parsed, err)
--   Gen2Events.writeWarps(path, parsed, text)       -> (ok, err)
--   Gen2Events.writeCoords(path, parsed, text)      -> (ok, err)
--   Gen2Events.writeBgEvents(path, parsed, text)    -> (ok, err)
--   Gen2Events.writePeople(path, parsed, text)      -> (ok, err)
--   Gen2Events.writeConnections(path, parsed, text) -> (ok, err)

local Util = require("edit_map.util")

local Gen2Events = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function parseCount(code)
  return tonumber(code:match("^%s*db%s+(%d+)%s*"))
end

local function spliceLines(lines, first, last, newLines)
  local result = {}
  for i = 1, first - 1 do table.insert(result, lines[i]) end
  for _, l in ipairs(newLines) do table.insert(result, l) end
  for i = last + 1, #lines do table.insert(result, lines[i]) end
  return result
end

local function insertAfterLine(lines, afterIdx, newLines)
  local result = {}
  for i = 1, afterIdx do table.insert(result, lines[i]) end
  for _, l in ipairs(newLines) do table.insert(result, l) end
  for i = afterIdx + 1, #lines do table.insert(result, lines[i]) end
  return result
end

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

function Gen2Events.parse(text)
  local lines = Util.splitLines(text)

  local parsed = {
    lines = lines,

    -- MapEvents section
    eventsLabelLine   = nil,

    warps             = {},
    warpsCountLine    = nil,
    warpLines         = {},

    coords            = {},
    coordsCountLine   = nil,
    coordLines        = {},

    bgEvents          = {},
    bgCountLine       = nil,
    bgLines           = {},

    people            = {},
    peopleCountLine   = nil,
    peopleLines       = {},

    -- MapConnections section
    connectionsLabelLine = nil,
    connections          = {},
    connectionsCountLine = nil,
    connectionLines      = {},
  }

  local inEvents      = false
  local inConnections = false
  local section       = nil  -- "warps"|"coords"|"bg"|"people" inside events
  local remaining     = 0

  local i = 1
  while i <= #lines do
    local code, comment = Util.stripComment(lines[i])
    local trimCode = Util.trim(code)
    local lc = comment:lower() .. trimCode:lower()

    -- Detect section labels
    if trimCode:match("_MapEvents:%s*$") or trimCode:match("_MapEvents$") then
      inEvents      = true
      inConnections = false
      parsed.eventsLabelLine = i
      section   = nil
      remaining = 0
      i = i + 1
      goto continue
    end

    if trimCode:match("_MapConnections:%s*$") or trimCode:match("_MapConnections$") then
      inConnections = true
      inEvents      = false
      section       = nil
      parsed.connectionsLabelLine = i
      i = i + 1
      goto continue
    end

    -- Skip other label lines that start a new section.
    if trimCode:match("^[%w_]+:%s*$") and not inConnections and not inEvents then
      i = i + 1
      goto continue
    end

    if inEvents then
      local countVal = parseCount(code)
      if countVal ~= nil then
        if lc:find("warp") then
          section = "warps"
          parsed.warpsCountLine = i
          remaining = countVal
        elseif lc:find("coord") then
          section = "coords"
          parsed.coordsCountLine = i
          remaining = countVal
        elseif lc:find("bgevent") or lc:find("bg event") or lc:find("bg_event") then
          section = "bg"
          parsed.bgCountLine = i
          remaining = countVal
        elseif lc:find("people") or lc:find("person") then
          section = "people"
          parsed.peopleCountLine = i
          remaining = countVal
        end
        i = i + 1
        goto continue
      end

      -- Entry macros
      if section == "warps" and remaining > 0 and code:match("^%s*warp_def%s") then
        local args = code:match("warp_def%s+(.+)$")
        if args then
          local p = {}
          for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
          if #p >= 4 then
            table.insert(parsed.warps, { x=p[1], y=p[2], warpId=p[3], dest=p[4] })
            table.insert(parsed.warpLines, i)
            remaining = remaining - 1
          end
        end

      elseif section == "coords" and remaining > 0 and code:match("^%s*coord_event%s") then
        local args = code:match("coord_event%s+(.+)$")
        if args then
          local p = {}
          for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
          if #p >= 4 then
            table.insert(parsed.coords, { x=p[1], y=p[2], scene=p[3], script=p[4] })
            table.insert(parsed.coordLines, i)
            remaining = remaining - 1
          end
        end

      elseif section == "bg" and remaining > 0 and code:match("^%s*bg_event%s") then
        local args = code:match("bg_event%s+(.+)$")
        if args then
          local p = {}
          for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
          if #p >= 4 then
            table.insert(parsed.bgEvents, { x=p[1], y=p[2], eventType=p[3], script=p[4] })
            table.insert(parsed.bgLines, i)
            remaining = remaining - 1
          end
        end

      elseif section == "people" and remaining > 0 and code:match("^%s*person_event%s") then
        local args = code:match("person_event%s+(.+)$")
        if args then
          local p = {}
          for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
          if #p >= 11 then
            table.insert(parsed.people, {
              sprite=p[1], x=p[2], y=p[3], move=p[4], range=p[5],
              sx=p[6], sy=p[7], sight=p[8], color=p[9], script=p[10], facing=p[11]
            })
            table.insert(parsed.peopleLines, i)
            remaining = remaining - 1
          end
        end
      end

    elseif inConnections then
      -- Count line
      local countVal = parseCount(code)
      if countVal ~= nil and not parsed.connectionsCountLine then
        parsed.connectionsCountLine = i
        i = i + 1
        goto continue
      end

      -- connection macro
      if code:match("^%s*connection%s") then
        local args = code:match("connection%s+(.+)$")
        if args then
          local p = {}
          for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
          if #p >= 4 then
            table.insert(parsed.connections, {
              dir        = p[1]:lower(),
              destMap    = p[2],
              destBlocks = p[3],
              offset     = p[4],
              width      = p[5] or "0",
              strip      = p[6] or "0",
            })
            table.insert(parsed.connectionLines, i)
          end
        end
      end
    end

    ::continue::
    i = i + 1
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Text rendering
-- ---------------------------------------------------------------------------

function Gen2Events.warpsToText(parsed)
  local out = {}
  for _, w in ipairs(parsed.warps) do
    table.insert(out, string.format("%s %s %s %s", w.x, w.y, w.warpId, w.dest))
  end
  return table.concat(out, "\n")
end

function Gen2Events.coordsToText(parsed)
  local out = {}
  for _, c in ipairs(parsed.coords) do
    table.insert(out, string.format("%s %s %s %s", c.x, c.y, c.scene, c.script))
  end
  return table.concat(out, "\n")
end

function Gen2Events.bgEventsToText(parsed)
  local out = {}
  for _, b in ipairs(parsed.bgEvents) do
    table.insert(out, string.format("%s %s %s %s", b.x, b.y, b.eventType, b.script))
  end
  return table.concat(out, "\n")
end

function Gen2Events.peopleToText(parsed)
  local out = {}
  for _, p in ipairs(parsed.people) do
    table.insert(out, string.format("%s %s %s %s %s %s %s %s %s %s %s",
      p.sprite, p.x, p.y, p.move, p.range, p.sx, p.sy, p.sight, p.color, p.script, p.facing))
  end
  return table.concat(out, "\n")
end

function Gen2Events.connectionsToText(parsed)
  local out = {}
  for _, c in ipairs(parsed.connections) do
    -- Compact 3-token form; extra fields are preserved on write but not shown.
    table.insert(out, string.format("%s %s %s", c.dir, c.destMap, c.offset))
  end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Text-area parsing
-- ---------------------------------------------------------------------------

local function parseTextWarps(text)
  local entries, n = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local t = Util.tokenize(s)
      if #t < 4 then
        return nil, string.format("Line %d: warp needs X Y warpId DEST (4 tokens).", n)
      end
      table.insert(entries, { x=t[1], y=t[2], warpId=t[3], dest=t[4] })
    end
  end
  return entries, nil
end

local function parseTextCoords(text)
  local entries, n = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local t = Util.tokenize(s)
      if #t < 4 then
        return nil, string.format("Line %d: coord event needs X Y SCENE Script (4 tokens).", n)
      end
      table.insert(entries, { x=t[1], y=t[2], scene=t[3], script=t[4] })
    end
  end
  return entries, nil
end

local function parseTextBgEvents(text)
  local entries, n = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local t = Util.tokenize(s)
      if #t < 4 then
        return nil, string.format("Line %d: bg_event needs X Y TYPE Script (4 tokens).", n)
      end
      table.insert(entries, { x=t[1], y=t[2], eventType=t[3], script=t[4] })
    end
  end
  return entries, nil
end

local function parseTextPeople(text)
  local entries, n = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local t = Util.tokenize(s)
      -- Minimum 5 tokens: SPRITE X Y MOVE Script
      if #t < 5 then
        return nil, string.format(
          "Line %d: person_event needs at least SPRITE X Y MOVE Script (5 tokens).", n)
      end
      table.insert(entries, {
        sprite = t[1],
        x      = t[2],
        y      = t[3],
        move   = t[4],
        range  = t[5] or "-1",
        sx     = t[6] or "-1",
        sy     = t[7] or "-1",
        sight  = t[8] or "0",
        color  = t[9] or "255",
        script = t[10] or t[5] or "0",
        facing = t[11] or "-1",
      })
    end
  end
  return entries, nil
end

local function parseTextConnections(text)
  local entries, n = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local t = Util.tokenize(s)
      -- Accept "DIR DestMapName offset" (3 tokens) or full 6-token form.
      if #t < 3 then
        return nil, string.format(
          "Line %d: connection needs DIR DestMapName offset (3 tokens min).", n)
      end
      local destMap    = t[2]
      local destBlocks = t[4] or (destMap .. "_MapBlocks")
      local offset     = t[3]
      local width      = t[5] or "0"
      local strip      = t[6] or "0"
      table.insert(entries, {
        dir        = t[1]:lower(),
        destMap    = destMap,
        destBlocks = destBlocks,
        offset     = offset,
        width      = width,
        strip      = strip,
      })
    end
  end
  return entries, nil
end

-- ---------------------------------------------------------------------------
-- Generic block rebuild
-- ---------------------------------------------------------------------------

-- Replace the entries for one section (identified by its count line and
-- list of entry line indices) in `lines`, and return updated lines.
-- `newEntries` is a list of already-formatted ASM strings (no indent).
-- `countLine` is the 1-based index of the `db N` count line.
-- `entryLines` is the list of 1-based indices of the old entry lines.
-- `macro` is the macro name used to format new entries, e.g. "warp_def".
local function rebuildBlock(lines, countLine, entryLines, newMacroLines)
  -- Update count.
  lines[countLine] = Util.replaceLineKeepingComment(
    lines[countLine], string.format("db %d", #newMacroLines))

  -- Determine indent.
  local indent = ""
  if #entryLines > 0 then
    indent = Util.indentOf(lines[entryLines[1]])
  else
    indent = Util.indentOf(lines[countLine]) .. "\t"
  end

  local indented = {}
  for _, m in ipairs(newMacroLines) do
    table.insert(indented, indent .. m)
  end

  if #entryLines > 0 then
    lines = spliceLines(lines, entryLines[1], entryLines[#entryLines], indented)
  elseif #indented > 0 then
    lines = insertAfterLine(lines, countLine, indented)
  end

  return lines
end

-- ---------------------------------------------------------------------------
-- Section serializers
-- ---------------------------------------------------------------------------

function Gen2Events.serializeWarps(parsed, text)
  local entries, err = parseTextWarps(text)
  if not entries then return nil, err end
  if not parsed.warpsCountLine then return nil, "No warp count line found." end

  local macros = {}
  for _, e in ipairs(entries) do
    table.insert(macros, string.format("warp_def %s, %s, %s, %s",
      e.x, e.y, e.warpId, e.dest))
  end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end
  lines = rebuildBlock(lines, parsed.warpsCountLine, parsed.warpLines, macros)
  return Util.joinLines(lines), nil
end

function Gen2Events.serializeCoords(parsed, text)
  local entries, err = parseTextCoords(text)
  if not entries then return nil, err end
  if not parsed.coordsCountLine then return nil, "No coord count line found." end

  local macros = {}
  for _, e in ipairs(entries) do
    table.insert(macros, string.format("coord_event %s, %s, %s, %s",
      e.x, e.y, e.scene, e.script))
  end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end
  lines = rebuildBlock(lines, parsed.coordsCountLine, parsed.coordLines, macros)
  return Util.joinLines(lines), nil
end

function Gen2Events.serializeBgEvents(parsed, text)
  local entries, err = parseTextBgEvents(text)
  if not entries then return nil, err end
  if not parsed.bgCountLine then return nil, "No bg_event count line found." end

  local macros = {}
  for _, e in ipairs(entries) do
    table.insert(macros, string.format("bg_event %s, %s, %s, %s",
      e.x, e.y, e.eventType, e.script))
  end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end
  lines = rebuildBlock(lines, parsed.bgCountLine, parsed.bgLines, macros)
  return Util.joinLines(lines), nil
end

function Gen2Events.serializePeople(parsed, text)
  local entries, err = parseTextPeople(text)
  if not entries then return nil, err end
  if not parsed.peopleCountLine then return nil, "No people count line found." end

  local macros = {}
  for _, e in ipairs(entries) do
    table.insert(macros, string.format(
      "person_event %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s",
      e.sprite, e.x, e.y, e.move, e.range, e.sx, e.sy,
      e.sight, e.color, e.script, e.facing))
  end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end
  lines = rebuildBlock(lines, parsed.peopleCountLine, parsed.peopleLines, macros)
  return Util.joinLines(lines), nil
end

function Gen2Events.serializeConnections(parsed, text)
  local entries, err = parseTextConnections(text)
  if not entries then return nil, err end
  if not parsed.connectionsCountLine then return nil, "No connections count line found." end

  local macros = {}
  for _, e in ipairs(entries) do
    table.insert(macros, string.format("connection %s, %s, %s, %s, %s, %s",
      e.dir, e.destMap, e.destBlocks, e.offset, e.width, e.strip))
  end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end
  lines = rebuildBlock(lines, parsed.connectionsCountLine, parsed.connectionLines, macros)
  return Util.joinLines(lines), nil
end

-- ---------------------------------------------------------------------------
-- Read / Write helpers
-- ---------------------------------------------------------------------------

function Gen2Events.read(path)
  local text, err = pt.file.read(path)
  if not text then
    return nil, err or ("cannot read " .. path)
  end
  local ok, result = pcall(Gen2Events.parse, text)
  if not ok then
    return nil, "parse error: " .. tostring(result)
  end
  return result, nil
end

local function writeWith(path, parsed, text, serializeFn)
  local newText, err = serializeFn(parsed, text)
  if not newText then return false, err end
  local ok, werr = pt.file.write(path, newText)
  if not ok then return false, werr or ("cannot write " .. path) end
  return true, nil
end

function Gen2Events.writeWarps(path, parsed, text)
  return writeWith(path, parsed, text, Gen2Events.serializeWarps)
end

function Gen2Events.writeCoords(path, parsed, text)
  return writeWith(path, parsed, text, Gen2Events.serializeCoords)
end

function Gen2Events.writeBgEvents(path, parsed, text)
  return writeWith(path, parsed, text, Gen2Events.serializeBgEvents)
end

function Gen2Events.writePeople(path, parsed, text)
  return writeWith(path, parsed, text, Gen2Events.serializePeople)
end

function Gen2Events.writeConnections(path, parsed, text)
  return writeWith(path, parsed, text, Gen2Events.serializeConnections)
end

return Gen2Events
