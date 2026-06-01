-- gen1_edit_map/map_list.lua
-- Discovers all Gen1 (pokered) maps by scanning data/maps/headers/*.asm.
-- Targets the CURRENT pret/pokered layout:
--   Headers : data/maps/headers/{MapId}.asm
--   Objects : data/maps/objects/{MapId}.asm
--   Blocks  : maps/{MapId}.blk  (or data/maps/blocks/{MapId}.blk)

local Util = require("gen1_edit_map.util")

local MapList = {}

local function basename(path)
  return path:match("[/\\]([^/\\]+)%.asm$")
end

-- Try multiple candidate paths for .blk files.
local function findBlkPath(root, id)
  local candidates = {
    root .. "/maps/" .. id .. ".blk",
    root .. "/data/maps/blocks/" .. id .. ".blk",
    root .. "/data/maps/" .. id .. ".blk",
  }
  for _, p in ipairs(candidates) do
    if pt.file.exists(p) then return p end
  end
  -- Return the most likely path even if it doesn't exist yet.
  return root .. "/maps/" .. id .. ".blk"
end

-- Scan the project and return a sorted list of map records.
-- Each record: { id, name, headerPath, objectsPath, blkPath }
function MapList.scan(root)
  if not root then return {} end

  local headersDir = root .. "/data/maps/headers"
  local files = pt.file.list(headersDir, { glob = "*.asm" })

  if not files or #files == 0 then
    return {}
  end

  local maps = {}
  for _, path in ipairs(files) do
    local id = basename(path)
    if id then
      table.insert(maps, {
        id          = id,
        name        = Util.displayName(id),
        headerPath  = path,
        objectsPath = root .. "/data/maps/objects/" .. id .. ".asm",
        blkPath     = findBlkPath(root, id),
      })
    end
  end

  table.sort(maps, function(a, b) return a.name < b.name end)
  return maps
end

-- Extract just the display names for a PluginSelection dropdown.
function MapList.names(maps)
  local names = {}
  for _, m in ipairs(maps) do
    table.insert(names, m.name)
  end
  return names
end

-- Find a map record by display name.
function MapList.findByName(maps, name)
  for _, m in ipairs(maps) do
    if m.name == name then return m end
  end
  return nil
end

-- Find a map record by id.
function MapList.findById(maps, id)
  for _, m in ipairs(maps) do
    if m.id == id then return m end
  end
  return nil
end

return MapList
