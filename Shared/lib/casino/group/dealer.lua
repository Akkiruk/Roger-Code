-- dealer.lua
-- A table with many screens: one dealer, up to 8 seats, and a game from the cabinet's registry. The same code runs Big Table, with
-- a wall of its own and seat computers on the link, and Duel, with two walls on this computer and no network. The dealer owns the
-- truth: seats, the hand, the clock, the owed book, FAIR. A seat draws what it is sent. Games/BigTable/games/README.md is what a
-- game sees of all this, and Do/group_tables_design.md is why it is this way.
--
-- How a hand's money moves. ccvault sessions are per player per computer, so only a player's seat can move their tokens:
--   1. The nets go in this computer's owed book, once, under a tag, before anything moves. nets in a players game add up to zero, or a little below it when
--      the owner keeps a split pot's odd chips (rounding.lua).
--      A house game's go under "name@house", so the book's plain names still add up to what the host holds for players.
--   2. A move is an order to that player's seat. Each attempt has its own tag, written here with journal.beginMove, and sent again
--      until the seat answers. The answer takes what moved off the book in one write, with journal.endMove. seat.lua has the
--      seat's side: a repeated tag gets the stored answer, so a move happens once however many times it is asked for.
--   3. M.plan says what to order, in the order of pokertable_rules.settle: collect from every loser first, then pay winners only
--      from what was collected, biggest first. An order not yet answered counts as paid when paying and as not collected when
--      collecting, so the host can never go below even, whatever is lost on the way. House amounts stand on their own and wait for
--      nobody else's money. A loser who cannot be reached is not asked for again until they touch, so they hold up nobody.
--   4. What did not move stays in the book, one book for the whole table. A credit on one side of it pays a debt on the other with
--      no tokens moving. Any touch on a seat tells the dealer, and if the book holds something for that name a fresh order goes out.
--      A seated player plays on what their balance covers after a debt. Someone who has left must clear it before they can sit again.
--   5. An order stays open until the seat it went to answers, however long that takes. If that seat has been silent longer than a
--      touch lasts it can no longer be moving tokens, so when the player touches another computer that one reads the ledger for the
--      answer (a trace, see seat.lua), the order closes on it, and a fresh one goes out from where they are.
-- The final reveal waits until the orders are answered, or a few seconds if a seat has gone quiet, so the money moves before it. Until
-- the last cards have played the dealer's wall shows the seats as they stood when the hand ended: the book would give the result away.
--
-- On Duel the walls are on this computer, so there is no seat book: a move is books.move, as on a Poker Table.
--
-- A free cabinet (cabinet.free, Game Night) has no money at all: nobody buys in or approves, nothing goes in the book, no order is
-- ever sent, and the stats, the session notes and the hub hear nothing. A seat is a name and a count of wins. Every money step
-- below checks self.free first, and lib/casino/group/free.lua swaps the wallet and the books for stand-ins that refuse to move a
-- token, so a call missed here fails instead of reaching ccvault.
--
-- A reboot resumes the hand from the journal, seats show WAITING FOR THE DEALER until then, and open orders simply go again. The
-- journal keeps a hand until its result has been up, so a reboot during the reveal still shows it, and the money does not move again.
-- Everything the dealer hears comes through the link's checks. It runs in one loop with no scenes inside scenes, because any seat
-- can say anything at any moment. Every event lands in the pump, which makes no wallet call and so can never lose one.

local audio = require("lib.casino.audio")
local board = require("lib.casino.board")
local books = require("lib.casino.books")
local canvas = require("lib.casino.canvas")
local chat = require("lib.casino.chat")
local journal = require("lib.casino.journal")
local lamps = require("lib.casino.lamps")
local limits = require("lib.casino.limits")
local link = require("lib.casino.group.link")
local net = require("lib.casino.net")
local rng = require("lib.casino.rng")
local seatmod = require("lib.casino.group.seat")
local seatui = require("lib.casino.group.seatui")
local session = require("lib.casino.session")
local station = require("lib.casino.group.station")
local stats = require("lib.casino.stats")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local wallet = require("lib.casino.wallet")

local C = theme.C
local M = {}

M.HOUSE = "@house"       -- what follows a name in the book for what stands against the house
M.MAX_SEATS = 8

local FRAME = 0.1
local MAX_TOUCHES = 6          -- a frame's worth of mashing. Each touch can wait on the bank, so a backlog would lag the whole table
local SETTLE_EVERY_MS = 400      -- how often the book is looked at
local TURN_MS = 45000
local LOBBY_MS = 10000           -- from enough players ready to the deal. Nobody has to press anything
local BET_MS = 20000             -- from the first bet to the deal
local ALL_BET_MS = 1500          -- from everyone being ready to the deal
local RESULT_MS = 15000
local PANEL_MS = 30000           -- a buy-in or a page nobody touches closes
local APPROVE_MS = 60000
local VOTE_MS = 30000
local COLLECT_WAIT_MS = 3000     -- winners wait this long for a loser's seat to answer, so one payment is not two
local SETTLE_WAIT_MS = 3000      -- the final reveal waits this long for the money
local AWAY_LIMIT = 2             -- hands in a row a player can time out before losing their seat
local VIEWER_MS = 300000         -- on a Duel wall, a player's private view stays up this long after their last touch
local COMPUTER_MS = 1000         -- the pause before the computer takes a move of its own
local SESSION_STALE_MS = 120000  -- a visit with no seat, which only a reboot can leave behind, ends here
local TOUCH_MS = link.TOUCH_MS
local HASH_SHOWN = 16
local BIG_WIN_TIMES = 10
local LOCK_NOTICE = "Owner: tap to lock this table"
local CHIPS = { 100, 250, 500, 1000, 2500 }

local log = journal.log

local function now()
  return os.epoch("utc")
end

local function short(name)
  return seatui.short(name)
end

local function isHouse(key)
  return key:sub(-#M.HOUSE) == M.HOUSE
end

local function playerOf(key)
  return isHouse(key) and key:sub(1, -#M.HOUSE - 1) or key
end

-- ------------------------------------------------------------------ the order of the money

--- What to order now. Pure, so the order can be proved: see Tests/group_engine_test.lua.
-- @param owed table     the book: key -> tokens, positive to the player
-- @param moves table    orders not yet answered: tag -> { name = key, amount }
-- @param wanted table   name -> true for the players it is worth asking for
-- @param payLater bool  a loser's seat may still answer, so hold the winners back a moment
-- @return list of { key, name, amount }. At most one for a player, and never one while they have one out.
function M.plan(owed, moves, wanted, payLater)
  local busy, holding = {}, 0
  for key, amount in pairs(owed) do
    if not isHouse(key) then holding = holding + amount end
  end
  for _, move in pairs(moves) do
    busy[playerOf(move.name)] = true
    if move.amount > 0 and not isHouse(move.name) then holding = holding - move.amount end
  end

  local collects, pays = {}, {}
  for key, amount in pairs(owed) do
    local name = playerOf(key)
    if wanted[name] and not busy[name] then
      local entry = { key = key, name = name, amount = amount }
      if amount < 0 then collects[#collects + 1] = entry else pays[#pays + 1] = entry end
    end
  end
  table.sort(collects, function(a, b) return a.key < b.key end)
  table.sort(pays, function(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return a.key < b.key
  end)

  local orders, sent, collecting = {}, {}, false
  for _, entry in ipairs(collects) do
    if not sent[entry.name] then
      sent[entry.name] = true
      orders[#orders + 1] = entry
      collecting = collecting or not isHouse(entry.key)
    end
  end
  -- What the house owes is its own money, so it waits for nobody's collection
  for _, entry in ipairs(pays) do
    if isHouse(entry.key) and not sent[entry.name] then
      sent[entry.name] = true
      orders[#orders + 1] = entry
    end
  end
  if payLater or collecting then return orders end
  for _, entry in ipairs(pays) do
    if not sent[entry.name] then
      local room = math.min(entry.amount, holding)
      if room > 0 then
        sent[entry.name] = true
        holding = holding - room
        orders[#orders + 1] = { key = entry.key, name = entry.name, amount = room }
      end
    end
  end
  return orders
end

-- ------------------------------------------------------------------ the dealer

local Dealer = {}
Dealer.__index = Dealer

local function normal(plugin)
  plugin.minSeats = plugin.minSeats or (plugin.kind == "players" and 2 or 1)
  plugin.maxSeats = math.min(plugin.maxSeats or M.MAX_SEATS, M.MAX_SEATS)
  plugin.ante = plugin.ante or 1
  plugin.minBuy = plugin.minBuy or 100
  plugin.maxStack = plugin.maxStack or 5000
  plugin.minBet = plugin.minBet or 1
  plugin.turnMs = plugin.turnMs or TURN_MS
  return plugin
end

function Dealer:save()
  journal.saveKeep(self.keep)
end

function Dealer:seats()
  self.keep.seats = self.keep.seats or {}
  return self.keep.seats
end

function Dealer:seat(number)
  return self:seats()[number]
end

--- A player's seat number and record, or nil.
function Dealer:seatOf(name)
  for number = 1, M.MAX_SEATS do
    local seat = self:seat(number)
    if seat and seat.name == name then return number, seat end
  end
  return nil
end

function Dealer:seatedNames()
  local names = {}
  for number = 1, M.MAX_SEATS do
    local seat = self:seat(number)
    if seat then names[#names + 1] = seat.name end
  end
  return names
end

--- Everything the book holds for a player, across both sides of it.
function Dealer:owedTo(name, book)
  book = book or journal.owed()
  return (book[name] or 0) + (book[name .. M.HOUSE] or 0)
end

--- What a player owes and is owed, apart. Each has its own money behind it, so a debt is a debt even with a credit beside it.
function Dealer:sides(name, book)
  book = book or journal.owed()
  local debt, credit = 0, 0
  for _, key in ipairs({ name, name .. M.HOUSE }) do
    local amount = book[key] or 0
    if amount < 0 then debt = debt - amount else credit = credit + amount end
  end
  return debt, credit
end

function Dealer:mark()
  self.stale, self.wallDirty = true, true
end

function Dealer:toast(number, text)
  local st = self.stations[number]
  if st then st:toast(text) end
end

function Dealer:wallToast(text)
  self.toastText, self.toastUntil = text, now() + 2500
  audio.play("error")
end

--- The game on the table.
function Dealer:setGame(id)
  local plugin = self.cabinet.find(id)
  if not plugin then return false end
  if self.keep.game ~= id then
    -- A stake and any panel open for a sit-down belong to the game that is going. A boot comes through here too, and keeps them
    self.keep.stake = nil
    for _, st in pairs(self.stations) do
      if st.sub and st.sub.kind ~= "page" then st.sub = nil end
    end
  end
  self.plugin = normal(plugin)
  self.keep.game = id
  self.bets = {}
  self.dealAt = nil
  self:save()
  if self.monitor then theme.apply(self.monitor, plugin.felt) end
  log("game " .. id)
  self:mark()
  return true
end

--- This game's own keep: its shoe, its road, what it carries from round to round.
function Dealer:gameKeep()
  self.keep.games = self.keep.games or {}
  local id = self.plugin.id
  self.keep.games[id] = self.keep.games[id] or {}
  return self.keep.games[id]
end

-- ------------------------------------------------------------------ money

--- Tell the book a player is worth asking for: they touched, or a hand ended.
function Dealer:want(name)
  self.wanted[name] = true
end

--- The computer that can move this player's tokens now: the one they touched last, or the one they sit at.
function Dealer:stationFor(name)
  local touch = self.lastTouch[name]
  if touch and now() - touch.at < TOUCH_MS and self.stations[touch.number] then return touch.number end
  return (self:seatOf(name))
end

function Dealer:afterMove(name, amount, moved, wasHouse)
  if moved ~= 0 then
    local left = self:owedTo(name)
    session.noteMoved(name, moved, left, self.cabinet.title)
    if moved < 0 and not wasHouse then
      -- Tokens have come in, so anyone waiting on them may be paid now
      for key, owed in pairs(journal.owed()) do
        if owed > 0 and not isHouse(key) then self:want(key) end
      end
    end
  end
  -- A short move means this player's touch has run out, or their balance has. It waits for their next touch
  if moved ~= amount then self.wanted[name] = nil end
  self:mark()
end

--- Returns whether it went. A player with no computer to reach them on waits for their next touch.
function Dealer:sendOrder(order)
  local number = self:stationFor(order.name)
  local st = number and self.stations[number]
  if not st or st:quiet(now()) then return false end
  self.orderSeq = (self.orderSeq or 0) + 1
  local tag = ("Group %d.%d #%x.%d"):format(os.getComputerID(), st.id or number, now() % 268435456, self.orderSeq)
  if not st.remote then
    self:afterMove(order.name, order.amount, st:order(tag, order.name, order.amount), false)
    return true
  end
  -- Written down first: from here it stays open until that seat answers, through any reboot on either side
  if not journal.beginMove(order.key, order.amount, tag) then
    log("order " .. tag .. " could not be written down")
    return false
  end
  self.sentAt[tag] = now()
  st:order(tag, order.name, order.amount)
  return true
end

--- One book for the whole table: what the house owes a player pays what they owe a pot, and the other way round, with no tokens
-- moving. The host owed that much anyway, so it can pay the pot's winner from it. Never for a player with an order out, because its
-- answer has yet to come off the book.
function Dealer:netBook(moves)
  local busy = {}
  for _, move in pairs(moves) do busy[playerOf(move.name)] = true end
  for key in pairs(journal.owed()) do
    if not isHouse(key) and not busy[key] then
      local amount = journal.offset(key, key .. M.HOUSE)
      if amount > 0 then
        log("netted " .. amount .. " across the book for " .. key)
        self:mark()
        for name, owed in pairs(journal.owed()) do
          if owed > 0 and not isHouse(name) then self:want(name) end
        end
      end
    end
  end
end

--- The seat holding this order has been silent longer than a touch lasts, so it cannot be moving tokens, and it may be gone for good.
-- Only the ledger can answer now, and the player's touch on another computer lets that computer read it.
function Dealer:trace(tag, move, id, time)
  local name = playerOf(move.name)
  local touch = self.lastTouch[name]
  local st = touch and time - touch.at < TOUCH_MS and self.stations[touch.number]
  if not st or not st.remote or st.id == id or st:quiet(time) or time - move.at <= TOUCH_MS then return end
  self.traces[tag] = st.id
  st:trace(tag, name, move.amount, move.at)
end

--- Send again what has not been answered, and order what the book says can move now. self.moving says whether any of that is
-- still going on, which is what the final reveal waits for.
function Dealer:settleTick(time)
  if self.free then
    self.moving = false
    return
  end
  if time - (self.settledAt or 0) < SETTLE_EVERY_MS then return end
  self.settledAt = time
  local moves = journal.moves()
  self:netBook(moves)
  local payLater = false
  for tag, move in pairs(moves) do
    if move.amount < 0 and not isHouse(move.name) and time - move.at < COLLECT_WAIT_MS then payLater = true end
    local id = tonumber(tag:match("^Group %d+%.(%d+) "))
    local st = id and self.byId[id]
    if time - (self.sentAt[tag] or 0) > link.RESEND_MS and not self.localMode then
      self.sentAt[tag] = time
      if st then st:order(tag, playerOf(move.name), move.amount) end
      if id and (not st or time - st.heardAt > TOUCH_MS) then self:trace(tag, move, id, time) end
    end
  end
  local book = journal.owed()
  self.lastBook = book
  for name in pairs(self.wanted) do
    if not book[name] and not book[name .. M.HOUSE] then self.wanted[name] = nil end
  end
  -- Someone who cannot be reached waits for their next touch, and the plan goes again without them, so nobody waits on them
  local sent, again = false, true
  while again do
    again = false
    for _, order in ipairs(M.plan(journal.owed(), journal.moves(), self.wanted, payLater)) do
      if self:sendOrder(order) then
        sent = true
        if order.amount < 0 and not isHouse(order.key) then payLater = true end
      else
        self.wanted[order.name] = nil
        again = true
      end
    end
  end
  self.moving = next(moves) ~= nil or sent
end

--- A seat's answer. Only the seat the order went to or was traced through, only for an order still open, and only what could be true.
function Dealer:answer(st, tag, moved)
  local move = journal.moves()[tag]
  if not move then return end
  local traced = self.traces[tag] == st.id
  if tonumber(tag:match("^Group %d+%.(%d+) ")) ~= st.id and not traced then return end
  if moved * move.amount < 0 or math.abs(moved) > math.abs(move.amount) then
    log("order " .. tag .. " answered " .. moved .. " to " .. move.amount)
    return
  end
  journal.endMove(tag, moved)
  self.sentAt[tag], self.traces[tag] = nil, nil
  self:afterMove(playerOf(move.name), move.amount, moved, isHouse(move.name))
  -- The touch that let the ledger answer is still good, so whatever is left goes from there now
  if traced then
    log("order " .. tag .. " closed from the ledger: " .. moved)
    self:want(playerOf(move.name))
  end
end

--- Any touch at all proves a player is here, so it is the moment to try what is in the book for them.
function Dealer:touched(number, who, approved)
  local time = now()
  self.lastTouch[who] = { number = number, at = time, approved = approved }
  if self.viewers then self.viewers[number] = { name = who, at = time } end
  if self.free then return end
  local st = self.stations[number]
  if st and not st.remote and approved then books.resolve(who) end
  local debt, credit = self:sides(who)
  if debt > 0 or credit > 0 then
    self:want(who)
    -- A player back at a computer they never used has to approve it before anything can move. Only the book knows that is worth asking
    if st and not approved then
      st:ask(who)
      st:toast("Click [APPROVE] in chat, then tap again")
    end
  end
end

--- Close a hand's books: the only place a hand changes anyone's chips or tokens.
function Dealer:closeHand(round)
  local nets, names = self.plugin.rules.nets(round.state), {}
  for _, entry in ipairs(round.entries) do
    names[entry.name] = (names[entry.name] or 0) + (nets[entry.seat] or 0)
  end
  round.nets = names
  if self.free then
    -- Nothing to book: a free game's nets are all nought, and nothing ever goes in the owed book
    round.phase = "booked"
    journal.saveRound(round)
    self:finishBooks(round)
    return
  end
  round.phase = "settling"
  journal.saveRound(round)
  self:book(round)
  self:finishBooks(round)
end

--- Each net goes in the book. The tag holds the hand and the name, so a reboot cannot book one twice.
function Dealer:book(round)
  for name, amount in pairs(round.nets) do
    local key = (round.kind == "house" and not self.localMode) and (name .. M.HOUSE) or name
    journal.book(key, amount, "hand " .. round.id .. " " .. name)
  end
  round.phase = "booked"
  journal.saveRound(round)
end

--- Everything after the book. Each step can run again after a reboot and do nothing.
function Dealer:finishBooks(round)
  local plugin = self.cabinet.find(round.game)
  local dropped = {}
  if self.keep.closed ~= round.id then
    for _, entry in ipairs(round.entries) do
      local number, seat = self:seatOf(entry.name)
      if seat then
        if entry.stack then seat.stack = math.max(0, entry.stack + (round.nets[entry.name] or 0)) end
        seat.away = round.timedOut[entry.name] and (seat.away or 0) + 1 or 0
        if seat.away >= AWAY_LIMIT then
          self:seats()[number] = nil
          dropped[#dropped + 1] = entry.name
          log("dropped " .. entry.name .. " after " .. seat.away .. " hands away")
        end
      end
    end
    if plugin and plugin.rules.finish then
      local keep = self.keep.games and self.keep.games[round.game]
      if keep then
        local ok, err = pcall(plugin.rules.finish, round.state, keep)
        if not ok then log("finish failed: " .. tostring(err)) end
      end
    end
    if self.free then self:countWins(round, plugin) end
    -- The seats and the note that they are done land in one write of keep
    self.keep.closed = round.id
    self:save()
  end

  if self.free then
    for _, name in ipairs(dropped) do self:leaving(name) end
    round.phase = "closed"
    journal.saveRound(round)
    return
  end

  for name in pairs(round.nets) do self:want(name) end
  self.settledAt = 0
  self.exposure = 0
  if round.kind == "house" then net.setExposure(self.keep.host or wallet.hostName(), 0) end

  for _, entry in ipairs(round.entries) do
    local amount = round.nets[entry.name] or 0
    local wagered = self:wagered(round, entry)
    stats.record(entry.name, wagered, amount, round.id .. entry.name)
    session.record(entry.name, amount, round.id .. entry.name)
  end
  self.leaders = nil
  -- Noted before it is said. A crash in that gap loses a line on the hub, which is better than saying it twice
  if not round.told then
    round.told = true
    journal.saveRound(round)
    for _, entry in ipairs(round.entries) do
      local amount = round.nets[entry.name] or 0
      net.send("round", { game = self.cabinet.key .. "_" .. round.game, player = entry.name, wagered = self:wagered(round, entry), net = amount })
      log(("hand %s %s %s in=%d net=%d owed=%d%s"):format(round.id, round.game, entry.name, self:wagered(round, entry), amount,
        self:owedTo(entry.name), plugin and plugin.shoe and "" or (" seed=" .. round.seed)))
    end
  end
  for _, entry in ipairs(round.entries) do
    if round.timedOut[entry.name] or not self:seatOf(entry.name) then session.noteOwed(entry.name, self.cabinet.title) end
  end
  for _, name in ipairs(dropped) do self:leaving(name) end
  -- The hand stays in the journal until its result has been up: the money is done, but a reboot still has that to show
  round.phase = "closed"
  journal.saveRound(round)
end

--- A free table keeps only who played and who won, in its own keep. It lands in the same write that closes the round.
function Dealer:countWins(round, plugin)
  self.keep.wins = self.keep.wins or {}
  self.keep.played = self.keep.played or {}
  for _, entry in ipairs(round.entries) do
    local name = entry.name
    self.keep.played[name] = (self.keep.played[name] or 0) + 1
    local ok, result = false, nil
    if plugin then ok, result = pcall(plugin.rules.result, round.state, entry.seat) end
    if ok and type(result) == "table" and result.kind == "win" then self.keep.wins[name] = (self.keep.wins[name] or 0) + 1 end
  end
  log("game " .. round.id .. " " .. round.game .. " over")
end

--- What this player really had at stake, for the stats and the hub.
function Dealer:wagered(round, entry)
  local plugin = self.cabinet.find(round.game)
  if plugin and plugin.rules.risk then
    local ok, risk = pcall(plugin.rules.risk, round.state, entry.seat)
    if ok and type(risk) == "number" then return math.floor(risk) end
  end
  if round.spent and round.spent[entry.seat] then return round.spent[entry.seat] end
  return math.abs(round.nets[entry.name] or 0)
end

--- The end of a visit.
function Dealer:leaving(name)
  if self.free then return end
  session.noteOwed(name, self.cabinet.title)
  local entry = session.close(name)
  if not entry then return end
  chat.tell(name, "Your session at " .. self.cabinet.title .. ": " .. session.text(entry))
end

--- A reboot can lose a visit its ending. If nobody is sitting in it, it is closed here.
function Dealer:closeStale(time)
  if self.free then return end
  for name, at in pairs(session.open()) do
    if time - at > SESSION_STALE_MS and not self:seatOf(name) then self:leaving(name) end
  end
end

--- Anything a reboot interrupted.
function Dealer:recover()
  if self.localMode then books.resolve() end
  local round = journal.loadRound()
  for name in pairs(journal.owed()) do self:want(playerOf(name)) end
  if not round then return end
  local plugin = self.cabinet.find(round.game)
  log("resuming hand " .. tostring(round.id) .. " phase " .. tostring(round.phase))
  if plugin then self:setGame(round.game) end
  if round.phase == "open" then
    if not plugin then
      log("hand " .. tostring(round.id) .. " needs a game this computer does not have")
      return
    end
    self.round, self.mode = round, "hand"
    self.deadlines, self.queue = {}, {}
    self:syncTurns()
    self:refreshPublic()
    return
  end
  if round.phase == "settling" then self:book(round) end
  if round.phase ~= "closed" then self:finishBooks(round) end
  if not plugin then
    journal.clearRound()
    return
  end
  -- The tokens are settled or on their way, so only the showing is left. Screens have nothing of the hand to hold, so there is no hold
  self.finished, self.finalEvents = round, round.finalEvents
  self:reveal()
end

-- ------------------------------------------------------------------ sitting down

--- What a player can really stake: their balance, with anything in the book for or against them.
function Dealer:covers(name)
  local balance = wallet.balance(name)
  if not balance then return nil end
  return balance + self:owedTo(name)
end

function Dealer:canPlay(seat)
  if self.free then return true end
  if self.plugin.stakes then return self.keep.stake ~= nil and seat.stack >= self.keep.stake * (self.plugin.stakeCover or 1) end
  return seat.stack >= self.plugin.ante
end

--- Why this player cannot have this seat now, or nil. Asked when a panel opens and again when it is pressed, because a panel stays
-- up while the table changes around it. One player, one seat: a table's nets are by name.
function Dealer:seatRefused(number, who)
  if self:seatOf(who) then return "You already have a seat" end
  if self:seat(number) then return "This seat is taken" end
  if #self:seatedNames() >= self.plugin.maxSeats then return "This table is full" end
  if self.free then return nil end
  local debt = self:sides(who)
  if debt > 0 then return short(who) .. " owes " .. ui.group(debt) .. " from a past hand" end
  return nil
end

function Dealer:readyCount()
  local total = 0
  for number = 1, M.MAX_SEATS do
    local seat = self:seat(number)
    if seat and self:canPlay(seat) then total = total + 1 end
  end
  return total
end

--- Open the panel a sit-down needs next. approved says the player has cleared chat approval on this computer.
function Dealer:sitDown(number, who, approved)
  local st = self.stations[number]
  st.sub = nil
  local refused = self:seatRefused(number, who)
  if self.free then
    -- Free play: a seat is a name. No wallet, no approval, no buy-in
    if refused then
      self:toast(number, refused)
    else
      self:seats()[number] = { name = who, stack = 0, away = 0 }
      self:save()
      log("sit " .. who .. " seat " .. number)
    end
    self:mark()
    return
  end
  if not wallet.available() then
    self:toast(number, "The economy is offline")
  elseif refused then
    self:toast(number, refused)
  elseif not approved then
    st.sub = { kind = "approve", who = who, deadline = now() + APPROVE_MS }
  elseif self.plugin.kind == "house" then
    self:seats()[number] = { name = who, stack = 0, away = 0 }
    self:save()
    log("sit " .. who .. " seat " .. number)
    st.sub = nil
  elseif self.plugin.stakes then
    self:openStake(number, who)
  else
    self:openBuyIn(number, who, false)
  end
  self:mark()
end

function Dealer:openBuyIn(number, who, topUp)
  local st = self.stations[number]
  local _, seat = self:seatOf(who)
  local base = seat and seat.stack or 0
  local balance = self:covers(who)
  local limit = balance and math.min(self.plugin.maxStack - base, balance - base) or 0
  local least = topUp and 1 or self.plugin.minBuy
  if limit < least then
    st.sub = nil
    self:toast(number, topUp and "Nothing more to top up with" or ("You need " .. ui.group(least) .. " in your wallet"))
    return
  end
  st.sub = { kind = "buyin", who = who, amount = topUp and 0 or least, limit = limit, least = least, topUp = topUp,
    deadline = now() + PANEL_MS }
end

function Dealer:confirmBuyIn(number, sub)
  local st = self.stations[number]
  local _, seat = self:seatOf(sub.who)
  local base = seat and seat.stack or 0
  local balance = self:covers(sub.who)
  st.sub = nil
  local refused = not sub.topUp and self:seatRefused(number, sub.who)
  if refused then
    self:toast(number, refused)
    return
  end
  if not balance or sub.amount < sub.least or sub.amount > math.min(self.plugin.maxStack - base, balance - base) then
    self:toast(number, "Your balance has changed")
    return
  end
  if sub.topUp then
    seat.stack = seat.stack + sub.amount
  else
    self:seats()[number] = { name = sub.who, stack = sub.amount, away = 0 }
  end
  self:save()
  log((sub.topUp and "top up " or "sit ") .. sub.who .. " " .. sub.amount)
end

--- A match game: the first player names the stake and the second takes it or leaves it. Each stake is checked against the balance.
function Dealer:openStake(number, who)
  local st = self.stations[number]
  local cover = self:covers(who) or 0
  local multiple = self.plugin.stakeCover or 1
  if self.keep.stake then
    if cover < self.keep.stake * multiple then
      st.sub = nil
      self:toast(number, "The stake is " .. ui.group(self.keep.stake))
      return
    end
    st.sub = { kind = "accept", who = who, deadline = now() + PANEL_MS }
    return
  end
  if cover < (self.plugin.stakes[1] or 0) * multiple then
    st.sub = nil
    self:toast(number, "You need " .. ui.group(self.plugin.stakes[1] * multiple) .. " in your wallet")
    return
  end
  st.sub = { kind = "stake", who = who, cover = cover, deadline = now() + PANEL_MS }
end

--- Whether this stake can be taken here. A seated player already in this seat is only choosing a stake for a new game.
function Dealer:canTake(number, who, stake)
  local refused = self:seatOf(who) ~= number and self:seatRefused(number, who)
  local short_of = (self:covers(who) or 0) < stake * (self.plugin.stakeCover or 1)
  self.stations[number].sub = nil
  if refused then self:toast(number, refused) end
  if short_of and not refused then self:toast(number, "The stake is " .. ui.group(stake)) end
  return not refused and not short_of
end

function Dealer:seatForStake(number, who)
  local cover = self:covers(who) or 0
  self:seats()[number] = { name = who, stack = math.min(self.plugin.maxStack, cover), away = 0 }
  self:save()
  log("sit " .. who .. " stake " .. tostring(self.keep.stake))
end

--- A stake panel stands on the game and the stake as they were when it opened. When those change it turns into the panel that fits
-- now, so nobody names a stake over one already taken, or takes one that has gone. With nobody seated there is no stake to take.
function Dealer:checkPanels()
  if self.keep.stake and #self:seatedNames() == 0 then
    self.keep.stake = nil
    self:save()
    self:mark()
  end
  for number, st in pairs(self.stations) do
    local sub = st.sub
    if sub and (sub.kind == "stake" or sub.kind == "accept") then
      local stakes = self.plugin and self.plugin.stakes
      if not stakes then
        st.sub = nil
        self:mark()
      elseif (sub.kind == "stake") == (self.keep.stake ~= nil) then
        self:openStake(number, sub.who)
        self:mark()
      end
    end
  end
end

--- One press on a panel that belongs to one player.
function Dealer:subInput(number, input)
  local st, sub, id = self.stations[number], self.stations[number].sub, input.id
  if sub.kind == "page" then
    if id == "close" then st.sub = nil end
    return
  end
  if input.who ~= sub.who then return end
  sub.deadline = now() + (sub.kind == "approve" and APPROVE_MS or PANEL_MS)
  if id == "cancel" then
    st.sub = nil
  elseif sub.kind == "approve" then
    if id == "approved" and input.approved then self:sitDown(number, sub.who, true) end
  elseif sub.kind == "buyin" then
    if id == "chip" and type(input.value) == "number" then
      sub.amount = math.min(sub.limit, sub.amount + math.max(0, input.value))
    elseif id == "max" then
      sub.amount = sub.limit
    elseif id == "clear" then
      sub.amount = 0
    elseif id == "confirm" then
      self:confirmBuyIn(number, sub)
    end
  elseif sub.kind == "stake" then
    if self.keep.stake then
      -- Named by the other player since this panel opened: there is nothing left to name, only to take or leave
      self:openStake(number, sub.who)
    elseif id == "stake" and type(input.value) == "number" then
      for _, stake in ipairs(self.plugin.stakes) do
        if stake == input.value and stake * (self.plugin.stakeCover or 1) <= sub.cover and self:canTake(number, sub.who, stake) then
          self.keep.stake = stake
          self:seatForStake(number, sub.who)
        end
      end
    end
  elseif sub.kind == "accept" then
    if id == "accept" and self:canTake(number, sub.who, self.keep.stake) then self:seatForStake(number, sub.who) end
  end
end

-- ------------------------------------------------------------------ house bets

function Dealer:bet(number)
  self.bets[number] = self.bets[number] or { total = 0, spots = {}, ready = false }
  return self.bets[number]
end

--- What the host can stand behind for a round: the same share of the reserve-protected balance any table offers.
function Dealer:hostRoom()
  local host = wallet.hostName()
  return math.floor(limits.protected(wallet.hostBalance(), net.otherExposure(host)) * limits.LIABILITY_SHARE), host
end

local function entryOf(number, seat, bet)
  local entry = { seat = number, name = seat.name, bet = bet.total }
  if next(bet.spots) then
    entry.bets = {}
    for id, amount in pairs(bet.spots) do entry.bets[id] = amount end
  end
  return entry
end

--- The most this seat may add now, from their balance and this game's cap.
function Dealer:betRoom(number)
  local seat, bet = self:seat(number), self:bet(number)
  local room = (self:covers(seat.name) or 0) - bet.total
  if self.plugin.maxBet then room = math.min(room, self.plugin.maxBet - bet.total) end
  return math.max(0, room)
end

--- The host must cover every seat's best case. Bets are shrunk to fit, and refused when they cannot. Returns the entries.
function Dealer:fitBets(entries)
  local room, host = self:hostRoom()
  local rules = self.plugin.rules
  local function total()
    local sum = 0
    for _, entry in ipairs(entries) do sum = sum + rules.maxWin(entry) end
    return sum
  end
  local want = total()
  if want > room and want > 0 then
    local share = room / want
    for number = #entries, 1, -1 do
      local entry = entries[number]
      entry.bet = 0
      if entry.bets then
        for id, amount in pairs(entry.bets) do
          entry.bets[id] = math.floor(amount * share)
          if entry.bets[id] <= 0 then entry.bets[id] = nil end
          entry.bet = entry.bet + (entry.bets[id] or 0)
        end
      else
        entry.bet = math.floor(self.bets[entry.seat].total * share)
      end
      if entry.bet < self.plugin.minBet then
        self:toast(entry.seat, "The table cannot cover that bet")
        table.remove(entries, number)
      else
        self:toast(entry.seat, "Your bet was cut to " .. ui.group(entry.bet))
      end
    end
    -- Rounding can only leave it under, but a game's maxWin need not be linear, so this is checked again
    while #entries > 0 and total() > room do
      local last = table.remove(entries)
      self:toast(last.seat, "The table cannot cover that bet")
    end
  end
  self.exposure = total()
  net.setExposure(host, self.exposure)
  return entries
end

-- ------------------------------------------------------------------ a hand

--- Who plays this hand, as Poker Table does: each stack held to what the player could really pay, and anyone sitting it out one step
-- closer to losing their seat. House games take whoever has a bet down.
function Dealer:entries()
  local plugin, entries = self.plugin, {}
  if plugin.kind == "house" then
    for number = 1, M.MAX_SEATS do
      local seat, bet = self:seat(number), self.bets[number]
      if seat and bet and bet.total >= plugin.minBet then
        local cover = self:covers(seat.name)
        if cover and bet.total <= cover then
          entries[#entries + 1] = entryOf(number, seat, bet)
        else
          self:toast(number, "Your balance has changed")
        end
      end
    end
    return self:fitBets(entries)
  end
  for number = 1, M.MAX_SEATS do
    local seat = self:seat(number)
    if seat then
      local cover = not self.free and self:covers(seat.name)
      if cover then
        seat.stack = plugin.stakes and math.min(plugin.maxStack, math.max(0, cover)) or math.min(seat.stack, math.max(0, cover))
      end
      if self:canPlay(seat) and #entries < plugin.maxSeats then
        entries[#entries + 1] = { seat = number, name = seat.name, stack = seat.stack, stake = self.keep.stake }
      end
    end
  end
  return entries
end

--- A shoe that has just been replaced is finished, so its seed may be shown. See table.lua.
local function startShoe(keep, seed, commit)
  if keep.shoeSeed then
    keep.lastShoe = { seed = keep.shoeSeed, commit = keep.shoeCommit }
    log("shoe finished hash=" .. keep.shoeCommit .. " seed=" .. keep.shoeSeed)
  end
  keep.shoeSeed, keep.shoeCommit, keep.shuffled = seed, commit, nil
end

function Dealer:deal()
  local plugin = self.plugin
  self.dealAt = nil
  local entries = self:entries()
  if #entries < plugin.minSeats then
    self:save()
    self.bets = {}
    self:mark()
    return false
  end

  local taken = {}
  for _, entry in ipairs(entries) do taken[entry.seat] = true end
  for number = 1, M.MAX_SEATS do
    local seat = self:seat(number)
    if seat and not taken[number] then
      seat.away = (seat.away or 0) + 1
      if seat.away >= AWAY_LIMIT then
        self:seats()[number] = nil
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

  local keep = self:gameKeep()
  local seed = rng.freshSeed(tostring(self.keep.hands))
  local stream = rng.new(seed)
  if plugin.shoe and not keep.shoeCommit then keep.shoe = nil end
  local dealt, state, events = pcall(plugin.rules.new, entries, button, stream, keep)
  if not dealt then
    -- A game that cannot deal must not take the table with it. Everyone stays seated, and it tries again after the next countdown
    log("deal failed: " .. tostring(state))
    self.bets = {}
    self:mark()
    return false
  end
  local commit = rng.sha256(seed)
  if plugin.shoe and keep.shuffled then startShoe(keep, seed, commit) end
  local spent = {}
  for _, entry in ipairs(entries) do spent[entry.seat] = entry.bet or 0 end
  local round = {
    id = ("%x"):format(now() % 268435456),
    game = plugin.id,
    kind = plugin.kind,
    seed = seed,
    commit = plugin.shoe and keep.shoeCommit or commit,
    rng = stream:serial(),
    state = state,
    entries = entries,
    spent = spent,
    phase = "open",
    timedOut = {},
  }
  self:save()
  journal.saveRound(round)
  self.round, self.mode = round, "hand"
  self.bets, self.deadlines, self.queue, self.playing = {}, {}, {}, nil
  self.publicView, self.computerAt = nil, nil
  if plugin.rules.done(state) then
    -- A round can be over as it is dealt, such as every hand a natural. It still settles before anyone sees it
    self:endHand(round, events)
  else
    self:refreshPublic()
    self:queueEvents(events)
    self:syncTurns()
  end
  self:mark()
  return true
end

--- This seat's view for whoever may look at it. Built by the game, field by field, so nothing secret can come along.
function Dealer:viewFor(seat)
  local ok, view = pcall(self.plugin.rules.viewFor, self.round.state, seat)
  if ok then return view end
  log("view failed: " .. tostring(view))
  return {}
end

function Dealer:refreshPublic()
  self.publicView = self:viewFor(nil)
end

--- Events belong to everyone, so a game keeps secrets out of them. The dealer plays them on its wall and seats on theirs.
function Dealer:queueEvents(events)
  local seconds = 0
  for _, ev in ipairs(events or {}) do
    self.queue[#self.queue + 1] = ev
    local ok, length = pcall(self.plugin.event or function() return 0.1 end, ev)
    seconds = seconds + ((ok and type(length) == "number") and length or 0.1)
    for number in pairs(self.stations) do
      local st = self.stations[number]
      st.events = st.events or {}
      st.events[#st.events + 1] = ev
    end
  end
  self.showUntil = math.max(self.showUntil or 0, now() + math.floor(seconds * 1000))
end

--- How long this seat has from now. A game can give each wait its own clock with rules.turnMs(state, seat), such as a short one
-- for answering a trade and a long one for a whole turn. Without it, the game's turnMs.
function Dealer:turnMs(seat)
  local rules = self.plugin.rules
  if rules.turnMs then
    local ok, ms = pcall(rules.turnMs, self.round.state, seat)
    if ok and type(ms) == "number" and ms > 0 then return math.floor(ms) end
  end
  return self.plugin.turnMs
end

--- The clock follows whoever the game is waiting on.
function Dealer:syncTurns()
  local waiting = {}
  local ok, list = pcall(self.plugin.rules.waitingOn, self.round.state)
  if not ok then
    log("waitingOn failed: " .. tostring(list))
    list = {}
  end
  local start = math.max(now(), self.showUntil or 0)
  for _, seat in ipairs(list) do
    waiting[seat] = true
    if not self.deadlines[seat] then
      local ms = self:turnMs(seat)
      self.deadlines[seat] = start + ms
      self.clockTotal = self.clockTotal or {}
      self.clockTotal[seat] = ms
    end
  end
  for seat in pairs(self.deadlines) do
    if not waiting[seat] then self.deadlines[seat] = nil end
  end
  self.waiting = waiting
  -- Waiting on nobody with the round not over is the computer's own move: a house's draw, or a roll with no shooter
  self.computerAt = next(waiting) == nil and (self.computerAt or (start + COMPUTER_MS)) or nil
end

--- The rules say it is over. The money moves before the reveal plays, so nothing that happens during it can change the result.
function Dealer:endHand(round, events)
  self.finalEvents, round.finalEvents = events, events
  self.finished, self.round = round, nil
  self.mode = "hold"
  self.holdUntil = now() + SETTLE_WAIT_MS
  self.deadlines, self.waiting, self.computerAt = {}, {}, nil
  -- From here the book and the stacks hold the result, and the cards have not turned
  self.heldStrip = nil
  self.heldStrip = self:stripSeats(journal.owed())
  local ok, err = pcall(self.closeHand, self, round)
  if not ok then log("closing a hand failed: " .. tostring(err)) end
  self.settledAt = 0
  self:settleTick(now())
end

--- A press or a timeout. Illegal input does nothing, and the game's rules are what say so.
function Dealer:apply(seat, id, value, timedOut)
  local round = self.round
  local rules = self.plugin.rules
  local stream = rng.restore(round.rng)
  local ok, events = pcall(rules.act, round.state, seat, id, value, stream)
  if not ok then
    log("act failed: " .. tostring(events))
    return false
  end
  if not events or #events == 0 then return false end
  local entryName = nil
  for _, entry in ipairs(round.entries) do
    if entry.seat == seat then entryName = entry.name end
  end
  -- A clock that closes betting is no missed turn for a seat that bet: a game says so with rules.present, and it never counts as away
  if timedOut and entryName and not (rules.present and rules.present(round.state, seat)) then
    round.timedOut[entryName] = true
    log("hand " .. round.id .. " " .. entryName .. " timed out: " .. tostring(id))
  end
  round.rng = stream:serial()
  if rules.done(round.state) then
    self:endHand(round, events)
  else
    journal.saveRound(round)
    self:refreshPublic()
    self:queueEvents(events)
    self:syncTurns()
  end
  self:mark()
  return true
end

--- Whether this seat can cover what a button costs.
function Dealer:canCover(seat, cost)
  if self.free or not cost or cost <= 0 then return true end
  local round = self.round
  local name
  for _, entry in ipairs(round.entries) do
    if entry.seat == seat then name = entry.name end
  end
  local cover = name and self:covers(name)
  return cover ~= nil and cover - (round.spent[seat] or 0) >= cost
end

function Dealer:handInput(number, input)
  local round = self.round
  if not self.waiting[number] then return end
  local rules = self.plugin.rules
  local cost, offered = 0, false
  local ok, actions = pcall(rules.actions, round.state, number)
  if ok and type(actions) == "table" then
    for _, action in ipairs(actions) do
      if action.id == input.id and (action.value == nil or action.value == input.value) then
        offered = true
        cost = action.cost or 0
      end
    end
  end
  if offered and not self:canCover(number, cost) then
    self:toast(number, "Your balance will not cover that")
    return
  end
  local before = round.spent[number] or 0
  round.spent[number] = before + cost
  if not self:apply(number, input.id, input.value, false) then round.spent[number] = before end
end

function Dealer:handTick(time)
  if not self.round then return end
  if self.computerAt and time >= self.computerAt then
    self.computerAt = nil
    local ok, id, value = pcall(self.plugin.rules.auto, self.round.state, nil)
    if not ok or not self:apply(nil, id, value, false) then
      log("the computer's move did nothing: " .. tostring(id))
      self.computerAt = time + COMPUTER_MS
    end
    return
  end
  for seat, deadline in pairs(self.deadlines) do
    if time >= deadline then
      local ok, id, value = pcall(self.plugin.rules.auto, self.round.state, seat)
      self.deadlines[seat] = nil
      if ok then
        if not self:apply(seat, id, value, true) then
          log("auto " .. tostring(id) .. " for seat " .. seat .. " did nothing")
          self.deadlines[seat] = time + self.plugin.turnMs
        end
      else
        log("auto failed: " .. tostring(id))
        self.deadlines[seat] = time + self.plugin.turnMs
      end
      return
    end
  end
end

-- ------------------------------------------------------------------ what each seat sees

local function base(self, number)
  local seat, plugin = self:seat(number), self.plugin
  return {
    kind = "panel", number = number, game = plugin and plugin.id or false, felt = plugin and plugin.felt or "green",
    title = plugin and plugin.title or self.cabinet.title, name = seat and seat.name or false, buttons = {},
  }
end

local function pagePanel(screen, sub)
  screen.title = sub.title or screen.title
  screen.lines = sub.lines
  screen.buttons = { { id = "close", label = "DONE", color = "win", textColor = "ink" } }
  return screen
end

function Dealer:subScreen(number, st, screen)
  local sub = st.sub
  if sub.kind == "page" then return pagePanel(screen, sub) end
  screen.only = sub.who
  if sub.kind == "approve" then
    screen.lines = { { short(sub.who), "gold", 1 }, { "Click [APPROVE] in chat to use your wallet here, then tap this screen.", "text" } }
    screen.buttons = { { id = "cancel", label = "CANCEL", color = "red" } }
    screen.approve = sub.who
  elseif sub.kind == "buyin" then
    screen.lines = { { sub.topUp and "TOP UP" or "BUY IN", "gold", 1 }, { ui.group(sub.amount), "gold", 2 },
      { ("Up to %s. Nothing is taken until a hand ends."):format(ui.group(sub.limit)), "mute" } }
    local tiles = {}
    for _, value in ipairs(self.plugin.chips or CHIPS) do
      if value <= sub.limit then
        tiles[#tiles + 1] = { id = "chip", value = value, label = ui.group(value), color = "accent", textColor = "ink",
          disabled = sub.amount + value > sub.limit }
      end
    end
    screen.tiles = tiles
    screen.buttons = {
      { id = "cancel", label = "CANCEL", color = "red" },
      { id = "max", label = "MAX", color = "panel2" },
      { id = "clear", label = "CLEAR", color = "panel2" },
      { id = "confirm", label = sub.topUp and "ADD" or "SIT", color = "win", textColor = "ink", disabled = sub.amount < sub.least },
    }
  elseif sub.kind == "stake" then
    screen.lines = { { "NAME THE STAKE", "gold", 1 }, { "The other player takes it or leaves it. Nothing moves until the match ends.", "mute" } }
    local tiles = {}
    for _, value in ipairs(self.plugin.stakes) do
      tiles[#tiles + 1] = { id = "stake", value = value, label = ui.group(value), color = "accent", textColor = "ink",
        sub = self.plugin.stakeNote and self.plugin.stakeNote(value) or nil, disabled = value * (self.plugin.stakeCover or 1) > sub.cover }
    end
    screen.tiles = tiles
    screen.buttons = { { id = "cancel", label = "CANCEL", color = "red" } }
  elseif sub.kind == "accept" then
    screen.lines = { { "THE STAKE IS", "gold", 1 }, { ui.group(self.keep.stake), "gold", 2 }, { "Nothing moves until the match ends.", "mute" } }
    if self.plugin.stakeNote then table.insert(screen.lines, 3, { self.plugin.stakeNote(self.keep.stake), "text" }) end
    screen.buttons = {
      { id = "cancel", label = "NO", color = "red" },
      { id = "accept", label = "PLAY", color = "win", textColor = "ink" },
    }
  end
  return screen
end

function Dealer:emptyScreen(screen)
  local plugin = self.plugin
  if not plugin then
    screen.lines = { { self.cabinet.title, "gold", 1 }, { "No game is on this table yet.", "text" } }
    return screen
  end
  screen.lines = { { plugin.title, "gold", 2 }, { plugin.tagline or "", "text" } }
  if self.mode ~= "lobby" then screen.note = "A hand is on. Sit now for the next one." end
  local full = #self:seatedNames() >= plugin.maxSeats
  screen.tiles = { { id = "sit", label = full and "FULL" or "SIT DOWN", color = "win", textColor = "ink", disabled = full } }
  screen.buttons = { { id = "rules", label = "RULES", color = "blue" } }
  if not self.free and not wallet.available() then screen.note, screen.warn = "Economy offline", true end
  return screen
end

--- The line on a seat about what the book holds for this player. Either side alone is worth a word.
function Dealer:owedNote(screen, name, book, debtOnly)
  if self.free then return end
  local debt, credit = self:sides(name, book)
  if debt > 0 then
    screen.note, screen.warn = "You owe " .. ui.group(debt) .. ". Tap to settle", true
  elseif credit > 0 and not debtOnly then
    screen.note, screen.warn = "You are owed " .. ui.group(credit) .. ". Tap to collect", true
  end
end

--- A seated player between games at a free table: no money on it anywhere, and START for whoever does not want to wait.
function Dealer:freeLobbyScreen(seat, screen)
  local plugin = self.plugin
  screen.badge = "FREE"
  local seated = #self:seatedNames()
  local wins = (self.keep.wins or {})[seat.name] or 0
  screen.lines = { { plugin.title, "gold", 2 }, { plugin.tagline or "", "text" },
    { "Free to play. " .. (wins == 1 and "1 win" or (ui.group(wins) .. " wins")) .. " here so far.", "mute" } }
  if self.dealAt then
    screen.countdownText = "The game starts in %ds. More can sit until then"
    screen.countdown = math.max(0, self.dealAt - now())
  elseif seated < plugin.minSeats then
    screen.note = "Waiting for another player"
  end
  screen.buttons = { { id = "leave", label = "LEAVE", color = "red" }, { id = "rules", label = "RULES", color = "blue" },
    { id = "deal", label = "START", color = "win", textColor = "ink", disabled = seated < plugin.minSeats } }
  return screen
end

function Dealer:lobbyScreen(number, seat, screen, book)
  local plugin = self.plugin
  if self.free then return self:freeLobbyScreen(seat, screen) end
  screen.owed = self:owedTo(seat.name, book)
  self:owedNote(screen, seat.name, book)
  if plugin.kind == "players" then
    screen.money = seat.stack
    local ready = self:readyCount()
    screen.lines = { { plugin.title, "gold", 2 }, { "You have " .. ui.group(seat.stack) .. " on the table", "text" } }
    if self.keep.stake then screen.lines[#screen.lines + 1] = { "The stake is " .. ui.group(self.keep.stake), "text" } end
    if self.dealAt then
      screen.countdownText = "Next hand in %ds"
      screen.countdown = math.max(0, self.dealAt - now())
    elseif not screen.note then
      -- Seated with nothing that can play: a game change leaves a player here, and nothing deals until they answer
      local stuck = not self:canPlay(seat)
      screen.note = not stuck and "Waiting for another player" or (plugin.stakes and "Tap STAKE to play this game" or "Tap CHIPS to buy in")
      screen.warn = stuck
    end
    screen.buttons = { { id = "leave", label = "LEAVE", color = "red" }, { id = "rules", label = "RULES", color = "blue" } }
    if not plugin.stakes then
      screen.buttons[3] = { id = "topup", label = "CHIPS", color = "blue" }
    elseif not self:canPlay(seat) then
      screen.buttons[3] = { id = "topup", label = "STAKE", color = "blue" }
    end
    screen.buttons[#screen.buttons + 1] = { id = "deal", label = "DEAL", color = "win", textColor = "ink",
      disabled = ready < plugin.minSeats or not self:canPlay(seat) }
    return screen
  end

  local bet = self:bet(number)
  screen.money = bet.total
  local spots, tiles = plugin.spots, {}
  if spots then
    for _, spot in ipairs(spots) do
      local amount = bet.spots[spot.id] or 0
      tiles[#tiles + 1] = { id = "spot", value = spot.id, label = spot.label, sub = amount > 0 and ui.group(amount) or spot.sub,
        color = amount > 0 and "gold" or (spot.color or "accent"), textColor = "ink" }
    end
  end
  screen.tiles = tiles
  screen.lines = { { bet.ready and "BET IS IN" or "PLACE YOUR BET", "gold", 1 }, { ui.group(bet.total), "gold", spots and 1 or 2 } }
  local room = self:betRoom(number)
  local list = limits.chips(math.min(room + bet.total, plugin.maxBet or room + bet.total))
  bet.chip = bet.chip or list[1]
  local buttons = {}
  for _, value in ipairs(list) do
    buttons[#buttons + 1] = { id = "chip", value = value, label = ui.group(value), color = bet.chip == value and "gold" or "accent",
      textColor = "ink", disabled = not spots and value > room }
  end
  buttons[#buttons + 1] = { id = "clear", label = "CLEAR", color = "panel2" }
  buttons[#buttons + 1] = { id = "leave", label = "LEAVE", color = "red" }
  buttons[#buttons + 1] = { id = "rules", label = "RULES", color = "blue" }
  buttons[#buttons + 1] = { id = "ready", label = "READY", color = "win", textColor = "ink", disabled = bet.total < plugin.minBet }
  screen.buttons = buttons
  if self.dealAt then
    screen.countdownText = "Betting closes in %ds"
    screen.countdown = math.max(0, self.dealAt - now())
  end
  return screen
end

--- Whether this seat played this hand, and whether its player's private view may go up on it. A Duel wall with nobody at it shows only
-- what anyone may see, right to the end of the hand: a wall that has gone public stays that way until its own player taps.
function Dealer:whoSees(round, number, seat)
  local playing = false
  for _, entry in ipairs(round.entries) do
    if entry.seat == number and seat and entry.name == seat.name then playing = true end
  end
  local private = playing
  if playing and self.viewers then
    local viewer = self.viewers[number]
    private = viewer ~= nil and viewer.name == seat.name and now() - viewer.at < VIEWER_MS
  end
  return playing, private
end

--- The hand from this seat, or from outside it.
function Dealer:handScreen(number, seat, screen, book)
  local round = self.round
  local playing, private = self:whoSees(round, number, seat)
  if playing and not private then screen.note = "Tap to see your hand" end
  screen.kind = "game"
  screen.view = self:viewFor(private and number or nil)
  screen.hash = round.commit:sub(1, HASH_SHOWN)
  -- A house game has no stack, so the bar says what is riding on this round, as it does while they bet
  if seat and self.free then
    screen.badge = "FREE"
  elseif seat then
    screen.money = self.plugin.kind == "house" and (round.spent[number] or 0) or seat.stack
  end
  local rules = self.plugin.rules
  if private and self.waiting[number] then
    screen.tap = true
    local ok, actions = pcall(rules.actions, round.state, number)
    local buttons = {}
    if ok and type(actions) == "table" then
      for _, action in ipairs(actions) do
        local item = {}
        for key, value in pairs(action) do item[key] = value end
        if not self:canCover(number, action.cost) then item.disabled = true end
        buttons[#buttons + 1] = item
      end
    end
    screen.buttons = buttons
    local deadline = self.deadlines[number]
    if deadline then
      screen.left, screen.total = math.max(0, deadline - now()), (self.clockTotal and self.clockTotal[number]) or self.plugin.turnMs
    end
  elseif playing then
    self:owedNote(screen, seat.name, book, true)
  else
    screen.tiles = {}
  end
  return screen
end

function Dealer:resultScreen(number, seat, screen, book)
  local round = self.finished
  local plugin = self.cabinet.find(round.game)
  screen.kind = "game"
  screen.hash = round.commit:sub(1, HASH_SHOWN)
  local playing, private = self:whoSees(round, number, seat)
  local ok, view = pcall(plugin.rules.viewFor, round.state, private and number or nil)
  screen.view = ok and view or {}
  if seat then
    -- While the last cards turn the player's money stays as it stood, because the new figure is the result
    local last = self.stations[number].last
    local revealing = self.mode == "reveal" and last and last.kind == "game"
    if self.free then
      screen.badge = "FREE"
    else
      screen.money = revealing and last.money or (plugin.kind == "house" and (round.spent[number] or 0) or seat.stack)
    end
    if self.mode == "result" then
      if playing then
        local good, result = pcall(plugin.rules.result, round.state, private and number or nil)
        if good then screen.result = result end
        self:owedNote(screen, seat.name, book)
        if not private then screen.note, screen.warn = "Tap to see your hand", false end
      end
      screen.buttons = { { id = "fair", label = "FAIR?", color = "panel2" } }
      if playing and not self.nexted[seat.name] then
        screen.buttons[2] = { id = "next", label = "NEXT", color = "win", textColor = "ink" }
      elseif playing then
        screen.note, screen.warn = "Waiting for the others", false
      end
    end
  end
  return screen
end

function Dealer:voteScreen(number, screen)
  local vote = self.vote
  local plugin = self.cabinet.find(vote.game)
  screen.lines = { { "CHANGE GAME?", "gold", 1 }, { plugin and plugin.title or vote.game, "gold", 1 },
    { "Everyone seated must agree.", "text" } }
  local seat = self:seat(number)
  if vote.yes[seat.name] then
    screen.note = "Waiting for the others"
  else
    screen.buttons = {
      { id = "voteno", label = "NO", color = "red" },
      { id = "voteyes", label = "YES", color = "win", textColor = "ink" },
    }
  end
  return screen
end

--- The picker for a table with no wall of its own, a Duel.
function Dealer:pickTiles()
  local tiles = {}
  for _, plugin in ipairs(self.cabinet.list) do
    tiles[#tiles + 1] = { id = "pick", value = plugin.id, label = plugin.title, color = plugin.id == self.keep.game and "gold" or "panel2",
      textColor = plugin.id == self.keep.game and "ink" or "text" }
  end
  return tiles
end

function Dealer:screenFor(number, book)
  local st = self.stations[number]
  local seat, screen = self:seat(number), base(self, number)
  if self.mode == "hold" and st.last and st.last.kind == "game" then
    for key, value in pairs(st.last) do screen[key] = value end
    screen.buttons, screen.tap, screen.events, screen.left, screen.total = {}, false, nil, nil, nil
    screen.note, screen.warn = "Settling...", false
    return screen
  end
  if st.sub then return self:subScreen(number, st, screen) end
  if self.vote and seat and self.mode == "lobby" then return self:voteScreen(number, screen) end
  if self.mode ~= "lobby" and (self.round or self.finished) then
    if not seat and not self.localMode then return self:emptyScreen(screen) end
    if self.round then return self:handScreen(number, seat, screen, book) end
    return self:resultScreen(number, seat, screen, book)
  end
  if seat then return self:lobbyScreen(number, seat, screen, book) end
  self:emptyScreen(screen)
  if self.localMode and #self.cabinet.list > 1 and #self:seatedNames() == 0 then
    for _, tile in ipairs(self:pickTiles()) do screen.tiles[#screen.tiles + 1] = tile end
  end
  return screen
end

--- Volatile fields do not count as a change: a countdown must not make a seat redraw, or a press in flight look stale.
local function signature(screen)
  local left, total, countdown, events = screen.left, screen.total, screen.countdown, screen.events
  screen.left, screen.total, screen.countdown, screen.events, screen.n, screen.gen = nil, nil, nil, nil, nil, nil
  local ok, text = pcall(textutils.serialize, screen, { compact = true })
  screen.left, screen.total, screen.countdown, screen.events = left, total, countdown, events
  return ok and text or tostring(now())
end

--- Send every station what it should see, if that has changed or it is time for a beat.
function Dealer:push(time)
  local beat = time - (self.pushedAt or 0) >= link.BEAT_MS
  if not self.stale and not beat then return end
  self.stale = false
  if beat then self.pushedAt = time end
  local book = journal.owed()
  for number, st in pairs(self.stations) do
    -- A screen that cannot be built costs that one station a picture, never the table
    local ok, screen = pcall(self.screenFor, self, number, book)
    if not ok then
      log("the screen for seat " .. number .. " failed: " .. tostring(screen))
    else
      screen.events = st.events
      st.events = nil
      local text = signature(screen)
      if text ~= st.signature or not st.last or screen.events then
        st.signature = text
        self.viewCount = self.viewCount + 1
        screen.n = self.viewCount
        -- gen moves only when what can be pressed does, so someone else's move never makes a press land on nothing
        local keys = textutils.serialize({ screen.buttons, screen.tiles or false, screen.tap or false }, { compact = true })
        if keys ~= st.keys then st.keys, st.gen = keys, screen.n end
        screen.gen = st.gen
        st.last = screen
        st:show(screen)
      else
        -- The same picture: it says we are alive, and carries the clock
        st.last.left, st.last.countdown = screen.left, screen.countdown
        if beat or screen.left or screen.countdown then st:show(st.last) end
      end
    end
  end
end

-- ------------------------------------------------------------------ input

function Dealer:lobbyInput(number, input)
  local id, who, plugin = input.id, input.who, self.plugin
  local seat = self:seat(number)
  if id == "pick" then
    self:pick(input.value)
    return
  end
  if id == "sit" then
    self:sitDown(number, who, input.approved)
    return
  end
  if not seat then return end
  if self.vote then
    if id == "voteyes" then
      self.vote.yes[who] = true
      self:voteCheck()
    elseif id == "voteno" then
      self.vote = nil
    end
    return
  end
  if id == "leave" then
    self:seats()[number] = nil
    self.bets[number] = nil
    if #self:seatedNames() == 0 then self.keep.stake = nil end
    self:save()
    log("left " .. who)
    self:leaving(who)
  elseif id == "topup" then
    if plugin.stakes then self:openStake(number, who) else self:openBuyIn(number, who, true) end
  elseif id == "deal" and plugin.kind == "players" then
    if self:readyCount() >= plugin.minSeats and self:canPlay(seat) then self:deal() end
  elseif plugin.kind == "house" then
    local bet = self:bet(number)
    if id == "chip" and type(input.value) == "number" then
      if plugin.spots then
        bet.chip = input.value
      else
        local add = math.min(input.value, self:betRoom(number))
        bet.total = bet.total + add
        bet.ready = false
      end
    elseif id == "spot" and bet.chip then
      local known = false
      for _, spot in ipairs(plugin.spots or {}) do known = known or spot.id == input.value end
      local add = math.min(bet.chip, self:betRoom(number))
      if known and add > 0 then
        bet.spots[input.value] = (bet.spots[input.value] or 0) + add
        bet.total = bet.total + add
        bet.ready = false
      end
    elseif id == "clear" then
      bet.total, bet.spots, bet.ready = 0, {}, false
    elseif id == "ready" and bet.total >= plugin.minBet then
      bet.ready = true
    end
  end
end

--- A tile on the wall. With nobody seated it simply changes. With players seated it needs every one of them.
function Dealer:pick(id)
  if id == self.keep.game or not self.cabinet.find(id) or self.mode ~= "lobby" then return end
  if #self:seatedNames() == 0 then
    self.vote = nil
    self:setGame(id)
    return
  end
  self.vote = { game = id, yes = {}, deadline = now() + VOTE_MS }
  self:mark()
end

function Dealer:voteCheck()
  local vote = self.vote
  if not vote then return end
  for _, name in ipairs(self:seatedNames()) do
    if not vote.yes[name] then return end
  end
  self.vote = nil
  self:setGame(vote.game)
  self:askSeated()
end

--- The game has changed under seated players. Whoever has nothing on the table for it is asked now, because nothing deals until then.
function Dealer:askSeated()
  if self.plugin.kind ~= "players" then return end
  for number = 1, M.MAX_SEATS do
    local seat = self:seat(number)
    if seat and self.stations[number] and not self:canPlay(seat) then
      if self.plugin.stakes then self:openStake(number, seat.name) else self:openBuyIn(number, seat.name, true) end
    end
  end
end

--- NEXT is one player's say. The result comes down when everyone who played has said so, or when its time is up, so nobody can take
-- another player's result, or the seed on their FAIR page, away from them.
function Dealer:pressNext(who)
  self.nexted[who] = true
  for _, entry in ipairs(self.finished.entries) do
    if not self.nexted[entry.name] and self:seatOf(entry.name) then return end
  end
  self.resultUntil = 0
end

function Dealer:fairLines(round)
  local plugin = self.cabinet.find(round.game)
  if plugin and plugin.shoe then
    local keep = self.keep.games and self.keep.games[round.game] or {}
    local lines = {
      "These cards come from one shoe, shuffled once from a secret seed. Its hash was on the table before this round's first card.",
      "", { "This shoe's hash", "gold" }, round.commit,
      "Its seed comes when the shoe ends: shown sooner, it would give away every card still to come.",
    }
    if keep.lastShoe then
      lines[#lines + 1] = ""
      lines[#lines + 1] = { "The last shoe's hash", "gold" }
      lines[#lines + 1] = keep.lastShoe.commit
      lines[#lines + 1] = { "The last shoe's seed", "gold" }
      lines[#lines + 1] = keep.lastShoe.seed
    end
    return lines
  end
  return {
    "Before the deal this table fixed a secret seed, and showed the start of its hash. Its SHA-256 is the hash below, and the seed drives every shuffle.",
    "", { "Hash", "gold" }, round.commit,
    "", { "Seed, shown now the hand is over", "gold" }, round.seed,
  }
end

--- Everything a seat says. (seat, who, buttonId, value) is all a game ever sees of it.
function Dealer:input(number, input)
  local st, who = self.stations[number], input.who
  if not st then return end
  st:heard()
  self:touched(number, who, input.approved)
  self:mark()
  local id = input.id
  if not id then return end
  -- A press on buttons that have since changed is a press on nothing. The player sees the new ones and presses again
  if input.shown and st.gen and input.shown ~= st.gen then return end
  local seat = self:seat(number)
  -- Nobody else's touch does anything on a seat that is taken. The seat checks this too, and either alone would do
  local holder = (st.sub and st.sub.who) or (seat and seat.name)
  if holder and holder ~= who then return end
  if st.sub then
    self:subInput(number, input)
    return
  end
  if id == "rules" and self.plugin then
    local ok, lines = pcall(self.plugin.help)
    st.sub = { kind = "page", title = "RULES", lines = ok and type(lines) == "table" and self:pageLines(lines) or {}, deadline = now() + PANEL_MS }
    return
  end
  if self.mode == "hand" and self.round then
    if id == "sit" then self:sitDown(number, who, input.approved) else self:handInput(number, input) end
  elseif self.mode == "result" and self.finished then
    if id == "sit" then
      self:sitDown(number, who, input.approved)
    elseif id == "next" then
      self:pressNext(who)
    elseif id == "fair" then
      st.sub = { kind = "page", title = "FAIR PLAY", lines = self:pageLines(self:fairLines(self.finished)), deadline = now() + PANEL_MS }
    end
  elseif self.mode == "lobby" and self.plugin then
    self:lobbyInput(number, input)
  elseif id == "sit" then
    self:sitDown(number, who, input.approved)
  end
end

--- Help and FAIR text as a panel takes it.
function Dealer:pageLines(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      local color = line[2]
      if type(color) ~= "string" or not C[color] then color = "text" end
      for name, value in pairs(C) do
        if value == line[2] then color = name end
      end
      out[#out + 1] = { tostring(line[1] or ""), color }
    else
      out[#out + 1] = { tostring(line), "text" }
    end
  end
  return out
end

-- ------------------------------------------------------------------ joining

function Dealer:freeCount()
  local used = 0
  for _ in pairs(self.stations) do used = used + 1 end
  return M.MAX_SEATS - used
end

--- A number for a computer. The same computer always gets the same one, and seats are numbered in the order they arrive.
function Dealer:numberFor(id)
  self.keep.stations = self.keep.stations or {}
  local known = self.keep.stations[id]
  if known then return known end
  local taken = {}
  for _, number in pairs(self.keep.stations) do taken[number] = true end
  for number = 1, M.MAX_SEATS do
    if not taken[number] then
      self.keep.stations[id] = number
      self:save()
      return number
    end
  end
  -- Every number is in use. One that has gone for good, with nobody in it, gives way
  for known_id, number in pairs(self.keep.stations) do
    local st = self.stations[number]
    if not self:seat(number) and (not st or st:quiet(now())) and not self:orderOpenFor(known_id) then
      self.stations[number], self.byId[known_id] = nil, nil
      self.keep.stations[known_id] = nil
      self.keep.stations[id] = number
      self:save()
      return number
    end
  end
  return nil
end

function Dealer:orderOpenFor(id)
  for tag in pairs(journal.moves()) do
    if tonumber(tag:match("^Group %d+%.(%d+) ")) == id then return true end
  end
  return false
end

function Dealer:attachStation(id, number)
  local st = self.stations[number]
  if not st or st.id ~= id then
    st = station.remote(self.wire, id, number)
    self.stations[number], self.byId[id] = st, st
  end
  return st
end

--- What a seat says about being a seat. Answers to anything else come from wired-up handlers below.
function Dealer:handle(message)
  -- Both of a Duel's walls are on this computer, so it has no seats to find. It may have a modem for the hub
  if self.localMode then return end
  local kind, from = message.kind, message.from
  if kind == "hello" then
    local plugin = self.plugin
    local here = { host = self.host or "?", cabinet = self.cabinet.key, title = self.cabinet.title, game = plugin and plugin.title or nil,
      seated = #self:seatedNames(), free = self:freeCount() }
    self.wire:send(from, "here", here)
  elseif kind == "join" then
    if message.host ~= self.host or message.cabinet ~= self.cabinet.key then return end
    local number = self:numberFor(from)
    if not number then
      self.wire:send(from, "full", {})
      return
    end
    local st = self:attachStation(from, number)
    st:heard()
    st.signature, st.last = nil, nil
    self.wire:send(from, "welcome", { number = number })
    log("seat " .. number .. " is computer " .. from)
    self:mark()
  else
    local st = self.byId[from]
    if not st then return end
    st:heard()
    if kind == "input" then
      self:input(st.number, message)
    elseif kind == "answer" then
      self:answer(st, message.tag, message.moved)
    end
  end
end

-- ------------------------------------------------------------------ the dealer's wall

function Dealer:attachCanvas()
  self.monitor = peripheral.wrap(self.monitorName)
  self.monitor.setTextScale(0.5)
  theme.apply(self.monitor, self.plugin and self.plugin.felt or "green")
  if self.c then self.c:attach(self.monitor) else self.c = canvas.new(self.monitor) end
end

function Dealer:attachBoard()
  -- The scoreboard is the casino's leaders and jackpot, which a free table has no part in
  if self.free then return end
  self.board = board.attach(self.monitorName, self.plugin and self.plugin.felt or "green")
  self.boardName = self.board and self.board.name or nil
end

function Dealer:drawBoard()
  if not self.board then return end
  self.leaders = self.leaders or stats.leaders(board.ROWS)
  local hub = net.hub()
  local shown = board.show(self.board, { title = self.cabinet.title, leaders = self.leaders, jackpot = hub and hub.jackpot or nil,
    playing = self:seatedNames() })
  if not shown then self.board, self.boardName = nil, nil end
end

function Dealer:stripSeats(book)
  if self.heldStrip then return self.heldStrip end
  local seats = {}
  for number = 1, M.MAX_SEATS do
    local seat, st = self:seat(number), self.stations[number]
    if st or seat then
      local line = "Empty"
      local color = "mute"
      if seat then
        local owed = self.free and 0 or self:owedTo(seat.name, book)
        local wins = self.free and (self.keep.wins or {})[seat.name] or 0
        if st and st:quiet(now()) then
          line, color = "No signal", "orange"
        elseif self.free then
          line, color = wins == 1 and "1 win" or (ui.group(wins) .. " wins"), wins > 0 and "gold" or "text"
        elseif owed < 0 then
          line, color = "Owes " .. ui.group(-owed), "red"
        elseif owed > 0 then
          line, color = "Owed " .. ui.group(owed), "win"
        elseif self.plugin and self.plugin.kind == "house" and self.mode == "lobby" then
          line, color = "Bet " .. ui.group(self.bets[number] and self.bets[number].total or 0), "gold"
        elseif self.plugin and self.plugin.kind == "house" then
          local round = self.round or self.finished
          line, color = "Bet " .. ui.group(round and round.spent[number] or 0), "gold"
        else
          line, color = ui.group(seat.stack or 0), "text"
        end
      end
      seats[#seats + 1] = { number = number, name = seat and seat.name or nil, line = line, color = color,
        acting = (self.mode == "hand" and self.waiting and self.waiting[number]) or false }
    end
  end
  return seats
end

function Dealer:ownerLine(book)
  local parts = {}
  for key, amount in pairs(book) do
    parts[#parts + 1] = amount < 0 and (short(playerOf(key)) .. " owes " .. ui.group(-amount))
      or (short(playerOf(key)) .. " is owed " .. ui.group(amount))
  end
  if #parts == 0 then return nil end
  table.sort(parts)
  return table.concat(parts, "   ") .. "   (touch your seat)"
end

--- A free table's own record: who has won the most games here.
function Dealer:drawWins(c, cx, y)
  local list = {}
  for name, played in pairs(self.keep.played or {}) do
    list[#list + 1] = { name = name, wins = (self.keep.wins or {})[name] or 0, played = played }
  end
  table.sort(list, function(a, b)
    if a.wins ~= b.wins then return a.wins > b.wins end
    if a.played ~= b.played then return a.played > b.played end
    return a.name < b.name
  end)
  c:textCenter(cx, y, "WINS AT THIS TABLE", C.gold)
  if #list == 0 then
    c:textCenter(cx, y + 2, "No games finished yet", C.mute)
    return
  end
  for i = 1, math.min(#list, 8) do
    local entry = list[i]
    local line = ("%d. %-16s %3d won of %d"):format(i, short(entry.name), entry.wins, entry.played)
    c:textCenter(cx, y + 1 + i, line, i == 1 and C.gold or C.text)
  end
end

function Dealer:drawLobby(book)
  local c = self.c
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
  ui.bar(c, { title = self.cabinet.title })
  local hands = (self.free and "Game " or "Hand ") .. ui.group(self.keep.hands or 0)
  c:text(c.w - #hands - 2, 3, hands, C.text)
  self.buttons = ui.newButtons()
  local cx = math.floor(c.w / 2) + 1
  c:textCenter(cx, ui.TOP + 1, "PICK A GAME", C.gold)
  local tiles = {}
  for _, plugin in ipairs(self.cabinet.list) do
    local here = self.plugin and plugin.id == self.plugin.id
    local sub = plugin.kind == "house" and "Against the house" or "Player against player"
    if self.free then sub = plugin.tagline or "Free to play" end
    tiles[#tiles + 1] = { id = "pick", value = plugin.id, label = plugin.title, color = here and "gold" or "panel2",
      textColor = here and "ink" or "text", sub = sub }
  end
  local tilesBottom = self.free and 32 or 54
  seatui.tiles(c, self.buttons, tiles, ui.TOP + 3, tilesBottom)
  if #tiles == 0 then c:textCenter(cx, 30, "No games are installed yet", C.orange) end
  if self.free then self:drawWins(c, cx, tilesBottom + 3) end
  local y = 57
  if self.vote then
    local plugin = self.cabinet.find(self.vote.game)
    c:textCenter(cx, y, "Change to " .. tostring(plugin and plugin.title) .. "? Everyone seated must agree on their screens.", C.gold)
  elseif self.dealAt then
    local words = self.plugin.kind == "house" and "Betting closes in " or (self.free and "The game starts in " or "Next hand in ")
    c:textCenter(cx, y, words .. math.max(0, math.ceil((self.dealAt - now()) / 1000)) .. "s", C.text)
  elseif #self:seatedNames() == 0 then
    c:textCenter(cx, y, "Tap a game, then sit down at any seat", C.text)
  else
    c:textCenter(cx, y, "Waiting for players", C.text)
  end
  local line = self:ownerLine(book)
  if self.free and self.host and self.modem then
    c:textCenter(cx, y + 2, "Free to play: no tokens, ever. Wins are kept on this table.", C.mute)
  elseif not self.free and not wallet.available() then
    c:textCenter(cx, y + 2, "Economy offline", C.orange)
  elseif not self.host then
    c:textCenter(cx, y + 2, "Owner: right-click this computer and claim it in chat", C.orange)
  elseif not self.modem then
    c:textCenter(cx, y + 2, "This table needs a modem: no seat can find it", C.orange)
  elseif line then
    c:textCenter(cx, y + 2, line, C.orange)
  elseif self.wantsLock then
    c:textCenter(cx, y + 2, LOCK_NOTICE, C.mute)
  end
  seatui.strip(c, self:stripSeats(book))
end

function Dealer:drawTable(book)
  local c = self.c
  local round = self.round or self.finished
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
  self.buttons = ui.newButtons()
  local plugin = self.cabinet.find(round.game)
  local anim = self.playing and { ev = self.playing.ev, t = math.min(1, self.playing.t) } or nil
  if self.publicView then
    -- What is left on each clock, for a game that shows it on the wall (plugin.wallClock)
    local clocks, time = {}, now()
    for seat, deadline in pairs(self.mode == "hand" and self.deadlines or {}) do
      clocks[seat] = { left = math.max(0, deadline - time), total = (self.clockTotal and self.clockTotal[seat]) or plugin.turnMs }
    end
    local ok, err = pcall(plugin.tableView.draw, c, self.publicView, anim, { waiting = self.waiting or {}, seats = self:stripSeats(book),
      clocks = clocks })
    if not ok then
      c:textCenter(math.floor(c.w / 2), 30, "This table could not be drawn", C.orange)
      log("table view failed: " .. tostring(err))
    end
  end
  ui.bar(c, { title = plugin.title })
  local hands = (self.free and "Game " or "Hand ") .. ui.group(self.keep.hands or 0)
  c:text(c.w - #hands - 2, 3, hands, C.text)
  seatui.strip(c, self:stripSeats(book))
  if self.mode == "result" and self.tableResult then
    local _, top, _, h = seatui.tableArea(c)
    ui.banner(c, top + h - ui.BANNER_H, tostring(self.tableResult.title or ""), self.tableResult.detail, C.gold)
  end
  if self.mode == "hold" then c:textCenter(math.floor(c.w / 2), c.h - seatui.STRIP_H - 1, "Settling...", C.gold, C.ink) end
  -- The promise the FAIR page makes: the hash is up before any card is
  ui.hash(c, round.commit:sub(1, HASH_SHOWN))
end

function Dealer:drawWall()
  if self.localMode or not self.c then return end
  local c = self.c
  local ticking = self.plugin and self.plugin.wallClock and self.mode == "hand" and now() - (self.wallDrawnAt or 0) >= 1000
  if not (self.wallDirty or self.playing or #(self.queue or {}) > 0 or self.dealAt or self.stale or ticking) then return end
  self.wallDirty = false
  self.wallDrawnAt = now()
  local book = self.lastBook or journal.owed()
  if self.mode == "lobby" then self:drawLobby(book) else self:drawTable(book) end
  if self.toastText then
    local text = self.toastText
    local w = #text + 4
    local x = math.floor((c.w - w) / 2)
    c:rect(x, 40, w, 3, C.orange)
    c:text(x + 2, 41, text, C.ink, C.orange)
  end
  c:flush()
end

function Dealer:wallTouch(x, y, who)
  who = who or wallet.livePlayer()
  if wallet.lockIfOwner(who) then self.wantsLock = false end
  if who then self.lastWallTouch = who end
  self.wallDirty = true
  if self.playing or #(self.queue or {}) > 0 then
    self.queue, self.playing = {}, nil
    return
  end
  local hit = ui.hit(self.buttons or {}, x, y)
  if not hit then return end
  audio.play("tap")
  if hit.id == "pick" then self:pick(hit.value) end
end

function Dealer:wallTick(dt)
  if self.toastUntil and now() > self.toastUntil then
    self.toastText, self.toastUntil = nil, nil
    self.wallDirty = true
  end
  if self.playing then
    self.playing.t = self.playing.t + dt / self.playing.duration
    if self.playing.t >= 1 then
      self.playing = nil
      self.wallDirty = true -- a slow tick can skip the last frames, and a game may be holding something back until then
    end
  end
  if not self.playing and self.queue and #self.queue > 0 and not self.localMode then
    local ev = table.remove(self.queue, 1)
    local seconds, sound = 0.1, nil
    if self.plugin.event then
      local ok, length, noise = pcall(self.plugin.event, ev)
      if ok and type(length) == "number" and length > 0 then seconds, sound = length, noise end
    end
    if sound then audio.play(sound) end
    self.playing = { ev = ev, t = 0, duration = seconds }
    self.wallDirty = true
  end
end

-- ------------------------------------------------------------------ the loop

function Dealer:lobbyTick(time)
  if not self.plugin then return end
  if self.vote and time > self.vote.deadline then
    self.vote = nil
    self:mark()
  end
  if self.vote then
    self.dealAt = nil
    return
  end
  local plugin = self.plugin
  local count, wait = 0, plugin.lobbyMs or LOBBY_MS
  if plugin.kind == "players" then
    count = self:readyCount()
  else
    local everyone = true
    for number = 1, M.MAX_SEATS do
      local seat, bet = self:seat(number), self.bets[number]
      if bet and bet.total >= plugin.minBet then count = count + 1 end
      if seat and not (bet and bet.ready) then everyone = false end
    end
    wait = (everyone and count > 0) and ALL_BET_MS or BET_MS
  end
  if count >= plugin.minSeats then
    if not self.dealAt or (wait == ALL_BET_MS and self.dealAt > time + ALL_BET_MS) then
      self.dealAt = time + wait
      self:mark()
    end
    if time >= self.dealAt then self:deal() end
  elseif self.dealAt then
    self.dealAt = nil
    self:mark()
  end
end

--- One frame of whatever the table is doing now.
function Dealer:tick(time)
  if self.mode == "lobby" then
    self:lobbyTick(time)
  elseif self.mode == "hand" then
    self:handTick(time)
  elseif self.mode == "hold" then
    if not self.moving or time > self.holdUntil then self:reveal() end
  elseif self.mode == "reveal" then
    if time >= (self.showUntil or 0) then
      self.mode = "result"
      self.resultUntil = time + RESULT_MS
      self.nexted, self.heldStrip = {}, nil
      self:resultLamp(self.finished)
      self:mark()
    end
  elseif self.mode == "result" and time >= (self.resultUntil or 0) then
    self.mode = "lobby"
    if self.finished.phase == "closed" then journal.clearRound() end
    self.finished = nil
    self:mark()
  end
end

function Dealer:step(time, dt)
  for _, message in ipairs(self.wire:drain()) do
    local ok, err = pcall(self.handle, self, message)
    if not ok then log("message " .. tostring(message.kind) .. " failed: " .. tostring(err)) end
  end

  local touches = self.touches
  self.touches = {}
  for _, touch in ipairs(touches) do
    local ok, err = pcall(function()
      if touch.front then
        local input = touch.front:press(touch.x, touch.y, touch.who)
        if input then self:input(touch.number, input) end
      else
        self:wallTouch(touch.x, touch.y, touch.who)
      end
    end)
    if not ok then log("touch failed: " .. tostring(err)) end
  end

  for number, st in pairs(self.stations) do
    local sub = st.sub
    if sub and time > sub.deadline then
      st.sub = nil
      self:mark()
    end
    if st.front then
      local input = st.front:watchApproval()
      if input then self:input(number, input) end
    end
  end

  local ok, err = pcall(self.tick, self, time)
  if not ok then log("tick failed: " .. tostring(err)) end

  self:checkPanels()
  ok, err = pcall(self.settleTick, self, time)
  if not ok then log("settling failed: " .. tostring(err)) end
  self:push(time)

  if time - (self.beatAt or 0) > 5000 then
    self.beatAt = time
    os.queueEvent("roger_alive")
    os.queueEvent("roger_busy", #self:seatedNames() > 0)
    net.tick()
    self.host = wallet.hostName() or self.host
    self.wantsLock = wallet.wantsLock()
    self:closeStale(time)
    -- The leaders already hold the hand, and the cards have not turned yet
    if self.mode ~= "hold" and self.mode ~= "reveal" then self:drawBoard() end
    self.wallDirty = true
    for _, st in pairs(self.stations) do
      if st.front then st.front.lockNote = self.wantsLock and LOCK_NOTICE or nil end
    end
  end

  self:wallTick(dt)
  self:drawWall()
  if self.localMode then
    for _, st in pairs(self.stations) do
      if st.front then
        st.front:tick(dt)
        st.front:draw()
      end
    end
  end
  if self.debug then self:writeDebug() end
end

--- The hold is over: the money has moved, so the last cards can turn.
function Dealer:reveal()
  local round = self.finished
  local plugin = self.cabinet.find(round.game)
  self.mode = "reveal"
  local ok, view = pcall(plugin.rules.viewFor, round.state, nil)
  self.publicView = ok and view or self.publicView
  local good, result = pcall(plugin.rules.result, round.state, nil)
  self.tableResult = good and result or nil
  self:queueEvents(self.finalEvents)
  self.finalEvents = nil
  self.wallDirty = true
  self:mark()
end

--- A lamp and the sound of a win wait for the result to be up, the same as everything else that would give it away.
function Dealer:resultLamp(round)
  for _, entry in ipairs(round.entries) do
    if (round.nets[entry.name] or 0) > 0 and round.nets[entry.name] >= self:wagered(round, entry) * BIG_WIN_TIMES then
      lamps.pulse("bigWin")
      break
    end
  end
  audio.play("win")
end

function Dealer:writeDebug()
  local seats = {}
  for number = 1, M.MAX_SEATS do
    local seat = self:seat(number)
    if seat then seats[#seats + 1] = { seat = number, name = seat.name, stack = seat.stack, away = seat.away or 0 } end
  end
  local stations = {}
  for number, st in pairs(self.stations) do
    stations[#stations + 1] = { number = number, id = st.id or false, quiet = st:quiet(now()), sub = st.sub and st.sub.kind or false }
  end
  table.sort(stations, function(a, b) return a.number < b.number end)
  local buttons = {}
  for _, b in ipairs(self.buttons or {}) do
    buttons[#buttons + 1] = { id = b.id, value = b.value, x = b.x, y = b.y, w = b.w, h = b.h, label = b.label }
  end
  local round = self.round or self.finished
  local tags = {}
  for tag, move in pairs(journal.moves()) do tags[#tags + 1] = { tag = tag, name = move.name, amount = move.amount } end
  local waiting = {}
  for seat in pairs(self.waiting or {}) do waiting[#waiting + 1] = seat end
  table.sort(waiting)
  local entries = {}
  for i, entry in ipairs(round and round.entries or {}) do
    entries[i] = { seat = entry.seat, name = entry.name, bet = entry.bet or false, bets = entry.bets or false, stack = entry.stack or false, stake = entry.stake or false }
  end
  local state = {
    role = "dealer", scene = self.mode, game = self.keep.game or false, seats = seats, stations = stations, owed = journal.owed(),
    moves = tags, moving = self.moving == true, buttons = buttons, countdown = self.dealAt and math.ceil((self.dealAt - now()) / 1000) or false, toast = self.toastText or false,
    round = round and { id = round.id, phase = round.phase or false, nets = round.nets or false, commit = round.commit, entries = entries } or false,
    waiting = waiting, vote = self.vote and self.vote.game or false, hands = self.keep.hands or 0, w = self.c and self.c.w or false,
    h = self.c and self.c.h or false, public = self.publicView or false, wanted = self.wanted, stake = self.keep.stake or false,
    strip = self:stripSeats(journal.owed()), modem = self.modem == true,
  }
  if self.localMode then
    state.walls = {}
    for number, st in pairs(self.stations) do state.walls[number] = st.front:debug() end
  end
  local ok, text = pcall(textutils.serializeJSON, state)
  if not ok then return end
  local handle = fs.open("casino_ui.dat", "w")
  if handle then
    handle.write(text)
    handle.close()
  end
end

--- Every event lands here first, in a coroutine that never makes a wallet call, so none can be lost while one waits.
function Dealer:pump()
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "rednet_message" then
      self.wire:hear(a, b, c)
    elseif event == "vhcc_touch" then
      self.toucher = a
    elseif event == "monitor_touch" then
      local who = self.toucher
      self.toucher = nil
      if #self.touches >= MAX_TOUCHES then
        self.dropped = (self.dropped or 0) + 1
      elseif a == self.monitorName then
        self.touches[#self.touches + 1] = { x = b, y = c, who = who }
      else
        for number, st in pairs(self.stations) do
          if st.front and st.front.monitorName == a then
            self.touches[#self.touches + 1] = { x = b, y = c, who = who, front = st.front, number = number }
          end
        end
      end
    elseif event == "monitor_resize" then
      self.resized = a
    elseif event == "peripheral" or event == "peripheral_detach" then
      self.rescan = true
    end
  end
end

function Dealer:main()
  self:recover()
  local last = now()
  while true do
    local timer = os.startTimer(FRAME)
    repeat
      local _, id = os.pullEvent("timer")
    until id == timer
    if self.rescan then
      self.rescan = false
      audio.init()
      self.modem = link.open()
      net.open()
      chat.scan()
      lamps.rescan()
      if not self.localMode then self:attachBoard() end
    end
    if self.resized then
      local name = self.resized
      self.resized = nil
      if name == self.monitorName and not self.localMode then
        self:attachCanvas()
        self.wallDirty = true
      elseif self.localMode then
        for _, st in pairs(self.stations) do
          if st.front and st.front.monitorName == name then st.front:attach() end
        end
      end
    end
    local time = now()
    self:step(time, (time - last) / 1000)
    last = time
  end
end

local function open(cabinet, localMode)
  audio.init()
  local modem = link.open()
  net.open()
  chat.scan()
  local keep = journal.loadKeep()
  local self = setmetatable({
    cabinet = cabinet, localMode = localMode, keep = keep, wire = link.new(), stations = {}, byId = {}, touches = {}, wanted = {},
    lastTouch = {}, sentAt = {}, traces = {}, nexted = {}, bets = {}, deadlines = {}, queue = {}, waiting = {}, mode = "lobby",
    viewCount = now(), modem = modem, host = wallet.hostName(), debug = fs.exists("casino_debug.flag"), wallDirty = true, stale = true,
    free = cabinet.free == true,
  }, Dealer)
  keep.role = "dealer"
  local id = keep.game or (cabinet.list[1] and cabinet.list[1].id)
  if id then
    if not self:setGame(id) and cabinet.list[1] then self:setGame(cabinet.list[1].id) end
  end
  return self
end

local function run(self)
  self.wantsLock = wallet.wantsLock()
  parallel.waitForAny(function() self:main() end, function() self:pump() end, net.worker, chat.worker, lamps.worker)
end

--- Run a Big Table dealer on this wall, for ever.
function M.runDealer(cabinet, monitorName)
  local self = open(cabinet, false)
  self.monitorName = monitorName
  self:attachCanvas()
  self:attachBoard()
  for id, number in pairs(self.keep.stations or {}) do
    self:attachStation(id, number)
  end
  run(self)
end

--- Run a Duel on two walls. Each is a seat with no network: the dealer's job and the seat's are on one computer.
function M.runDuel(cabinet, walls)
  local self = open(cabinet, true)
  self.viewers = {}
  self.monitorName = false
  for number, name in ipairs(walls) do
    local front = seatmod.front(cabinet, name, true)
    self.stations[number] = station.wall(front, number)
    self.stations[number].front = front
  end
  run(self)
end

--- Show a line on whatever wall there is, for what stops a cabinet starting.
local function notice(monitorName, text)
  if not monitorName then
    print(text)
    return
  end
  local monitor = peripheral.wrap(monitorName)
  monitor.setTextScale(0.5)
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()
  for row, line in ipairs(ui.wrap(text, math.max(10, monitor.getSize() - 2))) do
    monitor.setCursorPos(2, 1 + row)
    monitor.write(line)
  end
end

--- A computer that still holds a dealer's hand or orders stays a dealer, even if its wall has not finished forming.
local function wasDealer()
  local keep = journal.loadKeep()
  return keep.role == "dealer" and (journal.loadRound() ~= nil or next(journal.moves()) ~= nil)
end

--- What a cabinet's startup.lua calls. The same package goes on every computer, and the wall decides what each one is.
-- cabinet: { key, title, list, find } from games/registry.lua. duel = true for two walls and no network.
function M.start(cabinet)
  while true do
    local list = board.monitors()
    if cabinet.duel then
      local first, second = list[1], list[2]
      if first and second and first.area == second.area and first.area >= seatui.DEALER_W * seatui.DEALER_H then
        local names = { first.name, second.name }
        table.sort(names)
        M.runDuel(cabinet, names)
        return
      end
      notice(first and first.name, cabinet.title .. " needs two equal 6x6 walls on this computer.")
    elseif list[1] then
      local monitor = peripheral.wrap(list[1].name)
      local w, h = monitor.getSize()
      if (w >= seatui.DEALER_W and h >= seatui.DEALER_H) or wasDealer() then
        M.runDealer(cabinet, list[1].name)
      else
        seatmod.run(cabinet, list[1].name)
      end
      return
    else
      print(cabinet.title .. " needs a monitor.")
    end
    local event
    repeat
      event = os.pullEvent()
    until event == "peripheral" or event == "monitor_resize"
  end
end

return M
