-- games/uno/rules.lua
-- UNO on Game Night, for one to eight people, the computer filling the table to four. One round of the engine is one whole game:
-- hands are dealt one after another until someone reaches the goal (500 by the official rules, 200 for a shorter game, or a single
-- hand). Free: nets are always nought.
--
-- The official rules, with these choices:
--   * 108 cards, seven each. The first discard is turned up: a Wild Draw Four goes back and another is turned; a Skip skips the first
--     player; a Reverse makes the dealer go first and play run the other way; a Draw Two makes the first player draw two and miss
--     their turn; a Wild lets the first player name the colour, then play.
--   * Play a card of the colour in play, the same number or symbol, or a wild. A Wild Draw Four may be played at any time, and there
--     is no challenge. A Draw Two or Draw Four cannot be stacked: the next player draws and misses their turn.
--   * Reverse with two players acts as a Skip.
--   * DRAW takes one card. If it can be played it may be played at once, or kept, and the turn passes.
--   * UNO: going down to one card, a player must say UNO first. On their screen the UNO button lights up gold while they hold two
--     cards on their turn: tap it, then play. Saying it first means tap lag can never cost anyone the call. A player who goes down
--     to one without it can be caught: any other player can tap CATCH until the next player plays or draws (and the others have a
--     few seconds), and the one caught draws two. The computer players say UNO most of the time, and sometimes catch.
--   * Going out wins the hand and scores every card left in the others' hands: the face of a number, 20 for an action, 50 for a wild.
--     A Draw Two or Draw Four that goes out still makes the next player draw first, and those cards count.
--
-- The clock: a turn has a minute. When it runs out the player draws one and the turn passes, and their clock is short until they tap
-- again. A seat that was already being waited on when its turn began (it could catch, or it pressed NEXT HAND) first gets its full
-- clock: its old one only says "clock" and starts the turn's own.

local bot = require("games.uno.bot")
local cards = require("games.uno.cards")

local M = {}

M.FILL = 4               -- the computer fills the table to this many players
M.MAX = 8
M.HAND = 7
M.TURN_MS = 60000
M.IDLE_MS = 15000        -- for someone whose clock has run out and who has not pressed since
M.CATCH_MS = 6000        -- how long the others have to catch a missed UNO
M.GOAL_MS = 20000        -- picking how long a game to play
M.NEXT_MS = 30000        -- reading the scores after a hand
M.GOALS = { 500, 200, 0 }  -- 0 is a single hand
M.DEFAULT_GOAL = 500
M.PAGE = 14              -- cards on a seat's screen at once
M.MAX_TURNS = 600        -- a hand this long goes to the fewest points held, so a table can never play for ever
M.MAX_HANDS = 40
M.BOT_FORGETS = 12       -- percent of the time a computer player forgets to say UNO
M.BOT_NOTICES = 40       -- percent of the time a computer player catches a missed UNO first
M.LOG = 6
M.RECENT = 7

local BOT_NAMES = { "Ada", "Hal", "Max", "Ivy", "Kit", "Sol", "Bea" }

local function event(kind, fields)
  local ev = fields or {}
  ev.type = kind
  return ev
end

local function shuffle(list, rng)
  for i = #list, 2, -1 do
    local j = rng:below(i) + 1
    list[i], list[j] = list[j], list[i]
  end
  return list
end

local function copyList(list)
  local out = {}
  for i, item in ipairs(list) do out[i] = item end
  return out
end

local function log(state, text)
  local lines = state.log
  lines[#lines + 1] = text
  while #lines > M.LOG do table.remove(lines, 1) end
end

local function nameOf(state, p)
  return state.players[p].name
end

local function nextOf(state, p, steps)
  local n = #state.players
  return ((p - 1 + state.dir * (steps or 1)) % n) + 1
end
M.nextOf = nextOf

local function playerOfSeat(state, seat)
  if seat == nil then return nil end
  for p, player in ipairs(state.players) do
    if player.seat == seat then return p end
  end
  return nil
end
M.playerOfSeat = playerOfSeat

local function top(state)
  return state.pile[#state.pile]
end
M.top = top

local function freshUi()
  return { page = 1, pick = false, armed = false }
end

local function inList(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then return true end
  end
  return false
end

-- ------------------------------------------------------------------ the deck

--- The discard pile but its top card goes back in the deck, shuffled.
local function reshuffle(state, rng, events)
  if #state.pile <= 1 then return false end
  local keep = table.remove(state.pile)
  for _, card in ipairs(state.pile) do state.deck[#state.deck + 1] = card end
  state.pile = { keep }
  shuffle(state.deck, rng)
  log(state, "The discards are shuffled into a new draw pile")
  if events then events[#events + 1] = event("shuffle", {}) end
  return true
end

--- A player draws n cards, as many as there are. Returns the number drawn and the last card.
local function drawCards(state, p, n, rng, events)
  local player = state.players[p]
  local got, last = 0, nil
  for _ = 1, n do
    if #state.deck == 0 then reshuffle(state, rng, events) end
    if #state.deck == 0 then break end
    last = table.remove(state.deck)
    player.hand[#player.hand + 1] = last
    got = got + 1
  end
  cards.sort(player.hand)
  if #player.hand ~= 1 then player.said = false end
  return got, last
end

local function playableNow(state, card)
  return cards.playable(card, top(state), state.color)
end
M.playableNow = playableNow

--- The cards in a player's hand that may go down now.
function M.playable(state, p)
  local list = {}
  if state.phase ~= "play" and state.phase ~= "drawn" then return list end
  if state.turn ~= p then return list end
  if state.phase == "drawn" then
    if state.drawn and inList(state.players[p].hand, state.drawn) and playableNow(state, state.drawn) then list[1] = state.drawn end
    return list
  end
  for _, card in ipairs(state.players[p].hand) do
    if playableNow(state, card) then list[#list + 1] = card end
  end
  return list
end

-- ------------------------------------------------------------------ a new game, a new hand

local function firstHuman(state)
  for p, player in ipairs(state.players) do
    if not player.bot and player.seat == state.chooserSeat then return p end
  end
  return nil
end

local function startTurn(state, p)
  state.turn = p
  state.phase = "play"
  state.drawn = false
  state.turnNo = state.turnNo + 1
  state.handTurns = state.handTurns + 1
  for _, player in ipairs(state.players) do
    player.ui.pick = false
    player.ui.armed = false
    player.ui.page = math.max(1, math.min(player.ui.page, math.ceil(#player.hand / M.PAGE)))
  end
end

local endHand

--- Deal a hand: seven each, then turn up the first discard and do what it says.
local function startHand(state, rng, events)
  state.handNo = state.handNo + 1
  state.handTurns = 0
  state.deck = shuffle(cards.deck(), rng)
  state.pile = {}
  state.recent = {}
  state.window = false
  state.drawn = false
  state.dir = 1
  state.lastHand = state.lastHand or false
  for _, player in ipairs(state.players) do
    player.hand = {}
    player.said = false
    player.ready = false
    player.gain = 0
    player.ui = freshUi()
  end
  for _ = 1, M.HAND do
    for p = 1, #state.players do
      local player = state.players[p]
      player.hand[#player.hand + 1] = table.remove(state.deck)
    end
  end
  for _, player in ipairs(state.players) do cards.sort(player.hand) end
  -- A Wild Draw Four never starts a hand: back in the deck somewhere, and turn another
  local first = table.remove(state.deck)
  while first == "wF" do
    table.insert(state.deck, rng:below(#state.deck) + 1, first)
    first = table.remove(state.deck)
  end
  state.pile[1] = first
  state.color = false
  if not cards.isWild(first) then state.color = cards.color(first) end
  local dealer = state.dealer
  local leader = nextOf(state, dealer)
  events[#events + 1] = event("deal", { dealer = dealer, hand = state.handNo, card = first })
  log(state, "Hand " .. state.handNo .. ": " .. nameOf(state, dealer) .. " deals. First card " .. cards.name(first))
  state.recent[1] = { p = 0, card = first, color = state.color or "w" }
  local kind = cards.kind(first)
  if kind == "S" then
    log(state, nameOf(state, leader) .. " is skipped")
    startTurn(state, nextOf(state, leader))
  elseif kind == "R" then
    state.dir = -1
    log(state, "Play runs the other way: " .. nameOf(state, dealer) .. " goes first")
    startTurn(state, dealer)
  elseif kind == "D" then
    drawCards(state, leader, 2, rng, events)
    log(state, nameOf(state, leader) .. " draws 2 and is skipped")
    events[#events + 1] = event("draw", { p = leader, n = 2 })
    startTurn(state, nextOf(state, leader))
  elseif kind == "W" then
    startTurn(state, leader)
    state.phase = "color"
    log(state, nameOf(state, leader) .. " names the first colour")
  else
    startTurn(state, leader)
  end
end

function M.new(entries, button, rng, keep)
  local players = {}
  for _, entry in ipairs(entries) do
    if #players < M.MAX then players[#players + 1] = { seat = entry.seat, name = entry.name, bot = false } end
  end
  local chooserSeat = players[1] and players[1].seat or false
  local names = shuffle(copyList(BOT_NAMES), rng)
  local n = 1
  while #players < M.FILL do
    players[#players + 1] = { seat = false, name = names[n], bot = true }
    n = n + 1
  end
  shuffle(players, rng)
  for _, player in ipairs(players) do
    player.hand = {}
    player.score = 0
    player.idle = 0
    player.said = false
    player.ready = false
    player.carry = false
    player.gain = 0
    player.ui = freshUi()
  end
  local state = {
    players = players, phase = "goal", goal = M.DEFAULT_GOAL, chooserSeat = chooserSeat, dealer = rng:below(#players) + 1,
    dir = 1, turn = 1, deck = {}, pile = {}, color = false, handNo = 0, turnNo = 0, handTurns = 0, log = {}, recent = {},
    window = false, drawn = false, winner = 0, lastHand = false,
  }
  local events = { event("start", {}) }
  if chooserSeat then
    log(state, "A new game of UNO. " .. players[firstHuman(state)].name .. " picks how long")
  else
    startHand(state, rng, events)
  end
  return state, events
end

-- ------------------------------------------------------------------ the end of a hand and of the game

local function scoreText(state)
  local parts = {}
  for _, player in ipairs(state.players) do parts[#parts + 1] = player.name .. " " .. player.score end
  return table.concat(parts, ", ")
end

endHand = function(state, w, events)
  local gained = 0
  local rows = {}
  for p, player in ipairs(state.players) do
    local points = cards.handPoints(player.hand)
    if p ~= w then gained = gained + points end
    rows[p] = { cards = #player.hand, points = points }
    player.gain = 0
  end
  local winner = state.players[w]
  winner.score = winner.score + gained
  winner.gain = gained
  state.window = false
  state.drawn = false
  state.handWinner = w
  state.lastHand = { winner = w, points = gained, hand = state.handNo, rows = rows }
  log(state, winner.name .. " wins hand " .. state.handNo .. " and scores " .. gained)
  events[#events + 1] = event("handwin", { p = w, points = gained })
  local over = state.goal == 0 or winner.score >= state.goal or state.handNo >= M.MAX_HANDS
  if over then
    local best = w
    if state.goal ~= 0 and winner.score < state.goal then
      for p, player in ipairs(state.players) do
        if player.score > state.players[best].score then best = p end
      end
    end
    state.phase, state.winner = "over", best
    if state.goal == 0 then
      log(state, winner.name .. " wins the game!")
    else
      log(state, state.players[best].name .. " wins the game with " .. state.players[best].score .. "!")
    end
    events[#events + 1] = event("win", { p = best })
    return
  end
  state.phase = "scored"
  for _, player in ipairs(state.players) do player.ready = player.bot end
  state.dealer = ((state.dealer) % #state.players) + 1
end

--- Every person has pressed NEXT HAND (or their clock did): deal the next.
local function maybeDeal(state, rng, events)
  for _, player in ipairs(state.players) do
    if not player.ready then return false end
  end
  startHand(state, rng, events)
  return true
end

-- ------------------------------------------------------------------ playing

local function closeWindow(state)
  state.window = false
end

--- A player went down to one card without saying UNO: the others may catch them until the next player moves.
local function openWindow(state, p, rng)
  local wait = {}
  for q, player in ipairs(state.players) do
    if not player.bot and q ~= p and q ~= state.turn then wait[#wait + 1] = player.seat end
  end
  local spotters = {}
  for q, player in ipairs(state.players) do
    if player.bot and q ~= p then spotters[#spotters + 1] = q end
  end
  local noticed = false
  if #spotters > 0 and rng:below(100) < M.BOT_NOTICES then noticed = spotters[rng:below(#spotters) + 1] end
  state.window = { p = p, wait = wait, noticed = noticed }
end

local function catch(state, q, rng, events)
  local window = state.window
  if not window then return false end
  local p = window.p
  closeWindow(state)
  local got = drawCards(state, p, 2, rng, events)
  log(state, nameOf(state, q) .. " catches " .. nameOf(state, p) .. " without UNO! " .. nameOf(state, p) .. " draws " .. got)
  events[#events + 1] = event("catch", { p = q, q = p, n = got })
  return true
end

local EVENT_OF = { S = "skip", R = "reverse", D = "draw2", W = "wild", F = "draw4" }

--- p plays a card from their hand. color names the colour for a wild. called says they said UNO with it.
local function play(state, p, card, color, called, rng, events)
  local player = state.players[p]
  local at = nil
  for i, held in ipairs(player.hand) do
    if held == card then
      at = i
      break
    end
  end
  if not at then return false end
  table.remove(player.hand, at)
  state.pile[#state.pile + 1] = card
  state.color = cards.isWild(card) and color or cards.color(card)
  state.drawn = false
  player.ui.pick = false
  local recent = state.recent
  recent[#recent + 1] = { p = p, card = card, color = state.color }
  while #recent > M.RECENT do table.remove(recent, 1) end
  local kind = cards.kind(card)
  local left = #player.hand
  local text = player.name .. " plays " .. cards.name(card)
  if cards.isWild(card) then text = text .. ", " .. cards.COLOR_NAME[state.color] end
  log(state, text)
  local n = #state.players
  local target = nextOf(state, p)
  local ev = event(EVENT_OF[kind] or "play", { p = p, card = card, color = state.color })
  if kind == "S" or kind == "D" or kind == "F" or (kind == "R" and n == 2) then ev.victim = target end
  events[#events + 1] = ev
  local armed = player.ui.armed or called
  player.ui.armed = false
  local nextTurn
  if kind == "S" then
    log(state, nameOf(state, target) .. " is skipped")
    nextTurn = nextOf(state, p, 2)
  elseif kind == "R" then
    if n == 2 then
      nextTurn = p
    else
      state.dir = -state.dir
      nextTurn = nextOf(state, p)
    end
  elseif kind == "D" or kind == "F" then
    local count = kind == "D" and 2 or 4
    local got = drawCards(state, target, count, rng, events)
    log(state, nameOf(state, target) .. " draws " .. got .. " and is skipped")
    events[#events + 1] = event("draw", { p = target, n = got })
    nextTurn = nextOf(state, p, 2)
  else
    nextTurn = nextOf(state, p)
  end
  if left == 0 then
    endHand(state, p, events)
    return true
  end
  if left == 1 and armed then
    player.said = true
    log(state, player.name .. ": UNO!")
    events[#events + 1] = event("uno", { p = p })
  end
  startTurn(state, nextTurn)
  if left == 1 and not armed then openWindow(state, p, rng) end
  return true
end

--- p draws one. A card they can play waits for them to play it or keep it; anything else passes the turn.
local function drawOne(state, p, rng, events, pass)
  closeWindow(state)
  local got, card = drawCards(state, p, 1, rng, events)
  events[#events + 1] = event("draw", { p = p, n = got })
  if got == 0 then
    log(state, nameOf(state, p) .. " has nothing to draw and passes")
    startTurn(state, nextOf(state, p))
    return nil
  end
  if not pass and playableNow(state, card) then
    log(state, nameOf(state, p) .. " draws a card")
    state.phase = "drawn"
    state.drawn = card
    return card
  end
  log(state, nameOf(state, p) .. " draws and passes")
  startTurn(state, nextOf(state, p))
  return nil
end

local function keep(state, p, events)
  log(state, nameOf(state, p) .. " keeps the card")
  events[#events + 1] = event("pass", { p = p })
  startTurn(state, nextOf(state, p))
end

local function pickGoal(state, goal, rng, events)
  state.goal = goal
  local text = goal == 0 and "One hand decides it" or ("First to " .. goal .. " points wins")
  log(state, text)
  events[#events + 1] = event("goal", { goal = goal })
  startHand(state, rng, events)
end

-- ------------------------------------------------------------------ the computer

local function botMove(state, rng)
  local events = {}
  local window = state.window
  if window and window.noticed then
    catch(state, window.noticed, rng, events)
    return events
  end
  if state.phase == "goal" then
    pickGoal(state, M.DEFAULT_GOAL, rng, events)
    return events
  end
  if state.phase == "scored" then
    for _, player in ipairs(state.players) do player.ready = true end
    maybeDeal(state, rng, events)
    return events
  end
  local p = state.turn
  local player = state.players[p]
  if not player.bot then return nil end
  if state.phase == "color" then
    state.color = cards.bestColor(player.hand)
    state.phase = "play"
    log(state, player.name .. " names " .. cards.COLOR_NAME[state.color])
    events[#events + 1] = event("color", { p = p, color = state.color })
    return events
  end
  local said = rng:below(100) >= M.BOT_FORGETS
  local card, color = bot.choose(state, p)
  if card then
    play(state, p, card, color, said, rng, events)
    return events
  end
  local drawn = drawOne(state, p, rng, events, false)
  if drawn then
    local pick = cards.isWild(drawn) and bot.colorFor(player.hand, drawn) or nil
    play(state, p, drawn, pick, said, rng, events)
  end
  return events
end

-- ------------------------------------------------------------------ the clock, and who is waited on

function M.waitingOn(state)
  local list = {}
  local phase = state.phase
  if phase == "over" then return list end
  if phase == "goal" then
    local p = firstHuman(state)
    if p then list[1] = state.players[p].seat end
    return list
  end
  if phase == "scored" then
    for _, player in ipairs(state.players) do
      if not player.bot and not player.ready then list[#list + 1] = player.seat end
    end
    return list
  end
  local window = state.window
  -- A computer player saw the missed UNO first: it moves before anyone
  if window and window.noticed then return list end
  local current = state.players[state.turn]
  if not current.bot then list[1] = current.seat end
  if window then
    for _, seat in ipairs(window.wait) do
      if not inList(list, seat) then list[#list + 1] = seat end
    end
  end
  return list
end

function M.turnMs(state, seat)
  local p = playerOfSeat(state, seat)
  if not p then return nil end
  local player = state.players[p]
  if state.phase == "goal" then return M.GOAL_MS end
  if state.phase == "scored" then return M.NEXT_MS end
  if state.turn == p then
    if player.idle > 0 and not player.carry then return M.IDLE_MS end
    return M.TURN_MS
  end
  if state.window and inList(state.window.wait, seat) then return M.CATCH_MS end
  return M.TURN_MS
end

--- A clock that ran out once is no missed turn: a player only counts as away from the second in a row.
function M.present(state, seat)
  local p = playerOfSeat(state, seat)
  return p ~= nil and state.players[p].idle < 2
end

--- A seat's clock ran out.
local function timeout(state, p, rng)
  local events = {}
  local player = state.players[p]
  local seat = player.seat
  if state.phase == "goal" then
    if firstHuman(state) ~= p then return nil end
    pickGoal(state, M.DEFAULT_GOAL, rng, events)
    return events
  end
  if state.phase == "scored" then
    if player.ready then return nil end
    player.ready = true
    events[#events + 1] = event("ready", { p = p })
    maybeDeal(state, rng, events)
    return events
  end
  local window = state.window
  if state.turn ~= p then
    if window and inList(window.wait, seat) then
      local rest = {}
      for _, other in ipairs(window.wait) do
        if other ~= seat then rest[#rest + 1] = other end
      end
      window.wait = rest
      events[#events + 1] = event("late", { p = p })
      return events
    end
    return nil
  end
  -- The clock that ran out was the one from before this turn began: now the turn's own starts
  if player.carry then
    player.carry = false
    events[#events + 1] = event("clock", { p = p })
    return events
  end
  player.idle = player.idle + 1
  player.ui.pick = false
  player.ui.armed = false
  if state.phase == "color" then
    state.color = cards.bestColor(player.hand)
    state.phase = "play"
    events[#events + 1] = event("color", { p = p, color = state.color })
  end
  if state.phase == "drawn" then
    log(state, player.name .. " ran out of time and keeps the card")
    keep(state, p, events)
    return events
  end
  log(state, player.name .. " ran out of time")
  drawOne(state, p, rng, events, true)
  return events
end

-- ------------------------------------------------------------------ a person's presses

local function canCatch(state, p)
  local window = state.window
  if not window or window.noticed or window.p == p then return false end
  if state.phase ~= "play" and state.phase ~= "drawn" and state.phase ~= "color" then return false end
  return state.turn == p or inList(window.wait, state.players[p].seat)
end
M.canCatch = canCatch

local function pages(state, p)
  return math.max(1, math.ceil(#state.players[p].hand / M.PAGE))
end

local function press(state, p, id, value, rng)
  local events = {}
  local player = state.players[p]
  local phase = state.phase
  if phase == "goal" then
    if id ~= "goal" or firstHuman(state) ~= p then return nil end
    local goal = tonumber(value)
    if not inList(M.GOALS, goal) then return nil end
    pickGoal(state, goal, rng, events)
    return events
  end
  if phase == "scored" then
    if id ~= "next" or player.ready then return nil end
    player.ready = true
    events[#events + 1] = event("ready", { p = p })
    maybeDeal(state, rng, events)
    return events
  end
  if id == "catch" then
    if not canCatch(state, p) then return nil end
    catch(state, p, rng, events)
    return events
  end
  if id == "page" then
    local step = tonumber(value)
    if step ~= 1 and step ~= -1 then return nil end
    local page = player.ui.page + step
    if page < 1 or page > pages(state, p) then return nil end
    player.ui.page = page
    events[#events + 1] = event("page", { p = p })
    return events
  end
  if state.turn ~= p then return nil end
  if phase == "color" then
    if id ~= "color" or not cards.isColor(value) then return nil end
    state.color = value
    state.phase = "play"
    log(state, player.name .. " names " .. cards.COLOR_NAME[value])
    events[#events + 1] = event("color", { p = p, color = value })
    return events
  end
  if phase ~= "play" and phase ~= "drawn" then return nil end
  if id == "uno" then
    if #player.hand ~= 2 or player.ui.armed then return nil end
    player.ui.armed = true
    log(state, player.name .. ": UNO!")
    events[#events + 1] = event("uno", { p = p, early = true })
    return events
  end
  local pick = player.ui.pick
  if pick then
    if id == "back" then
      player.ui.pick = false
      events[#events + 1] = event("pick", { p = p })
      return events
    elseif id == "color" and cards.isColor(value) then
      closeWindow(state)
      play(state, p, pick, value, false, rng, events)
      return events
    end
    return nil
  end
  if id == "play" then
    local card = tostring(value or "")
    if not inList(M.playable(state, p), card) then return nil end
    if cards.isWild(card) then
      player.ui.pick = card
      events[#events + 1] = event("pick", { p = p })
      return events
    end
    closeWindow(state)
    play(state, p, card, nil, false, rng, events)
    return events
  end
  if phase == "play" and id == "draw" then
    drawOne(state, p, rng, events, false)
    return events
  end
  if phase == "drawn" and id == "keep" then
    keep(state, p, events)
    return events
  end
  return nil
end

local function waitingSet(state)
  local set = {}
  for _, seat in ipairs(M.waitingOn(state)) do set[seat] = true end
  return set
end

function M.act(state, seat, id, value, rng)
  if state.phase == "over" then return nil end
  local before = waitingSet(state)
  local turnNo, handNo = state.turnNo, state.handNo
  local events
  if seat == nil then
    if id ~= "bot" then return nil end
    events = botMove(state, rng)
  else
    local p = playerOfSeat(state, seat)
    if not p then return nil end
    if id == "timeout" then
      events = timeout(state, p, rng)
    else
      events = press(state, p, id, value, rng)
      if events and #events > 0 then state.players[p].idle = 0 end
    end
  end
  if not events or #events == 0 then return nil end
  if (state.phase == "play" or state.phase == "color") and state.handTurns > M.MAX_TURNS then
    -- A hand this long goes to whoever holds the fewest points
    local best, low = 1, math.huge
    for q, other in ipairs(state.players) do
      local points = cards.handPoints(other.hand)
      if points < low then best, low = q, points end
    end
    log(state, "The hand has gone on too long: the fewest points wins it")
    endHand(state, best, events)
  end
  -- A turn that began for someone the engine was already waiting on keeps that old clock: the first time it runs out only
  -- starts the turn's own (see timeout)
  if (state.phase == "play" or state.phase == "color") and (state.turnNo ~= turnNo or state.handNo ~= handNo) then
    for _, player in ipairs(state.players) do player.carry = false end
    local current = state.players[state.turn]
    if not current.bot and before[current.seat] then current.carry = true end
  end
  return events
end

function M.auto(state, seat)
  if seat == nil then return "bot", nil end
  return "timeout", nil
end

-- ------------------------------------------------------------------ the buttons

local function button(id, label, color, extra)
  local b = { id = id, label = label, color = color or "panel2" }
  if color == "win" or color == "gold" or color == "accent" then b.textColor = "ink" end
  for key, value in pairs(extra or {}) do b[key] = value end
  return b
end

local COLOR_BUTTON = { r = { "RED", "red" }, y = { "YELLOW", "gold" }, g = { "GREEN", "win" }, b = { "BLUE", "blue" } }
M.COLOR_BUTTON = COLOR_BUTTON

local function colorButtons(list)
  for _, c in ipairs(cards.COLORS) do
    local entry = COLOR_BUTTON[c]
    list[#list + 1] = button("color", entry[1], entry[2], { value = c })
  end
  return list
end

function M.actions(state, seat)
  local p = playerOfSeat(state, seat)
  if not p or state.phase == "over" then return {} end
  local player = state.players[p]
  local list = {}
  local phase = state.phase
  if phase == "goal" then
    if firstHuman(state) ~= p then return list end
    list[1] = button("goal", "TO 500", "win", { value = 500, sub = "the full game" })
    list[2] = button("goal", "TO 200", "gold", { value = 200, sub = "a shorter one" })
    list[3] = button("goal", "ONE HAND", "blue", { value = 0, sub = "one hand wins" })
    return list
  end
  if phase == "scored" then
    if not player.ready then list[1] = button("next", "NEXT HAND", "win") end
    return list
  end
  local catchable = canCatch(state, p)
  local function catchButton()
    local who = state.window and state.players[state.window.p]
    list[#list + 1] = button("catch", "CATCH!", "red", { sub = who and who.name:sub(1, 10) or nil })
  end
  if state.turn ~= p then
    if catchable then catchButton() end
    return list
  end
  if phase == "color" then return colorButtons(list) end
  if player.ui.pick then
    colorButtons(list)
    list[#list + 1] = button("back", "BACK", "panel2")
    return list
  end
  if phase == "drawn" then
    local drawn = state.drawn
    list[#list + 1] = button("play", "PLAY IT", "win", { value = drawn })
    list[#list + 1] = button("keep", "KEEP", "panel2")
  else
    list[#list + 1] = button("draw", "DRAW", "blue")
  end
  if #player.hand == 2 then
    list[#list + 1] = button("uno", player.ui.armed and "SAID" or "UNO!", "gold",
      { disabled = player.ui.armed, sub = player.ui.armed and "now play" or "then play" })
  end
  if catchable then catchButton() end
  if phase == "play" and pages(state, p) > 1 then
    list[#list + 1] = button("page", "<", "panel2", { value = -1, disabled = player.ui.page <= 1 })
    list[#list + 1] = button("page", ">", "panel2", { value = 1, disabled = player.ui.page >= pages(state, p) })
  end
  return list
end

-- ------------------------------------------------------------------ what each seat may see

local function publicPlayers(state)
  local out = {}
  for p, player in ipairs(state.players) do
    out[p] = {
      name = player.name, bot = player.bot, seat = player.seat or false, count = #player.hand, score = player.score,
      said = player.said and #player.hand == 1, idle = player.idle, ready = player.ready, gain = player.gain or 0,
    }
  end
  return out
end

local function publicView(state)
  local view = {
    phase = state.phase, goal = state.goal, handNo = state.handNo, turn = state.turn, dir = state.dir, color = state.color,
    top = top(state) or false, deck = #state.deck, pile = #state.pile, dealer = state.dealer, turnNo = state.turnNo,
    players = publicPlayers(state), log = copyList(state.log), recent = {}, window = false, winner = state.winner,
    lastHand = false, chooser = firstHuman(state) or false,
  }
  for i, item in ipairs(state.recent) do view.recent[i] = { p = item.p, card = item.card, color = item.color or "w" } end
  local window = state.window
  if window then view.window = { p = window.p, noticed = window.noticed or false } end
  local last = state.lastHand
  if last then
    view.lastHand = { winner = last.winner, points = last.points, hand = last.hand, rows = {} }
    for p, row in ipairs(last.rows) do view.lastHand.rows[p] = { cards = row.cards, points = row.points } end
  end
  return view
end

function M.viewFor(state, seat)
  local view = publicView(state)
  local p = playerOfSeat(state, seat)
  if not p then return view end
  local player = state.players[p]
  view.me = p
  view.hand = copyList(player.hand)
  view.playable = M.playable(state, p)
  view.pick = player.ui.pick or false
  view.armed = player.ui.armed
  view.pages = pages(state, p)
  view.page = math.min(player.ui.page, view.pages)
  view.drawn = (state.phase == "drawn" and state.turn == p) and state.drawn or false
  view.canCatch = canCatch(state, p)
  return view
end

function M.done(state)
  return state.phase == "over"
end

function M.nets(state)
  local out = {}
  for _, player in ipairs(state.players) do
    if player.seat then out[player.seat] = 0 end
  end
  return out
end

function M.result(state, seat)
  local winner = state.winner
  if winner == 0 then return { kind = "push", title = "NO WINNER", detail = "The game ended early" } end
  local name = nameOf(state, winner)
  local p = playerOfSeat(state, seat)
  local detail
  if state.goal == 0 then
    detail = name .. " went out first and scored " .. state.players[winner].score
  else
    detail = scoreText(state)
  end
  if p == winner then return { kind = "win", title = "YOU WIN!", detail = detail } end
  if p then return { kind = "lose", title = string.upper(name) .. " WINS", detail = "You scored " .. state.players[p].score .. ". " .. detail } end
  return { kind = "win", title = string.upper(name) .. " WINS", detail = detail }
end

return M
