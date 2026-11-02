-- games/blightmare/party.lua
-- Who can fight, what they know, and what they carry. All data here stays here: a member in s.party holds only ids and numbers.
-- Display names of deserter, cleric and owlin are placeholders in this one table: the author is naming them.
--
-- Six ways to fight:
--   FOCUS  the hero. One huge hit, and it grows: the blow sweeps the other foes from level 14, FOCUS braces from 28, four times
--          the blow from 40.
--   MIX    the doctor. Flasks for every foe at once, in every element, and field medicine. No voice needed, so silence can't stop it.
--   PRAY   the sister. Healing, raising, curing, and holy fire late on. Needs a voice.
--   MAGIC  the scholar. The hardest hits in the game, if you find the weakness. Needs a voice.
--   STEAL  Jezzara. No MP. Takes what bosses carry, then blinds, and stabs what can't see her.
--   BLOOD  Asphodel. No MP. Everything costs her HP, and she can feed on it or give it away.

local floor, max, min = math.floor, math.max, math.min

local M = {}

M.MAX_LEVEL = 50
M.IN_BATTLE = 4
M.BENCH_SHARE = 75 -- percent of the XP for those not in the fight

-- learns: level -> spell, in the order they join the list. Stats are base + floor(growth * (level - 1)).
-- chants: they need a voice, so silence stops them.
M.CHARS = {
  hero = {
    name = "HERO", role = "fighter", special = "FOCUS", weapon = "knife", armour = "rags",
    hp = 40, mp = 0, atk = 9, def = 3, mag = 2, spd = 7,
    growth = { hp = 13, mp = 0, atk = 2, def = 1, mag = 0.5, spd = 0.25 },
    learns = {},
    immune = { nightmare = true, sleep = true }, -- the one who has never dreamed
  },
  deserter = {
    name = "THE DOCTOR", short = "DOCTOR", role = "alchemist", special = "MIX", weapon = "scalpel", armour = "clinic_coat",
    hp = 32, mp = 12, atk = 7, def = 2, mag = 6, spd = 7,
    growth = { hp = 10, mp = 3, atk = 1.5, def = 0.8, mag = 1.2, spd = 0.25 },
    learns = {
      [1] = "caustic", [2] = "salve", [3] = "knockout", [4] = "firepot", [8] = "iceflask", [10] = "reviver", [12] = "arcjar",
      [15] = "tincture", [18] = "ashcloud", [22] = "napalm", [26] = "antibody", [30] = "vitriol", [34] = "cordial",
      [38] = "plaguejar", [42] = "lifeblood", [46] = "lastdraught",
    },
  },
  cleric = {
    name = "CLERIC", role = "white mage", special = "PRAY", weapon = "cudgel", armour = "robe", chants = true,
    hp = 28, mp = 16, atk = 5, def = 2, mag = 7, spd = 6,
    growth = { hp = 9, mp = 4, atk = 1, def = 0.8, mag = 1.5, spd = 0.25 },
    learns = {
      [1] = "mend", [2] = "cleanse", [3] = "rise", [6] = "vigil", [9] = "smite", [12] = "grace", [16] = "sunder", [20] = "absolve",
      [24] = "longvigil", [28] = "ravenwing", [32] = "judgement", [36] = "mercy", [40] = "lastwake", [48] = "requiem",
    },
  },
  owlin = {
    name = "OWLIN", role = "black mage", special = "MAGIC", weapon = "cudgel", armour = "robe", chants = true,
    hp = 24, mp = 18, atk = 4, def = 1, mag = 9, spd = 8,
    growth = { hp = 8, mp = 4.5, atk = 0.8, def = 0.6, mag = 2, spd = 0.25 },
    learns = {
      [1] = "ember", [2] = "frost", [4] = "bolt", [7] = "dread", [10] = "blaze", [12] = "sleet", [14] = "chain", [17] = "firestorm",
      [20] = "blizzard", [23] = "mindspike", [26] = "hush", [28] = "tempest", [32] = "inferno", [35] = "deepfreeze",
      [38] = "skyfall", [41] = "psistorm", [44] = "oblivion", [48] = "lastpage",
    },
  },
  jezzara = {
    name = "JEZZARA", role = "thief", special = "STEAL", weapon = "knife", armour = "leathers",
    hp = 34, mp = 0, atk = 9, def = 3, mag = 3, spd = 10,
    growth = { hp = 11, mp = 0, atk = 2, def = 1, mag = 0.5, spd = 0.3 },
    learns = {
      [1] = "steal", [18] = "mug", [22] = "grit", [26] = "backstab", [30] = "coinshot", [34] = "vanish", [38] = "bladefan",
      [44] = "fourcuts",
    },
  },
  asphodel = {
    name = "ASPHODEL", role = "blood knight", special = "BLOOD", weapon = "shortsword", armour = "leathers",
    hp = 38, mp = 0, atk = 10, def = 3, mag = 8, spd = 6,
    growth = { hp = 12, mp = 0, atk = 2.2, def = 1, mag = 1.5, spd = 0.25 },
    learns = {
      [1] = "bleed", [24] = "leech", [30] = "bloodwave", [34] = "transfuse", [38] = "redoath", [44] = "hemorrhage",
    },
  },
}

-- What FOCUS is at each level: the last row reached counts. sweep: the blow also cuts every other foe for half. brace: FOCUS
-- guards as well.
M.FOCUS = {
  { lvl = 1, times = 3 },
  { lvl = 14, times = 3, sweep = true },
  { lvl = 28, times = 3, sweep = true, brace = true },
  { lvl = 40, times = 4, sweep = true, brace = true },
}

-- target: foe | foes | ally | allies | fallen | self. kind: damage (power + mag), heal (power + 2 * mag), raise (share of max HP),
-- cure, status (a status at chance percent).
-- Skills with no MP, for Jezzara and Asphodel:
--   steal, mug (a blow and a try at stealing), strike (pct of a blow; hits = that many cuts at random; open = pct on the blind or
--   sleeping; drain = percent of the hit comes back), gold (spends cost * level gold for a blow armour can't stop), vanish (nothing
--   reaches her until her next turn), oath (the next few blows at half as much again), transfuse (ally gets twice what she pays).
-- blood = n: costs max HP / n. element: fire ice bolt holy blood mind.
M.SPELLS = {
  -- MIX
  caustic = { name = "CAUSTIC", mp = 3, target = "foes", kind = "damage", power = 7 },
  salve = { name = "SALVE", mp = 3, target = "ally", kind = "heal", power = 6, cures = { "poison" } },
  knockout = { name = "KNOCKOUT", mp = 5, target = "foes", kind = "status", status = "sleep", chance = 60 },
  firepot = { name = "FIREPOT", mp = 6, target = "foe", kind = "damage", power = 26, element = "fire" },
  iceflask = { name = "ICE FLASK", mp = 6, target = "foes", kind = "damage", power = 14, element = "ice" },
  reviver = { name = "REVIVER", mp = 10, target = "fallen", kind = "raise", power = 25 },
  arcjar = { name = "ARC JAR", mp = 9, target = "foes", kind = "damage", power = 26, element = "bolt" },
  tincture = { name = "TINCTURE", mp = 10, target = "allies", kind = "heal", power = 10 },
  ashcloud = { name = "ASH CLOUD", mp = 10, target = "foes", kind = "status", status = "blind", chance = 65 },
  napalm = { name = "NAPALM", mp = 14, target = "foes", kind = "damage", power = 62, element = "fire" },
  antibody = { name = "ANTIBODY", mp = 8, target = "ally", kind = "cure", cures = { "poison", "blind", "silence", "thrall", "tadpole" } },
  vitriol = { name = "VITRIOL", mp = 16, target = "foe", kind = "damage", power = 140, pierce = true },
  cordial = { name = "CORDIAL", mp = 22, target = "allies", kind = "heal", power = 70 },
  plaguejar = { name = "PLAGUE JAR", mp = 20, target = "foes", kind = "damage", power = 105, status = "poison", chance = 70 },
  lifeblood = { name = "LIFEBLOOD", mp = 26, target = "ally", kind = "heal", power = 400 },
  lastdraught = { name = "LAST FLASK", mp = 34, target = "foes", kind = "damage", power = 180, element = "holy" },
  -- PRAY
  mend = { name = "MEND", mp = 3, target = "ally", kind = "heal", power = 12 },
  cleanse = { name = "CLEANSE", mp = 2, target = "ally", kind = "cure", cures = { "poison", "sleep", "nightmare" } },
  rise = { name = "RISE", mp = 8, target = "fallen", kind = "raise", power = 35 },
  vigil = { name = "VIGIL", mp = 9, target = "allies", kind = "heal", power = 8 },
  smite = { name = "SMITE", mp = 6, target = "foe", kind = "damage", power = 30, element = "holy" },
  grace = { name = "GRACE", mp = 7, target = "ally", kind = "heal", power = 60 },
  sunder = { name = "SUNDER", mp = 8, target = "foe", kind = "status", status = "silence", chance = 80 },
  absolve = { name = "ABSOLVE", mp = 8, target = "ally", kind = "cure", cures = { "poison", "sleep", "nightmare", "blind", "silence", "thrall", "tadpole", "doom" } },
  longvigil = { name = "LONG VIGIL", mp = 18, target = "allies", kind = "heal", power = 50 },
  ravenwing = { name = "RAVEN WING", mp = 16, target = "fallen", kind = "raise", power = 70 },
  judgement = { name = "JUDGEMENT", mp = 24, target = "foes", kind = "damage", power = 120, element = "holy" },
  mercy = { name = "MERCY", mp = 16, target = "ally", kind = "heal", power = 220 },
  lastwake = { name = "LAST WAKE", mp = 30, target = "allies", kind = "heal", power = 170 },
  requiem = { name = "REQUIEM", mp = 34, target = "foe", kind = "damage", power = 340, element = "holy" },
  -- MAGIC
  ember = { name = "EMBER", mp = 3, target = "foe", kind = "damage", power = 10, element = "fire" },
  frost = { name = "FROST", mp = 4, target = "foes", kind = "damage", power = 6, element = "ice" },
  bolt = { name = "BOLT", mp = 7, target = "foe", kind = "damage", power = 30, element = "bolt" },
  dread = { name = "DREAD", mp = 9, target = "foe", kind = "status", status = "nightmare", chance = 75 },
  blaze = { name = "BLAZE", mp = 8, target = "foe", kind = "damage", power = 42, element = "fire" },
  sleet = { name = "SLEET", mp = 9, target = "foe", kind = "damage", power = 50, element = "ice" },
  chain = { name = "CHAIN", mp = 10, target = "foes", kind = "damage", power = 26, element = "bolt" },
  firestorm = { name = "FIRESTORM", mp = 13, target = "foes", kind = "damage", power = 42, element = "fire" },
  blizzard = { name = "BLIZZARD", mp = 15, target = "foes", kind = "damage", power = 55, element = "ice" },
  mindspike = { name = "MIND SPIKE", mp = 14, target = "foe", kind = "damage", power = 105, element = "mind" },
  hush = { name = "HUSH", mp = 10, target = "foes", kind = "status", status = "silence", chance = 65 },
  tempest = { name = "TEMPEST", mp = 18, target = "foes", kind = "damage", power = 72, element = "bolt" },
  inferno = { name = "INFERNO", mp = 22, target = "foe", kind = "damage", power = 165, element = "fire" },
  deepfreeze = { name = "ICE TOMB", mp = 24, target = "foe", kind = "damage", power = 185, element = "ice" },
  skyfall = { name = "SKYFALL", mp = 26, target = "foe", kind = "damage", power = 205, element = "bolt" },
  psistorm = { name = "PSI STORM", mp = 28, target = "foes", kind = "damage", power = 130, element = "mind" },
  oblivion = { name = "OBLIVION", mp = 34, target = "foe", kind = "damage", power = 290, element = "mind" },
  lastpage = { name = "LAST PAGE", mp = 40, target = "foes", kind = "damage", power = 230 },
  -- STEAL
  steal = { name = "STEAL", mp = 0, target = "foe", kind = "steal" },
  mug = { name = "MUG", mp = 0, target = "foe", kind = "mug" },
  grit = { name = "GRIT", mp = 0, target = "foe", kind = "status", status = "blind", chance = 75 },
  backstab = { name = "BACKSTAB", mp = 0, target = "foe", kind = "strike", pct = 90, open = 280 },
  coinshot = { name = "COIN SHOT", mp = 0, target = "foe", kind = "gold", cost = 8, pct = 260 },
  vanish = { name = "VANISH", mp = 0, target = "self", kind = "vanish" },
  bladefan = { name = "BLADE FAN", mp = 0, target = "foes", kind = "strike", pct = 60 },
  fourcuts = { name = "FOUR CUTS", mp = 0, target = "foes", kind = "strike", pct = 45, hits = 4 },
  -- BLOOD
  bleed = { name = "BLEED", mp = 0, target = "foe", kind = "strike", pct = 240, blood = 6 },
  leech = { name = "LEECH", mp = 0, target = "foe", kind = "strike", pct = 110, drain = 60, element = "blood" },
  bloodwave = { name = "BLOOD WAVE", mp = 0, target = "foes", kind = "strike", pct = 130, blood = 6, element = "blood" },
  transfuse = { name = "TRANSFUSE", mp = 0, target = "ally", kind = "transfuse", blood = 4 },
  redoath = { name = "RED OATH", mp = 0, target = "self", kind = "oath", blood = 5, turns = 3 },
  hemorrhage = { name = "HEMORRHAGE", mp = 0, target = "foe", kind = "strike", pct = 420, blood = 3, element = "blood" },
}

-- field: usable from the menu as well. Status only exists inside a battle, so curing it is a battle use.
-- camp: only from the menu, and for the whole party. key: a story item, neither sold, used nor listed in a fight.
M.ITEMS = {
  potion = { name = "POTION", price = 12, target = "ally", hp = 35, field = true },
  hipotion = { name = "HI-POTION", price = 60, target = "ally", hp = 150, field = true },
  xpotion = { name = "X-POTION", price = 220, target = "ally", hp = 400, field = true },
  ether = { name = "ETHER", price = 40, target = "ally", mp = 15, field = true },
  hiether = { name = "HI-ETHER", price = 180, target = "ally", mp = 60, field = true },
  elixir = { name = "ELIXIR", price = 1500, target = "ally", hp = 9999, mp = 9999, field = true },
  antidote = { name = "ANTIDOTE", price = 8, target = "ally", cures = { "poison" } },
  tonic = { name = "TONIC", price = 30, target = "any", hp = 20, raise = 25, cures = { "sleep", "nightmare" }, field = true },
  feather = { name = "PLUME", price = 200, target = "fallen", raise = 60, field = true },
  eyewash = { name = "EYE WASH", price = 15, target = "ally", cures = { "blind" } },
  echoherb = { name = "ECHO HERB", price = 15, target = "ally", cures = { "silence" } },
  wakeroot = { name = "WAKE ROOT", price = 50, target = "ally", cures = { "thrall", "tadpole" } },
  lastrites = { name = "LAST RITES", price = 90, target = "ally", cures = { "doom" } },
  panacea = { name = "PANACEA", price = 150, target = "ally", cures = { "poison", "sleep", "nightmare", "blind", "silence", "thrall", "tadpole", "doom" } },
  tent = { name = "TENT", price = 300, target = "allies", hp = 9999, mp = 9999, field = true, camp = true },
}
M.ITEM_ORDER = {
  "potion", "hipotion", "xpotion", "ether", "hiether", "elixir", "antidote", "tonic", "feather", "eyewash", "echoherb", "wakeroot",
  "lastrites", "panacea", "tent",
}

--- A story item, or any other. Key items are worth nothing, and shown under KEY.
function M.addItem(id, def)
  if def.key then def.price = def.price or 0 end
  if not M.ITEMS[id] then M.ITEM_ORDER[#M.ITEM_ORDER + 1] = id end
  M.ITEMS[id] = def
  return def
end

-- who: the members who can use it. No who means anyone, as the slice's gear does.
local BLADES, KNIVES, STAVES = { hero = true, asphodel = true }, { deserter = true, jezzara = true }, { cleric = true, owlin = true }
local HEAVY, LIGHT, ROBES = BLADES, KNIVES, STAVES

M.GEAR = {
  -- tier 1, the slice
  knife = { name = "KNIFE", slot = "weapon", atk = 3, price = 10 },
  scalpel = { name = "SCALPEL", slot = "weapon", atk = 2, price = 10 },
  cudgel = { name = "CUDGEL", slot = "weapon", atk = 2, price = 10 },
  shortsword = { name = "SHORT SWORD", slot = "weapon", atk = 6, price = 60 },
  miners_pick = { name = "MINER'S PICK", slot = "weapon", atk = 9, price = 130 },
  rags = { name = "RAGS", slot = "armour", def = 0, price = 1 },
  robe = { name = "ROBE", slot = "armour", def = 1, price = 15 },
  clinic_coat = { name = "CLINIC COAT", slot = "armour", def = 1, price = 15 },
  leathers = { name = "LEATHERS", slot = "armour", def = 3, price = 50 },
  ringmail = { name = "RINGMAIL", slot = "armour", def = 5, price = 120 },
  -- blades
  falchion = { name = "FALCHION", slot = "weapon", who = BLADES, atk = 14, price = 240 },
  broadsword = { name = "BROADSWORD", slot = "weapon", who = BLADES, atk = 24, price = 600 },
  warblade = { name = "WARBLADE", slot = "weapon", who = BLADES, atk = 34, price = 1100 },
  drow_sabre = { name = "DROW SABRE", slot = "weapon", who = BLADES, atk = 44, price = 1500 },
  wraith_edge = { name = "WRAITH EDGE", slot = "weapon", who = BLADES, atk = 58, price = 2300 },
  last_light = { name = "LAST LIGHT", slot = "weapon", who = BLADES, atk = 74, element = "holy", price = 3400 },
  -- knives
  bone_saw = { name = "BONE SAW", slot = "weapon", who = KNIVES, atk = 12, price = 220 },
  stiletto = { name = "STILETTO", slot = "weapon", who = KNIVES, atk = 20, price = 550 },
  lancet = { name = "SILVER LANCET", slot = "weapon", who = KNIVES, atk = 29, price = 1000 },
  spider_fang = { name = "SPIDER FANG", slot = "weapon", who = KNIVES, atk = 38, spd = 1, price = 1400 },
  night_kris = { name = "NIGHT KRIS", slot = "weapon", who = KNIVES, atk = 50, spd = 1, price = 2100 },
  grief_knife = { name = "GRIEF KNIFE", slot = "weapon", who = KNIVES, atk = 64, spd = 2, price = 3200 },
  -- staves
  ash_rod = { name = "ASH ROD", slot = "weapon", who = STAVES, atk = 5, mag = 4, price = 220 },
  oak_staff = { name = "OAK STAFF", slot = "weapon", who = STAVES, atk = 8, mag = 8, price = 550 },
  scribe_rod = { name = "SCRIBE ROD", slot = "weapon", who = STAVES, atk = 11, mag = 12, price = 1000 },
  web_staff = { name = "WEB STAFF", slot = "weapon", who = STAVES, atk = 14, mag = 17, price = 1400 },
  grave_rod = { name = "GRAVE ROD", slot = "weapon", who = STAVES, atk = 18, mag = 24, price = 2100 },
  raven_staff = { name = "RAVEN STAFF", slot = "weapon", who = STAVES, atk = 22, mag = 32, price = 3200 },
  -- heavy
  chainmail = { name = "CHAINMAIL", slot = "armour", who = HEAVY, def = 8, price = 200 },
  brigandine = { name = "BRIGANDINE", slot = "armour", who = HEAVY, def = 12, price = 480 },
  splint_mail = { name = "SPLINT MAIL", slot = "armour", who = HEAVY, def = 16, price = 880 },
  drow_plate = { name = "DROW PLATE", slot = "armour", who = HEAVY, def = 20, price = 1200 },
  ruin_plate = { name = "RUIN PLATE", slot = "armour", who = HEAVY, def = 26, price = 1800 },
  warden_plate = { name = "WARDEN PLATE", slot = "armour", who = HEAVY, def = 32, price = 2800 },
  -- light
  hide_coat = { name = "HIDE COAT", slot = "armour", who = LIGHT, def = 6, price = 180 },
  padded_coat = { name = "SURGEON COAT", slot = "armour", who = LIGHT, def = 10, price = 440 },
  scale_vest = { name = "SCALE VEST", slot = "armour", who = LIGHT, def = 13, price = 800 },
  spider_silk = { name = "SPIDER SILK", slot = "armour", who = LIGHT, def = 17, price = 1100 },
  shade_coat = { name = "SHADE COAT", slot = "armour", who = LIGHT, def = 22, price = 1700 },
  grief_coat = { name = "GRIEF COAT", slot = "armour", who = LIGHT, def = 27, price = 2600 },
  -- robes
  linen_alb = { name = "LINEN ALB", slot = "armour", who = ROBES, def = 5, mp = 6, price = 180 },
  wool_habit = { name = "WOOL HABIT", slot = "armour", who = ROBES, def = 8, mp = 12, price = 440 },
  scholar_robe = { name = "SCHOLAR ROBE", slot = "armour", who = ROBES, def = 11, mp = 18, price = 800 },
  gloam_robe = { name = "GLOAM ROBE", slot = "armour", who = ROBES, def = 14, mp = 26, price = 1100 },
  ash_vestment = { name = "ASH VESTMENT", slot = "armour", who = ROBES, def = 18, mp = 36, price = 1700 },
  raven_vest = { name = "RAVEN VESTMENT", slot = "armour", who = ROBES, def = 23, mp = 48, price = 2600 },
  -- accessories. immune: statuses that can't land. resist: elements that do half.
  iron_charm = { name = "IRON CHARM", slot = "accessory", def = 2, price = 150 },
  circlet = { name = "CIRCLET", slot = "accessory", immune = { nightmare = true, tadpole = true }, price = 500 },
  fire_ward = { name = "FIRE WARD", slot = "accessory", resist = { fire = true }, price = 500 },
  frost_ward = { name = "FROST WARD", slot = "accessory", resist = { ice = true }, price = 500 },
  swift_band = { name = "SWIFT BAND", slot = "accessory", spd = 1, price = 900 },
  clear_eye = { name = "CLEAR EYE", slot = "accessory", immune = { blind = true }, price = 700 },
  cantor_ring = { name = "CANTOR RING", slot = "accessory", immune = { silence = true }, price = 700 },
  storm_ward = { name = "STORM WARD", slot = "accessory", resist = { bolt = true }, price = 1100 },
  oath_ring = { name = "OATH RING", slot = "accessory", immune = { thrall = true }, price = 1200 },
  sage_ring = { name = "SAGE RING", slot = "accessory", mag = 8, price = 1400 },
  might_ring = { name = "MIGHT RING", slot = "accessory", atk = 12, price = 2200 },
  life_ring = { name = "LIFE RING", slot = "accessory", hp = 60, price = 2200 },
  raven_charm = { name = "RAVEN CHARM", slot = "accessory", immune = { doom = true }, price = 2000 },
  mind_ward = { name = "MIND WARD", slot = "accessory", resist = { mind = true }, price = 2600 },
  archon_crown = { name = "ARCHON CROWN", slot = "accessory", mag = 10, immune = { nightmare = true, tadpole = true, thrall = true }, price = 5000 },
  -- nobody sells these: Jezzara takes them off bosses
  hunters_eye = { name = "HUNTER'S EYE", slot = "accessory", atk = 6, def = 2, price = 400 },
  saints_bone = { name = "SAINT'S BONE", slot = "accessory", mag = 8, mp = 20, price = 900 },
  vampire_fang = { name = "VAMPIRE FANG", slot = "accessory", atk = 16, hp = 40, price = 1600 },
  quick_heart = { name = "QUICK HEART", slot = "accessory", spd = 2, hp = 60, price = 2600 },
  dragon_heart = { name = "DRAGON HEART", slot = "accessory", atk = 14, mag = 14, hp = 100, price = 5000 },
}

--- A shop's standard stock: { item, price } rows. Consumables run through, so an old tier's cures are still on sale.
local function stock(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local def = M.ITEMS[id] or M.GEAR[id]
    out[#out + 1] = { item = id, price = def.price }
  end
  return out
end

M.SHOP_TIERS = {
  stock({ "shortsword", "miners_pick", "leathers", "ringmail", "robe", "potion", "ether", "antidote", "tonic" }),
  stock({
    "falchion", "bone_saw", "ash_rod", "chainmail", "hide_coat", "linen_alb", "iron_charm",
    "potion", "ether", "antidote", "tonic", "eyewash", "echoherb",
  }),
  stock({
    "broadsword", "stiletto", "oak_staff", "brigandine", "padded_coat", "wool_habit", "fire_ward", "frost_ward",
    "potion", "hipotion", "ether", "antidote", "tonic", "eyewash", "echoherb", "wakeroot",
  }),
  stock({
    "warblade", "lancet", "scribe_rod", "splint_mail", "scale_vest", "scholar_robe", "swift_band", "clear_eye", "cantor_ring",
    "hipotion", "ether", "tonic", "feather", "eyewash", "echoherb", "wakeroot", "tent",
  }),
  stock({
    "drow_sabre", "spider_fang", "web_staff", "drow_plate", "spider_silk", "gloam_robe", "storm_ward", "oath_ring", "sage_ring",
    "hipotion", "hiether", "feather", "eyewash", "echoherb", "wakeroot", "lastrites", "panacea", "tent",
  }),
  stock({
    "wraith_edge", "night_kris", "grave_rod", "ruin_plate", "shade_coat", "ash_vestment", "might_ring", "life_ring", "raven_charm", "mind_ward",
    "hipotion", "xpotion", "hiether", "feather", "lastrites", "panacea", "tent",
  }),
  stock({
    "last_light", "grief_knife", "raven_staff", "warden_plate", "grief_coat", "raven_vest", "archon_crown",
    "xpotion", "hiether", "elixir", "feather", "panacea", "tent",
  }),
}

-- per member, what each tier of shop gives them, for joining late and for tests. Tier 1 is their own starting kit.
local KIT = {
  blade = {
    { "shortsword", "leathers" }, { "falchion", "chainmail" }, { "broadsword", "brigandine" }, { "warblade", "splint_mail" },
    { "drow_sabre", "drow_plate" }, { "wraith_edge", "ruin_plate" }, { "last_light", "warden_plate" },
  },
  knife = {
    { "knife", "leathers" }, { "bone_saw", "hide_coat" }, { "stiletto", "padded_coat" }, { "lancet", "scale_vest" },
    { "spider_fang", "spider_silk" }, { "night_kris", "shade_coat" }, { "grief_knife", "grief_coat" },
  },
  staff = {
    { "cudgel", "robe" }, { "ash_rod", "linen_alb" }, { "oak_staff", "wool_habit" }, { "scribe_rod", "scholar_robe" },
    { "web_staff", "gloam_robe" }, { "grave_rod", "ash_vestment" }, { "raven_staff", "raven_vest" },
  },
}
local KIT_OF = { hero = "blade", asphodel = "blade", deserter = "knife", jezzara = "knife", cleric = "staff", owlin = "staff" }

--- The weapon and armour of a shop tier for a character.
function M.kit(id, tier)
  local row = KIT[KIT_OF[id]][tier]
  return row[1], row[2]
end

--- The shop tier a party of that level is buying from.
function M.tierOf(lvl)
  if lvl < 6 then return 1 end
  if lvl < 12 then return 2 end
  if lvl < 21 then return 3 end
  if lvl < 25 then return 4 end
  if lvl < 32 then return 5 end
  if lvl < 42 then return 6 end
  return 7
end

--- Can this member wear this piece? Gear with no who is anyone's.
function M.canWear(member, id)
  local def = M.GEAR[id]
  return def ~= nil and (def.who == nil or def.who[member.id] == true)
end

--- How good a piece is for this member, to compare two of a slot. Nil if they can't wear it. Worn nothing scores 0.
function M.gearScore(member, id)
  if not M.canWear(member, id) then return nil end
  local def, ch = M.GEAR[id], M.CHARS[member.id]
  local caster = ch.mag > ch.atk
  local score = (caster and 1 or 2) * (def.atk or 0) + 2 * (def.def or 0) + (caster and 2 or 1) * (def.mag or 0)
  return score + (def.mp or 0) / 2 + (def.hp or 0) / 4 + 6 * (def.spd or 0)
end

local function stat(ch, key, lvl)
  return ch[key] + floor(ch.growth[key] * (lvl - 1))
end

-- What a level costs. To level 5 the slice's curve stands: a level every few fights. After that, about ten fights a level with
-- foes of that tier, which is what keeps the party on the spec's table without grinding. Whole numbers.
local XP_NEEDED = { 0 }
for lvl = 1, M.MAX_LEVEL - 1 do
  local past = max(0, lvl - 5)
  XP_NEEDED[lvl + 1] = XP_NEEDED[lvl] + 30 + 28 * (lvl - 1) + floor(100 * past + 1.7 * past * past)
end

--- Total XP that brings a member to lvl. Fighting what the mine puts in the way brings the party to about 5 by the Foreman.
function M.xpFor(lvl)
  return XP_NEEDED[min(lvl, M.MAX_LEVEL)]
end

--- A new member at full health, with their own starting gear, or the shop's if they join late.
function M.new(id, lvl)
  local ch = M.CHARS[id]
  lvl = lvl or 1
  local weapon, armour = ch.weapon, ch.armour
  if lvl >= 12 then weapon, armour = M.kit(id, M.tierOf(lvl)) end
  local member = { id = id, lvl = lvl, xp = M.xpFor(lvl), weapon = weapon, armour = armour }
  member.hp, member.mp = 0, 0
  local st = M.stats(member)
  member.hp, member.mp = st.hp, st.mp
  return member
end

--- A member's numbers with gear on: hp and mp here are the maximums. An unknown gear id counts for nothing, and an old save has no
-- accessory.
function M.stats(member)
  local ch, lvl = M.CHARS[member.id], member.lvl
  local weapon, armour, extra = M.GEAR[member.weapon] or {}, M.GEAR[member.armour] or {}, M.GEAR[member.accessory] or {}
  local function worn(key) return (weapon[key] or 0) + (armour[key] or 0) + (extra[key] or 0) end
  local hp, mp = stat(ch, "hp", lvl) + worn("hp"), stat(ch, "mp", lvl) + worn("mp")
  return {
    hp = hp, mp = mp, maxHp = hp, maxMp = mp,
    atk = stat(ch, "atk", lvl) + worn("atk"), def = stat(ch, "def", lvl) + worn("def"),
    mag = stat(ch, "mag", lvl) + worn("mag"),
    spd = ch.spd + ch.growth.spd * (lvl - 1) + worn("spd"), -- in quarters, not whole steps: a whole step in one level would swing a fight
    element = weapon.element,
  }
end

--- Does a status fail on this member, from who they are or what they wear?
function M.immune(member, status)
  local own = M.CHARS[member.id].immune
  if own and own[status] then return true end
  for _, slot in ipairs({ "weapon", "armour", "accessory" }) do
    local def = M.GEAR[member[slot]]
    if def and def.immune and def.immune[status] then return true end
  end
  return false
end

--- Does what they wear halve this element?
function M.resists(member, element)
  for _, slot in ipairs({ "weapon", "armour", "accessory" }) do
    local def = M.GEAR[member[slot]]
    if def and def.resist and def.resist[element] then return true end
  end
  return false
end

--- What this member's FOCUS is at their level.
function M.focusOf(member)
  local out = M.FOCUS[1]
  for _, row in ipairs(M.FOCUS) do
    if member.lvl >= row.lvl then out = row end
  end
  return out
end

--- Everything back: inns, the wipe rule and { heal = true }.
function M.restore(member)
  local st = M.stats(member)
  member.hp, member.mp = st.hp, st.mp
end

--- Spells a member knows, in the order they learned them.
function M.known(member)
  local out, learns = {}, M.CHARS[member.id].learns
  for lvl = 1, member.lvl do
    if learns[lvl] then out[#out + 1] = learns[lvl] end
  end
  return out
end

--- Give a member XP. Each level gained adds what it adds to the maximums, as FF4 does. Returns how many levels.
function M.gainXp(member, n)
  member.xp = member.xp + n
  local gained = 0
  while member.lvl < M.MAX_LEVEL and member.xp >= M.xpFor(member.lvl + 1) do
    local before = M.stats(member)
    member.lvl = member.lvl + 1
    gained = gained + 1
    local after = M.stats(member)
    if member.hp > 0 then member.hp = member.hp + after.hp - before.hp end
    member.mp = member.mp + after.mp - before.mp
  end
  return gained
end

--- Spend an item's HP, MP and raising on a member. Curing status is the battle's part. Returns the HP and MP restored.
function M.applyItem(member, id)
  local item, st = M.ITEMS[id], M.stats(member)
  local hp0, mp0 = member.hp, member.mp
  if member.hp <= 0 then
    if item.raise then member.hp = max(1, floor(st.hp * item.raise / 100)) end
  elseif item.hp then
    member.hp = min(st.hp, member.hp + item.hp)
  end
  if item.mp then member.mp = min(st.mp, member.mp + item.mp) end
  return member.hp - hp0, member.mp - mp0
end

--- Using an item from the menu: on the one chosen, or on everyone for a camp item. Returns the HP and MP restored in all.
function M.useField(team, member, id)
  if not M.ITEMS[id].camp then return M.applyItem(member, id) end
  local hp, mp = 0, 0
  for _, one in ipairs(team) do
    local gainedHp, gainedMp = M.applyItem(one, id)
    hp, mp = hp + gainedHp, mp + gainedMp
  end
  return hp, mp
end

-- ---------------------------------------------------------------- what the regions bring

-- Each data module merges for itself. Only a missing content.lua is forgiven: a region with a mistake in it must say so.
-- Sorted, because pairs has no order and ITEM_ORDER is the bag's.
local found, content = pcall(require, "games.blightmare.content")
if not found and not tostring(content):find("not found", 1, true) then error(content, 0) end
if found and content and content.regions then
  for _, R in ipairs(content.regions()) do
    local ids = {}
    for id in pairs(R.items or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do M.addItem(id, R.items[id]) end
  end
end

return M
