-- plugins/e_radio.lua
-- Stream E: the car radio and the soundtrack's director. Four stations, R changes them; the DJ's lines come up as
-- messages. It also cues the rest of the soundtrack from the game's state (title, free roam, chases, jobs, stings) through
-- the music module's public functions (music/player.lua). Settings for sound, music and volume are applied here.
--   ctx.radio   the radio (sg/radio.lua): ctx.radio:next() ctx.radio:label() ctx.radio.station

local radioLib = require("sg.radio")

local P = { name = "e_radio", order = 40, needs = { "e_ui" } }

local function nowSeconds()
  local os_ = rawget(_G, "os")
  if os_ and os_.epoch then return os_.epoch("utc") / 1000 end
  return os.clock()
end

function P.init(ctx)
  local data = ctx.content:data("activities/radio.lua")
  if not data then
    ctx.log("e_radio: no radio.lua")
    return
  end
  -- the music module is optional: without it (or a speaker) the radio still tunes and the DJ still talks
  local ok, music = pcall(require, "music")
  if not ok then music = nil end
  local settings = ctx.eui.settings
  local stats = ctx.progress and ctx.progress.stats
  local state = { title = false, car = false, heat = 0, mission = false, district = nil }
  local saved = ctx.save.settings.station
  local radio = radioLib.new({
    data = data, music = music, station = type(saved) == "number" and saved or 1,
    onLine = function(station, text)
      ctx.hud.toast(station.dj .. ": " .. text, "cyan", data.lineSeconds or 7, station.name, "dj")
    end,
    onHear = function(station)
      if stats and stats:member("stations", station.id) then ctx.progress.achievements:check() end
    end,
  })
  ctx.radio = radio
  local music_ = { dt = 0, last = nowSeconds(), state = state }
  ctx.musicState = music_

  ctx.hud.radioLine = function()
    if not settings:get("music") then return nil end
    local s = radio:current()
    return "R " .. (s and s.name or "radio off")
  end

  local function applySettings()
    if not music then return end
    music.setEnabled(settings:get("sound") and settings:get("music"))
    music.setVolume(settings:get("musicVolume"))
  end
  settings:hook(function(name)
    if name == "sound" or name == "music" or name == "musicVolume" then applySettings() end
  end)
  if music then
    local init = pcall(music.init, { sound = settings:get("sound"), music = settings:get("music"), volume = settings:get("musicVolume") })
    if not init then music = nil radio.music = nil end
  end
  applySettings()

  local bus = ctx.bus
  bus:on("heat_changed", function(d) state.heat = d.level end, "e_radio")
  bus:on("mission_start", function() state.mission = true end, "e_radio")
  bus:on("mission_end", function(d)
    state.mission = false
    if d.result == "pass" and music then music.cue("job_complete") end
  end, "e_radio")
  bus:on("player_down", function(d)
    if music then music.cue(d.kind == "nabbed" and "cuffed" or "wasted") end
  end, "e_radio")
  bus:on("district_enter", function(d)
    local id = d.district
    if id ~= "gilt" and id ~= "lantern" and id ~= "cinder" and id ~= "brine" then id = "mid" end
    state.district = id
  end, "e_radio")
  bus:on("vehicle_enter", function() state.car = true end, "e_radio")
  bus:on("vehicle_exit", function() state.car = false end, "e_radio")
end

function P.update(ctx)
  local radio = ctx.radio
  if not radio then return end
  -- R: the next station (in a car)
  if ctx.player.car and ctx.eui.keys:pressed("radio") then
    radio:next()
    ctx.save.settings.station = radio.station
    local s = radio:current()
    ctx.hud.toast(s and (s.freq .. "  " .. s.name) or "Radio off", s and "cyan" or "lightGray", 2.5, nil, "radio")
  end
end

function P.draw(ctx)
  local radio = ctx.radio
  if not radio then return end
  local ms = ctx.musicState
  local t = nowSeconds()
  local dt = math.min(0.25, math.max(0, t - ms.last))
  ms.last = t
  local top = ctx.ui.top()
  local state = ms.state
  state.title = top ~= nil and top.name == "e_title"
  state.car = ctx.player.car ~= nil
  radio:setState(state)
  if top and top.name == "play" then
    radio:update(dt)
  else
    radio:apply()
  end
  local ok, music = pcall(require, "music")
  if ok and music and music.update then music.update(dt) end
end

return P
