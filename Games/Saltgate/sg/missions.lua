-- missions.lua
-- The story of Saltgate: five jobs for Mama Juno and Rusty, told in steps. Pure data plus a small runner that reads and
-- changes the game through a narrow surface (player, heat, cars, money, messages), so it is tested without a screen.
--
-- Step kinds:
--   car       be in any working car
--   enter     be in the mission's car (spawned by a spawn step)
--   spawn     place the mission's car at a place (done at once)
--   reach     be at a place (car = must be driving; target = in the mission's car; noHeat = with no heat;
--             minHealth = the mission car's health fraction on arrival)
--   wait      stay at a place for seconds (the count pauses while you are away)
--   loseheat  get your heat to 0
-- Any step may have timer (seconds, fails at 0) and done = { heat = n, say = "text", money = n }.

local util = require("sg.util")
local heatlib = require("sg.heat")

local M = {}

M.LIST = {
  {
    id = "fresh_air", title = "Fresh Air", giver = "juno", reward = 200,
    intro = {
      { "Mama Juno", "Wren Calloway. Three years in the Harbor lockup and you still walk like you own the street." },
      { "Wren", "Missed you too, Juno. You said there'd be work." },
      { "Mama Juno", "First you need wheels. Borrow some. Bring them round to my back lot." },
    },
    steps = {
      { kind = "car", text = "Get into any car (walk up to one, press E)." },
      { kind = "reach", place = "juno_lot", car = true, text = "Drive to Juno's back lot." },
    },
    outro = {
      { "Mama Juno", "Not bad. Keep the car. Nobody's going to ask for it back. Probably." },
    },
  },
  {
    id = "hot_broth", title = "Hot Broth", giver = "juno", reward = 350,
    intro = {
      { "Mama Juno", "The night ferry crew want my broth hot. Hot, Wren. Not warm." },
      { "Wren", "Where's the pot?" },
      { "Mama Juno", "Already in your boot. Ferry pier, south shore. Go!" },
    },
    steps = {
      { kind = "car", text = "Get a car for the delivery." },
      { kind = "reach", place = "ferry", car = true, timer = 85, text = "Get the broth to the ferry pier before it cools." },
    },
    outro = {
      { "Ferry Cook", "Still steaming! Tell Juno the crew says thanks." },
    },
  },
  {
    id = "gulls", title = "Gulls on the Roof", giver = "juno", reward = 600,
    intro = {
      { "Mama Juno", "A crate came in on the Brine docks with my name on it." },
      { "Mama Juno", "The Harbor Patrol has the same idea. Get there first, then lose them." },
      { "Wren", "And then?" },
      { "Mama Juno", "Then Rusty. He's got a cellar nobody's ever found." },
    },
    steps = {
      { kind = "reach", place = "crane", text = "Pick up Juno's crate at the dock crane.",
        done = { heat = 2, say = "The crate's tagged! Patrol on the way." } },
      { kind = "loseheat", text = "Lose the Harbor Patrol." },
      { kind = "reach", place = "rusty", car = true, noHeat = true, text = "Take the crate to Rusty's Chop Yard." },
    },
    outro = {
      { "Rusty", "Juno's crate, Juno's runner. Tell her the cellar's still dry." },
    },
  },
  {
    id = "gilded", title = "Gilded", giver = "rusty_door", reward = 1200,
    intro = {
      { "Rusty", "The Gilt brothers park their Sovereign on the tower plaza like a trophy." },
      { "Rusty", "Bring it here with most of the paint still on and I'll make it worth your while." },
      { "Wren", "And the brothers?" },
      { "Rusty", "Will call the Patrol. They always do." },
    },
    steps = {
      { kind = "spawn", vehicle = "sovereign", place = "gilt_lot", heading = math.pi },
      { kind = "enter", text = "Steal the gold Sovereign at the Gilt Tower plaza.",
        done = { heat = 3, say = "The Gilts called it in. Lose them!" } },
      { kind = "reach", place = "rusty", target = true, noHeat = true, minHealth = 0.35,
        text = "Bring the Sovereign to Rusty's, in one piece." },
    },
    outro = {
      { "Rusty", "Look at that shine. The brothers are going to cry into their caviar." },
    },
  },
  {
    id = "low_tide", title = "Low Tide", giver = "juno", reward = 5000,
    intro = {
      { "Mama Juno", "The Gilts own the docks, the Patrol and half of Lantern Row." },
      { "Mama Juno", "Tonight they pay what they owe the city. Then you and I take the last ferry out." },
      { "Wren", "I'll drive. You do the talking." },
    },
    steps = {
      { kind = "car", text = "Get a fast car." },
      { kind = "reach", place = "gilt_door", car = true, text = "Drive Juno to the Gilt Tower doors." },
      { kind = "wait", place = "gilt_door", seconds = 6, text = "Hold the car at the doors while Juno works.",
        away = "Get back to the tower doors!",
        done = { heat = 4, say = "The tower's lit up like a lighthouse. GO!" } },
      { kind = "reach", place = "ferry", car = true, timer = 120, text = "Make the last ferry!" },
    },
    outro = {
      { "Mama Juno", "Look at it, Wren. All those lights, and not one of them belongs to a Gilt any more." },
      { "Wren", "Next ferry's at dawn. Plenty of time to see the town." },
    },
    final = true,
  },
}

M.CREDITS_SECONDS = 90 -- how long the credits music plays after the ending, unless the Patrol interrupts

M.BY_ID = {}
for i, def in ipairs(M.LIST) do
  def.index = i
  M.BY_ID[def.id] = def
end

--- The next mission not yet done, or nil when the story is over.
function M.nextMission(progress)
  for _, def in ipairs(M.LIST) do
    if not progress.done[def.id] then return def end
  end
  return nil
end

local function placeOf(g, name)
  return g.city.places[name]
end

local function at(g, place, extra)
  local p = g.player
  local r = place.r + (extra or 0)
  return util.dist2(p.x, p.z, place.x, place.z) <= r * r
end

--- Start def (the intro has been seen).
function M.start(g, def)
  g.mission = { def = def, index = 0, data = {} }
  M.advance(g)
end

local function finish(g)
  local m = g.mission
  local def = m.def
  g.progress.done[def.id] = true
  g.mission = nil
  g:addMoney(def.reward, def.title)
  g:message("JOB DONE: " .. def.title .. "  +" .. util.money(def.reward), 5, "pass")
  if m.car and m.car ~= g.player.car then m.car.mission = nil end
  if m.car then m.car.mission = nil end
  if def.final then
    g.progress.finished = true
    -- the ending: once the last words are said, the credits roll (the music has a track for them)
    g:dialogue(def.outro, function() g.credits = M.CREDITS_SECONDS end)
  else
    g:dialogue(def.outro)
  end
  g:save()
end

--- Move to the next step, running instant ones as it goes.
function M.advance(g)
  local m = g.mission
  while m do
    m.index = m.index + 1
    local step = m.def.steps[m.index]
    if not step then
      finish(g)
      return
    end
    m.timer = step.timer
    m.waited = 0
    if step.kind == "spawn" then
      local place = placeOf(g, step.place)
      m.car = g:spawnCar(step.vehicle, place.x, place.z, step.heading or 0)
      m.car.mission = true
    else
      return
    end
  end
end

--- A step is done: its reward, then the next.
local function complete(g, step)
  local d = step.done
  if d then
    if d.heat then heatlib.atLeast(g.heat, d.heat, "mission") end
    if d.money then g:addMoney(d.money, "job") end
    if d.say then g:message(d.say, 4, "alarm") end
  end
  M.advance(g)
end

function M.fail(g, reason)
  local m = g.mission
  if not m then return end
  g.mission = nil
  if m.car then
    m.car.mission = nil
  end
  g:message("JOB FAILED: " .. reason, 5, "fail")
end

--- The current objective's text, for the HUD.
function M.objective(g)
  local m = g.mission
  if not m then return nil end
  local step = m.def.steps[m.index]
  if not step then return nil end
  if step.kind == "wait" and m.away then return step.away or step.text end
  if step.kind == "reach" and step.noHeat and g.heat.level > 0 and m.atButHot then
    return "Lose the Patrol first. Nobody opens up with cops on your tail."
  end
  return step.text
end

--- Where the objective is, for the markers and the map: x, z, or nil.
function M.target(g)
  local m = g.mission
  if not m then
    local def = M.nextMission(g.progress)
    if not def then return nil end
    local p = placeOf(g, def.giver)
    return p.x, p.z, "giver"
  end
  local step = m.def.steps[m.index]
  if not step then return nil end
  if step.kind == "enter" and m.car then return m.car.x, m.car.z, "car" end
  if step.kind == "reach" and step.target and m.car and g.player.car ~= m.car then return m.car.x, m.car.z, "car" end
  if step.place then
    local p = placeOf(g, step.place)
    return p.x, p.z, "place"
  end
  return nil
end

--- Advance the running mission by dt seconds.
function M.update(g, dt)
  local m = g.mission
  if not m then return end
  local step = m.def.steps[m.index]
  if not step then return end
  local p = g.player
  local car = p.car

  if m.car and m.car.wrecked then
    M.fail(g, "the " .. m.car.spec.name .. " is wrecked")
    return
  end
  if m.timer then
    m.timer = m.timer - dt
    if m.timer <= 0 then
      M.fail(g, "out of time")
      return
    end
  end

  local kind = step.kind
  if kind == "car" then
    if car and not car.wrecked then complete(g, step) end
  elseif kind == "enter" then
    if car and car == m.car then complete(g, step) end
  elseif kind == "loseheat" then
    if g.heat.level <= 0 then complete(g, step) end
  elseif kind == "reach" then
    local place = placeOf(g, step.place)
    if at(g, place) then
      local ok = true
      if step.car and not (car and not car.wrecked) then ok = false end
      if step.target and car ~= m.car then ok = false end
      m.atButHot = false
      if ok and step.noHeat and g.heat.level > 0 then
        ok = false
        m.atButHot = true
      end
      if ok then
        if step.minHealth and m.car and m.car.health / m.car.spec.health < step.minHealth then
          M.fail(g, "Rusty won't take scrap")
          return
        end
        if car and math.abs(car.v) > 9 then
          m.slowDown = true
          return
        end
        m.slowDown = false
        complete(g, step)
      end
    else
      m.atButHot = false
    end
  elseif kind == "wait" then
    local place = placeOf(g, step.place)
    if at(g, place, 2) then
      m.away = false
      m.waited = m.waited + dt
      if m.waited >= step.seconds then complete(g, step) end
    else
      m.away = true
    end
  end
end

--- Seconds left on the clock, or nil.
function M.timeLeft(g)
  return g.mission and g.mission.timer
end

return M
