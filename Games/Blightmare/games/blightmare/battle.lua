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
M.FOCUS_TIMES = 3
M.GUARD_DIVIDE = 2

local BEAT = 5            -- ticks an action stays on the wall before time moves on
local TELEGRAPH_BEAT = 9
local SPOILS_TICKS = 40   -- the end card goes by itself
local SPOILS_MIN = 6      -- and a tap can't skip it before it has been seen
local FLOAT_TICKS = 8
local HIT_PERCENT = 95
local CRIT_ONE_IN = 16
local BLOOD_SHARE = 6     -- BLOOD costs this fraction of max HP
local STEAL_PERCENT = 55
local BLINK_TICKS = 3     -- how often a blinking ring repaints

local STATUS = { "poison", "sleep", "nightmare" } -- a fixed order, because pairs isn't one

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
    return id == "hero" and s.heroName and s.heroName:upper() or party.CHARS[id].name
  end
  local def = enemies.FOES[u.id]
  return def.short or def.name
end

local function immuneTo(s, u, status)
  local list
  if u.m then list = party.CHARS[member(s, u).id].immune else list = enemies.FOES[u.id].immune end
  return list and list[status]
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

local function float(b, u, text, color)
  if #b.floats >= 6 then table.remove(b.floats, 1) end
  b.floats[#b.floats + 1] = { side = u.side, i = u.i, text = text, color = color, t = FLOAT_TICKS }
end

local function emit(events, kind, u, n)
  events[#events + 1] = { type = kind, side = u and u.side, i = u and u.i, id = u and u.id, n = n }
end

local function statusClear(u)
  u.poison, u.sleep, u.nightmare = 0, 0, 0
  u.guard, u.focus = false, false
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
    phase = "run", beat = BEAT, t = 0, msg = "", inbox = {}, allies = {}, foes = {}, floats = {},
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
    for _, m in ipairs(s.party) do
      if party.gainXp(m, xp) > 0 then
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
  if not alive(s, u) then fall(s, b, u, events) end
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
  elseif status == "sleep" then
    u.sleep, u.guard = M.SLEEP_TICKS, false
  else
    u.nightmare = M.NIGHTMARE_TURNS
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

--- A swing: armour takes half, a little luck either way. times multiplies the blow before armour.
local function strike(s, b, from, to, percent, rng, events)
  local sure = to.sleep > 0 or from.focus
  if not sure and rng(100) > HIT_PERCENT then
    float(b, to, "MISS", "line")
    emit(events, "miss", to)
    return nil
  end
  local raw = power(s, from).atk * percent * (88 + rng(25)) / 10000
  if from.focus then
    raw = raw * M.FOCUS_TIMES
    from.focus = false
  end
  if rng(CRIT_ONE_IN) == 1 then raw = raw * 3 / 2 end
  if not from.m then emit(events, "foeStrike", from) end
  return hurt(s, b, to, floor(raw - power(s, to).def / 2), events)
end

local function maybeStatus(s, b, to, status, chance, rng, events)
  if status and alive(s, to) and rng(100) <= chance then return afflict(s, b, to, status, events) end
  return false
end

--- Spell damage against one foe: power plus magic, with little luck, and armour counts for a quarter.
local function blast(s, b, caster, to, spell, rng, events)
  local raw = (spell.power + power(s, caster).mag) * (94 + rng(13)) / 100
  return hurt(s, b, to, floor(raw - power(s, to).def / 4), events)
end

-- ---------------------------------------------------------------- what the party can do

local function castOn(s, b, u, spell, target, rng, events)
  local st = power(s, u)
  if spell.kind == "damage" then
    blast(s, b, u, target, spell, rng, events)
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
  say(b, nameOf(s, u) .. ": " .. spell.name)
  emit(events, "spell", u)
  if spell.target == "foes" then
    for _, f in ipairs(standing(s, b.foes)) do castOn(s, b, u, spell, f, rng, events) end
  elseif spell.target == "allies" then
    for _, a in ipairs(standing(s, b.allies)) do castOn(s, b, u, spell, a, rng, events) end
  else
    castOn(s, b, u, spell, target, rng, events)
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
  local dealt = strike(s, b, u, foe, 100, rng, events)
  say(b, dealt and (nameOf(s, u) .. " HITS FOR " .. dealt) or (nameOf(s, u) .. " MISSES"))
  endTurn(s, b, u, events)
end

local function doSteal(s, b, u, foe, rng, events)
  if foe.robbed or rng(100) > STEAL_PERCENT then
    say(b, nameOf(s, u) .. " GOT NOTHING")
    emit(events, "miss", foe)
  else
    foe.robbed = true
    s.bag.potion = (s.bag.potion or 0) + 1
    say(b, nameOf(s, u) .. " STOLE A POTION")
    emit(events, "item", foe)
  end
  endTurn(s, b, u, events)
end

local function doBlood(s, b, u, foe, rng, events)
  local m = member(s, u)
  local cost = max(1, floor(party.stats(m).hp / BLOOD_SHARE))
  m.hp = max(1, m.hp - cost)
  float(b, u, tostring(cost), "red")
  local dealt = strike(s, b, u, foe, 240, rng, events)
  say(b, nameOf(s, u) .. " BLEEDS FOR IT")
  if not dealt then say(b, nameOf(s, u) .. " MISSES") end
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

--- The rows of the open list: { kind, id, name, note, ok }, tapped by position.
function M.rows(s)
  local b = s.battle
  local out = {}
  if not b or not b.active then return out end
  local m = s.party[b.allies[b.active].m]
  if b.list == "special" then
    for _, id in ipairs(party.known(m)) do
      local spell = party.SPELLS[id]
      local ok = m.mp >= spell.mp and (spell.target ~= "fallen" or fallen(s, b))
      out[#out + 1] = { kind = "spell", id = id, name = spell.name, note = spell.mp .. "MP", ok = ok }
    end
  elseif b.list == "item" then
    for _, id in ipairs(party.ITEM_ORDER) do
      local n = s.bag[id] or 0
      if n > 0 then out[#out + 1] = { kind = "item", id = id, name = party.ITEMS[id].name, note = "x" .. n, ok = true } end
    end
    if b.flee then out[#out + 1] = { kind = "flee", id = "flee", name = "FLEE", note = "", ok = true } end
  end
  return out
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
  u.guard = false -- a guard lasts until your next turn
  b.phase, b.active, b.list, b.pick, b.pickId = "cmd", i, nil, nil, nil
  say(b, nameOf(s, u) .. " IS READY")
  emit(events, "menu", u)
end

local function chooseSpecial(s, b, u, rng, events)
  local special = party.CHARS[member(s, u).id].special
  if special == "FOCUS" then
    u.focus = true
    say(b, "NEXT HIT IS STRONGER")
    float(b, u, "FOCUS", "hi")
    emit(events, "focus", u)
    endTurn(s, b, u, events)
  elseif special == "STEAL" or special == "BLOOD" then
    ask(b, special == "STEAL" and "steal" or "blood", nil, special)
  else
    b.phase, b.list = "list", "special"
    say(b, special)
  end
end

local function chooseCommand(s, b, u, cmd, rng, events)
  if cmd == "attack" then
    ask(b, "attack", nil, "ATTACK")
  elseif cmd == "special" then
    chooseSpecial(s, b, u, rng, events)
  elseif cmd == "defend" then
    u.guard = true
    say(b, nameOf(s, u) .. " DEFENDS")
    float(b, u, "GUARD", "info")
    emit(events, "defend", u)
    endTurn(s, b, u, events)
  elseif cmd == "item" then
    b.list = "item"
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
  if row.kind == "flee" then
    doFlee(s, b, u, rng, events)
  elseif row.kind == "item" then
    ask(b, "item", row.id, row.name .. " ON WHO?")
  else
    local want = party.SPELLS[row.id].target
    if want == "foes" or want == "allies" then
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
  elseif b.pick == "steal" then
    doSteal(s, b, u, target, rng, events)
  elseif b.pick == "blood" then
    doBlood(s, b, u, target, rng, events)
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

local function foeLabel(s, u, ab) return nameOf(s, u) .. ": " .. ab.name end

local function randomAlly(s, b, rng)
  local list = standing(s, b.allies)
  return list[rng(#list)]
end

local function summon(s, b, u, id, rng, events)
  local slot
  for i, f in ipairs(b.foes) do
    if not alive(s, f) and f ~= u then slot = slot or i end
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
    summon(s, b, u, ab.summon, rng, events)
  elseif ab.target == "friend" then
    local worst, share
    for _, f in ipairs(standing(s, b.foes)) do
      local here = f.hp * 100 / f.mhp
      if not worst or here < share then worst, share = f, here end
    end
    mend(s, b, worst, ab.power + floor(power(s, u).atk / 2), events)
  else
    local list = ab.target == "all" and standing(s, b.allies) or { randomAlly(s, b, rng) }
    for _, to in ipairs(list) do
      local dealt
      if ab.magic then
        dealt = hurt(s, b, to, floor(power(s, u).atk * ab.power * (94 + rng(13)) / 10000), events)
      elseif ab.power then
        dealt = strike(s, b, u, to, ab.power, rng, events)
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
  local now = enemies.phaseOf(u.hp * 100 / u.mhp)
  if now <= u.phase then return false end
  u.phase = now
  u.spd = u.spd + 1
  say(b, now == 2 and "THE SHIFT IS CALLED" or "HE STOPS FEELING IT")
  emit(events, "phase", u)
  b.beat = TELEGRAPH_BEAT
  return true
end

local function foeTurn(s, b, u, rng, events)
  u.atb = 0
  b.beat = BEAT
  if u.phase and bossPhase(s, b, u, events) then return end
  u.turns = u.turns + 1
  local others, hurtFriend = 0, false
  for _, f in ipairs(standing(s, b.foes)) do
    if f ~= u then others = others + 1 end
    if f.hp * 3 < f.mhp * 2 then hurtFriend = true end
  end
  local id = enemies.choose(u, { others = others, hurt = hurtFriend }, rng)
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
        settled(s, b, events)
        return
      end
    end
  end
  for _, f in ipairs(b.foes) do
    if alive(s, f) and f.atb >= M.GAUGE and f.sleep == 0 and f.charge == 0 then
      if f.nightmare > 0 then nightmareTurn(s, b, f, rng, events) else foeTurn(s, b, f, rng, events) end
      return
    end
  end
  for i, u in ipairs(b.allies) do
    if alive(s, u) and u.atb >= M.GAUGE and u.sleep == 0 then
      if u.nightmare > 0 then nightmareTurn(s, b, u, rng, events) else openMenu(s, b, i, events) end
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

--- A reasonable player's whole decision for the member on turn: { cmd, row, side, i }. It takes no chance, so asking again at the
-- next menu gives the same answer, and the bot needs no memory.
local function plan(s, b)
  local u = b.allies[b.active]
  local m = member(s, u)
  local knows = {}
  for _, id in ipairs(party.known(m)) do knows[id] = true end
  local function can(id) return knows[id] and m.mp >= party.SPELLS[id].mp end
  local function has(id) return (s.bag[id] or 0) > 0 end
  local function cast(id, side, i) return { cmd = "special", row = id, side = side, i = i } end
  local function use(id, i) return { cmd = "item", row = id, side = "ally", i = i } end

  local lowest, lowShare, lowCount, down, troubled, sick, healer = nil, 101, 0, nil, nil, nil, false
  for i, a in ipairs(b.allies) do
    if alive(s, a) then
      local share = hpOf(s, a) * 100 / maxHpOf(s, a)
      if share < lowShare then lowest, lowShare = i, share end
      if share < 50 then lowCount = lowCount + 1 end
      if a.sleep > 0 or a.nightmare > 0 then troubled = troubled or i end
      if a.poison > 0 then sick = sick or i end
      local mate = party.known(member(s, a))
      for _, id in ipairs(mate) do
        if id == "mend" and member(s, a).mp >= party.SPELLS.mend.mp and a.sleep == 0 then healer = true end
      end
    else
      down = down or i
    end
  end

  local function healLowest()
    if lowCount >= 2 and can("vigil") then return cast("vigil") end
    if can("mend") then return cast("mend", "ally", lowest) end
    if can("salve") then return cast("salve", "ally", lowest) end
    if has("potion") then return use("potion", lowest) end
    return nil
  end

  -- a telegraphed blow: brace unless another turn will come first, or someone won't live through it even braced
  local blow = M.blowIn(b)
  if blow and blow <= ceil(M.GAUGE / M.gain(u.spd)) + BEAT then
    local worst = 0
    for _, f in ipairs(b.foes) do
      if f.charging then
        local ab = enemies.ABILITIES[f.charging]
        worst = max(worst, ceil(enemies.FOES[f.id].atk * ab.power * 106 / 10000 / M.GUARD_DIVIDE))
      end
    end
    if hpOf(s, b.allies[lowest]) <= worst and lowest ~= b.active then
      local help = healLowest()
      if help then return help end
    end
    return { cmd = "defend" }
  end

  if down then
    if can("rise") then return cast("rise", "ally", down) end
    if has("tonic") then return use("tonic", down) end
  end
  local urgent = lowShare < 28
  if lowShare < 45 and (urgent or knows.mend or knows.salve or not healer) then
    local help = healLowest()
    if help then return help end
  end
  if troubled and can("cleanse") then return cast("cleanse", "ally", troubled) end
  if knows.mend and m.mp < party.SPELLS.mend.mp and has("ether") then return use("ether", b.active) end
  if sick and can("cleanse") and m.mp * 5 > party.stats(m).mp * 2 then return cast("cleanse", "ally", sick) end

  -- on the attack: the weakest first, so the fight shrinks
  local foeHp, weakest, count = nil, nil, 0
  for i, f in ipairs(b.foes) do
    if alive(s, f) then
      count = count + 1
      if not foeHp or f.hp < foeHp then foeHp, weakest = f.hp, i end
    end
  end
  if count >= 2 and can("caustic") then return cast("caustic") end
  if count == 1 and foeHp > 60 and can("firepot") then return cast("firepot", "foe", weakest) end
  local special = party.CHARS[m.id].special
  if special == "FOCUS" and not u.focus and foeHp > 3 * power(s, u).atk then return { cmd = "special" } end
  if special == "MAGIC" then
    if can("bolt") then return cast("bolt", "foe", weakest) end
    if can("ember") then return cast("ember", "foe", weakest) end
  end
  return { cmd = "attack", side = "foe", i = weakest }
end

--- A reasonable player: an action, or nil when there is nothing to tap.
function M.bot(s)
  local b = s.battle
  if not b or b.result then return nil end
  if b.phase == "spoils" then return { kind = "tap" } end
  if b.phase == "run" then return nil end
  local want = plan(s, b)
  if b.phase == "cmd" then return { kind = "cmd", cmd = want.cmd } end
  if b.phase == "list" then
    for i, row in ipairs(M.rows(s)) do
      if row.id == want.row and row.ok then return { kind = "pick", i = i } end
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
