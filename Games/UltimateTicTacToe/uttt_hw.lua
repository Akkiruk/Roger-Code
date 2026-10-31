-- uttt_hw.lua
-- Peripheral layer for Ultimate Tic-Tac-Toe. Everything except the main monitor is optional and the game
-- degrades quietly without it:
--   monitor         the board (largest monitor), a second monitor becomes a live scoreboard
--   speaker         sound (through uttt_audio / lib.sound)
--   playerDetector  who is nearby, and whether a player walked away mid-game
--   chatBox         result announcements and turn reminders
--   redstoneIntegrator / computer sides   turn lamps and a celebration output

local config = require("uttt_config")

local M = {}

local state = {
  monitor = nil, monitorName = nil, scoreboard = nil, scoreboardName = nil,
  detector = nil, detectorName = nil, chat = nil, chatName = nil,
  redstone = nil, redstoneName = nil, speakerName = nil,
  nearbyAt = -1e9, nearbyDetected = {}, nearbyOk = false,
}

local function nowMs() return os.epoch("local") end

local function safe(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil, a
end

local function typeOf(name)
  local t = peripheral.getType(name)
  return t
end

--- Discover peripherals. cfg may override names: monitor, scoreboard.
function M.init(cfg)
  cfg = cfg or {}
  state.monitor, state.monitorName, state.scoreboard, state.scoreboardName = nil, nil, nil, nil
  state.detector, state.detectorName, state.chat, state.chatName = nil, nil, nil, nil
  state.redstone, state.redstoneName, state.speakerName = nil, nil, nil
  state.nearbyAt = -1e9
  local names = peripheral.getNames()
  table.sort(names)

  local monitors = {}
  for _, name in ipairs(names) do
    local t = typeOf(name)
    if t == "monitor" then
      local m = peripheral.wrap(name)
      local w, h = 0, 0
      if m and m.getSize then w, h = m.getSize() end
      -- rank by physical size: a real monitor remembers the text scale of earlier programs, so characters alone mislead
      local scale = (m and m.getTextScale and m.getTextScale()) or 1
      monitors[#monitors + 1] = { name = name, obj = m, area = w * h * scale * scale }
    elseif t == "speaker" and not state.speakerName then
      state.speakerName = name
    elseif t == "playerDetector" and not state.detector then
      state.detector, state.detectorName = peripheral.wrap(name), name
    elseif t == "chatBox" and not state.chat then
      state.chat, state.chatName = peripheral.wrap(name), name
    elseif t == "redstoneIntegrator" and not state.redstone then
      state.redstone, state.redstoneName = peripheral.wrap(name), name
    end
  end

  table.sort(monitors, function(a, b)
    if a.area ~= b.area then return a.area > b.area end
    return a.name < b.name
  end)

  local mainName = cfg.monitor or config.MONITOR
  local boardName = cfg.scoreboard or config.SCOREBOARD
  for _, m in ipairs(monitors) do
    if mainName and m.name == mainName then state.monitor, state.monitorName = m.obj, m.name end
  end
  if not state.monitor and monitors[1] then
    state.monitor, state.monitorName = monitors[1].obj, monitors[1].name
  end
  for _, m in ipairs(monitors) do
    if m.name ~= state.monitorName then
      if (boardName and m.name == boardName) or (not boardName and not state.scoreboard) then
        state.scoreboard, state.scoreboardName = m.obj, m.name
      end
    end
  end
  return M.report()
end

function M.monitor() return state.monitor, state.monitorName end
function M.scoreboard() return state.scoreboard, state.scoreboardName end
function M.speakerName() return state.speakerName end
function M.hasDetector() return state.detector ~= nil end
function M.hasChat() return state.chat ~= nil end

--- A summary of what is attached, for logs and the settings screen.
function M.report()
  return {
    monitor = state.monitorName, scoreboard = state.scoreboardName, speaker = state.speakerName,
    detector = state.detectorName, chat = state.chatName,
    redstone = state.redstoneName or "computer",
  }
end

--- The player the server says is using this computer right now (CCVault), if that API exists.
function M.livePlayer()
  if type(ccvault) == "table" and type(ccvault.getPlayerName) == "function" then
    local name = safe(ccvault.getPlayerName)
    if type(name) == "string" and name ~= "" then return name end
  end
  return nil
end

--- Names of players near the detector, sorted. Cached for one second. Falls back to the CCVault player.
-- Detector and chat box methods run on the server thread: the caller waits a tick and every event that arrives
-- meanwhile is thrown away for that coroutine. Called from the game loop, that loses timers (stopping the game clock
-- for good) and touches. So only M.worker, a coroutine of its own, ever calls them; the game loop reads the results.
local function byName(a, b) return string.lower(a) < string.lower(b) end

--- Ask the detector who is near. Only call this from M.worker, or before the game loop starts.
function M.pollDetector()
  local detected, ok = {}, false
  if state.detector then
    local players = safe(state.detector.getPlayersInRange, config.DETECT_RANGE)
    if type(players) == "table" then
      ok = true
      for _, n in ipairs(players) do detected[#detected + 1] = n end
    end
  end
  table.sort(detected, byName)
  state.nearbyDetected, state.nearbyOk, state.nearbyAt = detected, ok, nowMs()
end

-- Returns the list (detector plus the CCVault player), ok (a real detector answered), and the detector-only list.
-- Presence checks must use the detector-only list: the CCVault player stays "live" after walking away.
function M.nearby()
  local detected = state.nearbyDetected or {}
  local list = {}
  for _, n in ipairs(detected) do list[#list + 1] = n end
  local live = M.livePlayer() -- ccvault runs on the computer thread, so this one is safe here
  if live then
    local have = false
    for _, n in ipairs(list) do if n == live then have = true end end
    if not have then list[#list + 1] = live end
  end
  table.sort(list, byName)
  return list, state.nearbyOk, detected
end

function M.isNear(name)
  local _, ok, detected = M.nearby()
  if not ok then return true end -- cannot tell, so do not accuse anyone of leaving
  for _, n in ipairs(detected) do
    if n == name then return true end
  end
  return false
end

-- The chat box has a cooldown between messages, so messages queue up and go out one at a time.
local outbox = {}
local nextChatAt = 0
local CHAT_GAP_MS = 1100
local OUTBOX_LIMIT = 8

local function enqueue(item)
  if not state.chat then return false end
  if #outbox >= OUTBOX_LIMIT then table.remove(outbox, 1) end
  outbox[#outbox + 1] = item
  return true
end

--- Whisper to one player (queued).
function M.tell(player, message)
  if not player then return false end
  return enqueue({ message = message, player = player })
end

--- Send the next queued chat message when the cooldown allows.
local function pumpChat()
  if #outbox == 0 or not state.chat then return end
  local t = nowMs()
  if t < nextChatAt then return end
  local item = outbox[1]
  local ok, res
  if item.player then
    ok, res = pcall(state.chat.sendMessageToPlayer, item.message, item.player, "UTTT")
  else
    ok, res = pcall(state.chat.sendMessage, item.message, "UTTT")
  end
  if ok and not res then
    -- the box refused (cooldown or unknown player); try again shortly, but not forever
    item.tries = (item.tries or 0) + 1
    if item.tries >= 3 then table.remove(outbox, 1) end
    nextChatAt = t + CHAT_GAP_MS
    return
  end
  table.remove(outbox, 1)
  nextChatAt = t + CHAT_GAP_MS
end

function M.pending() return #outbox end

--- Background coroutine, run beside the game loop with parallel: polls the detector and sends chat. Never returns.
function M.worker()
  while true do
    if nowMs() - state.nearbyAt >= 1000 then M.pollDetector() end
    pumpChat()
    os.sleep(0.25)
  end
end

local rsEnabled = true

--- Turn the lamp and celebration outputs on or off as a feature (they are forced off when disabled).
function M.setRedstone(on) rsEnabled = on and true or false end

local function setOut(side, on)
  if not rsEnabled then on = false end
  if state.redstone and state.redstone.setOutput then
    safe(state.redstone.setOutput, side, on and true or false)
  elseif redstone and redstone.setOutput then
    safe(redstone.setOutput, side, on and true or false)
  end
end

--- Turn lamps: which side's lamp is lit.
function M.lamps(redOn, blueOn)
  setOut(config.REDSTONE.red, redOn)
  setOut(config.REDSTONE.blue, blueOn)
end

--- Celebration output (fireworks, note blocks, lamps...). Switch it off again with M.celebrate(false).
function M.celebrate(on)
  setOut(config.REDSTONE.celebrate, on)
end

function M.allOff()
  M.lamps(false, false)
  M.celebrate(false)
end

return M
