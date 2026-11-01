-- hilo_rules.lua
-- Higher or lower through one deck. Pure: no screen, no sound, no money.
-- Every guess is priced from the cards still in the deck, so no starting card is a trap: the first guess pays
-- RETURN / chance and each later guess pays 1 / chance. That makes the return the same at every point a player
-- can stop, whatever they do. Equal ranks lose.

local deck = require("lib.casino.deck")

local M = {
  RETURN = 0.96,        -- tokens back per token bet, at every stopping point
  MAX_GUESSES = 10,
  MAX_MULTIPLE = 50,    -- a streak that reaches this cashes out by itself
}

--- How many cards left in the deck beat the current one each way.
local function counts(state)
  local rank = deck.rank(state.current)
  local higher, lower = 0, 0
  for _, card in ipairs(state.cards) do
    local other = deck.rank(card)
    if other > rank then higher = higher + 1 end
    if other < rank then lower = lower + 1 end
  end
  return higher, lower, #state.cards
end

--- The multiple a correct guess would reach, from `wins` cards in `total`.
local function nextMultiple(state, wins, total)
  local step = total / wins
  if state.guesses == 0 then step = step * M.RETURN end
  return math.min(M.MAX_MULTIPLE, math.floor(state.multiple * step * 100) / 100)
end

local function winnings(state)
  return math.floor(state.bet * state.multiple) - state.bet
end

function M.maxWin(bet)
  return bet * (M.MAX_MULTIPLE - 1)
end

function M.new(bet, rng, _, _)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local state = { bet = bet, cards = cards, multiple = 1, guesses = 0, trail = {} }
  state.current = deck.draw(cards)
  state.trail[1] = state.current
  return state, { { type = "first", card = state.current } }
end

function M.actions(state)
  local higher, lower, total = counts(state)
  local list = {}
  if higher > 0 then
    list[#list + 1] = { id = "higher", label = "HIGHER", color = "blue",
      sub = ("x%.2f  %d%%"):format(nextMultiple(state, higher, total), math.floor(higher / total * 100 + 0.5)) }
  end
  if lower > 0 then
    list[#list + 1] = { id = "lower", label = "LOWER", color = "red",
      sub = ("x%.2f  %d%%"):format(nextMultiple(state, lower, total), math.floor(lower / total * 100 + 0.5)) }
  end
  if state.guesses > 0 and winnings(state) > 0 then
    list[#list + 1] = { id = "cash", label = "CASH OUT", color = "win", textColor = "ink",
      sub = "+" .. winnings(state) }
  end
  return list
end

--- The round ends here, and the card they would have turned next is shown. It stays in the deck: nothing was drawn.
local function cashOut(state)
  state.over = true
  state.next = state.cards[#state.cards]
  return { type = "cash", card = state.next }
end

local function guess(state, side, rng)
  local _ = rng
  local higher, lower, total = counts(state)
  local wins = side == "higher" and higher or lower
  local card = deck.draw(state.cards)
  local rank, was = deck.rank(card), deck.rank(state.current)
  local right = (side == "higher" and rank > was) or (side == "lower" and rank < was)
  local multiple = nextMultiple(state, wins, total)
  state.current = card
  state.trail[#state.trail + 1] = card
  state.guesses = state.guesses + 1
  if not right then
    state.over, state.lost = true, true
    state.tied = rank == was
    return { { type = "reveal", card = card, right = false, multiple = state.multiple } }
  end
  state.multiple = multiple
  local events = { { type = "reveal", card = card, right = true, multiple = multiple } }
  if state.guesses >= M.MAX_GUESSES or multiple >= M.MAX_MULTIPLE then events[2] = cashOut(state) end
  return events
end

function M.act(state, id, rng)
  if id == "cash" then return { cashOut(state) } end
  return guess(state, id, rng)
end

--- Nobody at the table: bank a streak, or take the likelier side when there is nothing to bank.
function M.auto(state)
  if state.guesses > 0 and winnings(state) > 0 then return "cash" end
  local higher, lower = counts(state)
  return higher >= lower and "higher" or "lower"
end

function M.done(state)
  return state.over == true
end

function M.risk(state)
  return state.bet
end

function M.net(state)
  if state.lost then return -state.bet end
  return winnings(state)
end

function M.result(state)
  if state.lost then
    return { kind = "lose", title = state.tied and "SAME RANK" or "WRONG", detail = "The streak ends at x" .. state.multiple }
  end
  if winnings(state) == 0 then return { kind = "push", title = "PUSH", detail = "Your bet comes back" } end
  return { kind = "win", title = "CASHED OUT", detail = ("x%.2f after %d guesses"):format(state.multiple, state.guesses) }
end

function M.finish()
end

return M
