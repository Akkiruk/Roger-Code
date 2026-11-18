-- combat/weapons.lua
-- The cartoony arsenal: bright tracers, pops and puffs, and no blood anywhere. A hit does knock points; a person who
-- runs out of them is knocked down, sees stars and gets back up (sg/combat/knock.lua). Pure data.
--
--   id, name, short   what it is called (short is for the HUD)
--   kind              "melee" or "gun"
--   slot              1-6: the number key and the place on the wheel
--   dmg               knock points a pellet or a swing does (a person has 30)
--   pellets, spread   how many shots a trigger pull sends, and how far each may stray (radians)
--   range             how far it reaches; melee reach is short and arcs round the front
--   rate              pulls a second (held key repeats at this rate)
--   mag, reserve      rounds in the gun, and the most that can be carried besides
--   reload            seconds to reload (it reloads itself when the magazine runs dry)
--   crate             rounds in an ammo crate
--   tracer            the colour of the streak
--   driveby           whether it can be fired from a car or bike
--   words             what the pop says when it lands

local M = {}

M.LIST = {
  { id = "fists", name = "Fists", short = "FISTS", kind = "melee", slot = 1, dmg = 9, pellets = 1, spread = 0, range = 1.9, rate = 2.6,
    mag = 0, reserve = 0, reload = 0, crate = 0, tracer = "white", driveby = false, words = { "BIFF!", "POW!", "BAM!" } },
  { id = "oar", name = "Boat Oar", short = "OAR", kind = "melee", slot = 2, dmg = 17, pellets = 1, spread = 0, range = 2.8, rate = 1.5,
    mag = 0, reserve = 0, reload = 0, crate = 0, tracer = "brown", driveby = false, words = { "BONK!", "WHAP!", "THWACK!" } },
  { id = "popper", name = "Cork Popper", short = "POPPER", kind = "gun", slot = 3, dmg = 12, pellets = 1, spread = 0.03, range = 30, rate = 3.6,
    mag = 12, reserve = 72, reload = 1.1, crate = 24, tracer = "yellow", driveby = true, words = { "POP!", "PING!", "BOP!" } },
  { id = "scatter", name = "Gull Scatter", short = "SCATTER", kind = "gun", slot = 4, dmg = 9, pellets = 7, spread = 0.17, range = 15, rate = 1.1,
    mag = 6, reserve = 36, reload = 1.9, crate = 12, tracer = "orange", driveby = true, words = { "BLAM!", "KABLAM!", "WHUMP!" } },
  { id = "rattler", name = "Rattler", short = "RATTLER", kind = "gun", slot = 5, dmg = 6, pellets = 1, spread = 0.075, range = 24, rate = 11,
    mag = 30, reserve = 150, reload = 1.6, crate = 60, tracer = "lime", driveby = true, words = { "RAT!", "TAT!", "PAP!" } },
  { id = "longpop", name = "Long Pop", short = "LONGPOP", kind = "gun", slot = 6, dmg = 30, pellets = 1, spread = 0.008, range = 58, rate = 1.2,
    mag = 5, reserve = 30, reload = 2.2, crate = 10, tracer = "white", driveby = false, words = { "POW!", "KAPOW!", "WHAM!" } },
}

M.BY_ID = {}
for _, w in ipairs(M.LIST) do M.BY_ID[w.id] = w end

function M.get(id) return M.BY_ID[id] end

--- The weapons a player starts with: the two melee weapons and the pistol with some ammo.
function M.starter()
  return { fists = { mag = 0, reserve = 0 }, oar = { mag = 0, reserve = 0 }, popper = { mag = 12, reserve = 36 } }
end

--- The weapon in a slot (1-6), or nil.
function M.inSlot(n)
  return M.LIST[n]
end

return M
