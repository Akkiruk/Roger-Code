-- saltgate.lua
-- SALTGATE: LOW TIDE. An open-city crime and driving game in 3D (Pine3D), played on an advanced computer's own screen
-- with its keyboard. (A pocket computer works too.)
--   saltgate             play
--   saltgate bench [n]   drive itself for n frames (default 200) and write the frame times to saltgate_bench.log
--
-- Music: if a music module is installed (music.lua or music/init.lua), it is told what is going on through
-- music.cue(name) and music.setDistrict(name) (gilt, lantern, cinder, brine, mid, when you cross into another);
-- music.init({ speaker, sound }) and music.update(dt) are called too if it has them, and the sound effects keep to
-- 2 notes a tick so the speaker's 8 hold both. Every call is
-- optional and guarded. State cues (sg/hints.lua MUSIC_STATES) are sent when the state changes; event cues
-- (MUSIC_EVENTS) once, after which the current state cue is sent again.

local util = require("sg.util")
local gamelib = require("sg.game")
local render = require("sg.render")
local sound = require("sg.sound")
local missions = require("sg.missions")
local ai = require("sg.ai")
local inputlib = require("sg.input")
local hints = require("sg.hints")

local args = { ... }
local SAVE = "saltgate_save.dat"
local LOG = "saltgate.log"
local BENCH_LOG = "saltgate_bench.log"

local function log(msg)
  local h = fs.open(LOG, "a")
  if h then
    h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg))
    h.close()
  end
end

local function now()
  return os.epoch("local") / 1000
end

-- ---------------------------------------------------------------- settings and saves

local function loadSettings()
  local defaults = { sound = true }
  if fs.exists("saltgate_settings.lua") then
    local ok, t = pcall(dofile, "saltgate_settings.lua")
    if ok and type(t) == "table" then
      for k, v in pairs(t) do defaults[k] = v end
    else
      log("settings unreadable: " .. tostring(t))
    end
  end
  return defaults
end

local function readSave()
  if not fs.exists(SAVE) then return nil end
  local h = fs.open(SAVE, "r")
  if not h then return nil end
  local text = h.readAll()
  h.close()
  local data = textutils.unserialise(text or "")
  if type(data) ~= "table" then
    log("save unreadable, starting fresh")
    return nil
  end
  return data
end

local function writeSave(data)
  local tmp = SAVE .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then
    log("cannot write the save")
    return
  end
  h.write(textutils.serialise(data))
  h.close()
  if fs.exists(SAVE) then fs.delete(SAVE) end
  fs.move(tmp, SAVE)
end

-- ---------------------------------------------------------------- music (optional, from music/)

local music = {}
if fs.exists("music.lua") or fs.exists("music/init.lua") then
  local ok, m = pcall(require, "music")
  if ok and type(m) == "table" then
    music = m
  else
    log("music did not load: " .. tostring(m))
  end
end

local function musicCall(name, ...)
  local f = music[name]
  if type(f) ~= "function" then return end
  local ok, err = pcall(f, ...)
  if not ok then log("music." .. name .. ": " .. tostring(err)) end
end

-- ---------------------------------------------------------------- pages

local CONTROLS = {
  { "CONTROLS", colours.yellow },
  { "" },
  { "ON FOOT", colours.orange },
  { "W / S      walk forward / back" },
  { "A / D      turn left / right" },
  { "SHIFT      run (hold)" },
  { "E          get in, or steal, a car" },
  { "" },
  { "DRIVING", colours.orange },
  { "W          gas (hold)    let go: coast" },
  { "S          brake, then reverse" },
  { "A / D      steer      SPACE  handbrake" },
  { "E          get out    H  horn" },
  { "" },
  { "ANY TIME", colours.orange },
  { "M map   C camera   P pause   ENTER talk" },
  { "Arrow keys work like WASD", colours.lightGrey },
}

local CAMERAS = { "chase", "far", "hood" }

local function run(bench)
  if not term.isColour() then
    print("SALTGATE needs an advanced computer (gold) or an advanced pocket computer.")
    return
  end
  local settings = loadSettings()
  local screen = term.current()
  render.applyPalette(screen)
  screen.setBackgroundColour(colours.black)
  screen.clear()

  local speaker = settings.sound and peripheral.find("speaker") or nil
  -- with the soundtrack playing (up to 6 of the speaker's 8 notes a tick), the effects keep to 2 a tick
  local sfx = sound.new(speaker, music.cue and 2 or 7)
  musicCall("init", { speaker = speaker, sound = settings.sound })

  local saved = readSave()
  local g = gamelib.new({ seed = os.epoch("utc") % 100000, saver = writeSave })
  local r = render.new(screen)
  local inp = inputlib.new(keys)

  local w, h = screen.getSize()
  local text = "Building Saltgate..."
  screen.setCursorPos(math.max(1, math.floor((w - #text) / 2)), math.floor(h / 2))
  screen.setTextColour(colours.yellow)
  screen.write(text)
  r:build(g, function()
    os.queueEvent("saltgate_yield")
    os.pullEvent("saltgate_yield")
  end)

  local mode = bench and "play" or "title"
  local back = "title" -- where the controls page returns to
  local camIndex = 1
  local menuPick = 1
  local timer = os.startTimer(0.05)
  local last = now()
  local titleT = 0
  local frameMs, benchTimes, benchDraw = 0, {}, 0
  local showPerf = false
  local benchFrames = bench and (tonumber(args[2]) or 200) or 0
  local lastMusic, lastDistrict = nil, nil

  if bench then
    local spot = g.city.places.start
    local car = g:spawnCar("marlin", spot.x + 18, spot.z - 4.5, 0, "red")
    g.player.car = car
    ai.init(car, "traffic", 5, 1, 0)
    sfx.speaker = nil
  elseif not music.cue then
    sound.play(sfx, "title")
  end

  local function startGame(fromSave)
    local carry = saved and saved.tutorialDone
    local data = fromSave and saved or nil
    g = gamelib.new({ seed = os.epoch("utc") % 100000, save = data, saver = writeSave, tutorial = not carry })
    if not fromSave and carry then g.tutorialDone = true end
    mode = "play"
    r.camYaw = nil
    inp:clear()
    if not fromSave then
      g:message(g.tutorial and "Saltgate. Three years, and the sea still smells the same." or "Saltgate. Back on the street.", 5)
      writeSave(g:saveData())
    else
      g:message("Welcome back to Saltgate.", 3)
    end
  end

  local function titleItems()
    local items = { { "NEW GAME", "new" } }
    if saved then items[#items + 1] = { "CONTINUE  " .. util.money(saved.money or 0), "continue" } end
    items[#items + 1] = { "CONTROLS", "controls" }
    items[#items + 1] = { "QUIT", "quit" }
    return items
  end
  local PAUSE_ITEMS = { { "RESUME", "resume" }, { "CONTROLS", "controls" }, { "MAP", "map" }, { "SAVE AND QUIT", "quit" } }

  local function menuMove(items)
    if inp:pressedAction("up") then menuPick = (menuPick - 2) % #items + 1 end
    if inp:pressedAction("down") then menuPick = menuPick % #items + 1 end
    if inp:pressedAction("advance") or inp:pressedAction("use") then return items[menuPick][2] end
    return nil
  end

  local function menuLines(items, hint)
    local lines = {}
    for i, item in ipairs(items) do
      local on = i == menuPick
      lines[#lines + 1] = { (on and "> " or "  ") .. item[1] .. (on and " <" or "  "), on and colours.yellow or colours.white }
    end
    lines[#lines + 1] = { hint, colours.lightGrey }
    return lines
  end

  local running = true
  while running do
    local ev = { os.pullEventRaw() }
    local name = ev[1]
    if name == "terminate" then
      if mode ~= "title" and mode ~= "controls" then g:save() end
      running = false
    elseif name == "key" or name == "key_up" then
      inp:event(now(), name, ev[2], ev[3])
    elseif name == "timer" and ev[2] == timer then
      local t0 = now()
      local dt = util.clamp(t0 - last, 0, 0.25)
      last = t0
      timer = os.startTimer(0.05)

      if mode == "title" then
        titleT = titleT + dt
        local items = titleItems()
        if menuPick > #items then menuPick = 1 end
        local pick = menuMove(items)
        if pick == "new" then startGame(false)
        elseif pick == "continue" then startGame(true)
        elseif pick == "controls" then back, mode = "title", "controls"
        elseif pick == "quit" then running = false end
      elseif mode == "play" then
        if not g.talk and not g.overlay then
          if inp:pressedAction("pause") then mode, menuPick = "pause", 1 end
          if inp:pressedAction("map") then mode = "map" end
        end
        if inp:pressedAction("camera") then camIndex = camIndex % #CAMERAS + 1 end
        if inp:pressedAction("perf") then showPerf = not showPerf end
      elseif mode == "pause" then
        local pick = menuMove(PAUSE_ITEMS)
        if inp:pressedAction("pause") or pick == "resume" then mode = "play"
        elseif pick == "controls" then back, mode = "pause", "controls"
        elseif pick == "map" then mode = "map"
        elseif pick == "quit" then
          g:save()
          saved = readSave()
          mode, menuPick = "title", 1
        end
      elseif mode == "controls" then
        if inp:pressedAction("advance") or inp:pressedAction("pause") or inp:pressedAction("use") then
          mode, menuPick = back, 1
        end
      elseif mode == "map" then
        if inp:pressedAction("map") or inp:pressedAction("advance") or inp:pressedAction("pause") then mode = "play" end
      end

      -- the music follows what is going on
      if music.cue then
        local state = mode == "title" and "title" or (mode == "controls" and back == "title" and "title" or hints.music(g, "play"))
        if state ~= lastMusic then
          musicCall("cue", state)
          lastMusic = state
        end
        -- each district has its own arrangement of the roaming tune
        if mode == "play" then
          local district = hints.district(g)
          if district ~= lastDistrict then
            musicCall("setDistrict", district)
            lastDistrict = district
          end
        end
      end

      if mode == "play" then
        local u0 = now()
        local input = inp:read()
        if bench and g.player.car and g.player.car.ai then
          input = ai.traffic(g, g.player.car, dt)
        end
        g:update(dt, input) -- an error here reaches the crash screen with its whole stack
        for _, cue in ipairs(g:takeCues()) do
          sound.play(sfx, cue)
          if cue == "pass" and music.cue then
            musicCall("cue", "job_complete")
            lastMusic = nil -- the state's cue again next frame
          end
        end
        local siren = false
        if g.heat.level > 0 then
          for _, car in ipairs(g.cars) do
            if car.ai and car.ai.mode == "cop" and util.dist2(car.x, car.z, g.player.x, g.player.z) < 60 * 60 then
              siren = true
              break
            end
          end
        end
        sound.update(sfx, dt, siren)
        local r0 = now()
        r:draw(g, CAMERAS[camIndex], dt)
        local ms = (now() - r0) * 1000
        frameMs = frameMs * 0.9 + ms * 0.1
        if showPerf then
          screen.setCursorPos(1, 5)
          screen.setTextColour(colours.white)
          screen.setBackgroundColour(colours.black)
          screen.write(string.format(" %3.0f ms  %d cars %d peds ", frameMs, #g.cars, #g.peds))
        end
        if bench then
          benchTimes[#benchTimes + 1] = (now() - u0) * 1000
          benchDraw = benchDraw + ms
          if #benchTimes >= benchFrames then running = false end
        end
      elseif mode == "title" then
        sound.update(sfx, dt, false)
        r:title(g, titleT, menuLines(titleItems(), "W/S choose   ENTER select"))
      elseif mode == "pause" then
        r:panel(menuLines(PAUSE_ITEMS, "W/S choose   ENTER select   P back"))
      elseif mode == "controls" then
        local lines = {}
        for _, l in ipairs(CONTROLS) do lines[#lines + 1] = l end
        lines[#lines + 1] = { "" }
        lines[#lines + 1] = { "ENTER back", colours.lightGrey }
        r:panel(lines)
      elseif mode == "map" then
        r:drawMap(g)
      end
      musicCall("update", dt)
      inp:endFrame(now())
    end
  end

  if bench then
    table.sort(benchTimes)
    local sum = 0
    for _, ms in ipairs(benchTimes) do sum = sum + ms end
    local n = #benchTimes
    local line = string.format("bench %dx%d chars (%dx%d px): %d frames, update+draw mean %.1f ms, median %.1f ms, p90 %.1f ms, max %.1f ms; draw alone mean %.1f ms",
      w, h, w * 2, h * 3, n, sum / math.max(1, n), benchTimes[math.max(1, math.floor(n / 2))] or 0,
      benchTimes[math.max(1, math.floor(n * 0.9))] or 0, benchTimes[n] or 0, benchDraw / math.max(1, n))
    local f = fs.open(BENCH_LOG, "a")
    if f then
      f.writeLine(line)
      f.close()
    end
    return -- the last frame stays on the screen
  end

  musicCall("stop")
  render.resetPalette(screen)
  screen.setBackgroundColour(colours.black)
  screen.setTextColour(colours.white)
  screen.clear()
  screen.setCursorPos(1, 1)
  print("Thanks for driving in Saltgate.")
end

-- ---------------------------------------------------------------- when it goes wrong

local CRASH_LOG = "saltgate_crash.log"
local native = term.current()

--- The error and where it happened, on the screen and in saltgate_crash.log, so it can be sent to whoever fixes it.
local function showCrash(err, trace)
  local h = fs.open(CRASH_LOG, "a")
  if h then
    h.writeLine("==== " .. os.date("%Y-%m-%d %H:%M:%S"))
    h.writeLine(tostring(err))
    h.writeLine(tostring(trace))
    h.close()
  end
  log("crash: " .. tostring(err))
  term.redirect(native)
  render.resetPalette(native)
  native.setBackgroundColour(colours.black)
  native.clear()
  local w, hgt = native.getSize()
  local y = 1
  local function line(text, colour)
    for _, part in ipairs(render.wrap(text, w - 1)) do
      if y > hgt - 2 then return end
      native.setCursorPos(1, y)
      native.setTextColour(colour)
      native.write(part)
      y = y + 1
    end
  end
  line("SALTGATE crashed. Sorry!", colours.red)
  line(tostring(err), colours.yellow)
  for frame in tostring(trace):gmatch("[^\n]+") do
    if not frame:find("^stack traceback") and not frame:find("%[C%]") then
      line(frame:gsub("^%s+", ""), colours.lightGrey)
    end
  end
  native.setCursorPos(1, hgt - 1)
  native.setTextColour(colours.white)
  native.write("Saved to " .. CRASH_LOG .. ".")
  native.setCursorPos(1, hgt)
  native.write("Press any key to restart.")
  os.pullEvent("key")
end

local crashTrace = nil
local ok, err = xpcall(function() run(args[1] == "bench") end, function(e)
  crashTrace = debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
  return e
end)
if not ok then
  if type(err) == "string" and err:find("Terminated", 1, true) then
    render.resetPalette(native)
    error(err, 0)
  end
  local shown = pcall(showCrash, err, crashTrace)
  if not shown then log("crash: " .. tostring(err)) end
  error(err, 0)
end
