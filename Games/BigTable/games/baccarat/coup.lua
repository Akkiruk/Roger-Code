-- games/baccarat/coup.lua
-- One coup of punto banco from an eight-deck shoe, the part of Games/Baccarat/baccarat_rules.lua a shared table needs, with the same
-- names. Big Table's package does not carry Games/Baccarat, so baccarat_rules cannot be required on a real cabinet. Tests/group_baccarat_test.lua
-- plays this file against baccarat_rules and fails if the two ever differ. With Games/Baccarat in the cabinet's manifest-bundle, this
-- whole file could become one require.

local deck = require("lib.casino.deck")

local M = {
  DECKS = 8,
  BURN = 1,
  RESHUFFLE_BELOW = 30,
  PAYS = { player = 1, banker = 1, tie = 8 },
  COMMISSION = 5,        -- percent of a Banker win, rounded up to a whole token
  MIN_BANKER = 20,       -- below this the commission is more than 5% of the bet by a long way
  NATURAL = 8,           -- two cards on this or more end the coup
  ROAD_KEPT = 26,        -- results on the road, which is all the strip on the table can hold
}

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

local function takeShoe(keep, rng)
  local shoe = keep.shoe
  keep.shoe = nil
  if shoe and #shoe >= M.RESHUFFLE_BELOW then return shoe, false end
  keep.shuffled = true -- the engine keeps this round's seed as the shoe's, secret until the shoe ends
  shoe = deck.shuffle(deck.fresh(M.DECKS), rng)
  for _ = 1, M.BURN do deck.draw(shoe) end
  return shoe, true
end

--- A round holds the road as it stood when it opened, because keep gets its result in the settle, before the cards have played.
-- The road is a string, one letter a coup, newest first: "PBT" is Player last, Banker before that, a Tie before that.
function M.new(bet, rng, keep)
  local shoe, fresh = takeShoe(keep or {}, rng)
  return { bet = bet, cards = shoe, player = {}, banker = {}, road = keep and keep.road or "" }, { { type = "start", fresh = fresh } }
end

--- The road with one more coup on it.
function M.addToRoad(road, winner)
  return (winner:sub(1, 1):upper() .. (road or "")):sub(1, M.ROAD_KEPT)
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

function M.act(state, id)
  local events = {}
  if state.over then return events end
  if M.PAYS[id] and (id ~= "banker" or state.bet >= M.MIN_BANKER) then
    state.side = id
    state.over = true
    events[1] = { type = "side", side = id }
    coup(state, events)
  end
  return events
end

--- Hand the shoe to the next round. It leaves the state, so the two never share a table.
function M.finish(state, keep)
  keep.shoe = state.cards
  state.cards = {}
  if state.winner then keep.road = M.addToRoad(keep.road, state.winner) end
end

return M
