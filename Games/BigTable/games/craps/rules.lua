-- games/craps/rules.lua
-- Shared Craps. One shooter, one pair of dice, everyone at the table betting on them. No screen, no money, no os.*: the engine calls
-- this and reads nets at the end. See games/README.md.
--
-- A round has clear ends, because the engine moves money only at the end of a round and a bet that carries across rolls is exposure:
--   comeout  Pass, Don't Pass and Field were placed on the seats before the deal. The shooter rolls. A natural or craps ends the round
--   point    A point is on. Between rolls every seat may add Come, Don't Come, Field and odds, and the shooter rolls when ready
--   runout   The point was made with Come bets still on their numbers. No new bets. The shooter rolls until each of them has resolved
-- Nothing carries past the end of a round, so each bet resolves once and each seat's net is booked once, by the engine, at the end.
-- A seven out ends everything at once, and the dice pass. If the shooter made the point, they keep the dice for the next round: a run
-- out comes after that, so its rolls are come-outs to a real table. Come odds are off on a come-out, so they go back whatever the number
-- does, and a seven there is a natural, not a seven out. It takes the Come bets and leaves the shooter the dice.
--
-- Every roll is two moves. The shooter's press closes betting and leaves the game waiting on nobody, which clears every seat's clock.
-- The computer's move then throws the dice, and a new window opens with a fresh clock. A shooter who does not press has the dice thrown
-- for them and loses them to the next seat. With nobody left to shoot the computer just keeps rolling until the bets are decided.
--
-- Stakes are never taken up front. A press has a cost so the engine checks the balance covers it, and that is all. The most a seat
-- can win is fixed before the deal, because the host has to cover it then: rules.maxWin is MAX_TIMES their opening bet, and a press is
-- only offered while what the seat has won plus the best their live bets could still do stays inside that.
--
-- Odds are whole numbers. An odds bet is a multiple of what its price divides by, rounded down, so a payout never needs rounding and
-- odds stay at exactly true value.

local rules = {}

rules.MAX_TIMES = 10          -- the most a seat can win in a round, as a multiple of its opening bet
rules.ODDS_TIMES = 3          -- odds behind a bet, as a multiple of that bet

-- Pay as { to, for }: true odds of making the number, and of the seven coming first
rules.TAKE_ODDS = { [4] = { 2, 1 }, [5] = { 3, 2 }, [6] = { 6, 5 }, [8] = { 6, 5 }, [9] = { 3, 2 }, [10] = { 2, 1 } }
rules.LAY_ODDS = { [4] = { 1, 2 }, [5] = { 2, 3 }, [6] = { 5, 6 }, [8] = { 5, 6 }, [9] = { 2, 3 }, [10] = { 1, 2 } }

-- What a total does to a bet on its first roll. Anything missing sets a point. 12 is barred on the Don't side: a push, not a win
rules.PASS_FIRST = { [2] = "lose", [3] = "lose", [7] = "win", [11] = "win", [12] = "lose" }
rules.DONT_FIRST = { [2] = "win", [3] = "win", [7] = "lose", [11] = "lose", [12] = "push" }

-- Field pays this many to one. Anything missing loses
rules.FIELD = { [2] = 2, [3] = 1, [4] = 1, [9] = 1, [10] = 1, [11] = 1, [12] = 3 }

rules.NUMBERS = { 4, 5, 6, 8, 9, 10 }

local NUMBERS = rules.NUMBERS
local LOG_MAX = 6
local HISTORY_MAX = 10

local CALLS = {
  [2] = "SNAKE EYES", [3] = "ACE DEUCE", [4] = "FOUR", [5] = "FIVE", [6] = "SIX", [7] = "SEVEN", [8] = "EIGHT", [9] = "NINE",
  [10] = "TEN", [11] = "YO ELEVEN", [12] = "BOXCARS",
}

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

local function whole(value)
  return type(value) == "number" and value == math.floor(value) and value > 0
end

--- The most a live bet can still win, odds included, if everything goes its way.
local function best(record, price)
  if record.odds <= 0 then return record.bet end
  return record.bet + record.odds * price[1] / price[2]
end

--- What the seat has made so far plus the best its live bets could still do. A press must keep this inside player.cap.
local function ceiling(state, player)
  local total = player.net + player.field * 3 + player.comeBox + player.dontBox
  if state.point then
    total = total + best(player.pass, rules.TAKE_ODDS[state.point]) + best(player.dont, rules.LAY_ODDS[state.point])
  else
    total = total + player.pass.bet + player.dont.bet
  end
  for _, number in ipairs(NUMBERS) do
    if player.come[number] then total = total + best(player.come[number], rules.TAKE_ODDS[number]) end
    if player.lay[number] then total = total + best(player.lay[number], rules.LAY_ODDS[number]) end
  end
  return total
end
rules.ceiling = ceiling

--- Whether anything is still riding on a Come number, in a box, or on a line.
local function live(state)
  for _, player in ipairs(state.players) do
    if player.comeBox > 0 or player.dontBox > 0 or player.pass.bet > 0 or player.dont.bet > 0 then return true end
    if next(player.come) or next(player.lay) then return true end
  end
  return false
end

local function note(player, label, amount)
  player.net = player.net + amount
  player.log[#player.log + 1] = { label = label, amount = amount }
  if #player.log > LOG_MAX then table.remove(player.log, 1) end
end

--- One bet and its odds, won.
local function winBet(player, label, record, price)
  local odds = record.odds * price[1] / price[2]
  note(player, label, record.bet + odds)
  record.bet, record.odds = 0, 0
end

--- One bet and its odds, lost.
local function loseBet(player, label, record)
  note(player, label, -(record.bet + record.odds))
  record.bet, record.odds = 0, 0
end

--- A Field bet lasts one roll.
local function resolveField(player, total)
  if player.field <= 0 then return end
  local pays = rules.FIELD[total]
  note(player, "FIELD", pays and player.field * pays or -player.field)
  player.field = 0
end

--- Bets already on a number. The bet in a box moves after this, so an old Come on six is paid and a new one takes its place.
-- oddsOff is a run out: what backs a Come bet goes back, with nothing won or lost on it. Don't odds always work.
local function resolveNumbers(player, total, oddsOff)
  for _, number in ipairs(NUMBERS) do
    local come, lay = player.come[number], player.lay[number]
    if come then
      if oddsOff and (total == number or total == 7) then come.odds = 0 end
      if total == number then
        winBet(player, "COME " .. number, come, rules.TAKE_ODDS[number])
        player.come[number] = nil
      elseif total == 7 then
        loseBet(player, "COME " .. number, come)
        player.come[number] = nil
      end
    end
    if lay then
      if total == 7 then
        winBet(player, "DON'T " .. number, lay, rules.LAY_ODDS[number])
        player.lay[number] = nil
      elseif total == number then
        loseBet(player, "DON'T " .. number, lay)
        player.lay[number] = nil
      end
    end
  end
end

--- A bet in a box has its own first roll: it wins, loses, or moves to the number.
local function resolveBoxes(player, total)
  if player.comeBox > 0 then
    local amount, verdict = player.comeBox, rules.PASS_FIRST[total]
    player.comeBox = 0
    if verdict == "win" then note(player, "COME", amount)
    elseif verdict == "lose" then note(player, "COME", -amount)
    else player.come[total] = { bet = amount, odds = 0 } end
  end
  if player.dontBox > 0 then
    local amount, verdict = player.dontBox, rules.DONT_FIRST[total]
    player.dontBox = 0
    if verdict == "win" then note(player, "DON'T COME", amount)
    elseif verdict == "lose" then note(player, "DON'T COME", -amount)
    elseif verdict == "push" then note(player, "DON'T COME", 0)
    else player.lay[total] = { bet = amount, odds = 0 } end
  end
end

local function settleFirst(player, total)
  local record = player.pass
  local verdict = rules.PASS_FIRST[total]
  if record.bet > 0 and verdict then
    note(player, "PASS", verdict == "win" and record.bet or -record.bet)
    record.bet = 0
  end
  record = player.dont
  verdict = rules.DONT_FIRST[total]
  if record.bet > 0 and verdict then
    local amount = verdict == "win" and record.bet or (verdict == "lose" and -record.bet or 0)
    note(player, "DON'T PASS", amount)
    record.bet = 0
  end
end

--- The line once a point is on: the point or a seven decides it.
local function settlePoint(player, point, made)
  local take, lay = rules.TAKE_ODDS[point], rules.LAY_ODDS[point]
  if player.pass.bet > 0 then
    if made then winBet(player, "PASS", player.pass, take) else loseBet(player, "PASS", player.pass) end
  end
  if player.dont.bet > 0 then
    if made then loseBet(player, "DON'T PASS", player.dont) else winBet(player, "DON'T PASS", player.dont, lay) end
  end
end

--- What the dice do. Returns the call for the table.
local function resolve(state, total)
  local stage, point = state.stage, state.point
  local call = CALLS[total]
  for _, player in ipairs(state.players) do
    resolveField(player, total)
    resolveNumbers(player, total, stage == "runout")
    resolveBoxes(player, total)
  end

  if stage == "comeout" then
    local anyLine = false
    for _, player in ipairs(state.players) do
      anyLine = anyLine or player.pass.bet > 0 or player.dont.bet > 0
      settleFirst(player, total)
    end
    if rules.PASS_FIRST[total] == nil and anyLine then
      state.stage, state.point = "point", total
      call = "POINT IS " .. total
    else
      -- A natural, craps, or nobody on a line, which leaves nothing to carry a point for
      state.point = nil
      state.over = true
    end
  elseif stage == "point" then
    if total == point or total == 7 then
      for _, player in ipairs(state.players) do settlePoint(player, point, total == point) end
      state.sevenOut = total == 7
      call = total == 7 and "SEVEN OUT" or "POINT MADE"
      state.point = nil
      if live(state) then state.stage = "runout" else state.over = true end
    end
  elseif not live(state) then
    state.over = true
  end
  if state.over then state.stage = "over" end
  state.call = call
  return call
end

--- The next seat after this one that has not walked away from the dice, or nil.
local function nextShooter(state, seat)
  local count = #state.players
  local start = 1
  for index, player in ipairs(state.players) do
    if player.seat == seat then start = index end
  end
  for step = 1, count - 1 do
    local player = state.players[(start - 1 + step) % count + 1]
    if not player.away then return player.seat end
  end
  return nil
end

--- Who shoots a new round: whoever kept the dice, or the next seat round from whoever lost them.
local function firstShooter(entries, button, keep)
  keep = keep or {}
  if keep.shooter then
    for _, entry in ipairs(entries) do
      if entry.seat == keep.shooter and not keep.passDice then return entry.seat end
    end
    for _, entry in ipairs(entries) do
      if entry.seat > keep.shooter then return entry.seat end
    end
    return entries[1].seat
  end
  local entry = entries[button or 1] or entries[1]
  return entry.seat
end

--- The largest spot a seat opened with is what its Come, Don't Come and Field buttons stake.
local function opening(entry)
  local pass, dont, field = 0, 0, 0
  local bets = type(entry.bets) == "table" and entry.bets or nil
  if bets then
    pass = whole(bets.pass) and bets.pass or 0
    dont = whole(bets.dont) and bets.dont or 0
    field = whole(bets.field) and bets.field or 0
  end
  if pass + dont + field == 0 then pass = entry.bet end
  return pass, dont, field
end

function rules.new(entries, button, _, keep)
  local players = {}
  for index, entry in ipairs(entries) do
    local pass, dont, field = opening(entry)
    players[index] = {
      seat = entry.seat, name = entry.name,
      cap = rules.maxWin(entry),
      unit = math.max(pass, dont, field),
      staked = pass + dont + field,
      net = 0,
      pass = { bet = pass, odds = 0 }, dont = { bet = dont, odds = 0 },
      field = field, comeBox = 0, dontBox = 0,
      come = {}, lay = {},          -- by number: { bet, odds }
      log = {}, passed = false, away = false,
    }
  end
  local shooter = firstShooter(entries, button, keep)
  local state = {
    players = players, shooter = shooter, shot = shooter, stage = "comeout", point = nil, rolling = false, over = false,
    sevenOut = false, dice = nil, total = nil, call = nil, rolls = 0, history = {},
  }
  return state, { { type = "comeout", seat = shooter } }
end

--- A list of what this seat can do with its odds now: { key, label, record, number, price }. The line first, then its Come numbers.
local function oddsBets(state, player)
  local list = {}
  if state.point then
    list[#list + 1] = { key = "pass", label = "ODDS PASS", record = player.pass, price = rules.TAKE_ODDS[state.point] }
    list[#list + 1] = { key = "dont", label = "ODDS DP", record = player.dont, price = rules.LAY_ODDS[state.point] }
  end
  for _, number in ipairs(NUMBERS) do
    if player.come[number] then
      list[#list + 1] = { key = "c" .. number, label = "ODDS C" .. number, record = player.come[number], price = rules.TAKE_ODDS[number] }
    end
    if player.lay[number] then
      list[#list + 1] = { key = "d" .. number, label = "ODDS D" .. number, record = player.lay[number], price = rules.LAY_ODDS[number] }
    end
  end
  return list
end

--- How much the next step of odds adds: 1x, then 2x, then 3x, each down to a multiple the price pays whole. nil at the limit.
local function nextOdds(record, price)
  if record.bet <= 0 then return nil end
  local step = price[2]
  for times = 1, rules.ODDS_TIMES do
    local target = math.floor(record.bet * times / step) * step
    if target > record.odds then return target - record.odds end
  end
  return nil
end

--- The bets a seat may press now, in the order of the buttons. Each carries what it costs and what it could win.
local function offers(state, player)
  local list = {}
  if state.stage ~= "point" then return list end
  local room = player.cap - ceiling(state, player)
  local unit = player.unit
  if player.comeBox == 0 and unit <= room then
    list[#list + 1] = { id = "come", label = "COME", sub = tostring(unit), color = "accent", textColor = "ink", cost = unit }
  end
  if player.dontBox == 0 and unit <= room then
    list[#list + 1] = { id = "dontcome", label = "DON'T COME", sub = tostring(unit), color = "blue", cost = unit }
  end
  if player.field == 0 and unit * 3 <= room then
    list[#list + 1] = { id = "field", label = "FIELD", sub = tostring(unit), color = "gold", textColor = "ink", cost = unit }
  end
  for _, bet in ipairs(oddsBets(state, player)) do
    local add = nextOdds(bet.record, bet.price)
    if add and add * bet.price[1] / bet.price[2] <= room then
      list[#list + 1] = { id = "odds", value = bet.key, label = bet.label, sub = "+" .. add, color = "panel2", cost = add }
    end
  end
  return list
end

function rules.actions(state, seat)
  local player = find(state, seat)
  if not player or state.over or state.rolling or not state.shooter then return {} end
  local list = {}
  local bets = offers(state, player)
  if seat == state.shooter then
    list[1] = { id = "roll", label = "ROLL", color = "win", textColor = "ink" }
  elseif player.passed or #bets == 0 then
    return {}
  else
    list[1] = { id = "pass", label = "NO BET", color = "panel2" }
  end
  for _, action in ipairs(bets) do
    if #list < 10 then list[#list + 1] = action end
  end
  return list
end

function rules.waitingOn(state)
  local list = {}
  if state.over or state.rolling or not state.shooter then return list end
  for _, player in ipairs(state.players) do
    if #rules.actions(state, player.seat) > 0 then list[#list + 1] = player.seat end
  end
  return list
end

--- The throw itself, the computer's move.
local function throw(state, rng)
  local d1, d2 = rng:below(6) + 1, rng:below(6) + 1
  local total = d1 + d2
  local before = state.point
  state.dice, state.total = { d1, d2 }, total
  state.rolls = state.rolls + 1
  state.history[#state.history + 1] = total
  if #state.history > HISTORY_MAX then table.remove(state.history, 1) end
  state.rolling = false
  for _, player in ipairs(state.players) do player.passed = false end
  local call = resolve(state, total)
  return { { type = "roll", d1 = d1, d2 = d2, total = total, call = call, point = before or false, n = state.rolls } }
end

--- The press that closes betting.
local function closeBets(state, seat)
  state.rolling = true
  state.shot = seat
  return { type = "throw", seat = seat }
end

--- Find a press among those on offer, with both its id and its value.
local function offered(state, seat, id, value)
  for _, action in ipairs(rules.actions(state, seat)) do
    if action.id == id and action.value == value then return action end
  end
  return nil
end

local function placeOdds(state, player, key, add)
  for _, bet in ipairs(oddsBets(state, player)) do
    if bet.key == key then
      bet.record.odds = bet.record.odds + add
      return
    end
  end
end

function rules.act(state, seat, id, value, rng)
  if state.over then return {} end
  if seat == nil then
    if id ~= "dice" or #rules.waitingOn(state) > 0 or not rng then return {} end
    return throw(state, rng)
  end
  local player = find(state, seat)
  if not player then return {} end

  -- The clock ran out on the shooter. The dice are thrown for them, and the next seat takes over. Never a button, so never offered
  if id == "skip" then
    if seat ~= state.shooter or state.rolling then return {} end
    player.away = true
    local events = { closeBets(state, seat) }
    state.shooter = nextShooter(state, seat)
    events[2] = { type = "shooter", seat = state.shooter or false }
    return events
  end

  local action = offered(state, seat, id, value)
  if not action then return {} end
  if id == "roll" then return { closeBets(state, seat) } end
  if id == "pass" then
    player.passed = true
    return { { type = "pass", seat = seat } }
  end

  player.staked = player.staked + action.cost
  if id == "come" then
    player.comeBox = action.cost
  elseif id == "dontcome" then
    player.dontBox = action.cost
  elseif id == "field" then
    player.field = action.cost
  else
    placeOdds(state, player, value, action.cost)
  end
  return { { type = "bet", seat = seat, what = id, amount = action.cost } }
end

function rules.auto(state, seat)
  if not seat then return "dice" end
  if seat == state.shooter then return "skip" end
  return "pass"
end

--- A live bet, as a view shows it.
local function betView(record, number)
  return { n = number, bet = record.bet, odds = record.odds }
end

--- What everyone can see across the felt: the dice, the puck, and the chips in each place.
local function publicView(state)
  local view = {
    stage = state.stage, point = state.point or false, rolling = state.rolling, over = state.over, shooter = state.shooter or false,
    dice = state.dice and { state.dice[1], state.dice[2] } or false, total = state.total or false, call = state.call or false,
    rolls = state.rolls, sevenOut = state.sevenOut, history = {}, seats = {}, numbers = {},
    pass = 0, dont = 0, field = 0, comeBox = 0, dontBox = 0,
  }
  for index, total in ipairs(state.history) do view.history[index] = total end
  for index, number in ipairs(NUMBERS) do view.numbers[index] = { n = number, come = 0, lay = 0 } end
  for index, player in ipairs(state.players) do
    local on = player.field + player.comeBox + player.dontBox + player.pass.bet + player.pass.odds + player.dont.bet + player.dont.odds
    view.pass = view.pass + player.pass.bet + player.pass.odds
    view.dont = view.dont + player.dont.bet + player.dont.odds
    view.field = view.field + player.field
    view.comeBox = view.comeBox + player.comeBox
    view.dontBox = view.dontBox + player.dontBox
    for spot, number in ipairs(NUMBERS) do
      local come, lay = player.come[number], player.lay[number]
      if come then
        view.numbers[spot].come = view.numbers[spot].come + come.bet + come.odds
        on = on + come.bet + come.odds
      end
      if lay then
        view.numbers[spot].lay = view.numbers[spot].lay + lay.bet + lay.odds
        on = on + lay.bet + lay.odds
      end
    end
    view.seats[index] = { seat = player.seat, name = player.name, on = on }
  end
  return view
end

function rules.viewFor(state, seat)
  local view = publicView(state)
  local player = seat and find(state, seat)
  if not player then return view end
  local mine = {
    net = player.net, unit = player.unit, field = player.field, comeBox = player.comeBox, dontBox = player.dontBox,
    pass = betView(player.pass), dont = betView(player.dont), come = {}, lay = {}, log = {},
    shooting = seat == state.shooter,
    limit = state.stage == "point" and #offers(state, player) == 0,
  }
  for _, number in ipairs(NUMBERS) do
    if player.come[number] then mine.come[#mine.come + 1] = betView(player.come[number], number) end
    if player.lay[number] then mine.lay[#mine.lay + 1] = betView(player.lay[number], number) end
  end
  for index, line in ipairs(player.log) do mine.log[index] = { label = line.label, amount = line.amount } end
  view.mine = mine
  return view
end

function rules.done(state)
  return state.over
end

function rules.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net end
  return nets
end

function rules.result(state, seat)
  local player = seat and find(state, seat)
  if not player then
    local detail = state.total and ("Last roll " .. state.total .. ", " .. state.rolls .. (state.rolls == 1 and " roll" or " rolls") .. " this round") or ""
    return { kind = "push", title = state.call or "ROUND OVER", detail = detail }
  end
  local detail = (state.call or "") .. ". You staked " .. player.staked .. " this round"
  if player.net > 0 then return { kind = "win", title = "YOU WON " .. player.net, detail = detail } end
  if player.net < 0 then return { kind = "lose", title = "YOU LOST " .. -player.net, detail = detail } end
  return { kind = "push", title = "EVEN", detail = detail }
end

function rules.maxWin(entry)
  return entry.bet * rules.MAX_TIMES
end

function rules.risk(state, seat)
  local player = find(state, seat)
  return player and player.staked or 0
end

--- The dice stay with a shooter who has not sevened out. Either way the next round knows whose they were.
function rules.finish(state, keep)
  if state.shooter then
    keep.shooter, keep.passDice = state.shooter, state.sevenOut
  else
    keep.shooter, keep.passDice = state.shot, true
  end
end

return rules
