-- gen1_edit_map/header.lua
-- Parse and write Gen1 (pokered) map header files — CURRENT pret/pokered format.
--
-- File format (data/maps/headers/{MapId}.asm):
--
--   	map_header PalletTown, PALLET_TOWN, OVERWORLD, NORTH | SOUTH
--   	connection north, Route1, ROUTE_1, 0
--   	connection south, Route21, ROUTE_21, 0
--   	end_map_header
--
-- map_header args: MapName, MAP_CONST, TILESET_CONST, CONN_FLAGS
-- connection args: dir, DestMapFile, DEST_MAP_CONST, offset
--
-- Public API:
--   Header.parse(text)             → parsed
--   Header.serialize(parsed, edits)→ newText
--   Header.read(path)              → (parsed, err)
--   Header.write(path, parsed, edits) → (ok, err)
--
-- `parsed` fields:
--   lines, mapName, mapConst, tileset, connFlags,
--   headerLine,  -- 1-based index of the map_header macro line
--   connections = { north={dir,dest,destConst,offset,line}, ... }
--
-- `edits` (all optional):
--   { tileset, connFlags,
--     connections = { north={dest,destConst,offset} | false, ... } }

local Util = require("gen1_edit_map.util")

local Header = {}

local DIRS = { "north", "south", "east", "west" }

local DIR_FLAGS = { north="NORTH", south="SOUTH", east="EAST", west="WEST" }

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

local function parseHeaderLine(code)
  -- map_header MapName, MAP_CONST, TILESET, CONN_FLAGS
  local args = code:match("map_header%s+(.+)$")
  if not args then return nil end
  local parts = {}
  for p in args:gmatch("([^,]+)") do
    table.insert(parts, Util.trim(p))
  end
  if #parts < 3 then return nil end
  -- Parts 4+ form connFlags (may contain | separators)
  local connFlags = #parts >= 4 and table.concat(parts, ", ", 4) or "0"
  return {
    mapName   = parts[1],
    mapConst  = parts[2],
    tileset   = parts[3],
    connFlags = connFlags,
  }
end

local function parseConnectionLine(code)
  -- connection dir, DestMapFile, DEST_MAP_CONST, offset
  local args = code:match("connection%s+(.+)$")
  if not args then return nil end
  local parts = {}
  for p in args:gmatch("([^,]+)") do
    table.insert(parts, Util.trim(p))
  end
  if #parts < 4 then return nil end
  return {
    dir      = parts[1]:lower(),
    dest     = parts[2],
    destConst= parts[3],
    offset   = parts[4],
  }
end

function Header.parse(text)
  local lines = Util.splitLines(text)
  local parsed = {
    lines       = lines,
    mapName     = "",
    mapConst    = "",
    tileset     = "",
    connFlags   = "0",
    headerLine  = nil,
    connections = {},
  }

  for i, line in ipairs(lines) do
    local code = Util.stripComment(line)

    if not parsed.headerLine and code:match("^%s*map_header%s") then
      local h = parseHeaderLine(code)
      if h then
        parsed.mapName    = h.mapName
        parsed.mapConst   = h.mapConst
        parsed.tileset    = h.tileset
        parsed.connFlags  = h.connFlags
        parsed.headerLine = i
      end

    elseif code:match("^%s*connection%s") then
      local c = parseConnectionLine(code)
      if c then
        c.line = i
        parsed.connections[c.dir] = c
      end
    end
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Serializer
-- ---------------------------------------------------------------------------

local function buildConnFlags(connections)
  local flags = {}
  for _, dir in ipairs(DIRS) do
    if connections[dir] then
      table.insert(flags, DIR_FLAGS[dir])
    end
  end
  return #flags > 0 and table.concat(flags, " | ") or "0"
end

function Header.serialize(parsed, edits)
  edits = edits or {}

  local lines = {}
  for _, l in ipairs(parsed.lines) do
    table.insert(lines, l)
  end

  local tileset   = edits.tileset   or parsed.tileset   or ""
  local mapName   = parsed.mapName  or ""
  local mapConst  = parsed.mapConst or ""

  -- Merge connection edits.
  local finalConns = {}
  for dir, conn in pairs(parsed.connections) do
    finalConns[dir] = Util.shallowCopy(conn)
  end
  if edits.connections then
    for dir, v in pairs(edits.connections) do
      if v == false then
        finalConns[dir] = nil
      elseif type(v) == "table" then
        finalConns[dir] = Util.shallowCopy(v)
        finalConns[dir].dir = dir
      end
    end
  end

  local connFlags = edits.connFlags or buildConnFlags(finalConns)

  -- Rewrite the map_header line.
  if parsed.headerLine then
    local indent = Util.indentOf(lines[parsed.headerLine])
    lines[parsed.headerLine] = string.format(
      "%smap_header %s, %s, %s, %s",
      indent, mapName, mapConst, tileset, connFlags
    )
  end

  -- Rewrite existing connection lines.
  for dir, conn in pairs(parsed.connections) do
    if conn.line then
      if finalConns[dir] then
        local fc = finalConns[dir]
        local indent = Util.indentOf(lines[conn.line])
        lines[conn.line] = string.format(
          "%sconnection %s, %s, %s, %s",
          indent, dir, fc.dest or conn.dest, fc.destConst or conn.destConst, fc.offset or conn.offset
        )
      else
        -- Delete this connection line (and possibly the label above it).
        lines[conn.line] = nil
      end
    end
  end

  -- Add new connection entries (those in finalConns not already in parsed).
  local toAdd = {}
  for dir, fc in pairs(finalConns) do
    if not parsed.connections[dir] then
      table.insert(toAdd, fc)
    end
  end
  -- Insert new connections before end_map_header.
  if #toAdd > 0 then
    local insertAt = #lines
    for i, line in ipairs(lines) do
      if line and Util.stripComment(line):match("^%s*end_map_header") then
        insertAt = i - 1
        break
      end
    end
    local baseIndent = "\t"
    if parsed.headerLine then
      baseIndent = Util.indentOf(lines[parsed.headerLine] or "")
    end
    for _, fc in ipairs(toAdd) do
      local newLine = string.format(
        "%sconnection %s, %s, %s, %s",
        baseIndent, fc.dir or "north", fc.dest or "", fc.destConst or "", fc.offset or "0"
      )
      table.insert(lines, insertAt + 1, newLine)
      insertAt = insertAt + 1
    end
  end

  -- Compact nil'd lines.
  local result = {}
  for _, l in ipairs(lines) do
    if l ~= nil then table.insert(result, l) end
  end

  return Util.joinLines(result)
end

-- ---------------------------------------------------------------------------
-- I/O
-- ---------------------------------------------------------------------------

function Header.read(path)
  local text, err = pt.file.read(path)
  if not text then return nil, err or "Could not read " .. path end
  return Header.parse(text), nil
end

function Header.write(path, parsed, edits)
  local newText = Header.serialize(parsed, edits)
  local ok, err = pt.file.write(path, newText)
  if not ok then return false, err end
  return true, nil
end

return Header
