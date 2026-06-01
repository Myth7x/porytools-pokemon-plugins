-- Reads and writes one Pokemon's base_stats/*.asm file.
--
-- A base stats file looks roughly like this (pokecrystal example):
--
--   BulbasaurBaseStats:
--       db DEX_BULBASAUR ; pokedex id
--       db 45, 49, 49, 45, 65, 65   ; hp atk def spd spa spdef
--       db GRASS, POISON ; type
--       db 45            ; catch rate
--       db 64            ; base exp
--       db NO_ITEM, NO_ITEM ; held items
--       db GENDER_F12_5  ; gender ratio
--       db 100 ; unknown 1
--       db 20  ; step cycles to hatch
--       db 5   ; unknown 2
--       INCBIN "gfx/pokemon/bulbasaur/front.dimensions"
--       db 64, 64        ; padding
--       db GROWTH_MEDIUM_SLOW ; growth rate
--       dn EGG_MONSTER, EGG_PLANT ; egg groups
--       ...
--
-- pokered files are similar but only have 5 stats (no Sp.Def) and use
-- slightly different fields. The parser handles both.
--
-- The parser is forgiving on purpose: it walks the file looking for the
-- shapes it knows about (a `db` with 5 or 6 numbers is the stats line,
-- a `db NAME, NAME` after that is the types line, etc.). It stores the
-- line *index* of each field so we can later rewrite just those lines and
-- leave the rest of the file untouched.

local Util       = require("edit_pokemon.util")

local BaseStats = {}

-- The keys we use for each stat slot, in file order.
BaseStats.STAT_KEYS_GEN2 = { "hp", "atk", "def", "spd", "spa", "spdef" }
BaseStats.STAT_KEYS_GEN1 = { "hp", "atk", "def", "spd", "spc" }

-- ---------------------------------------------------------------
-- Tiny line-level helpers
-- ---------------------------------------------------------------

-- If `line` is `db <num>, <num>, ...` return the list of numbers.
-- Otherwise return nil.
local function dbNumbers(line)
  local code = Util.stripComment(line)
  local body = code:match("^%s*db%s+(.+)$")
  if not body then return nil end

  local nums = {}
  for part in body:gmatch("([^,]+)") do
    local n = tonumber(Util.trim(part))
    if not n then return nil end
    table.insert(nums, n)
  end
  return nums
end

-- If `line` is `db NAME, NAME, ...` return the list of names.
-- Otherwise return nil.
local function dbNames(line)
  local code = Util.stripComment(line)
  local body = code:match("^%s*db%s+(.+)$")
  if not body then return nil end

  local names = {}
  for part in body:gmatch("([^,]+)") do
    local name = Util.trim(part)
    if not name:match("^[%a_][%w_]*$") then return nil end
    table.insert(names, name)
  end
  return names
end

-- Type names from the project's constants file. Pass an empty list to
-- accept any name (useful when we couldn't find the constants file).
local function makeTypeChecker(typeList)
  if #typeList == 0 then
    return function() return true end
  end
  local set = {}
  for _, name in ipairs(typeList) do set[name] = true end
  return function(name) return set[name] == true end
end

-- ---------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------

-- Parse one base stats file's text. Returns a table:
--
--   {
--     lines  = { ... },         -- every line of the file, in order
--     stats  = { 45, 49, ... }, -- numbers from the stats line, or nil
--     types  = { "GRASS", "POISON" }, -- or nil
--     catch  = 45,              -- single number, or nil
--     exp    = 64,              -- single number, or nil
--     items  = { "NO_ITEM", "NO_ITEM" }, -- gen-2 only, or nil
--     gender = "GENDER_F12_5",  -- gen-2 only, or nil
--     growth = "GROWTH_MEDIUM_SLOW", -- nil if not found
--     eggGroups = { "EGG_MONSTER", "EGG_PLANT" }, -- gen-2 only, or nil
--
--     statsLine = 3, typesLine = 4, catchLine = 5, expLine = 6,
--     itemsLine = 7, genderLine = 8, growthLine = 14, eggLine = 15,
--   }
--
-- Any field that isn't found is left nil and won't be rewritten on save.
function BaseStats.parse(text, knownTypes)
  local lines = Util.splitLines(text)
  local result = { lines = lines }
  local isKnownType = makeTypeChecker(knownTypes or {})

  -- Step 1: the stats line is the first `db` with 5 or 6 plain numbers.
  local i = 1
  while i <= #lines do
    local nums = dbNumbers(lines[i])
    if nums and (#nums == 5 or #nums == 6) then
      result.statsLine = i
      result.stats = nums
      i = i + 1
      break
    end
    i = i + 1
  end

  if not result.statsLine then
    return result
  end

  -- Step 2: types — the next `db NAME, NAME` where at least one name is a
  -- known type constant.
  while i <= #lines do
    local names = dbNames(lines[i])
    if names and #names == 2
       and (isKnownType(names[1]) or isKnownType(names[2])) then
      result.typesLine = i
      result.types = names
      i = i + 1
      break
    end
    i = i + 1
  end

  -- Step 3: catch rate — next single-integer `db`.
  while i <= #lines do
    local nums = dbNumbers(lines[i])
    if nums and #nums == 1 then
      result.catchLine = i
      result.catch = nums[1]
      i = i + 1
      break
    end
    i = i + 1
  end

  -- Step 4: base exp — the next single-integer `db` after catch.
  while i <= #lines do
    local nums = dbNumbers(lines[i])
    if nums and #nums == 1 then
      result.expLine = i
      result.exp = nums[1]
      i = i + 1
      break
    end
    i = i + 1
  end

  if #result.stats == 6 then
    -- gen-2 only: items, gender, growth and egg groups.
    -- Items line: next `db NAME, NAME` with any two names.
    local j = i
    while j <= #lines do
      local names = dbNames(lines[j])
      if names and #names == 2 then
        result.itemsLine = j
        result.items = names
        j = j + 1
        break
      end
      j = j + 1
    end

    -- Gender, growth and egg groups can be matched anywhere by their
    -- prefix because the constant names are distinctive enough.
    while j <= #lines do
      local code = Util.stripComment(lines[j])

      if not result.genderLine then
        local g = code:match("^%s*db%s+(GENDER_[%w_]+)")
        if g then result.genderLine = j; result.gender = g end
      end
      if not result.growthLine then
        local g = code:match("^%s*db%s+(GROWTH_[%w_]+)")
        if g then result.growthLine = j; result.growth = g end
      end
      if not result.eggLine then
        local e1, e2 = code:match("^%s*dn%s+(EGG_[%w_]+)%s*,%s*(EGG_[%w_]+)")
        if e1 then
          result.eggLine = j
          result.eggGroups = { e1, e2 }
        end
      end
      j = j + 1
    end
  else
    -- gen-1 only: growth rate is a single `db GROWTH_...` after base exp.
    while i <= #lines do
      local code = Util.stripComment(lines[i])
      local g = code:match("^%s*db%s+(GROWTH_[%w_]+)")
      if g then
        result.growthLine = i
        result.growth = g
        break
      end
      i = i + 1
    end
  end

  return result
end

-- ---------------------------------------------------------------
-- Serializing
-- ---------------------------------------------------------------

-- Rewrite the parsed file with the user's edits.
--
-- `edits` is a table with the same shape as the parsed result, but with
-- only the fields the user wants to change. Lines we don't recognise are
-- left alone, comments on the edited lines are preserved.
function BaseStats.serialize(parsed, edits)
  local lines = {}
  for i, l in ipairs(parsed.lines) do
    lines[i] = l
  end

  local function setLine(idx, newCode)
    if idx then
      lines[idx] = Util.replaceLineKeepingComment(lines[idx], newCode)
    end
  end

  if edits.stats then
    setLine(parsed.statsLine, "db " .. table.concat(edits.stats, ", "))
  end
  if edits.types then
    setLine(parsed.typesLine, "db " .. edits.types[1] .. ", " .. edits.types[2])
  end
  if edits.catch then
    setLine(parsed.catchLine, "db " .. tostring(edits.catch))
  end
  if edits.exp then
    setLine(parsed.expLine, "db " .. tostring(edits.exp))
  end
  if edits.items then
    setLine(parsed.itemsLine, "db " .. edits.items[1] .. ", " .. edits.items[2])
  end
  if edits.gender then
    setLine(parsed.genderLine, "db " .. edits.gender)
  end
  if edits.growth then
    setLine(parsed.growthLine, "db " .. edits.growth)
  end
  if edits.eggGroups then
    setLine(parsed.eggLine, "dn " .. edits.eggGroups[1] .. ", " .. edits.eggGroups[2])
  end

  return Util.joinLines(lines)
end

-- Read + parse the file in one call. Returns (parsed, nil) or (nil, err).
function BaseStats.read(path, knownTypes)
  local text, err = pt.file.read(path)
  if not text then
    return nil, err
  end
  return BaseStats.parse(text, knownTypes), nil
end

-- Serialize + write in one call. Returns (ok, err).
function BaseStats.write(path, parsed, edits)
  local newText = BaseStats.serialize(parsed, edits)
  return pt.file.write(path, newText)
end

return BaseStats
