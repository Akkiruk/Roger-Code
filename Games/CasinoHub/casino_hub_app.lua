-- casino_hub_app.lua
-- The hub's computer: listens to the floor, keeps the books on disk, and tells every table where things stand.
-- It moves no tokens. A monitor is optional, and with none it prints a short summary to its own screen.
-- Its wall is a display for everyone but the owner, whose touch locks it like any table and opens the tournament menu.
-- It also hears the Arcade's results, for one page of the wall, and a jackpot from any table lights its own lamp (lamps.lua).
-- A contest moves no tokens. Its rules are casino_hub_contest.lua; a chat box, if there is one, whispers the top three.

local board = require("lib.casino.board")
local canvas = require("lib.casino.canvas")
local chat = require("lib.casino.chat")
local journal = require("lib.casino.journal")
local lamps = require("lib.casino.lamps")
local net = require("lib.casino.net")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local wallet = require("lib.casino.wallet")
local contest = require("casino_hub_contest")
local contestView = require("casino_hub_contest_view")
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

--- The wall and its name, and the scoreboard if there is a smaller monitor.
local function attach()
  local name = board.largest()
  if not name then return nil end
  local monitor = peripheral.wrap(name)
  monitor.setTextScale(TEXT_SCALE)
  theme.apply(monitor, FELT)
  return canvas.new(monitor), name, board.attach(name, FELT)
end

--- The scoreboard's view of the floor. Returns false once its monitor has gone.
local function showBoard(scoreboard, data, at)
  local live = 0
  for _, entry in ipairs(rules.tables(data, at)) do
    if entry.live then live = live + 1 end
  end
  return board.show(scoreboard, {
    title = "CASINO HUB",
    leaders = rules.leaders(data, board.ROWS),
    jackpot = data.jackpot,
    note = live .. (live == 1 and " table live" or " tables live"),
  })
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

local function writeDebug(c, data, page, at, menu)
  local handle = fs.open("casino_ui.dat", "w")
  if not handle then return end
  local buttons = {}
  for _, b in ipairs(menu and menu.buttons or {}) do
    buttons[#buttons + 1] = { id = b.id, value = b.value, x = b.x, y = b.y, w = b.w, h = b.h, label = b.label }
  end
  handle.write(textutils.serializeJSON({
    scene = "hub",
    buttons = buttons,
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
      arcade = data.arcade,
      games = rules.games(data),
      tables = rules.tables(data, at),
      totals = rules.totals(data),
      menu = menu and menu.step or false,
      contest = contest.broadcast(data.contest, at) or false,
      past = data.contest.past,
      champions = rules.champions(data),
    },
  }))
  handle.close()
end

--- The hub's own loop: everything but the lamp.
local function floor()
  local online = net.open()
  local data = rules.restore(journal.loadKeep())
  local c, wall, scoreboard = attach()
  local debug = fs.exists("casino_debug.flag")
  local page, started = 1, now()
  local nextPage, nextState, nextSave, nextBeat, nextPrint, nextBoard = 0, 0, 0, 0, 0, 0
  local dirty = false
  local toucher = nil
  local menu = nil        -- the owner's tournament menu, when it is open
  local back = nil        -- the page to go on from once the tournament's has had its turn
  local frame = os.startTimer(FRAME)

  local function announce()
    net.send("state", rules.state(data))
    local message = contest.broadcast(data.contest, now())
    if message then net.send("contest", message) end
  end

  --- A touch on the wall. It only means something from the owner, by the name vhcc_touch gave.
  local function touchWall(x, y, who, at)
    if not who or who ~= wallet.hostName() then return end
    if not menu then
      menu = contestView.openMenu(data.contest, at)
      return
    end
    local changed
    menu, changed = contestView.touch(menu, ui.hit(menu.buttons or {}, x, y), data.contest, who, at)
    if changed then
      journal.saveKeep(data)
      dirty = false
      announce()
    end
  end

  --- The contest's grace is over: on disk first, so a reboot cannot whisper the result twice.
  local function closeContest(at)
    local record = contest.tick(data.contest, at)
    if not record then return end
    journal.saveKeep(data)
    dirty = false
    announce()
    for _, line in ipairs(contest.whispers(record, rules.gameName(record.game))) do chat.tell(line.player, line.text) end
  end

  if debug then writeDebug(c, data, page, now()) end

  while true do
    local event, a, b, protocol = os.pullEvent()
    if event == "rednet_message" and protocol == net.PROTOCOL then
      local changed, grant = rules.apply(data, a, b, now())
      dirty = dirty or changed
      if changed and b.kind == "jackpot" then lamps.pulse("jackpot") end
      if grant then
        -- The pool has moved: nothing may answer another claim from an older copy, so this goes to disk first
        journal.saveKeep(data)
        dirty = false
        net.send("grant", grant)
        announce()
      end
    elseif event == "rednet_message" and protocol == rules.ARCADE_PROTOCOL then
      dirty = rules.arcadeResult(data, b, now()) or dirty
    elseif event == "vhcc_touch" then
      toucher = a
    elseif event == "monitor_touch" then
      -- The scoreboard is display only, and its touch still has to clear who touched
      if a == wall then
        wallet.lockIfOwner(toucher or wallet.livePlayer())
        touchWall(b, protocol, toucher, now())
      end
      toucher = nil
    elseif event == "monitor_resize" or event == "peripheral" or event == "peripheral_detach" then
      c, wall, scoreboard = attach()
      nextBoard = 0
      online = net.open()
      lamps.rescan()
      chat.scan()
    elseif event == "timer" and a == frame then
      local at = now()
      if at >= nextPage then
        if nextPage > 0 then page, back = contestView.turn(page, back, #view.PAGES, contest.showing(data.contest, at)) end
        nextPage = at + PAGE_MS
      end
      closeContest(at)
      if menu and at >= menu.deadline then menu = nil end
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
      if c and menu then
        contestView.drawMenu(c, menu, data.contest, at)
        c:flush()
      elseif c then
        local note = not online and "No modem: no tables can be heard" or (wallet.wantsLock() and LOCK_NOTICE) or nil
        view.draw(c, data, page, (at - started) / 1000, at, note)
        c:flush()
      elseif at >= nextPrint then
        nextPrint = at + PRINT_MS
        printSummary(data, online)
      end
      if scoreboard and at >= nextBoard then
        nextBoard = at + board.REFRESH_MS
        if not showBoard(scoreboard, data, at) then scoreboard = nil end
      end
      if debug then writeDebug(c, data, page, at, menu) end
      frame = os.startTimer(FRAME)
    end
  end
end

--- Run the hub for ever.
function M.run()
  chat.scan()
  parallel.waitForAny(floor, lamps.worker, chat.worker)
end

return M
