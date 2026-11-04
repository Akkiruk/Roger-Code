-- seat.lua
-- The seat computer, and the front end of any seat. Thin on purpose: it draws what the dealer sends, reports touches, and carries
-- out moves. The dealer owns the truth, and this computer is the hands, because ccvault sessions are per player per computer and
-- only this one can move this player's tokens.
--
-- A Front is one wall: it shows a screen, plays its events and turns a touch into an input. A seat computer has one, driven over
-- the link. A Duel has two on one computer, driven by the dealer directly (station.lua).
--
-- A move, step by step. The order is { tag, name, amount } and each tag is one attempt:
--   open   the order is written down in group_orders.dat
--   book   the amount goes in this computer's own owed book, under the tag, and that is noted beside the order
--   move   books.move, which writes the transfer down first and takes what moved off the book in one write
--   moved  what moved is noted beside the order
--   back   any part that did not move comes off this book, so only the dealer's book carries a debt
--   done   the order goes from open to done[tag] = moved, in one write, and the answer goes back
-- A crash between any two of these leaves the order open. The note says whether it was booked: the book's own memory of tags is
-- short, and an order can stay in doubt longer than that. books.resolve answers what the transfer did from the audit log or the
-- ledger, and what is left in the book says how much did not move. If that cannot be told yet the seat says nothing: the dealer
-- keeps asking, and the player's next touch lets the ledger answer. A repeated tag gets the stored answer and nothing moves. Nobody
-- but this file calls books on a seat.
--
-- A trace is the ledger's word on an order sent to some other computer that has gone for good, read here because the player touched
-- here. It moves nothing and keeps nothing, and the dealer asks until it hears.

local audio = require("lib.casino.audio")
local books = require("lib.casino.books")
local journal = require("lib.casino.journal")
local link = require("lib.casino.group.link")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local wallet = require("lib.casino.wallet")

local C = theme.C
local M = {}

M.LINK_FILE = "group_link.dat"
M.ORDER_FILE = "group_orders.dat"

local FRAME = 0.1
local MAX_TOUCHES = 6          -- a frame's worth of mashing. Each touch can wait on the bank, so a backlog would lag the whole seat
local DONE_KEPT = 64           -- answers remembered. Far more than a dealer can have open
local HELLO_MS = 2000          -- how often a seat with no dealer asks
local CHOOSE_WAIT_MS = 2500    -- how long the first answer waits for others
local FOUND_STALE_MS = 8000
local APPROVE_RETRY_MS = 20000
local APPROVE_POLL_MS = 500
local TOAST_MS = 2500
local NUDGE_MS = 22000         -- a seated player gets a word before the bank's 30 second touch window closes
local LOCK_NOTICE = "Owner: tap to lock this seat"
local NO_MODEM = "This seat needs an ender modem"

local function now()
  return os.epoch("utc")
end

local function log(message)
  journal.log(message)
end

-- ------------------------------------------------------------------ a wall

local Front = {}
Front.__index = Front

--- A front end on a monitor. full gives the game the whole wall, as a Duel does; otherwise it gets a centred 78x52.
function M.front(cabinet, monitorName, full)
  local self = setmetatable({ cabinet = cabinet, monitorName = monitorName, full = full, queue = {}, buttons = {}, asked = {} }, Front)
  self:attach()
  return self
end

function Front:attach()
  local monitor = peripheral.wrap(self.monitorName)
  if not monitor then
    self.monitor, self.c = nil, nil
    return
  end
  self.monitor = monitor
  monitor.setTextScale(0.5)
  theme.apply(monitor, self.felt or "green")
  local c, ox, oy = seatui.canvas(monitor, self.full)
  self.c, self.ox, self.oy = c, ox or 0, oy or 0
  monitor.setBackgroundColor(2 ^ tonumber(C.feltDark, 16))
  monitor.clear()
  if c then c:invalidate() end
  self.dirty = true
end

function Front:plugin()
  local screen = self.screen
  return screen and screen.game and self.cabinet.find(screen.game) or nil
end

function Front:setFelt(felt)
  if felt and felt ~= self.felt and self.monitor then
    self.felt = felt
    theme.apply(self.monitor, felt)
  end
end

--- Take a screen. Only a new n replaces what is up. The same n again is the heartbeat, and it may carry a newer clock.
function Front:show(screen)
  local time = now()
  self.heardAt = time
  -- An overlay took the buttons with it, so the picture underneath has to go back up, even if it has not changed
  if self.overlay then self.dirty = true end
  self.overlay = nil
  if self.screen and self.screen.n == screen.n then
    self.screen.left, self.screen.countdown = screen.left, screen.countdown
    self.clockAt = time
    return false
  end
  self.screen = screen
  self.clockAt = time
  self:setFelt(screen.felt)
  self.dirty = true
  if type(screen.events) == "table" then
    for _, ev in ipairs(screen.events) do self.queue[#self.queue + 1] = ev end
  end
  return true
end

function Front:busy()
  return self.playing ~= nil or #self.queue > 0
end

local function eventTiming(plugin, ev)
  if plugin and plugin.event then
    local ok, seconds, sound = pcall(plugin.event, ev)
    if ok and type(seconds) == "number" and seconds > 0 then return seconds, sound end
  end
  return 0.1, nil
end

function Front:tick(dt)
  if self.toastUntil and now() > self.toastUntil then
    self.toastText, self.toastUntil = nil, nil
    self.dirty = true
  end
  if self.playing then
    self.playing.t = self.playing.t + dt / self.playing.duration
    if self.playing.t >= 1 then self.playing = nil end
    self.dirty = true
  end
  if not self.playing then
    local ev = table.remove(self.queue, 1)
    if ev then
      local seconds, sound = eventTiming(self:plugin(), ev)
      if sound then audio.play(sound) end
      self.playing = { ev = ev, t = 0, duration = seconds }
      self.dirty = true
    end
  end
  local screen = self.screen
  if screen and (screen.left or screen.countdown or screen.kind == "game") and now() - (self.drawnAt or 0) > 500 then self.dirty = true end
end

--- A word on the screen, for a moment.
function Front:toast(text)
  self.toastText = tostring(text)
  self.toastUntil = now() + TOAST_MS
  self.dirty = true
  audio.play("error")
end

function Front:draw()
  if not self.dirty then return end
  self.dirty = false
  local c, screen = self.c, self.screen
  if not screen then return end
  if not c then
    if self.monitor then
      self.monitor.setCursorPos(1, 1)
      self.monitor.write("This seat needs a 4x4 wall")
    end
    return
  end
  local time = now()
  self.drawnAt = time
  local passed = time - (self.clockAt or time)
  local shown = {}
  for key, value in pairs(screen) do shown[key] = value end
  if screen.left then shown.left = math.max(0, screen.left - passed) end
  local countdown = screen.countdown and math.max(0, screen.countdown - passed) or nil
  if self.overlay then
    shown.buttons, shown.tap, shown.tiles = {}, false, {}
    shown.note, shown.warn = self.overlay, true
  elseif self.lockNote and not screen.name and not shown.note then
    shown.note = self.lockNote
  elseif screen.kind == "game" and screen.name and not shown.note and not self.cabinet.free and time - (self.touchedAt or time) > NUDGE_MS then
    shown.note, shown.warn = "Tap the screen now and then: the bank needs a recent touch", true
  end
  local anim = self.playing and { ev = self.playing.ev, t = math.min(1, self.playing.t) } or nil
  self.buttons = seatui.draw(c, shown, self:plugin(), anim, countdown)
  if self.toastText then seatui.toast(c, self.toastText) end
  c:flush()
end

--- Ask the player at this computer to approve it in chat, if they have not, and not too often. A player can only be asked while they
-- are the one this computer knows, which a touch makes them.
function Front:ask(who)
  if wallet.livePlayer() ~= who or wallet.isApproved() == true or now() - (self.asked[who] or 0) <= APPROVE_RETRY_MS then return end
  self.asked[who] = now()
  local sent, err = wallet.requestApproval()
  if not sent and not tostring(err):find("pending", 1, true) then log("approval request failed: " .. tostring(err)) end
end

--- A touch on this wall. Returns the input to report, or nil if nobody could be told apart from anybody.
function Front:press(x, y, who)
  x, y = x - (self.ox or 0), y - (self.oy or 0)
  who = who or wallet.livePlayer()
  if not who then
    self:toast("Touch again: the table could not see who you are")
    return nil
  end
  wallet.lockIfOwner(who)
  self.touchedAt = now()
  local screen = self.screen
  local hit = ui.hit(self.buttons, x, y)
  if self:busy() then
    -- A touch skips whatever is playing, and still counts if it landed on a button
    self.queue, self.playing = {}, nil
    self.dirty = true
  end
  -- A free table never asks for approval: there is nothing for a wallet to do
  local free = self.cabinet.free == true
  local approved = not free and wallet.isApproved() == true
  local theirs = screen and (screen.name == who or screen.only == who or (hit and hit.id == "sit"))
  if theirs and not free then self:ask(who) end
  local holder = screen and (screen.only or screen.name)
  if hit and holder and holder ~= who then
    self:toast(seatui.short(holder) .. "'s seat")
    hit = nil
  end
  if hit then audio.play("tap") end
  return { who = who, id = hit and hit.id or nil, value = hit and hit.value or nil, approved = approved,
    shown = screen and screen.gen or nil }
end

--- While a player is asked to approve, watch for it. Returns the input to report once they have.
function Front:watchApproval()
  local who = self.screen and self.screen.approve
  if not who or now() - (self.polledAt or 0) < APPROVE_POLL_MS then return nil end
  self.polledAt = now()
  if wallet.livePlayer() == who and wallet.isApproved() then
    return { who = who, id = "approved", approved = true, shown = self.screen.gen }
  end
  return nil
end

--- What the test suites read: only with casino_debug.flag on the computer.
function Front:debug()
  local screen = self.screen or {}
  local buttons = {}
  for _, b in ipairs(self.buttons or {}) do
    buttons[#buttons + 1] = { id = b.id, value = b.value, x = b.x + (self.ox or 0), y = b.y + (self.oy or 0), w = b.w, h = b.h,
      label = b.label }
  end
  return { n = screen.n or false, kind = screen.kind or false, game = screen.game or false, name = screen.name or false,
    only = screen.only or false, number = screen.number or false, title = screen.title or false, note = screen.note or false,
    lines = screen.lines or false, tap = screen.tap == true, view = screen.view or false, result = screen.result or false,
    money = screen.money or false, owed = screen.owed or false, overlay = self.overlay or false, toast = self.toastText or false,
    busy = self:busy(), buttons = buttons, w = self.c and self.c.w or false, h = self.c and self.c.h or false, ox = self.ox or 0,
    oy = self.oy or 0 }
end

-- ------------------------------------------------------------------ moves

local Orders = {}
Orders.__index = Orders

--- The book of orders on this computer. answer(tag, moved) is told each result.
function M.orders(answer)
  local data = journal.load(M.ORDER_FILE)
  if type(data) ~= "table" then data = {} end
  data.open, data.done = data.open or {}, data.done or {}
  return setmetatable({ data = data, answer = answer }, Orders)
end

function Orders:save()
  return journal.save(M.ORDER_FILE, self.data)
end

function Orders:stored(tag)
  for _, entry in ipairs(self.data.done) do
    if entry.tag == tag then return entry.moved end
  end
  return nil
end

--- The last steps of a move once what moved is known and noted. Each can run again and do nothing.
function Orders:close(tag)
  local open = self.data.open[tag]
  local left = open.amount - open.moved
  if left ~= 0 then journal.book(open.name, -left, "back " .. tag) end
  local done = self.data.done
  done[#done + 1] = { tag = tag, moved = open.moved }
  while #done > DONE_KEPT do table.remove(done, 1) end
  self.data.open[tag] = nil
  if not self:save() then log("order " .. tag .. " could not be closed") end
  self.answer(tag, open.moved)
end

--- Finish an order a crash left open, if that can be told yet. Returns true once it is closed.
function Orders:finish(tag)
  local open = self.data.open[tag]
  if not open then return true end
  if open.moved == nil then
    if not open.booked then
      -- Only a crash right after booking comes here, and that is answered at boot while the book still knows the tag
      journal.book(open.name, open.amount, "order " .. tag)
      open.booked = true
      self:save()
    end
    if not books.resolve(open.name) then return false end
    open.moved = open.amount - journal.owedTo(open.name)
    self:save()
    log("resolved order " .. tag .. " " .. open.name .. " " .. open.amount .. " moved=" .. open.moved)
  end
  self:close(tag)
  return true
end

--- Everything a crash left open. For one name after their touch, or everyone at boot.
function Orders:recover(name)
  for tag, open in pairs(self.data.open) do
    if not name or open.name == name then self:finish(tag) end
  end
end

--- A move. Every step is in the header of this file.
function Orders:run(tag, name, amount)
  local stored = self:stored(tag)
  if stored then
    self.answer(tag, stored)
    return
  end
  if self.data.open[tag] then
    self:finish(tag)
    return
  end
  -- An earlier order for this player is in doubt, so nothing else moves for them until it is answered
  for _, open in pairs(self.data.open) do
    if open.name == name then return end
  end
  self.data.open[tag] = { name = name, amount = amount }
  if not self:save() then
    self.data.open[tag] = nil
    log("order " .. tag .. " could not be written down")
    return
  end
  if not journal.book(name, amount, "order " .. tag) then
    self.data.open[tag] = nil
    self:save()
    log("order " .. tag .. " could not be booked")
    return
  end
  self.data.open[tag].booked = true
  if not self:save() then
    -- Nothing has moved. The dealer asks again, and with the book as it stands that closes it as moved 0
    log("order " .. tag .. " could not be noted as booked")
    return
  end
  local moved, _, err = books.move(name, amount, tag)
  if moved ~= amount then log("order " .. tag .. " " .. name .. " wanted " .. amount .. " moved " .. moved .. ": " .. tostring(err)) end
  self.data.open[tag].moved = moved
  self:save()
  self:close(tag)
end

--- What the ledger says of an order this computer was never sent. If it can never say, the player gets the benefit of the doubt, as
-- books.lua gives it: a charge counts as taken and a payment as not made.
function Orders:trace(tag, name, amount, at)
  local moved, never = wallet.ledgerMoved(name, tag, at)
  if moved == nil then
    if not never then return end
    moved = amount < 0 and -amount or 0
  end
  moved = math.min(moved, math.abs(amount))
  self.answer(tag, amount < 0 and -moved or moved)
end

-- ------------------------------------------------------------------ the seat computer

local Seat = {}
Seat.__index = Seat

function Seat:saveLink()
  journal.save(M.LINK_FILE, { dealer = self.dealer })
end

local function clearScreen(self, key, lines, tiles, note)
  self.boot = (self.boot or 0) + 1
  self.front:show({ n = -self.boot, kind = "panel", title = self.cabinet.title, name = false, buttons = {}, lines = lines,
    tiles = tiles or {}, note = note, felt = "green" })
  self.shownLocal = key
end

--- A screen of the seat's own, while it has no dealer to ask.
function Seat:localScreen(key, lines, tiles, note)
  if self.shownLocal ~= key then clearScreen(self, key, lines, tiles, note) end
end

function Seat:join(id)
  self.link:send(id, "join", { host = self.host, cabinet = self.cabinet.key })
end

function Seat:choose(id)
  self.dealer, self.number, self.joinedAt = id, nil, nil
  self.seekingSince = nil
  self.shownLocal, self.choosing = nil, false
  self:saveLink()
  self:join(id)
  self.joinAskedAt = now()
  log("joining dealer " .. id)
end

--- Dealers heard lately, and whether more than one needs a person to choose.
function Seat:fresh(time)
  local list = {}
  for id, entry in pairs(self.found) do
    if time - entry.at > FOUND_STALE_MS then
      self.found[id] = nil
    else
      list[#list + 1] = { id = id, title = entry.title, game = entry.game, seated = entry.seated, free = entry.free }
    end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function Seat:showChoice(list)
  local key, tiles = "choose", {}
  for _, entry in ipairs(list) do
    key = key .. ":" .. entry.id
    tiles[#tiles + 1] = { id = "dealer", value = entry.id, label = "TABLE " .. entry.id, color = "win", textColor = "ink",
      sub = tostring(entry.game or ""):sub(1, 20) }
  end
  self.choosing = true
  local line = self.dealer and ("Table " .. self.dealer .. " has gone quiet. This seat waits for it, or tap another.")
    or "Tap the table this seat belongs to. It remembers."
  self:localScreen(key, { { "CHOOSE YOUR TABLE", "gold", 1 }, { line, "text" } }, tiles)
end

--- Find a dealer. Runs while there is none, and while the one this seat had has been silent a long time. Choosing is the only thing
-- that writes group_link.dat once a seat has a dealer: a table that goes quiet is coming back, and its seats and debts are there.
function Seat:seek(time)
  if time - (self.hostAt or 0) > HELLO_MS then
    self.hostAt = time
    self.host = wallet.hostName()
  end
  if not self.host then
    self:localScreen("owner", { { self.cabinet.title, "gold", 1 }, { "Owner: right-click this computer and claim it in chat.", "text" },
      { "It looks for its dealer as soon as it has an owner.", "mute" } })
    return
  end
  if time - (self.helloAt or 0) > HELLO_MS then
    self.helloAt = time
    self.modem = link.open()
    self.link:broadcast("hello", { host = self.host })
  end
  local list = self:fresh(time)
  if #list == 0 then
    if not self.dealer then
      local words = self.modem and "Waiting for a dealer with the same owner" or NO_MODEM
      self:localScreen("seek:" .. words, { { "LOOKING FOR", "gold", 1 }, { "THE DEALER", "gold", 1 }, { words, "text" } })
    end
    self.seekingSince, self.choosing = nil, false
    return
  end
  for _, entry in ipairs(list) do
    if entry.id == self.dealer then
      -- It is there and has not been talking to this seat, so it may have lost track of it: ask again
      self.number, self.choosing = nil, false
      return
    end
  end
  self.seekingSince = self.seekingSince or time
  if time - self.seekingSince < CHOOSE_WAIT_MS then return end
  if #list == 1 and not self.dealer then
    self:choose(list[1].id)
  else
    self:showChoice(list)
  end
end

function Seat:handle(message)
  local kind, from = message.kind, message.from
  if kind == "here" then
    -- A dealer of another owner or another cabinet is not this seat's, however loudly it answers
    if message.host == self.host and message.cabinet == self.cabinet.key then
      self.found[from] = { title = message.title, game = message.game, seated = message.seated, free = message.free, at = now() }
    end
  elseif from ~= self.dealer then
    return
  elseif self.cabinet.free and (kind == "order" or kind == "trace" or kind == "ask") then
    -- A free seat moves no tokens and asks nobody to approve anything, whoever says so
    return
  elseif kind == "welcome" then
    self.number = message.number
    self.heardAt = now()
    log("seat " .. self.number .. " at dealer " .. from)
  elseif kind == "full" then
    -- It keeps asking, so it gets a number the moment one frees up
    self.heardAt = now()
    self:localScreen("full", { { "TABLE FULL", "orange", 1 }, { "This dealer has all the seats it can take.", "text" } })
  elseif kind == "view" then
    self.heardAt = now()
    self.number = self.number or message.screen.number
    self.shownLocal, self.choosing = nil, false
    self.front:show(message.screen)
  elseif kind == "toast" then
    self.heardAt = now()
    self.front:toast(message.text)
  elseif kind == "order" then
    self.heardAt = now()
    self.orders:run(message.tag, message.name, message.amount)
  elseif kind == "trace" then
    self.heardAt = now()
    self.orders:trace(message.tag, message.name, message.amount, message.at)
  elseif kind == "ask" then
    self.heardAt = now()
    self.front:ask(message.who)
  end
end

--- One frame of work. Nothing here may stop the seat: a message that throws is logged and forgotten.
function Seat:step(time, dt)
  for _, message in ipairs(self.link:drain()) do
    local ok, err = pcall(self.handle, self, message)
    if not ok then log("message " .. tostring(message.kind) .. " failed: " .. tostring(err)) end
  end

  local touches = self.touches
  self.touches = {}
  for _, touch in ipairs(touches) do
    local input = self.front:press(touch.x, touch.y, touch.who)
    if input then
      if self.front.screen and input.id == "dealer" then
        self:choose(input.value)
      elseif self.dealer then
        if input.approved then self.orders:recover(input.who) end
        self.link:send(self.dealer, "input", input)
      end
    end
  end

  local input = self.front:watchApproval()
  if input and self.dealer then self.link:send(self.dealer, "input", input) end

  local silent = self.dealer and time - (self.heardAt or self.bootAt) or 0
  if not self.dealer or silent > link.LOST_MS then self:seek(time) end
  if self.dealer then
    if not self.number and time - (self.joinAskedAt or 0) > link.BEAT_MS then
      self.joinAskedAt = time
      self.host = self.host or wallet.hostName()
      if self.host then self:join(self.dealer) end
    end
    if time - (self.beatAt or 0) > link.BEAT_MS then
      self.beatAt = time
      if self.number then self.link:send(self.dealer, "beat", {}) end
    end
    if silent > link.QUIET_MS and not self.choosing then
      if not self.front.screen or self.shownLocal then
        local words = not self.modem and NO_MODEM or nil
        self:localScreen("waiting:" .. tostring(words), { { "WAITING FOR", "gold", 1 }, { "THE DEALER", "gold", 1 }, words and { words, "text" } or nil })
      else
        self.front.overlay = "WAITING FOR THE DEALER"
        self.front.dirty = true
      end
    end
  end

  if time - (self.aliveAt or 0) > 5000 then
    self.aliveAt = time
    os.queueEvent("roger_alive")
    local screen = self.front.screen
    os.queueEvent("roger_busy", screen ~= nil and screen.name ~= false and screen.name ~= nil) -- an update waits for the player
    self.front.lockNote = wallet.wantsLock() and LOCK_NOTICE or nil
  end

  self.front:tick(dt)
  self.front:draw()
  if self.debug then self:writeDebug() end
end

function Seat:writeDebug()
  local state = self.front:debug()
  state.role, state.dealer, state.seat = "seat", self.dealer or false, self.number or false
  state.open = 0
  for _ in pairs(self.orders.data.open) do state.open = state.open + 1 end
  local ok, text = pcall(textutils.serializeJSON, state)
  if not ok then return end
  local handle = fs.open("casino_ui.dat", "w")
  if handle then
    handle.write(text)
    handle.close()
  end
end

--- Every event lands here first, in a coroutine that never makes a wallet call, so none can be lost while one waits.
function Seat:pump()
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "rednet_message" then
      self.link:hear(a, b, c)
    elseif event == "vhcc_touch" then
      self.toucher = a
    elseif event == "monitor_touch" then
      if a == self.front.monitorName and #self.touches < MAX_TOUCHES then
        self.touches[#self.touches + 1] = { x = b, y = c, who = self.toucher }
      end
      self.toucher = nil
    elseif event == "monitor_resize" and a == self.front.monitorName then
      self.resized = true
    elseif event == "peripheral" or event == "peripheral_detach" then
      self.rescan = true
    end
  end
end

function Seat:main()
  self.orders:recover()
  local last = now()
  while true do
    local timer = os.startTimer(FRAME)
    repeat
      local _, id = os.pullEvent("timer")
    until id == timer
    local time = now()
    if self.resized then
      self.resized = false
      -- A wall still forming at boot looks small. Once it has formed it may turn out to be a dealer's
      local w, h = peripheral.call(self.front.monitorName, "getSize")
      if w >= seatui.DEALER_W and h >= seatui.DEALER_H then os.reboot() end
      self.front:attach()
    end
    if self.rescan then
      self.rescan = false
      audio.init()
      self.modem = link.open()
    end
    self:step(time, (time - last) / 1000)
    last = time
  end
end

--- Run a seat on this wall, for ever.
function M.run(cabinet, monitorName)
  audio.init()
  local modem = link.open()
  local saved = journal.load(M.LINK_FILE)
  local self = setmetatable({
    cabinet = cabinet, link = link.new(), front = M.front(cabinet, monitorName), found = {}, touches = {}, modem = modem,
    dealer = type(saved) == "table" and tonumber(saved.dealer) or nil, bootAt = now(), debug = fs.exists("casino_debug.flag"),
  }, Seat)
  self.orders = M.orders(function(tag, moved)
    if self.dealer then self.link:send(self.dealer, "answer", { tag = tag, moved = moved }) end
  end)
  clearScreen(self, "boot", { { "LOOKING FOR", "gold", 1 }, { "THE DEALER", "gold", 1 } })
  parallel.waitForAny(function() self:main() end, function() self:pump() end)
end

return M
