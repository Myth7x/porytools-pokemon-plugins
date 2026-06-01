-- Parses and serializes Gen-2 (pokecrystal) map header files.
--
-- Format of data/maps/{MapName}.asm:
--
--   NewBarkTown_MapHeader:
--       map_header NewBarkTownTileset, NewBarkTown_MapAttributes, \
--                  NewBarkTown_MapScriptHeader, NewBarkTown_MapEvents, \
--                  NewBarkTown_MapConnections, NewBarkTown_MapBlocks, \
--                  MUSIC_NEW_BARK_TOWN, MAP_NEWBARKTOWN, MAP_SCENE_NEW_BARK_TOWN, 0
--
-- The macro may span multiple lines joined with backslash continuations, but
-- in practice it is almost always written on one long line.
-- Arguments (1-indexed):
--   1  Tileset
--   2  MapName_MapAttributes    (derived — not user-editable here)
--   3  MapName_MapScriptHeader  (derived)
--   4  MapName_MapEvents        (derived)
--   5  MapName_MapConnections   (derived)
--   6  MapName_MapBlocks        (derived)
--   7  MUSIC_* constant         (editable)
--   8  MAP_* constant           (editable — the map ID)
--   9  MAP_SCENE_* constant     (editable)
--   10 land flag (0 or 1)       (editable)
--
-- We only expose the editable fields: tileset, music, mapConst, sceneConst, land.
--
-- Public API
-- ----------
--   Gen2Header.parse(text)                  -> parsed
--   Gen2Header.serialize(parsed, edits)     -> newText
--   Gen2Header.read(path)                   -> (parsed, err)
--   Gen2Header.write(path, parsed, edits)   -> (ok, err)
--
-- `edits` may contain any subset of:
--   { tileset, music, mapConst, sceneConst, land }

local Util = require("edit_map.util")

local Gen2Header = {}

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

-- Split a `map_header` argument list into individual args, handling the fact
-- that the line might contain line-continuation backslashes.
local function parseArgs(argStr)
  -- Remove backslash-newline continuations.
  local s = argStr:gsub("\\%s*\n%s*", " ")
  local parts = {}
  for p in s:gmatch("([^,]+)") do
    table.insert(parts, Util.trim(p))
  end
  return parts
end

function Gen2Header.parse(text)
  local lines = Util.splitLines(text)
  local parsed = {
    lines      = lines,
    tileset    = "",
    music      = "",
    mapConst   = "",
    sceneConst = "",
    land       = "0",
    headerLine = nil,   -- 1-based line index of the map_header macro
    rawArgs    = {},    -- all 10 parsed arg strings (for round-trip fidelity)
  }

  local i = 1
  while i <= #lines do
    local code = Util.stripComment(lines[i])

    if code:match("^%s*map_header%s") then
      -- Collect potential continuation lines.
      local full = code
      local j = i
      while full:match("\\%s*$") and j < #lines do
        j = j + 1
        full = full:gsub("\\%s*$", "") .. " " .. Util.stripComment(lines[j])
      end

      local argStr = full:match("map_header%s+(.+)$") or ""
      local args = parseArgs(argStr)

      parsed.rawArgs    = args
      parsed.tileset    = args[1] or ""
      -- args[2..6] are derived labels — skip
      parsed.music      = args[7] or ""
      parsed.mapConst   = args[8] or ""
      parsed.sceneConst = args[9] or ""
      parsed.land       = args[10] or "0"
      parsed.headerLine = i
      break
    end

    i = i + 1
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Serializer
-- ---------------------------------------------------------------------------

function Gen2Header.serialize(parsed, edits)
  edits = edits or {}
  local lines = {}
  for _, l in ipairs(parsed.lines) do table.insert(lines, l) end

  if not parsed.headerLine then
    return Util.joinLines(lines)
  end

  local args = {}
  for _, a in ipairs(parsed.rawArgs) do
    table.insert(args, a)
  end

  -- Patch only the editable positions.
  if edits.tileset    then args[1]  = edits.tileset    end
  if edits.music      then args[7]  = edits.music      end
  if edits.mapConst   then args[8]  = edits.mapConst   end
  if edits.sceneConst then args[9]  = edits.sceneConst end
  if edits.land       then args[10] = edits.land       end

  -- Rebuild as a single long line.
  local newMacro = "map_header " .. table.concat(args, ", ")
  lines[parsed.headerLine] = Util.replaceLineKeepingComment(
    lines[parsed.headerLine], newMacro
  )

  return Util.joinLines(lines)
end

-- ---------------------------------------------------------------------------
-- Read / Write helpers
-- ---------------------------------------------------------------------------

function Gen2Header.read(path)
  local text, err = pt.file.read(path)
  if not text then
    return nil, err or ("cannot read " .. path)
  end
  local ok, result = pcall(Gen2Header.parse, text)
  if not ok then
    return nil, "parse error: " .. tostring(result)
  end
  return result, nil
end

function Gen2Header.write(path, parsed, edits)
  local newText = Gen2Header.serialize(parsed, edits)
  local ok, err = pt.file.write(path, newText)
  if not ok then
    return false, err or ("cannot write " .. path)
  end
  return true, nil
end

return Gen2Header
