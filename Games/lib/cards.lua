-- cards.lua
-- Shared card deck, shuffling, drawing, and hand evaluation for all card games.
-- Supports standard 52-card deck, multi-deck shoes, and card rendering via surface API.
-- Usage:
--   local cards = require("lib.cards")
--   local deck = cards.buildDeck(6)   -- 6-deck shoe
--   cards.shuffle(deck)
--   local card = cards.deal(deck)
--   local value = cards.blackjackValue({card})

local m_random = math.random

-- Card constants
local SUITS  = { "heart", "diamond", "club", "spade" }
local VALUES = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K" }

local RED_SUITS   = { heart = true, diamond = true }
local BLACK_SUITS = { club = true, spade = true }

local FACE_VALUES = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
  ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  ["T"] = 10, ["J"] = 10, ["Q"] = 10, ["K"] = 10, ["A"] = 11,
}

--- Parse a card ID string into its value character and suit string.
-- @param cardID string  e.g. "Aheart", "Tclub"
-- @return string value, string suit
local function parseCard(cardID)
  assert(type(cardID) == "string" and #cardID >= 2, "Invalid card: " .. tostring(cardID))
  local value = cardID:sub(1, 1)
  local suit  = cardID:sub(2)
  return value, suit
end

--- Check whether a card string is structurally valid.
-- @param cardID string
-- @return boolean
local function isValid(cardID)
  if type(cardID) ~= "string" or #cardID < 2 then return false end
  local v, s = cardID:sub(1, 1), cardID:sub(2)
  return FACE_VALUES[v] ~= nil and (RED_SUITS[s] or BLACK_SUITS[s]) == true
end

--- Build a standard 52-card deck (or multi-deck shoe).
-- @param deckCount number? Number of decks to combine (default 1)
-- @return table  Array of card ID strings
local function buildDeck(deckCount)
  deckCount = deckCount or 1
  local deck = {}
  local idx = 1
  for _ = 1, deckCount do
    for _, suit in ipairs(SUITS) do
      for _, val in ipairs(VALUES) do
        deck[idx] = val .. suit
        idx = idx + 1
      end
    end
  end
  return deck
end

--- Fisher-Yates shuffle in-place.
-- @param tbl table  The array to shuffle
-- @return table  The same table, shuffled
local function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = m_random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

--- Deal one card off the top of a deck (removes and returns it).
-- @param deck table  The deck array
-- @return string  The card ID, or nil if deck is empty
local function deal(deck)
  if #deck == 0 then return nil end
  return table.remove(deck, 1)
end

--- Get the display-friendly label for a card value.
-- "T" becomes "10", everything else stays as-is.
-- @param cardID string
-- @return string
local function displayValue(cardID)
  local v = cardID:sub(1, 1)
  if v == "T" then return "10" end
  return v
end

--- Get the suit string from a card ID.
-- @param cardID string
-- @return string
local function getSuit(cardID)
  return cardID:sub(2)
end

--- Check if a card is red (heart/diamond).
-- @param cardID string
-- @return boolean
local function isRed(cardID)
  return RED_SUITS[getSuit(cardID)] == true
end

--- Check if a card is black (club/spade).
-- @param cardID string
-- @return boolean
local function isBlack(cardID)
  return BLACK_SUITS[getSuit(cardID)] == true
end

-------------------------------------------------
-- Blackjack-specific helpers
-------------------------------------------------

--- Calculate the best blackjack hand total, handling Aces as 11 or 1.
-- @param hand table  Array of card ID strings
-- @return number total, boolean isSoft
local function blackjackValue(hand)
  local total = 0
  local aces = 0
  for _, cardID in ipairs(hand) do
    local v = cardID:sub(1, 1)
    local fv = FACE_VALUES[v]
    total = total + fv
    if v == "A" then aces = aces + 1 end
  end
  local isSoft = false
  while total > 21 and aces > 0 do
    total = total - 10
    aces = aces - 1
  end
  if aces > 0 then isSoft = true end
  return total, isSoft
end

--- Check if a hand is a natural blackjack (2 cards, total 21).
-- @param hand table
-- @return boolean
local function isBlackjack(hand)
  if #hand ~= 2 then return false end
  local total = blackjackValue(hand)
  return total == 21
end

-------------------------------------------------
-- Surface rendering (requires surface API instance)
-------------------------------------------------

-- Cached references set by initRenderer
local _surface  = nil
local _font     = nil
local _cardBg   = nil

--- Initialize the card renderer with a surface API and assets.
-- Call this once after loading the surface library.
-- @param surfaceAPI table  The loaded surface library
-- @param font       table  Loaded font from surface.loadFont
-- @param cardBgImg  table  Loaded card.nfp surface
local function initRenderer(surfaceAPI, font, cardBgImg)
  _surface = surfaceAPI
  _font    = font
  _cardBg  = cardBgImg
end

--- Render a card to a surface object (12x15 pixels).
-- Requires initRenderer() to have been called.
-- @param cardID string
-- @return surface  A 12x15 surface with the card drawn
local function renderCard(cardID)
  assert(_surface, "Call cards.initRenderer() before renderCard()")
  assert(isValid(cardID), "Invalid card: " .. tostring(cardID))

  local number = displayValue(cardID)
  local suit   = getSuit(cardID)
  local card   = _surface.create(12, 15)
  local suitImg = _surface.load(suit .. ".nfp")
  card:drawSurface(_cardBg, 0, 0)
  if suitImg then
    card:drawSurface(suitImg, 5, 2)
  end
  card:drawText(number, _font, 2, 8, colors.black)
  return card
end

return {
  -- Constants
  SUITS       = SUITS,
  VALUES      = VALUES,
  RED_SUITS   = RED_SUITS,
  BLACK_SUITS = BLACK_SUITS,
  FACE_VALUES = FACE_VALUES,

  -- Core deck operations
  buildDeck    = buildDeck,
  shuffle      = shuffle,
  deal         = deal,

  -- Card inspection
  parseCard    = parseCard,
  isValid      = isValid,
  displayValue = displayValue,
  getSuit      = getSuit,
  isRed        = isRed,
  isBlack      = isBlack,

  -- Blackjack helpers
  blackjackValue = blackjackValue,
  isBlackjack    = isBlackjack,

  -- Rendering
  initRenderer = initRenderer,
  renderCard   = renderCard,
}
