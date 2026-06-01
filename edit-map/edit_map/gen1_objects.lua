-- Parses and serializes Gen-1 (pokered) map object files.
--
-- Format of data/mapObjects/{mapId}.asm:
--
--   MapNameObject:
--       db $1b       ; border block
--       db 3         ; warps
--       warp 5, 11, 0, REDS_HOUSE_1F
--       warp 5, 13, 0, BLUES_HOUSE
--       warp 11, 13, 0, OAKS_LAB
--       db 2         ; signs
--       sign 7, 9, PelletTownText_4
--       sign 7, 17, PelletTownText_5
--       db 3         ; people
--       object SPRITE_BLUE_RIVAL, 5, 5, 0, 0, OAK_AIDE_TRIGGER
--       object SPRITE_GIRL, 5, 8, 0, 2, PelletTownText_6
--       object SPRITE_OAK, 1, 5, 0, 0, OAKScript
--
-- Text-area formats (one entry per line, whitespace-separated):
--   Warp  : X Y warpId DEST_MAP
--   Sign  : X Y ScriptLabel
--   Person: SPRITE X Y facing movement ScriptLabel
--
-- Public API
-- ----------
--   Gen1Objects.parse(text)                        -> parsed
--   Gen1Objects.warpsToText(parsed)                -> string
--   Gen1Objects.signsToText(parsed)                -> string
--   Gen1Objects.peopleToText(parsed)               -> string
--   Gen1Objects.serializeWarps(parsed, text)       -> (newText, err)
--   Gen1Objects.serializeSigns(parsed, text)       -> (newText, err)
--   Gen1Objects.serializePeople(parsed, text)      -> (newText, err)
--   Gen1Objects.read(path)                         -> (parsed, err)
--   Gen1Objects.writeWarps(path, parsed, text)     -> (ok, err)
--   Gen1Objects.writeSigns(path, parsed, text)     -> (ok, err)
--   Gen1Objects.writePeople(path, parsed, text)    -> (ok, err)

local Util = require("edit_map.util")

local Gen1Objects = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Parse a `db N` count line; return N or nil.
local function parseCount(code)
  return tonumber(code:match("^%s*db%s+(%d+)%s*"))
end

-- Build a block of ASM lines from a list of already-formatted macro strings.
-- `indent` is the leading whitespace to use.
local function buildBlock(macros, indent)
  local lines = {}
  for _, m in ipairs(macros) do
    table.insert(lines, indent .. m)
  end
  return lines
end

-- Replace lines [first, last] (1-based, inclusive) in `lines` with `newLines`.
local function spliceLines(lines, first, last, newLines)
  local result = {}
  for i = 1, first - 1 do
    table.insert(result, lines[i])
  end
  for _, l in ipairs(newLines) do
    table.insert(result, l)
  end
  for i = last + 1, #lines do
    table.insert(result, lines[i])
  end
  return result
end

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

function Gen1Objects.parse(text)
  local lines = Util.splitLines(text)
  local parsed = {
    lines          = lines,
    border         = nil,
    borderLine     = nil,
    warps          = {},
    warpsCountLine = nil,
    warpLines      = {},
    signs          = {},
    signsCountLine = nil,
    signLines      = {},
    people         = {},
    peopleCountLine= nil,
    peopleLines    = {},
  }

  -- Simple state machine: after we see "db N ; warps" we collect warp lines, etc.
  local section = nil  -- "border" | "warps" | "signs" | "people" | nil
  local remaining = 0  -- entries still expected in current section

  local i = 1
  while i <= #lines do
    local code, comment = Util.stripComment(lines[i])
    local lc = comment:lower()
    local countVal = parseCount(code)

    -- Border block: first `db $XX` before any section marker
    if not parsed.borderLine and code:match("^%s*db%s+%$%x+%s*$") then
      parsed.border = Util.trim(code):match("db%s+(%S+)")
      parsed.borderLine = i

    -- Count lines that start new sections
    elseif countVal ~= nil then
      if lc:find("warp") then
        section = "warps"
        parsed.warpsCountLine = i
        remaining = countVal
      elseif lc:find("sign") then
        section = "signs"
        parsed.signsCountLine = i
        remaining = countVal
      elseif lc:find("people") or lc:find("person") or lc:find("npc") or lc:find("object") then
        section = "people"
        parsed.peopleCountLine = i
        remaining = countVal
      end

    -- Entry lines
    elseif section == "warps" and remaining > 0 and code:match("^%s*warp%s") then
      -- warp X, Y, warpId, DEST
      local args = code:match("warp%s+(.+)$")
      if args then
        local p = {}
        for part in args:gmatch("([^,]+)") do
          table.insert(p, Util.trim(part))
        end
        if #p >= 4 then
          table.insert(parsed.warps, { x=p[1], y=p[2], warpId=p[3], dest=p[4] })
          table.insert(parsed.warpLines, i)
          remaining = remaining - 1
        end
      end

    elseif section == "signs" and remaining > 0 and code:match("^%s*sign%s") then
      -- sign X, Y, ScriptLabel
      local args = code:match("sign%s+(.+)$")
      if args then
        local p = {}
        for part in args:gmatch("([^,]+)") do
          table.insert(p, Util.trim(part))
        end
        if #p >= 3 then
          table.insert(parsed.signs, { x=p[1], y=p[2], script=p[3] })
          table.insert(parsed.signLines, i)
          remaining = remaining - 1
        end
      end

    elseif section == "people" and remaining > 0 and code:match("^%s*object%s") then
      -- object SPRITE, X, Y, facing, movement, ScriptLabel
      local args = code:match("object%s+(.+)$")
      if args then
        local p = {}
        for part in args:gmatch("([^,]+)") do
          table.insert(p, Util.trim(part))
        end
        if #p >= 6 then
          table.insert(parsed.people, {
            sprite=p[1], x=p[2], y=p[3],
            facing=p[4], movement=p[5], script=p[6]
          })
          table.insert(parsed.peopleLines, i)
          remaining = remaining - 1
        end
      end
    end

    i = i + 1
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Text rendering (parsed -> text area content)
-- ---------------------------------------------------------------------------

function Gen1Objects.warpsToText(parsed)
  local out = {}
  for _, w in ipairs(parsed.warps) do
    table.insert(out, string.format("%s %s %s %s", w.x, w.y, w.warpId, w.dest))
  end
  return table.concat(out, "\n")
end

function Gen1Objects.signsToText(parsed)
  local out = {}
  for _, s in ipairs(parsed.signs) do
    table.insert(out, string.format("%s %s %s", s.x, s.y, s.script))
  end
  return table.concat(out, "\n")
end

function Gen1Objects.peopleToText(parsed)
  local out = {}
  for _, p in ipairs(parsed.people) do
    table.insert(out, string.format("%s %s %s %s %s %s",
      p.sprite, p.x, p.y, p.facing, p.movement, p.script))
  end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Parsing text-area input back to entry lists
-- ---------------------------------------------------------------------------

-- Parse one line as a warp entry. Returns entry table or (nil, errMsg).
local function parseWarpLine(line, lineNo)
  local t = Util.tokenize(line)
  if #t < 4 then
    return nil, string.format("Line %d: warp needs 4 tokens (X Y warpId DEST), got %d.", lineNo, #t)
  end
  return { x=t[1], y=t[2], warpId=t[3], dest=t[4] }
end

-- Parse one line as a sign entry. Returns entry table or (nil, errMsg).
local function parseSignLine(line, lineNo)
  local t = Util.tokenize(line)
  if #t < 3 then
    return nil, string.format("Line %d: sign needs 3 tokens (X Y Script), got %d.", lineNo, #t)
  end
  return { x=t[1], y=t[2], script=t[3] }
end

-- Parse one line as a person/object entry. Returns entry table or (nil, errMsg).
local function parsePersonLine(line, lineNo)
  local t = Util.tokenize(line)
  if #t < 6 then
    return nil, string.format(
      "Line %d: object needs 6 tokens (SPRITE X Y facing movement Script), got %d.", lineNo, #t)
  end
  return { sprite=t[1], x=t[2], y=t[3], facing=t[4], movement=t[5], script=t[6] }
end

-- Parse a text area into a list of warp entries. Returns (list, err).
local function parseTextWarps(text)
  local entries = {}
  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local e, err = parseWarpLine(s, n)
      if not e then return nil, err end
      table.insert(entries, e)
    end
  end
  return entries, nil
end

local function parseTextSigns(text)
  local entries = {}
  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local e, err = parseSignLine(s, n)
      if not e then return nil, err end
      table.insert(entries, e)
    end
  end
  return entries, nil
end

local function parseTextPeople(text)
  local entries = {}
  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local s = Util.trim(line)
    if s ~= "" and not s:match("^;") then
      local e, err = parsePersonLine(s, n)
      if not e then return nil, err end
      table.insert(entries, e)
    end
  end
  return entries, nil
end

-- ---------------------------------------------------------------------------
-- Serializers — rebuild the file with one section replaced
-- ---------------------------------------------------------------------------

-- Rebuild the warps section in `parsed.lines` from `text`.
-- Returns (newFileText, err).
function Gen1Objects.serializeWarps(parsed, text)
  local entries, err = parseTextWarps(text)
  if not entries then return nil, err end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end

  if not parsed.warpsCountLine then
    return nil, "No warp count line found in file."
  end

  -- Determine indent from existing warp lines or count line.
  local indent = parsed.warpLines[1] and Util.indentOf(lines[parsed.warpLines[1]])
              or Util.indentOf(lines[parsed.warpsCountLine]) .. "\t"

  -- Build new entry lines.
  local newEntries = {}
  for _, e in ipairs(entries) do
    table.insert(newEntries, indent .. string.format("warp %s, %s, %s, %s",
      e.x, e.y, e.warpId, e.dest))
  end

  -- Update count line.
  lines[parsed.warpsCountLine] = Util.replaceLineKeepingComment(
    lines[parsed.warpsCountLine],
    string.format("db %d", #entries)
  )

  -- Replace old entry lines with new ones.
  if #parsed.warpLines > 0 then
    local first = parsed.warpLines[1]
    local last  = parsed.warpLines[#parsed.warpLines]
    lines = spliceLines(lines, first, last, newEntries)
  elseif #newEntries > 0 then
    -- No existing lines; insert right after count line.
    local insertAfter = parsed.warpsCountLine
    local result = {}
    for i = 1, insertAfter do table.insert(result, lines[i]) end
    for _, l in ipairs(newEntries) do table.insert(result, l) end
    for i = insertAfter + 1, #lines do table.insert(result, lines[i]) end
    lines = result
  end

  return Util.joinLines(lines), nil
end

-- Rebuild the signs section.
function Gen1Objects.serializeSigns(parsed, text)
  local entries, err = parseTextSigns(text)
  if not entries then return nil, err end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end

  if not parsed.signsCountLine then
    return nil, "No sign count line found in file."
  end

  local indent = parsed.signLines[1] and Util.indentOf(lines[parsed.signLines[1]])
              or Util.indentOf(lines[parsed.signsCountLine]) .. "\t"

  local newEntries = {}
  for _, e in ipairs(entries) do
    table.insert(newEntries, indent .. string.format("sign %s, %s, %s",
      e.x, e.y, e.script))
  end

  lines[parsed.signsCountLine] = Util.replaceLineKeepingComment(
    lines[parsed.signsCountLine],
    string.format("db %d", #entries)
  )

  if #parsed.signLines > 0 then
    local first = parsed.signLines[1]
    local last  = parsed.signLines[#parsed.signLines]
    lines = spliceLines(lines, first, last, newEntries)
  elseif #newEntries > 0 then
    local insertAfter = parsed.signsCountLine
    local result = {}
    for i = 1, insertAfter do table.insert(result, lines[i]) end
    for _, l in ipairs(newEntries) do table.insert(result, l) end
    for i = insertAfter + 1, #lines do table.insert(result, lines[i]) end
    lines = result
  end

  return Util.joinLines(lines), nil
end

-- Rebuild the people / objects section.
function Gen1Objects.serializePeople(parsed, text)
  local entries, err = parseTextPeople(text)
  if not entries then return nil, err end

  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end

  if not parsed.peopleCountLine then
    return nil, "No people count line found in file."
  end

  local indent = parsed.peopleLines[1] and Util.indentOf(lines[parsed.peopleLines[1]])
              or Util.indentOf(lines[parsed.peopleCountLine]) .. "\t"

  local newEntries = {}
  for _, e in ipairs(entries) do
    table.insert(newEntries, indent .. string.format("object %s, %s, %s, %s, %s, %s",
      e.sprite, e.x, e.y, e.facing, e.movement, e.script))
  end

  lines[parsed.peopleCountLine] = Util.replaceLineKeepingComment(
    lines[parsed.peopleCountLine],
    string.format("db %d", #entries)
  )

  if #parsed.peopleLines > 0 then
    local first = parsed.peopleLines[1]
    local last  = parsed.peopleLines[#parsed.peopleLines]
    lines = spliceLines(lines, first, last, newEntries)
  elseif #newEntries > 0 then
    local insertAfter = parsed.peopleCountLine
    local result = {}
    for i = 1, insertAfter do table.insert(result, lines[i]) end
    for _, l in ipairs(newEntries) do table.insert(result, l) end
    for i = insertAfter + 1, #lines do table.insert(result, lines[i]) end
    lines = result
  end

  return Util.joinLines(lines), nil
end

-- ---------------------------------------------------------------------------
-- Read / Write helpers
-- ---------------------------------------------------------------------------

function Gen1Objects.read(path)
  local text, err = pt.file.read(path)
  if not text then
    return nil, err or ("cannot read " .. path)
  end
  local ok, result = pcall(Gen1Objects.parse, text)
  if not ok then
    return nil, "parse error: " .. tostring(result)
  end
  return result, nil
end

local function writeWith(path, parsed, text, serializeFn)
  local newText, err = serializeFn(parsed, text)
  if not newText then
    return false, err
  end
  local ok, werr = pt.file.write(path, newText)
  if not ok then
    return false, werr or ("cannot write " .. path)
  end
  return true, nil
end

function Gen1Objects.writeWarps(path, parsed, text)
  return writeWith(path, parsed, text, Gen1Objects.serializeWarps)
end

function Gen1Objects.writeSigns(path, parsed, text)
  return writeWith(path, parsed, text, Gen1Objects.serializeSigns)
end

function Gen1Objects.writePeople(path, parsed, text)
  return writeWith(path, parsed, text, Gen1Objects.serializePeople)
end

return Gen1Objects
