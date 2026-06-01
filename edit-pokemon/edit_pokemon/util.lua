-- Small string and line helpers used by the rest of the plugin.
--
-- Everything here is a plain function on a single table called Util.
-- No metatables, no `self`, just functions you call as Util.trim(s).

local Util = {}

-- Remove leading and trailing whitespace from a string.
function Util.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "bulbasaur" -> "Bulbasaur"
function Util.titleCase(s)
  return (s:gsub("^%l", string.upper))
end

-- "bulbasaur"  -> "Bulbasaur"
-- "mr_mime"    -> "MrMime"
-- "porygon2"   -> "Porygon2"
--
-- Used to build the ASM label names like `BulbasaurEvosAttacks:`.
function Util.pascalCase(id)
  local capitalized = id:gsub("(%a)([%w]*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
  return (capitalized:gsub("_", ""))
end

-- Break a string into a list of lines, dropping a trailing empty line if any.
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

-- Join a list of lines back into a single string with newline separators
-- and a trailing newline.
function Util.joinLines(lines)
  return table.concat(lines, "\n") .. "\n"
end

-- Split a single line into its code part and its comment part.
-- A comment starts at the first `;`. If there is no comment, the second
-- return value is an empty string.
function Util.stripComment(line)
  local code, comment = line:match("^(.-)(;.*)$")
  if not code then
    return line, ""
  end
  return code, comment
end

-- Return the leading whitespace (spaces and tabs) of a line.
function Util.indentOf(line)
  return line:match("^(%s*)") or ""
end

-- Replace the code on a line while keeping its original indent and any
-- inline `; comment` that was already there.
function Util.replaceLineKeepingComment(line, newCode)
  local _, comment = Util.stripComment(line)
  local indent = Util.indentOf(line)
  if comment ~= "" then
    return indent .. newCode .. " " .. comment
  end
  return indent .. newCode
end

return Util
