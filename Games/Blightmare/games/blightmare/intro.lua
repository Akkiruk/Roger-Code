-- games/blightmare/intro.lua
-- The opening cutscene's pictures, by name, for a script's { pic = name }. Each lives in one of three files, by movement:
-- intro_legend (the gods), intro_land (the map, the plague and the wall) and intro_town (one night in Scythebreak).
--
-- A picture file gives, for each of its pictures:
--   draw(L, pic, t)  paint it on the whole wall, L.W by L.H, at t ticks (120 ms each) since it came up. The talk box covers
--                    the bottom 17 rows and big letters sit across the middle, so what matters stays in rows 0 to 63.
--   LENGTH[pic]      how many ticks it moves for before it holds its last frame, true if it never stops, or nil if it's still.
--   CUES[pic]        { { tick, sound name }, ... }: sounds from lib/sound_picks.lua at those ticks.
-- A picture is a pure function of t, so a save, a second cabinet or a redraw all show the same frame.

local M = {}

local WHERE = {
  oblivion = "intro_legend", binding = "intro_legend",
  embia = "intro_land", empire = "intro_land", ward = "intro_land", plague = "intro_land", wall = "intro_land",
  dusk = "intro_town", book = "intro_town", night = "intro_town", knock = "intro_town", one = "intro_town",
}
M.PICS = WHERE

local function partFor(pic)
  local name = WHERE[pic]
  return name and require("games.blightmare." .. name)
end

local NONE = {}

function M.draw(L, pic, t)
  local part = partFor(pic)
  if part then part.draw(L, pic, t or 0) end
end

function M.length(pic)
  local part = partFor(pic)
  return part and part.LENGTH and part.LENGTH[pic]
end

function M.cues(pic)
  local part = partFor(pic)
  return part and part.CUES and part.CUES[pic] or NONE
end

return M
