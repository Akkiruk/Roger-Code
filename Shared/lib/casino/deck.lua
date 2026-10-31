-- deck.lua
-- Cards as plain numbers, so a game's state serializes and tests without a screen.
-- A card is (rank - 2) * 4 + suit: rank 2..14 with ace high, suit 0..3 (clubs, diamonds, hearts, spades).

local M = {}

M.CLUBS, M.DIAMONDS, M.HEARTS, M.SPADES = 0, 1, 2, 3
M.ACE = 14

local RANK_NAMES = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
local SUIT_NAMES = { [0] = "C", [1] = "D", [2] = "H", [3] = "S" }

function M.card(rank, suit)
  return (rank - 2) * 4 + suit
end

function M.rank(card)
  return math.floor(card / 4) + 2
end

function M.suit(card)
  return card % 4
end

function M.isRed(card)
  local suit = card % 4
  return suit == 1 or suit == 2
end

function M.rankName(card)
  local rank = M.rank(card)
  return RANK_NAMES[rank] or tostring(rank)
end

--- "AS", "10D": used in logs and tests.
function M.name(card)
  return M.rankName(card) .. SUIT_NAMES[M.suit(card)]
end

--- Parse "AS" or "10D" back to a card. For tests and scripted decks.
function M.parse(text)
  local rankText, suitText = text:match("^(%w-)([CDHS])$")
  local rank = tonumber(rankText)
  if not rank then
    for value, name in pairs(RANK_NAMES) do
      if name == rankText then rank = value end
    end
  end
  for value, name in pairs(SUIT_NAMES) do
    if name == suitText then return M.card(rank, value) end
  end
  error("bad card " .. tostring(text))
end

--- An unshuffled shoe of whole decks.
function M.fresh(decks)
  local cards = {}
  for _ = 1, decks or 1 do
    for card = 0, 51 do
      cards[#cards + 1] = card
    end
  end
  return cards
end

--- Fisher-Yates. rng needs below(n), a uniform integer in [0, n).
function M.shuffle(cards, rng)
  for i = #cards, 2, -1 do
    local j = rng:below(i) + 1
    cards[i], cards[j] = cards[j], cards[i]
  end
  return cards
end

--- Take the next card off the end.
function M.draw(cards)
  return table.remove(cards)
end

--- Put named cards on top in deal order: for scripted rounds in tests.
function M.stack(cards, names)
  for i = #names, 1, -1 do
    cards[#cards + 1] = M.parse(names[i])
  end
  return cards
end

return M
