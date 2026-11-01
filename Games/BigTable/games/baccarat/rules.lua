-- games/baccarat/rules.lua
-- Shared-coup baccarat. Every seat's bets go down in the lobby and the computer deals one coup for all of them, so nobody has a move and
-- the whole round is the computer's. Cards and payouts are coup.lua's, the same as Games/Baccarat. Pure: no screen, no sound, no money.
-- The deal is a move and not part of new, so the shoe's hash is on the table before any card and the final reveal waits for the money.

local base = require("games.baccarat.coup")

local M = {}

local SIDES = { "player", "banker", "tie" }
local NAMES = { player = "Player", banker = "Banker", tie = "Tie" }

--- What stands from an entry, one figure a side, and any Banker bet too small to take. The bet panel cannot stop that happening:
-- 10 on each of two sides passes the table's minimum, and a host short of cover can cut a Banker bet below 20. It nets nothing.
local function stakes(entry)
  local source = entry.bets or { player = entry.bet }
  local bets, void = {}, 0
  for _, side in ipairs(SIDES) do
    local amount = source[side]
    if type(amount) == "number" and amount > 0 then
      if side == "banker" and amount < base.MIN_BANKER then
        void = amount
      else
        bets[side] = amount
      end
    end
  end
  return bets, void
end

--- What a set of bets nets on a winner. On a tie Player and Banker bets push.
local function netOn(bets, winner)
  local player, banker, tie = bets.player or 0, bets.banker or 0, bets.tie or 0
  if winner == "tie" then return base.winOn("tie", tie) end
  if winner == "player" then return base.winOn("player", player) - banker - tie end
  return base.winOn("banker", banker) - player - tie
end

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

function M.new(entries, _, rng, keep)
  local coup, events = base.new(0, rng, keep)
  local players = {}
  for index, entry in ipairs(entries) do
    local bets, void = stakes(entry)
    players[index] = { seat = entry.seat, name = entry.name, bets = bets, void = void, net = 0 }
  end
  return { coup = coup, players = players, fresh = events[1].fresh }, events
end

--- Nobody ever has a move: bets are in before the round starts, and the deal is the computer's.
function M.waitingOn()
  return {}
end

function M.actions()
  return {}
end

--- The computer's deal, once. coup.lua wants a side to deal for and every side here is someone's, so it gets the one with no minimum.
function M.act(state, seat, id)
  if seat ~= nil or id ~= "deal" or state.coup.over then return {} end
  local events = base.act(state.coup, "tie")
  table.remove(events, 1) -- the "side" event, which means nothing at a table of many
  for _, player in ipairs(state.players) do
    player.net = netOn(player.bets, state.coup.winner)
  end
  return events
end

function M.auto()
  return "deal"
end

local function copy(list)
  local out = {}
  for index, value in ipairs(list) do out[index] = value end
  return out
end

--- Every bet is on the felt for all to see. Only cards that have been dealt are in a view, and never the shoe.
function M.viewFor(state, seat)
  local coup = state.coup
  local over = coup.over == true
  local view = {
    over = over, fresh = state.fresh, road = coup.road, winner = coup.winner,
    player = copy(coup.player), banker = copy(coup.banker), bets = {},
  }
  for index, player in ipairs(state.players) do
    local line = { seat = player.seat, name = player.name, net = over and player.net or nil }
    for _, side in ipairs(SIDES) do line[side] = player.bets[side] end
    view.bets[index] = line
  end
  local own = seat and find(state, seat)
  if own then
    view.own = { void = own.void, net = over and own.net or nil }
    for _, side in ipairs(SIDES) do view.own[side] = own.bets[side] end
  end
  return view
end

function M.done(state)
  return state.coup.over == true
end

function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net end
  return nets
end

function M.result(state, seat)
  local coup = state.coup
  local winner = coup.winner
  local title = winner == "tie" and "TIE" or (NAMES[winner]:upper() .. " WINS")
  local score = ("Player %d, Banker %d"):format(base.total(coup.player), base.total(coup.banker))
  local player = seat and find(state, seat)
  if not player then return { kind = "push", title = title, detail = score } end
  if not next(player.bets) then
    return { kind = "push", title = title, detail = ("%s. Banker needs a bet of %d, so nothing stood"):format(score, base.MIN_BANKER) }
  end
  local net = player.net
  if net > 0 then
    if winner == "banker" and player.bets.banker then
      score = score .. (". Commission %d"):format(base.commission(player.bets.banker))
    end
    return { kind = "win", title = title, detail = ("%s. You win %d"):format(score, net) }
  elseif net == 0 then
    return { kind = "push", title = title, detail = score .. ". Your bets push" }
  end
  return { kind = "lose", title = title, detail = ("%s. You lose %d"):format(score, -net) }
end

--- The most a seat's bets can win: each side coming up, net of what the others lose. Bets too small to stand are left out, as in new.
function M.maxWin(entry)
  local bets = stakes(entry)
  return math.max(0, netOn(bets, "player"), netOn(bets, "banker"), netOn(bets, "tie"))
end

--- What really stood. A bet that pushed was still wagered.
function M.risk(state, seat)
  local player = find(state, seat)
  if not player then return 0 end
  local sum = 0
  for _, side in ipairs(SIDES) do sum = sum + (player.bets[side] or 0) end
  return sum
end

function M.finish(state, keep)
  base.finish(state.coup, keep)
end

return M
