-- baccarat_rules.lua
-- Punto banco from an eight-deck shoe. Pure: no screen, no sound, no money.
-- The round opens on the amount alone. Choosing a side deals the whole coup, so the round ends on that one action
-- and the engine settles it before the cards play out. Nobody choosing a side simply cancels: no card has been seen.
-- "cancel" is an action id like the sides; the view offers it as a button on the felt, which leaves the bar to them.

local deck = require("lib.casino.deck")

local M = {
  DECKS = 8,
  BURN = 1,
  RESHUFFLE_BELOW = 30,
  PAYS = { player = 1, banker = 1, tie = 8 },
  COMMISSION = 5,        -- percent of a Banker win, rounded up to a whole token
  MIN_BANKER = 20,       -- below this the commission is more than 5% of the bet by a long way
  NATURAL = 8,           -- two cards on this or more end the coup
}

local NAMES = { player = "Player", banker = "Banker", tie = "Tie" }

function M.value(card)
  local rank = deck.rank(card)
  if rank == deck.ACE then return 1 end
  if rank >= 10 then return 0 end
  return rank
end

function M.total(cards)
  local total = 0
  for _, card in ipairs(cards) do total = total + M.value(card) end
  return total % 10
end

function M.playerDraws(total)
  return total <= 5
end

--- Whether the Banker draws. third is the value of the Player's third card, nil when the Player stood.
function M.bankerDraws(total, third)
  if third == nil then return total <= 5 end
  if total <= 2 then return true end
  if total == 3 then return third ~= 8 end
  if total == 4 then return third >= 2 and third <= 7 end
  if total == 5 then return third >= 4 and third <= 7 end
  if total == 6 then return third == 6 or third == 7 end
  return false
end

function M.commission(bet)
  return math.ceil(bet * M.COMMISSION / 100)
end

--- What a bet nets if its side comes up.
function M.winOn(side, bet)
  local win = bet * M.PAYS[side]
  if side == "banker" then win = win - M.commission(bet) end
  return win
end

--- Tie at 8:1 is the most a bet can win.
function M.maxWin(bet)
  return bet * M.PAYS.tie
end

local function takeShoe(keep, rng)
  local shoe = keep.shoe
  keep.shoe = nil
  if shoe and #shoe >= M.RESHUFFLE_BELOW then return shoe, false end
  shoe = deck.shuffle(deck.fresh(M.DECKS), rng)
  for _ = 1, M.BURN do deck.draw(shoe) end
  return shoe, true
end

function M.new(bet, rng, keep, _)
  local shoe, fresh = takeShoe(keep or {}, rng)
  return { bet = bet, cards = shoe, player = {}, banker = {} }, { { type = "start", fresh = fresh } }
end

function M.actions(state)
  if state.over then return {} end
  local list = {
    { id = "player", label = "PLAYER", color = "blue", sub = "wins +" .. M.winOn("player", state.bet) },
    { id = "tie", label = "TIE", color = "gold", textColor = "ink", sub = "wins +" .. M.winOn("tie", state.bet) },
  }
  if state.bet >= M.MIN_BANKER then
    list[#list + 1] = { id = "banker", label = "BANKER", color = "red", sub = "wins +" .. M.winOn("banker", state.bet) }
  end
  return list
end

local function deal(state, who, events)
  local card = deck.draw(state.cards)
  local hand = state[who]
  hand[#hand + 1] = card
  events[#events + 1] = { type = "deal", who = who, card = card, slot = #hand }
  return card
end

--- One coup from the first card to the last, following the third-card table.
local function coup(state, events)
  for _ = 1, 2 do
    deal(state, "player", events)
    deal(state, "banker", events)
  end
  local player, banker = M.total(state.player), M.total(state.banker)
  if player < M.NATURAL and banker < M.NATURAL then
    local third = nil
    if M.playerDraws(player) then third = M.value(deal(state, "player", events)) end
    if M.bankerDraws(banker, third) then deal(state, "banker", events) end
  end
  player, banker = M.total(state.player), M.total(state.banker)
  state.winner = player > banker and "player" or banker > player and "banker" or "tie"
  events[#events + 1] = { type = "outcome", winner = state.winner }
end

function M.act(state, id, _)
  local events = {}
  if state.over then return events end
  if id == "cancel" then
    state.over, state.cancelled = true, true
  elseif M.PAYS[id] and (id ~= "banker" or state.bet >= M.MIN_BANKER) then
    state.side = id
    state.over = true
    events[1] = { type = "side", side = id }
    coup(state, events)
  end
  return events
end

--- Nobody at the table: no side was chosen, so no bet stands.
function M.auto()
  return "cancel"
end

function M.done(state)
  return state.over == true
end

function M.risk(state)
  return state.bet
end

function M.net(state)
  if state.cancelled then return 0 end
  if state.winner == state.side then return M.winOn(state.side, state.bet) end
  if state.winner == "tie" then return 0 end
  return -state.bet
end

function M.result(state)
  if state.cancelled then
    return { kind = "push", title = "NO BET", detail = "No side was chosen, so nothing was wagered" }
  end
  local player, banker = M.total(state.player), M.total(state.banker)
  local score = ("Player %d, Banker %d"):format(player, banker)
  local net = M.net(state)
  local title = state.winner == "tie" and "TIE" or (NAMES[state.winner]:upper() .. " WINS")
  if net > 0 then
    if state.side == "banker" then
      score = score .. (". Commission %d"):format(M.commission(state.bet))
    end
    return { kind = "win", title = title, detail = score }
  elseif net == 0 then
    return { kind = "push", title = title, detail = "Your " .. NAMES[state.side] .. " bet pushes" }
  end
  return { kind = "lose", title = title, detail = score .. ". Your " .. NAMES[state.side] .. " bet loses" }
end

--- Hand the shoe to the next round. It leaves the state, so the two never share a table.
function M.finish(state, keep)
  keep.shoe = state.cards
  state.cards = {}
end

return M
