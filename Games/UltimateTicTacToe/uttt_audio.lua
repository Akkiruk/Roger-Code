-- uttt_audio.lua
-- Sound events for Ultimate Tic-Tac-Toe on top of lib.sound. Events map to sounds the other games already
-- use (see uttt_config.SOUNDS); a small timeline lets one event play several sounds a little apart.

local config = require("uttt_config")
local sound = require("lib.sound")

local M = {}

local enabled = true
local volume = 1.0
local pending = {} -- { at = ms, event = name } sorted by time
local last = {}    -- event name -> last play time, to rate-limit

local function nowMs()
  return os.epoch("local")
end

function M.init(side)
  return sound.init(side)
end

function M.setEnabled(on) enabled = on and true or false end
function M.setVolume(v) volume = math.max(0, math.min(3, tonumber(v) or 1)) end
function M.isAvailable() return sound.isAvailable() end

--- Play an event now. Returns true if the speaker accepted it.
local lastAny = -1e9
local MIN_GAP_MS = 60 -- a speaker accepts one sound per game tick (50 ms); a second one in the same tick is refused

local function pendingInsert(item)
  pending[#pending + 1] = item
  table.sort(pending, function(a, b) return a.at < b.at end)
end

function M.play(event, volScale, pitchScale)
  if not enabled then return false end
  local def = config.SOUNDS[event]
  if not def then return false, "unknown sound event " .. tostring(event) end
  local t = nowMs()
  if t - lastAny < MIN_GAP_MS then
    -- too close to the previous sound: play it right after instead of losing it
    pendingInsert({ at = lastAny + MIN_GAP_MS, event = event, vol = volScale, pitch = pitchScale })
    return false, "deferred"
  end
  lastAny = t
  last[event] = t
  local vol = math.min(3, def[2] * volume * (volScale or 1))
  local pitch = math.max(0.5, math.min(2, def[3] * (pitchScale or 1)))
  local ok, err = sound.play(def[1], vol, pitch)
  if fs.exists("uttt_debug.flag") then
    local h = fs.open("uttt_sound.log", "a")
    if h then
      h.writeLine(string.format("%s %s %.2f %.2f %s", event, def[1], vol, pitch, ok and "ok" or tostring(err)))
      h.close()
    end
  end
  return ok, err
end

--- Play an event after delayMs. Call pump() regularly (the main loop does).
function M.later(event, delayMs, volScale, pitchScale)
  pending[#pending + 1] = { at = nowMs() + delayMs, event = event, vol = volScale, pitch = pitchScale }
  table.sort(pending, function(a, b) return a.at < b.at end)
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
function M.cue(name, player)
  if name == "move" then
    M.play(player == 2 and "placeBlue" or "placeRed")
  elseif name == "capture" then
    M.play(player == 2 and "captureBlue" or "captureRed")
    M.later("capture", 110, 0.6, player == 2 and 0.8 or 1.2)
  elseif name == "win" then
    M.play("win")
    M.later("winFanfare", 450)
    M.later("rank", 1100, 0.6)
  elseif name == "lose" then
    M.play("lose")
  elseif name == "draw" then
    M.play("draw")
  elseif name == "start" then
    M.play("start")
    M.later("tap", 400, 0.8, 0.8)
  elseif name == "forceFree" then
    M.play("freeMove")
  elseif name == "achievement" then
    M.play("achievement")
    M.later("achievement", 180, 0.8, 1.3)
  else
    M.play(name)
  end
end

return M
