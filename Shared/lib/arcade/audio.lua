-- arcade_audio.lua
-- Sound events on top of lib.sound. A game adds its own events with addSounds; a small timeline lets one event play
-- several sounds a little apart.

local config = require("lib.arcade.constants")
local picks = require("lib.sound_picks")
local sound = require("lib.sound")

local M = {}

local enabled = true
local volume = 1.0
local sounds = {}
local pending = {} -- { at = ms, event = name } sorted by time
local lastAny = -1e9
local MIN_GAP_MS = 60 -- a speaker takes one sound per game tick (50 ms); a second in the same tick is refused

for name, def in pairs(picks) do sounds[name] = def end
for name, def in pairs(config.SOUNDS) do sounds[name] = def end

local function nowMs()
  return os.epoch("local")
end

local function pendingInsert(item)
  pending[#pending + 1] = item
  table.sort(pending, function(a, b) return a.at < b.at end)
end

function M.init(side)
  return sound.init(side)
end

function M.addSounds(map)
  for name, def in pairs(map or {}) do sounds[name] = def end
end

function M.setEnabled(on) enabled = on and true or false end
function M.setVolume(v) volume = math.max(0, math.min(3, tonumber(v) or 1)) end
function M.isAvailable() return sound.isAvailable() end

--- Play an event now. Returns true if the speaker accepted it.
function M.play(event, volScale, pitchScale)
  if not enabled then return false end
  local def = sounds[event]
  if not def then return false, "unknown sound event " .. tostring(event) end
  local t = nowMs()
  if t - lastAny < MIN_GAP_MS then
    -- too close to the previous sound: play it right after instead of losing it
    pendingInsert({ at = lastAny + MIN_GAP_MS, event = event, vol = volScale, pitch = pitchScale })
    return false, "deferred"
  end
  lastAny = t
  local vol = math.min(3, def[2] * volume * (volScale or 1))
  local pitch = math.max(0.5, math.min(2, def[3] * (pitchScale or 1)))
  local ok, err = sound.play(def[1], vol, pitch)
  if fs.exists(config.DEBUG_FLAG) then
    local h = fs.open("arcade_sound.log", "a")
    if h then
      h.writeLine(string.format("%s %s %.2f %.2f %s", event, def[1], vol, pitch, ok and "ok" or tostring(err)))
      h.close()
    end
  end
  return ok, err
end

--- Play an event after delayMs. Call pump() regularly (the main loop does).
function M.later(event, delayMs, volScale, pitchScale)
  pendingInsert({ at = nowMs() + delayMs, event = event, vol = volScale, pitch = pitchScale })
end

--- Play every scheduled sound that is due.
function M.pump()
  if #pending == 0 then return end
  local t = nowMs()
  while pending[1] and pending[1].at <= t do
    local item = table.remove(pending, 1)
    M.play(item.event, item.vol, item.pitch)
  end
end

function M.clear() pending = {} end

--- Named cues made of several events.
function M.cue(name)
  if name == "win" then
    M.play("win")
    M.later("winFanfare", 450)
    M.later("rank", 1100, 0.6)
  elseif name == "start" then
    M.play("start")
    M.later("tap", 400, 0.8, 0.8)
  elseif name == "achievement" then
    M.play("achievement")
    M.later("achievement", 180, 0.8, 1.3)
  else
    M.play(name)
  end
end

return M
