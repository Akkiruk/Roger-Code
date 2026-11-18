-- saltgate.lua
-- SALTGATE: LOW TIDE. An open-city crime and driving game in 3D (Pine3D) for an advanced computer, or a big advanced
-- monitor with the keyboard on its computer.
--   saltgate             play
--   saltgate bench [n]   drive itself for n frames (default 200) and write the frame times to saltgate_bench.log

local util = require("sg.util")
local gamelib = require("sg.game")
local render = require("sg.render")
local sound = require("sg.sound")
local missions = require("sg.missions")
local heatlib = require("sg.heat")
local ai = require("sg.ai")

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
  local defaults = { display = "auto", monitorScale = 0, maxColumns = 100, sound = true }
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

-- ---------------------------------------------------------------- the screen

local settings = loadSettings()

local function biggestMonitor()
  local best, bestArea = nil, 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      local m = peripheral.wrap(name)
      if m.isColour and m.isColour() then
        m.setTextScale(0.5)
        local w, h = m.getSize()
        if w * h > bestArea then best, bestArea = m, w * h end
      end
    end
  end
  return best
end

local SCALES = { 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5 }

local function fitScale(mon)
  if settings.monitorScale and settings.monitorScale > 0 then
    mon.setTextScale(settings.monitorScale)
    return settings.monitorScale
  end
  for _, s in ipairs(SCALES) do
    mon.setTextScale(s)
    local w = mon.getSize()
    if w <= settings.maxColumns then return s end
  end
  return 5
end

local native = term.current()
local display = { target = native, monitor = nil, onMonitor = false, scale = nil }

local function chooseDisplay(wantMonitor)
  local mon = nil
  if settings.display ~= "terminal" then mon = biggestMonitor() end
  display.monitor = mon
  if mon and wantMonitor ~= false then
    display.scale = display.scale or fitScale(mon)
    mon.setTextScale(display.scale)
    display.target = mon
    display.onMonitor = true
  else
    display.target = native
    display.onMonitor = false
  end
  render.applyPalette(display.target)
  display.target.setBackgroundColour(colours.black)
  display.target.clear()
end

-- ---------------------------------------------------------------- input

local held = {}
local pressed = {}

local function down(...)
  for _, k in ipairs({ ... }) do
    if k and held[k] then return true end
  end
  return false
end

local function tapped(...)
  for _, k in ipairs({ ... }) do
    if k and pressed[k] then return true end
  end
  return false
end

local function readInput()
  local throttle = (down(keys.w, keys.up) and 1 or 0) - (down(keys.s, keys.down) and 1 or 0)
  local steer = (down(keys.d, keys.right) and 1 or 0) - (down(keys.a, keys.left) and 1 or 0)
  return {
    throttle = throttle,
    steer = steer,
    handbrake = down(keys.space),
    sprint = down(keys.leftShift, keys.rightShift),
    enter = tapped(keys.f, keys.e),
    horn = tapped(keys.h),
    advance = tapped(keys.enter, keys.numPadEnter, keys.space),
  }
end

-- ---------------------------------------------------------------- the game

local function controlsPanel(extra)
  local lines = {
    { "SALTGATE: LOW TIDE", colours.yellow },
    { "" },
    { "W/S or Up/Down   drive / walk", colours.white },
    { "A/D or Left/Right  steer / turn", colours.white },
    { "Space  handbrake     Shift  run", colours.white },
    { "F  get in or out (take any car)", colours.white },
    { "H  horn   C  camera   M  map", colours.white },
    { "P  pause   Enter  next line", colours.white },
    { "" },
    { "Heat: the Patrol chases at 1-5 pips.", colours.lightGrey },
    { "Stay out of sight to cool off, or", colours.lightGrey },
    { "pay Paint & Pray for a respray.", colours.lightGrey },
  }
  for _, l in ipairs(extra or {}) do lines[#lines + 1] = l end
  return lines
end

local CAMERAS = { "chase", "far", "hood" }

local function run(bench)
  if not term.isColour() then
    print("SALTGATE needs an advanced computer (gold), or an advanced monitor.")
    return
  end
  chooseDisplay(true)
  local speaker = settings.sound and peripheral.find("speaker") or nil
  local sfx = sound.new(speaker)

  local saved = readSave()
  local g = gamelib.new({ seed = os.epoch("utc") % 100000, save = nil, saver = writeSave })
  local r = render.new(display.target)

  local function loading(text)
    local t = display.target
    t.setBackgroundColour(colours.black)
    t.clear()
    local w, h = t.getSize()
    t.setCursorPos(math.max(1, math.floor((w - #text) / 2)), math.floor(h / 2))
    t.setTextColour(colours.yellow)
    t.write(text)
  end
  loading("Building Saltgate...")
  local function breathe()
    os.queueEvent("saltgate_yield")
    os.pullEvent("saltgate_yield")
  end
  r:build(g, breathe)

  if display.onMonitor then
    native.setBackgroundColour(colours.black)
    native.clear()
  end

  local function showTerminalHelp()
    if not display.onMonitor then return end
    render.applyPalette(native)
    native.setBackgroundColour(colours.black)
    native.clear()
    local lines = controlsPanel({ { "" }, { "Playing on the monitor.", colours.cyan }, { "V: play here instead", colours.lightGrey } })
    for i, l in ipairs(lines) do
      native.setCursorPos(2, i + 1)
      native.setTextColour(l[2] or colours.white)
      native.write(l[1])
    end
  end
  showTerminalHelp()

  local mode = bench and "play" or "title"
  local camIndex = 1
  local menuPick = saved and 2 or 1
  local timer = os.startTimer(0.05)
  local last = now()
  local titleT = 0
  local frameMs, frameCount, benchTimes, benchDraw = 0, 0, {}, 0
  local showPerf = false
  local benchFrames = bench and (tonumber(args[2]) or 200) or 0

  if bench then
    g.quiet = false
    local spot = g.city.places.start
    local car = g:spawnCar("marlin", spot.x + 18, spot.z - 4.5, 0, "red")
    g.player.car = car
    ai.init(car, "traffic", 5, 1, 0)
    sfx.speaker = nil
  else
    sound.play(sfx, "title")
  end

  local function startGame(fromSave)
    g = gamelib.new({ seed = os.epoch("utc") % 100000, save = fromSave and saved or nil, saver = writeSave })
    -- the renderer keeps its city models: the city is the same every game
    mode = "play"
    r.camYaw = nil
    if not fromSave then
      g:message("Saltgate. Three years, and the sea still smells the same.", 5)
      writeSave(g:saveData())
    else
      g:message("Welcome back to Saltgate.", 3)
    end
  end

  local running = true
  while running do
    local ev = { os.pullEventRaw() }
    local name = ev[1]
    if name == "terminate" then
      if mode ~= "title" then g:save() end
      running = false
    elseif name == "key" then
      if not ev[3] then pressed[ev[2]] = true end
      held[ev[2]] = true
    elseif name == "key_up" then
      held[ev[2]] = nil
    elseif name == "monitor_resize" then
      -- setting a text scale fires this too: only follow a real change of size, and never set the scale here
      if display.onMonitor then
        local w, h = display.target.getSize()
        if w ~= r.cw or h ~= r.ch then r:setTarget(display.target) end
      end
    elseif name == "peripheral" or name == "peripheral_detach" then
      chooseDisplay(display.onMonitor or name == "peripheral")
      r:setTarget(display.target)
      showTerminalHelp()
    elseif name == "timer" and ev[2] == timer then
      local t0 = now()
      local dt = util.clamp(t0 - last, 0, 0.25)
      last = t0
      timer = os.startTimer(0.05)

      -- keys that change screens
      if mode == "title" then
        titleT = titleT + dt
        if tapped(keys.up, keys.w) then menuPick = 1 end
        if tapped(keys.down, keys.s) and saved then menuPick = 2 end
        if tapped(keys.enter, keys.numPadEnter, keys.space) then
          startGame(menuPick == 2 and saved ~= nil)
        elseif tapped(keys.c) and saved then
          startGame(true)
        elseif tapped(keys.n) then
          startGame(false)
        elseif tapped(keys.q) then
          running = false
        end
      elseif mode == "play" then
        if tapped(keys.p, keys.tab) and not g.talk then mode = "pause" end
        if tapped(keys.m) and not g.talk then mode = "map" end
        if tapped(keys.c) then camIndex = camIndex % #CAMERAS + 1 end
        if tapped(keys.f3) then showPerf = not showPerf end
      elseif mode == "pause" then
        if tapped(keys.p, keys.tab, keys.enter, keys.numPadEnter) then mode = "play" end
        if tapped(keys.q) then
          g:save()
          mode = "title"
          saved = readSave()
          menuPick = saved and 2 or 1
        end
      elseif mode == "map" then
        if tapped(keys.m, keys.enter, keys.p, keys.tab) then mode = "play" end
      end
      if tapped(keys.v) and display.monitor then
        chooseDisplay(not display.onMonitor)
        r:setTarget(display.target)
        if not display.onMonitor then render.applyPalette(native) end
        showTerminalHelp()
      end
      if tapped(keys.r) and display.onMonitor and mode ~= "title" then
        local idx = 1
        for i, s in ipairs(SCALES) do if s == display.scale then idx = i end end
        display.scale = SCALES[idx % 4 + 1]
        display.monitor.setTextScale(display.scale)
        r:setTarget(display.target)
      end

      if mode == "play" then
        local u0 = now()
        local input = readInput()
        if bench and g.player.car and g.player.car.ai then
          input = ai.traffic(g, g.player.car, dt)
        end
        local ok, err = pcall(g.update, g, dt, input)
        if not ok then
          log("update: " .. tostring(err))
          error(err, 0)
        end
        for _, cue in ipairs(g:takeCues()) do sound.play(sfx, cue) end
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
        frameCount = frameCount + 1
        if showPerf then
          local t = display.target
          t.setCursorPos(1, 2)
          t.setTextColour(colours.white)
          t.setBackgroundColour(colours.black)
          t.write(string.format(" %3.0f ms  %d cars %d peds ", frameMs, #g.cars, #g.peds))
        end
        if bench then
          benchTimes[#benchTimes + 1] = (now() - u0) * 1000
          benchDraw = benchDraw + ms
          if #benchTimes >= benchFrames then running = false end
        end
      elseif mode == "title" then
        sound.update(sfx, dt, false)
        local lines = {
          { (menuPick == 1 and "> " or "  ") .. "NEW GAME" .. (menuPick == 1 and " <" or "  "), menuPick == 1 and colours.yellow or colours.white },
        }
        if saved then
          lines[#lines + 1] = { (menuPick == 2 and "> " or "  ") .. "CONTINUE  " .. util.money(saved.money or 0)
            .. (menuPick == 2 and " <" or "  "), menuPick == 2 and colours.yellow or colours.white }
        end
        lines[#lines + 1] = { "Enter: play   Q: quit", colours.lightGrey }
        r:title(g, titleT, lines)
      elseif mode == "pause" then
        r:panel(controlsPanel({ { "" }, { "P: back to the street    Q: save and quit", colours.cyan },
          { "Jobs done: " .. (function()
            local n = 0
            for _ in pairs(g.progress.done) do n = n + 1 end
            return n
          end)() .. " of " .. #missions.LIST .. "   Cars taken: " .. g.stats.cars, colours.lightGrey } }))
      elseif mode == "map" then
        r:drawMap(g)
      end
      pressed = {}
    end
  end

  if bench then
    table.sort(benchTimes)
    local sum = 0
    for _, ms in ipairs(benchTimes) do sum = sum + ms end
    local n = #benchTimes
    local w, h = display.target.getSize()
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

  render.resetPalette(native)
  if display.monitor then
    render.resetPalette(display.monitor)
    display.monitor.setBackgroundColour(colours.black)
    display.monitor.clear()
  end
  native.setBackgroundColour(colours.black)
  native.setTextColour(colours.white)
  native.clear()
  native.setCursorPos(1, 1)
  if not bench then print("Thanks for driving in Saltgate.") end
  local _ = heatlib
end

local ok, err = pcall(run, args[1] == "bench")
if not ok then
  log("crash: " .. tostring(err))
  render.resetPalette(native)
  term.redirect(native)
  error(err, 0)
end
