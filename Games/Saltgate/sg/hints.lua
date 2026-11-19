-- hints.lua
-- The key hints, the arrow toward where to go, and the soundtrack's cue names. Pure.

local util = require("sg.util")

local M = {}

-- the key hint at the bottom of the screen, by what you are doing (one key per action; keys in capitals)
M.FOOT = "WASD move  SHIFT run  E enter car"
M.NEAR_CAR = "E steal car  WASD move  SHIFT run"
M.DRIVING = "W gas S brake/rev A/D steer SPACE handbrake E out"
M.TALK = "ENTER/SPACE next"

--- Which words of a hint are keys (shown in a key colour): all-capital words and A/D.
function M.isKey(word)
  return word == "A/D" or (word:match("^[A-Z]+$") ~= nil)
end

-- arrows in the CC font: 24 up, 25 down, 26 right, 27 left
M.ARROWS = { ahead = "\24", right = "\26", behind = "\25", left = "\27" }

--- Which way the target is from where the camera looks: "ahead", "right", "behind" or "left", and how far.
function M.direction(px, pz, yaw, tx, tz)
  local rel = util.wrap(util.headingTo(px, pz, tx, tz) - yaw)
  local dist = util.dist(px, pz, tx, tz)
  local q = math.pi / 4
  local word
  if rel > -q and rel <= q then word = "ahead"
  elseif rel > q and rel <= 3 * q then word = "right"
  elseif rel > -3 * q and rel <= -q then word = "left"
  else word = "behind" end
  return word, dist
end

-- ---------------------------------------------------------------- music

-- The music cues, for the soundtrack in music/ (see saltgate.lua): state cues play until the state changes,
-- event cues once.
M.MUSIC_STATES = { "title", "free_roam", "driving", "job_fresh_air", "job_hot_broth", "job_gulls", "job_gilded", "finale",
  "heat_low", "heat_high", "cuffed", "wasted", "credits" }
M.MUSIC_EVENTS = { "job_complete" }

return M
