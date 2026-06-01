-- gen1_edit_map/objects.lua
-- Parse and write Gen1 (pokered) map object files — CURRENT pret/pokered format.
--
-- File format (data/maps/objects/{MapId}.asm):
--
--   	object_const_def
--   	const_export PALLETTOWN_OAK
--   	...
--
--   PalletTown_Object:
--   	db $b ; border block
--
--   	def_warp_events
--   	warp_event  5,  5, REDS_HOUSE_1F, 1
--   	...
--
--   	def_bg_events
--   	bg_event 13, 13, TEXT_PALLETTOWN_OAKSLAB_SIGN
--   	...
--
--   	def_object_events
--   	object_event  8,  5, SPRITE_OAK, STAY, NONE, TEXT_PALLETTOWN_OAK
--   	...
--
--   	def_warps_to PALLET_TOWN
--
-- Sections are delimited by def_* macros (no explicit count lines).
--
-- Public API:
--   Objects.parse(text)                      → parsed
--   Objects.serialize(parsed)                → newText
--   Objects.read(path)                       → (parsed, err)
--   Objects.write(path, parsed)              → (ok, err)
--
-- `parsed` fields:
--   lines, border, borderLine,
--   warps    = [{x,y,dest,warpId,line}, ...]
--   bgEvents = [{x,y,script,line}, ...]
--   people   = [{sprite,x,y,movement,dir,script,line}, ...]
--   warpsTo, constBlock  (raw lines before the Object: label)
--   sectionLines = { warpsDef, bgDef, objectsDef, warpsTo } line indices

local Util = require("gen1_edit_map.util")

local Objects = {}

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

local function parseWarpEvent(code)
  -- warp_event X, Y, DEST, WARP_ID
  local args = code:match("warp_event%s+(.+)$")
  if not args then return nil end
  local p = {}
  for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
  if #p < 4 then return nil end
  return { x=p[1], y=p[2], dest=p[3], warpId=p[4] }
end

local function parseBgEvent(code)
  -- bg_event X, Y, SCRIPT_LABEL
  local args = code:match("bg_event%s+(.+)$")
  if not args then return nil end
  local p = {}
  for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
  if #p < 3 then return nil end
  return { x=p[1], y=p[2], script=p[3] }
end

local function parseObjectEvent(code)
  -- object_event SPRITE, X, Y, MOVEMENT, DIR, SCRIPT
  local args = code:match("object_event%s+(.+)$")
  if not args then return nil end
  local p = {}
  for part in args:gmatch("([^,]+)") do table.insert(p, Util.trim(part)) end
  if #p < 6 then return nil end
  return { sprite=p[1], x=p[2], y=p[3], movement=p[4], dir=p[5], script=p[6] }
end

function Objects.parse(text)
  local lines = Util.splitLines(text)
  local parsed = {
    lines        = lines,
    border       = nil,
    borderLine   = nil,
    warps        = {},
    bgEvents     = {},
    people       = {},
    warpsTo      = nil,
    sectionLines = {
      warpsDef   = nil,
      bgDef      = nil,
      objectsDef = nil,
      warpsTo    = nil,
    },
    -- raw preamble lines (const_def, const_export, etc.) up to the Object: label
    preambleEnd  = nil,
  }

  -- Simple section state: nil | "warps" | "bg" | "objects"
  local section = nil

  for i, line in ipairs(lines) do
    local code = Util.stripComment(line)
    local trimmed = Util.trim(code)

    -- Detect section transitions first.
    if trimmed:match("^def_warp_events") then
      section = "warps"
      parsed.sectionLines.warpsDef = i

    elseif trimmed:match("^def_bg_events") then
      section = "bg"
      parsed.sectionLines.bgDef = i

    elseif trimmed:match("^def_object_events") then
      section = "objects"
      parsed.sectionLines.objectsDef = i

    elseif trimmed:match("^def_warps_to%s") then
      section = nil
      parsed.warpsTo = trimmed:match("def_warps_to%s+(.+)$")
      parsed.sectionLines.warpsTo = i

    -- Border block: `db $XX ; border block`
    elseif not parsed.borderLine and trimmed:match("^db%s+%$%x+") then
      parsed.border = trimmed:match("db%s+(%S+)")
      parsed.borderLine = i

    -- Mark end of preamble at the Object: label line.
    elseif not parsed.preambleEnd and trimmed:match("^[%w_]+_Object:") then
      parsed.preambleEnd = i

    -- Entry lines per current section.
    elseif section == "warps" and trimmed:match("^warp_event%s") then
      local w = parseWarpEvent(trimmed)
      if w then
        w.line = i
        table.insert(parsed.warps, w)
      end

    elseif section == "bg" and trimmed:match("^bg_event%s") then
      local b = parseBgEvent(trimmed)
      if b then
        b.line = i
        table.insert(parsed.bgEvents, b)
      end

    elseif section == "objects" and trimmed:match("^object_event%s") then
      local obj = parseObjectEvent(trimmed)
      if obj then
        obj.line = i
        table.insert(parsed.people, obj)
      end
    end
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Serializer helpers
-- ---------------------------------------------------------------------------

-- Format a warp_event line.
local function fmtWarp(w, indent)
  return string.format("%swarp_event %s, %s, %s, %s",
    indent, w.x, w.y, w.dest, w.warpId)
end

-- Format a bg_event line.
local function fmtBg(b, indent)
  return string.format("%sbg_event %s, %s, %s",
    indent, b.x, b.y, b.script)
end

-- Format an object_event line.
local function fmtObject(obj, indent)
  return string.format("%sobject_event %s, %s, %s, %s, %s, %s",
    indent, obj.sprite, obj.x, obj.y, obj.movement, obj.dir, obj.script)
end

-- Get the indent used in the original file for entry lines.
local function getEntryIndent(parsed)
  -- Look at the first event of any type.
  local refs = {}
  if parsed.warps[1] then table.insert(refs, parsed.warps[1].line) end
  if parsed.bgEvents[1] then table.insert(refs, parsed.bgEvents[1].line) end
  if parsed.people[1] then table.insert(refs, parsed.people[1].line) end
  if #refs > 0 then
    return Util.indentOf(parsed.lines[refs[1]])
  end
  -- Default to a tab.
  if parsed.sectionLines.warpsDef then
    return Util.indentOf(parsed.lines[parsed.sectionLines.warpsDef])
  end
  return "\t"
end

-- ---------------------------------------------------------------------------
-- Serialize
-- ---------------------------------------------------------------------------

-- Rebuild the object file from the current parsed state.
-- This does a full re-write of the section content between section markers,
-- preserving all other lines (preamble, const_export, border, markers, warps_to).
function Objects.serialize(parsed)
  local indent = getEntryIndent(parsed)

  -- Collect lines to keep as-is (non-entry lines).
  -- We'll mark entry lines for removal and re-generate them.
  local entryLines = {}
  for _, w in ipairs(parsed.warps)    do entryLines[w.line]   = true end
  for _, b in ipairs(parsed.bgEvents) do entryLines[b.line]   = true end
  for _, obj in ipairs(parsed.people) do entryLines[obj.line] = true end

  -- Build the new file by iterating original lines, replacing entry blocks.
  local out = {}
  local insertedWarps, insertedBg, insertedObjs = false, false, false

  for i, line in ipairs(parsed.lines) do
    if entryLines[i] then
      -- Skip original entry lines; they will be replaced after their def_ line.
    else
      table.insert(out, line)

      local code = Util.trim(Util.stripComment(line))

      -- After def_warp_events, emit all warps.
      if code:match("^def_warp_events") and not insertedWarps then
        insertedWarps = true
        for _, w in ipairs(parsed.warps) do
          table.insert(out, fmtWarp(w, indent))
        end

      -- After def_bg_events, emit all bg events.
      elseif code:match("^def_bg_events") and not insertedBg then
        insertedBg = true
        for _, b in ipairs(parsed.bgEvents) do
          table.insert(out, fmtBg(b, indent))
        end

      -- After def_object_events, emit all NPCs.
      elseif code:match("^def_object_events") and not insertedObjs then
        insertedObjs = true
        for _, obj in ipairs(parsed.people) do
          table.insert(out, fmtObject(obj, indent))
        end
      end
    end
  end

  return Util.joinLines(out)
end

-- ---------------------------------------------------------------------------
-- I/O
-- ---------------------------------------------------------------------------

function Objects.read(path)
  local text, err = pt.file.read(path)
  if not text then return nil, err or "Could not read " .. path end
  return Objects.parse(text), nil
end

function Objects.write(path, parsed)
  local newText = Objects.serialize(parsed)
  local ok, err = pt.file.write(path, newText)
  if not ok then return false, err end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Convenience: build a human-readable summary of all events (for UI lists)
-- ---------------------------------------------------------------------------

function Objects.eventList(parsed)
  local items = {}
  for i, w in ipairs(parsed.warps) do
    table.insert(items, {
      kind  = "warp",
      index = i,
      label = string.format("Warp %d: (%s,%s) → %s", i, w.x, w.y, w.dest),
      data  = w,
    })
  end
  for i, b in ipairs(parsed.bgEvents) do
    table.insert(items, {
      kind  = "bg",
      index = i,
      label = string.format("Sign %d: (%s,%s) %s", i, b.x, b.y, b.script),
      data  = b,
    })
  end
  for i, obj in ipairs(parsed.people) do
    table.insert(items, {
      kind  = "npc",
      index = i,
      label = string.format("NPC %d: %s at (%s,%s)", i, obj.sprite, obj.x, obj.y),
      data  = obj,
    })
  end
  return items
end

return Objects
