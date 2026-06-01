-- Small string and line helpers shared across the edit-map modules.
-- Same pattern as edit_pokemon.util; all plain functions on a Util table.

local Util = {}

-- Remove leading and trailing whitespace.
function Util.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "pelletTown" -> "Pellet Town"  (splits on camelCase boundaries)
function Util.camelToDisplay(s)
  -- Insert a space before each uppercase letter that follows a lowercase one.
  local result = s:gsub("(%l)(%u)", function(a, b) return a .. " " .. b end)
  return (result:gsub("^%l", string.upper))
end

-- "bulbasaur" -> "Bulbasaur"
function Util.titleCase(s)
  return (s:gsub("^%l", string.upper))
end

-- "pellet_town" / "pelletTown" / "PelletTown" -> "PelletTown"
function Util.pascalCase(id)
  local capitalized = id:gsub("(%a)([%w]*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
  return (capitalized:gsub("_", ""))
end

-- Break a string into a list of lines, dropping a trailing empty entry.
function Util.splitLines(s)
  local lines = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

-- Join a list of lines back into a string with a trailing newline.
function Util.joinLines(lines)
  return table.concat(lines, "\n") .. "\n"
end

-- Split a line into its code part and its "; comment" part.
function Util.stripComment(line)
  local code, comment = line:match("^(.-)(;.*)$")
  if not code then
    return line, ""
  end
  return code, comment
end

-- Return the leading whitespace of a line.
function Util.indentOf(line)
  return line:match("^(%s*)") or ""
end

-- Replace the code on a line while keeping its original indent and any
-- trailing inline comment.
function Util.replaceLineKeepingComment(line, newCode)
  local _, comment = Util.stripComment(line)
  local indent = Util.indentOf(line)
  if comment ~= "" then
    return indent .. newCode .. " " .. comment
  end
  return indent .. newCode
end

-- Split a string by whitespace into a list of tokens.
function Util.tokenize(s)
  local tokens = {}
  for t in s:gmatch("%S+") do
    table.insert(tokens, t)
  end
  return tokens
end

return Util
