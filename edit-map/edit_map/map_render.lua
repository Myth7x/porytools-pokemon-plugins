-- edit_map/map_render.lua
--
-- Renders a pokered / pokecrystal block map onto a PluginCanvas.
--
-- Block colouring uses a golden-angle HSL distribution so that consecutive
-- block IDs get clearly distinct hues.  Block 0 is rendered as near-black
-- (it is almost always the void / background tile in these games).
--
-- Event overlays (warps, NPCs, signs) are drawn on top as coloured shapes.
-- Coordinates in event tables are tile-space; they are divided by 2 to
-- convert to block-space because one block = 2×2 tiles in Gen 1/2.
--
-- The canvas is NOT resized by this module — callers create it at a fixed
-- size and the renderer scales the map to fit within that area.
--
-- Public API
-- ----------
--   MapRender.autoScale(mapW, mapH, maxW, maxH)          -> integer scale (px/block)
--   MapRender.drawBlocks(canvas, blocks, mapW, mapH, scale)
--   MapRender.drawOverlay(canvas, scale, events)
--   MapRender.render(canvas, mapData, events, opts)       -> scale used
--
-- `events` table (all fields optional):
--   { warps, npcs, people, signs, bgEvents }
--   warps / signs / npcs are lists of { x, y, ... } in tile coordinates.

local MapRender = {}

-- ---------------------------------------------------------------------------
-- Colour generation
-- ---------------------------------------------------------------------------

-- Convert HSL (h in [0,360], s and l in [0,1]) to RGB integers 0..255.
local function hsl2rgb(h, s, l)
    if s == 0 then
        local v = math.floor(l * 255)
        return v, v, v
    end
    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1 / 6 then return p + (q - p) * 6 * t end
        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end
    h = h / 360
    local q = l < 0.5 and l * (1 + s) or (l + s - l * s)
    local p = 2 * l - q
    return math.floor(hue2rgb(p, q, h + 1 / 3) * 255),
           math.floor(hue2rgb(p, q, h         ) * 255),
           math.floor(hue2rgb(p, q, h - 1 / 3) * 255)
end

-- Golden angle in degrees: consecutive IDs are maximally separated in hue.
local GOLDEN = 137.50776405003786

local function blockColor(blockId)
    if blockId == 0 then return 18, 18, 22 end     -- near-black void
    local hue = (blockId * GOLDEN) % 360
    local sat = 0.52 + (blockId % 5) * 0.03        -- 0.52 – 0.64
    local lit = 0.30 + (blockId % 6) * 0.035       -- 0.30 – 0.475
    return hsl2rgb(hue, sat, lit)
end

-- Pre-compute the colour table for IDs 0–255 to avoid recomputing on every
-- render call.
local COLOR_CACHE = {}
for i = 0, 255 do
    COLOR_CACHE[i] = { blockColor(i) }
end

-- ---------------------------------------------------------------------------
-- Scale helpers
-- ---------------------------------------------------------------------------

-- Choose the largest integer pixels-per-block such that the full map fits
-- inside maxW × maxH.  Result is clamped to [4, 32].
function MapRender.autoScale(mapW, mapH, maxW, maxH)
    maxW = maxW or 480
    maxH = maxH or 400
    if mapW <= 0 or mapH <= 0 then return 8 end
    local s = math.min(math.floor(maxW / mapW), math.floor(maxH / mapH))
    return math.max(4, math.min(32, s))
end

-- ---------------------------------------------------------------------------
-- Block drawing
-- ---------------------------------------------------------------------------

-- Draw the block grid onto `canvas` using absolute pixel coordinates.
-- The canvas must already be sized large enough (at least mapW*scale wide).
function MapRender.drawBlocks(canvas, blocks, mapW, mapH, scale)
    canvas:clear(18, 18, 22)
    local limit = mapW * mapH
    for i, blockId in ipairs(blocks) do
        if i > limit then break end
        local bId = blockId > 255 and 0 or blockId
        local col = COLOR_CACHE[bId]
        local bx  = (i - 1) % mapW
        local by  = math.floor((i - 1) / mapW)
        local px  = bx * scale
        local py  = by * scale
        canvas:setFillColor(col[1], col[2], col[3])
        canvas:fillRect(px, py, scale, scale)
        -- Grid lines at scale ≥ 8.
        if scale >= 8 then
            canvas:setColor(0, 0, 0, 70)
            canvas:setLineWidth(1)
            canvas:drawRect(px, py, scale - 1, scale - 1)
        end
        -- Block ID text at scale ≥ 20.
        if scale >= 20 then
            canvas:setPenColor(255, 255, 255, 160)
            canvas:drawText(px + 2, py + scale - 3, string.format("%02X", bId), 8)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event overlay
-- ---------------------------------------------------------------------------

-- Draw coloured markers for warps, NPCs and signs on top of the block grid.
-- Event coordinates are in tile-space; dividing by `tilesPerBlock` (default 2)
-- converts them to block-space.
--
-- `events` table fields (all optional):
--   warps     — list of { x, y }  → blue filled circles
--   npcs      — list of { x, y }  → green filled squares
--   people    — alias for npcs
--   signs     — list of { x, y }  → yellow filled circles
--   bgEvents  — alias for signs (Gen 2 bg_event)
function MapRender.drawOverlay(canvas, scale, events)
    if not events then return end
    local tpb = 2  -- tiles per block dimension

    -- Helper: tile-space coords → canvas centre of the block.
    local function blockCenter(x, y)
        local bx = math.floor(x / tpb)
        local by = math.floor(y / tpb)
        return bx * scale + math.floor(scale / 2),
               by * scale + math.floor(scale / 2)
    end

    local markerR = math.max(2, math.floor(scale / 4))

    -- Warps: blue circles.
    local warps = events.warps
    if warps and #warps > 0 then
        canvas:setFillColor(50, 120, 255, 210)
        for _, w in ipairs(warps) do
            local tx, ty = tonumber(w.x), tonumber(w.y)
            if tx and ty then
                local cx, cy = blockCenter(tx, ty)
                canvas:fillCircle(cx, cy, markerR)
            end
        end
    end

    -- NPCs (npcs or people): green squares.
    local npcs = events.npcs or events.people
    if npcs and #npcs > 0 then
        canvas:setFillColor(40, 200, 70, 210)
        local sz = math.max(2, math.floor(scale / 3))
        for _, npc in ipairs(npcs) do
            local tx, ty = tonumber(npc.x), tonumber(npc.y)
            if tx and ty then
                local cx, cy = blockCenter(tx, ty)
                canvas:fillRect(cx - math.floor(sz / 2),
                                cy - math.floor(sz / 2), sz, sz)
            end
        end
    end

    -- Signs / bg_events: yellow circles.
    local signs = events.signs or events.bgEvents
    if signs and #signs > 0 then
        canvas:setFillColor(255, 215, 30, 210)
        local r2 = math.max(2, math.floor(scale / 5))
        for _, s in ipairs(signs) do
            local tx, ty = tonumber(s.x), tonumber(s.y)
            if tx and ty then
                local cx, cy = blockCenter(tx, ty)
                canvas:fillCircle(cx, cy, r2)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Main render entry point
-- ---------------------------------------------------------------------------

-- Render the map onto `canvas`.
--
-- `mapData`  : { blocks, mapW, mapH, total }  (from MapData.load)
-- `events`   : event overlay table (may be nil)
-- `opts`     : {
--     scale  = integer px/block (nil = auto-fit to canvas size),
--     maxW   = max width  for auto-scale (default: canvas:width()),
--     maxH   = max height for auto-scale (default: canvas:height()),
-- }
--
-- Returns the scale actually used.
function MapRender.render(canvas, mapData, events, opts)
    if not canvas then return 0 end
    opts = opts or {}

    if not mapData then
        canvas:clear(18, 18, 22)
        canvas:setPenColor(140, 140, 140)
        canvas:drawText(10, 28, "No map data loaded.", 13)
        canvas:update()
        return 0
    end

    local maxW  = opts.maxW  or canvas:width()
    local maxH  = opts.maxH  or canvas:height()
    local scale = opts.scale
                  or MapRender.autoScale(mapData.mapW, mapData.mapH, maxW, maxH)

    MapRender.drawBlocks(canvas, mapData.blocks, mapData.mapW, mapData.mapH, scale)
    MapRender.drawOverlay(canvas, scale, events)
    canvas:update()
    return scale
end

return MapRender
