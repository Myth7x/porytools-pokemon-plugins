-- Discovers all maps in a pokered or pokecrystal project by scanning the
-- relevant directories and returns a sorted list of map records.
--
-- Gen 1 (pokered):
--   Objects : data/mapObjects/*.asm   (one file per map)
--   Headers : data/mapHeaders/*.asm
--
-- Gen 2 (pokecrystal):
--   Events  : maps/*.asm              (one file per map — events + connections)
--   Headers : data/maps/*.asm

local Util = require("edit_map.util")

local MapList = {}

-- Strip the directory prefix and .asm suffix from a full path, returning
-- just the base id ("pelletTown", "NewBarkTown", etc.).
local function basename(path)
  local name = path:match("[/\\]([^/\\]+)%.asm$")
  return name
end

-- Build a human-readable display name from a map id.
-- "pelletTown"  -> "Pellet Town"
-- "NewBarkTown" -> "New Bark Town"
local function displayName(id)
  -- Insert spaces before runs of uppercase letters that follow lowercase
  -- letters or digits (camelCase / PascalCase boundary).
  local s = id:gsub("(%l)(%u)", function(a, b) return a .. " " .. b end)
  -- Also handle runs like "ABCDef" -> "ABC Def"
  s = s:gsub("(%u+)(%u%l)", function(a, b) return a .. " " .. b end)
  -- Capitalise the very first letter.
  return (s:gsub("^%l", string.upper))
end

-- Scan for gen-1 maps.
-- Supports two layouts:
--   Old pokered: data/mapObjects/*.asm  +  data/mapHeaders/*.asm
--   New pokered: data/maps/objects/*.asm  +  data/maps/headers/*.asm
-- Returns a sorted list: { {id, name, headerPath, objectsPath, blkPath}, ... }
local function scanGen1(root)
  -- Try old pokered layout first.
  local objectsDir = root .. "/data/mapObjects"
  local files = pt.file.list(objectsDir, { glob = "*.asm" })
  local newLayout = false

  -- Fall back to new pokered layout.
  if not files or #files == 0 then
    objectsDir = root .. "/data/maps/objects"
    files = pt.file.list(objectsDir, { glob = "*.asm" })
    newLayout = true
  end

  if not files or #files == 0 then
    return {}
  end

  local maps = {}
  for _, path in ipairs(files) do
    local id = basename(path)
    if id then
      local headerPath = newLayout
        and (root .. "/data/maps/headers/" .. id .. ".asm")
        or  (root .. "/data/mapHeaders/"  .. id .. ".asm")
      table.insert(maps, {
        id          = id,
        name        = displayName(id),
        headerPath  = headerPath,
        objectsPath = path,
        blkPath     = root .. "/maps/" .. id .. ".blk",
      })
    end
  end

  table.sort(maps, function(a, b) return a.name < b.name end)
  return maps
end

-- Scan for gen-2 maps.
-- Prefers data/maps/*.asm (newer layout where header + events share one file);
-- falls back to maps/*.asm (layout where events are separate from data/maps headers).
-- Returns a sorted list: { {id, name, headerPath, objectsPath}, ... }
local function scanGen2(root)
  -- Try data/maps/ first.
  local dataDir = root .. "/data/maps"
  local files   = pt.file.list(dataDir, { glob = "*.asm" })

  -- Fall back to maps/ if data/maps had nothing.
  local useDataMaps = files and #files > 0
  if not useDataMaps then
    local mapsDir = root .. "/maps"
    files = pt.file.list(mapsDir, { glob = "*.asm" })
    if not files or #files == 0 then return {} end
  end

  local maps = {}
  for _, path in ipairs(files) do
    local id = basename(path)
    if id then
      -- When using data/maps/, both header and events are in the same file.
      -- When using the separate maps/ layout, header is still in data/maps/.
      local hdrPath = root .. "/data/maps/" .. id .. ".asm"
      local evtPath = useDataMaps and hdrPath or path
      table.insert(maps, {
        id          = id,
        name        = displayName(id),
        headerPath  = hdrPath,
        objectsPath = evtPath,
        blkPath     = root .. "/maps/" .. id .. ".blk",
      })
    end
  end

  table.sort(maps, function(a, b) return a.name < b.name end)
  return maps
end

-- Public entry point.
-- `root`   : absolute path to the project root.
-- `isGen2` : true for pokecrystal, false for pokered.
-- Returns a sorted list of map records (empty list if nothing found).
function MapList.scan(root, isGen2)
  if not root then return {} end
  if isGen2 then
    return scanGen2(root)
  else
    return scanGen1(root)
  end
end

-- Extract just the display names for use in a PluginSelection dropdown.
function MapList.names(maps)
  local names = {}
  for _, m in ipairs(maps) do
    table.insert(names, m.name)
  end
  return names
end

return MapList
