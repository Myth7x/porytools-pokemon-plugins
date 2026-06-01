-- edit_map/map_data.lua
--
-- Loads the binary .blk map file and resolves map dimensions.
--
-- .blk format (pokered + pokecrystal):
--   One byte per block.  File length = map_width × map_height.
--   Typical location: {root}/maps/{MapId}.blk
--
-- Dimension resolution order:
--   1. Use headerData.width / headerData.height if they are numeric strings.
--   2. Try to resolve constant names (e.g. PALLET_TOWN_WIDTH) from
--      constants/map_constants.asm.
--   3. Fall back to the most square-ish integer factorisation of the total
--      block count.
--
-- Public API
-- ----------
--   MapData.blkPath(root, mapId)                    -> path or nil
--   MapData.readBlk(path)                            -> 1-based byte array or nil
--   MapData.load(mapRecord, headerData, root)        -> {blocks, mapW, mapH, total} or nil

local MapData = {}

-- ---------------------------------------------------------------------------
-- .blk file location
-- ---------------------------------------------------------------------------

-- Return the path to the .blk file for the given map ID.
-- Tries the standard locations used by pokered and pokecrystal.
function MapData.blkPath(root, mapId)
    local candidates = {
        root .. "/maps/" .. mapId .. ".blk",
        root .. "/data/maps/" .. mapId .. ".blk",
    }
    for _, p in ipairs(candidates) do
        if pt.file.exists(p) then return p end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Binary reader
-- ---------------------------------------------------------------------------

-- Read the .blk binary file and return a 1-based array of block byte values.
-- Returns nil if the file cannot be read or is empty.
function MapData.readBlk(path)
    local data = pt.file.read(path)
    if not data or #data == 0 then return nil end
    local blocks = {}
    for i = 1, #data do
        blocks[i] = string.byte(data, i)
    end
    return blocks
end

-- ---------------------------------------------------------------------------
-- Constant / dimension resolution
-- ---------------------------------------------------------------------------

-- Try to resolve `value` to an integer.
-- `value` can be a numeric string like "9" or a constant name like
-- "PALLET_TOWN_HEIGHT".  `root` is the project root directory.
local function resolveConst(value, root)
    if not value or value == "" then return nil end
    -- Trim whitespace.
    value = value:match("^%s*(.-)%s*$")
    -- Direct numeric parse.
    local n = tonumber(value)
    if n then return math.floor(n) end
    -- Search constants/map_constants.asm for "CONST_NAME EQU N".
    local paths = {
        root .. "/constants/map_constants.asm",
        root .. "/data/constants/map_constants.asm",
        root .. "/constants.asm",
    }
    for _, p in ipairs(paths) do
        local text = pt.file.read(p)
        if text then
            -- Escape special pattern characters in the constant name.
            local pat = value:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
            local m = text:match(pat .. "%s+[Ee][Qq][Uu]%s+(%d+)")
            if m then return tonumber(m) end
            -- Also handle "CONST_NAME = N" style (used by some forks).
            m = text:match(pat .. "%s*=%s*(%d+)")
            if m then return tonumber(m) end
        end
    end
    return nil
end

-- Given the total number of blocks and optionally a known width or height,
-- return (w, h).
-- If neither dimension is known, finds the most square-ish integer
-- factorisation.  Prefers w <= h (portrait orientation common for GBC maps).
local function inferDimensions(total, knownW, knownH)
    if total <= 0 then return 1, total end
    if knownW and knownH then
        return knownW, knownH
    end
    if knownW and knownW > 0 then
        local h = math.floor(total / knownW)
        if h * knownW == total then return knownW, h end
    end
    if knownH and knownH > 0 then
        local w = math.floor(total / knownH)
        if w * knownH == total then return w, knownH end
    end
    -- Find the factor pair closest to a square.
    local bestW, bestH, bestDiff = 1, total, total - 1
    for w = 2, math.floor(math.sqrt(total)) do
        if total % w == 0 then
            local h   = total / w
            local diff = math.abs(w - h)
            if diff < bestDiff then
                bestW, bestH, bestDiff = w, h, diff
            end
        end
    end
    -- Prefer w <= h (portrait); swap if needed.
    if bestW > bestH then bestW, bestH = bestH, bestW end
    return bestW, bestH
end

-- ---------------------------------------------------------------------------
-- Public loader
-- ---------------------------------------------------------------------------

-- Load all map data needed for rendering.
--
-- `mapRecord`  : { id, blkPath?, ... }  — blkPath tried first, then auto-located.
-- `headerData` : { width?, height? }    — optional, may be nil or string constants.
-- `root`       : project root directory string.
--
-- Returns { blocks, mapW, mapH, total } on success, or nil on failure.
function MapData.load(mapRecord, headerData, root)
    -- Locate the .blk file.
    local blkPath = (mapRecord and mapRecord.blkPath)
                 or MapData.blkPath(root, mapRecord and mapRecord.id or "")
    if not blkPath then return nil end

    local blocks = MapData.readBlk(blkPath)
    if not blocks or #blocks == 0 then return nil end

    local total  = #blocks
    local knownW = nil
    local knownH = nil

    if headerData then
        knownW = resolveConst(headerData.width,  root)
        knownH = resolveConst(headerData.height, root)
    end

    local mapW, mapH = inferDimensions(total, knownW, knownH)

    return {
        blocks   = blocks,
        mapW     = mapW,
        mapH     = mapH,
        total    = total,
        blkPath  = blkPath,
    }
end

return MapData
