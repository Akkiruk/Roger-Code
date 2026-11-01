-- games/blightmare/enemies.lua
-- What you fight. Difficulty is FF4 normal: field fights are short and the boss makes you think. The party is about level 5 by
-- the Foreman; tools/arcadetest/tests/blightmare_battle.test.lua measures that, so run it after changing a number here.

local M = {}

-- power is a percent of atk, against armour. magic ignores armour. target: one | all | friend (mends a hurt foe) | summon.
-- windup is a telegraph: that many ticks of warning, always enough for everyone to get a turn in.
M.ABILITIES = {
  bite = { name = "BITE", power = 100 },
  gnaw = { name = "GNAW", power = 100 },
  claw = { name = "CLAW", power = 100 },
  stab = { name = "STAB", power = 110 },
  baton = { name = "BATON", power = 100 },
  swing = { name = "PICK SWING", power = 115 },
  lunge = { name = "LUNGE", power = 150 },
  spit = { name = "SPIT", power = 50, status = "poison", chance = 70 },
  tongue = { name = "TONGUE", power = 70, status = "poison", chance = 50 },
  shriek = { name = "SHRIEK", mp = 3, power = 30, magic = true, status = "sleep", chance = 50 },
  needle = { name = "NEEDLE", power = 60, status = "sleep", chance = 45 },
  draught = { name = "DRAUGHT", mp = 4, power = 30, magic = true, status = "nightmare", chance = 60 },
  suture = { name = "SUTURE", mp = 4, target = "friend", power = 18 },
  retch = { name = "RETCH", power = 60, status = "poison", chance = 60 },
  touch = { name = "BLIGHT TOUCH", power = 80, status = "nightmare", chance = 25 },
  stare = { name = "THE STARE", mp = 3, power = 40, magic = true, status = "nightmare", chance = 40 },

  -- the Foreman
  shaft = { name = "SHAFT PICK", power = 100 },
  bile = { name = "BLIGHT BILE", power = 45, target = "all", status = "poison", chance = 50 },
  scream = { name = "NO MORE SLEEP", mp = 5, power = 45, magic = true, status = "nightmare", chance = 70 },
  whistle = { name = "SHIFT WHISTLE", target = "summon", summon = "miner" },
  cavein = {
    name = "CAVE IN", power = 210, magic = true, target = "all", windup = 34,
    warn = "HE GRIPS THE PROP",
  },
}

-- abilities: { id, weight } lists for a plain foe. size: how much of the field the sprite takes. immune: statuses that fail.
M.FOES = {
  crawler = {
    name = "CRAWLER", hp = 14, mp = 0, atk = 7, def = 0, spd = 5, xp = 6, gold = 4, sprite = "crawler",
    abilities = { { "bite", 3 }, { "spit", 1 } },
  },
  rat = {
    name = "PIT RAT", hp = 16, mp = 0, atk = 8, def = 1, spd = 8, xp = 7, gold = 3, sprite = "rat",
    abilities = { { "gnaw", 1 } },
  },
  harpy = {
    name = "HARPY", hp = 26, mp = 6, atk = 10, def = 1, spd = 9, xp = 12, gold = 9, sprite = "harpy",
    abilities = { { "claw", 3 }, { "shriek", 1 } },
  },
  frogman = {
    name = "FROGMAN", hp = 30, mp = 0, atk = 10, def = 2, spd = 6, xp = 13, gold = 8, sprite = "frogman",
    abilities = { { "stab", 3 }, { "tongue", 1 } },
  },
  stalker = {
    name = "STALKER", hp = 34, mp = 0, atk = 13, def = 2, spd = 8, xp = 18, gold = 12, sprite = "stalker",
    abilities = { { "claw", 4 }, { "lunge", 1 } },
  },
  orderly = {
    name = "ORDERLY", hp = 28, mp = 0, atk = 9, def = 2, spd = 6, xp = 14, gold = 12, sprite = "orderly",
    abilities = { { "baton", 4 }, { "needle", 1 } },
  },
  doctor = {
    name = "CLINIC DOCTOR", short = "DOCTOR", hp = 46, mp = 20, atk = 9, def = 2, spd = 5, xp = 22, gold = 25, sprite = "doctor",
    abilities = { { "baton", 2 }, { "draught", 1 }, { "suture", 1 } },
  },
  blighted = {
    name = "BLIGHTED", hp = 18, mp = 0, atk = 8, def = 1, spd = 6, xp = 9, gold = 3, sprite = "blighted",
    abilities = { { "claw", 4 }, { "retch", 2 }, { "touch", 1 } },
  },
  miner = {
    name = "BLIGHTED MINER", short = "MINER", hp = 38, mp = 6, atk = 13, def = 3, spd = 5, xp = 18, gold = 10, sprite = "miner",
    abilities = { { "swing", 4 }, { "stare", 1 } },
  },
  foreman = {
    name = "THE FOREMAN", short = "FOREMAN", hp = 880, mp = 99, atk = 28, def = 6, spd = 6, xp = 120, gold = 150,
    sprite = "foreman", boss = true, abilities = { { "shaft", 1 } }, immune = { sleep = true, nightmare = true },
  },
}

-- flee is a chance, not a promise. bg: grass | town | mine.
M.ENCOUNTERS = {
  tut_crawler = { foes = { "crawler" }, flee = false, bg = "town" },
  wall_breach = { foes = { "blighted", "crawler" }, flee = false, bg = "town" },
  gate_orderlies = { foes = { "orderly", "orderly" }, flee = false, bg = "town" },
  field_heart_1 = { foes = { "rat", "rat" }, flee = true, bg = "grass" },
  field_heart_2 = { foes = { "harpy" }, flee = true, bg = "grass" },
  field_heart_3 = { foes = { "frogman", "rat" }, flee = true, bg = "grass" },
  field_road_1 = { foes = { "rat" }, flee = true, bg = "grass" },
  field_road_2 = { foes = { "stalker" }, flee = true, bg = "grass" },
  mine_1 = { foes = { "crawler", "crawler", "rat" }, flee = true, bg = "mine" },
  mine_2 = { foes = { "blighted", "blighted" }, flee = true, bg = "mine" },
  mine_3 = { foes = { "miner" }, flee = true, bg = "mine" },
  mine_4 = { foes = { "miner", "blighted" }, flee = true, bg = "mine" },
  boss_foreman = { foes = { "foreman" }, flee = false, bg = "mine", boss = true },
}

M.FIELD = {
  heart = { "field_heart_1", "field_heart_2", "field_heart_3" },
  road = { "field_road_1", "field_road_2" },
}

-- ---------------------------------------------------------------- choosing what to do

--- A weighted pick from an { id, weight } list.
local function weighted(list, rng)
  local total = 0
  for _, entry in ipairs(list) do total = total + entry[2] end
  local roll = rng(total)
  for _, entry in ipairs(list) do
    roll = roll - entry[2]
    if roll <= 0 then return entry[1] end
  end
  return list[1][1]
end

M.PHASE_AT = { 66, 33 } -- percent of health where the Foreman changes

--- The Foreman's phase from his health, 1 to 3.
function M.phaseOf(share)
  if share > M.PHASE_AT[1] then return 1 end
  return share > M.PHASE_AT[2] and 2 or 3
end

local FOREMAN_MOVES = {
  { { "shaft", 5 }, { "bile", 2 } },
  { { "shaft", 5 }, { "bile", 2 }, { "scream", 3 } },
  { { "shaft", 6 }, { "bile", 1 }, { "scream", 3 } },
}
local CAVE_EVERY = { 5, 4, 3 } -- every so many of his turns

--- The Foreman's turn. A fixed beat for the cave in, so a player can learn him, and weighted choice between.
local function foreman(f, ctx, rng)
  if f.phase >= 2 and ctx.others == 0 and f.called < f.phase - 1 then return "whistle" end
  if f.turns % CAVE_EVERY[f.phase] == 0 then return "cavein" end
  return weighted(FOREMAN_MOVES[f.phase], rng)
end

--- What a foe does this turn. f is its unit in the battle; ctx.others is how many other foes stand, ctx.hurt whether one of them
-- has lost a third of its health or more.
function M.choose(f, ctx, rng)
  local def = M.FOES[f.id]
  if def.boss then return foreman(f, ctx, rng) end
  local id = weighted(def.abilities, rng)
  local ab = M.ABILITIES[id]
  local broke = (ab.mp or 0) > f.mp
  if broke or (ab.target == "friend" and not ctx.hurt) then return def.abilities[1][1] end
  return id
end

return M
