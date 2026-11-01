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
  return (tostring(text):gsub("{hero}", function() return s.heroName end))
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

local function take(s, id)
  local left = (s.bag[id] or 0) - 1
  s.bag[id] = left > 0 and left or nil
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
  if following and following.choice then
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
  s.mode = run.back
  if run.once then s.opened[run.once] = true end
  changed(s)
  if run.arrived and s.mode == "walk" then checkStep(s) end
end

--- A fight. The engine keeps its own note of what it was for, so it needn't read inside the battle.
local function startFight(s, enc, foeId, back, rng, events)
  s.fight = { enc = enc, foe = foeId }
  s.back = back
  s.queue = {}
  s.heading = nil
  part("battle").begin(s, enc, rng)
  s.mode = "battle"
  emit(events, "battle", { enc = enc })
  changed(s)
end

local function toWorld(s, x, y)
  s.wx, s.wy, s.heading = x, y, nil
  s.foes = {}
  s.hints.world = s.hints.world or HINT_TICKS
end

local function doStep(s, step, rng, events)
  local run = s.run
  if step.when and (step.steps or step.other) then
    local k = s.flags[step.when] and "steps" or "other"
    if step[k] then run.at[#run.at + 1] = { k = k, i = 1 } end
  elseif step.say or step.text then
    show(s, step.say, step.text or "", step.name)
    emit(events, "talk")
  elseif step.big then
    run.say, run.name, run.text, run.page, run.wait = nil, nil, nil, 1, "tap"
    run.big = fillName(s, step.big)
    emit(events, "big")
    changed(s)
  elseif step.choice then
    run.wait = "pick"
    changed(s)
  elseif step.set then
    s.flags[step.set] = true
  elseif step.unset then
    s.flags[step.unset] = nil
  elseif step.give then
    give(s, step.give, step.n)
    emit(events, "item")
  elseif step.gold then
    s.gold = max(0, s.gold + step.gold)
    emit(events, "gold")
  elseif step.join then
    local there = false
    for _, member in ipairs(s.party) do there = there or member.id == step.join end
    if not there then s.party[#s.party + 1] = part("party").new(step.join, step.lvl or 1) end
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
      run.at[#run.at + 1] = { k = action.i, i = 1 }
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
  run.wait, run.big = nil, nil
  emit(events, "page")
end

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

local function wipe(s, events)
  s.run, s.back, s.battle, s.fight = nil, nil, nil, nil
  s.gold = floor(s.gold / 2)
  healAll(s)
  local at = s.savepoint
  if at then enterMap(s, at.map, at.x, at.y, at.dir, nil) end
  s.fx.fade = FADE_TICKS
  s.mode = "walk"
  emit(events, "wipe")
  note(s, "Everything goes dark. You come to at the last safe place, with half your gold gone.", "walk")
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
  s.level = s.party[1].lvl
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
    openMenu(s, events)
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
    if site.x == x and site.y == y and (not site.when or s.flags[site.when]) then return site end
  end
  return nil
end
M.siteAt = siteAt

local function gateAt(s, x, y)
  for _, gate in ipairs(part("overworld").GATES or {}) do
    if gate.x == x and gate.y == y and passes(s, gate) then return gate end
  end
  return nil
end
M.gateAt = gateAt

--- Walking a road stops where the road bends, so a tap is all a corner costs.
local function roadBends(s)
  local overworld = part("overworld")
  local function road(x, y)
    local c = overworld.tileAt(x, y)
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
  local region = part("overworld").region(s.wx, s.wy)
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
    s.heading = nil
    startScript(s, gate.script)
    return
  end
  if not overworld.walkable(x, y) then
    s.heading = nil
    emit(events, "bump")
    changed(s)
    return
  end
  s.wx, s.wy, s.msg = x, y, ""
  emit(events, "step")
  changed(s)
  local site = siteAt(s, x, y)
  if site then
    s.heading = nil
    s.mode = "walk"
    enterMap(s, site.map, site.mx, site.my, site.dir, events)
    emit(events, "door")
    checkStep(s)
    return
  end
  rollEncounter(s, rng, events)
  if s.mode == "world" and roadBends(s) then s.heading = nil end
end

local function worldTick(s, rng, events)
  if not s.heading then
    s.walkClock = 0
    return
  end
  s.walkClock = s.walkClock + 1
  if s.walkClock >= WORLD_TICKS_A_TILE then
    s.walkClock = 0
    worldStep(s, rng, events)
  end
end

local function worldInput(s, action, events)
  if action.kind == "turn" then
    s.heading = WAYS[action.dir]
    s.walkClock = WORLD_TICKS_A_TILE - 1 -- the first tile answers the tap
    emit(events, "turn")
  elseif action.kind == "act" then
    if s.heading then s.heading = nil else openMenu(s, events) end
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
      rows[#rows + 1] = { label = itemName(id) .. " x" .. s.bag[id], item = id, field = party.ITEMS[id].field == true }
    end
  end
  return rows
end

local function slotOf(gearId)
  local def = part("party").GEAR[gearId]
  return def and def.slot
end

--- The gear in the bag, weapons first. The sort matters: pairs has no order, and a tap must mean the same row twice.
local function gearRows(s)
  local ids = {}
  for id in pairs(s.bag) do
    if slotOf(id) then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b)
    if slotOf(a) ~= slotOf(b) then return slotOf(a) == "weapon" end
    return a < b
  end)
  local rows = {}
  for i, id in ipairs(ids) do
    rows[i] = { label = itemName(id) .. " x" .. s.bag[id], gear = id, slot = slotOf(id) }
  end
  return rows
end

--- The rows of the menu page that's open. Each is a table with label and whatever a pick needs.
function M.menuRows(s)
  local menu = s.menu
  if not menu then return {} end
  if menu.page == "main" then
    return { { label = "ITEMS", go = "items" }, { label = "GEAR", go = "gear" }, { label = "STATUS", go = "status" }, { label = "CLOSE", close = true } }
  elseif menu.page == "items" then
    return pageOf(bagRows(s), menu.top)
  elseif menu.page == "useon" or menu.page == "gear" or menu.page == "status" then
    return memberRows(s)
  elseif menu.page == "equip" then
    return pageOf(gearRows(s), menu.top)
  end
  return {}
end

--- Use one item on a member, if it would do anything. Returns a line for the wall.
local function useItem(s, id, member)
  local hp, mp = part("party").applyItem(member, id)
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
    local list = menu.page == "items" and bagRows(s) or gearRows(s)
    menu.top = menu.top + MENU_ROWS - 1
    if menu.top >= #list then menu.top = 0 end
  elseif row.go then
    menu.page, menu.top = row.go, 0
  elseif row.item then
    if row.field then
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
  menu.line = nil
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

-- ---------------------------------------------------------------- one tap

local function apply(s, action, rng, events)
  local mode = s.mode
  if mode == "walk" then
    if action.kind == "act" then act(s, rng, events) end
    if action.kind == "turn" then steer(s, action.dir, rng, events) end
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

function M.new(opts)
  local name = opts and opts.player
  local s = {
    v = 1, score = 0, level = 1, over = false, won = false, rev = 0, frame = 0,
    heroName = (type(name) == "string" and name ~= "") and name or "Hero",
    mode = "talk", back = nil,
    map = "scythebreak", x = 3, y = 3, dir = 1,
    wx = 10, wy = 10, heading = nil, walkClock = 0, safeSteps = ENCOUNTER_GRACE,
    party = { part("party").new("hero", 1) },
    bag = { potion = 3 }, gold = 0,
    flags = {}, opened = {}, beaten = {}, foes = {},
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
  if s.mode == "battle" then
    part("battle").input(s, action)
    return
  end
  if #s.queue >= QUEUE_LONGEST then return end
  s.queue[#s.queue + 1] = { kind = action.kind, dir = action.dir, i = action.i }
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

local function botMem(s)
  local mem = s.botMem
  if not mem then
    mem = { tried = {}, seen = {}, sig = -1 }
    s.botMem = mem
  end
  local sig = #s.party
  for _ in pairs(s.flags) do sig = sig + 1 end
  if sig ~= mem.sig then
    mem.sig, mem.tried = sig, {}
  end
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
  local steps, people, chests, foes, newExits, oldExits = {}, {}, {}, {}, {}, {}
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
  if s.level < BOT_FOR_BOSS then
    for _, f in ipairs(s.foes or {}) do add(foes, f.x, f.y, true, "foe:" .. s.map .. ":" .. f.id) end
  end
  for _, e in ipairs(map.exits or {}) do
    if passes(s, e) then
      local to = e.map or "world"
      add(mem.seen[to] and oldExits or newExits, e.x, e.y, false, "exit:" .. s.map .. ":" .. e.x .. "," .. e.y)
    end
  end
  return { steps, people, chests, foes, newExits, oldExits }
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
      if not from[y * 1000 + x] and overworld.walkable(x, y) then
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
    local sites = {}
    for _, site in ipairs(part("overworld").SITES or {}) do
      if siteAt(s, site.x, site.y) and not (site.x == s.wx and site.y == s.wy) then
        local rank = (mem.seen[site.map] and 2 or 0) + (mem.tried["site:" .. site.id] and 1 or 0)
        sites[#sites + 1] = { site = site, rank = rank }
      end
    end
    table.sort(sites, function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      return a.site.id < b.site.id
    end)
    local pick = sites[1]
    local ways = pick and worldPath(s, pick.site.x, pick.site.y)
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
  local function power(id)
    local def = party.GEAR[id]
    return def and ((def.atk or 0) + (def.def or 0)) or 0
  end
  local ids = {}
  for id in pairs(s.bag) do
    if party.GEAR[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for i, member in ipairs(s.party) do
    for _, id in ipairs(ids) do
      local slot = party.GEAR[id].slot
      if power(id) > power(member[slot]) then return i, id end
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

local function botMenu(s)
  local menu = s.menu
  local hurt = (s.bag.potion or 0) > 0 and hurtMember(s)
  local who, gear = betterGear(s)
  local rows = M.menuRows(s)
  if menu.page == "main" then
    if hurt then return { kind = "pick", i = 1 } end
    if who then return { kind = "pick", i = 2 } end
    return { kind = "pick", i = 4 }
  elseif menu.page == "items" then
    local i = hurt and (rowWhere(rows, "item", "potion") or rowWhere(rows, "more", true))
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
        local worn = party.GEAR[s.party[1][def.slot]]
        if (def.atk or 0) + (def.def or 0) > (worn and (worn.atk or 0) + (worn.def or 0) or 0) then
          return { kind = "pick", i = i }
        end
      elseif row.ware == "potion" and (s.bag.potion or 0) < BOT_POTIONS then
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
  if mode == "battle" then
    if s.battle and s.battle.result then return nil end
    return part("battle").bot(s, rng)
  elseif mode == "talk" then
    local run = s.run
    if not run or run.wait == "fade" or not run.wait then return nil end
    if run.wait == "pick" then return { kind = "pick", i = 1 } end
    return { kind = "tap" }
  elseif mode == "menu" then
    return botMenu(s)
  elseif mode == "shop" then
    return botShop(s)
  end
  if s.fin then return nil end
  local mem = botMem(s)
  if hurtMember(s) and (s.bag.potion or 0) > 0 or betterGear(s) then
    if mode == "world" or not M.target(s) then return { kind = "act" } end
  end
  if mode == "world" then return botOnWorld(s, mem) end
  return botOnFoot(s, mem)
end

return M
