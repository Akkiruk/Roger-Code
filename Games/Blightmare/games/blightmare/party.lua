-- games/blightmare/party.lua
-- Who can fight, what they know, and what they carry. All data here stays here: a member in s.party holds only ids and numbers.
-- Display names of deserter, cleric and owlin are placeholders in this one table: the author is naming them.

local floor, max, min = math.floor, math.max, math.min

local M = {}

M.MAX_LEVEL = 50
M.IN_BATTLE = 4

-- learns: level -> spell, in the order they join the list. Stats are base + floor(growth * (level - 1)).
M.CHARS = {
  hero = {
    name = "HERO", role = "fighter", special = "FOCUS", weapon = "knife", armour = "rags",
    hp = 40, mp = 0, atk = 9, def = 3, mag = 2, spd = 7,
    growth = { hp = 13, mp = 0, atk = 2, def = 1, mag = 0.5, spd = 0.25 },
    learns = {},
    immune = { nightmare = true, sleep = true }, -- the one who has never dreamed
  },
  deserter = {
    name = "DESERTER", role = "alchemist", special = "MIX", weapon = "scalpel", armour = "clinic_coat",
    hp = 32, mp = 12, atk = 7, def = 2, mag = 6, spd = 7,
    growth = { hp = 10, mp = 3, atk = 1.5, def = 0.8, mag = 1.2, spd = 0.25 },
    learns = { [1] = "caustic", [2] = "salve", [3] = "knockout", [4] = "firepot" },
  },
  cleric = {
    name = "CLERIC", role = "white mage", special = "PRAY", weapon = "cudgel", armour = "robe",
    hp = 28, mp = 16, atk = 5, def = 2, mag = 7, spd = 6,
    growth = { hp = 9, mp = 4, atk = 1, def = 0.8, mag = 1.5, spd = 0.25 },
    learns = { [1] = "mend", [2] = "cleanse", [3] = "rise", [6] = "vigil" },
  },
  owlin = {
    name = "OWLIN", role = "black mage", special = "MAGIC", weapon = "cudgel", armour = "robe",
    hp = 24, mp = 18, atk = 4, def = 1, mag = 9, spd = 8,
    growth = { hp = 8, mp = 4.5, atk = 0.8, def = 0.6, mag = 2, spd = 0.25 },
    learns = { [1] = "ember", [2] = "frost", [4] = "bolt", [7] = "dread" },
  },
  jezzara = {
    name = "JEZZARA", role = "thief", special = "STEAL", weapon = "knife", armour = "leathers",
    hp = 34, mp = 0, atk = 9, def = 3, mag = 3, spd = 10,
    growth = { hp = 11, mp = 0, atk = 2, def = 1, mag = 0.5, spd = 0.3 },
    learns = {},
  },
  asphodel = {
    name = "ASPHODEL", role = "blood knight", special = "BLOOD", weapon = "shortsword", armour = "leathers",
    hp = 38, mp = 0, atk = 10, def = 3, mag = 8, spd = 6,
    growth = { hp = 12, mp = 0, atk = 2.2, def = 1, mag = 1.5, spd = 0.25 },
    learns = {},
  },
}

-- target: foe | foes | ally | allies | fallen. kind: damage (power + mag), heal (power + 2 * mag), raise (share of max HP),
-- cure, sleep/nightmare/poison (a status at chance percent).
M.SPELLS = {
  caustic = { name = "CAUSTIC", mp = 3, target = "foes", kind = "damage", power = 7 },
  salve = { name = "SALVE", mp = 3, target = "ally", kind = "heal", power = 6, cures = { "poison" } },
  knockout = { name = "KNOCKOUT", mp = 5, target = "foes", kind = "status", status = "sleep", chance = 60 },
  firepot = { name = "FIREPOT", mp = 6, target = "foe", kind = "damage", power = 26 },
  mend = { name = "MEND", mp = 3, target = "ally", kind = "heal", power = 12 },
  cleanse = { name = "CLEANSE", mp = 2, target = "ally", kind = "cure", cures = { "poison", "sleep", "nightmare" } },
  rise = { name = "RISE", mp = 8, target = "fallen", kind = "raise", power = 35 },
  vigil = { name = "VIGIL", mp = 9, target = "allies", kind = "heal", power = 8 },
  ember = { name = "EMBER", mp = 3, target = "foe", kind = "damage", power = 10 },
  frost = { name = "FROST", mp = 4, target = "foes", kind = "damage", power = 6 },
  bolt = { name = "BOLT", mp = 7, target = "foe", kind = "damage", power = 30 },
  dread = { name = "DREAD", mp = 9, target = "foe", kind = "status", status = "nightmare", chance = 75 },
}

-- field: usable from the menu as well. Status only exists inside a battle, so curing it is a battle use.
M.ITEMS = {
  potion = { name = "POTION", price = 12, target = "ally", hp = 35, field = true },
  ether = { name = "ETHER", price = 40, target = "ally", mp = 15, field = true },
  antidote = { name = "ANTIDOTE", price = 8, target = "ally", cures = { "poison" } },
  tonic = { name = "TONIC", price = 30, target = "any", hp = 20, raise = 25, cures = { "sleep", "nightmare" }, field = true },
}
M.ITEM_ORDER = { "potion", "ether", "antidote", "tonic" }

M.GEAR = {
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
}

local function stat(ch, key, lvl)
  return ch[key] + floor(ch.growth[key] * (lvl - 1))
end

--- Total XP that brings a member to lvl. Fighting what the mine puts in the way brings the party to about 5 by the Foreman.
function M.xpFor(lvl)
  local n = lvl - 1
  return 30 * n + 14 * n * (n - 1)
end

--- A new member at full health, with their own starting gear.
function M.new(id, lvl)
  local ch = M.CHARS[id]
  lvl = lvl or 1
  return {
    id = id, lvl = lvl, xp = M.xpFor(lvl), weapon = ch.weapon, armour = ch.armour,
    hp = stat(ch, "hp", lvl), mp = stat(ch, "mp", lvl),
  }
end

--- A member's numbers with gear on: hp and mp here are the maximums. An unknown gear id counts for nothing.
function M.stats(member)
  local ch, lvl = M.CHARS[member.id], member.lvl
  local weapon, armour = M.GEAR[member.weapon] or {}, M.GEAR[member.armour] or {}
  local hp, mp = stat(ch, "hp", lvl), stat(ch, "mp", lvl)
  return {
    hp = hp, mp = mp, maxHp = hp, maxMp = mp,
    atk = stat(ch, "atk", lvl) + (weapon.atk or 0), def = stat(ch, "def", lvl) + (armour.def or 0),
    mag = stat(ch, "mag", lvl),
    spd = ch.spd + ch.growth.spd * (lvl - 1), -- in quarters, not whole steps: a whole step in one level would swing a fight
  }
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

return M
