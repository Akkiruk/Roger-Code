-- horseracing_rules.lua
-- Six horses, a card of bets, one finishing order. Pure: no screen, no sound, no money.
--
-- A race card is drawn before betting: each horse gets a strength, a whole number. The finishing order is then
-- drawn once, up front: first place from the strengths, second from those left, third from those left, and so on
-- (Harville's model). Every price comes from the exact chance that order gives the bet, so each bet on each horse
-- returns RETURN, less the rounding of its multiple down to the cent. horseracing_test.lua proves that over all 720
-- orders of many races. Multiples are kept as whole hundredths and payouts round down to whole tokens.
--
-- The race the wall shows is only a way of telling that order: position() draws every horse's run from the order and
-- a few pace numbers, and its last frame is the drawn order.

local M = {
  HORSES = 6,
  RETURN = 0.96,
  MIN_BET = 5,
  DISTANCE = 1000,
  KINDS = { "win", "place", "show" },
  KIND_NAMES = { win = "Win", place = "Place", show = "Show", exacta = "Exacta" },
  KIND_HELP = { win = "first", place = "first or second", show = "in the top three" },
}

local NAMES = {
  "Redstone Run", "Creeper Bait", "Diamond Dust", "Enderman", "Night Vision", "Lucky Clover",
  "Iron Golem", "Vault Hunter", "Sugar Cane", "Blaze Rod", "Slime Time", "Copper Top",
  "Ghast Mode", "Hay Bale", "Silk Touch", "Moon Pearl", "Pumpkin Pie", "Thunderclap",
}

--- A new race card: strengths and names. Strengths run from 10 to 60, skewed low, so most races have a favourite.
function M.newRace(rng)
  local strengths, names, pool = {}, {}, {}
  for i, name in ipairs(NAMES) do pool[i] = name end
  for i = 1, M.HORSES do
    local roll = rng:below(11)
    strengths[i] = 10 + math.floor(roll * roll / 2)
    names[i] = table.remove(pool, rng:below(#pool) + 1)
  end
  return { strengths = strengths, names = names }
end

--- Exact chances from the strengths: win[i], place[i], show[i], exacta[i][j].
function M.chances(strengths)
  local total = 0
  for i = 1, M.HORSES do total = total + strengths[i] end
  local win, place, show, exacta = {}, {}, {}, {}
  for i = 1, M.HORSES do win[i], place[i], show[i], exacta[i] = 0, 0, 0, {} end
  for a = 1, M.HORSES do
    local pa = strengths[a] / total
    win[a] = pa
    for b = 1, M.HORSES do
      if b ~= a then
        local pab = pa * strengths[b] / (total - strengths[a])
        exacta[a][b] = pab
        place[a] = place[a] + pab
        place[b] = place[b] + pab
        for d = 1, M.HORSES do
          if d ~= a and d ~= b then
            local pabd = pab * strengths[d] / (total - strengths[a] - strengths[b])
            show[a] = show[a] + pabd
            show[b] = show[b] + pabd
            show[d] = show[d] + pabd
          end
        end
      end
    end
  end
  return { win = win, place = place, show = show, exacta = exacta }
end

local function price(chance)
  return math.floor(M.RETURN / chance * 100)
end

--- Every price for a race, as whole hundredths of a multiple of the stake, stake included.
function M.prices(strengths)
  local chance = M.chances(strengths)
  local prices = { win = {}, place = {}, show = {}, exacta = {} }
  for i = 1, M.HORSES do
    prices.win[i] = price(chance.win[i])
    prices.place[i] = price(chance.place[i])
    prices.show[i] = price(chance.show[i])
    prices.exacta[i] = {}
    for j = 1, M.HORSES do
      if i ~= j then prices.exacta[i][j] = price(chance.exacta[i][j]) end
    end
  end
  return prices
end

--- Whether a bet wins given the first three home. A bet is { kind, a, b, amount }; b is exacta's second horse.
function M.wins(bet, first, second, third)
  if bet.kind == "win" then return bet.a == first end
  if bet.kind == "place" then return bet.a == first or bet.a == second end
  if bet.kind == "show" then return bet.a == first or bet.a == second or bet.a == third end
  return bet.a == first and bet.b == second
end

--- What a bet pays back, stake included, rounded down.
function M.payout(bet, prices, first, second, third)
  if not M.wins(bet, first, second, third) then return 0 end
  local hundredths = bet.kind == "exacta" and prices.exacta[bet.a][bet.b] or prices[bet.kind][bet.a]
  return math.floor(bet.amount * hundredths / 100)
end

function M.stake(wager)
  local total = 0
  for _, bet in ipairs(wager.bets) do total = total + bet.amount end
  return total
end

--- The biggest net win of a card of bets: every first three walked, since one order can pay several bets at once.
function M.maxWin(wager)
  local prices = M.prices(wager.race.strengths)
  local best = 0
  for a = 1, M.HORSES do
    for b = 1, M.HORSES do
      for d = 1, M.HORSES do
        if a ~= b and a ~= d and b ~= d then
          local back = 0
          for _, bet in ipairs(wager.bets) do back = back + M.payout(bet, prices, a, b, d) end
          if back > best then best = back end
        end
      end
    end
  end
  return math.max(0, best - M.stake(wager))
end

--- The finishing order, drawn once.
function M.drawOrder(strengths, rng)
  local left, order = {}, {}
  local total = 0
  for i = 1, M.HORSES do
    left[i] = i
    total = total + strengths[i]
  end
  while #left > 0 do
    local roll = rng:below(total)
    for slot, horse in ipairs(left) do
      roll = roll - strengths[horse]
      if roll < 0 then
        order[#order + 1] = horse
        total = total - strengths[horse]
        table.remove(left, slot)
        break
      end
    end
  end
  return order
end

--- The numbers that shape the run: how each horse spends its race, and how far apart they finish.
local function drawPace(rng)
  local pace = {}
  for i = 1, M.HORSES do
    pace[i] = {
      style = rng:below(141) - 70,    -- ahead early when positive, a closer when negative
      swell = rng:below(41) - 20,     -- a surge and a fade through the middle
      phase = rng:below(628) / 100,
    }
  end
  local margins = { 0 }
  margins[2] = 3 + rng:below(12)
  for rank = 3, M.HORSES do margins[rank] = margins[rank - 1] + 4 + rng:below(22) end
  return pace, margins
end

--- How far a horse has run at time t of 1. It reaches DISTANCE less its margin at t = 1, so the last frame is the order.
function M.position(state, horse, t)
  local rank = state.rankOf[horse]
  local pace = state.pace[horse]
  local base = (M.DISTANCE - state.margins[rank]) * t
  local shape = math.sin(math.pi * t)
  return base + pace.style * shape + pace.swell * shape * shape * math.sin(3 * math.pi * t + pace.phase)
end

function M.new(wager, rng, _, _)
  local race = wager.race
  local state = { race = { strengths = {}, names = {} }, bets = {}, rankOf = {} }
  for i = 1, M.HORSES do
    state.race.strengths[i] = race.strengths[i]
    state.race.names[i] = race.names[i]
  end
  local prices = M.prices(state.race.strengths)
  state.order = M.drawOrder(state.race.strengths, rng)
  state.pace, state.margins = drawPace(rng)
  for rank, horse in ipairs(state.order) do state.rankOf[horse] = rank end

  local first, second, third = state.order[1], state.order[2], state.order[3]
  state.stake, state.back = 0, 0
  for i, bet in ipairs(wager.bets) do
    local paid = M.payout(bet, prices, first, second, third)
    state.bets[i] = { kind = bet.kind, a = bet.a, b = bet.b, amount = bet.amount, paid = paid }
    state.stake = state.stake + bet.amount
    state.back = state.back + paid
  end
  state.photo = state.margins[2] <= 6
  state.over = true
  return state, { { type = "race" }, { type = "line" } }
end

function M.actions()
  return {}
end

function M.act()
  return {}
end

function M.auto()
  return "none"
end

function M.done(state)
  return state.over == true
end

function M.risk(state)
  return state.stake
end

function M.net(state)
  return state.back - state.stake
end

--- A horse's number and name, as the commentary and the banner say it.
function M.label(state, horse)
  return "#" .. horse .. " " .. state.race.names[horse]
end

function M.result(state)
  local order = state.order
  local net = M.net(state)
  local detail = ("2nd %s, 3rd %s"):format(M.label(state, order[2]), M.label(state, order[3]))
  return {
    kind = net > 0 and "win" or net == 0 and "push" or "lose",
    title = M.label(state, order[1]) .. " WINS",
    detail = detail,
  }
end

--- Remember the winners for the race card.
function M.finish(state, keep)
  keep.recent = keep.recent or {}
  table.insert(keep.recent, 1, state.order[1])
  while #keep.recent > 8 do table.remove(keep.recent) end
end

return M
