-- games/liarsdice/rules.lua
-- Liar's Dice for two, a stake per match. Both roll five dice in secret. They take turns to bid how many of a face are on the table
-- between them, each bid higher than the last, until one calls LIAR. Every die then shows. Ones count as the bid face, unless the bid
-- is for ones. If the bid was short the bidder loses a die, otherwise the caller does. The loser opens the next round, and whoever
-- runs out of dice pays the stake.
--
-- A bid goes up by count, or stays on the count and goes up by face. Ones rank above sixes, because nothing is wild for them.
-- The player builds a bid by tapping a count and a face on their wall. That draft lives in the state, so a reboot keeps it, and it is
-- always a legal bid: tapping something that needs a change to the other half makes that change.

local M = {}

M.DICE = 5
M.FACES = 6

local ONE = { "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX" }
local MANY = { "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES" }

--- A bid in words, such as 3 FIVES.
function M.words(count, face)
  return count .. " " .. (count == 1 and ONE[face] or MANY[face])
end

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

local function total(state)
  local sum = 0
  for _, player in ipairs(state.players) do sum = sum + player.left end
  return sum
end

--- How a face ranks within a count. Ones sit above sixes.
local function rank(face)
  return face == 1 and M.FACES + 1 or face
end

--- Whether a bid beats the one on the table. With nothing on the table any bid does.
function M.raises(bid, count, face)
  if not bid then return true end
  return count > bid.count or (count == bid.count and rank(face) > rank(bid.face))
end

--- The lowest bid there is now: count, face. nil when the bid on the table cannot be beaten.
local function lowest(state)
  local bid = state.bid
  local count, face = 1, 2
  if bid then
    count, face = bid.count, bid.face
    if face == 1 then
      count, face = count + 1, 2
    elseif face == M.FACES then
      face = 1
    else
      face = face + 1
    end
  end
  if count > total(state) then return nil end
  return count, face
end

--- The draft goes back to the lowest bid, so a press of BID is always good.
local function resetDraft(state)
  local count, face = lowest(state)
  state.draft = count and { count = count, face = face } or nil
end

local function whole(value)
  return type(value) == "number" and value == math.floor(value)
end

local function roll(state, rng)
  for _, player in ipairs(state.players) do
    local dice = {}
    for index = 1, player.left do dice[index] = rng:below(M.FACES) + 1 end
    table.sort(dice)
    player.dice = dice
  end
  state.round = state.round + 1
  state.phase = "bid"
  state.bid, state.bids = nil, {}
  resetDraft(state)
end

--- How many dice on the table make a bid good.
function M.counted(state, face)
  local found = 0
  for _, player in ipairs(state.players) do
    for _, die in ipairs(player.dice) do
      if die == face or (die == 1 and face ~= 1) then found = found + 1 end
    end
  end
  return found
end

local function challenge(state, seat)
  local bid = state.bid
  local actual = M.counted(state, bid.face)
  local caller = find(state, seat)
  local bidder = find(state, bid.seat)
  local loser = actual >= bid.count and caller or bidder
  loser.left = loser.left - 1
  state.last = { caller = seat, bidder = bid.seat, count = bid.count, face = bid.face, actual = actual, loser = loser.seat }
  state.turn = loser.seat
  state.draft = nil
  if loser.left == 0 then
    state.over = true
    state.phase = "over"
    state.winner = other(state, loser.seat).seat
  else
    state.phase = "reveal"
  end
  return { { type = "liar", seat = seat }, { type = "reveal", loser = loser.seat } }
end

function M.new(entries, button, rng, keep)
  local players = {}
  for index, entry in ipairs(entries) do
    players[index] = { seat = entry.seat, name = entry.name, left = M.DICE, dice = {} }
  end
  -- Never more than the shorter stack, so a loser can always cover it
  local stake = entries[1].stake or entries[1].stack
  for _, entry in ipairs(entries) do stake = math.min(stake, entry.stack) end
  local first = players[button] or players[1]
  local state = { players = players, stake = stake, turn = first.seat, round = 0, phase = "bid", bids = {}, over = false }
  roll(state, rng)
  return state, { { type = "roll" } }
end

function M.waitingOn(state)
  if state.over or state.phase ~= "bid" then return {} end
  return { state.turn }
end

function M.actions(state, seat)
  if state.over or state.phase ~= "bid" or seat ~= state.turn then return {} end
  local list = {}
  local draft = state.draft
  if draft then
    list[1] = { id = "bid", label = "BID " .. M.words(draft.count, draft.face), color = "win", textColor = "ink",
      sub = draft.face == 1 and "Only ones count" or "Ones count too" }
  end
  if state.bid then
    list[#list + 1] = { id = "liar", label = "LIAR!", color = "red", sub = "Call " .. M.words(state.bid.count, state.bid.face) }
  end
  return list
end

--- Set the draft's count, changing its face if the bid on the table needs that.
local function pickCount(state, count)
  local draft = state.draft
  if not draft or not whole(count) or count < 1 or count > total(state) then return false end
  if M.raises(state.bid, count, draft.face) then
    draft.count = count
    return true
  end
  -- Same count as the table, on a face that does not beat it: the next face up does
  local low, face = lowest(state)
  if low ~= count then return false end
  draft.count, draft.face = count, face
  return true
end

--- Set the draft's face, adding one to its count if the bid on the table needs that.
local function pickFace(state, face)
  local draft = state.draft
  if not draft or not whole(face) or face < 1 or face > M.FACES then return false end
  if M.raises(state.bid, draft.count, face) then
    draft.face = face
    return true
  end
  if draft.count >= total(state) then return false end
  draft.count, draft.face = draft.count + 1, face
  return true
end

function M.act(state, seat, id, value, rng)
  if state.over then return {} end
  if seat == nil then
    if id ~= "roll" or state.phase ~= "reveal" or not rng then return {} end
    roll(state, rng)
    return { { type = "roll" } }
  end
  if state.phase ~= "bid" or seat ~= state.turn then return {} end
  if id == "count" or id == "face" then
    local changed
    if id == "count" then changed = pickCount(state, value) else changed = pickFace(state, value) end
    return changed and { { type = "pick", seat = seat } } or {}
  end
  if id == "bid" then
    local draft = state.draft
    if not draft or not M.raises(state.bid, draft.count, draft.face) then return {} end
    state.bid = { seat = seat, count = draft.count, face = draft.face }
    state.bids[#state.bids + 1] = { seat = seat, count = draft.count, face = draft.face }
    state.turn = other(state, seat).seat
    resetDraft(state)
    return { { type = "bid", seat = seat, count = draft.count, face = draft.face } }
  end
  if id == "liar" and state.bid then return challenge(state, seat) end
  return {}
end

--- A missing player takes the lowest opening bid, or calls whatever stands. Calling ends the round, so nobody can stall a match.
function M.auto(state, seat)
  if seat == nil then return "roll" end
  return state.bid and "liar" or "bid"
end

function M.viewFor(state, seat)
  local open = state.over or state.phase == "reveal"
  local view = {
    phase = state.phase, over = state.over, round = state.round, stake = state.stake, turn = state.turn, total = total(state),
    winner = state.winner, players = {}, bids = {},
  }
  for index, player in ipairs(state.players) do
    local shown = { seat = player.seat, name = player.name, left = player.left }
    if open then
      shown.dice = {}
      for position, die in ipairs(player.dice) do shown.dice[position] = die end
    end
    view.players[index] = shown
  end
  if state.bid then view.bid = { seat = state.bid.seat, count = state.bid.count, face = state.bid.face } end
  for index, bid in ipairs(state.bids) do
    view.bids[index] = { seat = bid.seat, count = bid.count, face = bid.face }
  end
  local last = state.last
  if last then
    view.last = { caller = last.caller, bidder = last.bidder, count = last.count, face = last.face, actual = last.actual, loser = last.loser }
  end

  -- Only this seat's own dice, and its draft only on its own turn
  local own = seat and find(state, seat)
  if own then
    view.me = seat
    view.mine = {}
    for position, die in ipairs(own.dice) do view.mine[position] = die end
    if state.phase == "bid" and not state.over and state.turn == seat and state.draft then
      view.draft = { count = state.draft.count, face = state.draft.face }
      -- What the picker may offer, worked out here because a view cannot call the rules
      view.counts, view.faces = {}, {}
      local low = lowest(state)
      for count = 1, view.total do view.counts[count] = count >= low end
      for face = 1, M.FACES do
        view.faces[face] = M.raises(state.bid, state.draft.count, face) or state.draft.count < view.total
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
  local player = seat and find(state, seat)
  if not player then
    return { kind = "win", title = winner.name .. " WINS", detail = "Takes " .. state.stake .. " from " .. loser.name }
  end
  if player == winner then
    return { kind = "win", title = "YOU WIN", detail = "+" .. state.stake .. ". " .. loser.name .. " is out of dice" }
  end
  return { kind = "lose", title = "YOU LOSE", detail = "-" .. state.stake .. ". You are out of dice" }
end

function M.risk(state, seat)
  return find(state, seat) and state.stake or 0
end

return M
