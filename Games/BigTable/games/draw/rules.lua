-- games/draw/rules.lua
-- Five-card draw on Big Table. The game is pokertable_rules, untouched: this file only speaks the group plugin's contract over it.
-- That means seat numbers in place of whose turn it is, a cost on each button, and the cards picked to throw, which live on the
-- player as marks so a reboot keeps them. Each tap is a move of its own, because a seat only reports touches.
-- A tap that would make an illegal draw does nothing, so the marks are always a draw the rules allow.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local rounding = require("lib.casino.group.rounding")
local five = require("pokertable_rules")

local M = {}

local TITLE_ROOM = 18      -- what fits as big text over a wall, with " WINS"
local DETAIL_ROOM = 112
local BETTING = { fold = true, check = true, call = true, raise = true }

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

--- The player to act, if that is this seat.
local function onTurn(state, seat)
  local player = state.turn and state.players[state.turn]
  if player and seat ~= nil and player.seat == seat then return player end
  return nil
end

local function markedCount(player)
  local total = 0
  for _, marked in ipairs(player.marks) do
    if marked then total = total + 1 end
  end
  return total
end

--- The marks as the positions the rules want, such as "125".
local function digits(player)
  local out = ""
  for position, marked in ipairs(player.marks) do
    if marked then out = out .. position end
  end
  return out
end

local function positions(marks)
  local list = {}
  for position, marked in ipairs(marks) do
    if marked then list[#list + 1] = position end
  end
  return list
end

local function copyList(list)
  local out = {}
  for i, item in ipairs(list) do out[i] = item end
  return out
end

--- Tap a card to throw it, tap again to keep it.
local function mark(state, player, position)
  if state.phase ~= "draw" or type(position) ~= "number" or player.marks[position] == nil then return {} end
  local marks = copyList(player.marks)
  marks[position] = not marks[position]
  if not five.legalDiscard(player.hand, positions(marks)) then return {} end
  player.marks = marks
  -- Nothing about which card: this goes to every seat
  return { { type = "mark" } }
end

function M.new(entries, button, rng)
  local state, events = five.new(entries, button, rng)
  for _, player in ipairs(state.players) do
    player.marks = {}
    for position = 1, five.HAND_SIZE do player.marks[position] = false end
  end
  rounding.take(state)
  return state, events
end

function M.waitingOn(state)
  local player = state.turn and state.players[state.turn]
  return player and { player.seat } or {}
end

function M.actions(state, seat)
  local player = onTurn(state, seat)
  if not player then return {} end
  if state.phase == "draw" then
    -- The same button whatever is marked. New buttons make a press in flight count for nothing, and that would eat the second of two
    -- quick taps on the cards
    return { { id = "draw", label = "DRAW", color = "blue" } }
  end
  local list = {}
  for index, action in ipairs(five.actions(state)) do
    list[index] = { id = action.id, label = action.label, color = action.color, textColor = action.textColor,
      sub = action.sub, cost = tonumber(action.sub) }
  end
  return list
end

--- id: fold, check, call or raise, draw to throw what is marked, or mark with a card's position as value.
function M.act(state, seat, id, value)
  local player = onTurn(state, seat)
  if not player then return {} end
  if id == "mark" then return mark(state, player, value) end
  local events = {}
  if id == "draw" then
    if state.phase ~= "draw" then return {} end
    events = five.act(state, "draw" .. digits(player))
  elseif BETTING[id] then
    events = five.act(state, id)
  end
  rounding.take(state)
  return events
end

--- Check if it is free, fold if not. In the draw the cards they have marked go: stand pat if they marked none.
function M.auto(state, seat)
  if not onTurn(state, seat) then return nil end
  if state.phase == "draw" then return "draw" end
  return five.auto(state)
end

--- What everyone at the table can see of a player.
local function publicPlayer(player, state)
  local over = five.done(state)
  local out = {
    seat = player.seat, name = player.name, stack = player.stack, bet = player.bet, total = player.total,
    folded = player.folded, allin = player.allin, last = player.last,
  }
  if over then
    out.net = player.net
    -- Only a showdown turns cards over, and only those still in
    if not state.uncontested and not player.folded then
      out.hand = copyList(player.hand)
      out.handName = player.handName
    end
  end
  return out
end

--- Built field by field. Only a player's own view ever holds their cards or marks, until a showdown turns them over.
function M.viewFor(state, seat)
  local over = five.done(state)
  local actor = state.turn and state.players[state.turn]
  local view = {
    phase = state.phase, over = over, uncontested = state.uncontested, pot = five.potTotal(state), size = state.size,
    betsLeft = state.phase ~= "draw" and five.MAX_BETS - (state.bets or 0) or nil,
    button = state.players[state.button].seat,
    turn = actor and actor.seat or nil, actor = actor and actor.name or nil, players = {},
  }
  if actor and state.phase ~= "draw" then view.toCall = math.min(five.toCall(state), actor.stack) end

  local contested, side = 0, 0
  for _, pot in ipairs(five.pots(state.players)) do
    if #pot.eligible > 1 then
      contested = contested + 1
      if contested > 1 then side = side + pot.amount else view.mainPot = pot.amount end
    end
  end
  view.side = side

  for index, player in ipairs(state.players) do view.players[index] = publicPlayer(player, state) end

  local own = seat and find(state, seat)
  if own then
    view.seat = seat
    view.hand = copyList(own.hand)
    view.handName = poker.describe(poker.evaluate(own.hand))
    view.folded = own.folded
    view.stack = own.stack
    view.total = own.total
    if onTurn(state, seat) and state.phase == "draw" then
      view.drawing = true
      view.marks = copyList(own.marks)
      view.thrown = markedCount(own)
      view.mayThrow = five.MAX_DISCARD
      for _, card in ipairs(own.hand) do
        if deck.rank(card) == deck.ACE then view.mayThrow = five.MAX_DISCARD_ACE end
      end
    end
  end
  return view
end

function M.done(state)
  return five.done(state)
end

function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net or 0 end
  return nets
end

local function signed(amount)
  return (amount > 0 and "+" or "") .. amount
end

function M.result(state, seat)
  local player = seat and find(state, seat)
  if not player then
    local line = five.result(state)
    local title = line.title
    if #title > TITLE_ROOM then title = title:sub(1, TITLE_ROOM - 6) .. ". WINS" end
    return { kind = title:find("SPLIT") and "push" or "win", title = title, detail = line.detail:sub(1, DETAIL_ROOM) }
  end
  local detail = signed(player.net)
  if player.handName then detail = detail .. " with " .. player.handName end
  if player.folded then return { kind = "lose", title = "YOU FOLDED", detail = detail } end
  if state.uncontested then return { kind = "win", title = "YOU WIN", detail = detail .. ". Everyone else folded" } end
  if player.net > 0 then return { kind = "win", title = "YOU WIN", detail = detail } end
  if player.net < 0 then return { kind = "lose", title = "YOU LOSE", detail = detail } end
  return { kind = "push", title = "EVEN", detail = "Your chips come back with " .. tostring(player.handName) }
end

function M.risk(state, seat)
  local player = find(state, seat)
  return player and player.total or 0
end

return M
