-- games/indianpoker/rules.lua
-- Heads-up Indian Poker, also called Blind Man's Bluff. Each player holds one card to their forehead, so a player sees the other's card
-- and never their own. That reversal is the whole game: viewFor(state, seat) holds the other player's card and not this seat's.
--
-- A hand: both ante, a card each from a fresh deck, one round of fixed-limit betting, and both cards turn over. The player the button
-- sits with acts first. A round allows a bet and two raises. Ace is high, suits do not rank, equal ranks split the pot.
--
-- A short stack goes all-in as it does in lib/casino/group/community.lua, with one rule less. There a raise of under half a bet leaves the
-- others unable to raise again. With two players a raise that short is always an all-in, so there is nobody left to raise anyway.
-- A stack that cannot ante goes all-in for what it has, and a hand with nobody left to bet against goes straight to the cards.
--
-- Chips only ever count up to what both put in: what one player has in above the other comes back to them. So a pot is always twice
-- what each has at stake, a split is always even, and there is never an odd chip for lib/casino/group/rounding.lua to take.

local deck = require("lib.casino.deck")
local ui = require("lib.casino.ui")

local M = {
  ANTE = 10,
  BET = 20,
  MAX_BETS = 3,  -- a bet and two raises
}

local WORDS = { [11] = "JACK", [12] = "QUEEN", [13] = "KING", [14] = "ACE" }

-- ------------------------------------------------------------------ the hand

local function find(state, seat)
  if seat == nil then return nil end
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

--- The player across from this one.
local function across(state, player)
  return state.players[1] == player and state.players[2] or state.players[1]
end

local function canAct(player)
  return not player.folded and not player.allin
end

--- Move chips from a stack to the pot. A short stack puts in what it has and is all-in.
local function put(player, amount)
  local paid = math.min(amount, player.stack)
  player.stack = player.stack - paid
  player.total = player.total + paid
  if player.stack == 0 then player.allin = true end
  return paid
end

--- What this player must add to stay in.
local function owes(state, player)
  return math.max(0, state.current - player.total)
end

--- Whether the betting has to come to this player, after the player across from them has moved.
local function isDue(state, player)
  if not canAct(player) then return false end
  if owes(state, player) > 0 then return true end
  return not player.acted and canAct(across(state, player))
end

--- What both players have in. It is all that can change hands.
local function matched(state)
  return math.min(state.players[1].total, state.players[2].total)
end

--- The winner, by a fold or by the cards. Nil is a split.
local function winnerOf(state)
  local first, second = state.players[1], state.players[2]
  if first.folded then return second end
  if second.folded then return first end
  local a, b = deck.rank(first.card), deck.rank(second.card)
  if a > b then return first end
  if b > a then return second end
  return nil
end

--- Both cards turn over, a fold included, and the money is settled from what both put in.
local function finishHand(state, events)
  local winner = winnerOf(state)
  local stake = matched(state)
  state.phase = "over"
  state.turn = nil
  state.uncontested = state.players[1].folded or state.players[2].folded
  state.pot = stake * 2
  state.winner = winner and winner.seat or nil
  for _, player in ipairs(state.players) do
    player.net = winner == nil and 0 or (player == winner and stake or -stake)
    player.stack = player.start + player.net
  end
  events[#events + 1] = { type = "reveal" }
end

--- After a betting action: pass the turn, or turn the cards over.
local function moveOn(state, player, events)
  local other = across(state, player)
  if player.folded or not isDue(state, other) then
    finishHand(state, events)
  else
    state.turn = other == state.players[1] and 1 or 2
  end
end

--- Deal a hand. entries: { seat, name, stack }, two of them. button: an index into entries.
local function deal(entries, button, rng)
  local state = {
    players = {},
    button = button,
    turn = button,
    phase = "bet",
    bets = 0,
    current = 0,
  }
  for index, entry in ipairs(entries) do
    state.players[index] = {
      seat = entry.seat, name = entry.name, start = entry.stack, stack = entry.stack,
      total = 0, folded = false, allin = false, acted = false,
    }
  end
  for _, player in ipairs(state.players) do
    put(player, M.ANTE)
    state.current = math.max(state.current, player.total)
  end
  -- The deck stops here: it has nothing else to do, and what is not in the state cannot leak from it
  local cards = deck.shuffle(deck.fresh(1), rng)
  local dealtFirst = button % 2 + 1
  state.players[dealtFirst].card = deck.draw(cards)
  state.players[button].card = deck.draw(cards)
  local events = { { type = "deal" } }
  if not (canAct(state.players[1]) and canAct(state.players[2])) then finishHand(state, events) end
  return state, events
end

-- ------------------------------------------------------------------ the rules, as the engine calls them

local rules = { new = deal }

function rules.waitingOn(state)
  if state.phase == "over" then return {} end
  return { state.players[state.turn].seat }
end

function rules.actions(state, seat)
  local player = find(state, seat)
  if state.phase == "over" or not player or state.players[state.turn] ~= player then return {} end
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
  if state.bets < M.MAX_BETS and player.stack > toCall and canAct(across(state, player)) then
    local cost = math.min(player.stack, toCall + M.BET)
    local word = state.bets == 0 and "BET" or "RAISE"
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

function rules.act(state, seat, id)
  if not isOffered(state, seat, id) then return {} end
  local player = find(state, seat)
  local events = {}
  player.acted = true
  state.lastSeat = seat
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
    local word = state.bets == 0 and "BET" or "RAISE"
    local paid = put(player, owes(state, player) + M.BET)
    state.current = math.max(state.current, player.total)
    state.bets = state.bets + 1
    across(state, player).acted = false
    player.last = player.allin and "ALL-IN" or word
    events[#events + 1] = { type = "chips", seat = seat, amount = paid, raise = true }
  end
  events[#events + 1] = { type = "action", seat = seat, id = id }
  moveOn(state, player, events)
  return events
end

--- Check if it is free, fold if not.
function rules.auto(state, seat)
  local player = find(state, seat)
  if player and owes(state, player) > 0 then return "fold" end
  return "check"
end

--- Everything in the pot. Once the hand is over that is only what both matched.
local function potOf(state)
  if state.pot then return state.pot end
  return state.players[1].total + state.players[2].total
end

--- Built field by field. Until the hand is over the only card in a view is the other player's, and only in the view of a seat.
-- Nothing else here may read a card: the public view holds none, and neither does what a seat is told about itself.
function rules.viewFor(state, seat)
  local over = state.phase == "over"
  local turn = not over and state.players[state.turn] or nil
  local view = {
    over = over, uncontested = state.uncontested, winner = state.winner, pot = potOf(state), size = M.BET,
    bets = state.bets, maxBets = M.MAX_BETS, button = state.players[state.button].seat, turn = turn and turn.seat or nil,
    lastSeat = state.lastSeat, players = {},
  }
  for index, player in ipairs(state.players) do
    view.players[index] = {
      seat = player.seat, name = player.name, stack = player.stack, total = player.total,
      folded = player.folded, allin = player.allin, last = player.last,
      card = over and player.card or nil, net = over and player.net or nil,
    }
  end
  local own = find(state, seat)
  if own then
    view.seat = own.seat
    view.theirs = across(state, own).card
    if turn == own then view.toCall = math.min(owes(state, own), own.stack) end
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

--- A card as a sentence says it: "an ACE", "a 9".
local function named(card)
  local rank = deck.rank(card)
  local word = WORDS[rank] or tostring(rank)
  return ((rank == 14 or rank == 8) and "an " or "a ") .. word
end

--- What happened, from one seat. Only ever asked once the hand is over.
local function story(state, player)
  local other = across(state, player)
  if player.folded then return "You folded " .. named(player.card) .. ". " .. other.name .. " had " .. named(other.card) end
  if other.folded then return other.name .. " folded " .. named(other.card) .. ". You had " .. named(player.card) end
  if not state.winner then return "You both held " .. named(player.card) end
  return "You had " .. named(player.card) .. ", " .. other.name .. " had " .. named(other.card)
end

--- The table's line.
local function tableLine(state)
  if not state.winner then return { kind = "push", title = "SPLIT POT", detail = "Both held " .. named(state.players[1].card) } end
  local winner = find(state, state.winner)
  local loser = across(state, winner)
  local detail = winner.name .. " had " .. named(winner.card) .. ", " .. loser.name .. " had " .. named(loser.card)
  if loser.folded then detail = loser.name .. " folded " .. named(loser.card) .. " to " .. named(winner.card) end
  return { kind = "push", title = winner.name:upper() .. " WINS", detail = detail }
end

function rules.result(state, seat)
  if state.phase ~= "over" then return { kind = "push", title = "HAND IN PLAY", detail = "" } end
  local player = find(state, seat)
  if not player then return tableLine(state) end
  local net = player.net or 0
  if not state.winner then return { kind = "push", title = "SPLIT POT", detail = story(state, player) } end
  if net > 0 then return { kind = "win", title = "YOU WIN", detail = ui.signed(net) .. "  " .. story(state, player) } end
  return { kind = "lose", title = "YOU LOSE", detail = ui.signed(net) .. "  " .. story(state, player) }
end

--- What was really staked: chips above what the other matched came back.
function rules.risk(state, seat)
  return find(state, seat) and matched(state) or 0
end

M.rules = rules

return M
