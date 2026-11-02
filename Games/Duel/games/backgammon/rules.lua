-- games/backgammon/rules.lua
-- Backgammon for two, one game for a stake, with a doubling cube. Nothing moves until the game ends.
--
-- Each player numbers the board from their own side: point 1 is the last before bearing off and 24 is the far end, so a checker always
-- moves down, and my point p is the other player's 25 - p. Rules are written once, for "mine" and "theirs". A checker on the bar is
-- from point 25 and one borne off goes to point 0, so a move is always from - die.
--
-- A turn: the player may double, then rolls, then plays the dice one at a time by tapping a checker's point and a destination. What is
-- legal is worked out once after each change and kept in state.legal, so a view can show it and a reboot keeps it. The selected point
-- is state.draft, as in Liar's Dice. A move lands on the board straight away and can be taken back with UNDO, which uses no randomness,
-- until the last die that can be played is played: that ends the turn. The dice are rolled when ROLL is pressed, so no future roll exists
-- anywhere to be seen.
--
-- Whoever bears off their last checker wins at once. A gammon pays double and a backgammon triple. Nets are capped at the shorter
-- stack, and the cube is only offered while stake * the new cube fits under that cap.

local M = {}

M.POINTS = 24
M.CHECKERS = 15
M.BAR = 25
M.OFF = 0
M.FACES = 6

local BAR, OFF = M.BAR, M.OFF
local START = { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }
local MULTIPLE = { single = 1, drop = 1, gammon = 2, backgammon = 3 }
local HOW_WORD = { single = "", gammon = " A GAMMON", backgammon = " A BACKGAMMON" }
local HOW_NOTE = { single = "", gammon = ", a gammon", backgammon = ", a backgammon" }

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

local function other(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat ~= seat then return player end
  end
  return nil
end

local function whole(value)
  return type(value) == "number" and value == math.floor(value)
end

local function roll(rng)
  return rng:below(M.FACES) + 1
end

-- ------------------------------------------------------------------ the rules of a move

--- Whether every checker is home or off, so this side may bear off.
local function allHome(mine)
  if mine.bar > 0 then return false end
  for point = 7, M.POINTS do
    if mine.points[point] > 0 then return false end
  end
  return true
end

--- Whether a checker sits further from home than this point.
local function behind(mine, point)
  for higher = point + 1, M.POINTS do
    if mine.points[higher] > 0 then return true end
  end
  return false
end

--- Where this die takes a checker from this point, or nil if it cannot go.
local function landing(mine, theirs, from, die)
  if mine.bar > 0 and from ~= BAR then return nil end
  if from == BAR then
    if mine.bar == 0 then return nil end
  elseif mine.points[from] == 0 then
    return nil
  end
  local to = from - die
  if to >= 1 then
    if theirs.points[M.BAR - to] >= 2 then return nil end
    return to
  end
  if not allHome(mine) then return nil end
  -- An exact die always bears off. A higher one only takes the furthest checker
  if to == 0 or not behind(mine, from) then return OFF end
  return nil
end

--- Move one checker. Returns whether it hit.
local function step(mine, theirs, from, to)
  if from == BAR then mine.bar = mine.bar - 1 else mine.points[from] = mine.points[from] - 1 end
  if to == OFF then
    mine.off = mine.off + 1
    return false
  end
  mine.points[to] = mine.points[to] + 1
  local across = M.BAR - to
  if theirs.points[across] ~= 1 then return false end
  theirs.points[across] = 0
  theirs.bar = theirs.bar + 1
  return true
end

--- Take a checker back to where step found it.
local function unstep(mine, theirs, from, to, hit)
  if from == BAR then mine.bar = mine.bar + 1 else mine.points[from] = mine.points[from] + 1 end
  if to == OFF then
    mine.off = mine.off - 1
    return
  end
  mine.points[to] = mine.points[to] - 1
  if hit then
    theirs.points[M.BAR - to] = 1
    theirs.bar = theirs.bar - 1
  end
end

--- The most of these dice that can still be played from here. Bearing off the last checker counts as using them all, because the game
-- is over and no die is left unplayed by choice. Stops as soon as it finds them all used.
local function reach(mine, theirs, left)
  local count = #left
  if count == 0 or mine.off == M.CHECKERS then return count end
  local best, tried = 0, {}
  for index = 1, count do
    local die = left[index]
    if not tried[die] then
      tried[die] = true
      table.remove(left, index)
      for from = BAR, 1, -1 do
        local to = landing(mine, theirs, from, die)
        if to then
          local hit = step(mine, theirs, from, to)
          local played = 1 + reach(mine, theirs, left)
          unstep(mine, theirs, from, to, hit)
          if played > best then best = played end
          if best == count then break end
        end
      end
      table.insert(left, index, die)
      if best == count then break end
    end
  end
  return best
end

--- Every move of one checker that starts a legal play of these dice: { from, to, die }, furthest checker first. As many dice as can be
-- played must be played, so a move that leaves fewer is out. If only one of two different dice can be played, it must be the higher.
function M.moves(mine, theirs, dice)
  local left, found, best, tried = {}, {}, 0, {}
  for index, die in ipairs(dice) do left[index] = die end
  for index = 1, #left do
    local die = left[index]
    if not tried[die] then
      tried[die] = true
      table.remove(left, index)
      for from = BAR, 1, -1 do
        local to = landing(mine, theirs, from, die)
        if to then
          local hit = step(mine, theirs, from, to)
          local played = 1 + reach(mine, theirs, left)
          unstep(mine, theirs, from, to, hit)
          found[#found + 1] = { from = from, to = to, die = die, played = played }
          if played > best then best = played end
        end
      end
      table.insert(left, index, die)
    end
  end
  local high = 0
  if best == 1 and #dice == 2 and dice[1] ~= dice[2] then
    for _, move in ipairs(found) do
      if move.die > high then high = move.die end
    end
  end
  local list = {}
  for _, move in ipairs(found) do
    if move.played == best and move.die >= high then
      list[#list + 1] = { from = move.from, to = move.to, die = move.die }
    end
  end
  return list
end

--- How far a side has to go.
function M.pips(player)
  local sum = player.bar * BAR
  for point = 1, M.POINTS do sum = sum + point * player.points[point] end
  return sum
end

--- single, gammon or backgammon, by what the loser still has out.
function M.kindOfWin(loser)
  if loser.off > 0 then return "single" end
  if loser.bar > 0 then return "backgammon" end
  for point = 19, M.POINTS do
    if loser.points[point] > 0 then return "backgammon" end
  end
  return "gammon"
end

--- What the game pays, once it is over.
local function pays(state)
  return math.min(state.cap, state.stake * state.cube * (MULTIPLE[state.how] or 1))
end

-- ------------------------------------------------------------------ the turn

local function refresh(state)
  local mine = find(state, state.turn)
  state.legal = M.moves(mine, other(state, state.turn), state.left)
end

--- Dice for this player to play: two, or four of a double.
local function deal(state, seat, a, b)
  local dice = { math.max(a, b), math.min(a, b) }
  if a == b then dice = { a, a, a, a } end
  state.turn, state.phase, state.dice, state.left, state.played, state.draft = seat, "move", dice, {}, {}, nil
  for index, die in ipairs(dice) do state.left[index] = die end
  refresh(state)
end

--- What this turn did stays on the wall as state.last. Nothing is left in two places, because a journal will not save a shared table.
local function record(state)
  state.last = { seat = state.turn, dice = state.dice, played = state.played }
  state.dice, state.left, state.played, state.legal, state.draft = nil, nil, nil, nil, nil
end

--- This turn is over and the other player is next.
local function pass(state)
  record(state)
  state.turn = other(state, state.turn).seat
  state.phase = "roll"
end

local function finish(state, winner, how)
  state.over, state.phase, state.winner, state.how, state.offer = true, "over", winner, how, nil
  return { type = "win", seat = winner, how = how }
end

local function play(state, move, events)
  local mine, theirs = find(state, state.turn), other(state, state.turn)
  local hit = step(mine, theirs, move.from, move.to)
  state.played[#state.played + 1] = { from = move.from, to = move.to, die = move.die, hit = hit }
  for index, die in ipairs(state.left) do
    if die == move.die then
      table.remove(state.left, index)
      break
    end
  end
  state.draft = nil
  events[#events + 1] = { type = "move", seat = state.turn, from = move.from, to = move.to, hit = hit }
  if mine.off == M.CHECKERS then
    record(state)
    events[#events + 1] = finish(state, state.turn, M.kindOfWin(theirs))
    return
  end
  refresh(state)
  if #state.legal == 0 then
    local seat = state.turn
    pass(state)
    events[#events + 1] = { type = "turn", seat = seat }
  end
end

--- Whether this seat may offer the cube now: its turn to roll, the cube in the middle or its own, and the doubled game payable in full.
function M.canDouble(state, seat)
  if state.over or state.phase ~= "roll" or seat ~= state.turn then return false end
  if state.holder and state.holder ~= seat then return false end
  return state.stake * state.cube * 2 <= state.cap
end

local function rollDice(state, seat, rng, events)
  deal(state, seat, roll(rng), roll(rng))
  events[#events + 1] = { type = "roll", seat = seat }
  if #state.legal == 0 then
    events[#events + 1] = { type = "blocked", seat = seat }
    pass(state)
  end
end

--- The clock ran out, with nobody there. Plays out the whole turn, so one clock is one turn and a missing player cannot stall a game.
local function playOut(state, seat, rng, events)
  if state.phase == "roll" then
    if not rng then return end
    rollDice(state, seat, rng, events)
    if state.phase ~= "move" then return end
  end
  state.draft = nil
  while state.phase == "move" do play(state, state.legal[1], events) end
end

--- The move from the selected point to this one. Two dice can bear off the same checker, and the lower is the one to spend.
local function moveTo(state, to)
  local chosen
  for _, move in ipairs(state.legal) do
    if move.from == state.draft.from and move.to == to and (not chosen or move.die < chosen.die) then chosen = move end
  end
  return chosen
end

local function canStart(state, from)
  for _, move in ipairs(state.legal) do
    if move.from == from then return true end
  end
  return false
end

local function undo(state, events)
  local move = table.remove(state.played)
  if not move then return end
  unstep(find(state, state.turn), other(state, state.turn), move.from, move.to, move.hit)
  state.left[#state.left + 1] = move.die
  table.sort(state.left, function(a, b) return a > b end)
  state.draft = nil
  refresh(state)
  events[#events + 1] = { type = "undo", seat = state.turn }
end

-- ------------------------------------------------------------------ the contract

function M.new(entries, button, rng, keep)
  local players = {}
  for index, entry in ipairs(entries) do
    local points = {}
    for point = 1, M.POINTS do points[point] = START[point] or 0 end
    players[index] = { seat = entry.seat, name = entry.name, points = points, bar = 0, off = 0 }
  end
  local stake = entries[1].stake or entries[1].stack
  local cap = entries[1].stack
  for _, entry in ipairs(entries) do
    stake = math.min(stake, entry.stack)
    cap = math.min(cap, entry.stack)
  end
  local state = { players = players, stake = stake, cap = cap, cube = 1, over = false, phase = "move", ties = 0 }
  -- One die each, the higher starts and uses both. button plays no part
  local a, b = roll(rng), roll(rng)
  while a == b do
    state.ties = state.ties + 1
    a, b = roll(rng), roll(rng)
  end
  state.opening = { { seat = players[1].seat, die = a }, { seat = players[2].seat, die = b } }
  deal(state, a > b and players[1].seat or players[2].seat, a, b)
  return state, { { type = "opening", seat = state.turn } }
end

function M.waitingOn(state)
  if state.over then return {} end
  if state.phase == "double" then return { other(state, state.offer.seat).seat } end
  return { state.turn }
end

function M.actions(state, seat)
  if state.over then return {} end
  local list = {}
  if state.phase == "double" then
    if seat == state.offer.seat or not find(state, seat) then return list end
    list[1] = { id = "take", label = "TAKE", color = "win", textColor = "ink", sub = "Play on for " .. state.stake * state.offer.cube }
    list[2] = { id = "drop", label = "DROP", color = "red", sub = "Pay " .. state.stake * state.cube }
    return list
  end
  if seat ~= state.turn then return list end
  if state.phase == "roll" then
    list[1] = { id = "roll", label = "ROLL", color = "win", textColor = "ink" }
    if M.canDouble(state, seat) then
      local cube = state.cube * 2
      list[2] = { id = "double", label = "DOUBLE TO " .. cube, color = "gold", textColor = "ink", sub = "The game is worth " .. state.stake * cube }
    end
    return list
  end
  if #state.played > 0 then list[1] = { id = "undo", label = "UNDO", color = "panel2" } end
  return list
end

function M.act(state, seat, id, value, rng)
  if state.over or seat == nil then return {} end
  local events = {}
  if state.phase == "double" then
    if seat == state.offer.seat or not find(state, seat) then return events end
    if id == "take" then
      state.cube, state.holder = state.offer.cube, seat
      state.offer, state.phase = nil, "roll"
      events[1] = { type = "take", seat = seat }
    elseif id == "drop" then
      local winner = state.offer.seat
      events[1] = { type = "drop", seat = seat }
      events[2] = finish(state, winner, "drop")
    end
    return events
  end
  if seat ~= state.turn then return events end
  if id == "auto" then
    playOut(state, seat, rng, events)
    return events
  end
  if state.phase == "roll" then
    if id == "roll" and rng then
      rollDice(state, seat, rng, events)
    elseif id == "double" and M.canDouble(state, seat) then
      state.offer, state.phase = { seat = seat, cube = state.cube * 2 }, "double"
      events[1] = { type = "double", seat = seat, cube = state.offer.cube }
    end
    return events
  end
  if id == "from" then
    if state.draft and state.draft.from == value then
      state.draft = nil
    elseif whole(value) and canStart(state, value) then
      state.draft = { from = value }
    else
      return events
    end
    events[1] = { type = "pick", seat = seat }
  elseif id == "to" then
    local move = state.draft and whole(value) and moveTo(state, value)
    if move then play(state, move, events) end
  elseif id == "undo" then
    undo(state, events)
  end
  return events
end

--- A missing player drops a double. On their turn they never double: they roll and play the first legal moves.
function M.auto(state)
  if state.phase == "double" then return "drop" end
  return "auto"
end

function M.viewFor(state, seat)
  local view = {
    phase = state.phase, over = state.over, turn = state.turn, stake = state.stake, cap = state.cap, cube = state.cube,
    holder = state.holder, winner = state.winner, how = state.how, ties = state.ties, players = {}, opening = {},
  }
  for index, player in ipairs(state.players) do
    local points = {}
    for point = 1, M.POINTS do points[point] = player.points[point] end
    view.players[index] = { seat = player.seat, name = player.name, points = points, bar = player.bar, off = player.off, pips = M.pips(player) }
  end
  for index, entry in ipairs(state.opening) do view.opening[index] = { seat = entry.seat, die = entry.die } end
  local function copyMoves(list)
    local out = {}
    for index, move in ipairs(list) do out[index] = { from = move.from, to = move.to, die = move.die, hit = move.hit } end
    return out
  end
  local function copyDice(list)
    local out = {}
    for index, die in ipairs(list) do out[index] = die end
    return out
  end
  if state.dice then
    view.dice, view.left, view.played = copyDice(state.dice), copyDice(state.left), copyMoves(state.played)
  end
  if state.last then
    view.last = { seat = state.last.seat, dice = copyDice(state.last.dice), played = copyMoves(state.last.played) }
  end
  if state.offer then view.offer = { seat = state.offer.seat, cube = state.offer.cube } end
  if state.over then view.amount = pays(state) end

  -- What this seat may tap, worked out here because a view cannot call the rules, and only on its own turn
  if find(state, seat) then
    view.me = seat
    if state.phase == "move" and state.turn == seat and not state.over then
      view.sources = {}
      local seen = {}
      for _, move in ipairs(state.legal) do
        if not seen[move.from] then
          seen[move.from] = true
          view.sources[#view.sources + 1] = move.from
        end
      end
      if state.draft then
        view.draft = { from = state.draft.from }
        view.targets = {}
        local marked = {}
        for _, move in ipairs(state.legal) do
          if move.from == state.draft.from and not marked[move.to] then
            marked[move.to] = true
            view.targets[#view.targets + 1] = move.to
          end
        end
      end
    end
  end
  return view
end

function M.done(state)
  return state.over
end

function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do
    if not state.over then
      nets[player.seat] = 0
    elseif player.seat == state.winner then
      nets[player.seat] = pays(state)
    else
      nets[player.seat] = -pays(state)
    end
  end
  return nets
end

function M.result(state, seat)
  local winner, loser = find(state, state.winner), other(state, state.winner)
  if not winner then return { kind = "push", title = "GAME ON", detail = "" } end
  local amount = pays(state)
  local capped = amount < state.stake * state.cube * MULTIPLE[state.how]
  local tail = capped and ", capped at the shorter stack" or ""
  local player = seat and find(state, seat)
  if state.how == "drop" then
    if not player then
      return { kind = "win", title = loser.name .. " DROPS", detail = winner.name .. " takes " .. amount }
    end
    if player == winner then
      return { kind = "win", title = "YOU WIN", detail = "+" .. amount .. ". " .. loser.name .. " dropped the double" }
    end
    return { kind = "lose", title = "YOU DROPPED", detail = "-" .. amount .. ". " .. winner.name .. " wins the game" }
  end
  if not player then
    return { kind = "win", title = winner.name .. " WINS" .. HOW_WORD[state.how], detail = "Takes " .. amount .. " from " .. loser.name .. tail }
  end
  local cube = state.cube > 1 and (", cube at " .. state.cube) or ""
  if player == winner then
    return { kind = "win", title = "YOU WIN" .. HOW_WORD[state.how], detail = "+" .. amount .. HOW_NOTE[state.how] .. cube .. tail }
  end
  return { kind = "lose", title = "YOU LOSE" .. HOW_WORD[state.how], detail = "-" .. amount .. HOW_NOTE[state.how] .. cube .. tail }
end

function M.risk(state, seat)
  return find(state, seat) and math.min(state.cap, state.stake * state.cube) or 0
end

return M
