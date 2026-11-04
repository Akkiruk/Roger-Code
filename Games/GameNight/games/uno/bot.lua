-- games/uno/bot.lua
-- How a computer player picks its card. It plays when it can, keeps its wilds for when it has nothing else or someone is about to go
-- out, stays in the colour it holds most of, gets rid of high cards and action cards (20 points each in someone else's count), and
-- saves Draw Twos, Skips and Wild Draw Fours for the player after it when that player is close to going out or leads the scores.
-- Pure: it reads the state and returns a choice. rules.lua does the move.

local cards = require("games.uno.cards")

local M = {}

local function nextOf(state, p)
  local n = #state.players
  return ((p - 1 + state.dir) % n) + 1
end

--- Whether the player after p is a danger: about to go out, or leading the scores near the goal.
function M.threat(state, p)
  local q = nextOf(state, p)
  local victim = state.players[q]
  if #victim.hand <= 2 then return true end
  if state.goal and state.goal > 0 then
    local top = 0
    for _, player in ipairs(state.players) do top = math.max(top, player.score) end
    if victim.score == top and victim.score >= state.goal * 0.6 and #victim.hand <= 4 then return true end
  end
  return false
end

--- How much the computer wants to play this card now.
local function worth(state, p, card, threat, others)
  local hand = state.players[p].hand
  local counts = cards.colorCounts(hand)
  local kind = cards.kind(card)
  local score
  if kind == "W" then
    score = others and -30 or 5
  elseif kind == "F" then
    score = others and -40 or 4
    if threat then score = 60 end
  elseif kind == "D" then
    score = 14
    if threat then score = 50 end
  elseif kind == "S" then
    score = 13
    if threat then score = 40 end
  elseif kind == "R" then
    score = 12
    if threat and #state.players > 2 then score = 30 elseif threat then score = 40 end
  else
    score = 6 + tonumber(kind) * 0.6
  end
  if not cards.isWild(card) then
    -- Stay in the colour held most, so the next turn has a play
    score = score + (counts[cards.color(card)] - 1) * 2.5
  end
  -- Close to going out, keep a wild for the very last card: it always goes down
  if cards.isWild(card) and #hand <= 3 and others then score = score - 20 end
  return score
end

--- The card to play and, for a wild, its colour. Nothing playable gives nil: the computer draws.
function M.choose(state, p)
  local player = state.players[p]
  local top = state.pile[#state.pile]
  local plays = {}
  local plain = false
  for _, card in ipairs(player.hand) do
    if cards.playable(card, top, state.color) then
      plays[#plays + 1] = card
      if not cards.isWild(card) then plain = true end
    end
  end
  if #plays == 0 then return nil end
  local threat = M.threat(state, p)
  local best, bestScore = nil, -math.huge
  for _, card in ipairs(plays) do
    local score = worth(state, p, card, threat, plain)
    if score > bestScore then best, bestScore = card, score end
  end
  if cards.isWild(best) then return best, M.colorFor(player.hand, best) end
  return best, nil
end

--- The colour to name with a wild: the one held most once the wild has gone.
function M.colorFor(hand, wild)
  local rest = {}
  local skipped = false
  for _, card in ipairs(hand) do
    if card == wild and not skipped then skipped = true else rest[#rest + 1] = card end
  end
  return cards.bestColor(rest)
end

return M
