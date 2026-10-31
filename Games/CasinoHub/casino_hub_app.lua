-- casino_hub_app.lua
-- The hub's computer: listens to the floor, keeps the books on disk, and tells every table where things stand.
-- It moves no tokens. A monitor is optional, and with none it prints a short summary to its own screen.
-- Its wall takes no input, but a hub is a computer with the host's name on it like any table: the owner's touch locks it.

local canvas = require("lib.casino.canvas")
local journal = require("lib.casino.journal")
local net = require("lib.casino.net")
local theme = require("lib.casino.theme")
local wallet = require("lib.casino.wallet")
local rules = require("casino_hub_rules")
local view = require("casino_hub_view")

local M = {}

local FELT = "purple"
local FRAME = 0.5
local PAGE_MS = 8000
local SAVE_MS = 5000
local BEAT_MS = 5000
local PRINT_MS = 10000
local TEXT_SCALE = 0.5
local LOCK_NOTICE = "Owner: tap to lock this hub"

local function now()
  return os.epoch("utc")
end

local function largestMonitor()
  local best, bestArea = nil, 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "monitor") then
      local monitor = peripheral.wrap(name)
      monitor.setTextScale(TEXT_SCALE)
      local w, h = monitor.getSize()
      if w * h > bestArea then best, bestArea = name, w * h end
    end
  end
  return best
end

local function attach()
  local name = largestMonitor()
  if not name then return nil end
  local monitor = peripheral.wrap(name)
  monitor.setTextScale(TEXT_SCALE)
  theme.apply(monitor, FELT)
  return canvas.new(monitor)
end

local function printSummary(data, online)
  term.clear()
  term.setCursorPos(1, 1)
  print("Casino Hub")
  print(online and "Listening on rednet" or "No modem: add one to hear the tables")
  print("")
  local totals = rules.totals(data)
  print("Jackpot: " .. data.jackpot)
  print("Rounds:  " .. totals.rounds)
  print("Wagered: " .. totals.wagered)
  print("Players: " .. totals.players)
end

local function writeDebug(c, data, page, at)
  local handle = fs.open("casino_ui.dat", "w")
  if not handle then return end
  handle.write(textutils.serializeJSON({
    scene = "hub",
    buttons = {},
    seat = false,
    balance = false,
    playing = false,
    w = c and c.w or 0,
    h = c and c.h or 0,
    toast = false,
    locked = wallet.terminalLocked() == true,
    state = {
      page = page,
      jackpot = data.jackpot,
      paid = data.jackpotsPaid,
      leaders = rules.leaders(data, rules.TOP),
      biggest = data.biggest,
      latest = data.latest,
      games = rules.games(data),
      tables = rules.tables(data, at),
      totals = rules.totals(data),
    },
  }))
  handle.close()
end

--- Run the hub for ever.
function M.run()
  local online = net.open()
  local data = rules.restore(journal.loadKeep())
  local c = attach()
  local debug = fs.exists("casino_debug.flag")
  local page, started = 1, now()
  local nextPage, nextState, nextSave, nextBeat, nextPrint = 0, 0, 0, 0, 0
  local dirty = false
  local toucher = nil
  local frame = os.startTimer(FRAME)

  local function announce()
    net.send("state", rules.state(data))
  end

  if debug then writeDebug(c, data, page, now()) end

  while true do
    local event, a, b, protocol = os.pullEvent()
    if event == "rednet_message" and protocol == net.PROTOCOL then
      local changed, grant = rules.apply(data, a, b, now())
      dirty = dirty or changed
      if grant then
        -- The pool has moved: nothing may answer another claim from an older copy, so this goes to disk first
        journal.saveKeep(data)
        dirty = false
        net.send("grant", grant)
        announce()
      end
    elseif event == "vhcc_touch" then
      toucher = a
    elseif event == "monitor_touch" then
      wallet.lockIfOwner(toucher or wallet.livePlayer())
      toucher = nil
    elseif event == "monitor_resize" or event == "peripheral" or event == "peripheral_detach" then
      c = attach()
      online = net.open()
    elseif event == "timer" and a == frame then
      local at = now()
      if at >= nextPage then
        if nextPage > 0 then page = page % #view.PAGES + 1 end
        nextPage = at + PAGE_MS
      end
      if at >= nextState then
        nextState = at + rules.STATE_MS
        announce()
      end
      if dirty and at >= nextSave then
        nextSave = at + SAVE_MS
        journal.saveKeep(data)
        dirty = false
      end
      if at >= nextBeat then
        nextBeat = at + BEAT_MS
        -- The supervisor reboots a game with a silent monitor. Nobody touches this one, so it says it is alive
        os.queueEvent("roger_alive")
      end
      if c then
        local note = not online and "No modem: no tables can be heard" or (wallet.wantsLock() and LOCK_NOTICE) or nil
        view.draw(c, data, page, (at - started) / 1000, at, note)
        c:flush()
      elseif at >= nextPrint then
        nextPrint = at + PRINT_MS
        printSummary(data, online)
      end
      if debug then writeDebug(c, data, page, at) end
      frame = os.startTimer(FRAME)
    end
  end
end

return M
