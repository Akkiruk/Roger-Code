-- games/blightmare/battle.lua
-- ATB in Wait mode, as pure rules. Gauges fill only while no menu is open; when a party member's gauge fills, the command screen
-- opens and time stops until they have chosen. Everything in s.battle is whole numbers and plain tables, so a battle saves and
-- resumes exactly.
--
-- s.battle.phase: run (time passes) | cmd | list | target (a menu, time stopped) | spoils (the end card, then result is set).
-- Taps come through battle.input and take effect in the next tick.

local enemies = require("games.blightmare.enemies")
local party = require("games.blightmare.party")

local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min

local M = {}

M.GAUGE = 1000
M.SLEEP_TICKS = 45        -- about five seconds, or until something hits them
M.POISON_EVERY = 25       -- a sting about every three seconds of running time
M.POISON_SHARE = 16       -- each one takes this fraction of max HP, and never the last point
M.NIGHTMARE_TURNS = 3
M.THRALL_TURNS = 5        -- thrall and tadpole wear off at last, so someone alone can't be stuck for good
M.BLIND_TICKS = 100       -- about twelve seconds
M.SILENCE_TICKS = 100
M.DOOM_TICKS = 125        -- about fifteen seconds to cure it
M.BREAK_SHARE = 15        -- a hit of this percent of max HP breaks a thrall or a tadpole
M.GUARD_DIVIDE = 2

local BEAT = 5            -- ticks an action stays on the wall before time moves on
local TELEGRAPH_BEAT = 9
local SPOILS_TICKS = 40   -- the end card goes by itself
local SPOILS_MIN = 6      -- and a tap can't skip it before it has been seen
local FLOAT_TICKS = 8
local HIT_PERCENT = 95
local BLIND_HIT_PERCENT = 35
local CRIT_ONE_IN = 16
local STEAL_PERCENT = 55
local STEAL_BOSS_PERCENT = 35
local OATH_PERCENT = 150  -- RED OATH's blows
local MAX_STANDING = 4    -- no boss calls a helper past this many foes
local BLINK_TICKS = 3     -- how often a blinking ring repaints
local LIST_ROWS = 6       -- what the screen can show of a list at once

-- a fixed order, because pairs isn't one. Each lasts this long, in the unit's own count.
local STATUS = { "poison", "sleep", "nightmare", "thrall", "tadpole", "blind", "silence", "doom" }
local LASTS = {
  sleep = M.SLEEP_TICKS, nightmare = M.NIGHTMARE_TURNS, thrall = M.THRALL_TURNS, tadpole = M.THRALL_TURNS, blind = M.BLIND_TICKS,
  silence = M.SILENCE_TICKS, doom = M.DOOM_TICKS,
}

-- ---------------------------------------------------------------- units

--- Gauge gained in a tick: speed 7 fills in about 3 seconds at 120 ms a tick.
function M.gain(spd) return 16 + floor(spd * 7 / 2) end

local function member(s, u) return s.party[u.m] end
local function hpOf(s, u) return u.m and member(s, u).hp or u.hp end
local function alive(s, u) return hpOf(s, u) > 0 end


local function setHp(s, u, n)
  if u.m then member(s, u).hp = n else u.hp = n end
end

local function maxHpOf(s, u)
  if u.m then return party.stats(member(s, u)).hp end
  return u.mhp
end

local function nameOf(s, u)
  if u.m then
    local id = member(s, u).id
    local char = party.CHARS[id]
    return id == "hero" and s.heroName and s.heroName:upper() or char.short or char.name
  end
  local def = enemies.FOES[u.id]
  return def.short or def.name
end

local function immuneTo(s, u, status)
  if u.m then return party.immune(member(s, u), status) end
  local list = enemies.FOES[u.id].immune
  return list and list[status]
end

--- What an element does to this unit: a multiple of the damage.
local function elementTimes(s, u, element)
  if not element then return 1 end
  if u.m then return party.resists(member(s, u), element) and 0.5 or 1 end
  local def = enemies.FOES[u.id]
  if def.weak and def.weak[element] then return 1.5 end
  if def.resist and def.resist[element] then return 0.5 end
  return 1
end

local function unitOf(b, side, i)
  local list = side == "foe" and b.foes or b.allies
  return list and list[i]
end

local function standing(s, list)
  local out = {}
  for _, u in ipairs(list) do
    if alive(s, u) then out[#out + 1] = u end
  end
  return out
end

--- Physical numbers for either side.
local function power(s, u)
  if u.m then return party.stats(member(s, u)) end
  local def = enemies.FOES[u.id]
  return { atk = def.atk, def = def.def, mag = def.atk }
end

local function say(b, msg) b.msg = msg end
M.LABEL_LONGEST = 19

local function float(b, u, text, color, small)
  if #b.floats >= 6 then table.remove(b.floats, 1) end
  b.floats[#b.floats + 1] = { side = u.side, i = u.i, text = text, color = color, t = FLOAT_TICKS, small = small }
end

--- Tell the wall an element told.
local function elementNote(b, u, times)
  if times > 1 then float(b, u, "WEAK", "hi", true) elseif times < 1 then float(b, u, "RESIST", "line", true) end
end

local function emit(events, kind, u, n)
  events[#events + 1] = { type = kind, side = u and u.side, i = u and u.i, id = u and u.id, n = n }
end

local function statusClear(u)
  for _, status in ipairs(STATUS) do u[status] = 0 end
  u.guard, u.focus, u.hidden, u.braced = false, false, false, nil
  u.oath = 0
end

--- A battle saved before these statuses existed, or with an old menu open, plays on.
local function upgrade(b)
  if b.v == 2 then return end
  b.v = 2
  for _, list in ipairs({ b.allies, b.foes }) do
    for _, u in ipairs(list) do
      for _, status in ipairs(STATUS) do u[status] = u[status] or 0 end
      u.hidden, u.oath = u.hidden or false, u.oath or 0
    end
  end
  if b.pick == "steal" then b.pick, b.pickId = "spell", "steal" end
  if b.pick == "blood" then b.pick, b.pickId = "spell", "bleed" end
end

local function newFoe(id, i, rng)
  local def = enemies.FOES[id]
  local u = {
    side = "foe", i = i, id = id, hp = def.hp, mhp = def.hp, mp = def.mp, spd = def.spd, atb = rng(400),
    flash = 0, charge = 0, turns = 0,
  }
  statusClear(u)
  if def.boss then u.phase, u.called = 1, 0 end
  return u
end

function M.begin(s, encounterId, rng)
  local enc = enemies.ENCOUNTERS[encounterId]
  local b = {
    enc = encounterId, bg = enc.bg, boss = enc.boss or false, flee = enc.flee or false, mustLose = enc.mustLose or false,
    phase = "run", beat = BEAT, t = 0, msg = "", inbox = {}, allies = {}, foes = {}, floats = {}, v = 2,
  }
  for i, m in ipairs(s.party) do
    if i > party.IN_BATTLE then break end
    local u = { side = "ally", i = i, m = i, spd = party.stats(m).spd, atb = 300 + rng(500), flash = 0 }
    statusClear(u)
    b.allies[i] = u
  end
  for i, id in ipairs(enc.foes) do b.foes[i] = newFoe(id, i, rng) end
  say(b, b.boss and (enemies.FOES[enc.foes[1]].name .. "!") or "BATTLE!")
  s.battle, s.mode = b, "battle"
  s.rev = (s.rev or 0) + 1
end

-- ---------------------------------------------------------------- the end

local function finish(s, b, outcome, events)
  b.phase, b.outcome, b.wait = "spoils", outcome, SPOILS_TICKS
  b.active, b.list, b.pick, b.pickId = nil, nil, nil, nil
  for _, u in ipairs(b.allies) do statusClear(u) end
  if outcome == "won" then
    local xp, gold = 0, 0
    for _, f in ipairs(b.foes) do
      if not f.added then
        xp, gold = xp + enemies.FOES[f.id].xp, gold + enemies.FOES[f.id].gold
      end
    end
    local ups = {}
    for i, m in ipairs(s.party) do
      local share = i <= party.IN_BATTLE and xp or floor(xp * party.BENCH_SHARE / 100)
      if party.gainXp(m, share) > 0 then
        ups[#ups + 1] = { id = m.id, lvl = m.lvl }
        events[#events + 1] = { type = "levelup", id = m.id, lvl = m.lvl }
      end
      if m.id == "hero" then s.level = m.lvl end
    end
    s.score = s.score + xp
    s.gold = s.gold + gold
    b.spoils = { xp = xp, gold = gold, ups = ups }
    say(b, "VICTORY")
    events[#events + 1] = { type = "win" }
  elseif outcome == "fled" then
    say(b, "GOT AWAY")
    events[#events + 1] = { type = "fled" }
  else
    say(b, "THE PARTY FELL")
    events[#events + 1] = { type = "lose" }
  end
  -- nobody stays down after a fight that goes on: a fallen ally gets up with 1 HP, and the menu never meets a corpse
  if outcome ~= "lost" or b.mustLose then
    for _, m in ipairs(s.party) do
      if m.hp <= 0 then m.hp = 1 end
    end
  end
end

--- Has it ended? True if so.
local function settled(s, b, events)
  if b.phase == "spoils" then return true end
  if #standing(s, b.foes) == 0 then
    finish(s, b, "won", events)
  elseif #standing(s, b.allies) == 0 then
    finish(s, b, "lost", events)
  end
  return b.phase == "spoils"
end

-- ---------------------------------------------------------------- blows

local function fall(s, b, u, events)
  statusClear(u)
  u.atb, u.charge, u.charging = 0, 0, nil
  emit(events, u.m and "fall" or "kill", u)
end

--- Take n from a unit. A hit wakes the sleeping; a guard halves it.
local function hurt(s, b, u, n, events)
  n = max(1, n)
  if u.guard then n = ceil(n / M.GUARD_DIVIDE) end
  setHp(s, u, max(0, hpOf(s, u) - n))
  u.flash, u.sleep = 2, 0
  float(b, u, tostring(n), "text")
  emit(events, u.m and "hurt" or "hit", u, n)
  if not alive(s, u) then
    fall(s, b, u, events)
  elseif (u.thrall > 0 or u.tadpole > 0) and n * 100 >= maxHpOf(s, u) * M.BREAK_SHARE then
    u.thrall, u.tadpole = 0, 0
    float(b, u, "FREE", "ok", true)
    emit(events, "cure", u)
  end
  return n
end

local function mend(s, b, u, n, events)
  local room = maxHpOf(s, u) - hpOf(s, u)
  n = min(n, room)
  setHp(s, u, hpOf(s, u) + n)
  float(b, u, "+" .. n, "ok")
  emit(events, "heal", u, n)
  return n
end

--- A status lands, unless the target is immune. Returns true if it took.
local function afflict(s, b, u, status, events)
  if immuneTo(s, u, status) then
    float(b, u, "IMMUNE", "line")
    return false
  end
  if status == "poison" then
    if u.poison == 0 then u.poison = M.POISON_EVERY end
  else
    u[status] = LASTS[status]
    if status == "sleep" then u.guard, u.braced = false, nil end
  end
  float(b, u, status:upper(), "accent")
  emit(events, "status", u)
  return true
end

local function cure(b, u, list, events)
  local any = false
  for _, status in ipairs(list) do
    if u[status] > 0 then u[status], any = 0, true end
  end
  if any then
    float(b, u, "CURED", "soft")
    emit(events, "cure", u)
  end
  return any
end

--- A swing: armour takes half, a little luck either way. times multiplies the blow before armour. element, if given, stands in
-- for what the weapon carries.
local function strike(s, b, from, to, percent, rng, events, element)
  if to.hidden then
    float(b, to, "MISS", "line")
    emit(events, "miss", to)
    return nil
  end
  local sure = to.sleep > 0 or from.focus
  if not sure and rng(100) > (from.blind > 0 and BLIND_HIT_PERCENT or HIT_PERCENT) then
    float(b, to, "MISS", "line")
    emit(events, "miss", to)
    return nil
  end
  local mine = power(s, from)
  local raw = mine.atk * percent * (88 + rng(25)) / 10000
  if from.focus then
    raw = raw * party.focusOf(member(s, from)).times
    from.focus = false
  end
  if from.oath > 0 then
    raw = raw * OATH_PERCENT / 100
    from.oath = from.oath - 1
  end
  if rng(CRIT_ONE_IN) == 1 then raw = raw * 3 / 2 end
  if not from.m then emit(events, "foeStrike", from) end
  local times = elementTimes(s, to, element or mine.element)
  local dealt = hurt(s, b, to, floor((raw - power(s, to).def / 2) * times), events)
  elementNote(b, to, times)
  return dealt
end

local function maybeStatus(s, b, to, status, chance, rng, events)
  if status and alive(s, to) and rng(100) <= chance then return afflict(s, b, to, status, events) end
  return false
end

--- Spell damage against one foe: power plus magic, with little luck, and armour counts for a quarter.
local function blast(s, b, caster, to, spell, rng, events)
  local raw = (spell.power + power(s, caster).mag) * (94 + rng(13)) / 100
  local armour = spell.pierce and 0 or power(s, to).def / 4
  local times = elementTimes(s, to, spell.element)
  local dealt = hurt(s, b, to, floor((raw - armour) * times), events)
  elementNote(b, to, times)
  if alive(s, to) and spell.status then maybeStatus(s, b, to, spell.status, spell.chance, rng, events) end
  return dealt
end

-- ---------------------------------------------------------------- what the party can do

--- Pay in blood: never the last point.
local function payBlood(s, b, u, spell)
  if not spell.blood then return 0 end
  local m = member(s, u)
  local cost = max(1, floor(party.stats(m).hp / spell.blood))
  m.hp = max(1, m.hp - cost)
  float(b, u, tostring(cost), "red")
  return cost
end

--- A try at what a foe carries, once for each foe.
local function trySteal(s, b, u, foe, rng, events)
  local def = enemies.FOES[foe.id]
  local odds = def.boss and STEAL_BOSS_PERCENT or STEAL_PERCENT
  if foe.robbed or rng(100) > odds then
    say(b, nameOf(s, u) .. " GOT NOTHING")
    emit(events, "miss", foe)
    return false
  end
  foe.robbed = true
  local id = def.steal or "potion"
  s.bag[id] = (s.bag[id] or 0) + 1
  local got = party.ITEMS[id] or party.GEAR[id]
  say(b, nameOf(s, u) .. " STOLE " .. got.name)
  float(b, foe, got.name, "hi", true)
  emit(events, "item", foe)
  return true
end

--- One cut of a skill on one foe. Blind or sleeping foes can't see the open cut coming.
local function skillBlow(s, b, u, spell, foe, rng, events)
  local pct = spell.pct
  if spell.open and (foe.blind > 0 or foe.sleep > 0) then pct = spell.open end
  local dealt = strike(s, b, u, foe, pct, rng, events, spell.element)
  if dealt and spell.drain then
    local m = member(s, u)
    local back = min(party.stats(m).hp - m.hp, floor(dealt * spell.drain / 100))
    if back > 0 then
      m.hp = m.hp + back
      float(b, u, "+" .. back, "ok")
    end
  end
end

local function castOn(s, b, u, spell, target, rng, events)
  local st = power(s, u)
  if spell.kind == "damage" then
    blast(s, b, u, target, spell, rng, events)
  elseif spell.kind == "strike" then
    skillBlow(s, b, u, spell, target, rng, events)
  elseif spell.kind == "steal" then
    trySteal(s, b, u, target, rng, events)
  elseif spell.kind == "mug" then
    if strike(s, b, u, target, 100, rng, events) and alive(s, target) then trySteal(s, b, u, target, rng, events) end
  elseif spell.kind == "gold" then
    local cost = spell.cost * member(s, u).lvl
    s.gold = max(0, s.gold - cost)
    hurt(s, b, target, floor(st.atk * spell.pct * (94 + rng(13)) / 10000), events)
  elseif spell.kind == "vanish" then
    u.hidden = true
    float(b, u, "GONE", "info")
  elseif spell.kind == "oath" then
    u.oath = spell.turns
    float(b, u, "OATH", "red")
  elseif spell.kind == "transfuse" then
    mend(s, b, target, 2 * floor(party.stats(member(s, u)).hp / spell.blood), events)
  elseif spell.kind == "heal" then
    mend(s, b, target, spell.power + 2 * st.mag, events)
    if spell.cures then cure(b, target, spell.cures, events) end
  elseif spell.kind == "raise" then
    local m = member(s, target)
    m.hp = max(1, floor(party.stats(m).hp * spell.power / 100))
    float(b, target, "RISE", "ok")
    emit(events, "heal", target, m.hp)
  elseif spell.kind == "cure" then
    if not cure(b, target, spell.cures, events) then float(b, target, "NOTHING", "line") end
  else
    if not maybeStatus(s, b, target, spell.status, spell.chance, rng, events) then float(b, target, "RESISTED", "line") end
  end
end

--- Back to running time after someone's turn.
local function endTurn(s, b, u, events)
  u.atb = 0
  b.phase, b.active, b.list, b.pick, b.pickId = "run", nil, nil, nil, nil
  b.beat = BEAT
  settled(s, b, events)
end

local function doSpell(s, b, u, id, target, rng, events)
  local spell = party.SPELLS[id]
  local m = member(s, u)
  m.mp = m.mp - spell.mp
  payBlood(s, b, u, spell)
  say(b, nameOf(s, u) .. ": " .. spell.name)
  emit(events, "spell", u)
  if spell.hits then
    -- so many cuts, each at whoever still stands
    for _ = 1, spell.hits do
      local list = standing(s, b.foes)
      if #list > 0 then castOn(s, b, u, spell, list[rng(#list)], rng, events) end
    end
  elseif spell.target == "foes" then
    for _, f in ipairs(standing(s, b.foes)) do castOn(s, b, u, spell, f, rng, events) end
  elseif spell.target == "allies" then
    for _, a in ipairs(standing(s, b.allies)) do castOn(s, b, u, spell, a, rng, events) end
  else
    castOn(s, b, u, spell, target or u, rng, events)
  end
  endTurn(s, b, u, events)
end

local function doItem(s, b, u, id, target, events)
  local item = party.ITEMS[id]
  s.bag[id] = s.bag[id] - 1
  if s.bag[id] <= 0 then s.bag[id] = nil end
  local gained, mp = party.applyItem(member(s, target), id)
  if gained > 0 then
    float(b, target, "+" .. gained, "ok")
    emit(events, "heal", target, gained)
  elseif mp > 0 then
    float(b, target, "+" .. mp .. "MP", "info")
  end
  if item.cures then cure(b, target, item.cures, events) end
  say(b, nameOf(s, u) .. " USES " .. item.name)
  emit(events, "item", target)
  endTurn(s, b, u, events)
end

local function doAttack(s, b, u, foe, rng, events)
  local sweeping = u.focus and party.focusOf(member(s, u)).sweep
  local dealt = strike(s, b, u, foe, 100, rng, events)
  say(b, dealt and (nameOf(s, u) .. " HITS FOR " .. dealt) or (nameOf(s, u) .. " MISSES"))
  if sweeping and dealt then
    for _, f in ipairs(standing(s, b.foes)) do
      if f ~= foe then strike(s, b, u, f, 50, rng, events) end
    end
  end
  endTurn(s, b, u, events)
end

local function doFlee(s, b, u, rng, events)
  local fast, slow = 0, 0
  local them, us = standing(s, b.foes), standing(s, b.allies)
  for _, f in ipairs(them) do slow = slow + f.spd end
  for _, a in ipairs(us) do fast = fast + a.spd end
  local odds = max(30, min(95, 60 + floor(5 * (fast / #us - slow / #them))))
  if rng(100) <= odds then
    finish(s, b, "fled", events)
  else
    say(b, "NO WAY OUT")
    emit(events, "miss", u)
    endTurn(s, b, u, events)
  end
end

-- ---------------------------------------------------------------- the menus

local function fallen(s, b)
  for _, u in ipairs(b.allies) do
    if not alive(s, u) then return true end
  end
  return false
end

--- Can this member use this spell now? The menu and the bot ask the same question.
local function spellOk(s, b, u, id)
  local spell, m = party.SPELLS[id], member(s, u)
  if m.mp < spell.mp then return false end
  if u.silence > 0 and party.CHARS[m.id].chants then return false end
  if spell.target == "fallen" and not fallen(s, b) then return false end
  if spell.kind == "gold" and s.gold < spell.cost * m.lvl then return false end
  return true
end

--- A spell's price, for the row.
local function costNote(s, m, spell)
  if spell.blood then return floor(party.stats(m).hp / spell.blood) .. "HP" end
  if spell.kind == "gold" then return spell.cost * m.lvl .. "G" end
  if spell.mp > 0 then return spell.mp .. "MP" end
  return ""
end

--- Every row of the open list, before paging.
local function allRows(s, b)
  local out = {}
  local u = b.allies[b.active]
  local m = member(s, u)
  if b.list == "special" then
    for _, id in ipairs(party.known(m)) do
      local spell = party.SPELLS[id]
      out[#out + 1] = { kind = "spell", id = id, name = spell.name, note = costNote(s, m, spell), ok = spellOk(s, b, u, id) }
    end
  elseif b.list == "item" then
    for _, id in ipairs(party.ITEM_ORDER) do
      local n, item = s.bag[id] or 0, party.ITEMS[id]
      if n > 0 and not item.key and not item.camp then
        local ok = item.target ~= "fallen" or fallen(s, b)
        out[#out + 1] = { kind = "item", id = id, name = item.name, note = "x" .. n, ok = ok }
      end
    end
    if b.flee then out[#out + 1] = { kind = "flee", id = "flee", name = "FLEE", note = "", ok = true } end
  end
  return out
end

--- The rows on screen: { kind, id, name, note, ok }, tapped by position. A long list shows a page and a MORE row, which goes round.
function M.rows(s)
  local b = s.battle
  if not b or not b.active then return {} end
  local all = allRows(s, b)
  if #all <= LIST_ROWS then return all end
  local room = LIST_ROWS - 1
  local top = min(b.top or 0, #all - 1)
  local out = {}
  for i = top + 1, min(#all, top + room) do out[#out + 1] = all[i] end
  local page = floor(top / room) + 1
  out[#out + 1] = { kind = "more", id = "more", name = "MORE", note = page .. "/" .. ceil(#all / room), ok = true }
  return out
end

local function nextPage(s, b)
  local room = LIST_ROWS - 1
  b.top = (b.top or 0) + room
  if b.top >= #allRows(s, b) then b.top = 0 end
end

--- Who may be tapped now: side, and a list of indexes.
function M.targets(s)
  local b = s.battle
  local out = {}
  if not b or b.phase ~= "target" then return nil, out end
  local want
  if b.pick == "spell" then
    want = party.SPELLS[b.pickId].target
  elseif b.pick == "item" then
    want = party.ITEMS[b.pickId].target
  else
    want = "foe"
  end
  if want == "foe" then
    for i, f in ipairs(b.foes) do
      if alive(s, f) then out[#out + 1] = i end
    end
    return "foe", out
  end
  for i, a in ipairs(b.allies) do
    local up = alive(s, a)
    if want == "any" or (want == "ally" and up) or (want == "fallen" and not up) then out[#out + 1] = i end
  end
  return "ally", out
end

local function ask(b, pick, id, msg)
  b.phase, b.pick, b.pickId = "target", pick, id
  say(b, msg)
end

local function openMenu(s, b, i, events)
  local u = b.allies[i]
  -- a guard lasts until your next turn, and so does a vanishing. A guard raised against a wind-up holds until the blow lands,
  -- so a DEFEND in time is never wasted however many turns come before it
  if not u.braced then u.guard = false end
  u.hidden = false
  b.phase, b.active, b.list, b.pick, b.pickId = "cmd", i, nil, nil, nil
  say(b, nameOf(s, u) .. " IS READY")
  emit(events, "menu", u)
end

local function chooseSpecial(s, b, u, rng, events)
  local m = member(s, u)
  local special = party.CHARS[m.id].special
  if special == "FOCUS" then
    -- it doesn't stack, so a second one would only waste the turn: the menu stays open
    if u.focus then
      say(b, "ALREADY FOCUSED")
      return
    end
    u.focus = true
    if party.focusOf(m).brace then
      u.guard = true
      if M.blowIn(b) then u.braced = true end
    end
    say(b, "NEXT HIT IS STRONGER")
    float(b, u, "FOCUS", "hi")
    emit(events, "focus", u)
    endTurn(s, b, u, events)
    return
  end
  local known = party.known(m)
  if (special == "STEAL" or special == "BLOOD") and #known == 1 then
    ask(b, "spell", known[1], special) -- one skill needs no list
  else
    b.phase, b.list, b.top = "list", "special", 0
    say(b, special)
  end
end

local function chooseCommand(s, b, u, cmd, rng, events)
  if cmd == "attack" then
    ask(b, "attack", nil, "ATTACK")
  elseif cmd == "special" then
    chooseSpecial(s, b, u, rng, events)
  elseif cmd == "defend" then
    -- braced already, a second DEFEND would only waste the turn: the menu stays open
    if u.braced then
      say(b, "ALREADY GUARDING")
      return
    end
    u.guard = true
    if M.blowIn(b) then u.braced = true end
    say(b, nameOf(s, u) .. " DEFENDS")
    float(b, u, "GUARD", "info")
    emit(events, "defend", u)
    endTurn(s, b, u, events)
  elseif cmd == "item" then
    b.list, b.top = "item", 0
    if #M.rows(s) == 0 then
      b.list = nil
      say(b, "NOTHING IN THE BAG")
    else
      b.phase = "list"
      say(b, "ITEM")
    end
  elseif cmd == "flee" and b.flee then
    doFlee(s, b, u, rng, events)
  end
end

local function choosePick(s, b, u, i, rng, events)
  local row = M.rows(s)[i]
  if not row then return end
  if not row.ok then
    say(b, "CAN'T USE THAT NOW")
    return
  end
  if row.kind == "more" then
    nextPage(s, b)
  elseif row.kind == "flee" then
    doFlee(s, b, u, rng, events)
  elseif row.kind == "item" then
    ask(b, "item", row.id, row.name .. " ON WHO?")
  else
    local want = party.SPELLS[row.id].target
    if want == "foes" or want == "allies" or want == "self" then
      doSpell(s, b, u, row.id, nil, rng, events)
    else
      ask(b, "spell", row.id, row.name .. " ON WHO?")
    end
  end
end

local function chooseTarget(s, b, u, action, rng, events)
  local side, list = M.targets(s)
  if action.side ~= side then return end
  local valid = false
  for _, i in ipairs(list) do valid = valid or i == action.i end
  if not valid then return end
  local target = unitOf(b, side, action.i)
  if b.pick == "attack" then
    doAttack(s, b, u, target, rng, events)
  elseif b.pick == "spell" then
    doSpell(s, b, u, b.pickId, target, rng, events)
  else
    doItem(s, b, u, b.pickId, target, events)
  end
end

local function goBack(s, b, u)
  if b.phase == "target" and b.list then
    b.phase, b.pick, b.pickId = "list", nil, nil
    say(b, b.list == "item" and "ITEM" or party.CHARS[member(s, u).id].special)
  elseif b.phase == "target" or b.phase == "list" then
    b.phase, b.pick, b.pickId, b.list = "cmd", nil, nil, nil
    say(b, nameOf(s, u) .. " IS READY")
  end
end

local function handle(s, b, action, rng, events)
  if b.phase == "spoils" then
    if (action.kind == "tap" or action.kind == "act") and b.wait <= SPOILS_TICKS - SPOILS_MIN then b.wait = 0 end
    return
  end
  local u = b.active and b.allies[b.active]
  if not u then return end
  if action.kind == "back" then
    goBack(s, b, u)
  elseif b.phase == "cmd" and action.kind == "cmd" then
    chooseCommand(s, b, u, action.cmd, rng, events)
  elseif b.phase == "list" and action.kind == "pick" then
    choosePick(s, b, u, action.i, rng, events)
  elseif b.phase == "target" and action.kind == "target" then
    chooseTarget(s, b, u, action, rng, events)
  end
end

--- Queue a tap. No chance here: it takes effect in the tick.
function M.input(s, action)
  local b = s.battle
  if not b or b.result or not action or #b.inbox >= 4 then return end
  local copy = {}
  for k, v in pairs(action) do copy[k] = v end
  b.inbox[#b.inbox + 1] = copy
end

-- ---------------------------------------------------------------- foes acting

--- Who does what, across the top in big letters. A long pair loses the name: what's coming matters more.
local function foeLabel(s, u, ab)
  local label = nameOf(s, u) .. ": " .. ab.name
  return #label <= M.LABEL_LONGEST and label or ab.name
end
M.foeLabel = foeLabel

--- Whoever a foe's blow finds: never one of its own thralls, while anyone else stands.
local function randomAlly(s, b, rng)
  local list = standing(s, b.allies)
  local free = {}
  for _, a in ipairs(list) do
    if a.thrall == 0 and a.tadpole == 0 then free[#free + 1] = a end
  end
  if #free > 0 then list = free end
  return list[rng(#list)]
end

--- A helper takes a fallen helper's place, or a new one. Never a fallen boss's, whose XP is still owed.
local function summon(s, b, u, id, rng, events)
  local slot
  for i, f in ipairs(b.foes) do
    if f.added and not alive(s, f) then slot = slot or i end
  end
  slot = slot or #b.foes + 1
  local added = newFoe(id, slot, rng)
  added.added = true
  b.foes[slot] = added
  emit(events, "phase", added)
end

--- One ability, on whoever it reaches. The caller has already said it.
local function useAbility(s, b, u, id, rng, events)
  local ab = enemies.ABILITIES[id]
  u.mp = u.mp - (ab.mp or 0)
  if ab.target == "summon" then
    u.called = (u.called or 0) + 1
    summon(s, b, u, ab.summon or enemies.FOES[u.id].boss.phases[u.phase].summon, rng, events)
  elseif ab.target == "friend" then
    local worst, share
    for _, f in ipairs(standing(s, b.foes)) do
      local here = f.hp * 100 / f.mhp
      if not worst or here < share then worst, share = f, here end
    end
    mend(s, b, worst, ab.power + floor(power(s, u).atk / 2) + floor(worst.mhp * (ab.share or 0) / 100), events)
  else
    local list = ab.target == "all" and standing(s, b.allies) or { randomAlly(s, b, rng) }
    for _, to in ipairs(list) do
      local dealt
      if not ab.power then
        dealt = true -- nothing but the status
      elseif to.hidden then
        float(b, to, "MISS", "line")
        emit(events, "miss", to)
      elseif ab.magic then
        local times = elementTimes(s, to, ab.element)
        dealt = hurt(s, b, to, floor(power(s, u).atk * ab.power * (94 + rng(13)) / 10000 * times), events)
        elementNote(b, to, times)
      else
        dealt = strike(s, b, u, to, ab.power, rng, events, ab.element)
      end
      if dealt then maybeStatus(s, b, to, ab.status, ab.chance or 0, rng, events) end
    end
  end
end

--- The ticks a foe's windup still has, or nil. A player can plan on this.
function M.blowIn(b)
  local soonest
  for _, f in ipairs(b.foes) do
    if f.charge > 0 and (not soonest or f.charge < soonest) then soonest = f.charge end
  end
  return soonest
end

local function bossPhase(s, b, u, events)
  local def = enemies.FOES[u.id]
  local now = enemies.phaseOf(def, u.hp * 100 / u.mhp)
  if now <= u.phase then return false end
  u.phase = now
  local phase = def.boss.phases[now]
  u.spd = u.spd + (phase.speedUp or 0)
  if phase.say then say(b, phase.say) end
  emit(events, "phase", u)
  b.beat = TELEGRAPH_BEAT
  return true
end

local function foeTurn(s, b, u, rng, events)
  u.atb = 0
  b.beat = BEAT
  if u.phase and bossPhase(s, b, u, events) then return end
  u.turns = u.turns + 1
  local others, adds, hurtFriend = 0, 0, false
  for _, f in ipairs(standing(s, b.foes)) do
    if f ~= u then others = others + 1 end
    if f.added then adds = adds + 1 end
    if f.hp * 3 < f.mhp * 2 then hurtFriend = true end
  end
  local ctx = { others = others, adds = adds, hurt = hurtFriend, room = others + 1 < MAX_STANDING, silent = u.silence > 0 }
  local id = enemies.choose(u, ctx, rng)
  local ab = enemies.ABILITIES[id]
  if ab.windup then
    u.charge, u.charging = ab.windup, id
    say(b, ab.warn)
    float(b, u, "!!!", "warn")
    emit(events, "telegraph", u)
    b.beat = TELEGRAPH_BEAT
    return
  end
  say(b, foeLabel(s, u, ab))
  useAbility(s, b, u, id, rng, events)
  settled(s, b, events)
end

--- A nightmare's turn: swing at anyone at all, on either side.
local function nightmareTurn(s, b, u, rng, events)
  u.atb = 0
  u.nightmare = u.nightmare - 1
  b.beat = BEAT
  local anyone = {}
  for _, list in ipairs({ b.allies, b.foes }) do
    for _, other in ipairs(standing(s, list)) do
      if other ~= u then anyone[#anyone + 1] = other end
    end
  end
  say(b, nameOf(s, u) .. " THRASHES")
  if #anyone > 0 then strike(s, b, u, anyone[rng(#anyone)], 100, rng, events) end
  settled(s, b, events)
end

--- A thrall's or a tadpole's turn: they turn on their own side, with no menu. A tadpole lashes with the mind, past armour.
local function traitorTurn(s, b, u, status, rng, events)
  u.atb = 0
  u[status] = u[status] - 1
  b.beat = BEAT
  local mates = {}
  for _, other in ipairs(standing(s, u.m and b.allies or b.foes)) do
    if other ~= u then mates[#mates + 1] = other end
  end
  if #mates == 0 then
    say(b, nameOf(s, u) .. " STANDS LOST")
    return
  end
  local to = mates[rng(#mates)]
  say(b, nameOf(s, u) .. " TURNS ON " .. nameOf(s, to))
  if status == "thrall" then
    strike(s, b, u, to, 100, rng, events)
  else
    local mine = power(s, u)
    hurt(s, b, to, floor(max(mine.mag, mine.atk) * (94 + rng(13)) / 100), events)
  end
  settled(s, b, events)
end

--- One taken-over turn, if this unit isn't its own. True if so.
local function lostTurn(s, b, u, rng, events)
  if u.thrall > 0 then
    traitorTurn(s, b, u, "thrall", rng, events)
  elseif u.tadpole > 0 then
    traitorTurn(s, b, u, "tadpole", rng, events)
  elseif u.nightmare > 0 then
    nightmareTurn(s, b, u, rng, events)
  else
    return false
  end
  return true
end

-- ---------------------------------------------------------------- time

local function poisonSting(s, b, u, events)
  u.poison = u.poison - 1
  if u.poison > 0 then return end
  u.poison = M.POISON_EVERY
  local hp = hpOf(s, u)
  if hp <= 1 then return end
  local n = min(hp - 1, max(1, floor(maxHpOf(s, u) / M.POISON_SHARE)))
  setHp(s, u, hp - n)
  u.flash = 1
  float(b, u, tostring(n), "soft")
  emit(events, "sting", u, n)
end

--- One tick of running time for one unit.
local function age(s, b, u, events)
  if u.poison > 0 then poisonSting(s, b, u, events) end
  if u.blind > 0 then u.blind = u.blind - 1 end
  if u.silence > 0 then u.silence = u.silence - 1 end
  if u.doom > 0 then
    u.doom = u.doom - 1
    if u.doom == 0 then
      setHp(s, u, 0)
      float(b, u, "DOOM", "red")
      fall(s, b, u, events)
      return
    end
  end
  if u.sleep > 0 then
    u.sleep = u.sleep - 1
  elseif (u.charge or 0) == 0 then
    u.atb = min(M.GAUGE, u.atb + M.gain(u.spd))
  end
end

--- Running time. Only ever called with no menu open. Stops at the first thing that needs the wall's attention.
local function advance(s, b, rng, events)
  for _, list in ipairs({ b.allies, b.foes }) do
    for _, u in ipairs(list) do
      if alive(s, u) then age(s, b, u, events) end
    end
  end
  if settled(s, b, events) then return end -- doom can end a fight
  for _, f in ipairs(b.foes) do
    if alive(s, f) and f.charge > 0 then
      f.charge = f.charge - 1
      if f.charge == 0 then
        local ab = enemies.ABILITIES[f.charging]
        say(b, foeLabel(s, f, ab))
        emit(events, "cavein", f)
        useAbility(s, b, f, f.charging, rng, events)
        f.charging = nil
        f.atb = 0
        b.beat = TELEGRAPH_BEAT
        -- a guard raised against it has done its job, and from here lasts until that ally's next turn as any other
        if not M.blowIn(b) then
          for _, a in ipairs(b.allies) do a.braced = nil end
        end
        settled(s, b, events)
        return
      end
    end
  end
  for _, f in ipairs(b.foes) do
    if alive(s, f) and f.atb >= M.GAUGE and f.sleep == 0 and f.charge == 0 then
      if not lostTurn(s, b, f, rng, events) then foeTurn(s, b, f, rng, events) end
      return
    end
  end
  for i, u in ipairs(b.allies) do
    if alive(s, u) and u.atb >= M.GAUGE and u.sleep == 0 then
      if not lostTurn(s, b, u, rng, events) then openMenu(s, b, i, events) end
      return
    end
  end
end

--- Floats and flashes fade whatever the phase. True if anything on the wall changed.
local function fade(b)
  local changed = false
  for i = #b.floats, 1, -1 do
    local f = b.floats[i]
    f.t = f.t - 1
    changed = true
    if f.t <= 0 then table.remove(b.floats, i) end
  end
  for _, list in ipairs({ b.allies, b.foes }) do
    for _, u in ipairs(list) do
      if u.flash > 0 then
        u.flash = u.flash - 1
        changed = true
      end
    end
  end
  return changed
end

function M.tick(s, rng)
  local events = {}
  local b = s.battle
  if not b or b.result then return events end
  upgrade(b)
  b.t = b.t + 1
  local changed = fade(b)
  local inbox = b.inbox
  b.inbox = {}
  for _, action in ipairs(inbox) do
    handle(s, b, action, rng, events)
    changed = true
  end
  if b.phase == "run" then
    changed = true
    if b.beat > 0 then
      b.beat = b.beat - 1
    else
      advance(s, b, rng, events)
    end
  elseif b.phase == "spoils" then
    b.wait = b.wait - 1
    if b.wait <= 0 then
      b.result = b.outcome
      changed = true
    end
  elseif (b.phase == "target" or M.blowIn(b)) and b.t % BLINK_TICKS == 0 then
    changed = true
  end
  if changed then s.rev = s.rev + 1 end
  return events
end

-- ---------------------------------------------------------------- the bot

local HEAL_ITEMS = { "potion", "hipotion", "xpotion" } -- smallest first
local RAISE_ITEMS = { "feather", "tonic" }
local CURE_ITEMS = { "eyewash", "echoherb", "wakeroot", "lastrites", "panacea" } -- a tonic is for raising, so it isn't here
local CURE_ORDER = { "doom", "thrall", "tadpole", "sleep", "nightmare", "silence", "blind" } -- what matters most first

--- Does this status on this ally need a turn spent on it? Silence means nothing to a fighter, nor blindness to a caster.
local function worthCuring(s, u, status)
  if u[status] == 0 then return false end
  local ch = party.CHARS[member(s, u).id]
  if status == "silence" then return ch.chants == true end
  if status == "blind" then return not ch.chants end
  return true
end

local function cures(list, status)
  for _, id in ipairs(list or {}) do
    if id == status then return true end
  end
  return false
end

--- Who needs what: the party seen from one member's menu. Takes no chance.
local function survey(s, b)
  local out = { lowShare = 101, lowCount = 0, healer = false }
  for i, a in ipairs(b.allies) do
    if alive(s, a) then
      local share = hpOf(s, a) * 100 / maxHpOf(s, a)
      if share < out.lowShare then out.lowest, out.lowShare = i, share end
      if share < 50 then out.lowCount = out.lowCount + 1 end
      if a.poison > 0 then out.sick = out.sick or i end
      local mate = member(s, a)
      for _, id in ipairs(party.known(mate)) do
        local spell = party.SPELLS[id]
        if spell.kind == "heal" and mate.mp >= spell.mp and a.sleep == 0 and spellOk(s, b, a, id) then out.healer = true end
      end
    else
      out.down = out.down or i
    end
  end
  for _, status in ipairs(CURE_ORDER) do
    for i, a in ipairs(b.allies) do
      if alive(s, a) and not out.troubled and worthCuring(s, a, status) then out.troubled, out.trouble = i, status end
    end
  end
  return out
end

--- The foes as the bot sees them: the weakest first, so the fight shrinks.
local function sizeUp(s, b)
  local out = { count = 0 }
  for i, f in ipairs(b.foes) do
    if alive(s, f) then
      out.count = out.count + 1
      if not out.hp or f.hp < out.hp then out.hp, out.weakest = f.hp, i end
    end
  end
  return out
end

--- A reasonable player's whole decision for the member on turn: { cmd, row, side, i }. It takes no chance, so asking again at the
-- next menu gives the same answer, and the bot needs no memory.
local function plan(s, b)
  local u = b.allies[b.active]
  local m = member(s, u)
  local st = party.stats(m)
  local special = party.CHARS[m.id].special
  local need = survey(s, b)
  local usable, knows = {}, {}
  for _, id in ipairs(party.known(m)) do
    knows[id] = true
    if spellOk(s, b, u, id) then usable[#usable + 1] = id end
  end
  local function can(id) return knows[id] and spellOk(s, b, u, id) end
  local function has(id) return (s.bag[id] or 0) > 0 end
  local function cast(id, side, i) return { cmd = "special", row = id, side = side, i = i } end
  local function use(id, i) return { cmd = "item", row = id, side = "ally", i = i } end

  local function strongest(kind, target)
    local best
    for _, id in ipairs(usable) do
      local spell = party.SPELLS[id]
      if spell.kind == kind and spell.target == target and (not best or spell.power > party.SPELLS[best].power) then best = id end
    end
    return best
  end

  --- The cheapest heal of that reach that does the job, or the strongest there is.
  local function heal(target, missing)
    local fits
    for _, id in ipairs(usable) do
      local spell = party.SPELLS[id]
      if spell.kind == "heal" and spell.target == target and spell.power + 2 * st.mag >= missing then
        if not fits or spell.mp < party.SPELLS[fits].mp then fits = id end
      end
    end
    return fits or strongest("heal", target)
  end

  local function healLowest()
    local a = b.allies[need.lowest]
    local missing = maxHpOf(s, a) - hpOf(s, a)
    if need.lowCount >= 2 then
      local all = heal("allies", missing * 7 / 10)
      if all then return cast(all) end
    end
    local one = heal("ally", missing)
    if one then return cast(one, "ally", need.lowest) end
    if can("transfuse") and need.lowest ~= b.active and m.hp * 100 >= st.hp * 60 then return cast("transfuse", "ally", need.lowest) end
    local stock
    for _, id in ipairs(HEAL_ITEMS) do
      if has(id) and (not stock or party.ITEMS[stock].hp < missing) then stock = id end
    end
    if not stock and need.lowShare < 25 and has("elixir") then stock = "elixir" end
    return stock and use(stock, need.lowest) or nil
  end

  -- a telegraphed blow: brace once, then get on with it, unless someone won't live through it even braced
  if M.blowIn(b) and not u.braced then
    local worst = 0
    for _, f in ipairs(b.foes) do
      if f.charging then
        local ab = enemies.ABILITIES[f.charging]
        worst = max(worst, ceil(enemies.FOES[f.id].atk * (ab.power or 0) * 106 / 10000 / M.GUARD_DIVIDE))
      end
    end
    if hpOf(s, b.allies[need.lowest]) <= worst and need.lowest ~= b.active then
      local help = healLowest()
      if help then return help end
    end
    if can("vanish") then return cast("vanish") end
    return { cmd = "defend" }
  end

  if need.down then
    local raise = strongest("raise", "fallen")
    if raise then return cast(raise, "ally", need.down) end
    for _, id in ipairs(RAISE_ITEMS) do
      if has(id) then return use(id, need.down) end
    end
  end

  local cheapest
  for _, id in ipairs(party.known(m)) do
    local spell = party.SPELLS[id]
    if spell.kind == "heal" and spell.target == "ally" and (not cheapest or spell.mp < cheapest) then cheapest = spell.mp end
  end
  local urgent = need.lowShare < 28
  if need.lowShare < 45 and (urgent or cheapest or not need.healer) then
    local help = healLowest()
    if help then return help end
  end

  if need.troubled then
    for _, id in ipairs(usable) do
      local spell = party.SPELLS[id]
      if spell.kind == "cure" and spell.target == "ally" and cures(spell.cures, need.trouble) then
        return cast(id, "ally", need.troubled)
      end
    end
    for _, id in ipairs(CURE_ITEMS) do
      if has(id) and cures(party.ITEMS[id].cures, need.trouble) then return use(id, need.troubled) end
    end
  end

  -- the healer out of MP is the fight lost; the mage out of MP only slows it
  if special == "PRAY" and cheapest and m.mp < cheapest then
    if has("hiether") then return use("hiether", b.active) end
    if has("ether") then return use("ether", b.active) end
    if b.boss and has("elixir") then return use("elixir", b.active) end
  end
  if special == "MAGIC" and b.boss and m.mp * 4 < st.mp then
    if has("hiether") then return use("hiether", b.active) end
    if has("ether") then return use("ether", b.active) end
  end

  if need.sick and m.mp * 5 > st.mp * 2 then
    for _, id in ipairs(usable) do
      local spell = party.SPELLS[id]
      if spell.kind == "cure" and cures(spell.cures, "poison") then return cast(id, "ally", need.sick) end
    end
  end

  -- on the attack
  local foes = sizeUp(s, b)
  local foe = b.foes[foes.weakest]
  local atkNow = (st.atk - enemies.FOES[foe.id].def / 2) * elementTimes(s, foe, st.element)

  local function worth(id, f)
    local spell, def = party.SPELLS[id], enemies.FOES[f.id]
    return (spell.power + st.mag - (spell.pierce and 0 or def.def / 4)) * elementTimes(s, f, spell.element)
  end

  local function spend(id)
    local cost = party.SPELLS[id].mp
    if special == "PRAY" and m.mp * 2 <= st.mp then return false end -- that MP is for healing
    return b.boss or cost <= 6 or cost * 7 <= st.mp
  end

  if special == "STEAL" and b.boss then
    for i, f in ipairs(b.foes) do
      if alive(s, f) and not f.robbed and enemies.FOES[f.id].steal then
        return cast(can("mug") and "mug" or "steal", "foe", i)
      end
    end
  end

  if special == "STEAL" and #usable > 1 then
    if foes.count >= 2 and can("fourcuts") then return cast("fourcuts") end
    if foes.count >= 2 and can("bladefan") then return cast("bladefan") end
    if can("backstab") and (foe.blind > 0 or foe.sleep > 0) then return cast("backstab", "foe", foes.weakest) end
    if can("grit") and foe.blind == 0 and foes.hp > 3 * atkNow and not immuneTo(s, foe, "blind") then return cast("grit", "foe", foes.weakest) end
    if can("fourcuts") and foes.hp > 3 * atkNow then return cast("fourcuts") end
  end

  if special == "BLOOD" then
    local share = m.hp * 100 / st.hp
    if can("leech") and share < 50 then return cast("leech", "foe", foes.weakest) end
    if b.boss and can("redoath") and u.oath == 0 and share > 75 then return cast("redoath") end
    if can("bloodwave") and foes.count >= 2 and share >= 55 then return cast("bloodwave") end
    if foes.hp > 3 * atkNow and share >= 55 then
      if can("hemorrhage") and share >= 75 then return cast("hemorrhage", "foe", foes.weakest) end
      return cast("bleed", "foe", foes.weakest)
    end
  end

  -- flasks and storms for a crowd
  if foes.count >= 2 then
    local best, score
    for _, id in ipairs(usable) do
      local spell = party.SPELLS[id]
      if spell.kind == "damage" and spell.target == "foes" and spend(id) then
        local total = 0
        for _, f in ipairs(standing(s, b.foes)) do total = total + min(f.hp, worth(id, f)) end
        if not best or total > score then best, score = id, total end
      end
    end
    if best then return cast(best) end
  end

  --- The cheapest spell that finishes the weakest, or the hardest hit that can be paid for.
  local function bestSingle()
    local best, finisher
    for _, id in ipairs(usable) do
      local spell = party.SPELLS[id]
      if spell.kind == "damage" and spell.target == "foe" and spend(id) then
        local hit = worth(id, foe)
        if hit >= foes.hp and (not finisher or spell.mp < party.SPELLS[finisher].mp) then finisher = id end
        if not best or hit > worth(best, foe) then best = id end
      end
    end
    return finisher or best
  end

  if special ~= "FOCUS" and special ~= "MAGIC" and foes.count == 1 and foes.hp > 4 * atkNow then
    local id = bestSingle()
    if id then return cast(id, "foe", foes.weakest) end
  end
  if special == "FOCUS" and not u.focus and foes.hp > 3 * power(s, u).atk then return { cmd = "special" } end
  if special == "MAGIC" then
    local id = bestSingle()
    if id then return cast(id, "foe", foes.weakest) end
    -- a field budget that leaves nothing affordable still beats a mage's stick
    for _, spellId in ipairs(usable) do
      if party.SPELLS[spellId].kind == "damage" and party.SPELLS[spellId].target == "foe" then return cast(spellId, "foe", foes.weakest) end
    end
  end
  return { cmd = "attack", side = "foe", i = foes.weakest }
end

--- A reasonable player: an action, or nil when there is nothing to tap.
function M.bot(s)
  local b = s.battle
  if not b or b.result then return nil end
  upgrade(b)
  if b.phase == "spoils" then return { kind = "tap" } end
  if b.phase == "run" then return nil end
  local want = plan(s, b)
  if b.phase == "cmd" then return { kind = "cmd", cmd = want.cmd } end
  if b.phase == "list" then
    local rows = M.rows(s)
    for i, row in ipairs(rows) do
      if row.id == want.row and row.ok then return { kind = "pick", i = i } end
    end
    for _, row in ipairs(allRows(s, b)) do
      if row.id == want.row and row.ok and rows[#rows].kind == "more" then return { kind = "pick", i = #rows } end
    end
    return { kind = "back" }
  end
  local side, list = M.targets(s)
  if want.side == side then
    for _, i in ipairs(list) do
      if i == want.i then return { kind = "target", side = side, i = i } end
    end
  end
  if list[1] then return { kind = "target", side = side, i = list[1] } end
  return { kind = "back" }
end

return M
