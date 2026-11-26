-- gearlocker_test.lua
-- The Gear Locker's judge: what counts as junk, what's always kept, and the upgrades it points at.

local testing = require("testing")
local rules = require("lib.gearshop.rules")
local judge = require("lib.gearlocker.judge")

local test, eq, truthy = testing.test, testing.eq, testing.truthy

local TYPES = { head = "helmet", chest = "chestplate", legs = "leggings", feet = "boots", weapon = "sword", offhand = "wand" }

local serial = 0
-- o: rarity, stats = { attribute = value }, gs, kind, state, legendary, broken, type, noSlot
local function gear(slot, level, o)
  o = o or {}
  serial = serial + 1
  local prefixes = {}
  for a, v in pairs(o.stats or {}) do prefixes[#prefixes + 1] = { name = a, attribute = "the_vault:" .. a, value = v } end
  table.sort(prefixes, function(x, y) return x.attribute < y.attribute end)
  local vd = { itemType = o.kind or "Gear", level = level, rarity = o.rarity or "RARE", state = o.state or "IDENTIFIED",
    name = (TYPES[slot] or "magnet") .. " " .. serial, gearScore = o.gs, gearScoreStatus = o.gs and "COUNTED" or nil,
    equipmentSlot = not o.noSlot and slot ~= "magnet" and (slot == "weapon" and "mainhand" or slot) or nil,
    prefixes = prefixes, isLegendary = o.legendary or nil,
    durability = o.broken and { current = 0, max = 100 } or nil }
  local name = "the_vault:" .. (o.type or TYPES[slot] or "magnet")
  if o.noSlot then name = "the_vault:jewel" end
  local p = rules.piece({ name = name, count = 1, nbt = "s" .. serial, vaultData = vd })
  p.fp = ("fp%03d"):format(serial)
  return p
end

local function reasons(junk)
  local out = {}
  for _, j in ipairs(junk) do out[j.piece.fp] = j.reason end
  return out
end

-- a caster in a strong helmet, so the test helmets below aren't upgrades unless they mean to be
local function caster(level)
  return { level = level, temper = { magic = 100 },
    worn = { head = gear("head", level, { stats = { ability_power = 50, cooldown_reduction = 0.28 }, gs = 800 }) } }
end

local function stuff(n, level, ap)
  local out = {}
  for i = 1, n do out[i] = gear("head", level, { stats = { ability_power = ap } }) end
  return out
end

test("gearlocker: defaults", function()
  eq(judge.DEFAULTS.keepPerSlot, 3) eq(judge.DEFAULTS.maxBelow, 20) eq(judge.DEFAULTS.minRarity, "RARE")
  eq(judge.DEFAULTS.keepLegendary, true) eq(judge.DEFAULTS.auto, false) eq(judge.DEFAULTS.autoEvery, 300)
  local s = judge.settings({ maxBelow = 5 })
  eq(s.maxBelow, 5) eq(s.keepPerSlot, 3)
  eq(judge.DEFAULTS.maxBelow, 20, "settings never change the defaults")
end)

test("gearlocker: a piece more than maxBelow levels under the player is junk", function()
  local read = caster(50)
  local pieces = stuff(3, 50, 45)
  local old = gear("head", 25, { stats = { ability_power = 10 } })
  local edge = gear("head", 30, { stats = { ability_power = 49, cooldown_reduction = 0.28, area_of_effect = 0.2 } })
  pieces[#pieces + 1] = old
  pieces[#pieces + 1] = edge
  local junk, keep = judge.junk(pieces, read, "caster")
  local why = reasons(junk)
  eq(why[old.fp], "lvl 25, 25 under you")
  eq(why[edge.fp], nil, "20 under is still fine")
  truthy(keep[edge.fp], "kept: " .. tostring(keep[edge.fp]))
  -- a player over 100 is treated as 100, gear stops there
  junk = judge.junk({ gear("feet", 79, { rarity = "EPIC" }), gear("feet", 80, { rarity = "EPIC" }) }, { level = 120, worn = {} },
    "caster", { keepPerSlot = 0 })
  eq(#junk, 1) eq(junk[1].reason, "lvl 79, 21 under you")
  -- maxBelow is the owner's
  junk = judge.junk({ gear("feet", 45, { rarity = "EPIC" }) }, { level = 50, worn = {} }, "caster", { keepPerSlot = 0, maxBelow = 3 })
  eq(junk[1].reason, "lvl 45, 5 under you")
end)

test("gearlocker: below minRarity is junk, Rare and up stay", function()
  local read = { level = 40, worn = {} }
  local pieces = {
    gear("legs", 40, { rarity = "SCRAPPY" }), gear("legs", 40, { rarity = "COMMON" }), gear("legs", 40, { rarity = "RARE" }),
    gear("legs", 40, { rarity = "EPIC" }), gear("legs", 40, { rarity = "OMEGA" }), gear("legs", 40, { rarity = "UNIQUE" }),
  }
  local cfg = { keepPerSlot = 0 }
  local why = reasons((judge.junk(pieces, read, "caster", cfg)))
  eq(why[pieces[1].fp], "Scrappy") eq(why[pieces[2].fp], "Common")
  for i = 3, 6 do eq(why[pieces[i].fp], nil, pieces[i].rarity) end
  why = reasons((judge.junk(pieces, read, "caster", { keepPerSlot = 0, minRarity = "EPIC" })))
  eq(why[pieces[3].fp], "Rare", "minRarity EPIC takes Rare too")
  eq(why[pieces[4].fp], nil)
end)

test("gearlocker: a piece with keepPerSlot better ones in its slot, and no better than what's worn, is junk", function()
  local read = caster(50)
  local pieces = { gear("head", 50, { stats = { ability_power = 40 } }), gear("head", 50, { stats = { ability_power = 30 } }),
    gear("head", 50, { stats = { ability_power = 20 } }), gear("head", 50, { stats = { ability_power = 10 } }),
    gear("head", 50, { stats = { ability_power = 5 } }) }
  local junk, keep = judge.junk(pieces, read, "caster")
  local why = reasons(junk)
  eq(#junk, 2)
  eq(why[pieces[4].fp], "3 better Helmets") eq(why[pieces[5].fp], "4 better Helmets")
  for i = 1, 3 do eq(keep[pieces[i].fp], "top 3 Helmets") end
  -- keepPerSlot is the owner's
  junk = judge.junk(pieces, read, "caster", { keepPerSlot = 1 })
  eq(#junk, 4)
  -- other slots are ranked on their own
  junk = judge.junk({ pieces[5], gear("feet", 50, { stats = { ability_power = 1 } }) }, read, "caster")
  eq(#junk, 0, "one helmet and one pair of boots: both top of their slot")
  -- better than what's worn (but too high a level to be an upgrade yet): kept
  local future = gear("head", 70, { stats = { ability_power = 50, cooldown_reduction = 0.28, area_of_effect = 0.2 } })
  local up = {}
  for i = 1, 3 do up[i] = gear("head", 70, { stats = { ability_power = 50, cooldown_reduction = 0.28, area_of_effect = 0.2, mana_regen = 1 } }) end
  up[4] = future
  junk, keep = judge.junk(up, read, "caster")
  eq(#junk, 0) eq(keep[future.fp], "fine")
end)

test("gearlocker: never junk: not gear, no slot, unidentified, spared, legendary, broken", function()
  local read = { level = 60, worn = {} }
  local cfg = { keepPerSlot = 0 }
  local jewel = gear("head", 1, { kind = "Jewel", rarity = "SCRAPPY" })
  local slotless = gear("head", 1, { rarity = "SCRAPPY", noSlot = true })
  local unid = gear("chest", 1, { rarity = "SCRAPPY", state = "UNIDENTIFIED" })
  local spare = gear("chest", 1, { rarity = "SCRAPPY" })
  local leg = gear("chest", 1, { rarity = "SCRAPPY", legendary = true })
  local broke = gear("chest", 1, { rarity = "SCRAPPY", broken = true })
  local bad = gear("chest", 1, { rarity = "SCRAPPY" })
  local pieces = { jewel, slotless, unid, spare, leg, broke, bad }
  local junk, keep = judge.junk(pieces, read, "caster", cfg, { [spare.fp] = true })
  eq(#junk, 1) eq(junk[1].piece, bad)
  eq(keep[jewel.fp], "not gear") eq(keep[slotless.fp], "no slot") eq(keep[unid.fp], "unidentified")
  eq(keep[spare.fp], "spared") eq(keep[leg.fp], "legendary") eq(keep[broke.fp], "broken, can be repaired")
  -- with keepLegendary off a legendary goes like the rest
  junk, keep = judge.junk(pieces, read, "caster", { keepPerSlot = 0, keepLegendary = false }, { [spare.fp] = true })
  eq(#junk, 2) eq(keep[leg.fp], nil)
  -- rolling counts as unidentified
  local rolling = gear("feet", 1, { rarity = "SCRAPPY", state = "ROLLING" })
  junk, keep = judge.junk({ rolling }, read, "caster", cfg)
  eq(#junk, 0) eq(keep[rolling.fp], "unidentified")
end)

test("gearlocker: unsparing a piece lets it go again", function()
  local read = { level = 60, worn = {} }
  local p = gear("chest", 1, { rarity = "COMMON" })
  eq(#judge.junk({ p }, read, "caster", { keepPerSlot = 0 }, { [p.fp] = true }), 0)
  eq(#judge.junk({ p }, read, "caster", { keepPerSlot = 0 }, {}), 1)
  eq(#judge.junk({ p }, read, "caster", { keepPerSlot = 0 }), 1, "no spared list at all")
end)

test("gearlocker: the top keepPerSlot are kept even when a rule would take them", function()
  local read = { level = 60, worn = {} }
  local pieces = { gear("chest", 1, { rarity = "COMMON" }), gear("chest", 2, { rarity = "COMMON" }), gear("chest", 3, { rarity = "COMMON" }),
    gear("chest", 4, { rarity = "COMMON" }) }
  local junk, keep = judge.junk(pieces, read, "caster")
  eq(#junk, 1, "only the fourth goes")
  eq(junk[1].piece, pieces[1], "the lowest level of the four")
  eq(keep[pieces[4].fp], "top 3 Chestplates")
end)

test("gearlocker: a recommended upgrade is never junk", function()
  local read = caster(50)
  -- Common, and with keepPerSlot 0 nothing is kept for its rank, but it beats the worn helmet
  local up = gear("head", 48, { rarity = "COMMON", stats = { ability_power = 50, cooldown_reduction = 0.28, area_of_effect = 0.2, mana_regen = 1 } })
  local meh = gear("head", 48, { rarity = "COMMON", stats = { ability_power = 10 } })
  local list = judge.upgrades({ up, meh }, read, "caster")
  eq(#list, 1) eq(list[1].piece, up)
  local junk, keep = judge.junk({ up, meh }, read, "caster", { keepPerSlot = 0 })
  eq(#junk, 1) eq(junk[1].piece, meh)
  eq(keep[up.fp], "upgrade")
  -- same with build "gs"
  local gsUp = gear("head", 48, { rarity = "COMMON", gs = 900 })
  local gsMeh = gear("head", 48, { rarity = "COMMON", gs = 100 })
  junk, keep = judge.junk({ gsUp, gsMeh }, read, "gs", { keepPerSlot = 0 })
  eq(#junk, 1) eq(junk[1].piece, gsMeh) eq(keep[gsUp.fp], "upgrade")
  -- one the player reaches in a few levels counts too
  local later = gear("head", 52, { rarity = "COMMON", stats = { ability_power = 50, cooldown_reduction = 0.28, area_of_effect = 0.2, mana_regen = 1 } })
  list = judge.upgrades({ later }, read, "caster")
  eq(list[1].later, true)
  junk, keep = judge.junk({ later }, read, "caster", { keepPerSlot = 0 })
  eq(#junk, 0) eq(keep[later.fp], "upgrade")
end)

test("gearlocker: ties never push each other out", function()
  local read = caster(50)
  local pieces = stuff(6, 50, 20)
  local junk, keep = judge.junk(pieces, read, "caster")
  eq(#junk, 0, "six twins: none has three better")
  local top, fine = 0, 0
  for _, p in ipairs(pieces) do
    if keep[p.fp] == "top 3 Helmets" then top = top + 1 elseif keep[p.fp] == "fine" then fine = fine + 1 end
  end
  eq(top, 3) eq(fine, 3)
  -- the same in another order keeps the same three (by fingerprint)
  local flipped = {}
  for i = #pieces, 1, -1 do flipped[#flipped + 1] = pieces[i] end
  local _, keep2 = judge.junk(flipped, read, "caster")
  for _, p in ipairs(pieces) do eq(keep2[p.fp], keep[p.fp], p.fp) end
  -- three better and a tie behind them: both of the tied pair have three better
  local mix = stuff(3, 50, 40)
  local a, b = gear("head", 50, { stats = { ability_power = 10 } }), gear("head", 50, { stats = { ability_power = 10 } })
  mix[4], mix[5] = a, b
  local why = reasons((judge.junk(mix, read, "caster")))
  eq(why[a.fp], "3 better Helmets") eq(why[b.fp], "3 better Helmets")
  -- twins in Gear Score too
  local gs = { gear("head", 50, { gs = 300 }), gear("head", 50, { gs = 300 }), gear("head", 50, { gs = 300 }), gear("head", 50, { gs = 300 }) }
  eq(#judge.junk(gs, read, "gs"), 0)
end)

test("gearlocker: 2.2.36 pieces with no stats: only the level and rarity rules", function()
  local read = { level = 50, worn = { head = gear("head", 50, {}) }, limited = true }
  local pieces = {}
  for i = 1, 6 do pieces[i] = gear("head", 50, { rarity = "EPIC" }) end
  local old = gear("head", 20, { rarity = "EPIC" })
  local common = gear("head", 50, { rarity = "COMMON" })
  pieces[#pieces + 1] = old
  pieces[#pieces + 1] = common
  local junk, keep = judge.junk(pieces, read, "caster")
  local why = reasons(junk)
  eq(#junk, 2, "no fit rule: six Epic helmets all stay")
  eq(why[old.fp], "lvl 20, 30 under you") eq(why[common.fp], "Common")
  -- with no numbers the best three go by rarity, then level
  local n = 0
  for _, p in ipairs(pieces) do if keep[p.fp] == "top 3 Helmets" then n = n + 1 end end
  eq(n, 3)
  local list, best, counts, note = judge.upgrades(pieces, read, "caster")
  eq(#list, 0) eq(next(best), nil) eq(next(counts), nil)
  eq(note, "upgrades need vhcctweaks 2.2.37")
  _, _, _, note = judge.upgrades(pieces, read, "gs")
  eq(note, "upgrades need vhcctweaks 2.2.37", "no Gear Score either")
  eq(select(4, judge.upgrades({}, read, "caster")), nil, "an empty ME isn't a 2.2.36 problem")
  -- the best three without numbers: legendary first, then rarity, then level
  local leg = gear("feet", 10, { rarity = "RARE", legendary = true })
  local omega = gear("feet", 10, { rarity = "OMEGA" })
  local high = gear("feet", 60, { rarity = "EPIC" })
  local low = gear("feet", 40, { rarity = "EPIC" })
  _, keep = judge.junk({ low, high, omega, leg }, nil, "caster")
  eq(keep[omega.fp], "top 3 Boots") eq(keep[high.fp], "top 3 Boots") eq(keep[low.fp], "fine")
end)

test("gearlocker: no read (player offline): only the rarity rule", function()
  local pieces = { gear("chest", 1, { rarity = "RARE", stats = { ability_power = 1 } }), gear("chest", 1, { rarity = "RARE", stats = { ability_power = 2 } }),
    gear("chest", 1, { rarity = "RARE", stats = { ability_power = 3 } }), gear("chest", 1, { rarity = "RARE", stats = { ability_power = 4 } }),
    gear("chest", 1, { rarity = "RARE", stats = { ability_power = 5 } }), gear("chest", 90, { rarity = "COMMON" }) }
  local junk, keep = judge.junk(pieces, nil, "caster")
  eq(#junk, 1, "level 1 and five of them, but no level to go by and no fit rule")
  eq(junk[1].reason, "Common")
  eq(keep[pieces[1].fp], "fine")
  local list, best, counts, note = judge.upgrades(pieces, nil, "caster")
  eq(#list, 0) eq(next(best), nil) eq(next(counts), nil) truthy(note)
  local id, _, why = judge.build(nil, nil)
  eq(id, "balanced") truthy(why:find("can't read", 1, true))
end)

test("gearlocker: build gs ranks by Gear Score and upgrades by rules.improvements", function()
  local read = { level = 50, worn = { head = gear("head", 50, { gs = 500 }), feet = gear("feet", 50, { gs = 400 }) } }
  local pieces = { gear("head", 50, { gs = 900 }), gear("head", 50, { gs = 800 }), gear("head", 50, { gs = 700 }),
    gear("head", 50, { gs = 450 }), gear("head", 50, { gs = 600 }), gear("feet", 49, { gs = 430 }), gear("feet", 50, { gs = 410 }) }
  local junk, keep = judge.junk(pieces, read, "gs")
  local why = reasons(junk)
  eq(why[pieces[4].fp], "4 better Helmets")
  eq(keep[pieces[5].fp], "upgrade", "600 beats the 500 worn by more than the margin")
  local list, best, counts = judge.upgrades(pieces, read, "gs")
  eq(best.head.piece, pieces[1]) eq(best.head.gain, 400) eq(best.head.worn, read.worn.head)
  eq(best.feet.piece, pieces[6], "430 beats 400 by 30, the 410 doesn't make the margin")
  eq(counts.head, 4) eq(counts.feet, 1)
  eq(#list, 5)
end)

test("gearlocker: upgrades give the best per slot with what's worn there", function()
  local read = caster(50)
  local good = gear("head", 50, { stats = { ability_power = 50, cooldown_reduction = 0.28, area_of_effect = 0.2 } })
  local better = gear("head", 50, { stats = { ability_power = 50, cooldown_reduction = 0.28, area_of_effect = 0.2, mana_regen = 1 } })
  local wand = gear("offhand", 50, { stats = { ability_power = 40 } })
  local shield = gear("offhand", 50, { type = "shield", stats = { block = 0.3 } })
  local list, best, counts = judge.upgrades({ good, better, wand, shield }, read, "caster")
  eq(best.head.piece, better) eq(best.head.worn, read.worn.head)
  eq(best.offhand.piece, wand, "a caster gets a wand, never the shield") eq(best.offhand.worn, nil, "nothing in the offhand")
  eq(counts.head, 2) eq(counts.offhand, 1)
  eq(#list, 3)
  truthy(list[1].delta >= list[#list].delta)
end)

test("gearlocker: the build is the player's pick, else the guess", function()
  local id, label, why = judge.build(nil, "gs")
  eq(id, "gs") eq(label, "Best rolled (Gear Score)") eq(why, "your pick")
  id, label, why = judge.build(caster(50), "tank")
  eq(id, "tank") eq(why, "your pick")
  id = judge.build({ worn = {} }, "nonsense")
  eq(id, "balanced", "an unknown pick is guessed again")
  local read = {
    level = 60, temper = { might = 10, magic = 200, vigor = 20 },
    worn = {
      head = gear("head", 60, { stats = { ability_power = 45, cooldown_reduction = 0.15 } }),
      chest = gear("chest", 60, { stats = { ability_power = 50, mana_regen = 0.8 } }),
      offhand = gear("offhand", 60, { stats = { ability_power = 48, cooldown_reduction = 0.25 } }),
      weapon = gear("weapon", 60, { stats = { ability_power = 18, attack_damage = 110 } }),
    },
  }
  id, label, why = judge.build(read, nil)
  eq(id, "caster") truthy(why ~= "your pick")
end)

test("gearlocker: junk comes back lowest level first and every piece has a keep or a junk reason", function()
  local read = { level = 80, worn = {} }
  local pieces = { gear("legs", 30, { rarity = "EPIC" }), gear("legs", 10, { rarity = "EPIC" }), gear("legs", 50, { rarity = "EPIC" }),
    gear("feet", 79, { rarity = "EPIC" }), gear("legs", 20, { kind = "Trinket" }) }
  local junk, keep = judge.junk(pieces, read, "melee", { keepPerSlot = 0 })
  eq(#junk, 3)
  eq(junk[1].piece.level, 10) eq(junk[2].piece.level, 30) eq(junk[3].piece.level, 50)
  local gone = {}
  for _, j in ipairs(junk) do gone[j.piece.fp] = true end
  for _, p in ipairs(pieces) do truthy((keep[p.fp] ~= nil) ~= (gone[p.fp] == true), p.fp) end
end)
