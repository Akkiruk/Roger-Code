-- pokertable_app.lua
-- Five-card draw for up to six players at one computer and one 6x6 wall. Each touch names its player through vhcc_touch.
-- This is not table.lua's one-seat loop, but it is built the same way: scenes, a journal, money that moves once.
--
-- Chips are declared, not taken. A buy-in is checked against the player's balance when they sit and top up, and again
-- before each deal, and no tokens move until a hand ends.
--
-- How a hand's money moves. The host only ever passes tokens through, so it cannot lose more than rounding, which is none:
--   1. Each player's net for the hand is written to the owed book. The nets add up to zero, so the book adds up to
--      what the host holds for players, and that is zero or more at every step.
--   2. Collect from each loser, by name, taking what they have. A transfer needs a touch within 30 seconds, so a player
--      who folded long ago usually fails here. What cannot move stays owed.
--   3. Pay winners from what was collected, biggest first, never more than the host holds. A winner who misses out
--      keeps the rest owed, and it is paid once the loser has paid. A loser's failure never costs the host.
-- Any later touch by someone in the book tries again. A seated player keeps playing with what their balance covers after
-- the debt; someone who has left must clear it before they can sit again.
-- rules.settle holds that order; Tests/pokertable_test.lua proves the host never goes below even, whatever fails.
--
-- Every transfer is written down first with a unique tag, so a reboot can tell whether it happened (see lib/casino/books.lua).
--
-- With a chat box each player is whispered their own hand as it is dealt and after they draw, and never anyone else's.
-- PEEK stays either way: a whisper can fail, a table may have no chat box, and tapping the peek is how cards are thrown.
-- The other extras are table.lua's: a scoreboard on a smaller monitor, a session summary as a player goes, win lamps.

local audio = require("lib.casino.audio")
local board = require("lib.casino.board")
local books = require("lib.casino.books")
local canvas = require("lib.casino.canvas")
local chat = require("lib.casino.chat")
local demo = require("lib.casino.demo")
local journal = require("lib.casino.journal")
local lamps = require("lib.casino.lamps")
local net = require("lib.casino.net")
local rng = require("lib.casino.rng")
local session = require("lib.casino.session")
local stats = require("lib.casino.stats")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local wallet = require("lib.casino.wallet")
local rules = require("pokertable_rules")
local view = require("pokertable_view")

local C = theme.C
local M = {}

local GAME_ID = "pokertable"
local TITLE = "POKER"
local FELT = "green"
local FRAME = 0.1
local TURN_MS = 45000
local WARN_MS = 10000
local PEEK_MS = 6000
local LOBBY_MS = 15000
local RESULT_MS = 15000
local BUYIN_MS = 30000
local APPROVE_MS = 60000
local APPROVE_RETRY_MS = 20000
local AWAY_LIMIT = 2             -- hands in a row a player can time out before losing their seat
local CHIPS = { 100, 250, 500, 1000, 2500 }
local HASH_SHOWN = 16            -- how much of a hash the table shows while it plays. FAIR has the whole of it
local BIG_WIN_TIMES = 10         -- a win this many times what went in lights the lamps
local LOCK_NOTICE = "Owner: tap to lock this table"
local FAREWELL_MS = 6000         -- how long the lobby shows a session's summary
local SESSION_STALE_MS = 120000  -- a visit with no seat, which only a reboot can leave behind, ends here
local DEMO_SEATS = { 1, 3, 5 }
local DEMO_NAMES = { "Demo Ann", "Demo Bea", "Demo Cy" }
local DEMO_STACK = 200

local log = journal.log

local function now()
  return os.epoch("utc")
end

local App = {}
App.__index = App

-- ------------------------------------------------------------------ the event loop

--- Run a scene until it says it is finished. touch(self, x, y, who) always gets a name, or nil when nobody can be told.
function App:run(scene)
  local previous = self.scene
  self.scene = scene
  scene.dirty = true
  -- Always a new one: a scene opened from a tick starts after the current timer has already fired
  self.timer = os.startTimer(FRAME)
  local last = now()
  while not scene.finished do
    local event, a, b, c = os.pullEvent()
    if event == "vhcc_touch" then
      self.toucher = a
    elseif event == "monitor_touch" and a == self.monitorName then
      local who = self.toucher or wallet.livePlayer()
      self.toucher = nil
      if wallet.lockIfOwner(who) then self.wantsLock = false end
      if who then self:touched(who) end
      if scene.touch then
        scene:touch(b, c, who)
        scene.dirty = true
      end
      -- A wallet call can swallow the frame timer while it waits, so always start another
      self.timer = os.startTimer(FRAME)
    elseif event == "monitor_resize" and a == self.monitorName then
      self:attachCanvas()
      scene.dirty = true
    elseif event == "monitor_resize" and a == self.boardName then
      self:attachBoard()
    elseif event == "peripheral" or event == "peripheral_detach" then
      -- A speaker, a modem, a chat box or a scoreboard added after boot is picked up here
      audio.init()
      net.open()
      chat.scan()
      lamps.rescan()
      self:attachBoard()
    elseif event == "timer" and a == self.timer then
      local time = now()
      local dt = (time - last) / 1000
      last = time
      if scene.tick then scene:tick(dt) end
      self:heartbeat(time)
      if self.toastUntil and time > self.toastUntil then
        self.toastUntil, self.toastText = nil, nil
        scene.dirty = true
      end
      if scene.dirty or scene.animating then
        scene.dirty = false
        scene:draw()
        self:drawToast()
        self.c:flush()
        if self.debug then self:writeDebug(scene) end
      end
      self.timer = os.startTimer(FRAME)
    end
  end
  self.scene = previous
  if previous then previous.dirty = true end
end

function App:heartbeat(time)
  if time - (self.lastBeat or 0) > 5000 then
    self.lastBeat = time
    os.queueEvent("roger_alive")
    os.queueEvent("roger_busy", #self:seatedNames() > 0) -- an update waits until the table is empty
    net.tick()
    self.wantsLock = wallet.wantsLock()
    self:closeStale(time)
    self:drawBoard()
  end
end

--- With casino_debug.flag on the computer, write what is on screen for the test suites to read.
function App:writeDebug(scene)
  local buttons = {}
  for _, b in ipairs(scene.buttons or {}) do
    buttons[#buttons + 1] = { id = b.id, value = b.value, x = b.x, y = b.y, w = b.w, h = b.h, label = b.label }
  end
  local handle = fs.open("casino_ui.dat", "w")
  if handle then
    handle.write(textutils.serializeJSON({
      scene = scene.name or "?",
      buttons = buttons,
      seat = false,
      balance = false,
      playing = scene.playing ~= nil or (scene.queue ~= nil and #scene.queue > 0),
      w = self.c.w,
      h = self.c.h,
      toast = self.toastText or false,
      locked = wallet.terminalLocked() == true,
      state = scene.debugState and scene.debugState() or false,
      board = self.boardName or false,
    }))
    handle.close()
  end
end

function App:toast(text)
  self.toastText = text
  self.toastUntil = now() + 2500
  audio.play("error")
  if self.scene then self.scene.dirty = true end
end

function App:drawToast()
  if not self.toastText then return end
  local c = self.c
  local w = #self.toastText + 4
  local x = math.floor((c.w - w) / 2)
  c:rect(x, 40, w, 3, C.orange)
  c:text(x + 2, 41, self.toastText, C.ink, C.orange)
end

function App:attachCanvas()
  self.monitor = peripheral.wrap(self.monitorName)
  self.monitor.setTextScale(0.5)
  theme.apply(self.monitor, FELT)
  if self.c then self.c:attach(self.monitor) else self.c = canvas.new(self.monitor) end
end

--- Find the scoreboard, if there is one now. board.find measures every monitor, so this only runs when something changes.
function App:attachBoard()
  self.board = board.attach(self.monitorName, FELT)
  self.boardName = self.board and self.board.name or nil
  self:drawBoard()
end

--- A heartbeat's work, so a scoreboard costs the table nothing it would notice. The leaders are read again only after a hand.
function App:drawBoard()
  if not self.board then return end
  self.leaders = self.leaders or stats.leaders(board.ROWS)
  local hub = net.hub()
  local shown = board.show(self.board, {
    title = TITLE,
    leaders = self.leaders,
    jackpot = hub and hub.jackpot or nil,
    playing = self:seatedNames(),
  })
  if not shown then self.board, self.boardName = nil, nil end
end

--- The end of a visit: what it came to on the wall and in a whisper, and anything still in the book.
function App:leaving(name)
  session.noteOwed(name, TITLE)
  local entry = session.close(name)
  self:drawBoard()
  if not entry then return end
  local text = session.text(entry)
  self.farewell = { text = view.short(name) .. ": " .. text, untilAt = now() + FAREWELL_MS }
  chat.tell(name, "Your session at " .. TITLE .. ": " .. text)
end

--- A reboot can lose a seat's visit its ending. If nobody is sitting in it, it is closed here.
function App:closeStale(time)
  for name, at in pairs(session.open()) do
    if time - at > SESSION_STALE_MS and not self:seatOf(name) then self:leaving(name) end
  end
end

function App:topBar()
  local c = self.c
  ui.bar(c, self.ctx)
  local text = ("Ante %d   Bets %d/%d"):format(rules.ANTE, rules.SMALL, rules.BIG)
  c:text(c.w - #text - 2, 3, text, C.text)
  local hub = net.hub()
  local hands = "Hand " .. ui.group(self.keep.hands or 0)
  c:text(c.w - #hands - 2, 5, hands, hub and C.win or C.mute)
end

-- ------------------------------------------------------------------ seats

function App:seats()
  self.keep.seats = self.keep.seats or {}
  return self.keep.seats
end

--- A player's seat number and record, or nil.
function App:seatOf(name)
  local seats = self:seats()
  for index = 1, rules.MAX_SEATS do
    local seat = seats[index]
    if seat and seat.name == name then return index, seat end
  end
  return nil
end

function App:seatedNames()
  local seats, names = self:seats(), {}
  for index = 1, rules.MAX_SEATS do
    if seats[index] then names[#names + 1] = seats[index].name end
  end
  return names
end

--- A seat can be dealt in when it has the ante. A debt from the last hand does not stop that: most debts are just a
-- player who folded and has not touched the table since, and openHand holds their stack to what their balance covers
-- after the debt. Stopping them would stall the table, and they could never time out of their seat.
function App:canPlay(seat)
  return seat.stack >= rules.ANTE
end

function App:readyCount()
  local seats, total = self:seats(), 0
  for index = 1, rules.MAX_SEATS do
    if seats[index] and self:canPlay(seats[index]) then total = total + 1 end
  end
  return total
end

function App:save()
  journal.saveKeep(self.keep)
end

-- ------------------------------------------------------------------ money

--- One transfer of what the book already says. books.move writes it down first, so a reboot in the middle can tell whether it
-- happened, and takes what moved off the book. amount: tokens to the player when positive, from them when negative.
-- Returns what moved.
function App:move(name, amount)
  self.seq = (self.seq or 0) + 1
  local tag = ("Poker #%x.%d."):format(now() % 268435456, self.seq)
  local moved, _, err = books.move(name, amount, tag)
  if moved ~= amount then log("move " .. tag .. " " .. name .. " wanted " .. amount .. " moved " .. moved .. ": " .. tostring(err)) end
  return moved
end

--- Collect and pay what the book says, for these players. See the top of this file for the order.
function App:settleFor(names)
  rules.settle(journal.owed(), names, function(name, amount) return self:move(name, amount) end)
end

--- Any touch by a player proves they are here, so it is the moment to retry what they could not settle.
function App:touched(who)
  if self:seatOf(who) and not wallet.isApproved() then
    local time = now()
    self.asked = self.asked or {}
    if time - (self.asked[who] or 0) > APPROVE_RETRY_MS then
      self.asked[who] = time
      wallet.requestApproval()
    end
  end
  if wallet.isApproved() then books.resolve(who) end
  if journal.owedTo(who) ~= 0 and wallet.isApproved() then
    local names = self:seatedNames()
    if not self:seatOf(who) then names[#names + 1] = who end
    local before = {}
    for _, name in ipairs(names) do before[name] = journal.owedTo(name) end
    self:settleFor(names)
    for name, owed in pairs(before) do
      local left = journal.owedTo(name)
      if left ~= owed then session.noteMoved(name, owed - left, left, TITLE) end
    end
    if self.scene then self.scene.dirty = true end
  end
end

--- Close a hand's books: the only place a hand changes anyone's chips or tokens.
function App:closeHand(round)
  round.nets = rules.nets(round.state)
  round.phase = "settling"
  journal.saveRound(round)
  self:book(round)
  self:finishBooks(round)
end

--- Write each net to the owed book. The tag holds the hand and the name, so a reboot cannot book one twice.
function App:book(round)
  for name, amount in pairs(round.nets) do
    journal.book(name, amount, "hand " .. round.id .. " " .. name)
  end
  round.phase = "booked"
  journal.saveRound(round)
end

--- Everything after the book. Each step can run again after a reboot and do nothing.
function App:finishBooks(round)
  local names, dropped = {}, {}
  local closed = self.keep.closed == round.id
  for _, player in ipairs(round.state.players) do
    names[#names + 1] = player.name
    local index, seat = self:seatOf(player.name)
    if seat and not closed then
      seat.stack = player.start + player.net
      seat.away = round.timedOut[player.name] and (seat.away or 0) + 1 or 0
      if seat.away >= AWAY_LIMIT then
        self:seats()[index] = nil
        dropped[#dropped + 1] = player.name
        log("dropped " .. player.name .. " after " .. seat.away .. " hands away")
      end
    end
  end
  -- The seats and the note that they are done land in one write of keep
  self.keep.closed = round.id
  self:save()

  self:settleFor(names)

  for _, player in ipairs(round.state.players) do
    stats.record(player.name, player.total, player.net, round.id .. player.name)
    session.record(player.name, player.net, round.id .. player.name)
  end
  self.leaders = nil
  -- Noted before it is said. A crash in that gap loses a line on the hub, which is better than saying it twice
  if not round.told then
    round.told = true
    journal.saveRound(round)
    for _, player in ipairs(round.state.players) do
      net.send("round", { game = GAME_ID, player = player.name, wagered = player.total, net = player.net })
      log(("hand %s %s in=%d net=%d owed=%d seed=%s"):format(round.id, player.name, player.total, player.net,
        journal.owedTo(player.name), round.seed))
    end
  end
  -- A timed-out turn means they are not at the table to read the wall, and neither is someone who has lost their seat
  for _, player in ipairs(round.state.players) do
    if round.timedOut[player.name] or not self:seatOf(player.name) then session.noteOwed(player.name, TITLE) end
  end
  for _, name in ipairs(dropped) do self:leaving(name) end
  journal.clearRound()
end

--- What the book still says, in words.
function App:owedLine()
  local owed = journal.owed()
  local parts = {}
  for name, amount in pairs(owed) do
    parts[#parts + 1] = amount < 0 and (view.short(name) .. " owes " .. ui.group(-amount))
      or (view.short(name) .. " is owed " .. ui.group(amount))
  end
  if #parts == 0 then return nil end
  table.sort(parts)
  return table.concat(parts, "   ") .. "   (touch the table)"
end

--- Anything a reboot interrupted. Returns a hand to carry on with, if there is one.
function App:recover()
  local keep = self.keep
  -- From before the book held its own moves: a table updated while one was under way
  local moving = keep.moving
  if moving then
    if journal.owedTo(moving.name) == moving.owed and wallet.wasSettled(moving.tag) then
      journal.addOwed(moving.name, -moving.amount)
      log("recovered transfer " .. moving.tag)
    end
    keep.moving = nil
    self:save()
  end
  books.resolve()
  local round = journal.loadRound()
  if not round then return nil end
  log("resuming hand " .. tostring(round.id) .. " phase " .. tostring(round.phase))
  if round.phase == "open" then return round end
  if round.phase == "settling" then self:book(round) end
  self:finishBooks(round)
  return nil
end

-- ------------------------------------------------------------------ the show

local function eventTiming(ev)
  if ev.type == "deal" then return 1.4, "deal" end
  if ev.type == "street" then return 0.6, "flip" end
  if ev.type == "chips" then return 0.25, ev.amount >= 50 and "chipBig" or "chip" end
  if ev.type == "draw" then return 0.45, "deal" end
  if ev.type == "showdown" then return 0.5, "flip" end
  return 0.1, nil
end

--- An empty table plays itself: three made-up players through the real rules and the real table, for nothing. None of this
-- reaches keep, the journal, a seat or a wallet. The cards stay backs, as they do for anyone watching a real hand.
local function demoScript()
  local function pick(state, stream)
    if state.phase == "draw" then
      local digits = ""
      for position = 1, rules.HAND_SIZE do
        if #digits < rules.MAX_DISCARD and stream:below(3) == 0 then digits = digits .. position end
      end
      return "draw" .. digits
    end
    local list = rules.actions(state)
    local choice = list[stream:below(#list) + 1].id
    -- Folding what is free would end the show early
    if choice == "fold" and rules.toCall(state) == 0 then return "check" end
    return choice
  end

  return {
    start = function(stream)
      local entries = {}
      for i, seat in ipairs(DEMO_SEATS) do entries[i] = { name = DEMO_NAMES[i], seat = seat, stack = DEMO_STACK } end
      return rules.new(entries, stream:below(#entries) + 1, stream)
    end,
    act = function(state, stream) return rules.act(state, pick(state, stream)) end,
    done = rules.done,
    model = function() return {} end,
    sync = function() end,
    event = function(_, ev) return (eventTiming(ev)) end,
    commit = function() end,
  }
end

--- The demo in the lobby. A demo's player holds no seat: tapping one sits you there, on the same spot as the SIT it covers.
-- Returns false if it failed, so the lobby can carry on without it.
function App:drawDemo(buttons, show)
  local c = self.c
  local ok, err = pcall(function()
    view.table(c, show.state, show.playing)
    self:topBar()
    view.centre(c, show.state, show.playing)
    local taken = {}
    for _, player in ipairs(show.state.players) do taken[player.seat] = true end
    for seat = 1, rules.MAX_SEATS do
      if taken[seat] then
        local x, y, w, h = view.sitSpot(c, seat)
        buttons[#buttons + 1] = { id = "sit", value = seat, x = x, y = y, w = w, h = h }
      else
        view.emptySeat(c, buttons, seat, true)
      end
    end
  end)
  if not ok then log("demo draw failed: " .. tostring(err)) end
  return ok
end

-- ------------------------------------------------------------------ pages

--- A page of small text: the rules, or the fairness proof.
function App:page(title, lines)
  local c = self.c
  local scene = { name = "page", deadline = now() + BUYIN_MS }
  local wrapped = {}
  for _, line in ipairs(lines) do
    local text = type(line) == "table" and line[1] or line
    local color = type(line) == "table" and line[2] or C.text
    if text == "" then
      wrapped[#wrapped + 1] = { "", color }
    else
      for _, part in ipairs(ui.wrap(text, c.w - 10)) do wrapped[#wrapped + 1] = { part, color } end
    end
  end
  -- What the lines leave of the room above the buttons goes between the paragraphs
  local top = ui.BAR_H + 10
  local breaks = 0
  for _, line in ipairs(wrapped) do
    if line[1] == "" then breaks = breaks + 1 end
  end
  local spare = c.h - ui.ACTIONS_H - top - #wrapped
  local air = breaks > 0 and math.max(0, math.min(3, math.floor(spare / breaks))) or 0

  function scene.tick(s)
    if now() > s.deadline then s.finished = true end
  end

  function scene.draw(s)
    c:clear(C.felt)
    c:frame(1, 1, c.w, c.h, C.feltDark)
    self:topBar()
    c:big(5, ui.BAR_H + 2, title, C.gold, 1)
    local y = top
    for _, line in ipairs(wrapped) do
      c:text(6, y, line[1], line[2])
      y = y + (line[1] == "" and air + 1 or 1)
    end
    s.buttons = ui.newButtons()
    ui.actionBar(c, s.buttons, { { id = "close", label = "DONE", color = C.win, textColor = C.ink } })
  end

  function scene.touch(s, x, y)
    local hit = ui.hit(s.buttons or {}, x, y)
    if hit then
      audio.play("tap")
      s.finished = true
    end
  end

  self:run(scene)
end

local function helpLines()
  return {
    ("Everyone antes %d and gets five cards. There is a round of betting at %d, one draw, then a round at %d."):format(
      rules.ANTE, rules.SMALL, rules.BIG),
    ("Each round allows a bet and %d raises. The best hand at the showdown wins, and the button moves one seat each hand."):format(
      rules.MAX_BETS - 1),
    "",
    { "YOUR CARDS", C.gold },
    chat.available() and "This table whispers you your hand in chat when it is dealt and after you draw. Only you can read it."
      or "Keep your cards to yourself: nobody else's touch can show them.",
    "Tap PEEK to see your own hand for a few seconds. Only your touch shows it, and anyone else's touch flips it back.",
    ("In the draw, peek and tap the cards to throw: up to %d, or %d if the card you keep is an ace."):format(
      rules.MAX_DISCARD, rules.MAX_DISCARD_ACE),
    "",
    { "YOUR CHIPS", C.gold },
    ("Declare a buy-in of %d or more when you sit. It must be in your wallet, and nothing is taken."):format(rules.MIN_BUY),
    "Tokens move only when a hand ends, and only your result for that hand. Keep touching the table: the bank needs a touch from you in the last 30 seconds.",
    "A result that cannot move is written down and settled the next time you touch the table. Winners are paid from what losers paid.",
    "",
    { "AWAY FROM THE TABLE", C.gold },
    "If your turn runs out you check when it is free and fold when it is not. Two hands in a row and you lose the seat.",
    "If short of chips you can go all-in, and side pots keep it fair. Odd chips go to the first winner left of the button. The house takes no rake.",
  }
end

-- ------------------------------------------------------------------ buying in

--- Declare a buy-in or a top-up. Only this player's touches count. Nothing moves.
function App:buyIn(who, seatIndex, topUp)
  local c = self.c
  local _, seat = self:seatOf(who)
  local base = seat and seat.stack or 0

  local function room()
    local balance = wallet.balance(who)
    if not balance then return 0 end
    return math.min(rules.MAX_STACK - base, balance + journal.owedTo(who) - base)
  end

  local limit = room()
  local least = topUp and 1 or rules.MIN_BUY
  if limit < least then
    self:toast(topUp and "Nothing more to top up with" or ("You need " .. rules.MIN_BUY .. " in your wallet"))
    return
  end

  local scene = { name = "buyin", amount = topUp and 0 or rules.MIN_BUY, deadline = now() + BUYIN_MS }
  local cx = math.floor(c.w / 2)
  scene.debugState = function() return { who = who, amount = scene.amount, limit = limit } end

  function scene.tick(s)
    if now() > s.deadline then s.finished = true end
    s.dirty = true
  end

  function scene.draw(s)
    view.felt(c)
    self:topBar()
    c:panel(14, 11, c.w - 26, 56, C.panel, C.feltDark)
    c:frame(14, 11, c.w - 26, 56, C.ink)
    c:bigCenter(cx, 14, topUp and "TOP UP" or "BUY IN", C.gold, 2)
    c:textCenter(cx, 28, view.short(who) .. (topUp and (" has " .. ui.group(base) .. " on the table") or ""), C.text)
    c:bigCenter(cx, 31, ui.group(s.amount), C.gold, 3)
    c:textCenter(cx, 50, ("Up to %s. Nothing is taken until a hand ends."):format(ui.group(limit)), C.mute)
    s.buttons = ui.newButtons()
    local specs = {}
    for _, value in ipairs(CHIPS) do
      if value <= limit then
        specs[#specs + 1] = { id = "chip", value = value, label = value >= 1000 and (value / 1000 .. "K") or tostring(value),
          color = C.accent, textColor = C.ink, disabled = s.amount + value > limit }
      end
    end
    specs[#specs + 1] = { id = "max", label = "MAX", color = C.panel2 }
    specs[#specs + 1] = { id = "clear", label = "CLEAR", color = C.panel2 }
    local w = math.floor((c.w - 34 - 3 * (#specs - 1)) / #specs)
    local x = cx + 1 - math.floor((w * #specs + 3 * (#specs - 1)) / 2)
    for i, spec in ipairs(specs) do
      spec.x, spec.y, spec.w, spec.h = x + (i - 1) * (w + 3), 54, w, 9
      ui.button(c, s.buttons, spec)
    end
    ui.actionBar(c, s.buttons, {
      { id = "cancel", label = "CANCEL", color = C.red },
      { id = "confirm", label = topUp and "ADD CHIPS" or "SIT DOWN", color = C.win, textColor = C.ink, disabled = s.amount < least },
    })
  end

  function scene.touch(s, x, y, by)
    s.deadline = now() + BUYIN_MS
    if by ~= who then
      self:toast(view.short(who) .. " is buying in")
      return
    end
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    if hit.id == "chip" then
      s.amount = math.min(limit, s.amount + hit.value)
      audio.play(hit.value >= 500 and "chipBig" or "chip")
    elseif hit.id == "max" then
      s.amount = limit
      audio.play("chipBig")
    elseif hit.id == "clear" then
      s.amount = 0
      audio.play("tap")
    elseif hit.id == "cancel" then
      audio.play("tap")
      s.finished = true
    elseif hit.id == "confirm" then
      audio.play("start")
      s.chosen, s.finished = true, true
    end
  end

  self:run(scene)
  if not scene.chosen then return end
  -- The balance may have moved while they chose
  if scene.amount > room() or scene.amount < least then
    self:toast("Your balance has changed")
    return
  end
  if topUp then
    seat.stack = seat.stack + scene.amount
  else
    self:seats()[seatIndex] = { name = who, stack = scene.amount, away = 0 }
  end
  self:save()
  log((topUp and "top up " or "sit ") .. who .. " " .. scene.amount)
end

-- ------------------------------------------------------------------ between hands

--- Waiting room and attract screen in one: seats to take, and a countdown once two can play.
function App:lobby()
  local c = self.c
  local scene = { name = "lobby", animating = true, t = 0 }
  local cx = math.floor(c.w / 2)
  local pending = nil
  local show = demo.new(demoScript())

  --- Only an empty table plays: nothing may draw over a real seat or a buy-in on its way.
  local function showing()
    return show and not pending and #self:seatedNames() == 0
  end

  scene.debugState = function()
    local seats = {}
    for index = 1, rules.MAX_SEATS do
      local seat = self:seats()[index]
      if seat then seats[#seats + 1] = { seat = index, name = seat.name, stack = seat.stack, away = seat.away or 0 } end
    end
    return { seats = seats, owed = journal.owed(), countdown = scene.dealAt and math.ceil((scene.dealAt - now()) / 1000) or false,
      demoRounds = show and show.rounds or false, summary = self.farewell and self.farewell.text or false }
  end

  local function openBuyIn(who, seatIndex)
    pending = nil
    self:buyIn(who, seatIndex, false)
  end

  local function sit(who, seatIndex)
    if not wallet.available() then
      self:toast("The economy is offline")
    elseif self:seatOf(who) then
      self:toast("You already have a seat")
    elseif journal.owedTo(who) < 0 then
      self:toast(view.short(who) .. " owes " .. ui.group(-journal.owedTo(who)) .. " from a past hand")
    elseif wallet.isApproved() then
      openBuyIn(who, seatIndex)
    else
      local sent, err = wallet.requestApproval()
      if sent or tostring(err):find("pending", 1, true) then
        pending = { name = who, seat = seatIndex, deadline = now() + APPROVE_MS }
      else
        log("approval request failed: " .. tostring(err))
        self:toast("Could not ask for approval")
      end
    end
  end

  function scene.tick(s, dt)
    s.t = s.t + dt
    if self.farewell and now() > self.farewell.untilAt then self.farewell = nil end
    if showing() then
      local ok, err = pcall(show.tick, show, dt)
      if not ok then
        log("demo step failed: " .. tostring(err))
        show = nil
      end
    end
    if pending then
      if now() > pending.deadline then
        pending = nil
      elseif wallet.livePlayer() == pending.name and wallet.isApproved() then
        if self:seats()[pending.seat] then pending = nil else openBuyIn(pending.name, pending.seat) end
      end
    end
    if self:readyCount() >= rules.MIN_PLAYERS then
      s.dealAt = s.dealAt or (now() + LOBBY_MS)
      if now() >= s.dealAt then s.finished = true end
    else
      s.dealAt = nil
    end
  end

  function scene.draw(s)
    s.buttons = ui.newButtons()
    local playing = showing() and show.state and self:drawDemo(s.buttons, show)
    if showing() and show.state and not playing then show = nil end
    if not playing then
      view.felt(c)
      self:topBar()
      local seats = self:seats()
      for index = 1, rules.MAX_SEATS do
        local seat = seats[index]
        if seat then
          local owed = journal.owedTo(seat.name)
          local info = { name = seat.name, stack = seat.stack, button = self.keep.button == index }
          if owed < 0 then
            info.status, info.statusColor = "owes " .. ui.group(-owed), C.red
          elseif seat.stack < rules.ANTE then
            info.status, info.statusColor = "needs chips", C.orange
          elseif owed > 0 then
            info.status, info.statusColor = "is owed " .. ui.group(owed), C.win
          else
            info.status, info.statusColor = "ready", C.win
          end
          view.seat(c, index, info)
        else
          view.emptySeat(c, s.buttons, index, not pending or pending.seat ~= index)
        end
      end
      c:bigCenter(cx, 31, "DRAW POKER", C.gold, 2)
    end

    -- Under a demo's pot and whose turn it is, or under the title
    local statusY, noteY = playing and 46 or 43, playing and 47 or 45
    if pending then
      c:textCenter(cx, statusY, view.short(pending.name) .. ": click [APPROVE] in chat to use your wallet here.", C.text)
    elseif s.dealAt then
      c:textCenter(cx, statusY, "Next hand in " .. math.max(0, math.ceil((s.dealAt - now()) / 1000)) .. "s", C.text)
    elseif #self:seatedNames() == 0 then
      if math.floor(s.t * 1.5) % 2 == 0 then c:textCenter(cx, statusY, "Tap SIT to play", C.text) end
    else
      c:textCenter(cx, statusY, "Waiting for another player", C.text)
    end
    local line = self:owedLine()
    if not wallet.available() then
      c:textCenter(cx, noteY, "Economy offline", C.orange)
    elseif line then
      c:textCenter(cx, noteY, line, C.orange)
    elseif self.wantsLock then
      c:textCenter(cx, noteY, LOCK_NOTICE, C.mute)
    else
      c:textCenter(cx, noteY, ("%d to %d players. The house takes nothing."):format(rules.MIN_PLAYERS, rules.MAX_SEATS), C.text)
    end
    local finished = playing and show:finished()
    if finished then
      local result = rules.result(show.state)
      view.banner(c, view.BANNER_Y, result.title, result.detail)
    end
    if self.farewell then
      c:textCenter(cx, finished and 48 or (playing and 45 or 47), self.farewell.text, C.gold, C.ink)
    end

    local specs = {
      { id = "leave", label = "LEAVE", color = C.red, disabled = #self:seatedNames() == 0 },
      { id = "rules", label = "RULES", color = C.blue },
      { id = "topup", label = "CHIPS", color = C.blue, disabled = #self:seatedNames() == 0 },
      { id = "deal", label = "DEAL", color = C.win, textColor = C.ink, disabled = self:readyCount() < rules.MIN_PLAYERS },
    }
    if self.back then
      for i = 1, 3 do specs[i].small = true end
      table.insert(specs, 1, { id = "back", label = "ALL GAMES", small = true, color = C.panel2, disabled = #self:seatedNames() > 0 })
    end
    ui.actionBar(c, s.buttons, specs)
  end

  function scene.touch(s, x, y, who)
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    audio.play("tap")
    if hit.id == "back" then self.back() end
    if hit.id == "rules" then
      self:page("RULES", helpLines())
      return
    end
    if not who then
      self:toast("Touch again: the table could not see who you are")
      return
    end
    if hit.id == "sit" then
      sit(who, hit.value)
      return
    end
    local index = self:seatOf(who)
    if not index then
      self:toast("Sit down first")
    elseif hit.id == "leave" then
      self:seats()[index] = nil
      self:save()
      log("left " .. who)
      self:leaving(who)
    elseif hit.id == "topup" then
      self:buyIn(who, index, true)
      s.dealAt = nil
    elseif hit.id == "deal" then
      audio.play("start")
      s.finished = true
    end
  end

  self:run(scene)
end

-- ------------------------------------------------------------------ a hand

--- Who plays this hand. Each stack is held to what the player could really pay, and anyone sitting it out moves closer
-- to losing their seat. Returns nil when fewer than two can play.
function App:openHand()
  local seats = self:seats()
  local entries = {}
  for index = 1, rules.MAX_SEATS do
    local seat = seats[index]
    if seat then
      local balance = wallet.balance(seat.name)
      if balance then seat.stack = math.min(seat.stack, math.max(0, balance + journal.owedTo(seat.name))) end
      if self:canPlay(seat) then
        entries[#entries + 1] = { name = seat.name, stack = seat.stack, seat = index }
      end
    end
  end
  if #entries < rules.MIN_PLAYERS then
    self:save()
    return nil
  end
  for index = 1, rules.MAX_SEATS do
    local seat = seats[index]
    if seat and not self:canPlay(seat) then
      seat.away = (seat.away or 0) + 1
      if seat.away >= AWAY_LIMIT then
        seats[index] = nil
        self:leaving(seat.name)
      end
    end
  end

  local button = 1
  for position, entry in ipairs(entries) do
    if entry.seat > (self.keep.button or 0) then
      button = position
      break
    end
  end
  self.keep.button = entries[button].seat
  self.keep.hands = (self.keep.hands or 0) + 1
  self:save()

  local seed = rng.freshSeed(tostring(self.keep.hands))
  local stream = rng.new(seed)
  local state, events = rules.new(entries, button, stream)
  local round = {
    id = ("%x"):format(now() % 268435456),
    game = GAME_ID,
    seed = seed,
    commit = rng.sha256(seed),
    state = state,
    phase = "open",
    timedOut = {},
  }
  journal.saveRound(round)
  -- Each to their own: the name and the hand come from the same player, here and at the draw
  for _, player in ipairs(state.players) do chat.tell(player.name, rules.whisper(player.hand)) end
  return round, events
end

--- Play a hand to its end, new or resumed, and show how it finished.
function App:playHand(round, firstEvents)
  local c = self.c
  local state = round.state
  local scene = { name = "hand", animating = true, queue = firstEvents or {}, deadline = now() + TURN_MS }

  scene.debugState = function()
    local players = {}
    for i, player in ipairs(state.players) do
      players[i] = { name = player.name, stack = player.stack, bet = player.bet, total = player.total,
        folded = player.folded, allin = player.allin, hand = player.hand }
    end
    return { id = round.id, phase = state.phase, actor = rules.actor(state) or false, pot = rules.potTotal(state),
      players = players, peek = scene.peek and scene.peek.name or false }
  end

  local function startNext(s)
    local ev = table.remove(s.queue, 1)
    if not ev then
      s.playing = nil
      return
    end
    local seconds, sound = eventTiming(ev)
    if sound then audio.play(sound) end
    s.playing = { ev = ev, t = 0, duration = seconds }
  end

  local function apply(s, id, timedOut)
    local who = rules.actor(state)
    local drawing = state.phase == "draw"
    local events = rules.act(state, id)
    if #events == 0 then return false end
    if drawing then chat.tell(who, rules.whisper(rules.find(state, who).hand, true)) end
    if timedOut then
      round.timedOut[who] = true
      log("hand " .. round.id .. " " .. who .. " timed out: " .. id)
    end
    for _, ev in ipairs(events) do s.queue[#s.queue + 1] = ev end
    s.deadline = now() + TURN_MS
    s.peek = nil
    if rules.done(state) then
      -- The money moves before the reveal plays, so nothing that happens during it can change the result
      self:closeHand(round)
      s.settled = true
    else
      journal.saveRound(round)
    end
    return true
  end

  function scene.tick(s, dt)
    if s.peek and now() > s.peek.deadline then s.peek = nil end
    if s.playing then
      s.playing.t = s.playing.t + dt / s.playing.duration
      if s.playing.t >= 1 then s.playing = nil end
    end
    if not s.playing then startNext(s) end
    if s.playing then return end
    if s.settled then
      s.finished = true
      return
    end
    if now() >= s.deadline then apply(s, rules.auto(state), true) end
  end

  local function discardList(peek)
    local list = {}
    for position = 1, rules.HAND_SIZE do
      if peek and peek.discards[position] then list[#list + 1] = position end
    end
    return list
  end

  function scene.draw(s)
    view.table(c, state, s.playing)
    self:topBar()
    -- The promise the FAIR page makes: the hash is up before any card is
    local hash = round.commit:sub(1, HASH_SHOWN)
    local left = s.deadline - now()
    if not s.settled then view.centre(c, state, s.playing, left < WARN_MS, math.max(0, left / TURN_MS)) end
    s.buttons = ui.newButtons()
    if s.playing or #s.queue > 0 or s.settled then
      c:rect(1, c.h - ui.ACTIONS_H, c.w, ui.ACTIONS_H + 1, C.feltDark)
      c:textCenter(math.floor(c.w / 2), c.h - 5, "Tap to skip", C.feltLight)
      ui.hash(c, hash)
      return
    end
    local actor = rules.actor(state)
    local specs = { { id = "peek", label = "PEEK", color = C.panel2 } }
    if state.phase == "draw" then
      local count = #discardList(s.peek and s.peek.name == actor and s.peek or nil)
      specs[2] = { id = "drawgo", label = count > 0 and ("DRAW " .. count) or "STAND PAT", color = C.win, textColor = C.ink }
    else
      for _, action in ipairs(rules.actions(state)) do
        specs[#specs + 1] = { id = action.id, label = action.label, sub = action.sub, color = C[action.color],
          textColor = C[action.textColor or "text"] }
      end
    end
    ui.actionBar(c, s.buttons, specs)
    ui.hash(c, hash)
    if s.peek then
      local player = rules.find(state, s.peek.name)
      local drawing = state.phase == "draw" and s.peek.name == actor
      local share = math.max(0, (s.peek.deadline - now()) / PEEK_MS)
      local regions = view.peek(c, s.peek.name, player.hand, s.peek.discards, share, drawing)
      for _, region in ipairs(regions) do s.buttons[#s.buttons + 1] = region end
    end
  end

  local function toggleCard(s, position)
    local peek = s.peek
    local player = rules.find(state, peek.name)
    peek.discards[position] = not peek.discards[position] or nil
    if not rules.legalDiscard(player.hand, discardList(peek)) then
      peek.discards[position] = nil
      self:toast(("Throw up to %d, or %d keeping an ace"):format(rules.MAX_DISCARD, rules.MAX_DISCARD_ACE))
      return
    end
    peek.deadline = now() + PEEK_MS
    audio.play("flip")
  end

  function scene.touch(s, x, y, who)
    if s.playing or #s.queue > 0 then
      s.playing = nil
      s.queue = {}
      return
    end
    if s.settled then return end
    -- Anyone else's touch hides a hand before anything else happens
    if s.peek and who ~= s.peek.name then s.peek = nil end
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end

    local actor = rules.actor(state)
    if hit.id == "peek" then
      local player = who and rules.find(state, who)
      if not player then
        self:toast("You are not in this hand")
      elseif player.folded then
        self:toast("You have folded")
      elseif s.peek then
        s.peek = nil
      else
        audio.play("flip")
        s.peek = { name = who, deadline = now() + PEEK_MS, discards = {} }
      end
    elseif who ~= actor then
      self:toast("Waiting for " .. view.short(actor))
    elseif hit.id:match("^card%d$") then
      toggleCard(s, tonumber(hit.id:sub(5)))
    elseif hit.id == "drawgo" then
      local digits = table.concat(discardList(s.peek and s.peek.name == who and s.peek or nil))
      apply(s, "draw" .. digits)
    else
      audio.play("tap")
      apply(s, hit.id)
    end
  end

  self:run(scene)
  self:showResult(round)
end

--- The hand's result, with every hand still in face up. Touches here settle whoever makes them.
function App:showResult(round)
  local c = self.c
  local state = round.state
  local result = rules.result(state)
  local scene = { name = "result", deadline = now() + RESULT_MS }
  audio.play("win")
  for _, player in ipairs(state.players) do
    if player.net > 0 and player.net >= player.total * BIG_WIN_TIMES then
      lamps.pulse("bigWin")
      break
    end
  end

  scene.debugState = function()
    return { nets = round.nets, owed = journal.owed(), title = result.title, pots = state.pots }
  end

  function scene.tick(s)
    if now() > s.deadline then s.finished = true end
    s.dirty = true
  end

  function scene.draw(s)
    if state.uncontested then
      view.table(c, state)
      self:topBar()
      view.banner(c, view.BANNER_Y, result.title, result.detail)
      local line = self:owedLine()
      if line then c:textCenter(math.floor(c.w / 2), 47, line, C.orange) end
    else
      c:clear(C.felt)
      c:frame(1, 1, c.w, c.h, C.feltDark)
      self:topBar()
      view.banner(c, ui.TOP, result.title, result.detail)
      view.reveal(c, state, self:owedLine())
    end
    s.buttons = ui.newButtons()
    ui.actionBar(c, s.buttons, {
      { id = "fair", label = "FAIR?", color = C.panel2 },
      { id = "next", label = "NEXT HAND", color = C.win, textColor = C.ink },
    })
  end

  function scene.touch(s, x, y)
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    audio.play("tap")
    if hit.id == "next" then
      s.finished = true
    elseif hit.id == "fair" then
      self:page("FAIR PLAY", {
        "Before the deal this table fixed a secret seed, and showed the start of its hash at the top of the table. Its SHA-256 is the hash below, and the seed drives every shuffle.",
        "", { "Hash", C.gold }, round.commit,
        "", { "Seed, shown now the hand is over", C.gold }, round.seed,
      })
      s.deadline = now() + RESULT_MS
    end
  end

  self:run(scene)
end

--- Run the table for ever.
--- opts.back, on a cabinet: leave this game for the menu. It never returns.
function M.run(opts)
  audio.init()
  net.open()
  chat.scan()
  local self = setmetatable({ back = opts and opts.back, keep = journal.loadKeep(), ctx = { title = TITLE } }, App)
  self.monitorName = board.largest()
  assert(self.monitorName, "this table needs a monitor")
  self:attachCanvas()
  self:attachBoard()
  self.debug = fs.exists("casino_debug.flag")
  self.wantsLock = wallet.wantsLock()

  local function main()
    local round = self:recover()
    if round then self:playHand(round) end
    while true do
      self:lobby()
      local nextRound, events = self:openHand()
      if nextRound then self:playHand(nextRound, events) end
    end
  end

  parallel.waitForAny(main, net.worker, chat.worker, lamps.worker)
end

return M
