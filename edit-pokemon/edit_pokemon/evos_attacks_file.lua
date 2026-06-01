-- Reads and writes blocks in `data/pokemon/evos_attacks.asm`
-- (or `evos_moves.asm` in pokered).
--
-- Each Pokemon has a block that looks like this:
--
--   BulbasaurEvosAttacks:
--       db EVOLVE_LEVEL, 16, IVYSAUR
--       db 0                          ; terminator for evolutions
--       db 1, TACKLE
--       db 1, GROWL
--       db 7, LEECH_SEED
--       db 0                          ; terminator for level-up moves
--
--   IvysaurEvosAttacks:
--       ...
--
-- The two `db 0` lines split the block into the "evolutions" half and the
-- "level-up moves" half.
--
-- Methods:
--   * pokecrystal uses EVOLVE_LEVEL, EVOLVE_ITEM, EVOLVE_TRADE, ...
--   * pokered    uses EV_LEVEL,     EV_ITEM,     EV_TRADE,     ...
--
-- The reader accepts either. The writer adds the right prefix when the
-- user types a bare method name (e.g. "LEVEL" -> "EVOLVE_LEVEL").

local Util = require("edit_pokemon.util")

local EvosAttacks = {}

-- ---------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------

-- Find a `<Label>:` line and the line of the next `<Label>:` after it.
-- Returns (lines, start, stop) or nil. `stop` is the last line of the
-- block (the line *before* the next label).
local function findLabelBlock(text, labelPatterns)
  local lines = Util.splitLines(text)

  local start
  for i, line in ipairs(lines) do
    for _, pattern in ipairs(labelPatterns) do
      if line:match(pattern) then
        start = i
        break
      end
    end
    if start then break end
  end

  if not start then return nil end

  local stop = #lines
  for j = start + 1, #lines do
    if lines[j]:match("^[%w_]+:") then
      stop = j - 1
      break
    end
  end

  return lines, start, stop
end

-- Try to figure out the indentation used by `db` lines inside a block.
-- Defaults to a single tab if we can't tell.
local function detectIndent(lines, startIdx, stopIdx)
  for i = startIdx + 1, stopIdx do
    local indent = lines[i]:match("^(%s+)db")
    if indent then return indent end
  end
  return "\t"
end

-- ---------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------

-- Read one Pokemon's block out of evos_attacks.asm.
-- Returns a table:
--
--   {
--     evolutions = { { "EVOLVE_LEVEL", "16", "IVYSAUR" }, ... },
--     moves      = { { level = 1, move = "TACKLE" }, ... },
--     lines      = { ... entire file as a list of lines ... },
--     blockStart = 23,    -- 1-based, the label line
--     blockStop  = 30,    -- 1-based, last line of the block
--     missing    = false, -- true if no label was found
--   }
function EvosAttacks.read(filePath, pascalName)
  local text, err = pt.file.read(filePath)
  if not text then return nil, err end

  local lines, start, stop = findLabelBlock(text, {
    "^" .. pascalName .. "EvosAttacks:",
    "^" .. pascalName .. "EvosMoves:",
  })
  if not lines then
    return { evolutions = {}, moves = {}, missing = true }
  end

  local evolutions = {}
  local moves = {}
  local seenEvoTerminator = false

  for i = start + 1, stop do
    local code = Util.stripComment(lines[i])
    local body = code:match("^%s*db%s+(.+)$")
    if body then
      -- Split "EVOLVE_LEVEL, 16, IVYSAUR" into { "EVOLVE_LEVEL", "16", "IVYSAUR" }
      local parts = {}
      for p in body:gmatch("([^,]+)") do
        table.insert(parts, Util.trim(p))
      end

      local first = parts[1]
      local isTerminator = (#parts == 1 and first == "0")
      local isEvolution  = (first and (first:match("^EVOLVE_") or first:match("^EV_")))
      local isMove       = (#parts == 2 and tonumber(first) ~= nil)

      if isTerminator then
        seenEvoTerminator = true
      elseif not seenEvoTerminator and isEvolution then
        table.insert(evolutions, parts)
      elseif seenEvoTerminator and isMove then
        table.insert(moves, { level = tonumber(first), move = parts[2] })
      end
    end
  end

  return {
    evolutions = evolutions,
    moves      = moves,
    lines      = lines,
    blockStart = start,
    blockStop  = stop,
    missing    = false,
  }
end

-- ---------------------------------------------------------------
-- Parsing the user-edited text areas
-- ---------------------------------------------------------------

-- Each move line in the text area must look like "<level> <MOVE_CONSTANT>".
-- Returns (moves, nil) or (nil, errorMessage).
function EvosAttacks.parseMovesText(text)
  local moves = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = Util.trim(line)
    if stripped ~= "" and not stripped:match("^;") then
      local level, move = stripped:match("^(%d+)%s+([%w_]+)$")
      if not level then
        return nil, "Move line must be '<level> <MOVE_CONSTANT>': '" .. stripped .. "'"
      end
      table.insert(moves, { level = tonumber(level), move = move })
    end
  end
  return moves, nil
end

-- Each evolution line is "<METHOD> <param>... <TARGET>". The user is
-- allowed to drop the EVOLVE_ / EV_ prefix; we add the right one for the
-- project's generation.
function EvosAttacks.parseEvosText(text, isGen2)
  local prefix = isGen2 and "EVOLVE_" or "EV_"
  local evolutions = {}

  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = Util.trim(line)
    if stripped ~= "" and not stripped:match("^;") then
      local parts = {}
      for p in stripped:gmatch("[^%s,]+") do
        table.insert(parts, p)
      end
      if #parts < 2 then
        return nil, "Evolution line must be '<METHOD> <param>... <TARGET>': '" .. stripped .. "'"
      end
      if not parts[1]:match("^EVOLVE_") and not parts[1]:match("^EV_") then
        parts[1] = prefix .. parts[1]
      end
      table.insert(evolutions, parts)
    end
  end

  return evolutions, nil
end

-- ---------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------

-- Build a new file text that replaces just this Pokemon's block.
function EvosAttacks.rebuild(block, newEvolutions, newMoves)
  local indent = detectIndent(block.lines, block.blockStart, block.blockStop)

  local rewritten = { block.lines[block.blockStart] }

  for _, evo in ipairs(newEvolutions) do
    table.insert(rewritten, indent .. "db " .. table.concat(evo, ", "))
  end
  table.insert(rewritten, indent .. "db 0 ; no more evolutions")

  for _, mv in ipairs(newMoves) do
    table.insert(rewritten, indent .. "db " .. tostring(mv.level) .. ", " .. mv.move)
  end
  table.insert(rewritten, indent .. "db 0 ; no more level-up moves")

  local result = {}
  for i = 1, block.blockStart - 1 do
    table.insert(result, block.lines[i])
  end
  for _, line in ipairs(rewritten) do
    table.insert(result, line)
  end
  for i = block.blockStop + 1, #block.lines do
    table.insert(result, block.lines[i])
  end

  return Util.joinLines(result)
end

-- Convenience: rebuild + write to disk. Returns (ok, err).
function EvosAttacks.write(path, block, newEvolutions, newMoves)
  local text = EvosAttacks.rebuild(block, newEvolutions, newMoves)
  return pt.file.write(path, text)
end

return EvosAttacks
