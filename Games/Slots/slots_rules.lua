-- slots_rules.lua
-- Three independent reels of 52 stops. Pure: no screen, no sound, no money.
-- A multiple is the total return for the bet, so x1 is a push. A pair counts in any position.
-- The paytable returns exactly 133610/140608 (95.02%) before the jackpot; slots_test.lua enumerates it.
--
-- Jackpot: three 7s also pay the shared pot, but never more than POT_TIMES the bet. A small bet takes a small
-- share of a big pot and the pot still resets, so maxWin can be promised from the bet alone.
-- Gamble: after a win the player may stake the whole return on a fair flip, up to GAMBLES times, while the doubled
-- return stays within MAX_RETURN times the bet. The flip is a rules step, journaled, and settled after a collect or
-- a loss, so a loss cannot be dodged. A fair flip leaves the return unchanged, and three 7s are never at stake.

local M = {
  STOPS = 52,
  MAX_RETURN = 100,     -- the most the paytable and the gamble together can return, in bets
  POT_TIMES = 100,      -- the most the pot can add, in bets
  GAMBLES = 3,
  JACKPOT = { seed = 1000, share = 0.01 },
}

-- Rarest first. triple and pair are total-return multiples; 0 would mean nothing back.
M.SYMBOLS = {
  { id = "seven", name = "7", plural = "SEVENS", weight = 2, triple = 100, pair = 10 },
  { id = "diamond", name = "Diamond", plural = "DIAMONDS", weight = 3, triple = 45, pair = 6 },
  { id = "bell", name = "Bell", plural = "BELLS", weight = 5, triple = 16, pair = 1 },
  { id = "bar", name = "Bar", plural = "BARS", weight = 5, triple = 8, pair = 1 },
  { id = "cherry", name = "Cherry", plural = "CHERRIES", weight = 9, triple = 5, pair = 2 },
  { id = "lemon", name = "Lemon", plural = "LEMONS", weight = 13, triple = 3, pair = 1 },
  { id = "melon", name = "Melon", plural = "MELONS", weight = 15, triple = 2, pair = 2 },
}

M.SEVEN = 1
M.NEAR_MISS = { [1] = true, [2] = true } -- pairs a third symbol away from the top of the table

--- One reel as a strip of symbol numbers, each appearing exactly its weight, spread evenly round the reel.
-- Stops are what the rng picks and what the view scrolls, so what flashes past is the real reel.
local function buildStrip()
  local strip, credit = {}, {}
  for i = 1, #M.SYMBOLS do credit[i] = 0 end
  for stop = 1, M.STOPS do
    local best = 1
    for i, symbol in ipairs(M.SYMBOLS) do
      credit[i] = credit[i] + symbol.weight
      if credit[i] > credit[best] then best = i end
    end
    credit[best] = credit[best] - M.STOPS
    strip[stop] = best
  end
  return strip
end
M.STRIP = buildStrip()

--- What three symbols pay: multiple, "triple" | "pair" | "none", and the symbol that paid.
function M.evaluate(a, b, c)
  if a == b and b == c then return M.SYMBOLS[a].triple, "triple", a end
  local paired = (a == b or a == c) and a or (b == c and b or nil)
  if paired then return M.SYMBOLS[paired].pair, "pair", paired end
  return 0, "none", nil
end

--- The exact return before the jackpot, by walking all 52^3 outcomes through their weights.
function M.exactReturn()
  local paid, total = 0, 0
  for a, first in ipairs(M.SYMBOLS) do
    for b, second in ipairs(M.SYMBOLS) do
      for c, third in ipairs(M.SYMBOLS) do
        local ways = first.weight * second.weight * third.weight
        total = total + ways
        paid = paid + ways * M.evaluate(a, b, c)
      end
    end
  end
  return paid / total, paid, total
end

--- The biggest net win. The bet alone decides it, whatever the pot stands at.
function M.maxWin(bet)
  return bet * (M.MAX_RETURN - 1 + M.POT_TIMES)
end

--- What the pot pays a bet.
function M.potPayment(bet, pot)
  return math.floor(math.min(pot, bet * M.POT_TIMES))
end

--- The three stops. One rng draw per reel, on the strip's real weights.
function M.spin(rng)
  return { rng:below(M.STOPS) + 1, rng:below(M.STOPS) + 1, rng:below(M.STOPS) + 1 }
end

--- The gamble's fair flip.
function M.flip(rng)
  return rng:below(2) == 1
end

local function canGamble(state)
  return state.gambles < M.GAMBLES and state.payout * 2 <= state.bet * M.MAX_RETURN
end

function M.new(bet, rng, _, env)
  local stops = M.spin(rng)
  local a, b, c = M.STRIP[stops[1]], M.STRIP[stops[2]], M.STRIP[stops[3]]
  local times, kind, symbol = M.evaluate(a, b, c)
  local state = { bet = bet, stops = stops, symbols = { a, b, c }, times = times, kind = kind, symbol = symbol,
    payout = bet * times, gambles = 0 }

  local events = {}
  for i = 1, 3 do events[i] = { type = "reel", reel = i } end
  if kind == "triple" and symbol == M.SEVEN then
    state.jackpotHit = M.potPayment(bet, env and env.pot or M.JACKPOT.seed)
  end
  -- A push or a miss has nothing to decide, and three 7s are never gambled
  state.over = times <= 1 or not canGamble(state)
  if times > 1 then
    events[#events + 1] = { type = "win", amount = state.payout + (state.jackpotHit or 0), times = times,
      jackpot = state.jackpotHit, hold = state.over }
  end
  return state, events
end

function M.actions(state)
  local list = { { id = "collect", label = "COLLECT", color = "win", textColor = "ink",
    sub = "keep " .. state.payout } }
  if canGamble(state) then
    list[#list + 1] = { id = "gamble", label = "GAMBLE", color = "red",
      sub = "50% for " .. state.payout * 2 }
  end
  return list
end

function M.act(state, id, rng)
  if id == "gamble" and canGamble(state) then
    local won = M.flip(rng)
    state.gambles = state.gambles + 1
    if won then
      state.payout = state.payout * 2
      state.over = not canGamble(state)
    else
      state.staked = state.payout
      state.payout = 0
      state.lost, state.over = true, true
    end
    return { { type = "flip", won = won, amount = state.payout } }
  end
  state.over = true
  return { { type = "collect", amount = state.payout } }
end

--- Nobody at the table: bank it.
function M.auto()
  return "collect"
end

function M.done(state)
  return state.over == true
end

function M.risk(state)
  return state.bet
end

function M.net(state)
  return state.payout - state.bet + (state.jackpotHit or 0)
end

--- Whether a gamble decision is open or could be: for the view's words.
function M.gamblesLeft(state)
  return canGamble(state) and M.GAMBLES - state.gambles or 0
end

function M.result(state)
  local symbol = state.symbol and M.SYMBOLS[state.symbol]
  if state.lost then
    return { kind = "lose", title = "GAMBLE LOST", detail = ("The flip took the %d riding on it"):format(state.staked) }
  end
  if state.kind == "none" then return { kind = "lose", title = "NO WIN", detail = "Any pair pays. Spin again?" } end
  local title = state.kind == "triple" and ("THREE " .. symbol.plural) or ("PAIR OF " .. symbol.plural)
  if state.jackpotHit then
    return { kind = "win", title = "JACKPOT", detail = ("Three 7s pay x%d plus %d from the pot"):format(state.times, state.jackpotHit) }
  end
  if state.times == 1 then return { kind = "push", title = title, detail = "Your bet comes back" } end
  local detail = ("x%d"):format(state.times)
  if state.gambles > 0 then
    detail = detail .. (", doubled %d time%s"):format(state.gambles, state.gambles == 1 and "" or "s")
  elseif state.kind == "pair" and M.NEAR_MISS[state.symbol] then
    detail = detail .. ("  One %s short of x%d!"):format(symbol.name, symbol.triple)
  end
  return { kind = "win", title = title, detail = detail }
end

function M.finish()
end

return M
