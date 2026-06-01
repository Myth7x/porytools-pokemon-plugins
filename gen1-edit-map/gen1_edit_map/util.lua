-- gen1_edit_map/util.lua
-- String and line helpers for the Gen1 map editor.

local Util = {}

function Util.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.splitLines(s)
  local lines = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  if lines[#lines] == "" then table.remove(lines) end
  return lines
end

function Util.joinLines(lines)
  return table.concat(lines, "\n") .. "\n"
end

-- Split a line into its code part and "; comment" part.
function Util.stripComment(line)
  local code, comment = line:match("^(.-)(;.*)$")
  if not code then return line, "" end
  return code, comment
end

function Util.indentOf(line)
  return line:match("^(%s*)") or ""
end

-- Split whitespace-separated tokens.
function Util.tokenize(s)
  local tokens = {}
  for t in s:gmatch("%S+") do table.insert(tokens, t) end
  return tokens
end

-- camelCase/PascalCase → "Display Name"
function Util.camelToDisplay(s)
  local r = s:gsub("(%l)(%u)", function(a, b) return a .. " " .. b end)
  r = r:gsub("(%u+)(%u%l)", function(a, b) return a .. " " .. b end)
  return (r:gsub("^%l", string.upper))
end

-- "FileName" → "File Name"
function Util.displayName(id)
  return Util.camelToDisplay(id)
end

-- Convert CONST_NAME to lowercase_with_underscores.
function Util.constToLower(s)
  return s:lower()
end

-- Strip SPRITE_ prefix and lowercase: SPRITE_OAK → oak, SPRITE_MR_FUJI → mr_fuji
function Util.spriteToFilename(constName)
  local name = constName:match("^SPRITE_(.+)$") or constName
  return name:lower()
end

-- Return a deep copy of a table (shallow values).
function Util.shallowCopy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

return Util
