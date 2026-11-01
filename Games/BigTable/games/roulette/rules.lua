-- games/roulette/rules.lua
-- One wheel for up to eight seats. A seat's bet from the lobby is how much it may lay down this spin. When the round opens every seat
-- spreads that on its own screen at once, each with the same clock, and the computer spins when the last seat is done or the clock
-- runs out. Chips left down stay down, and anything not laid was never bet.
--
-- The number is drawn in the spin, after the last chip, so nothing in a state or a view knows it before then. It is the only thing
-- that uses the rng, which makes it the first number of the round's stream and the FAIR page can show that.

local limits = require("lib.casino.limits")
local wheel = require("games.roulette.wheel")

local M = {}

local CHIPS_SHOWN = 5   -- with UNDO, CLEAR, REPEAT, X2 and DONE that fills the two rows of small buttons
local UNDO_DEPTH = 10   -- wagers kept for UNDO. The state goes in the journal at every press, so it stays short

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

local function chipsFor(budget)
  local chips = limits.chips(budget)
  while #chips > CHIPS_SHOWN do table.remove(chips, 1) end
  return chips
end

local function chipLabel(value)
  return value >= 1000 and (value / 1000 .. "K") or tostring(value)
end

local function isMode(value)
  for _, mode in ipairs(wheel.MODES) do
    if mode == value then return true end
  end
  return false
end

local function isChip(player, value)
  for _, chip in ipairs(chipsFor(player.budget)) do
    if chip == value then return true end
  end
  return false
end

--- entries is { seat, name, bet }: bet is the most this seat can lay down, and what the host stands behind.
function M.new(entries, _, _, keep)
  local recent, last = {}, keep and keep.last or {}
  for i, n in ipairs(keep and keep.recent or {}) do recent[i] = n end
  local players = {}
  for index, entry in ipairs(entries) do
    local chips = chipsFor(entry.bet)
    local before = last[entry.name]
    players[index] = {
      seat = entry.seat, name = entry.name, budget = entry.bet, spots = {}, undo = {}, mode = wheel.MODES[1],
      chip = chips[math.min(2, #chips)], done = false, net = 0,
      again = (before and wheel.stakeOf(before) <= entry.bet) and wheel.copyWager(before) or nil,
    }
  end
  return { players = players, recent = recent, over = false }, { { type = "open" } }
end

function M.waitingOn(state)
  local list = {}
  if state.over then return list end
  for _, player in ipairs(state.players) do
    if not player.done then list[#list + 1] = player.seat end
  end
  return list
end

function M.actions(state, seat)
  local player = find(state, seat)
  if not player or player.done or state.over then return {} end
  local stake = wheel.stakeOf(player.spots)
  local list = {}
  for _, chip in ipairs(chipsFor(player.budget)) do
    local on = chip == player.chip
    list[#list + 1] = { id = "chip", value = chip, label = chipLabel(chip), small = true,
      color = on and "gold" or "blue", textColor = on and "ink" or "text" }
  end
  list[#list + 1] = { id = "undo", label = "UNDO", color = "panel2", small = true, disabled = #player.undo == 0 }
  list[#list + 1] = { id = "clear", label = "CLEAR", color = "panel2", small = true, disabled = stake == 0 }
  list[#list + 1] = { id = "again", label = "REPEAT", color = "panel2", small = true, disabled = player.again == nil }
  list[#list + 1] = { id = "double", label = "X2", color = "panel2", small = true, disabled = stake == 0 or stake * 2 > player.budget }
  list[#list + 1] = { id = "done", label = "DONE", color = "win", textColor = "ink", small = true }
  return list
end

--- Before anything changes, so UNDO can bring it back.
local function remember(player)
  local undo = player.undo
  undo[#undo + 1] = wheel.copyWager(player.spots)
  while #undo > UNDO_DEPTH do table.remove(undo, 1) end
end

--- The chip in hand on a spot, or what is left of the seat's money if that is less.
local function place(player, id)
  if not wheel.spot(id) then return false end
  local amount = math.min(player.chip, player.budget - wheel.stakeOf(player.spots))
  if amount <= 0 then return false end
  remember(player)
  player.spots[id] = (player.spots[id] or 0) + amount
  player.lit = id
  return true
end

local function spin(state, rng)
  local number = rng:below(wheel.POCKETS)
  state.number, state.over = number, true
  for _, player in ipairs(state.players) do
    player.net = wheel.netOn(player.spots, number)
    player.undo, player.again = {}, nil
  end
  return { { type = "spin" }, { type = "landed" }, { type = "payout" } }
end

--- A seat's press. Each branch either changes the seat and says so, or does nothing at all.
local function press(player, id, value)
  local stake = wheel.stakeOf(player.spots)
  if id == "spot" then
    return place(player, value)
  elseif id == "chip" then
    if not isChip(player, value) then return false end
    player.chip = value
  elseif id == "mode" then
    if not isMode(value) then return false end
    player.mode = value
  elseif id == "undo" then
    if #player.undo == 0 then return false end
    player.spots = table.remove(player.undo)
    player.lit = nil
  elseif id == "clear" then
    if stake == 0 then return false end
    remember(player)
    player.spots, player.lit = {}, nil
  elseif id == "again" then
    if not player.again then return false end
    remember(player)
    player.spots, player.lit = wheel.copyWager(player.again), nil
  elseif id == "double" then
    if stake == 0 or stake * 2 > player.budget then return false end
    remember(player)
    for spot, amount in pairs(player.spots) do player.spots[spot] = amount * 2 end
    player.lit = nil
  elseif id == "done" then
    player.done = true
  else
    return false
  end
  return true
end

function M.act(state, seat, id, value, rng)
  if state.over then return {} end
  if seat == nil then
    if id ~= "spin" or #M.waitingOn(state) > 0 or not rng then return {} end
    return spin(state, rng)
  end
  local player = find(state, seat)
  if not player or player.done or not press(player, id, value) then return {} end
  return { { type = id == "spot" and "bet" or "seat", seat = seat } }
end

--- The clock closes betting: a seat's chips stay where they are. With no seat, the wheel spins.
function M.auto(_, seat)
  if not seat then return "spin" end
  return "done"
end

--- A seat with chips down that lets the clock close betting has played, and is not away.
function M.present(state, seat)
  local player = find(state, seat)
  return player ~= nil and next(player.spots) ~= nil
end

local function publicSeat(state, player)
  return {
    seat = player.seat, name = player.name, placed = wheel.stakeOf(player.spots), done = player.done,
    net = state.over and player.net or nil,
  }
end

--- Bets lie on an open table, so the wall may show them. A seat is only told about itself: it never needs the others'.
function M.viewFor(state, seat)
  local view = { over = state.over, number = state.number, recent = {} }
  for i, n in ipairs(state.recent) do view.recent[i] = n end
  local own = seat and find(state, seat)
  if own then
    local stake = wheel.stakeOf(own.spots)
    view.me = {
      budget = own.budget, placed = stake, left = own.budget - stake, spots = wheel.copyWager(own.spots), mode = own.mode,
      chip = own.chip, lit = own.lit, done = own.done, net = state.over and own.net or nil,
    }
    return view
  end
  view.seats, view.board = {}, {}
  for index, player in ipairs(state.players) do
    view.seats[index] = publicSeat(state, player)
    for id, amount in pairs(player.spots) do view.board[id] = (view.board[id] or 0) + amount end
  end
  return view
end

function M.done(state)
  return state.over == true
end

function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net end
  return nets
end

function M.risk(state, seat)
  local player = find(state, seat)
  return player and wheel.stakeOf(player.spots) or 0
end

--- However a seat spreads its bet, nothing beats all of it on one number.
function M.maxWin(entry)
  return entry.bet * 35
end

local function signed(amount)
  return (amount > 0 and "+" or "") .. amount
end

local function seatResult(state, player)
  local number = state.number
  local title = wheel.numberName(number)
  if next(player.spots) == nil then return { kind = "push", title = title, detail = "No bet on this spin" } end
  local wins = wheel.winners(player.spots, number)
  if player.net > 0 then
    local names = {}
    for i, id in ipairs(wins) do
      if i <= 3 then names[i] = wheel.describe(id) end
    end
    if #wins > 3 then names[#names + 1] = "and " .. (#wins - 3) .. " more" end
    return { kind = "win", title = title, detail = signed(player.net) .. "  " .. table.concat(names, ", ") }
  end
  if player.net == 0 then return { kind = "push", title = title, detail = "Your winners cover your losers" } end
  if #wins > 0 then
    return { kind = "lose", title = title, detail = signed(player.net) .. "  " .. #wins .. " winning spot" .. (#wins > 1 and "s" or "") .. ", not enough to cover the rest" }
  end
  return { kind = "lose", title = title, detail = signed(player.net) .. "  No bet on " .. number }
end

function M.result(state, seat)
  if not state.over then return { kind = "push", title = "NO SPIN", detail = "" } end
  local own = seat and find(state, seat)
  if own then return seatResult(state, own) end
  local parts = {}
  for _, player in ipairs(state.players) do
    if next(player.spots) ~= nil then parts[#parts + 1] = player.name:sub(1, 10) .. " " .. signed(player.net) end
  end
  return { kind = "push", title = wheel.numberName(state.number), detail = #parts > 0 and table.concat(parts, "  ") or "No bets on this spin" }
end

--- What lasts: the last numbers, and each player's wager for REPEAT. Only those at this spin keep theirs, so this cannot grow.
function M.finish(state, keep)
  local recent = { state.number }
  for _, n in ipairs(keep.recent or {}) do
    if #recent < wheel.RECENT_KEPT then recent[#recent + 1] = n end
  end
  keep.recent = recent
  local before, last = keep.last or {}, {}
  for _, player in ipairs(state.players) do
    local wager = next(player.spots) ~= nil and player.spots or before[player.name]
    if wager then last[player.name] = wheel.copyWager(wager) end
  end
  keep.last = last
end

return M
