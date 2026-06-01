-- Parses and serializes Gen-1 (pokered) map header files.
--
-- Format of data/mapHeaders/{mapId}.asm:
--
--   PelletTown_h:
--       map_header PelletTownTileset, PELLET_TOWN_HEIGHT, PELLET_TOWN_WIDTH, NORTH | SOUTH
--
--   PelletTown_connection_north:
--       connection north, Route1Blocks, Route1_h, -1
--
--   PelletTown_connection_south:
--       connection south, AnotherMapBlocks, AnotherMap_h, 5
--
-- The `map_header` macro takes: Tileset, HeightConst, WidthConst, ConnectionFlags
-- Each `connection` macro takes: direction, DestBlocks, DestHeader, offset
--
-- Direction names match the flags in the connection flags field:
--   NORTH, SOUTH, EAST, WEST  (or 0 for no connections)
--
-- Public API
-- ----------
--   Gen1Header.parse(text)                  -> parsed
--   Gen1Header.serialize(parsed, edits)     -> newText
--   Gen1Header.read(path)                   -> (parsed, err)
--   Gen1Header.write(path, parsed, edits)   -> (ok, err)
--
-- `edits` may contain any subset of:
--   { tileset, height, width, connFlags,
--     connections = {
--       north = { destBlocks, destHeader, offset } | false,  -- false = delete
--       south = ...,
--       east  = ...,
--       west  = ...,
--     }
--   }
-- Setting a direction to `false` removes it; providing a new table adds or
-- replaces it (and the connFlags bitfield is recomputed automatically).

local Util = require("edit_map.util")

local Gen1Header = {}

-- All four direction names we handle.
local DIRS = { "north", "south", "east", "west" }

-- The corresponding flag names used in the connection bitfield.
local DIR_FLAGS = {
  north = "NORTH",
  south = "SOUTH",
  east  = "EAST",
  west  = "WEST",
}

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

-- Parse a `map_header` macro line into its four components.
-- Returns nil on failure.
local function parseMapHeaderLine(code)
  -- map_header Tileset, HEIGHT, WIDTH, ConnFlags
  local args = code:match("map_header%s+(.+)$")
  if not args then return nil end
  local parts = {}
  for p in args:gmatch("([^,]+)") do
    table.insert(parts, Util.trim(p))
  end
  if #parts < 4 then return nil end
  -- connFlags may contain " | " separators, already captured as single string.
  return {
    tileset   = parts[1],
    height    = parts[2],
    width     = parts[3],
    connFlags = table.concat(parts, ", ", 4),
  }
end

-- Parse a `connection` macro line into its components.
local function parseConnectionLine(code)
  -- connection dir, DestBlocks, DestHeader, offset
  local args = code:match("connection%s+(.+)$")
  if not args then return nil end
  local parts = {}
  for p in args:gmatch("([^,]+)") do
    table.insert(parts, Util.trim(p))
  end
  if #parts < 4 then return nil end
  return {
    dir        = parts[1]:lower(),
    destBlocks = parts[2],
    destHeader = parts[3],
    offset     = parts[4],
  }
end

-- Parse the full header file text and return a structured table.
-- All 1-based line indices are stored so the serializer can rewrite
-- precisely the right lines.
function Gen1Header.parse(text)
  local lines = Util.splitLines(text)
  local parsed = {
    lines       = lines,
    tileset     = "",
    height      = "",
    width       = "",
    connFlags   = "0",
    headerLine  = nil,    -- 1-based line index of the `map_header` macro
    connections = {},     -- keyed by direction string
  }

  local i = 1
  while i <= #lines do
    local code = Util.stripComment(lines[i])

    -- map_header macro
    if not parsed.headerLine and code:match("^%s*map_header%s") then
      local h = parseMapHeaderLine(code)
      if h then
        parsed.tileset    = h.tileset
        parsed.height     = h.height
        parsed.width      = h.width
        parsed.connFlags  = h.connFlags
        parsed.headerLine = i
      end

    -- connection macro
    elseif code:match("^%s*connection%s") then
      local c = parseConnectionLine(code)
      if c then
        -- The label for this connection is typically on the previous line.
        local labelLine = i - 1
        while labelLine >= 1 and Util.trim(lines[labelLine]) == "" do
          labelLine = labelLine - 1
        end
        -- Only use as the label line if it actually looks like a label.
        if labelLine >= 1 and lines[labelLine]:match(":%s*$") then
          c.labelLine = labelLine
        else
          c.labelLine = nil
        end
        c.macroLine = i
        parsed.connections[c.dir] = c
      end
    end

    i = i + 1
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Serializer
-- ---------------------------------------------------------------------------

-- Recompute the connection-flags string from the final set of directions.
local function buildConnFlags(connections)
  local flags = {}
  for _, dir in ipairs(DIRS) do
    if connections[dir] then
      table.insert(flags, DIR_FLAGS[dir])
    end
  end
  if #flags == 0 then return "0" end
  return table.concat(flags, " | ")
end

-- Build the `map_header` macro string (without leading whitespace).
local function mapHeaderMacro(tileset, height, width, connFlags)
  return string.format("map_header %s, %s, %s, %s",
    tileset, height, width, connFlags)
end

-- Build a `connection` macro string (without leading whitespace).
local function connectionMacro(dir, destBlocks, destHeader, offset)
  return string.format("connection %s, %s, %s, %s",
    dir, destBlocks, destHeader, offset)
end

-- Apply `edits` to `parsed` and return the new file text.
function Gen1Header.serialize(parsed, edits)
  edits = edits or {}
  local lines = {}
  for _, l in ipairs(parsed.lines) do
    table.insert(lines, l)
  end

  -- Apply simple field edits.
  local tileset   = edits.tileset   or parsed.tileset   or ""
  local height    = edits.height    or parsed.height    or ""
  local width     = edits.width     or parsed.width     or ""

  -- Merge connection edits into a working copy of parsed connections.
  local finalConns = {}
  for dir, conn in pairs(parsed.connections) do
    finalConns[dir] = conn
  end
  if edits.connections then
    for dir, v in pairs(edits.connections) do
      if v == false then
        finalConns[dir] = nil
      elseif type(v) == "table" then
        finalConns[dir] = {
          dir        = dir,
          destBlocks = v.destBlocks,
          destHeader = v.destHeader,
          offset     = tostring(v.offset or 0),
          labelLine  = (finalConns[dir] or {}).labelLine,
          macroLine  = (finalConns[dir] or {}).macroLine,
        }
      end
    end
  end

  local connFlags = edits.connFlags or buildConnFlags(finalConns)

  -- 1. Rewrite the map_header macro line.
  if parsed.headerLine then
    lines[parsed.headerLine] = Util.replaceLineKeepingComment(
      lines[parsed.headerLine],
      mapHeaderMacro(tileset, height, width, connFlags)
    )
  end

  -- 2. For existing connections that survive, update their macro lines.
  for dir, conn in pairs(finalConns) do
    if conn.macroLine then
      lines[conn.macroLine] = Util.replaceLineKeepingComment(
        lines[conn.macroLine],
        connectionMacro(conn.dir, conn.destBlocks, conn.destHeader, conn.offset)
      )
    end
  end

  -- 3. Mark lines belonging to deleted connections for removal.
  --    Collect line indices to delete (label + macro).
  local toDelete = {}
  for dir, conn in pairs(parsed.connections) do
    if not finalConns[dir] then
      if conn.macroLine then toDelete[conn.macroLine] = true end
      if conn.labelLine  then toDelete[conn.labelLine]  = true end
      -- Also remove a blank line immediately before the label, if present.
      local bl = (conn.labelLine or conn.macroLine or 1) - 1
      if bl >= 1 and Util.trim(lines[bl]) == "" then
        toDelete[bl] = true
      end
    end
  end

  -- 4. Build output lines, skipping deleted ones.
  local out = {}
  for i, l in ipairs(lines) do
    if not toDelete[i] then
      table.insert(out, l)
    end
  end

  -- 5. Append new connections that were not in the original file.
  local anchor = (parsed.headerLine or #out)
  local inserts = {}
  for dir, conn in pairs(finalConns) do
    if not conn.macroLine then
      -- Build the conventional label name from the header label on line before map_header.
      -- We detect the map name from the header label (e.g. "PelletTown_h:").
      local mapLabel = ""
      if parsed.headerLine then
        local hl = (parsed.headerLine or 1) - 1
        while hl >= 1 and lines[hl] and not lines[hl]:match(":%s*$") do
          hl = hl - 1
        end
        if hl >= 1 and lines[hl] then
          mapLabel = lines[hl]:match("^%s*([%w_]+)_h:%s*$") or ""
        end
      end
      local label = mapLabel ~= "" and (mapLabel .. "_connection_" .. dir .. ":") or ("connection_" .. dir .. ":")
      table.insert(inserts, "")
      table.insert(inserts, label)
      table.insert(inserts, "\t" .. connectionMacro(dir, conn.destBlocks, conn.destHeader, conn.offset))
    end
  end

  -- Insert after the header section (find the end of the map_header block).
  if #inserts > 0 then
    -- Find the insertion point: after the last line of the parsed block.
    -- Simple heuristic: after `anchor`, find the first blank line.
    local insertAt = #out
    for i = anchor, #out do
      if Util.trim(out[i]) == "" then
        insertAt = i - 1
        break
      end
    end
    local final = {}
    for i = 1, insertAt do
      table.insert(final, out[i])
    end
    for _, l in ipairs(inserts) do
      table.insert(final, l)
    end
    for i = insertAt + 1, #out do
      table.insert(final, out[i])
    end
    out = final
  end

  return Util.joinLines(out)
end

-- ---------------------------------------------------------------------------
-- Read / Write helpers
-- ---------------------------------------------------------------------------

function Gen1Header.read(path)
  local text, err = pt.file.read(path)
  if not text then
    return nil, err or ("cannot read " .. path)
  end
  local ok, result = pcall(Gen1Header.parse, text)
  if not ok then
    return nil, "parse error: " .. tostring(result)
  end
  return result, nil
end

function Gen1Header.write(path, parsed, edits)
  local newText = Gen1Header.serialize(parsed, edits)
  local ok, err = pt.file.write(path, newText)
  if not ok then
    return false, err or ("cannot write " .. path)
  end
  return true, nil
end

return Gen1Header
