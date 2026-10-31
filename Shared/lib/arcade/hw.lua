-- arcade_hw.lua
-- Peripheral layer for the Arcade. Everything except the main monitor is optional and the Arcade
-- degrades quietly without it:
--   monitor         the board (largest monitor). A second monitor of the same size is a second wall, back to back with
--                   the first, so two players can each keep something hidden. Any other monitor is a live scoreboard.
--   speaker         sound (through arcade_audio / lib.sound)
--   playerDetector  who is nearby, and whether a player walked away mid-match
--   chatBox         results and turn reminders, whispered to the players in the match only
--   redstoneIntegrator / computer sides   turn lamps and a celebration output

local config = require("lib.arcade.constants")

local M = {}

local state = {
  monitor = nil, monitorName = nil, wall2 = nil, wall2Name = nil, scoreboard = nil, scoreboardName = nil,
  detector = nil, detectorName = nil, chat = nil, chatName = nil,
  redstone = nil, redstoneName = nil, speakerName = nil,
  nearbyAt = -1e9, nearbyDetected = {}, nearbyOk = false, positions = {},
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
  state.wall2, state.wall2Name = nil, nil
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
      -- measure at the scale we play at: a real monitor remembers the text scale of earlier programs
      if m and m.setTextScale then m.setTextScale(config.TEXT_SCALE) end
      local w, h = 0, 0
      if m and m.getSize then w, h = m.getSize() end
      monitors[#monitors + 1] = { name = name, obj = m, w = w, h = h, area = w * h }
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
  local mainW, mainH = 0, 0
  if state.monitor then mainW, mainH = state.monitor.getSize() end
  for _, m in ipairs(monitors) do
    if m.name ~= state.monitorName and m.name ~= boardName and not state.wall2 and m.w == mainW and m.h == mainH then
      state.wall2, state.wall2Name = m.obj, m.name
    end
  end
  for _, m in ipairs(monitors) do
    if m.name ~= state.monitorName and m.name ~= state.wall2Name then
      if (boardName and m.name == boardName) or (not boardName and not state.scoreboard) then
        state.scoreboard, state.scoreboardName = m.obj, m.name
      end
    end
  end
  return M.report()
end

function M.monitor() return state.monitor, state.monitorName end
function M.wall2() return state.wall2, state.wall2Name end
function M.scoreboard() return state.scoreboard, state.scoreboardName end
function M.speakerName() return state.speakerName end
function M.hasDetector() return state.detector ~= nil end
function M.hasChat() return state.chat ~= nil end

--- A summary of what is attached, for logs and the settings screen.
function M.report()
  return {
    monitor = state.monitorName, wall2 = state.wall2Name, scoreboard = state.scoreboardName, speaker = state.speakerName,
    detector = state.detectorName, chat = state.chatName,
    redstone = state.redstoneName or "computer",
  }
end

--- Remember who just touched the wall (from vhcc_touch), so a rig with no detector can still list them.
function M.noteToucher(name)
  state.toucher, state.touchedAt = name, nowMs()
end

--- Names of players near the detector, sorted. Cached for one second.
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
  for name in pairs(state.watched or {}) do
    local pos = state.detector and safe(state.detector.getPlayerPos, name)
    state.positions[name] = (type(pos) == "table" and type(pos.x) == "number") and pos or nil
  end
end

--- Follow where these players stand, for a game with hidden pieces. An empty list stops following.
function M.watch(names)
  local positions = {}
  state.watched = {}
  for _, name in ipairs(names or {}) do
    state.watched[name] = true
    positions[name] = state.positions[name]
  end
  state.positions = positions
end

--- Start following one more player: someone who has just tapped their name at a wall.
function M.follow(name)
  state.watched = state.watched or {}
  state.watched[name] = true
end

--- Where a followed player stood at the last poll: { x, y, z }, or nil.
function M.position(name) return state.positions[name] end

-- Returns the list (detector plus whoever touched lately), ok (a real detector answered), and the detector-only list.
-- Presence checks must use the detector-only list: a toucher stays listed for a while after walking away.
function M.nearby()
  local detected = state.nearbyDetected or {}
  local list = {}
  for _, n in ipairs(detected) do list[#list + 1] = n end
  local live = state.toucher
  if live and nowMs() - state.touchedAt <= config.TOUCH_NEARBY * 1000 then
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
-- Everything is a whisper to a named player: the Arcade never talks to the whole server.
local outbox = {}
local chatTag = "ARCADE"

--- The label on chat messages: the game being played.
function M.setChatTag(tag) chatTag = tag end

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
  local ok, res = pcall(state.chat.sendMessageToPlayer, item.message, item.player, chatTag)
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
    M.flushOutputs()
    pumpChat()
    os.sleep(0.25)
  end
end

-- The Arcade is free to play and moves no tokens. These read who owns the computer and lock its terminal, and they are
-- the only ccvault calls it makes.
local terminalLocked = false

--- Who owns this computer, or nil.
function M.hostName()
  if not ccvault then return nil end
  local ok, name = pcall(ccvault.getHostName)
  return ok and name or nil
end

--- Only the owner can lock a computer, and only while using it, so this tries on each of their touches until it holds.
function M.lockFor(who)
  if terminalLocked or not who or not ccvault or not ccvault.setTerminalLock then return end
  local known, locked = pcall(ccvault.isTerminalLocked)
  if known and locked then
    terminalLocked = true
  elseif who == M.hostName() then
    local ok, done = pcall(ccvault.setTerminalLock, true)
    terminalLocked = ok and done == true
  end
end

local rsEnabled = true

--- Turn the lamp and celebration outputs on or off as a feature (they are forced off when disabled).
function M.setRedstone(on) rsEnabled = on and true or false end

-- The integrator runs on the server thread like the detector, so its outputs wait here for M.worker.
local outputs = {}

--- Send waiting integrator outputs. Only call this from M.worker, or once the game loop has ended.
function M.flushOutputs()
  if not (state.redstone and state.redstone.setOutput) then return end
  for side, on in pairs(outputs) do
    outputs[side] = nil
    safe(state.redstone.setOutput, side, on)
  end
end

local function setOut(side, on)
  if not rsEnabled then on = false end
  if state.redstone and state.redstone.setOutput then
    outputs[side] = on and true or false
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
