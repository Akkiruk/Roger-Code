-- games/farkle/rules.lua
-- Farkle for two, a stake per match, first to 5,000. Each turn the computer throws six dice for whoever is up. They set aside at least
-- one scoring die, then roll the rest or bank. A roll with nothing scoring is a farkle and the turn's points are gone. Once all six
-- dice have scored they are hot: the player may roll all six again and keep the points.
--
-- Only dice from one roll combine. A first bank needs 500 or more. When a player banks past the target the other gets one last turn
-- to beat them, and a tie on that turn goes to the one who got there first, so a match cannot tie.
--
-- The player picks dice by tapping them. Those marks live in the state, so a reboot keeps them. A mark can sit on a die that does not
-- score yet, because the third of a set has to be tapped after the first two: ROLL and BANK are what refuse a selection with a dead
-- die in it. Everything here is public but the rng, which is never kept.

local ui = require("lib.casino.ui")

local M = {}

M.DICE = 6
M.FACES = 6
M.TARGET = 5000
M.OPENING = 500

-- Sets of one face: how many dice to what they score. Three ones are the only three that do not follow the face x 100 rule
local KINDS = { [4] = 1000, [5] = 2000, [6] = 3000 }
local THREE_ONES = 1000
local STRAIGHT, THREE_PAIRS, TWO_TRIPLES = 1500, 1500, 2500
local SINGLES = { [1] = 100, [5] = 50 }

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

--- All of count dice of one face as the most points they can make, or nil if some cannot score.
local function ofOneFace(face, count)
  if count == 0 then return 0 end
  local single = SINGLES[face]
  local best = single and single * count or nil
  if count >= 3 then
    local three = face == 1 and THREE_ONES or face * 100
    local rest = count - 3
    if rest == 0 or single then best = math.max(best or 0, three + (single or 0) * rest) end
  end
  if KINDS[count] then best = math.max(best or 0, KINDS[count]) end
  return best
end

--- What exactly these dice score together, every die counted, or nil if any of them does not score. Takes the best reading, so
-- four ones are three ones and a one, 1100, and not four of a kind, 1000.
function M.score(faces)
  local counts = {}
  for face = 1, M.FACES do counts[face] = 0 end
  for _, face in ipairs(faces) do counts[face] = counts[face] + 1 end

  local best, whole = 0, true
  for face = 1, M.FACES do
    local points = ofOneFace(face, counts[face])
    if points then best = best + points else whole = false end
  end
  if not whole or #faces == 0 then best = nil end

  if #faces == M.DICE then
    local ones, pairsOf, triples = 0, 0, 0
    for face = 1, M.FACES do
      if counts[face] == 1 then ones = ones + 1 end
      if counts[face] == 2 then pairsOf = pairsOf + 1 end
      if counts[face] == 3 then triples = triples + 1 end
    end
    if ones == M.FACES then best = math.max(best or 0, STRAIGHT) end
    if pairsOf == 3 then best = math.max(best or 0, THREE_PAIRS) end
    if triples == 2 then best = math.max(best or 0, TWO_TRIPLES) end
  end
  return best
end

--- The faces under some marks.
local function marked(dice, marks)
  local faces = {}
  for index, face in ipairs(dice) do
    if marks[index] then faces[#faces + 1] = face end
  end
  return faces
end

--- The best selection of a roll: its marks and its points. 0 points is a farkle. More dice of a face never score less, so it is
-- every face that scores, whole, unless all six dice together make more.
function M.best(dice)
  local counts = {}
  for face = 1, M.FACES do counts[face] = 0 end
  for _, face in ipairs(dice) do counts[face] = counts[face] + 1 end
  local points, marks = 0, {}
  for index, face in ipairs(dice) do marks[index] = ofOneFace(face, counts[face]) ~= nil end
  for face = 1, M.FACES do points = points + (ofOneFace(face, counts[face]) or 0) end
  if #dice == M.DICE then
    local all = M.score(dice)
    if all and all > points then
      for index = 1, M.DICE do marks[index] = true end
      return marks, all
    end
  end
  return marks, points
end

--- How many dice are marked now, and what they score, or nil if nothing is marked or a die in there is dead.
local function picked(state)
  local faces = marked(state.dice, state.marks)
  return #faces, M.score(faces)
end

--- Banking this many points now would be allowed.
local function mayBank(state, total)
  return find(state, state.turn).opened or total >= M.OPENING
end

--- The next player's turn. The dice stay as they were until the next throw, so both walls can see what just happened.
local function pass(state)
  state.turn = other(state, state.turn).seat
  state.phase = "throw"
  state.points = 0
end

--- The match is over and the higher score wins. A tie can only come on the last turn, and goes to who got there first.
local function finish(state)
  local leader, chaser = find(state, state.closing.leader), find(state, state.closing.chaser)
  state.winner = chaser.score > leader.score and chaser.seat or leader.seat
  state.over = true
  state.phase = "over"
end

local function throw(state, rng, count)
  local dice, marks = {}, {}
  for index = 1, count do
    dice[index] = rng:below(M.FACES) + 1
    marks[index] = false
  end
  table.sort(dice)
  state.dice, state.marks = dice, marks
  state.phase = "pick"
  local events = { { type = "roll", seat = state.turn, count = count, running = state.points } }
  local _, points = M.best(dice)
  if points > 0 then return events end

  state.last = { seat = state.turn, kind = "farkle", points = state.points }
  events[2] = { type = "farkle", seat = state.turn, lost = state.points }
  if state.closing then finish(state) else pass(state) end
  return events
end

--- Set the marked dice aside and throw the others. With none left the dice are hot and all six go again.
local function rollOn(state, rng)
  local count, points = picked(state)
  if not points or not rng then return {} end
  state.points = state.points + points
  local left = #state.dice - count
  for _, face in ipairs(marked(state.dice, state.marks)) do state.aside[#state.aside + 1] = face end
  if left > 0 then return throw(state, rng, left) end
  state.aside = {}
  local seat = state.turn
  local events = throw(state, rng, M.DICE)
  table.insert(events, 1, { type = "hot", seat = seat })
  return events
end

local function bank(state)
  local _, points = picked(state)
  if not points then return {} end
  local total = state.points + points
  if not mayBank(state, total) then return {} end
  local player = find(state, state.turn)
  player.score = player.score + total
  player.opened = true
  state.last = { seat = player.seat, kind = "bank", points = total }
  local events = { { type = "bank", seat = player.seat, points = total } }
  if state.closing then
    finish(state)
  elseif player.score >= M.TARGET then
    state.closing = { leader = player.seat, chaser = other(state, player.seat).seat }
    events[2] = { type = "lastturn", seat = state.closing.chaser }
    pass(state)
  else
    pass(state)
  end
  return events
end

function M.new(entries, button, rng, keep)
  local players = {}
  for index, entry in ipairs(entries) do
    players[index] = { seat = entry.seat, name = entry.name, score = 0, opened = false }
  end
  -- Never more than the shorter stack, so a loser can always cover it
  local stake = entries[1].stake or entries[1].stack
  for _, entry in ipairs(entries) do stake = math.min(stake, entry.stack) end
  local first = players[button] or players[1]
  local state = { players = players, stake = stake, turn = first.seat, phase = "throw", points = 0, aside = {}, dice = {}, marks = {}, over = false }
  return state, throw(state, rng, M.DICE)
end

--- Between turns the computer throws, so nobody has a press to make that has no choice in it.
function M.waitingOn(state)
  if state.phase ~= "pick" then return {} end
  return { state.turn }
end

--- What a bank would do on the last turn, for the button.
local function closingNote(state, total)
  local leader = find(state, state.closing.leader)
  local mine = find(state, state.turn).score + total
  if mine > leader.score then return "Wins the match" end
  if mine == leader.score then return "A tie, and you lose" end
  return "Short, and you lose"
end

function M.actions(state, seat)
  if state.phase ~= "pick" or seat ~= state.turn then return {} end
  local count, points = picked(state)
  local roll = { id = "roll", label = "ROLL", color = "win", textColor = "ink", disabled = true }
  local bankIt = { id = "bank", label = "BANK", color = "gold", textColor = "ink", disabled = true }
  if count == 0 then
    roll.sub, bankIt.sub = "Tap the dice to keep", "Tap the dice to keep"
  elseif not points then
    roll.sub, bankIt.sub = "A die there does not score", "A die there does not score"
  else
    local left = #state.dice - count
    local hot = left == 0
    local rolled = hot and M.DICE or left
    roll.label = "ROLL " .. rolled .. (rolled == 1 and " DIE" or " DICE")
    roll.disabled = nil
    roll.sub = hot and "Hot dice! All six again" or nil
    local total = state.points + points
    bankIt.label = "BANK " .. ui.group(total)
    if mayBank(state, total) then
      bankIt.disabled = nil
      if state.closing then bankIt.sub = closingNote(state, total) end
    else
      bankIt.sub = "A first bank needs " .. M.OPENING
    end
  end
  return { roll, bankIt }
end

function M.act(state, seat, id, value, rng)
  if state.over then return {} end
  if seat == nil then
    if id ~= "roll" or state.phase ~= "throw" or not rng then return {} end
    state.aside = {}
    return throw(state, rng, M.DICE)
  end
  if state.phase ~= "pick" or seat ~= state.turn then return {} end
  if id == "die" then
    if type(value) ~= "number" or value ~= math.floor(value) or value < 1 or value > #state.dice then return {} end
    state.marks[value] = not state.marks[value]
    return { { type = "pick", seat = seat } }
  end
  if id == "roll" then return rollOn(state, rng) end
  if id == "bank" then return bank(state) end
  if id == "clock" and rng then
    state.marks = M.best(state.dice)
    local _, points = picked(state)
    if mayBank(state, state.points + points) then return bank(state) end
    return rollOn(state, rng)
  end
  return {}
end

--- A missing player takes the best the roll has and banks if they may, and otherwise rolls on. With no seat it is the computer's throw.
function M.auto(state, seat)
  if seat == nil then return "roll" end
  return "clock"
end

function M.viewFor(state, seat)
  local view = {
    phase = state.phase, over = state.over, stake = state.stake, turn = state.turn, target = M.TARGET, opening = M.OPENING,
    points = state.points, winner = state.winner, players = {}, dice = {}, marks = {}, aside = {},
  }
  for index, player in ipairs(state.players) do
    view.players[index] = { seat = player.seat, name = player.name, score = player.score, opened = player.opened }
  end
  for index, face in ipairs(state.dice) do
    view.dice[index] = face
    view.marks[index] = state.marks[index] == true
  end
  for index, face in ipairs(state.aside) do view.aside[index] = face end
  if state.last then view.last = { seat = state.last.seat, kind = state.last.kind, points = state.last.points } end
  if state.closing then view.closing = { leader = state.closing.leader, chaser = state.closing.chaser } end

  if state.phase == "pick" then
    local count, points = picked(state)
    view.picked = points or 0
    view.dead = count > 0 and not points
    view.hot = points ~= nil and count == #state.dice
    view.running = state.points + (points or 0)
    view.scoring = M.best(state.dice)
  end
  if find(state, seat) then view.me = seat end
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
      nets[player.seat] = state.stake
    else
      nets[player.seat] = -state.stake
    end
  end
  return nets
end

function M.result(state, seat)
  local winner, loser = find(state, state.winner), other(state, state.winner)
  if not winner then return { kind = "push", title = "MATCH ON", detail = "" } end
  local line = ui.group(winner.score) .. " to " .. ui.group(loser.score)
  if winner.score == loser.score then line = line .. ", and " .. winner.name .. " got there first" end
  local player = seat and find(state, seat)
  if not player then
    return { kind = "win", title = winner.name .. " WINS", detail = line .. ". Takes " .. state.stake .. " from " .. loser.name }
  end
  if player == winner then
    return { kind = "win", title = "YOU WIN", detail = "+" .. state.stake .. ". " .. line }
  end
  return { kind = "lose", title = "YOU LOSE", detail = "-" .. state.stake .. ". " .. line }
end

function M.risk(state, seat)
  return find(state, seat) and state.stake or 0
end

return M
