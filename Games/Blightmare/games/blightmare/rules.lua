-- games/blightmare/rules.lua
-- The engine of the slice: a mode machine over walking, the overworld, scripts, battles, the menu and shops. The clock runs
-- a short queue of taps, as Dungeon's does, and a script is a place in a list, so a save taken at any moment resumes there.
-- The state is plain data. Maps, scripts and foes stay in their data modules, and the state keeps only ids.

local M = {}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

-- The parts load when first needed, so this file can be read before they exist and a test can stand in for one.
local function part(name) return require("games.blightmare." .. name) end
local function story() return part("story") end
local function mapOf(id) return part("maps").DATA[id] end

local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local WAYS = { up = 1, right = 2, down = 3, left = 4 } -- on the overworld the sides of the wall are the compass
M.DIRS = DIRS

local QUEUE_LONGEST = 2
local STEPS_IN_A_TICK = 200     -- a script's quick steps run together, and a broken one can't hang the wall
local WORLD_TICKS_A_TILE = 2    -- about 4 tiles a second at 120 ms
local ENCOUNTER_ONE_IN = 20     -- with the grace below, about one fight in 25 steps
local ENCOUNTER_GRACE = 5       -- steps after a fight before the next can come
local CHASE_RANGE = 3
local FADE_TICKS = 6
local HINT_TICKS = 34
local TOLL_PER_LEVEL = 10       -- gold a lost fight costs, for each level of the hero's
local FALLEN_SCENES = 4         -- after the first, the Raven Queen's scenes fallen_1 to fallen_4 take turns

-- How text pages. The box is laid out in view_talk.lua around these: a portrait leaves SAY_WIDE, and narration keeps clear
-- of SAVE & QUIT all the same.
local SAY_WIDE, NARRATE_WIDE, TEXT_LINES = 80, 100, 6
local BIG_WIDE = 18
M.SAY_WIDE, M.NARRATE_WIDE, M.TEXT_LINES, M.BIG_WIDE = SAY_WIDE, NARRATE_WIDE, TEXT_LINES, BIG_WIDE

local MENU_ROWS = 8 -- rows on one page of the menu or a shop, with MORE as the last when there are others

local function changed(s) s.rev = s.rev + 1 end

local function emit(events, kind, fields)
  fields = fields or {}
  fields.type = kind
  events[#events + 1] = fields
end

local function passes(s, thing)
  if thing.when and not s.flags[thing.when] then return false end
  if thing.unless and s.flags[thing.unless] then return false end
  return true
end
M.passes = passes

-- ---------------------------------------------------------------- text

--- Lines of at most width characters, broken at spaces. A word too long for a line is cut. A newline starts a new line.
local function wrap(text, width)
  local lines = {}
  for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      while #word > width do
        if line ~= "" then
          lines[#lines + 1] = line
          line = ""
        end
        lines[#lines + 1] = word:sub(1, width)
        word = word:sub(width + 1)
      end
      if line ~= "" and #line + 1 + #word > width then
        lines[#lines + 1] = line
        line = word
      else
        line = line == "" and word or (line .. " " .. word)
      end
    end
    if line ~= "" or para == "" then lines[#lines + 1] = line end
  end
  return lines
end
M.wrap = wrap

local function fillName(s, text)
  local out = tostring(text):gsub("{hero}", function() return s.heroName end)
  return (out:gsub("{toll}", function() return tostring(s.toll or 0) end))
end

local function pageCount(text, width)
  return max(1, math.ceil(#wrap(text, width) / TEXT_LINES))
end

--- The name over a speaker's portrait.
local function speakerName(s, id)
  if id == "hero" then return s.heroName end
  local char = part("party").CHARS[id]
  return char and char.name or id:upper()
end

-- ---------------------------------------------------------------- party data

local function healAll(s)
  for _, member in ipairs(s.party) do part("party").restore(member) end
end

local function give(s, id, n)
  s.bag[id] = (s.bag[id] or 0) + (n or 1)
end

local function take(s, id, n)
  local left = (s.bag[id] or 0) - (n or 1)
  s.bag[id] = left > 0 and left or nil
end

local function findMember(s, id)
  for i, member in ipairs(s.party) do
    if member.id == id then return member, i end
  end
  return nil
end

local function heroOf(s)
  local hero = findMember(s, "hero")
  if hero then return hero end
  for _, member in ipairs(s.stash or {}) do
    if member.id == "hero" then return member end
  end
  return s.party[1]
end

--- The party's level, as far as who's joining can tell: the best of those here.
local function partyLevel(s)
  local best = 1
  for _, member in ipairs(s.party) do best = max(best, member.lvl) end
  return best
end

--- Someone joins, or comes back. Nobody comes back so far behind that they're no use: that's a chore, not a reunion.
local function joinParty(s, id, lvl)
  if findMember(s, id) then return end
  local away = s.away and s.away[id]
  local floorLevel = max(lvl or 1, partyLevel(s) - 1)
  local partyData = part("party")
  if away then
    s.away[id] = nil
    if away.lvl < floorLevel then partyData.gainXp(away, partyData.xpFor(floorLevel) - away.xp) end
    partyData.restore(away)
    s.party[#s.party + 1] = away
  else
    s.party[#s.party + 1] = partyData.new(id, floorLevel)
  end
end

local function leaveParty(s, id)
  local member, i = findMember(s, id)
  if not member or id == "hero" then return end
  table.remove(s.party, i)
  s.away = s.away or {}
  s.away[id] = member
end

--- The party is set aside for one person: a dream, or a road walked alone.
local function goSolo(s, id)
  local member, i = findMember(s, id)
  if not member or s.stash then return end
  table.remove(s.party, i)
  s.stash = s.party
  s.party = { member }
end

local function endSolo(s)
  if not s.stash then return end
  for _, member in ipairs(s.stash) do s.party[#s.party + 1] = member end
  s.stash = nil
end

--- A display name for anything that can be in the bag.
local function itemName(id)
  local party = part("party")
  local def = party.ITEMS[id] or party.GEAR[id]
  return def and def.name or id:upper()
end
M.itemName = itemName

-- ---------------------------------------------------------------- the map

local function isOpen(s, x, y)
  return s.opened[part("world").doorKey(s.map, x, y)] == true
end
M.isOpen = isOpen

local function open(s, x, y)
  s.opened[part("world").doorKey(s.map, x, y)] = true
end

local function findAt(list, s, x, y)
  for _, thing in ipairs(list or {}) do
    if thing.x == x and thing.y == y and passes(s, thing) then return thing end
  end
  return nil
end

local function npcAt(s, x, y) return findAt(mapOf(s.map).npcs, s, x, y) end
local function exitAt(s, x, y) return findAt(mapOf(s.map).exits, s, x, y) end
M.npcAt = npcAt

local function chestAt(s, x, y)
  for _, c in ipairs(mapOf(s.map).chests or {}) do
    if c.x == x and c.y == y and not s.opened[s.map .. ":" .. c.id] then return c end
  end
  return nil
end
M.chestAt = chestAt

local function foeAt(s, x, y)
  for _, f in ipairs(s.foes or {}) do
    if f.x == x and f.y == y then return f end
  end
  return nil
end
M.foeAt = foeAt

--- A foe's line in the map data: its encounter and its sprite.
local function foeDef(mapId, id)
  for _, f in ipairs(mapOf(mapId).foes or {}) do
    if f.id == id then return f end
  end
  return nil
end
M.foeDef = foeDef

local function ahead(s)
  local d = DIRS[s.dir]
  return s.x + d[1], s.y + d[2]
end
M.ahead = ahead

--- Can feet go on this square, things standing on it aside? Doors count once they're open.
local function floorAt(s, x, y)
  return not part("world").solid(s.map, x, y, s)
end

local function clear(s, x, y)
  return floorAt(s, x, y) and not npcAt(s, x, y) and not chestAt(s, x, y) and not foeAt(s, x, y)
end

--- What ACT would do right now: "foe", "npc", "chest", "door", "locked", "exit", or nil with nothing ahead.
function M.target(s)
  local x, y = ahead(s)
  if foeAt(s, x, y) then return "foe" end
  if npcAt(s, x, y) then return "npc" end
  if chestAt(s, x, y) then return "chest" end
  local c = part("world").tileAt(s.map, x, y)
  if c == "+" and not isOpen(s, x, y) then return "door" end
  if c == "L" and not isOpen(s, x, y) then return "locked" end
  if exitAt(s, x, y) then return "exit" end
  return nil
end

local function setSavepoint(s, events)
  s.savepoint = { map = s.map, x = s.x, y = s.y, dir = s.dir }
  if events then emit(events, "save") end
end

--- Everything that goes with standing on a new map. Beaten foes stay beaten, and the rest go back to their posts.
local function enterMap(s, id, x, y, dir, events)
  s.map, s.x, s.y, s.dir = id, x, y, dir or s.dir
  s.foes = {}
  local map = mapOf(id)
  for _, f in ipairs(map.foes or {}) do
    if not s.beaten[id .. ":" .. f.id] and passes(s, f) then
      s.foes[#s.foes + 1] = { id = f.id, x = f.x, y = f.y }
    end
  end
  if map.savepoint then setSavepoint(s, events) end
end

-- ---------------------------------------------------------------- the script runner

--- The list a place in the stack is reading. A branch hangs off the step just before its parent's next one.
local function branchOf(step, k)
  if not step then return nil end
  if k == "steps" or k == "other" then return step[k] end
  local option = step.choice and step.choice[k]
  return option and option[2]
end

local function listAt(run, depth)
  local list = run.id and story().SCRIPTS[run.id]
  for d = 2, depth do
    list = list and branchOf(list[run.at[d - 1].i - 1], run.at[d].k)
  end
  return list
end

--- The next step, moved past. A branch that runs out goes back to the list it came from.
local function nextStep(run)
  while #run.at > 0 do
    local frame = run.at[#run.at]
    local list = listAt(run, #run.at)
    local step = list and list[frame.i]
    if step then
      frame.i = frame.i + 1
      return step
    end
    run.at[#run.at] = nil
    -- a topic that's been heard goes back to the question list it came from
    if frame.again then
      local parent = run.at[#run.at]
      parent.i = parent.i - 1
    end
  end
  return nil
end

--- The next step without moving past it.
local function peekStep(run)
  for depth = #run.at, 1, -1 do
    local list = listAt(run, depth)
    local step = list and list[run.at[depth].i]
    if step then return step end
  end
  return nil
end

--- The choice waiting for a pick: the step the top of the stack has just passed.
local function choiceStep(run)
  local frame = run.at[#run.at]
  local list = frame and listAt(run, #run.at)
  return list and list[frame.i - 1]
end

local function pages(run)
  return pageCount(run.text or "", run.say and SAY_WIDE or NARRATE_WIDE)
end

--- With the last of a text showing, a choice after it comes up at once, under the question it answers.
local function settle(run)
  if run.big or run.page < pages(run) then return end
  local following = peekStep(run)
  if following and following.choice and not following.text then
    nextStep(run)
    run.wait = "pick"
  end
end

local function show(s, say, text, name)
  local run = s.run
  run.say, run.name, run.text, run.big, run.page, run.wait = say, name, fillName(s, text), nil, 1, "tap"
  settle(run)
  changed(s)
end

--- A line from the engine itself, not in any script, ending in the mode given.
local function note(s, text, back)
  s.run = { at = {}, back = back or s.mode, page = 1 }
  s.mode = "talk"
  s.queue = {}
  s.heading = nil
  show(s, nil, text)
end

local function startScript(s, id, once)
  if not story().SCRIPTS[id] then return false end
  s.run = { id = id, at = { { i = 1 } }, back = s.mode, once = once, page = 1 }
  s.mode = "talk"
  s.queue = {}
  s.heading = nil
  changed(s)
  return true
end
M.startScript = startScript

local checkStep -- declared here because a script's end can land on a trigger, and a trigger starts a script

local function finishRun(s)
  local run = s.run
  s.run = nil
  s.dark = nil
  s.mode = run.back
  if run.once then s.opened[run.once] = true end
  changed(s)
  if run.arrived and s.mode == "walk" then checkStep(s) end
end

--- A fight. The engine keeps its own note of what it was for, so it needn't read inside the battle.
local function startFight(s, enc, foeId, back, rng, events)
  -- what the party carried going in, so a loss can hand back whatever the fight used up
  local bag = {}
  for id, n in pairs(s.bag) do bag[id] = n end
  s.fight = { enc = enc, foe = foeId, bag = bag, gold = s.gold }
  s.back = back
  s.queue = {}
  s.heading = nil
  part("battle").begin(s, enc, rng)
  s.mode = "battle"
  emit(events, "battle", { enc = enc })
  changed(s)
end

local function toWorld(s, x, y)
  s.wx, s.wy, s.heading, s.route = x, y, nil, nil
  s.foes = {}
  s.hints.world = s.hints.world or HINT_TICKS
end

--- Is this step a fork, and if so which way? Returns nil for a step that isn't one.
local function forkOf(s, step)
  if not (step.steps or step.other) then return nil end
  local yes
  if step.when then
    yes = s.flags[step.when]
  elseif step.has then
    yes = (s.bag[step.has] or 0) > 0
  elseif step.paid then
    yes = s.gold >= step.paid
    if yes then s.gold = s.gold - step.paid end
  elseif step.all then
    yes = true
    for _, flag in ipairs(step.all) do yes = yes and s.flags[flag] end
  elseif step.count then
    local n = 0
    for _, flag in ipairs(step.count) do
      if s.flags[flag] then n = n + 1 end
    end
    yes = n >= step.at
  else
    return nil
  end
  return yes and "steps" or "other"
end

local function doStep(s, step, rng, events)
  local run = s.run
  local fork = forkOf(s, step)
  if fork then
    if step[fork] then run.at[#run.at + 1] = { k = fork, i = 1 } end
  elseif step.choice then
    -- a choice can carry its own short question, so a list that comes back still has someone asking it
    if step.text then show(s, step.say, step.text, step.name) end
    run.wait = "pick"
    changed(s)
  elseif step.say or step.text then
    show(s, step.say, step.text or "", step.name)
    emit(events, "talk")
  elseif step.big then
    run.say, run.name, run.text, run.page, run.wait = nil, nil, nil, 1, "tap"
    run.big = fillName(s, step.big)
    emit(events, "big")
    changed(s)
  elseif step.set then
    s.flags[step.set] = true
  elseif step.unset then
    s.flags[step.unset] = nil
  elseif step.give then
    give(s, step.give, step.n)
    emit(events, "item")
  elseif step.take then
    take(s, step.take, step.n)
  elseif step.leave then
    leaveParty(s, step.leave)
    changed(s)
  elseif step.solo then
    goSolo(s, step.solo)
    changed(s)
  elseif step.unsolo then
    endSolo(s)
    changed(s)
  elseif step.dark ~= nil then
    s.dark = step.dark or nil
    changed(s)
  elseif step.ending then
    s.won, s.ended = true, step.ending
    s.flags.cleared = true
    run.say, run.name, run.text, run.page, run.wait = nil, nil, nil, 1, "tap"
    run.big, run.leaveEnd = "THE END", true
    s.dark = true
    emit(events, "fin")
    changed(s)
  elseif step.gold then
    s.gold = max(0, s.gold + step.gold)
    emit(events, "gold")
  elseif step.join then
    joinParty(s, step.join, step.lvl)
    emit(events, "join", { id = step.join })
  elseif step.heal then
    healAll(s)
    emit(events, "heal")
  elseif step.battle then
    startFight(s, step.battle, nil, "talk", rng, events)
  elseif step.warp then
    local w = step.warp
    enterMap(s, w[1], w[2], w[3], w[4], events)
    run.back, run.arrived = "walk", true
    changed(s)
  elseif step.site then -- straight in at a site's door, whoever's region it is
    for _, site in ipairs(part("overworld").SITES or {}) do
      if site.id == step.site then
        enterMap(s, site.map, site.mx, site.my, site.dir, events)
        run.back, run.arrived = "walk", true
        changed(s)
      end
    end
  elseif step.world then
    toWorld(s, step.world[1], step.world[2])
    run.back, run.arrived = "world", nil
    changed(s)
  elseif step.shop then
    s.shop = { id = step.shop, top = 0 }
    s.back = "talk"
    s.mode = "shop"
    s.queue = {}
    changed(s)
  elseif step.inn then
    if s.gold >= step.inn then
      s.gold = s.gold - step.inn
      healAll(s)
      s.fx.fade = FADE_TICKS
      emit(events, "heal")
      show(s, nil, "You sleep. Everyone wakes rested.")
    else
      show(s, nil, "You can't pay for a bed.")
    end
  elseif step.save then
    if run.back == "walk" then setSavepoint(s, events) end
    s.msg = "A place to come back to."
  elseif step.fade then
    run.say, run.name, run.text, run.big = nil, nil, nil, nil
    run.wait = "fade"
    s.fx.fade = FADE_TICKS
    changed(s)
  elseif step.sfx then
    emit(events, "sfx", { name = step.sfx })
  elseif step.fin then
    s.fin = true
    run.say, run.name, run.text, run.page, run.wait = nil, nil, nil, 1, "tap"
    run.big = "TO BE CONTINUED"
    emit(events, "fin")
    changed(s)
  end
end

--- Run the script on until it has to wait for someone.
local function advance(s, rng, events)
  for _ = 1, STEPS_IN_A_TICK do
    local run = s.run
    if not run or s.mode ~= "talk" or run.wait then return end
    local step = nextStep(run)
    if step then doStep(s, step, rng, events) else finishRun(s) end
  end
end

local function talkInput(s, action, events)
  local run = s.run
  if not run or run.wait == "fade" then return end
  if run.wait == "pick" then
    local step = choiceStep(run)
    local option = action.kind == "pick" and step and step.choice and step.choice[action.i]
    if option then
      run.at[#run.at + 1] = { k = action.i, i = 1, again = option.again }
      run.wait, run.say, run.name, run.text = nil, nil, nil, nil
      emit(events, "pick")
    end
    return
  end
  if run.page < pages(run) then
    run.page = run.page + 1
    settle(run)
    emit(events, "page")
    return
  end
  if run.leaveEnd then
    M.afterEnd(s)
    return
  end
  run.wait, run.big = nil, nil
  emit(events, "page")
end

--- After the end: back to the last safe place, so the save lives on and the side stories can still be finished.
local function afterEnd(s)
  local spot = s.savepoint
  s.run, s.dark = nil, nil
  s.mode = "walk"
  if spot then enterMap(s, spot.map, spot.x, spot.y, spot.dir, nil) end
  changed(s)
end
M.afterEnd = afterEnd

--- What the talk box shows now, for the view and the tests.
function M.talk(s)
  local run = s.run
  if not run then return nil end
  local out = { say = run.say, page = run.page, wait = run.wait }
  if run.say then out.name = run.name or speakerName(s, run.say) end
  if run.big then out.big = wrap(run.big, BIG_WIDE) end
  if run.text then
    local width = run.say and SAY_WIDE or NARRATE_WIDE
    local all = wrap(run.text, width)
    out.pages = pages(run)
    out.lines = {}
    for i = (run.page - 1) * TEXT_LINES + 1, min(#all, run.page * TEXT_LINES) do out.lines[#out.lines + 1] = all[i] end
    out.more = run.page < out.pages
  end
  if run.wait == "pick" then
    out.choices = {}
    local step = choiceStep(run)
    for i, option in ipairs(step and step.choice or {}) do out.choices[i] = fillName(s, option[1]) end
  end
  return out
end

-- ---------------------------------------------------------------- fights ending

--- What the Raven Queen's gate takes for sending the party back: a little, the same for every loss at a level.
local function tollFor(s)
  return TOLL_PER_LEVEL * heroOf(s).lvl
end
M.tollFor = tollFor

--- A lost fight is undone: the pack and purse are as they were going in. Then a small toll, and the Raven Queen
--- sends everyone back to the last safe place, well. There's no telling how hard a fight is before it starts, so exploring
--- mustn't be punished for it.
local function wipe(s, events)
  local fight = s.fight or {}
  s.run, s.back, s.battle, s.fight, s.dark = nil, nil, nil, nil, nil
  endSolo(s) -- whatever they went into alone can be gone into again
  -- the pack and purse go back to exactly what they were, so nothing stolen in a lost fight is kept: losing on purpose must
  -- never pay. A fight only gives XP and gold when it's won, so this undoes everything it did.
  if fight.bag then s.bag = fight.bag end
  if fight.gold then s.gold = fight.gold end
  local toll = min(s.gold, tollFor(s))
  s.gold = s.gold - toll
  s.toll = toll
  s.flags.toll_free = toll == 0 or nil -- the scenes thank an empty purse instead
  s.deaths = (s.deaths or 0) + 1
  healAll(s)
  local at = s.savepoint
  if at then enterMap(s, at.map, at.x, at.y, at.dir, nil) end
  s.fx.fade = FADE_TICKS
  s.mode = "walk"
  emit(events, "wipe")
  local SCRIPTS = story().SCRIPTS
  local id = s.deaths == 1 and "fallen_first" or ("fallen_" .. ((s.deaths - 2) % FALLEN_SCENES + 1))
  if SCRIPTS[id] then
    startScript(s, id)
  else
    note(s, "Everything goes dark. You come to at the last safe place. Whatever you used in the fight is back in your pack, and the toll was " .. toll .. " gold.", "walk")
  end
end

local function dropFoe(s, id)
  for i, f in ipairs(s.foes or {}) do
    if f.id == id then
      table.remove(s.foes, i)
      return
    end
  end
end

local function endFight(s, events)
  local result = s.battle.result
  local fight = s.fight or {}
  local enc = fight.enc and part("enemies").ENCOUNTERS[fight.enc]
  local lost = result == "lost"
  if lost and enc and enc.mustLose then
    lost = false
    result = "won"
    healAll(s)
  end
  s.level = heroOf(s).lvl
  if lost then
    wipe(s, events)
    return
  end
  s.battle, s.fight = nil, nil
  s.mode = s.back or "walk"
  s.back = nil
  s.safeSteps = ENCOUNTER_GRACE
  if fight.foe then
    dropFoe(s, fight.foe)
    if result == "won" then s.beaten[s.map .. ":" .. fight.foe] = true end
  end
  changed(s)
end

-- ---------------------------------------------------------------- walking

--- Foes that have noticed close in, one square for each of the player's. One that reaches the player starts the fight.
local function foesMove(s, rng, events)
  for _, f in ipairs(s.foes or {}) do
    local dx, dy = s.x - f.x, s.y - f.y
    if abs(dx) + abs(dy) <= CHASE_RANGE then
      if abs(dx) + abs(dy) == 1 then
        local def = foeDef(s.map, f.id)
        startFight(s, def.enc, f.id, "walk", rng, events)
        return
      end
      local sx, sy = dx == 0 and 0 or (dx > 0 and 1 or -1), dy == 0 and 0 or (dy > 0 and 1 or -1)
      local first, second = { sx, 0 }, { 0, sy }
      if abs(dy) > abs(dx) then first, second = second, first end
      for _, way in ipairs({ first, second }) do
        local x, y = f.x + way[1], f.y + way[2]
        if (way[1] ~= 0 or way[2] ~= 0) and clear(s, x, y) then
          f.x, f.y = x, y
          break
        end
      end
    end
  end
end

--- A trigger on this square, if one is due. Returns true if it started a script.
checkStep = function(s)
  for _, step in ipairs(mapOf(s.map).steps or {}) do
    if step.x == s.x and step.y == s.y and passes(s, step) then
      local key = s.map .. ":step:" .. step.x .. "," .. step.y
      -- marked when the script ends, so a fight lost inside it can be had again
      if not (step.once and s.opened[key]) then
        return startScript(s, step.script, step.once and key or nil)
      end
    end
  end
  return false
end

local function takeExit(s, e, events)
  emit(events, "door")
  if e.script then
    startScript(s, e.script)
  elseif e.world then
    toWorld(s, e.world[1], e.world[2])
    s.mode = "world"
  else
    enterMap(s, e.map, e.mx, e.my, e.dir, events)
    checkStep(s)
  end
end

local function move(s, dx, dy, rng, events)
  local x, y = s.x + dx, s.y + dy
  local f = foeAt(s, x, y)
  if f then
    startFight(s, foeDef(s.map, f.id).enc, f.id, "walk", rng, events)
    return
  end
  local e = exitAt(s, x, y)
  if e and not npcAt(s, x, y) then
    takeExit(s, e, events)
    return
  end
  if not clear(s, x, y) then
    emit(events, "bump")
    return
  end
  s.x, s.y = x, y
  s.msg = ""
  emit(events, "step")
  if checkStep(s) then return end
  foesMove(s, rng, events)
end

local function openMenu(s, events)
  s.menu = { page = "main", top = 0 }
  s.back = s.mode
  s.mode = "menu"
  s.heading = nil
  emit(events, "menu")
end

local function openChest(s, chest, events)
  s.opened[s.map .. ":" .. chest.id] = true
  emit(events, "chest")
  local found = {}
  if chest.give then
    give(s, chest.give, chest.n)
    found[#found + 1] = (chest.n and chest.n > 1 and (chest.n .. " x ") or "") .. itemName(chest.give)
  end
  if chest.gold and chest.gold > 0 then
    s.gold = s.gold + chest.gold
    found[#found + 1] = chest.gold .. " GOLD"
    emit(events, "gold")
  end
  s.msg = #found > 0 and ("Found " .. table.concat(found, " and ")) or "It's empty."
end

local function act(s, rng, events)
  local x, y = ahead(s)
  local target = M.target(s)
  if target == "foe" then
    startFight(s, foeDef(s.map, foeAt(s, x, y).id).enc, foeAt(s, x, y).id, "walk", rng, events)
  elseif target == "npc" then
    startScript(s, npcAt(s, x, y).script)
  elseif target == "chest" then
    openChest(s, chestAt(s, x, y), events)
  elseif target == "door" then
    open(s, x, y)
    s.msg = ""
    emit(events, "door")
  elseif target == "locked" then
    if (s.bag.key or 0) > 0 then
      take(s, "key")
      open(s, x, y)
      s.msg = "The key turns in the lock."
      emit(events, "unlock")
    else
      s.msg = "Locked."
      emit(events, "bump")
    end
  elseif target == "exit" then
    takeExit(s, exitAt(s, x, y), events)
  else
    local d = DIRS[s.dir]
    move(s, d[1], d[2], rng, events)
  end
end

local function steer(s, dir, rng, events)
  local d = DIRS[s.dir]
  if dir == "up" then
    move(s, d[1], d[2], rng, events)
  elseif dir == "down" then
    move(s, -d[1], -d[2], rng, events)
  else
    s.dir = (s.dir - 1 + (dir == "right" and 1 or 3)) % 4 + 1
    emit(events, "turn")
  end
end

-- ---------------------------------------------------------------- the overworld

local function siteAt(s, x, y)
  local overworld = part("overworld")
  for _, site in ipairs(overworld.SITES or {}) do
    if site.x == x and site.y == y and passes(s, site) and mapOf(site.map) then return site end -- a site with no map yet is just country
  end
  return nil
end
M.siteAt = siteAt

local function gateAt(s, x, y) return part("overworld").gateAt(x, y, s) end
M.gateAt = gateAt

--- Walking a road stops where the road bends, so a tap is all a corner costs.
local function roadBends(s)
  local overworld = part("overworld")
  local function road(x, y)
    local c = overworld.tileAt(x, y, s)
    return c == "=" or c == "B" or c == "O"
  end
  if not road(s.wx, s.wy) then return false end
  local d = DIRS[s.heading]
  if road(s.wx + d[1], s.wy + d[2]) then return false end
  return road(s.wx + d[2], s.wy + d[1]) or road(s.wx - d[2], s.wy - d[1])
end

local function rollEncounter(s, rng, events)
  if s.safeSteps > 0 then
    s.safeSteps = s.safeSteps - 1
    return
  end
  local region = part("overworld").region(s.wx, s.wy, s)
  if not region then return end
  local table_ = part("enemies").FIELD[region]
  if not table_ or #table_ == 0 then return end
  if rng(ENCOUNTER_ONE_IN) ~= 1 then return end
  if region == "road" and rng(2) == 1 then return end
  startFight(s, table_[rng(#table_)], nil, "world", rng, events)
end

local function worldStep(s, rng, events)
  local overworld = part("overworld")
  local d = DIRS[s.heading]
  local x, y = s.wx + d[1], s.wy + d[2]
  local gate = gateAt(s, x, y)
  if gate then
    s.heading, s.route = nil, nil
    startScript(s, gate.script)
    return
  end
  if not overworld.walkable(x, y, s) then
    s.heading, s.route = nil, nil
    emit(events, "bump")
    changed(s)
    return
  end
  s.wx, s.wy, s.msg = x, y, ""
  emit(events, "step")
  changed(s)
  local site = siteAt(s, x, y)
  if site then
    s.heading, s.route = nil, nil
    s.mode = "walk"
    s.visited = s.visited or {}
    s.visited[site.id] = true
    enterMap(s, site.map, site.mx, site.my, site.dir, events)
    emit(events, "door")
    checkStep(s)
    return
  end
  rollEncounter(s, rng, events)
  if s.mode == "world" and not s.route and roadBends(s) then s.heading = nil end
end

--- The next way along a route, or nil at the end of it. A route survives a fight, so the party carries on afterwards.
local function routeWay(s)
  local route = s.route
  local way = route and tonumber(route.ways:sub(route.i, route.i))
  if way then
    route.i = route.i + 1
  else
    s.route = nil
  end
  return way
end

local function worldTick(s, rng, events)
  if s.route and not s.heading then
    s.heading = routeWay(s)
    s.walkClock = WORLD_TICKS_A_TILE - 1
    changed(s)
  end
  if not s.heading then
    s.walkClock = 0
    return
  end
  s.walkClock = s.walkClock + 1
  if s.walkClock >= WORLD_TICKS_A_TILE then
    s.walkClock = 0
    worldStep(s, rng, events)
    if s.mode == "world" and s.route then
      s.heading = routeWay(s)
      if not s.heading then changed(s) end
    end
  end
end

--- Flood the overworld from the party: for each tile reached, the way the party came into it. Other sites count as walls unless
-- throughSites, or a route past a town would stop at the town. The target can always be walked onto, so a tap on a gate rings it.
local function floodWorld(s, tx, ty, throughSites)
  local overworld = part("overworld")
  local sites = {}
  if not throughSites then
    for _, site in ipairs(overworld.SITES or {}) do
      if passes(s, site) then sites[site.y * 1000 + site.x] = true end
    end
  end
  local start = s.wy * 1000 + s.wx
  local from, order, head = { [start] = 0 }, { start }, 1
  while order[head] do
    local key = order[head]
    head = head + 1
    local x, y = key % 1000, floor(key / 1000)
    if x == tx and y == ty then break end
    for way, d in ipairs(DIRS) do
      local nx, ny = x + d[1], y + d[2]
      local nextKey = ny * 1000 + nx
      if not from[nextKey] then
        local isTarget = nx == tx and ny == ty
        local open = (isTarget and gateAt(s, nx, ny) ~= nil)
          or (overworld.walkable(nx, ny, s) and not gateAt(s, nx, ny) and (isTarget or not sites[nextKey]))
        if open then
          from[nextKey] = way
          order[#order + 1] = nextKey
        end
      end
    end
  end
  return from, order
end

--- The ways from the party to a tile the flood reached, as a string of facings.
local function waysTo(s, from, tx, ty)
  local out, x, y = {}, tx, ty
  while x ~= s.wx or y ~= s.wy do
    local way = from[y * 1000 + x]
    table.insert(out, 1, tostring(way))
    x, y = x - DIRS[way][1], y - DIRS[way][2]
  end
  return table.concat(out)
end

--- A tap on the map: walk there, round anything in the way, or as near as can be got if there is no way. A tap on the party stops it.
local function planRoute(s, tx, ty, events)
  s.heading = nil
  if tx == s.wx and ty == s.wy then
    s.route = nil
    changed(s)
    return
  end
  local from, order = floodWorld(s, tx, ty, false)
  if not from[ty * 1000 + tx] then
    local through, wider = floodWorld(s, tx, ty, true) -- the only way may be through a town
    if through[ty * 1000 + tx] then from, order = through, wider end
  end
  local gx, gy = tx, ty
  if not from[ty * 1000 + tx] then
    local best
    for _, key in ipairs(order) do
      local x, y = key % 1000, floor(key / 1000)
      local off = abs(x - tx) + abs(y - ty)
      if not best or off < best then best, gx, gy = off, x, y end
    end
  end
  local ways = waysTo(s, from, gx, gy)
  if ways == "" then
    s.route, s.msg = nil, "There's no way there from here."
    emit(events, "bump")
  else
    s.route, s.msg = { ways = ways, i = 1, x = gx, y = gy }, ""
    emit(events, "turn")
  end
  changed(s)
end

local function worldInput(s, action, events)
  if action.kind == "goto" then
    planRoute(s, action.x, action.y, events)
  elseif action.kind == "turn" then
    s.route = nil
    s.heading, s.lastWay = WAYS[action.dir], WAYS[action.dir]
    s.walkClock = WORLD_TICKS_A_TILE - 1 -- the first tile answers the tap
    emit(events, "turn")
  elseif action.kind == "act" then
    if s.heading then
      s.heading, s.route = nil, nil
    elseif s.lastWay then -- stopped: on the way they were going
      s.heading = s.lastWay
      s.walkClock = WORLD_TICKS_A_TILE - 1
      emit(events, "turn")
    end
  elseif action.kind == "menu" then
    openMenu(s, events)
  end
end

-- ---------------------------------------------------------------- the menu and shops

--- One page of a list, with MORE as the last row when there are further pages.
local function pageOf(all, top)
  if #all <= MENU_ROWS then return all end
  local rows = {}
  local room = MENU_ROWS - 1
  for i = top + 1, min(#all, top + room) do rows[#rows + 1] = all[i] end
  rows[#rows + 1] = { label = "MORE", more = true }
  return rows
end

local function memberRows(s)
  local rows = {}
  for i, member in ipairs(s.party) do
    local char = part("party").CHARS[member.id]
    rows[i] = { label = member.id == "hero" and s.heroName or (char and char.name or member.id), who = i }
  end
  return rows
end

--- The items in the bag, in the party's own order. Anything only a battle can use is still listed, marked so.
local function bagRows(s)
  local party = part("party")
  local rows = {}
  for _, id in ipairs(party.ITEM_ORDER) do
    if s.bag[id] then
      local def = party.ITEMS[id]
      rows[#rows + 1] = { label = itemName(id) .. " x" .. s.bag[id], item = id, field = def.field == true, key = def.key == true }
    end
  end
  return rows
end

local function slotOf(gearId)
  local def = part("party").GEAR[gearId]
  return def and def.slot
end

local SLOT_ORDER = { weapon = 1, armour = 2, accessory = 3 }

--- The gear in the bag that this person can wear, weapons first. The sort matters: pairs has no order, and a tap must mean the
-- same row twice.
local function gearRows(s)
  local partyData = part("party")
  local member = s.menu and s.menu.who and s.party[s.menu.who]
  local ids = {}
  for id in pairs(s.bag) do
    if slotOf(id) and (not member or partyData.canWear(member, id)) then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b)
    if slotOf(a) ~= slotOf(b) then return SLOT_ORDER[slotOf(a)] < SLOT_ORDER[slotOf(b)] end
    return a < b
  end)
  local rows = {}
  for i, id in ipairs(ids) do
    rows[i] = { label = itemName(id) .. " x" .. s.bag[id], gear = id, slot = slotOf(id) }
  end
  return rows
end

--- Who fights and who waits. Tap one, then tap who they change places with.
local function partyRows(s)
  local rows = memberRows(s)
  local fighting = part("party").IN_BATTLE
  for i, row in ipairs(rows) do
    row.label = (i <= fighting and "" or "(WAITS) ") .. row.label
    row.swap = true
    row.picked = s.menu.swap == i
  end
  return rows
end

--- Everywhere the party has been that's still there.
local function travelRows(s)
  local rows = {}
  for _, site in ipairs(part("overworld").SITES or {}) do
    if s.visited and s.visited[site.id] and passes(s, site) then
      rows[#rows + 1] = { label = site.name, site = site.id, x = site.x, y = site.y }
    end
  end
  return rows
end

--- The whole list a page shows, before it's cut into pages.
local function listFor(s, page)
  if page == "items" then return bagRows(s) end
  if page == "equip" then return gearRows(s) end
  if page == "travel" then return travelRows(s) end
  return memberRows(s)
end

--- The rows of the menu page that's open. Each is a table with label and whatever a pick needs.
function M.menuRows(s)
  local menu = s.menu
  if not menu then return {} end
  if menu.page == "main" then
    local rows = { { label = "ITEMS", go = "items" }, { label = "GEAR", go = "gear" }, { label = "STATUS", go = "status" } }
    if #s.party > 1 then rows[#rows + 1] = { label = "PARTY", go = "party" } end
    if s.flags.can_travel and s.back == "world" then rows[#rows + 1] = { label = "TRAVEL", go = "travel" } end
    rows[#rows + 1] = { label = "CLOSE", close = true }
    return rows
  elseif menu.page == "items" then
    return pageOf(bagRows(s), menu.top)
  elseif menu.page == "useon" or menu.page == "gear" or menu.page == "status" then
    return pageOf(memberRows(s), menu.top)
  elseif menu.page == "party" then
    return partyRows(s)
  elseif menu.page == "equip" then
    return pageOf(gearRows(s), menu.top)
  elseif menu.page == "travel" then
    return pageOf(travelRows(s), menu.top)
  end
  return {}
end

--- Use one item on a member, if it would do anything. Returns a line for the wall.
local function useItem(s, id, member)
  local hp, mp = part("party").useField(s.party, member, id)
  if hp == 0 and mp == 0 then return "It would do nothing." end
  take(s, id)
  return "Used " .. itemName(id) .. "."
end

--- Wear a piece from the bag. What was worn goes back in the bag.
local function equip(s, member, gearId)
  local slot = slotOf(gearId)
  local worn = member[slot]
  take(s, gearId)
  if worn then give(s, worn) end
  member[slot] = gearId
end

local function closeMenu(s)
  s.menu = nil
  s.mode = s.back or "walk"
  s.back = nil
end

local function menuPick(s, i, events)
  local menu = s.menu
  local all = M.menuRows(s)
  local row = all[i]
  if not row then return end
  emit(events, "pick")
  if row.close then
    closeMenu(s)
  elseif row.more then
    menu.top = menu.top + MENU_ROWS - 1
    if menu.top >= #listFor(s, menu.page) then menu.top = 0 end
  elseif row.go then
    menu.page, menu.top = row.go, 0
  elseif row.swap then
    if not menu.swap then
      menu.swap = i
      menu.line = "Tap who they change places with."
    else
      s.party[menu.swap], s.party[i] = s.party[i], s.party[menu.swap]
      menu.swap, menu.line = nil, nil
    end
  elseif row.site then
    closeMenu(s)
    toWorld(s, row.x, row.y)
    s.safeSteps = ENCOUNTER_GRACE
    s.fx.fade = FADE_TICKS
  elseif row.item then
    if row.key then
      menu.line = "You'll know when it's needed."
    elseif row.field then
      menu.item = row.item
      menu.page = "useon"
    else
      menu.line = "That's for a fight."
    end
  elseif menu.page == "useon" then
    menu.line = useItem(s, menu.item, s.party[row.who])
    if not s.bag[menu.item] then
      menu.item = nil
      menu.page, menu.top = "items", 0
    end
  elseif menu.page == "gear" then
    menu.who = row.who
    menu.page, menu.top = "equip", 0
  elseif menu.page == "status" then
    menu.who = row.who
  elseif row.gear then
    equip(s, s.party[menu.who], row.gear)
    menu.line = "Equipped " .. itemName(row.gear) .. "."
    menu.top = 0
  end
end

local function menuBack(s)
  local menu = s.menu
  menu.line, menu.swap = nil, nil
  if menu.page == "main" then
    closeMenu(s)
  elseif menu.page == "useon" then
    menu.page, menu.top = "items", 0
  elseif menu.page == "equip" then
    menu.page, menu.top = "gear", 0
  else
    menu.page, menu.top, menu.who = "main", 0, nil
  end
end

--- A shop's rows. An item the purse can't reach is still shown, so the player can see what to save for.
function M.shopRows(s)
  if not s.shop then return {} end
  local all = {}
  for i, ware in ipairs(story().SHOPS[s.shop.id] or {}) do
    all[i] = { label = itemName(ware.item), price = ware.price, ware = ware.item, afford = s.gold >= ware.price }
  end
  return pageOf(all, s.shop.top)
end

local function shopPick(s, i, events)
  local shop = s.shop
  local row = M.shopRows(s)[i]
  if not row then return end
  if row.more then
    shop.top = shop.top + MENU_ROWS - 1
    if shop.top >= #(story().SHOPS[shop.id] or {}) then shop.top = 0 end
  elseif row.afford then
    s.gold = s.gold - row.price
    give(s, row.ware)
    shop.line = "Bought " .. row.label .. "."
    emit(events, "buy")
  else
    shop.line = "You can't afford that."
    emit(events, "bump")
  end
end

local function closeShop(s)
  s.shop = nil
  s.mode = s.back or "talk"
  s.back = nil
end

-- ---------------------------------------------------------------- asking a name

local UNNAMED = "Player"    -- what the shell calls someone it can't name
local NAME_LONGEST = 12
M.NAME_DELETE, M.NAME_DONE = 27, 28 -- the keys after the 26 letters

--- Nobody could tell who this is, so the game asks, wherever they are.
local function askName(s)
  s.naming = { text = "", back = s.mode }
  s.mode = "name"
  s.queue = {}
  s.heading = nil
  changed(s)
end

local function nameInput(s, action)
  local naming = s.naming
  if action.kind ~= "pick" or not naming then return end
  local key = action.i
  if key == M.NAME_DONE then
    s.heroName = naming.text ~= "" and naming.text or "Hero"
    s.mode, s.naming = naming.back, nil
  elseif key == M.NAME_DELETE then
    naming.text = naming.text:sub(1, -2)
  elseif key >= 1 and key <= 26 and #naming.text < NAME_LONGEST then
    local letter = string.char(64 + key)
    naming.text = naming.text .. (naming.text == "" and letter or letter:lower())
  end
  changed(s)
end

-- ---------------------------------------------------------------- one tap

local function apply(s, action, rng, events)
  local mode = s.mode
  if mode == "name" then
    nameInput(s, action)
  elseif mode == "walk" then
    if action.kind == "act" then act(s, rng, events) end
    if action.kind == "turn" then steer(s, action.dir, rng, events) end
    if action.kind == "menu" then openMenu(s, events) end
  elseif mode == "world" then
    worldInput(s, action, events)
  elseif mode == "talk" then
    talkInput(s, action, events)
  elseif mode == "menu" then
    if action.kind == "pick" then menuPick(s, action.i, events) end
    if action.kind == "back" then menuBack(s) end
  elseif mode == "shop" then
    if action.kind == "pick" then shopPick(s, action.i, events) end
    if action.kind == "back" then closeShop(s) end
  end
end

-- ---------------------------------------------------------------- the contract

local VERSION = 3

--- A save from before the script was last rewritten. A run in progress holds its place by step number, so it can't carry
-- over: the conversation is dropped, and whatever started it can be had again. Anything in the world that moved is put right.
local function upgrade(s)
  if (s.v or 1) >= VERSION then return end
  s.v = VERSION
  local run = s.run
  if run then
    s.run = nil
    if s.mode == "talk" then
      s.mode = run.back or "walk"
    elseif s.back == "talk" then
      s.back = run.back or "walk"
    end
    s.queue = {}
  end
  if s.flags.foreman_down or s.opened["mine_3:step:10,7"] then s.flags.saw_shift = true end
  -- the slice ended on TO BE CONTINUED, and now it does
  s.fin = nil
  s.away, s.visited = s.away or {}, s.visited or {}
  local spot = s.savepoint
  if s.mode == "walk" and spot and part("world").solid(s.map, s.x, s.y, s) then
    s.map, s.x, s.y, s.dir = spot.map, spot.x, spot.y, spot.dir
  end
  changed(s)
end

function M.new(opts)
  local name = opts and opts.player
  local s = {
    v = VERSION, score = 0, level = 1, over = false, won = false, rev = 0, frame = 0,
    heroName = (type(name) == "string" and name ~= "") and name or "Hero",
    mode = "talk", back = nil,
    map = "scythebreak", x = 3, y = 3, dir = 1,
    wx = 10, wy = 10, heading = nil, walkClock = 0, safeSteps = ENCOUNTER_GRACE,
    party = { part("party").new("hero", 1) },
    bag = { potion = 3 }, gold = 0,
    flags = {}, opened = {}, beaten = {}, foes = {}, away = {}, visited = {},
    run = nil, battle = nil, menu = nil, shop = nil, fight = nil,
    fx = { flash = 0, hurt = 0, fade = 0 },
    hints = {},
    queue = {},
    msg = "",
  }
  enterMap(s, s.map, s.x, s.y, s.dir, nil)
  s.back = nil
  s.run = { id = story().START, at = { { i = 1 } }, back = "walk", page = 1 }
  s.hints.walk = HINT_TICKS
  return s
end

--- A tap, kept for the next step. In a battle it goes straight to the battle, which queues it itself.
function M.input(s, action)
  if s.over or not action then return end
  upgrade(s)
  if s.mode == "battle" then
    part("battle").input(s, action)
    return
  end
  if #s.queue >= QUEUE_LONGEST then return end
  s.queue[#s.queue + 1] = { kind = action.kind, dir = action.dir, i = action.i, x = action.x, y = action.y }
end

local function fxTick(s)
  local fx = s.fx
  for _, name in ipairs({ "flash", "hurt", "fade" }) do
    if fx[name] > 0 then
      fx[name] = fx[name] - 1
      if fx[name] == 0 then changed(s) end
    end
  end
  local run = s.run
  if run and run.wait == "fade" and fx.fade == 0 then run.wait = nil end
end

local function hintTick(s)
  local key = s.mode
  local left = s.hints[key]
  if type(left) == "number" and left > 0 then
    s.hints[key] = left - 1
    if left == 1 then changed(s) end
  end
end

function M.tick(s, rng)
  local events = {}
  if s.over then return events end
  upgrade(s)
  if s.heroName == UNNAMED and s.mode ~= "name" and s.mode ~= "battle" then askName(s) end
  s.frame = s.frame + 1
  fxTick(s)
  hintTick(s)
  if s.mode == "battle" then
    for _, ev in ipairs(part("battle").tick(s, rng) or {}) do events[#events + 1] = ev end
    if s.battle and s.battle.result then endFight(s, events) end
  else
    local action = table.remove(s.queue, 1)
    if action then
      apply(s, action, rng, events)
      changed(s)
    end
    if s.mode == "world" then worldTick(s, rng, events) end
  end
  advance(s, rng, events)
  return events
end

-- ---------------------------------------------------------------- the bot

-- It plays the slice to the end for the tests, knowing the maps but not the story: it tries everything it can reach, and
-- anything that changes the flags opens everything up to be tried again. Its notes are kept in the state, under s.botMem,
-- so a bot picked up from a save carries on. A real player's state never has them.

local BOT_HEAL_BELOW = 0.5     -- a share of HP
local BOT_POTIONS = 8          -- how many it wants to carry
local BOT_FOR_BOSS = 5         -- the level it wants before it goes down for good
local BOT_STALL = 1500         -- ticks with nothing new before it starts trying other answers

local function botMem(s)
  local mem = s.botMem
  if not mem then
    mem = { tried = {}, seen = {}, sig = -1 }
    s.botMem = mem
  end
  local sig = #s.party
  for _ in pairs(s.flags) do sig = sig + 1 end
  if sig ~= mem.sig then
    mem.sig, mem.tried, mem.changedAt = sig, {}, s.frame
  end
  -- a door shut last time may be open now: nothing it tried stays tried for long
  if s.frame - (mem.freshAt or 0) > BOT_STALL * 2 then mem.tried, mem.freshAt = {}, s.frame end
  return mem
end

local function turnTo(s, way)
  return { kind = "turn", dir = (way - s.dir) % 4 == 3 and "left" or "right" }
end

local function shutDoor(s, x, y)
  local c = part("world").tileAt(s.map, x, y)
  if isOpen(s, x, y) then return false end
  return c == "+" or (c == "L" and (s.bag.key or 0) > 0)
end

--- Steps to every square the bot can stand on, with the first way to go for each. Foes don't block: it walks into them.
local function botFlood(s)
  local dist, first = { [s.y * 1000 + s.x] = 0 }, {}
  local order = { { s.x, s.y } }
  local head = 1
  while order[head] do
    local at = order[head]
    head = head + 1
    local from = at[2] * 1000 + at[1]
    for way, d in ipairs(DIRS) do
      local x, y = at[1] + d[1], at[2] + d[2]
      local key = y * 1000 + x
      if not dist[key] and (floorAt(s, x, y) or shutDoor(s, x, y)) and not npcAt(s, x, y)
        and not chestAt(s, x, y) and not exitAt(s, x, y) then
        dist[key] = dist[from] + 1
        first[key] = first[from] or way
        order[#order + 1] = { x, y }
      end
    end
  end
  return dist, first
end

--- What's worth doing on this map, most wanted first, as lists of { x, y, act, key }.
local function botTargets(s, mem)
  local map = mapOf(s.map)
  local function add(list, x, y, useAct, key)
    if not mem.tried[key] then list[#list + 1] = { x = x, y = y, act = useAct, key = key } end
  end
  local wanted, steps, people, chests, foes, newExits, oldExits = {}, {}, {}, {}, {}, {}, {}
  -- the story guide first: what a player is told to do is what the bot does, so a guide that lies shows up as a bot that stalls
  local goal = M.goal(s)
  if goal and goal.x then
    local talks = npcAt(s, goal.x, goal.y) or chestAt(s, goal.x, goal.y)
    add(wanted, goal.x, goal.y, talks and true or false, "goal:" .. s.map .. ":" .. goal.x .. "," .. goal.y)
  end
  for _, step in ipairs(map.steps or {}) do
    local key = s.map .. ":step:" .. step.x .. "," .. step.y
    if passes(s, step) and not (step.once and s.opened[key]) then add(steps, step.x, step.y, false, key) end
  end
  for _, npc in ipairs(map.npcs or {}) do
    if passes(s, npc) then add(people, npc.x, npc.y, true, "npc:" .. s.map .. ":" .. npc.id) end
  end
  for _, chest in ipairs(map.chests or {}) do
    if chestAt(s, chest.x, chest.y) then add(chests, chest.x, chest.y, true, "chest:" .. s.map .. ":" .. chest.id) end
  end
  local enemies = part("enemies")
  for _, f in ipairs(s.foes or {}) do
    local enc = enemies.ENCOUNTERS[foeDef(s.map, f.id).enc]
    local def = enc and enemies.FOES[enc.foes[1]]
    if s.level < max(def and def.tier and def.tier + 1 or 0, BOT_FOR_BOSS) then add(foes, f.x, f.y, true, "foe:" .. s.map .. ":" .. f.id) end
  end
  for _, e in ipairs(map.exits or {}) do
    if passes(s, e) then
      local to = e.map or "world"
      add(mem.seen[to] and oldExits or newExits, e.x, e.y, false, "exit:" .. s.map .. ":" .. e.x .. "," .. e.y)
    end
  end
  return { foes, wanted, steps, people, chests, newExits, oldExits } -- anything it should fight comes first: it needs the levels
end

local function botOnFoot(s, mem)
  mem.seen[s.map] = true
  for _, site in ipairs(part("overworld").SITES or {}) do
    if site.map == s.map then mem.tried["site:" .. site.id] = true end
  end
  local dist, first = botFlood(s)
  for _, list in ipairs(botTargets(s, mem)) do
    local best
    for _, target in ipairs(list) do
      for way, d in ipairs(DIRS) do
        local steps = dist[(target.y - d[2]) * 1000 + target.x - d[1]]
        if steps and (not best or steps < best.steps) then
          best = { steps = steps, way = way, target = target }
        end
      end
    end
    if best then
      local target = best.target
      if best.steps == 0 then
        if s.dir ~= best.way then return turnTo(s, best.way) end
        mem.tried[target.key] = true
        if target.act then return { kind = "act" } end
        return { kind = "turn", dir = "up" }
      end
      local way = first[(target.y - DIRS[best.way][2]) * 1000 + target.x - DIRS[best.way][1]]
      if way ~= s.dir then return turnTo(s, way) end
      local x, y = ahead(s)
      if shutDoor(s, x, y) then return { kind = "act" } end
      return { kind = "turn", dir = "up" }
    end
  end
  mem.tried = {} -- everything has been tried with these flags: go round again, and the fights on the way make it stronger
  return { kind = "turn", dir = "left" }
end

--- The way from here to a tile, as a string of facings, or nil. Long enough to be worth keeping between ticks.
local function worldPath(s, tx, ty)
  local overworld = part("overworld")
  local function passable(x, y) return overworld.walkable(x, y, s) and not gateAt(s, x, y) end
  local from = { [s.wy * 1000 + s.wx] = 0 }
  local order = { { s.wx, s.wy } }
  local head = 1
  while order[head] do
    local at = order[head]
    head = head + 1
    if at[1] == tx and at[2] == ty then
      local out, x, y = {}, tx, ty
      while x ~= s.wx or y ~= s.wy do
        local way = from[y * 1000 + x]
        table.insert(out, 1, tostring(way))
        x, y = x - DIRS[way][1], y - DIRS[way][2]
      end
      return table.concat(out)
    end
    for way, d in ipairs(DIRS) do
      local x, y = at[1] + d[1], at[2] + d[2]
      if not from[y * 1000 + x] and passable(x, y) then
        from[y * 1000 + x] = way
        order[#order + 1] = { x, y }
      end
    end
  end
  return nil
end

local WAY_NAMES = { "up", "right", "down", "left" }

local function botOnWorld(s, mem)
  local path = mem.path
  if path and path.x == s.wx and path.y == s.wy then
    path.i = path.i + 1
    local way = tonumber(path.ways:sub(path.i, path.i))
    if way then
      path.x, path.y = path.x + DIRS[way][1], path.y + DIRS[way][2]
      path.way = way
    else
      mem.path, path = nil, nil
    end
  elseif path and (abs(path.x - s.wx) + abs(path.y - s.wy)) ~= 1 then
    mem.path, path = nil, nil
  end
  if not path then
    local goal = M.goal(s)
    local sites = {}
    for _, site in ipairs(part("overworld").SITES or {}) do
      if siteAt(s, site.x, site.y) and not (site.x == s.wx and site.y == s.wy) then
        local rank = (mem.seen[site.map] and 2 or 0) + (mem.tried["site:" .. site.id] and 1 or 0)
        if goal and goal.x == site.x and goal.y == site.y then rank = -1 end
        sites[#sites + 1] = { site = site, rank = rank }
      end
    end
    table.sort(sites, function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      return a.site.id < b.site.id
    end)
    local ways
    for _, pick in ipairs(sites) do -- the Empire is walled off, so some sites can't be walked to from here
      ways = worldPath(s, pick.site.x, pick.site.y)
      if ways and ways ~= "" then break end
    end
    if not ways or ways == "" then return nil end
    path = { ways = ways, i = 1, x = s.wx, y = s.wy }
    local way = tonumber(ways:sub(1, 1))
    path.x, path.y, path.way = path.x + DIRS[way][1], path.y + DIRS[way][2], way
    mem.path = path
  end
  if s.heading ~= path.way then return { kind = "turn", dir = WAY_NAMES[path.way] } end
  return nil
end

local function hurtMember(s)
  local worst, share
  for i, member in ipairs(s.party) do
    local here = member.hp / part("party").stats(member).maxHp
    if here < BOT_HEAL_BELOW and member.hp > 0 and (not share or here < share) then worst, share = i, here end
  end
  return worst
end

--- A piece in the bag better than what someone wears: member index and gear id.
local function betterGear(s)
  local party = part("party")
  local ids = {}
  for id in pairs(s.bag) do
    if party.GEAR[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for i, member in ipairs(s.party) do
    for _, id in ipairs(ids) do
      local worn = member[party.GEAR[id].slot]
      if party.canWear(member, id) and (not worn or party.gearScore(member, id) > party.gearScore(member, worn)) then return i, id end
    end
  end
  return nil
end

local function rowWhere(rows, field, value)
  for i, row in ipairs(rows) do
    if row[field] == value then return i end
  end
  return nil
end

local BOT_HEALS = { "xpotion", "hipotion", "potion" } -- best first

local function botHeal(s)
  for _, id in ipairs(BOT_HEALS) do
    if (s.bag[id] or 0) > 0 then return id end
  end
  return nil
end

local function botMenu(s)
  local menu = s.menu
  local heal = botHeal(s)
  local hurt = heal and hurtMember(s)
  local who, gear = betterGear(s)
  local rows = M.menuRows(s)
  if menu.page == "main" then
    if hurt then return { kind = "pick", i = 1 } end
    if who then return { kind = "pick", i = 2 } end
    return { kind = "pick", i = rowWhere(rows, "close", true) }
  elseif menu.page == "items" then
    local i = hurt and (rowWhere(rows, "item", heal) or rowWhere(rows, "more", true))
    return i and { kind = "pick", i = i } or { kind = "back" }
  elseif menu.page == "useon" then
    return hurt and { kind = "pick", i = hurt } or { kind = "back" }
  elseif menu.page == "gear" then
    return who and { kind = "pick", i = who } or { kind = "back" }
  elseif menu.page == "equip" then
    local i = gear and menu.who == who and (rowWhere(rows, "gear", gear) or rowWhere(rows, "more", true))
    return i and { kind = "pick", i = i } or { kind = "back" }
  end
  return { kind = "back" }
end

local function botShop(s)
  local party = part("party")
  for i, row in ipairs(M.shopRows(s)) do
    if row.afford then
      local def = party.GEAR[row.ware]
      if def and not s.bag[row.ware] then
        for _, member in ipairs(s.party) do
          local worn = member[def.slot]
          if party.canWear(member, row.ware) and (not worn or party.gearScore(member, row.ware) > party.gearScore(member, worn)) then
            return { kind = "pick", i = i }
          end
        end
      elseif (row.ware == "potion" or row.ware == "hipotion" or row.ware == "xpotion") and (s.bag[row.ware] or 0) < BOT_POTIONS then
        return { kind = "pick", i = i }
      elseif row.ware == "feather" and (s.bag.feather or 0) < 3 then
        return { kind = "pick", i = i }
      end
    end
  end
  return { kind = "back" }
end

--- Plays the slice from a new game to the end. A real player's taps go the same way: through input.
function M.bot(s, rng)
  if s.over then return nil end
  local mode = s.mode
  if mode == "name" then
    return { kind = "pick", i = M.NAME_DONE }
  elseif mode == "battle" then
    if s.battle and s.battle.result then return nil end
    return part("battle").bot(s, rng)
  elseif mode == "talk" then
    local run = s.run
    if not run or run.wait == "fade" or not run.wait then return nil end
    if run.wait == "pick" then
      -- the first option that moves on: a topic comes back to the list, so it would never finish
      local step = choiceStep(run)
      local mem = botMem(s)
      if s.frame - (mem.changedAt or 0) > BOT_STALL and step and step.choice then
        -- nothing has moved for a long time, so this may be a puzzle: try the answers in turn
        mem.picks = mem.picks or {}
        local key = tostring(run.id) .. ":" .. #run.at .. ":" .. run.at[#run.at].i
        mem.picks[key] = (mem.picks[key] or 0) + 1
        return { kind = "pick", i = (mem.picks[key] - 1) % #step.choice + 1 }
      end
      for i, option in ipairs(step and step.choice or {}) do
        if not option.again then return { kind = "pick", i = i } end
      end
      return { kind = "pick", i = 1 }
    end
    return { kind = "tap" }
  elseif mode == "menu" then
    return botMenu(s)
  elseif mode == "shop" then
    return botShop(s)
  end
  local mem = botMem(s)
  if hurtMember(s) and botHeal(s) or betterGear(s) then
    if mode == "world" or not M.target(s) then return { kind = "menu" } end
  end
  if mode == "world" then return botOnWorld(s, mem) end
  return botOnFoot(s, mem)
end

-- ---------------------------------------------------------------- the guide

-- Where the main story goes next. Nothing here is kept in the state: it's worked out from the flags and the data for each
-- picture, so an old save simply gets a guide, and a story with no GOALS gets none. Places link up as a small graph: each map
-- by its exits, and the overworld by its sites. "world" is the overworld's name in it.

local function currentGoal(s)
  for _, goal in ipairs(story().GOALS or {}) do
    if not (goal.done and s.flags[goal.done]) and (not goal.when or s.flags[goal.when]) then return goal end
  end
  return nil
end

M.currentGoal = currentGoal

--- Which ground the player is on: a menu, a fight or speech is on top of one, and goes back to it.
local function groundOf(s)
  local mode = s.mode
  if mode == "battle" or mode == "menu" or mode == "shop" then mode = s.back end
  if mode == "talk" then mode = s.run and s.run.back end
  return mode == "world" and "world" or "walk"
end

-- The way only changes with the flags, so what's worked out from the map is kept until they do.
local guideCache = { owner = nil, flags = -1, hops = {}, hopCount = 0, land = {}, lands = 0 }
local HOPS_KEPT = 400

local function freshCache(s)
  local flagCount = 0
  for _ in pairs(s.flags) do flagCount = flagCount + 1 end
  if guideCache.owner ~= s or guideCache.flags ~= flagCount or guideCache.hopCount > HOPS_KEPT then
    guideCache.owner, guideCache.flags, guideCache.hops, guideCache.hopCount = s, flagCount, {}, 0
    guideCache.land, guideCache.lands = {}, 0
  end
  return guideCache
end

--- Which piece of land a tile is on. The wall and closed gates cut the map into pieces, and a place across the wall can only be
-- reached through whatever joins them, so to the guide each piece is a place of its own, named "world1", "world2" and so on.
local function landOf(s, x, y)
  local cache = freshCache(s)
  local overworld = part("overworld")
  local key = y * 1000 + x
  if cache.land[key] then return "world" .. cache.land[key] end
  cache.lands = cache.lands + 1
  local id = cache.lands
  cache.land[key] = id
  local order, head = { key }, 1
  while order[head] do
    local at = order[head]
    head = head + 1
    local ax, ay = at % 1000, floor(at / 1000)
    for _, d in ipairs(DIRS) do
      local nx, ny = ax + d[1], ay + d[2]
      local nextKey = ny * 1000 + nx
      if not cache.land[nextKey] and overworld.walkable(nx, ny, s) and not gateAt(s, nx, ny) then
        cache.land[nextKey] = id
        order[#order + 1] = nextKey
      end
    end
  end
  return "world" .. id
end
M.landOf = landOf

--- The ways out of a place, as { to, x, y }. Only ones open now: a closed exit or a site not yet known leads nowhere.
local function linksFrom(s, place)
  local links = {}
  if place:sub(1, 5) == "world" then
    for _, site in ipairs(part("overworld").SITES or {}) do
      if siteAt(s, site.x, site.y) and landOf(s, site.x, site.y) == place then
        links[#links + 1] = { to = site.map, x = site.x, y = site.y }
      end
    end
  else
    local map = mapOf(place)
    for _, e in ipairs(map and map.exits or {}) do
      if passes(s, e) and not e.script then
        links[#links + 1] = { to = e.world and landOf(s, e.world[1], e.world[2]) or e.map, x = e.x, y = e.y }
      end
    end
  end
  return links
end

--- How many hops from one place to another, not going back through avoid, or nil if there's no way.
local function countHops(s, from, target, avoid)
  local hops = { [from] = 0 }
  if avoid then hops[avoid] = -1 end
  local order = { from }
  local head = 1
  while order[head] do
    local place = order[head]
    head = head + 1
    if place == target then return hops[place] end
    for _, link in ipairs(linksFrom(s, place)) do
      if not hops[link.to] then
        hops[link.to] = hops[place] + 1
        order[#order + 1] = link.to
      end
    end
  end
  return nil
end

--- The whole game is a big graph, and the guide is asked on every step of the overworld.
local function hopsBetween(s, from, target, avoid)
  local cache = freshCache(s)
  local key = from .. "|" .. target .. "|" .. tostring(avoid)
  local known = cache.hops[key]
  if known == nil then
    known = countHops(s, from, target, avoid) or false
    cache.hops[key] = known
    cache.hopCount = cache.hopCount + 1
  end
  return known or nil
end

--- Steps to stand beside a square on this map, or on it, or nil if it can't be walked to.
local function stepsTo(dist, x, y)
  local best = dist[y * 1000 + x]
  for _, d in ipairs(DIRS) do
    local steps = dist[(y - d[2]) * 1000 + x - d[1]]
    if steps and (not best or steps < best) then best = steps end
  end
  return best
end

--- The first link on the shortest way from a place: the fewest hops, then the nearest. One that can be walked to beats any
-- that can't, so a blocked door doesn't send the marker through a wall while another way is open.
local function firstLink(s, here, target, nearness)
  local best, bestReach, bestHops, bestSteps
  for _, link in ipairs(linksFrom(s, here)) do
    local hops = hopsBetween(s, link.to, target, here)
    if hops then
      local steps = nearness(link)
      local reach = steps ~= nil
      local better = not best or (reach and not bestReach) or (reach == bestReach and hops < bestHops)
        or (reach == bestReach and hops == bestHops and (steps or 0) < (bestSteps or 0))
      if better then best, bestReach, bestHops, bestSteps = link, reach, hops, steps end
    end
  end
  return best
end

--- The story's next goal and the place to head for from here: { text, x, y }, or nil with no goal. A goal with no way there
-- from here keeps its text and has no x and y, so the bar can still say what to do.
function M.goal(s)
  local goal = currentGoal(s)
  if not goal then return nil end
  local out = { text = goal.text }
  local onWorld = groundOf(s) == "world"
  local here = onWorld and landOf(s, s.wx, s.wy)
  local target, tx, ty = goal.map, goal.x, goal.y
  if goal.site then
    for _, site in ipairs(part("overworld").SITES or {}) do
      if site.id == goal.site then
        if onWorld and landOf(s, site.x, site.y) == here then
          out.x, out.y = site.x, site.y
          return out
        end
        target, tx, ty = site.map, site.mx, site.my
      end
    end
  end
  if not target then return out end
  if not onWorld and target == s.map then
    out.x, out.y = tx, ty
    return out
  end
  local link
  if onWorld then
    link = firstLink(s, here, target, function(l) return abs(l.x - s.wx) + abs(l.y - s.wy) end)
  elseif mapOf(s.map) then
    local dist = botFlood(s)
    link = firstLink(s, s.map, target, function(l) return stepsTo(dist, l.x, l.y) end)
  end
  if link then out.x, out.y = link.x, link.y end
  return out
end

return M
