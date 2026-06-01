-- Canvas Demo — showcases the pt.canvas Lua API.
--
-- Creates two canvases:
--   1. A standalone dock canvas with static drawing (shapes, text, image).
--   2. A canvas embedded inside a PluginWidget that supports mouse painting.
--
-- Run via Plugins → Demo → Canvas Demo.

local W, H = 320, 240   -- canvas dimensions

-- ---------------------------------------------------------------
-- Helper: draw static artwork onto a PluginCanvas
-- ---------------------------------------------------------------
local function drawStaticScene(c)
    -- Background gradient approximation (horizontal bands)
    for y = 0, H - 1 do
        local t = y / (H - 1)
        local r = math.floor(30 + t * 60)
        local g = math.floor(10 + t * 20)
        local b = math.floor(80 + t * 100)
        c:setColor(r, g, b)
        c:drawLine(0, y, W - 1, y)
    end

    -- Filled circle (sun / planet)
    c:setFillColor(255, 200, 50)
    c:fillCircle(80, 70, 45)

    -- Outline rings around it
    c:setPenColor(255, 240, 160, 180)
    c:setLineWidth(3)
    c:setAntialias(true)
    c:drawEllipse(25, 52, 110, 36)

    -- Ground plane
    c:setFillColor(40, 120, 60)
    c:fillRect(0, H - 50, W, 50)

    -- Tree trunks
    c:setFillColor(100, 60, 20)
    c:fillRect(190, H - 90, 14, 40)
    c:fillRect(260, H - 80, 12, 30)

    -- Tree canopies
    c:setFillColor(30, 160, 50)
    c:fillCircle(197, H - 100, 28)
    c:setFillColor(20, 140, 40)
    c:fillCircle(266, H - 88, 22)

    -- A simple house
    c:setFillColor(180, 100, 60)
    c:fillRect(110, H - 90, 70, 40)
    -- Roof (triangle approximated with lines)
    c:setPenColor(200, 50, 40)
    c:setLineWidth(2)
    c:drawLine(108, H - 90, 145, H - 120)
    c:drawLine(145, H - 120, 182, H - 90)
    c:drawLine(108, H - 90, 182, H - 90)
    -- Door
    c:setFillColor(80, 50, 20)
    c:fillRect(137, H - 63, 16, 23)

    -- Title text
    c:setAntialias(false)
    c:setPenColor(255, 255, 255)
    c:drawText(8, 18, "pt.canvas demo", 14)
end

-- ---------------------------------------------------------------
-- Helper: draw a simple colour-picker palette for the paint canvas
-- ---------------------------------------------------------------
local PALETTE = {
    {255, 50,  50 }, {255, 150, 0  }, {255, 230, 0  }, {80,  200, 60 },
    {40,  180, 220}, {60,  80,  200}, {180, 60,  200}, {255, 255, 255},
    {180, 180, 180}, {80,  80,  80 }, {20,  20,  20 }, {0,   0,   0  },
}
local SWATCH = 20  -- swatch size

local function drawPalette(c)
    for i, col in ipairs(PALETTE) do
        local x = (i - 1) * SWATCH
        c:setFillColor(col[1], col[2], col[3])
        c:fillRect(x, 0, SWATCH, SWATCH)
    end
    -- Separator
    c:setColor(60, 60, 60)
    c:drawLine(0, SWATCH, W - 1, SWATCH)
end

-- ---------------------------------------------------------------
-- run() — called each time the user invokes the plugin
-- ---------------------------------------------------------------
function run()
    -- ---- Standalone static canvas (pt.canvas.create) ----------------
    local static = pt.canvas.create(W, H, "Canvas Demo — Static Scene")
    drawStaticScene(static)

    -- ---- Paint canvas embedded in a PluginWidget --------------------
    local win = pt.ui.createWidget("Canvas Demo — Paint")
    win:setSize(W, H + SWATCH + 6)

    -- Palette strip at the top of the content area
    local pal = win:addCanvas(W, SWATCH)
    pal:setPosition(0, 0)
    drawPalette(pal)

    -- Drawing surface below the palette
    local paint = win:addCanvas(W, H)
    paint:setPosition(0, SWATCH + 4)
    paint:clear(240, 240, 240)

    -- State shared between callbacks
    local penR, penG, penB = 0, 0, 0
    local penSize = 4
    local drawing = false

    -- Pick colour from palette strip on click
    pal:onMousePress(function(x, y, btn)
        if btn == 1 then
            local idx = math.floor(x / SWATCH) + 1
            if PALETTE[idx] then
                penR, penG, penB = PALETTE[idx][1], PALETTE[idx][2], PALETTE[idx][3]
                -- Highlight selected swatch with a white border
                drawPalette(pal)
                local sx = (idx - 1) * SWATCH
                pal:setPenColor(255, 255, 255)
                pal:setLineWidth(2)
                pal:drawRect(sx + 1, 1, SWATCH - 2, SWATCH - 2)
            end
        end
    end)

    -- Paint on the drawing canvas
    paint:onMousePress(function(x, y, btn)
        if btn == 1 then
            drawing = true
            paint:setFillColor(penR, penG, penB)
            paint:fillCircle(x, y, penSize)
        elseif btn == 3 then
            -- Right-click: sample pixel colour
            local r, g, b = paint:getPixel(x, y)
            penR, penG, penB = r, g, b
        end
    end)

    paint:onMouseMove(function(x, y)
        if drawing then
            paint:setFillColor(penR, penG, penB)
            paint:fillCircle(x, y, penSize)
        end
    end)

    paint:onMouseRelease(function(x, y, btn)
        if btn == 1 then drawing = false end
    end)

    win:show()

    pt.ui.notify("Canvas Demo loaded.  Paint on the right panel; click a swatch to change colour.")
end
