-- Reads and writes blocks in `data/pokemon/egg_moves.asm` (gen-2 only).
--
-- Each Pokemon's egg moves are written like this:
--
--   BulbasaurEggMoves:
--       db CHARM
--       db CURSE
--       db GRASS_WHISTLE
--       db -1                  ; terminator
--
-- pokered does not have egg moves, so this module is unused for gen-1.

local Util = require("edit_pokemon.util")

local EggMoves = {}

local function findLabelBlock(text, labelPattern)
  local lines = Util.splitLines(text)

  local start
  for i, line in ipairs(lines) do
    if line:match(labelPattern) then
      start = i
      break
    end
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

local function detectIndent(lines, startIdx, stopIdx)
  for i = startIdx + 1, stopIdx do
    local indent = lines[i]:match("^(%s+)db")
    if indent then return indent end
  end
  return "\t"
end

-- Read one Pokemon's egg moves block.
function EggMoves.read(filePath, pascalName)
  if not filePath then return nil end

  local text, err = pt.file.read(filePath)
  if not text then return nil, err end

  local lines, start, stop = findLabelBlock(text, "^" .. pascalName .. "EggMoves:")
  if not lines then
    return { moves = {}, missing = true }
  end

  local moves = {}
  for i = start + 1, stop do
    local code = Util.stripComment(lines[i])
    local name = code:match("^%s*db%s+([%-%$%w_]+)%s*$")
    -- Skip the terminator lines (`db -1` or `db $ff`).
    if name and name ~= "-1" and name:lower() ~= "$ff" then
      table.insert(moves, name)
    end
  end

  return {
    moves      = moves,
    lines      = lines,
    blockStart = start,
    blockStop  = stop,
    missing    = false,
  }
end

-- Validate the user's text area: every non-empty, non-comment line must
-- be a single move constant. Returns (moves, nil) or (nil, errorMessage).
function EggMoves.parseText(text)
  local moves = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = Util.trim(line)
    if stripped ~= "" and not stripped:match("^;") then
      if not stripped:match("^[%w_]+$") then
        return nil, "Egg move line must be a single move constant: '" .. stripped .. "'"
      end
      table.insert(moves, stripped)
    end
  end
  return moves, nil
end

-- Build new file text with this Pokemon's block replaced.
function EggMoves.rebuild(block, newMoves)
  local indent = detectIndent(block.lines, block.blockStart, block.blockStop)

  local rewritten = { block.lines[block.blockStart] }
  for _, mv in ipairs(newMoves) do
    table.insert(rewritten, indent .. "db " .. mv)
  end
  table.insert(rewritten, indent .. "db -1 ; end")

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

-- Convenience: rebuild + write. Returns (ok, err).
function EggMoves.write(path, block, newMoves)
  local text = EggMoves.rebuild(block, newMoves)
  return pt.file.write(path, text)
end

return EggMoves
