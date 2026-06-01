-- gen1_edit_map/sprite_gfx.lua
-- Map SPRITE_* constants to their PNG file paths.
--
-- In pret/pokered the sprite PNGs live in:
--   gfx/sprites/{name}.png   (most sprites)
--   gfx/sprites/{name}.2bpp  (rare, not rendered here)
--
-- Conversion: SPRITE_OAK → "oak", SPRITE_MR_FUJI → "mr_fuji", etc.
-- (Strip the SPRITE_ prefix, lowercase the remainder.)
--
-- Public API:
--   SpriteGfx.spritePath(spriteConst, root)  → path or nil
--   SpriteGfx.allSpritePaths(sprites, root)  → { SPRITE_X = path, ... }

local Util = require("gen1_edit_map.util")

local SpriteGfx = {}

local SPRITES_DIR = "gfx/sprites/"

-- Resolve the file path for a single sprite constant.
-- Returns the PNG path if it exists, nil otherwise.
function SpriteGfx.spritePath(spriteConst, root)
  if not spriteConst or spriteConst == "" then return nil end

  local filename = Util.spriteToFilename(spriteConst)

  -- Primary: gfx/sprites/{name}.png
  local primary = root .. "/" .. SPRITES_DIR .. filename .. ".png"
  if pt.file.exists(primary) then return primary end

  -- Fallback: some names have "_walk" or similar suffixes in pokered
  -- e.g. SPRITE_RED → red.png or red_walk_down.png (animated sheet)
  -- Try without any numeric suffix as well.
  local stripped = filename:match("^(.-)_%d+$")
  if stripped and stripped ~= filename then
    local alt = root .. "/" .. SPRITES_DIR .. stripped .. ".png"
    if pt.file.exists(alt) then return alt end
  end

  return nil
end

-- Build a lookup table { SPRITE_CONST = path } for a list of sprite constants.
-- Omits constants whose PNGs cannot be found.
function SpriteGfx.allSpritePaths(sprites, root)
  local result = {}
  for _, name in ipairs(sprites) do
    local p = SpriteGfx.spritePath(name, root)
    if p then result[name] = p end
  end
  return result
end

return SpriteGfx
