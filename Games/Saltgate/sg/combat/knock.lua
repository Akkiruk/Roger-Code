-- combat/knock.lua
-- Nobody dies on screen. A person who has taken all their knock points is knocked down: they fall, see stars, and get
-- back up (half their points back). Knocked down again and again within a minute and they are "out" for much longer
-- and get up dazed. Nothing here ever removes an entity, and nobody ends the game with a body.
--
-- The fields on a person (an entity, or the player table):
--   health, maxHealth    knock points (default 30)
--   knocked, knockT      down now, and for how many more seconds
--   out                  down for the long count (it stays set until they stand)
--   dazed                seconds left of being dazed after standing up from out
--   knockCount           knockdowns in the last minute
--   hurtT                flinch timer after a hit
--
--   knock.hit(e, dmg) -> "up" | "hurt" | "down"       knock.down(e, secs)       knock.update(e, dt)
--   knock.isDown(e) -> true when they are on the ground                         knock.standUp(e)

local M = {}

M.DOWN = 3.2 -- seconds on the ground
M.OUT = 11 -- seconds on the ground when out
M.OUT_AFTER = 3 -- knockdowns a minute before they are out
M.DAZE = 4
M.WINDOW = 60

function M.isDown(e) return e.knocked == true or e.down == true end

local function maxOf(e)
  e.maxHealth = e.maxHealth or 30
  if e.health == nil then e.health = e.maxHealth end
  return e.maxHealth
end

--- Put them on the ground for secs (default the normal count; longer if this is their third time in a minute).
function M.down(e, secs)
  maxOf(e)
  e.health = 0
  e.knockCount = (e.knockCount or 0) + 1
  e.countT = M.WINDOW
  e.knocked = true
  e.down = true -- stream D's missions read this on people tagged mission
  if e.knockCount >= M.OUT_AFTER then
    e.out = true
    e.knockT = math.max(secs or 0, M.OUT)
  else
    e.knockT = secs or M.DOWN
  end
  e.knockTotal = e.knockT
  return e
end

--- Stand them up: half their points back.
function M.standUp(e)
  local m = maxOf(e)
  e.knocked = false
  e.down = false
  e.knockT = 0
  e.health = math.max(1, math.floor(m * 0.5))
  if e.out then
    e.out = false
    e.dazed = M.DAZE
    e.knockCount = 0
  end
end

--- A hit of dmg knock points. Returns what became of them: "up" (the hit missed a person already down),
-- "hurt" or "down" (this hit put them on the ground).
function M.hit(e, dmg)
  maxOf(e)
  if e.knocked or e.down == true then return "up" end
  e.health = e.health - dmg
  e.hurtT = 0.35
  if e.health <= 0 then
    M.down(e)
    return "down"
  end
  return "hurt"
end

function M.update(e, dt)
  if e.hurtT and e.hurtT > 0 then e.hurtT = e.hurtT - dt end
  if e.dazed and e.dazed > 0 then e.dazed = e.dazed - dt if e.dazed <= 0 then e.dazed = nil end end
  if e.countT then
    e.countT = e.countT - dt
    if e.countT <= 0 then e.countT, e.knockCount = nil, 0 end
  end
  if e.knocked then
    e.knockT = e.knockT - dt
    if e.knockT <= 0 then M.standUp(e) end
  end
end

return M
