-- games/blightmare/enemies.lua
-- What you fight. Difficulty is FF4 normal: field fights are short and bosses make you think. The balance lives here, in one
-- formula; tools/arcadetest/tests/blightmare_battle.test.lua measures it at tiers 5 to 40, so run that after changing a number.
--
-- FOES FOR REGION BUILDERS. Never set HP or attack: give a tier (the party level expected there) and a shape.
--
--   R.foes.hr_bog_leech = { name = "BOG LEECH", tier = 7, shape = "quick", sprite = "hr_leech", family = "bug",
--     abilities = { { "gnaw", 3 }, { "retch", 1 } }, weak = { "fire" } }
--
-- Shapes: small (comes in threes) quick brute tank caster healer. Optional: short (a name over 12 letters needs one), weak,
-- resist (lists of elements: fire ice bolt holy blood mind), immune (statuses: list or set), xpx, goldx, hpx, atkx, steal (an item or
-- gear id Jezzara can take; there is a sensible default), size (see below).
--
-- ABILITIES, in R.abilities or ABILITIES below. power is a percent of atk, against armour; magic = true ignores armour, and a
-- silenced foe can't use it. target: one (default) | all | friend (mends a hurt foe; share = percent of its max HP on top of
-- power) | summon. element, status and chance are optional, and with no power it is the status alone. mp is optional.
-- windup = ticks of warning, with warn = the line on the wall: use about 34, so everyone gets a turn in. A DEFEND in that time
-- holds until the blow lands.
-- Statuses: poison sleep nightmare blind silence thrall tadpole doom.
--   thrall  fights for the foes, until cured, hit hard, or 5 of their turns pass
--   tadpole the same, by psionic lash; circlets stop it
--   blind   misses often, for about 12 seconds
--   silence no PRAY and no MAGIC for about 12 seconds; MIX, STEAL and BLOOD need no voice
--   doom    falls when the count runs out, about 15 seconds, unless cured
-- Bosses are immune to all of those but poison unless they say otherwise.
--
-- BOSSES. Add boss to the foe, with a tier and shape as usual (shape defaults to brute):
--
--   boss = { hpx = 1.0, phases = {
--     { at = 100, moves = { { "hr_slam", 5 }, { "hr_spray", 2 } }, every = 5, big = "hr_flood" },
--     { at = 66, moves = { ... }, every = 4, big = "hr_flood", say = "THE WATER RISES", speedUp = 1, summon = "hr_bog_leech" },
--     { at = 33, moves = { ... }, every = 3, big = "hr_flood", say = "IT STOPS PRETENDING", speedUp = 1, call = "hr_horn", summon = "hr_bog_leech" },
--   } }
--
--   hpx     share of the standard boss's HP. For two bosses in one fight give each hpx = 0.45 and, on the foe, atkx = 0.7: that
--           pair beats a standard party 72 to 94% of the time. Three or more haven't been measured, so start lower and test them.
--   at      the phase begins at this percent of health or under. The first is 100. Keep them in falling order.
--   moves   weighted { abilityId, weight } list for that phase. A move it can't pay for falls back to the first in the list.
--   every   every so many of its turns it uses big instead. Give big a windup and a warn, so a player can learn it and DEFEND.
--   say     the big line on the wall as the phase begins. The change takes that turn, which is the player's breather.
--   speedUp added to its speed for good. Keep it to 1 or 2.
--   summon  a foe id. In this phase, when none of its helpers stand, it calls one, once for each phase so far that has a summon.
--           call names an ability with target = "summon" for the line on the wall; without it the line is CALLS FOR HELP.
--           Called foes pay no XP and no gold. At most 4 foes stand at once.
--
-- A multi-foe boss is an encounter with boss = true and several foes, and each has its own phases. All must fall.
--
-- size, for the picture only: 1 normal, 2 big (the left of the field), 3 huge (more of it). A lone boss defaults to 2, a boss in
-- a group to 1. Two foes of size 2 or more stand side by side; three or more are drawn at normal size.

local M = {}

M.ELEMENTS = { "fire", "ice", "bolt", "holy", "blood", "mind" }

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

  -- anyone's: regions may use these as they are
  call_help = { name = "CALLS FOR HELP", target = "summon" },
  scorch = { name = "SCORCH", mp = 4, power = 75, magic = true, element = "fire" },
  rime = { name = "RIME", mp = 4, power = 75, magic = true, element = "ice" },
  jolt = { name = "JOLT", mp = 4, power = 75, magic = true, element = "bolt" },
  glare = { name = "SEARING GLARE", mp = 4, power = 75, magic = true, element = "holy" },
  leech_vein = { name = "OPEN VEIN", mp = 4, power = 75, magic = true, element = "blood" },
  mind_lash = { name = "MIND LASH", mp = 4, power = 75, magic = true, element = "mind" },
  fire_sheet = { name = "SHEET OF FIRE", mp = 8, power = 50, magic = true, target = "all", element = "fire" },
  ice_sheet = { name = "HAIL", mp = 8, power = 50, magic = true, target = "all", element = "ice" },
  mind_wave = { name = "PSIONIC WAVE", mp = 8, power = 50, magic = true, target = "all", element = "mind" },
  blind_dust = { name = "GRIT", power = 40, status = "blind", chance = 70 },
  hush_word = { name = "HUSH", mp = 4, status = "silence", chance = 70 },
  bind_word = { name = "THE WORD", mp = 6, magic = true, status = "thrall", chance = 45 },
  tadpole_drop = { name = "EAR SEED", mp = 6, power = 20, magic = true, status = "tadpole", chance = 50 },
  death_mark = { name = "DEATH MARK", mp = 8, status = "doom", chance = 50 },
  field_surgery = { name = "FIELD SURGERY", mp = 6, target = "friend", power = 0, share = 25 },
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
    name = "THE FOREMAN", short = "FOREMAN", hp = 920, mp = 99, atk = 28, def = 6, spd = 6, xp = 120, gold = 150,
    sprite = "foreman", abilities = { { "shaft", 1 } }, immune = { sleep = true, nightmare = true },
    steal = "ether",
    boss = { phases = {
      { at = 100, moves = { { "shaft", 5 }, { "bile", 2 } }, every = 5, big = "cavein" },
      {
        at = 66, moves = { { "shaft", 5 }, { "bile", 2 }, { "scream", 3 } }, every = 4, big = "cavein",
        say = "THE SHIFT IS CALLED", speedUp = 1, call = "whistle", summon = "miner",
      },
      {
        at = 33, moves = { { "shaft", 6 }, { "bile", 1 }, { "scream", 3 } }, every = 3, big = "cavein",
        say = "HE STOPS FEELING IT", speedUp = 1, call = "whistle", summon = "miner",
      },
    } },
  },
}

-- flee is a chance, not a promise. bg: grass | town | mine, and the rest the spec lists.
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

-- ---------------------------------------------------------------- numbers from a tier and a shape

M.MAX_TIER = 50

-- multiples of the standard foe of a tier, and speed as a step from it
M.SHAPES = {
  small = { hp = 0.62, atk = 0.8, def = 0.6, spd = 1, mp = 0, xp = 0.6, gold = 0.6 },
  quick = { hp = 0.85, atk = 0.95, def = 0.7, spd = 3, mp = 1, xp = 1, gold = 1 },
  brute = { hp = 1.2, atk = 1.2, def = 1, spd = -1, mp = 1, xp = 1.2, gold = 1.1 },
  tank = { hp = 1.75, atk = 0.9, def = 2, spd = -2, mp = 1, xp = 1.4, gold = 1.3 },
  caster = { hp = 0.8, atk = 1.15, def = 0.7, spd = 0, mp = 4, xp = 1.2, gold = 1.3 },
  healer = { hp = 1.1, atk = 0.8, def = 1, spd = -1, mp = 4, xp = 1.2, gold = 1.5 },
}

local BOSS_ATK, BOSS_DEF, BOSS_XP, BOSS_GOLD, BOSS_MP = 1.7, 1.5, 6, 7, 999

--- The standard foe of a tier, before rounding: every balance change starts here.
local function standard(tier)
  return {
    hp = 6 + 8.5 * tier + 0.12 * tier * tier, atk = 5 + 2 * tier + 0.02 * tier * tier, def = 0.7 * tier, spd = 6 + 0.2 * tier, mp = 4 + tier,
    xp = 6 + 2.5 * tier + 0.1 * tier * tier, gold = 3 + 1.6 * tier + 0.08 * tier * tier,
  }
end

--- A boss's HP before hpx: about 14 rounds of what a party of the tier deals, because a boss should make you think.
local function bossHp(tier) return 350 + 115 * tier + 6.5 * tier * tier end

--- What a foe of that tier and shape has. boss: true for a boss's numbers.
function M.numbers(tier, shape, boss)
  local base, form = standard(tier), M.SHAPES[shape or "brute"] or M.SHAPES.brute
  local out = {
    hp = base.hp * form.hp, atk = base.atk * form.atk, def = base.def * form.def, spd = base.spd + form.spd,
    mp = base.mp * form.mp, xp = base.xp * form.xp, gold = base.gold * form.gold,
  }
  if boss then
    out.hp, out.atk, out.def, out.mp = bossHp(tier), base.atk * form.atk * BOSS_ATK, base.def * BOSS_DEF, BOSS_MP
    out.xp, out.gold = base.xp * BOSS_XP, base.gold * BOSS_GOLD
  end
  for key, value in pairs(out) do out[key] = math.floor(value + 0.5) end
  return out
end

-- what Jezzara finds on someone: the last one whose tier is at or above the foe's. Bosses carry something worth the trouble.
local STEAL_PLAIN = { { 12, "potion" }, { 25, "hipotion" }, { 40, "xpotion" }, { 99, "elixir" } }
local STEAL_BOSS = {
  { 12, "hunters_eye" }, { 20, "saints_bone" }, { 30, "vampire_fang" }, { 40, "quick_heart" }, { 99, "dragon_heart" },
}

local function stealFor(tier, boss)
  for _, entry in ipairs(boss and STEAL_BOSS or STEAL_PLAIN) do
    if tier <= entry[1] then return entry[2] end
  end
  return nil
end

--- A list of names as a set, leaving a set as it was. Regions write lists, the slice wrote sets.
local function asSet(list)
  if not list then return nil end
  for _, name in ipairs(list) do list[name] = true end
  return list
end

local BOSS_IMMUNE = { "sleep", "nightmare", "thrall", "tadpole", "blind", "silence", "doom" }

--- Give a foe def what it lacks: its numbers from tier and shape, and the sets battle reads. An explicit number always stands, so
-- the slice's foes are as they were. Safe to call twice. Returns the def.
function M.finish(def)
  local boss = def.boss
  if def.tier then
    local made = M.numbers(def.tier, def.shape, boss ~= nil)
    for _, key in ipairs({ "mp", "def", "spd" }) do
      if def[key] == nil then def[key] = made[key] end
    end
    if def.atk == nil then def.atk = math.floor(made.atk * (def.atkx or 1) + 0.5) end
    if def.hp == nil then
      local times = (def.hpx or 1) * (boss and boss.hpx or 1)
      def.hp = math.max(1, math.floor(made.hp * times + 0.5))
    end
    if def.xp == nil then def.xp = math.floor(made.xp * (def.xpx or 1) + 0.5) end
    if def.gold == nil then def.gold = math.floor(made.gold * (def.goldx or 1) + 0.5) end
    if def.steal == nil then def.steal = stealFor(def.tier, boss ~= nil) end
  end
  def.weak, def.resist = asSet(def.weak), asSet(def.resist)
  def.immune = asSet(def.immune)
  if boss then
    def.immune = def.immune or {}
    for _, status in ipairs(BOSS_IMMUNE) do def.immune[status] = true end
    if not def.abilities then def.abilities = boss.phases[1].moves end
  end
  return def
end

--- A new foe. Content merges regions through this.
function M.addFoe(id, def)
  M.FOES[id] = M.finish(def)
  return M.FOES[id]
end

for _, def in pairs(M.FOES) do M.finish(def) end

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

--- A boss's phase from its health: the last whose mark it has passed.
function M.phaseOf(def, share)
  local now = 1
  for i, phase in ipairs(def.boss.phases) do
    if share <= phase.at then now = i end
  end
  return now
end

--- How many helpers it may have called by now: one for each phase so far with a summon.
local function callsDue(phases, upTo)
  local due = 0
  for i = 1, upTo do
    if phases[i].summon then due = due + 1 end
  end
  return due
end

--- A boss's turn. A fixed beat for the big move, so a player can learn it, and weighted choice between.
local function bossMove(f, def, ctx, rng)
  local phases = def.boss.phases
  local phase = phases[f.phase]
  if phase.summon and ctx.adds == 0 and ctx.room and f.called < callsDue(phases, f.phase) then
    return phase.call or "call_help"
  end
  if phase.big and phase.every and f.turns % phase.every == 0 then return phase.big end
  local id = weighted(phase.moves, rng)
  if (M.ABILITIES[id].mp or 0) > f.mp then return phase.moves[1][1] end
  return id
end

--- What a foe does this turn. f is its unit in the battle; ctx.others is how many other foes stand, ctx.hurt whether one of them
-- has lost a third of its health or more, ctx.adds how many called foes stand, ctx.room whether another can be called, and
-- ctx.silent whether f is silenced.
function M.choose(f, ctx, rng)
  local def = M.FOES[f.id]
  if def.boss then return bossMove(f, def, ctx, rng) end
  local id = weighted(def.abilities, rng)
  local ab = M.ABILITIES[id]
  local broke = (ab.mp or 0) > f.mp or (ab.magic and ctx.silent)
  if broke or (ab.target == "friend" and not ctx.hurt) then return def.abilities[1][1] end
  return id
end

-- ---------------------------------------------------------------- what the regions bring

-- Each data module merges for itself. Only a missing content.lua is forgiven: a region with a mistake in it must say so.
local found, content = pcall(require, "games.blightmare.content")
if not found and not tostring(content):find("not found", 1, true) then error(content, 0) end
if found and content and content.regions then
  for _, R in ipairs(content.regions()) do
    for id, def in pairs(R.foes or {}) do M.addFoe(id, def) end
    for id, def in pairs(R.abilities or {}) do M.ABILITIES[id] = def end
    for id, def in pairs(R.encounters or {}) do M.ENCOUNTERS[id] = def end
    for region, list in pairs(R.field or {}) do
      M.FIELD[region] = M.FIELD[region] or {}
      for _, id in ipairs(list) do table.insert(M.FIELD[region], id) end
    end
  end
end

return M
