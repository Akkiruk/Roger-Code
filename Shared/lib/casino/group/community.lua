-- community.lua
-- Fixed limit community card poker for group tables: Texas Hold'em and Omaha on Big Table, Hold'em for two on Duel. One set of rules
-- and one set of pictures. Each game's plugin.lua is a few lines that name its variant. See Games/BigTable/games/README.md.
--
-- A hand: the two left of the button post the blinds, hole cards, a betting round, the flop, a round, the turn, a round, the river, a
-- round, showdown. The bet is the small size pre-flop and on the flop, the big size on the turn and river. A round allows a bet and
-- three raises, and the big blind counts as the bet. With two players the button posts the small blind and acts first pre-flop, then
-- last on every street after.
--
-- Omaha gives four hole cards, and a hand must use exactly two of them with exactly three from the board.
--
-- A blind too short to post goes all-in for what it has, and the table still calls the full big blind. A raise too short to be a full
-- raise is allowed as an all-in. Half a bet or more counts as a raise, and less only sets a new price: it uses up none of the bets, and
-- anyone who has already acted may call or fold but not raise. Nobody is asked to act with nobody left to bet against.
--
-- Chips are tracked as on Poker Table: stack behind, bet this round, total in the pot. pokertable_rules works out side pots and hands
-- them out from the totals at showdown, and an uncalled bet comes back as a pot only its owner can win.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local rounding = require("lib.casino.group.rounding")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local pokertable = require("pokertable_rules")

local C = theme.C

local M = {
  SMALL_BLIND = 5,
  BIG_BLIND = 10,
  SMALL = 10,      -- the bet pre-flop and on the flop
  BIG = 20,        -- the bet on the turn and river
  MAX_BETS = 4,    -- a bet and three raises, each round
}

local VARIANTS = {
  holdem = { hole = 2 },
  omaha = { hole = 4, exact = true },
}

local NEXT_STREET = { preflop = "flop", flop = "turn", turn = "river" }
local STREET_CARDS = { flop = 3, turn = 1, river = 1 }
local STREET_NAMES = { preflop = "PRE-FLOP", flop = "FLOP", turn = "TURN", river = "RIVER", over = "SHOWDOWN" }

-- ------------------------------------------------------------------ what a hand is worth

--- Every way of taking want cards from list, passed to visit in a table that is reused.
local function choose(list, want, visit)
  local picked = {}
  local function step(from, depth)
    if depth > want then
      visit(picked)
      return
    end
    for index = from, #list - (want - depth) do
      picked[depth] = list[index]
      step(index + 1, depth + 1)
    end
  end
  step(1, 1)
end

--- The best score of exactly two of hole and exactly three of board.
function M.omahaScore(hole, board)
  local best, five = nil, {}
  choose(hole, 2, function(pair)
    five[1], five[2] = pair[1], pair[2]
    choose(board, 3, function(three)
      five[3], five[4], five[5] = three[1], three[2], three[3]
      local value = poker.evaluate(five)
      if not best or value > best then best = value end
    end)
  end)
  return best
end

--- What hole and board are worth in this variant. Needs at least a flop.
function M.score(variant, hole, board)
  if VARIANTS[variant].exact then return M.omahaScore(hole, board) end
  local cards = {}
  for _, card in ipairs(hole) do cards[#cards + 1] = card end
  for _, card in ipairs(board) do cards[#cards + 1] = card end
  return (poker.evaluate(cards))
end

-- ------------------------------------------------------------------ the hand

local function canAct(player)
  return not player.folded and not player.allin
end

local function isLive(player)
  return not player.folded
end

--- The first player left of from, clockwise by list order, who passes the test.
local function leftOf(state, from, test)
  local total = #state.players
  for step = 1, total do
    local index = (from + step - 1) % total + 1
    if test(state.players[index]) then return index end
  end
  return nil
end

local function count(state, test)
  local total = 0
  for _, player in ipairs(state.players) do
    if test(player) then total = total + 1 end
  end
  return total
end

local function find(state, seat)
  if seat == nil then return nil end
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

--- Move chips from a stack to the pot. A short stack puts in what it has and is all-in.
local function put(player, amount)
  local paid = math.min(amount, player.stack)
  player.stack = player.stack - paid
  player.bet = player.bet + paid
  player.total = player.total + paid
  if player.stack == 0 then player.allin = true end
  return paid
end

--- How many others can still put chips in.
local function opponents(state, player)
  local total = 0
  for _, other in ipairs(state.players) do
    if other ~= player and canAct(other) then total = total + 1 end
  end
  return total
end

--- What this player must add to stay in. With nobody left to raise them, only what someone really bet has to be matched.
local function owes(state, player)
  local target = state.current
  if opponents(state, player) == 0 then
    local top = 0
    for _, other in ipairs(state.players) do
      if other ~= player and isLive(other) then top = math.max(top, other.bet) end
    end
    target = math.min(target, top)
  end
  return math.max(0, target - player.bet)
end

--- Whether the betting has to come to this player.
local function isDue(state, player)
  if not canAct(player) then return false end
  if owes(state, player) > 0 then return true end
  return not player.acted and opponents(state, player) > 0
end

local function finishHand(state, events)
  state.phase = "over"
  state.turn = nil
  state.uncontested = count(state, isLive) == 1
  if not state.uncontested then
    for _, player in ipairs(state.players) do
      if isLive(player) then
        player.score = M.score(state.variant, player.hole, state.board)
        player.handName = poker.describe(player.score)
        player.shown = true
      end
    end
  end
  state.pots = pokertable.pots(state.players)
  pokertable.award(state.pots, state.players, state.button)
  for _, player in ipairs(state.players) do
    player.net = player.won - player.total
    player.stack = player.start + player.net
  end
  rounding.take(state)
  events[#events + 1] = { type = "showdown", uncontested = state.uncontested }
end

--- Deal the next street and open its betting. Everyone all-in just sees the cards come.
local function nextStreet(state, events)
  local phase = NEXT_STREET[state.phase]
  while phase do
    for _ = 1, STREET_CARDS[phase] do state.board[#state.board + 1] = deck.draw(state.deck) end
    state.phase = phase
    state.size = (phase == "flop") and M.SMALL or M.BIG
    state.current, state.bets = 0, 0
    for _, player in ipairs(state.players) do
      player.bet, player.acted, player.last = 0, false, nil
    end
    events[#events + 1] = { type = "street", phase = phase, shown = #state.board, count = STREET_CARDS[phase] }
    if count(state, canAct) >= 2 then
      state.turn = leftOf(state, state.button, canAct)
      return
    end
    state.turn = nil
    phase = NEXT_STREET[phase]
  end
  finishHand(state, events)
end

--- After a betting action: pass the turn, or close the round.
local function moveOn(state, events)
  if count(state, isLive) == 1 then
    finishHand(state, events)
    return
  end
  local nextUp = leftOf(state, state.turn, function(player) return isDue(state, player) end)
  if nextUp then
    state.turn = nextUp
  else
    nextStreet(state, events)
  end
end

--- Deal a hand. entries: { seat, name, stack } in seat order, clockwise. button: an index into entries.
local function deal(variant, entries, button, rng)
  local state = {
    variant = variant,
    players = {},
    button = button,
    board = {},
    deck = deck.shuffle(deck.fresh(1), rng),
    phase = "preflop",
    size = M.SMALL,
    current = M.BIG_BLIND,
    bets = 1,
  }
  local total = #entries
  for index, entry in ipairs(entries) do
    state.players[index] = {
      seat = entry.seat, name = entry.name, start = entry.stack, stack = entry.stack,
      bet = 0, total = 0, hole = {}, folded = false, allin = false, acted = false,
    }
  end
  -- Two players: the button is the small blind. More: the blinds are the two to its left
  local smallAt = total == 2 and button or button % total + 1
  local bigAt = smallAt % total + 1
  put(state.players[smallAt], M.SMALL_BLIND)
  put(state.players[bigAt], M.BIG_BLIND)
  state.players[smallAt].blind = "SB"
  state.players[bigAt].blind = "BB"
  for _ = 1, VARIANTS[variant].hole do
    for step = 1, total do
      local player = state.players[(button + step - 1) % total + 1]
      player.hole[#player.hole + 1] = deck.draw(state.deck)
    end
  end
  local events = { { type = "deal", shown = 0 } }
  state.turn = leftOf(state, bigAt, function(player) return isDue(state, player) end)
  if not state.turn then nextStreet(state, events) end
  return state, events
end

-- ------------------------------------------------------------------ the rules, as the engine calls them

local rules = {}

function rules.waitingOn(state)
  if state.phase == "over" or not state.turn then return {} end
  return { state.players[state.turn].seat }
end

function rules.actions(state, seat)
  local player = find(state, seat)
  if not player or not state.turn or state.players[state.turn] ~= player then return {} end
  local list = {}
  local toCall = owes(state, player)
  if toCall > 0 then
    local amount = math.min(toCall, player.stack)
    list[#list + 1] = { id = "fold", label = "FOLD", color = "red" }
    list[#list + 1] = { id = "call", label = toCall >= player.stack and "ALL-IN" or "CALL", color = "win", textColor = "ink",
      sub = tostring(amount), cost = amount }
  else
    list[#list + 1] = { id = "check", label = "CHECK", color = "win", textColor = "ink" }
  end
  -- Owing more after acting can only come from an all-in too short to reopen the betting
  if state.bets < M.MAX_BETS and player.stack > toCall and opponents(state, player) > 0 and not (player.acted and toCall > 0) then
    local cost = math.min(player.stack, toCall + state.size)
    local word = state.current == 0 and "BET" or "RAISE"
    list[#list + 1] = { id = "raise", label = cost == player.stack and "ALL-IN" or word, color = "blue", sub = tostring(cost), cost = cost }
  end
  return list
end

local function isOffered(state, seat, id)
  for _, action in ipairs(rules.actions(state, seat)) do
    if action.id == id then return true end
  end
  return false
end

--- Every event says how much of the board it may show, so a picture never gives a card away early in a hand that ran out.
local function stamp(events, shown)
  for _, ev in ipairs(events) do
    if ev.shown then shown = ev.shown else ev.shown = shown end
  end
  return events
end

function rules.act(state, seat, id)
  if state.phase == "over" or not isOffered(state, seat, id) then return {} end
  local player = find(state, seat)
  local before = #state.board
  local events = {}
  player.acted = true
  if id == "fold" then
    player.folded = true
    player.last = "FOLD"
  elseif id == "check" then
    player.last = "CHECK"
  elseif id == "call" then
    local paid = put(player, owes(state, player))
    player.last = player.allin and "ALL-IN" or "CALL"
    events[#events + 1] = { type = "chips", seat = seat, amount = paid }
  else
    local price = state.current
    local paid = put(player, owes(state, player) + state.size)
    state.current = math.max(state.current, player.bet)
    if price == 0 or (player.bet - price) * 2 >= state.size then
      state.bets = state.bets + 1
      for _, other in ipairs(state.players) do
        if other ~= player then other.acted = false end
      end
    end
    player.last = player.allin and "ALL-IN" or (state.current == player.bet and state.bets == 1 and "BET" or "RAISE")
    events[#events + 1] = { type = "chips", seat = seat, amount = paid }
  end
  events[#events + 1] = { type = "action", seat = seat, id = id }
  moveOn(state, events)
  return stamp(events, before)
end

--- Check if it is free, fold if not.
function rules.auto(state, seat)
  local player = find(state, seat)
  if player and owes(state, player) > 0 then return "fold" end
  return "check"
end

--- Everything in the pot right now.
local function potOf(state)
  local total = 0
  for _, player in ipairs(state.players) do total = total + player.total end
  return total
end

local function copy(list)
  local out = {}
  for index, item in ipairs(list) do out[index] = item end
  return out
end

--- Built field by field. Hole cards are only in a view at a showdown, and only for those who got that far.
function rules.viewFor(state, seat)
  local over = state.phase == "over"
  local turn = state.turn and state.players[state.turn]
  local view = {
    variant = state.variant, holes = VARIANTS[state.variant].hole, phase = state.phase, over = over,
    uncontested = state.uncontested, board = copy(state.board), pot = potOf(state), current = state.current, size = state.size,
    bets = state.bets, button = state.players[state.button].seat, turn = turn and turn.seat or nil, players = {},
  }
  for index, player in ipairs(state.players) do
    view.players[index] = {
      seat = player.seat, name = player.name, stack = player.stack, bet = player.bet, total = player.total,
      folded = player.folded, allin = player.allin, last = player.last, blind = player.blind,
      hole = player.shown and copy(player.hole) or nil, handName = player.shown and player.handName or nil,
      net = over and player.net or nil,
    }
  end
  local own = find(state, seat)
  if own then
    view.seat = own.seat
    view.hole = copy(own.hole)
    if not own.folded and #state.board >= 3 then view.hand = poker.describe(M.score(state.variant, own.hole, state.board)) end
    if turn == own then view.toCall = owes(state, own) end
  end
  return view
end

function rules.done(state)
  return state.phase == "over"
end

function rules.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net or 0 end
  return nets
end

--- The table's line, or one seat's.
function rules.result(state, seat)
  if state.phase ~= "over" then return { kind = "push", title = "HAND IN PLAY", detail = "" } end
  local player = find(state, seat)
  if not player then
    local line = pokertable.result(state)
    return { kind = "push", title = line.title, detail = line.detail }
  end
  local why = state.uncontested and "Everyone else folded" or player.handName
  if player.folded then why = "You folded" end
  local net = player.net or 0
  if net > 0 then return { kind = "win", title = "YOU WIN", detail = ui.signed(net) .. "  " .. why } end
  if net < 0 then return { kind = "lose", title = "YOU LOSE", detail = ui.signed(net) .. "  " .. why } end
  return { kind = "push", title = "EVEN", detail = why }
end

function rules.risk(state, seat)
  local player = find(state, seat)
  return player and player.total or 0
end

--- A variant's rules, as a plugin hands them to the engine.
function M.rules(variant)
  local out = {}
  for key, value in pairs(rules) do out[key] = value end
  out.new = function(entries, button, rng) return deal(variant, entries, button, rng) end
  return out
end

-- ------------------------------------------------------------------ pictures

local TILE_W, TILE_H = 5, 3
local BOX_W, BOX_H = 29, 10
local SUIT_CHARS = { [0] = "\5", [1] = "\4", [2] = "\3", [3] = "\6" }

--- A small card with room for a rank and suit. No card is its back.
local function tile(c, x, y, card)
  if card == nil then
    c:rect(x, y, TILE_W, TILE_H, C.card)
    c:rect(x + 1, y + 1, TILE_W - 2, 1, C.feltDark)
    return
  end
  local color = deck.isRed(card) and C.red or C.ink
  local text = deck.rankName(card) .. SUIT_CHARS[deck.suit(card)]
  c:rect(x, y, TILE_W, TILE_H, C.card)
  c:text(x + math.floor((TILE_W - #text) / 2), y + 1, text, color, C.card)
end

local function slot(c, x, y)
  c:rect(x, y, TILE_W, TILE_H, C.feltDark)
end

--- How many board cards to show now. Events say, so a card lands as its street plays.
local function boardCount(view, anim)
  local total = #view.board
  local ev = anim and anim.ev
  if ev and type(ev.shown) == "number" then
    total = math.min(total, ev.shown)
    if ev.type == "street" and anim.t < 0.35 then total = total - (ev.count or 0) end
  end
  return math.max(0, total)
end

--- The five board cards, full size, centred on cx.
local function bigBoard(c, cx, y, view, anim)
  local shown = boardCount(view, anim)
  local xs = ui.fan(cx, 5, ui.CARD_W, c.w - 8, 3)
  for index, x in ipairs(xs) do
    if index <= shown then ui.card(c, x, y, view.board[index]) else ui.cardSlot(c, x, y) end
  end
end

--- The five board cards as tiles, from x.
local function tileBoard(c, x, y, view, anim)
  local shown = boardCount(view, anim)
  for index = 1, 5 do
    local at = x + (index - 1) * (TILE_W + 1)
    if index <= shown then tile(c, at, y, view.board[index]) else slot(c, at, y) end
  end
end

local function playerAt(view, seat)
  for _, player in ipairs(view.players) do
    if player.seat == seat then return player end
  end
  return nil
end

local function phaseName(view)
  if view.uncontested then return "HAND OVER" end
  return STREET_NAMES[view.phase] or ""
end

local function statusOf(player)
  if player.folded then return "FOLDED" end
  if player.allin then return "ALL-IN" end
  return player.last or ""
end

local function right(c, x, y, text, color, bg)
  c:text(x - #tostring(text) + 1, y, text, color, bg)
end

--- One player on the dealer's wall.
local function drawBox(c, x, y, view, player)
  local acting = view.turn == player.seat
  local won = view.over and (player.net or 0) > 0
  local bg = acting and C.gold or (won and C.win) or (player.folded and C.panel2) or C.panel
  local ink = (acting or won) and C.ink or C.text
  c:panel(x, y, BOX_W, BOX_H, bg)
  local mark = (view.button == player.seat and "D " or "") .. (player.blind or "")
  c:text(x + 2, y + 1, seatui.short(player.name, BOX_W - 10), ink, bg)
  right(c, x + BOX_W - 3, y + 1, mark, acting and C.ink or C.gold, bg)
  c:text(x + 2, y + 2, statusOf(player), player.folded and C.mute or ink, bg)
  if player.bet > 0 and not view.over then right(c, x + BOX_W - 3, y + 2, player.bet, ink, bg) end
  if not player.folded then
    for index = 1, view.holes do
      tile(c, x + 2 + (index - 1) * (TILE_W + 1), y + 4, player.hole and player.hole[index] or nil)
    end
  end
  if view.over then
    c:text(x + 2, y + 8, seatui.short(player.handName or "", BOX_W - 11), ink, bg)
    right(c, x + BOX_W - 3, y + 8, ui.signed(player.net or 0), ink, bg)
  end
end

--- The dealer's wall.
local function drawTable(c, view, anim)
  if not view.board then return end
  local _, top = seatui.tableArea(c)
  local cx = math.floor(c.w / 2) + 1
  c:bigCenter(cx, top + 1, "POT " .. ui.group(view.pot), C.gold, 1)
  c:textCenter(cx, top + 7, phaseName(view), C.text)
  bigBoard(c, cx, top + 9, view, anim)

  local players = view.players
  local columns = math.min(#players, 4)
  local y = top + 27
  for index, player in ipairs(players) do
    local row = math.floor((index - 1) / 4)
    local inRow = row == 0 and columns or (#players - 4)
    local across = (index - 1) % 4
    local x = cx + 1 - math.floor(inRow * (BOX_W + 1) / 2) + across * (BOX_W + 1)
    drawBox(c, x, y + row * (BOX_H + 1), view, player)
  end

  local turn = view.turn and playerAt(view, view.turn)
  if turn then
    c:bigCenter(cx, top + 51, seatui.short(turn.name, 10) .. " TO ACT", C.text, 1)
  end
  if not view.over then
    c:textCenter(cx, top + 59, "Blinds " .. M.SMALL_BLIND .. " and " .. M.BIG_BLIND .. ".  Bets " .. M.SMALL .. " then "
      .. M.BIG .. ", a bet and three raises.", C.mute)
  end
end

--- The line that says what is on the player: their turn and its price, or whose turn it is.
local function turnLine(view)
  if view.over then return nil end
  if view.seat and view.turn == view.seat then
    if (view.toCall or 0) > 0 then return "YOUR TURN: " .. view.toCall .. " TO CALL", C.gold end
    return "YOUR TURN", C.gold
  end
  local turn = view.turn and playerAt(view, view.turn)
  if turn then return "Waiting for " .. seatui.short(turn.name, 14), C.mute end
  return nil
end

--- A Big Table seat: this player's cards big, the board small, because the wall has it too.
local function drawSeat(c, view, anim)
  if not view.board then return end
  local _, top, w = seatui.area(c)
  local own = view.seat and playerAt(view, view.seat)
  c:text(3, top + 1, phaseName(view), C.gold)
  c:textCenter(math.floor(w / 2) + 1, top + 1, "POT " .. ui.group(view.pot), C.gold)
  if own and own.bet > 0 then right(c, w - 2, top + 1, "Your bet " .. ui.group(own.bet), C.text) end

  if view.hole then
    local xs = ui.fan(math.floor(w / 2) + 1, #view.hole, ui.CARD_W, w - 4, 2)
    for index, card in ipairs(view.hole) do ui.card(c, xs[index], top + 3, card) end
  else
    c:textCenter(math.floor(w / 2) + 1, top + 10, "You are watching this hand", C.mute)
  end

  local y = top + 21
  tileBoard(c, 3, y, view, anim)
  local x = 3 + 5 * (TILE_W + 1) + 2
  if own and own.folded then
    c:text(x, y, "You folded", C.mute)
  elseif view.hand then
    c:text(x, y, view.hand, C.text)
  end
  local line, color = turnLine(view)
  if line then c:text(x, y + 2, line, color) end
end

--- One player's side of a Duel wall.
local function drawSide(c, x, y, view, player, hole)
  local w = 2 * ui.CARD_W + 2
  if not player then return end
  local acting = view.turn == player.seat
  local mark = view.button == player.seat and "  D" or ""
  c:text(x, y, seatui.short(player.name, 14) .. mark, acting and C.gold or C.text)
  right(c, x + w - 1, y, statusOf(player), player.folded and C.mute or C.text)
  if player.folded then
    ui.cardSlot(c, x, y + 1)
    ui.cardSlot(c, x + ui.CARD_W + 2, y + 1)
  else
    ui.card(c, x, y + 1, hole and hole[1] or nil)
    ui.card(c, x + ui.CARD_W + 2, y + 1, hole and hole[2] or nil)
  end
  local text = view.over and player.net and ui.signed(player.net) or (player.bet > 0 and ("BET " .. ui.group(player.bet))) or ""
  if text ~= "" then c:big(x, y + 19, text, view.over and (player.net > 0 and C.win or C.text) or C.gold, 1) end
end

--- A Duel wall. It has the whole picture to itself, and a wall with nobody looking gets the public view, with no private fields.
local function drawDuel(c, view, anim)
  if not view.board then return end
  local _, top = seatui.area(c)
  local cx = math.floor(c.w / 2) + 1
  c:bigCenter(cx, top + 1, "POT " .. ui.group(view.pot), C.gold, 1)
  c:textCenter(cx, top + 7, phaseName(view), C.text)
  bigBoard(c, cx, top + 9, view, anim)

  local first = view.seat and playerAt(view, view.seat) or view.players[1]
  local second
  for _, player in ipairs(view.players) do
    if player ~= first then second = second or player end
  end
  local y = top + 26
  local rightX = c.w - 2 - (2 * ui.CARD_W + 2)
  drawSide(c, 3, y, view, first, view.seat and view.hole or first.hole)
  drawSide(c, rightX, y, view, second, second and second.hole)

  local line, color = turnLine(view)
  if line then c:textCenter(cx, y + 4, line, color) end
  if view.hand then c:textCenter(cx, y + 2, view.hand, C.text) end
  if view.over then
    if first.handName then c:textCenter(cx, y + 2, seatui.short(first.handName, 30), C.text) end
    if second and second.handName then c:textCenter(cx, y + 4, "against " .. second.handName, C.text) end
  end
end

-- ------------------------------------------------------------------ the plugin

local function helpFor(variant)
  local lines = {}
  if variant == "omaha" then
    lines[#lines + 1] = "Everyone gets four cards and shares five on the table. Your hand must use exactly two of your four and exactly three from the table."
  else
    lines[#lines + 1] = "Everyone gets two cards and shares five on the table. The best five of your seven win."
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = { "THE BETTING", "gold" }
  lines[#lines + 1] = "Blinds are " .. M.SMALL_BLIND .. " and " .. M.BIG_BLIND .. ". Bets and raises are " .. M.SMALL
    .. " before the flop and on it, " .. M.BIG .. " on the turn and river. A round allows a bet and three raises."
  lines[#lines + 1] = "A short stack goes all-in and can win what it matched. Side pots take care of the rest."
  lines[#lines + 1] = ""
  lines[#lines + 1] = { "THE MONEY", "gold" }
  lines[#lines + 1] = "Nothing moves until a hand ends. Then losers pay and winners are paid. An odd chip in a split pot goes to the house."
  return lines
end

local function eventOf(ev)
  if ev.type == "deal" then return 0.6, "deal" end
  if ev.type == "street" then return 0.8, "flip" end
  if ev.type == "chips" then return 0.1, "chip" end
  if ev.type == "showdown" then return 0.6, "flip" end
  return 0.05, nil
end

--- A game's whole plugin. spec: id, variant, title, felt, tagline, minSeats, maxSeats, duel.
function M.plugin(spec)
  return {
    id = spec.id, title = spec.title, kind = "players", minSeats = spec.minSeats, maxSeats = spec.maxSeats,
    felt = spec.felt, tagline = spec.tagline,
    ante = M.BIG_BLIND, minBuy = 100, maxStack = 5000,
    help = function() return helpFor(spec.variant) end,
    event = eventOf,
    rules = M.rules(spec.variant),
    tableView = not spec.duel and { draw = drawTable } or nil,
    seatView = { draw = spec.duel and drawDuel or drawSeat },
  }
end

return M
