-- hints.lua
-- What the screen tells you about the keys and where to go, and which music should be playing. Pure: it reads the game.

local util = require("sg.util")
local missions = require("sg.missions")

local M = {}

-- the key hint at the bottom of the screen, by what you are doing (one key per action; keys in capitals)
M.FOOT = "WASD move  SHIFT run  E enter car"
M.NEAR_CAR = "E steal car  WASD move  SHIFT run"
M.DRIVING = "W gas S brake/rev A/D steer SPACE handbrake E out"
M.TALK = "ENTER next"

--- The hint line for this moment ("" when there is nothing to press).
function M.line(g)
  if g.overlay then return "" end
  if g.talk then return M.TALK end
  if g.player.car then return M.DRIVING end
  if g:nearestCar() then return M.NEAR_CAR end
  return M.FOOT
end

--- Which words of a hint are keys (shown in a key colour): all-capital words and A/D.
function M.isKey(word)
  return word == "A/D" or (word:match("^[A-Z]+$") ~= nil)
end

--- Where to go: x, z and what it is ("giver", "car", "place", "tutorial"), or nil.
function M.target(g)
  local tut = g.tutorial
  if tut then
    if tut.step == "walk" or tut.step == "enter" then
      local car = tut.car
      if car then return car.x, car.z, "car" end
    elseif tut.step == "drive" then
      local p = g.city.places.juno
      return p.x, p.z, "giver"
    end
  end
  return missions.target(g)
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

--- The objective text: the tutorial's step, else the job's.
function M.objective(g)
  local tut = g.tutorial
  if tut then return M.TUTORIAL[tut.step] end
  return missions.objective(g)
end

M.TUTORIAL = {
  walk = "Hold W to walk, A/D to turn. Walk to the red car.",
  enter = "Press E to get in the car.",
  drive = "Hold W for gas, A/D to steer, S to brake. Drive to the yellow marker.",
}

-- ---------------------------------------------------------------- music

-- The music cues, for the soundtrack in music/ (see saltgate.lua): state cues play until the state changes,
-- event cues once.
M.MUSIC_STATES = { "title", "free_roam", "driving", "job_fresh_air", "job_hot_broth", "job_gulls", "job_gilded", "finale",
  "heat_low", "heat_high", "cuffed", "wasted", "credits" }
M.MUSIC_EVENTS = { "job_complete" }

--- The music cue for the game as it is now (mode "title" for the title screen).
function M.music(g, mode)
  if mode == "title" then return "title" end
  if g.overlay then return g.overlay.kind == "nabbed" and "cuffed" or "wasted" end
  local level = g.heat.level
  if level >= 3 then return "heat_high" end
  if level >= 1 then return "heat_low" end
  if g.mission then
    if g.mission.def.final then return "finale" end
    return "job_" .. g.mission.def.id
  end
  if g.credits then return "credits" end
  if g.player.car then return "driving" end
  return "free_roam"
end

--- The district the music should play for where you are: gilt, lantern, cinder, brine or mid (the park and the old
-- town are mid; off the grid counts as the nearest block).
function M.district(g)
  local city = require("sg.city")
  local p = g.player
  local i = util.clamp(math.floor(p.x / city.P), 0, city.N - 1)
  local j = util.clamp(math.floor(p.z / city.P), 0, city.N - 1)
  if i ~= i or j ~= j then return "mid" end
  return city.district(i, j)
end

return M
