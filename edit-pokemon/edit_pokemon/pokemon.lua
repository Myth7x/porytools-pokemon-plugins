-- A "Pokemon" is just a small table describing one entry in base_stats/.
--
--   {
--     id     = "bulbasaur",                 -- file basename, lowercase
--     name   = "Bulbasaur",                 -- nice display name
--     pascal = "Bulbasaur",                 -- used for ASM labels
--     file   = "<path>/bulbasaur.asm",      -- absolute path to the stats file
--
--     -- These are filled in lazily, as the user opens the entry:
--     parsedStats = nil,
--     parsedEvos  = nil,
--     parsedEgg   = nil,
--   }
--
-- This module gives you two things:
--   * Pokemon.new(id, file)   -> build one of the tables above
--   * Pokemon.scanFolder(dir) -> read every .asm file in `dir` and return
--                                 a sorted list of Pokemon tables

local Util = require("edit_pokemon.util")

local Pokemon = {}

-- Build one Pokemon record.
function Pokemon.new(id, file)
  return {
    id     = id,
    file   = file,
    name   = Util.titleCase(id),
    pascal = Util.pascalCase(id),

    parsedStats = nil,
    parsedEvos  = nil,
    parsedEgg   = nil,
  }
end

-- Return the file basename (without extension) of a path, or nil if the
-- path doesn't look like an .asm file.
local function basenameNoExt(path)
  return path:match("([^\\/]+)%.asm$")
end

-- Scan a folder for `*.asm` files and return a sorted list of Pokemon.
-- The list is sorted alphabetically by display name.
function Pokemon.scanFolder(dir)
  local list = {}

  local files = pt.file.list(dir, { glob = "*.asm" })
  for _, path in ipairs(files) do
    local id = basenameNoExt(path)
    if id then
      table.insert(list, Pokemon.new(id, path))
    end
  end

  table.sort(list, function(a, b)
    return a.name < b.name
  end)

  return list
end

return Pokemon
