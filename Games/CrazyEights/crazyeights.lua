-- crazyeights.lua
-- Fun-first Crazy Eights duel for ComputerCraft casino monitors.
-- Best-of-three match with mild consolation on losses and player-friendly AI.

local cfg = require("crazyeights_config")

local LO = cfg.LAYOUT
local PAYOUTS = cfg.PAYOUTS
local SCORE_VALUES = cfg.SCORE_VALUES

local settings_get = settings.get
local epoch = os.epoch
local floor = math.floor
local max = math.max
local min = math.min
local abs = math.abs
local random = math.random

settings.define("crazyeights.debug", {
  description = "Enable debug messages for Crazy Eights.",
  type = "boolean",
  default = false,
})

local DEBUG = settings_get("crazyeights.debug")

local function dbg(message)
  if DEBUG then
    print("[" .. epoch("local") .. "] [crazyeights] " .. tostring(message))
  end
end

local cards = require("lib.cards")
local currency = require("lib.currency")
local sound = require("lib.sound")
local ui = require("lib.ui")
local alert = require("lib.alert")
local recovery = require("lib.crash_recovery")
local gameSetup = require("lib.game_setup")
local betting = require("lib.betting")
local replayPrompt = require("lib.replay_prompt")
local cardAnim = require("lib.card_anim")
local pages = require("lib.casino_pages")
local settlement = require("lib.round_settlement")

local canReplayBet = nil

recovery.configure(cfg.RECOVERY_FILE)
recovery.setGame(cfg.GAME_NAME)

local env = gameSetup.init({
  monitorName = cfg.MONITOR,
  deckCount = cfg.DECK_COUNT,
  gameName = cfg.GAME_NAME,
  logFile = cfg.LOG_FILE,
})

alert.addPlannedExits({
  cfg.EXIT_CODES.MAIN_MENU,
  cfg.EXIT_CODES.USER_TERMINATED,
  cfg.EXIT_CODES.PLAYER_QUIT,
})

local screen = env.screen
local width = env.width
local height = env.height
local cardBack = env.cardBack
local font = env.font
local scale = env.scale
local centerX = floor(width / 2)
local centerY = scale:ratioY(0.38, 0, scale.subtitleY + scale.sectionGap, height - cardBack.height)

cardAnim.init(screen, cardBack)
sound.addSounds(cfg.SOUND_IDS or {})

local hostBankBalance = currency.getHostBalance()
local sessionPlayer = currency.getAuthenticatedPlayerName() or currency.getPlayerName() or "Unknown"
recovery.setPlayer(sessionPlayer)

local function refreshPlayer()
  local name = env.refreshPlayer()
  if name and name ~= "" then
    sessionPlayer = name
    recovery.setPlayer(name)
  end
  return sessionPlayer
end

local function drawPlayerOverlay()
  env.drawPlayerOverlay()
end

local function getMaxBet()
  return currency.getMaxBetLimit(hostBankBalance, cfg.MAX_BET_PERCENT, cfg.HOST_COVERAGE_MULT)
end

local function roundedAmount(value)
  return floor((tonumber(value) or 0) + 0.5)
end

local function drawCenteredLine(text, y, color)
  local value = tostring(text or "")
  local textWidth = ui.getTextSize(value)
  ui.safeDrawText(screen, value, font, floor((width - textWidth) / 2), y, color or colors.white)
end

local function drawCenteredBadge(text, y, textColor, bgColor)
  local value = tostring(text or "")
  if value == "" then
    return
  end

  local padX = scale:scaledX(4, 2, 6)
  local badgeWidth = min(width, ui.getTextSize(value) + (padX * 2))
  local badgeX = max(0, floor((width - badgeWidth) / 2))
  local badgeY = max(0, y - 1)

  screen:fillRect(badgeX, badgeY, badgeWidth, scale.lineHeight + 1, bgColor or colors.black)
  ui.safeDrawText(screen, value, font, badgeX + padX, y, textColor or colors.white)
end

local function cardRank(cardID)
  return tostring(cardID or ""):sub(1, 1)
end

local function cardSuit(cardID)
  return cards.getSuit(cardID)
end

local function suitName(suit)
  local value = tostring(suit or "")
  if value == "heart" then return "Hearts" end
  if value == "diamond" then return "Diamonds" end
  if value == "club" then return "Clubs" end
  if value == "spade" then return "Spades" end
  return value
end

local function suitShort(suit)
  local value = tostring(suit or "")
  if value == "heart" then return "H" end
  if value == "diamond" then return "D" end
  if value == "club" then return "C" end
  if value == "spade" then return "S" end
  return "?"
end

local function suitColor(suit)
  if suit == "heart" then
    return colors.red
  end
  if suit == "diamond" then
    return colors.orange
  end
  if suit == "club" then
    return colors.lightGray
  end
  if suit == "spade" then
    return colors.gray
  end
  return colors.white
end

local function displayCardLabel(cardID)
  if not cardID then
    return ""
  end
  return cards.displayValue(cardID) .. suitShort(cardSuit(cardID))
end

local function cardScore(cardID)
  local rank = cardRank(cardID)
  if rank == "8" then
    return SCORE_VALUES.EIGHT
  end
  if rank == "A" then
    return SCORE_VALUES.ACE
  end
  if rank == "T" or rank == "J" or rank == "Q" or rank == "K" then
    return SCORE_VALUES.FACE
  end
  return tonumber(rank) or 0
end

local function handScore(hand)
  local total = 0
  for _, cardID in ipairs(hand or {}) do
    total = total + cardScore(cardID)
  end
  return total
end

local function sortHand(hand)
  table.sort(hand, function(left, right)
    local leftSuit = suitName(cardSuit(left))
    local rightSuit = suitName(cardSuit(right))
    if leftSuit == rightSuit then
      return cardScore(left) < cardScore(right)
    end
    return leftSuit < rightSuit
  end)
end

local function countSuits(hand)
  local counts = {
    heart = 0,
    diamond = 0,
    club = 0,
    spade = 0,
  }

  for _, cardID in ipairs(hand or {}) do
    local suit = cardSuit(cardID)
    if counts[suit] ~= nil then
      counts[suit] = counts[suit] + 1
    end
  end

  return counts
end

local function chooseBestSuit(hand)
  local counts = countSuits(hand)
  local bestSuit = "spade"
  local bestCount = -1
  local suitOrder = { "heart", "diamond", "club", "spade" }

  for _, suit in ipairs(suitOrder) do
    local score = counts[suit] or 0
    if score > bestCount then
      bestSuit = suit
      bestCount = score
    end
  end

  return bestSuit
end

local function buildFreshDeck()
  local deck = cards.buildDeck(cfg.DECK_COUNT)
  cards.shuffle(deck)
  return deck
end

local function ensureDeck(roundState)
  if #roundState.deck > 0 then
    return
  end

  if #roundState.discardPile <= 1 then
    roundState.deck = buildFreshDeck()
    return
  end

  local topCard = roundState.discardPile[#roundState.discardPile]
  local refill = {}
  for index = 1, #roundState.discardPile - 1 do
    refill[#refill + 1] = roundState.discardPile[index]
  end
  roundState.discardPile = { topCard }
  cards.shuffle(refill)
  roundState.deck = refill
end

local function dealCard(roundState, hand)
  ensureDeck(roundState)
  local cardID = cards.deal(roundState.deck)
  if cardID then
    hand[#hand + 1] = cardID
  end
  return cardID
end

local function removeCardAt(hand, index)
  local removed = hand[index]
  if removed then
    table.remove(hand, index)
  end
  return removed
end

local function otherSide(side)
  if side == "player" then
    return "dealer"
  end
  return "player"
end

local function canPlayCard(cardID, roundState)
  if not cardID then
    return false
  end

  local rank = cardRank(cardID)
  local suit = cardSuit(cardID)

  if roundState.pendingDraw and roundState.pendingDraw > 0 then
    return rank == "2"
  end

  if rank == "8" then
    return true
  end

  return suit == roundState.activeSuit or rank == roundState.activeRank
end

local function getPlayableIndexes(hand, roundState)
  local playable = {}
  for index, cardID in ipairs(hand or {}) do
    if canPlayCard(cardID, roundState) then
      playable[#playable + 1] = index
    end
  end
  return playable
end

local function hasPlayableCard(hand, roundState)
  return #getPlayableIndexes(hand, roundState) > 0
end

local function getTurnPrompt(roundState)
  if roundState.skipSide == roundState.currentSide then
    return "ACE SKIP"
  end

  if roundState.pendingDraw and roundState.pendingDraw > 0 then
    return "STACK +2 OR TAKE " .. tostring(roundState.pendingDraw)
  end

  if roundState.currentSide == "player" then
    return nil
  end

  return roundState.statusText or "DEALER TURN"
end

local function shouldShowSuitBadge(topCard, opts)
  local options = opts or {}
  if options.showSuitBadge ~= nil then
    return options.showSuitBadge == true
  end
  return topCard ~= nil and cardRank(topCard) == "8"
end

local function getHandSpread(count)
  local usableWidth = max(cardBack.width, width - (scale.edgePad * 2))
  if count <= 1 then
    return cardBack.width + scale.cardSpacing, 0
  end

  local maxStep = cardBack.width + scale.cardSpacing
  local fitStep = floor((usableWidth - cardBack.width) / max(1, count - 1))
  local step = max(4, min(maxStep, fitStep))
  local totalWidth = cardBack.width + ((count - 1) * step)
  return totalWidth, step
end

local function getHandPositions(count, y)
  local totalWidth, step = getHandSpread(count)
  local startX = max(scale.edgePad, floor((width - totalWidth) / 2))
  local positions = {}
  for index = 1, count do
    positions[index] = {
      x = startX + ((index - 1) * step),
      y = y,
    }
  end
  return positions
end

local function getPlayerHandY()
  local gap = scale:scaledY(LO.PLAYER_BOTTOM_GAP or 6, scale.edgePad + 1, 10)
  return scale:bottom(cardBack.height + 2, gap)
end

local function getActionButtonY(rowCount)
  local rows = max(1, tonumber(rowCount) or 1)
  local blockHeight = scale.buttonHeight + ((rows - 1) * scale.buttonRowSpacing)
  local playerTopY = getPlayerHandY() - 2
  local preferredY = playerTopY - blockHeight - scale.sectionGap - scale.smallGap
  local minimumY = centerY + cardBack.height + scale.lineHeight + (scale.smallGap * 2)
  return max(minimumY, preferredY)
end

local function getActionHintY(rowCount)
  return max(scale.edgePad, getActionButtonY(rowCount) - scale.lineHeight - scale.smallGap)
end

local function getDealerHandY()
  return scale:scaledY(LO.DEALER_Y or 10, scale.subtitleY + scale.smallGap, centerY - cardBack.height - scale.sectionGap)
end

local function getCenterPileXOffsets()
  local gap = scale:scaledX(10, 6, 18)
  return centerX - cardBack.width - gap, centerX + gap
end

local function renderPileBackdrop(x, y, color)
  screen:fillRect(x - 1, y - 1, cardBack.width + 2, cardBack.height + 2, color)
end

local function renderRound(roundState, opts)
  local options = opts or {}
  local selectedIndex = options.selectedIndex
  local revealDealer = options.revealDealer == true
  local showPlayable = options.showPlayable == true

  screen:clear(LO.TABLE_COLOR)

  local topCard = roundState.discardPile[#roundState.discardPile]
  local discardX, drawX = getCenterPileXOffsets()
  local pileY = centerY

  renderPileBackdrop(discardX, pileY, suitColor(roundState.activeSuit))
  if topCard then
    screen:drawSurface(cards.renderCard(topCard), discardX, pileY)
  end

  renderPileBackdrop(drawX, pileY, colors.gray)
  screen:drawSurface(cardBack, drawX, pileY)

  local pileCaptionY = pileY + cardBack.height + scale.smallGap
  if shouldShowSuitBadge(topCard, options) then
    local activeLabel = string.upper(suitName(roundState.activeSuit))
    drawCenteredBadge(activeLabel, max(scale.edgePad + 1, pileY - scale.lineHeight - scale.sectionGap), suitColor(roundState.activeSuit), colors.black)
  end

  local prompt = options.statusText or getTurnPrompt(roundState)
  if prompt and prompt ~= "" then
    local promptColor = colors.cyan
    if roundState.pendingDraw and roundState.pendingDraw > 0 then
      promptColor = colors.orange
    elseif roundState.currentSide ~= "player" and not options.statusText then
      promptColor = colors.lightGray
    end
    drawCenteredBadge(prompt, pileCaptionY + scale.lineHeight + scale.smallGap, promptColor, colors.black)
  end

  local dealerY = getDealerHandY()
  local dealerPositions = getHandPositions(#roundState.dealerHand, dealerY)
  for index, cardID in ipairs(roundState.dealerHand) do
    local pos = dealerPositions[index]
    if revealDealer then
      screen:drawSurface(cards.renderCard(cardID), pos.x, pos.y)
    else
      screen:drawSurface(cardBack, pos.x, pos.y)
    end
  end

  if revealDealer or #roundState.dealerHand <= 1 then
    local dealerInfo = revealDealer and ("DEALER " .. tostring(#roundState.dealerHand)) or "DEALER 1"
    local dealerColor = #roundState.dealerHand <= 1 and colors.orange or colors.white
    drawCenteredBadge(dealerInfo, max(scale.edgePad, dealerY - scale.lineHeight - scale.smallGap), dealerColor, colors.black)
  end

  local playerY = getPlayerHandY()
  local playerPositions = getHandPositions(#roundState.playerHand, playerY)
  local playable = {}
  if showPlayable then
    for _, index in ipairs(getPlayableIndexes(roundState.playerHand, roundState)) do
      playable[index] = true
    end
  end

  for index, cardID in ipairs(roundState.playerHand) do
    local pos = playerPositions[index]
    local drawY = pos.y
    if selectedIndex == index then
      screen:fillRect(pos.x - 1, pos.y - 2, cardBack.width + 2, cardBack.height + 4, colors.yellow)
      drawY = pos.y - 2
    elseif playable[index] then
      screen:fillRect(pos.x, pos.y - 1, cardBack.width, 1, colors.lime)
    end

    screen:drawSurface(cards.renderCard(cardID), pos.x, drawY)
  end

  if revealDealer or #roundState.playerHand <= 1 then
    local playerInfo = revealDealer and ("YOU " .. tostring(#roundState.playerHand)) or "LAST CARD"
    local playerColor = #roundState.playerHand <= 1 and colors.orange or colors.white
    drawCenteredBadge(playerInfo, max(scale.edgePad, playerY - scale.lineHeight - scale.smallGap), playerColor, colors.black)
  end

  drawPlayerOverlay()
end

local function getTouchedPlayerCard(roundState, px, py)
  local positions = getHandPositions(#roundState.playerHand, getPlayerHandY())
  for index = #positions, 1, -1 do
    local pos = positions[index]
    if px >= pos.x and px <= pos.x + cardBack.width - 1 and py >= pos.y - 2 and py <= pos.y + cardBack.height + 1 then
      return index
    end
  end
  return nil
end

local function chooseSuitPrompt(roundState, side)
  local buttonY = getActionButtonY(2)
  return replayPrompt.waitForChoice(screen, {
    render = function()
      renderRound(roundState, {
        mode = "choose_suit",
        statusText = "CHOOSE SUIT",
        showSuitBadge = false,
      })
    end,
    hint = "",
    hint_y = getActionHintY(2),
    center_x = centerX,
    button_y = buttonY,
    row_spacing = scale.buttonRowSpacing,
    col_spacing = scale.buttonColGap,
    buttons = {
      {
        { id = "heart", text = "HEARTS", color = colors.red },
        { id = "diamond", text = "DIAMONDS", color = colors.orange },
      },
      {
        { id = "club", text = "CLUBS", color = colors.lightGray },
        { id = "spade", text = "SPADES", color = colors.gray },
      },
    },
  })
end

local function applyPlayedCard(roundState, side, cardID, chosenSuit, incomingDraw)
  roundState.discardPile[#roundState.discardPile + 1] = cardID
  roundState.activeRank = cardRank(cardID)
  roundState.activeSuit = chosenSuit or cardSuit(cardID)
  roundState.lastPlayedBy = side
  roundState.pendingDraw = 0
  roundState.skipSide = nil
  roundState.statusText = nil

  local rank = cardRank(cardID)
  if rank == "8" then
    roundState.activeSuit = chosenSuit or roundState.activeSuit
    sound.play(sound.SOUNDS.CRAZY_WILD or sound.SOUNDS.SUCCESS, 0.7)
    roundState.statusText = "SUIT " .. string.upper(suitName(roundState.activeSuit))
  elseif rank == "2" then
    local pending = max(2, (incomingDraw or 0) + 2)
    roundState.pendingDraw = min(cfg.DRAW_CHAIN_CAP, pending)
    sound.play(sound.SOUNDS.CRAZY_DRAW or sound.SOUNDS.CARD_PLACE, 0.7)
    roundState.statusText = (side == "player" and "DEALER" or "YOU") .. " MUST DRAW " .. tostring(roundState.pendingDraw)
  elseif rank == "A" then
    roundState.skipSide = otherSide(side)
    sound.play(sound.SOUNDS.CRAZY_SKIP or sound.SOUNDS.CARD_PLACE, 0.7)
    roundState.statusText = (side == "player" and "DEALER" or "YOU") .. " SKIPPED"
  else
    sound.play(sound.SOUNDS.CARD_PLACE, 0.7)
  end
end

local function chooseDealerCardIndex(roundState)
  local hand = roundState.dealerHand
  local playable = getPlayableIndexes(hand, roundState)
  if #playable == 0 then
    return nil, nil
  end

  local bestIndex = playable[1]
  local bestScore = -100000
  local bestSuitChoice = nil
  local opponentCount = #roundState.playerHand

  for _, index in ipairs(playable) do
    local cardID = hand[index]
    local rank = cardRank(cardID)
    local suitChoice = nil
    if rank == "8" then
      local remaining = {}
      for cardIndex, otherCard in ipairs(hand) do
        if cardIndex ~= index then
          remaining[#remaining + 1] = otherCard
        end
      end
      suitChoice = chooseBestSuit(remaining)
    end

    local score = 0
    local remainingCount = #hand - 1
    if remainingCount == 0 then
      score = score + 2000
    end

    score = score + cardScore(cardID)

    if rank == "8" then
      if #playable > 1 then
        score = score - 25
      else
        score = score + 20
      end
      local counts = countSuits(hand)
      score = score + ((counts[suitChoice] or 0) * 8)
    else
      local counts = countSuits(hand)
      score = score + ((counts[cardSuit(cardID)] or 0) * 6)
    end

    if rank == "2" then
      score = score + 18 + ((3 - min(opponentCount, 3)) * 8)
    end

    if rank == "A" then
      score = score + 10 + ((2 - min(opponentCount, 2)) * 6)
    end

    if roundState.activeSuit == cardSuit(cardID) then
      score = score + 5
    end

    if remainingCount <= 2 then
      score = score + cardScore(cardID)
    end

    if score > bestScore then
      bestScore = score
      bestIndex = index
      bestSuitChoice = suitChoice
    end
  end

  return bestIndex, bestSuitChoice
end

local function showTutorial()
  local tutorialPages = {
    {
      title = "Crazy Eights",
      lines = {
        { text = "Best of 3 rounds.", color = colors.white },
        { text = "Match suit, match rank, or play any 8.", color = colors.white },
        { text = "First to empty their hand wins the round.", color = colors.white },
        { text = "One ante covers the whole match.", color = colors.cyan },
      },
    },
    {
      title = "Action Cards",
      lines = {
        { text = "8 = wild. Choose the next suit.", color = colors.yellow },
        { text = "2 = draw 2. Twos can stack.", color = colors.orange },
        { text = "A = skip the next turn.", color = colors.lightBlue },
        { text = "Draw chains cap at 6 cards.", color = colors.lightGray },
      },
    },
    {
      title = "Payouts",
      lines = {
        { text = "Win 2-0: 1.52x return", color = colors.lime },
        { text = "Win 2-1: 1.42x return", color = colors.lime },
        { text = "Lose 1-2: 0.50x back", color = colors.cyan },
        { text = "Lose 0-2: 0.38x back", color = colors.cyan },
      },
    },
  }

  pages.showPagedLines(screen, font, scale, LO.TABLE_COLOR, tutorialPages, {
    centerX = centerX,
  })
end

local function preRoundMenu()
  while true do
    screen:clear(LO.TABLE_COLOR)
    drawCenteredLine("CRAZY EIGHTS", scale.titleY, colors.yellow)
    drawCenteredLine("Fun-first card duel", scale.subtitleY, colors.lightGray)
    drawCenteredLine("Wild 8s, Draw 2s, Ace skips", scale.subtitleY + scale.lineHeight + scale.smallGap, colors.cyan)

    ui.clearButtons()
    local chosen = nil
    ui.layoutButtonGrid(screen, {
      {
        { text = "PLAY", color = colors.lime, func = function() chosen = "play" end },
      },
      {
        { text = "HOW TO PLAY", color = colors.lightBlue, func = function() chosen = "tutorial" end },
      },
    }, centerX, scale.menuY, scale.buttonRowSpacing, scale.buttonColGap)
    screen:output()

    ui.waitForButton(0, 0)

    if chosen == "play" then
      return
    end
    if chosen == "tutorial" then
      showTutorial()
    end
  end
end

local function betSelection()
  hostBankBalance = currency.getHostBalance()
  return betting.runBetScreen(screen, {
    maxBet = getMaxBet(),
    gameName = cfg.GAME_NAME,
    confirmLabel = "MATCH",
    title = "ANTE FOR MATCH",
    hostBalance = currency.getProtectedHostBalance(hostBankBalance),
    hostCoverageMultiplier = cfg.HOST_COVERAGE_MULT,
  })
end

canReplayBet = function(betAmount)
  if not betAmount or betAmount <= 0 then
    return false
  end

  if currency.getPlayerBalance() < betAmount then
    return false
  end

  if getMaxBet() < betAmount then
    return false
  end

  return true
end

local function buildRoundState(matchState)
  local roundState = {
    betAmount = matchState.betAmount,
    matchIndex = matchState.roundNumber,
    roundNumber = matchState.roundNumber,
    playerRounds = matchState.playerRounds,
    dealerRounds = matchState.dealerRounds,
    deck = buildFreshDeck(),
    discardPile = {},
    playerHand = {},
    dealerHand = {},
    currentSide = matchState.startingSide,
    pendingDraw = 0,
    skipSide = nil,
    activeSuit = nil,
    activeRank = nil,
    statusText = nil,
    lastPlayedBy = nil,
  }

  for _ = 1, cfg.HAND_SIZE do
    dealCard(roundState, roundState.playerHand)
    dealCard(roundState, roundState.dealerHand)
  end

  sortHand(roundState.playerHand)
  sortHand(roundState.dealerHand)

  local discard = nil
  while true do
    ensureDeck(roundState)
    discard = cards.deal(roundState.deck)
    if cardRank(discard) ~= "8" then
      break
    end
    roundState.deck[#roundState.deck + 1] = discard
    cards.shuffle(roundState.deck)
  end

  roundState.discardPile = { discard }
  roundState.activeRank = cardRank(discard)
  roundState.activeSuit = cardSuit(discard)
  roundState.statusText = (matchState.startingSide == "player" and "YOU START" or "DEALER STARTS")

  return roundState
end

local function choosePlayableCard(roundState)
  local selectedIndex = nil
  local playable = getPlayableIndexes(roundState.playerHand, roundState)
  if #playable > 0 then
    selectedIndex = playable[1]
  end

  local choice = nil
  local buttonY = getActionButtonY(1)

  while not choice do
    renderRound(roundState, {
      mode = roundState.pendingDraw > 0 and "stack_choice" or "play_choice",
      selectedIndex = selectedIndex,
      showPlayable = true,
      statusText = roundState.pendingDraw > 0 and ("PLAY A 2 OR TAKE " .. tostring(roundState.pendingDraw)) or nil,
    })

    ui.clearButtons()
    local buttonRows = {}
    if roundState.pendingDraw > 0 then
      buttonRows = {
        {
          { text = "STACK +2", color = colors.orange, func = function()
              if selectedIndex and cardRank(roundState.playerHand[selectedIndex]) == "2" then
                choice = { type = "play", index = selectedIndex }
              else
                ui.displayCenteredMessage(screen, "Pick a 2", colors.orange, 0.8)
              end
            end },
          { text = "TAKE " .. tostring(roundState.pendingDraw), color = colors.red, func = function()
              choice = { type = "take_penalty" }
            end },
        },
      }
    elseif #playable > 0 then
      buttonRows = {
        {
          { text = "PLAY", color = colors.lime, func = function()
              if selectedIndex and canPlayCard(roundState.playerHand[selectedIndex], roundState) then
                choice = { type = "play", index = selectedIndex }
              else
                ui.displayCenteredMessage(screen, "Pick a green card", colors.orange, 0.8)
              end
            end },
        },
      }
    else
      buttonRows = {
        {
          { text = "DRAW", color = colors.cyan, func = function()
              choice = { type = "draw" }
            end },
        },
      }
    end

    ui.layoutButtonGrid(screen, buttonRows, centerX, buttonY, scale.buttonRowSpacing, scale.buttonColGap)
    screen:output()

    while not choice do
      local event, _, param2, param3 = os.pullEvent()
      if event == "monitor_touch" and ui.isAuthorizedMonitorTouch() then
        local cb = ui.checkButtonHit(param2, param3)
        if cb then
          cb()
          break
        end

        local touched = getTouchedPlayerCard(roundState, param2, param3)
        if touched then
          selectedIndex = touched
          sound.play(sound.SOUNDS.CARD_PLACE, 0.5, 1.2)
          break
        end
      end
    end
  end

  return choice
end

local function choosePostDrawAction(roundState, drawnIndex)
  local buttonY = getActionButtonY(1)
  return replayPrompt.waitForChoice(screen, {
    render = function()
      renderRound(roundState, {
        mode = "post_draw",
        selectedIndex = drawnIndex,
        statusText = "PLAY DRAWN CARD?",
        showPlayable = false,
      })
    end,
    hint = "",
    hint_y = getActionHintY(1),
    center_x = centerX,
    button_y = buttonY,
    row_spacing = scale.buttonRowSpacing,
    col_spacing = scale.buttonColGap,
    buttons = {
      {
        { id = "play", text = "PLAY IT", color = colors.lime },
        { id = "keep", text = "KEEP", color = colors.gray },
      },
    },
  }) == "play"
end

local function executePlayerTurn(roundState)
  if roundState.skipSide == "player" then
    roundState.skipSide = nil
    roundState.statusText = "YOU SKIPPED"
    return "skipped"
  end

  if roundState.pendingDraw > 0 then
    local choice = choosePlayableCard(roundState)
    if choice.type == "take_penalty" then
      local cardsToDraw = roundState.pendingDraw
      for _ = 1, cardsToDraw do
        dealCard(roundState, roundState.playerHand)
      end
      sortHand(roundState.playerHand)
      roundState.pendingDraw = 0
      roundState.statusText = "YOU TOOK " .. tostring(cardsToDraw)
      sound.play(sound.SOUNDS.CRAZY_DRAW or sound.SOUNDS.FAIL, 0.7)
      return "drew_penalty"
    end

    local cardID = removeCardAt(roundState.playerHand, choice.index)
    local chosenSuit = nil
    if cardRank(cardID) == "8" then
      chosenSuit = chooseSuitPrompt(roundState, "player")
    end
    applyPlayedCard(roundState, "player", cardID, chosenSuit, roundState.pendingDraw)
    sortHand(roundState.playerHand)
    return "played"
  end

  if hasPlayableCard(roundState.playerHand, roundState) then
    local choice = choosePlayableCard(roundState)
    local cardID = removeCardAt(roundState.playerHand, choice.index)
    local chosenSuit = nil
    if cardRank(cardID) == "8" then
      chosenSuit = chooseSuitPrompt(roundState, "player")
    end
    applyPlayedCard(roundState, "player", cardID, chosenSuit, 0)
    sortHand(roundState.playerHand)
    return "played"
  end

  local drawnCard = dealCard(roundState, roundState.playerHand)
  local drawnIndex = #roundState.playerHand
  roundState.statusText = "YOU DREW 1"
  sound.play(sound.SOUNDS.CARD_PLACE, 0.6)

  if canPlayCard(drawnCard, roundState) then
    if choosePostDrawAction(roundState, drawnIndex) then
      local cardID = removeCardAt(roundState.playerHand, drawnIndex)
      local chosenSuit = nil
      if cardRank(cardID) == "8" then
        chosenSuit = chooseSuitPrompt(roundState, "player")
      end
      applyPlayedCard(roundState, "player", cardID, chosenSuit, 0)
      sortHand(roundState.playerHand)
      return "played_after_draw"
    end
  end

  sortHand(roundState.playerHand)

  return "drew"
end

local function executeDealerTurn(roundState)
  roundState.statusText = "DEALER TURN"
  renderRound(roundState, {
    mode = "dealer_turn",
    statusText = roundState.statusText,
  })
  screen:output()
  os.sleep(0.8)

  if roundState.skipSide == "dealer" then
    roundState.skipSide = nil
    roundState.statusText = "DEALER SKIPPED"
    return "skipped"
  end

  if roundState.pendingDraw > 0 then
    local chainIndex, chainSuit = chooseDealerCardIndex(roundState)
    if chainIndex and cardRank(roundState.dealerHand[chainIndex]) == "2" then
      local cardID = removeCardAt(roundState.dealerHand, chainIndex)
      applyPlayedCard(roundState, "dealer", cardID, chainSuit, roundState.pendingDraw)
      sortHand(roundState.dealerHand)
      return "played"
    end

    local cardsToDraw = roundState.pendingDraw
    for _ = 1, cardsToDraw do
      dealCard(roundState, roundState.dealerHand)
    end
    sortHand(roundState.dealerHand)
    roundState.pendingDraw = 0
    roundState.statusText = "DEALER TOOK " .. tostring(cardsToDraw)
    sound.play(sound.SOUNDS.CRAZY_DRAW or sound.SOUNDS.FAIL, 0.7)
    return "drew_penalty"
  end

  local playIndex, chosenSuit = chooseDealerCardIndex(roundState)
  if playIndex then
    local cardID = removeCardAt(roundState.dealerHand, playIndex)
    applyPlayedCard(roundState, "dealer", cardID, chosenSuit, 0)
    sortHand(roundState.dealerHand)
    return "played"
  end

  dealCard(roundState, roundState.dealerHand)
  sortHand(roundState.dealerHand)
  roundState.statusText = "DEALER DREW 1"
  sound.play(sound.SOUNDS.CARD_PLACE, 0.6)

  local playAfterDrawIndex, playAfterDrawSuit = chooseDealerCardIndex(roundState)
  if playAfterDrawIndex then
    local drawnCard = roundState.dealerHand[playAfterDrawIndex]
    if canPlayCard(drawnCard, roundState) then
      local cardID = removeCardAt(roundState.dealerHand, playAfterDrawIndex)
      applyPlayedCard(roundState, "dealer", cardID, playAfterDrawSuit, 0)
      sortHand(roundState.dealerHand)
      return "played_after_draw"
    end
  end

  return "drew"
end

local function revealRoundResult(roundState, winner)
  local loser = winner == "player" and "dealer" or "player"
  local loserHand = loser == "player" and roundState.playerHand or roundState.dealerHand
  local deadwood = handScore(loserHand)
  local message = winner == "player" and ("Round win! Dealer left " .. tostring(deadwood) .. " points") or ("Dealer wins the round. You kept " .. tostring(deadwood) .. " points")
  local color = winner == "player" and colors.lime or colors.orange

  renderRound(roundState, {
    statusText = message,
    revealDealer = true,
  })
  screen:output()
  ui.displayCenteredMessage(screen, message, color, LO.RESULT_PAUSE)
end

local function playRound(matchState)
  local roundState = buildRoundState(matchState)
  local discardX = getCenterPileXOffsets()

  cardAnim.slideIn(cards.renderCard(roundState.discardPile[1]), discardX, centerY, function()
    renderRound(roundState, {
      mode = "round_start",
      statusText = roundState.statusText,
    })
  end)

  while true do
    refreshPlayer()

    if roundState.currentSide == "player" then
      executePlayerTurn(roundState)
      if #roundState.playerHand == 0 then
        revealRoundResult(roundState, "player")
        return "player"
      end
      roundState.currentSide = "dealer"
    else
      executeDealerTurn(roundState)
      if #roundState.dealerHand == 0 then
        revealRoundResult(roundState, "dealer")
        return "dealer"
      end
      roundState.currentSide = "player"
    end
  end
end

local function resolveMatchPayout(betAmount, playerRounds, dealerRounds)
  local returnMultiple = PAYOUTS.LOSS_SWEEP
  local resultLabel = "Lost 0-2"
  local color = colors.orange

  if playerRounds > dealerRounds then
    color = colors.lime
    if dealerRounds == 0 then
      returnMultiple = PAYOUTS.WIN_SWEEP
      resultLabel = "Won 2-0"
    else
      returnMultiple = PAYOUTS.WIN_CLOSE
      resultLabel = "Won 2-1"
    end
  else
    if playerRounds == 1 then
      returnMultiple = PAYOUTS.LOSS_CLOSE
      resultLabel = "Lost 1-2"
      color = colors.cyan
    end
  end

  local totalReturn = roundedAmount(betAmount * returnMultiple)
  local netChange = totalReturn - betAmount

  return totalReturn, netChange, resultLabel, color
end

local function waitForPostMatchChoice(betAmount, resultLabel, totalReturn, netChange)
  local signed = netChange > 0 and ("+" .. currency.formatTokens(netChange)) or (netChange < 0 and ("-" .. currency.formatTokens(abs(netChange))) or "even")

  return replayPrompt.waitForChoice(screen, {
    render = function()
      screen:clear(LO.TABLE_COLOR)
      drawCenteredLine("CRAZY EIGHTS", scale.titleY, colors.yellow)
      drawCenteredLine(resultLabel, scale.subtitleY, netChange >= 0 and colors.lime or colors.orange)
      drawCenteredLine("Return: " .. currency.formatTokens(totalReturn), scale.subtitleY + scale.lineHeight + scale.smallGap, colors.white)
      drawCenteredLine("Net: " .. signed, scale.subtitleY + (scale.lineHeight * 2) + scale.smallGap, colors.cyan)
      drawPlayerOverlay()
    end,
    hint = function()
      local replayAvailable = canReplayBet(betAmount)
      if replayAvailable then
        return nil
      end
      return "Pick a new ante from the main menu.", colors.orange
    end,
    hint_y = scale.footerButtonY - scale.lineHeight - scale.sectionGap,
    center_x = centerX,
    button_y = scale.footerButtonY - scale.buttonRowSpacing,
    row_spacing = scale.buttonRowSpacing,
    col_spacing = scale.buttonColGap,
    buttons = {
      {
        {
          id = "play_again",
          text = "PLAY AGAIN",
          color = colors.lime,
          enabled = function()
            return canReplayBet(betAmount)
          end,
          disabled_message = "Same ante is no longer available",
        },
        {
          id = "new_bet",
          text = "NEW ANTE",
          color = colors.cyan,
        },
      },
    },
  })
end

local function playMatch(betAmount)
  local matchState = {
    betAmount = betAmount,
    playerRounds = 0,
    dealerRounds = 0,
    roundNumber = 1,
    startingSide = "player",
  }

  recovery.saveBet(betAmount, "match_start")

  while matchState.playerRounds < cfg.WIN_ROUNDS and matchState.dealerRounds < cfg.WIN_ROUNDS and matchState.roundNumber <= 3 do
    if matchState.roundNumber == 2 then
      matchState.startingSide = "dealer"
    else
      matchState.startingSide = "player"
    end

    local winner = playRound(matchState)
    if winner == "player" then
      matchState.playerRounds = matchState.playerRounds + 1
    else
      matchState.dealerRounds = matchState.dealerRounds + 1
    end

    matchState.roundNumber = matchState.roundNumber + 1
  end

  local totalReturn, netChange, resultLabel, color = resolveMatchPayout(betAmount, matchState.playerRounds, matchState.dealerRounds)
  local settlementOk = settlement.applyNetChange(netChange, {
    reason = "CrazyEights: " .. resultLabel,
    winReason = "CrazyEights: " .. resultLabel,
    lossReason = "CrazyEights: " .. resultLabel,
    failurePrefix = "CRITICAL",
  })

  if not settlementOk then
    alert.send("CRITICAL: Failed to settle Crazy Eights match")
  end

  recovery.clearBet()
  sound.play(sound.SOUNDS.CRAZY_MATCH or sound.SOUNDS.SUCCESS, 0.8)

  screen:clear(LO.TABLE_COLOR)
  drawCenteredLine(resultLabel, scale.titleY, color)
  drawCenteredLine("Return: " .. currency.formatTokens(totalReturn), scale.subtitleY, colors.white)
  drawCenteredLine("Rounds " .. tostring(matchState.playerRounds) .. " - " .. tostring(matchState.dealerRounds), scale.subtitleY + scale.lineHeight + scale.smallGap, colors.lightGray)
  screen:output()
  os.sleep(LO.RESULT_PAUSE)

  return waitForPostMatchChoice(betAmount, resultLabel, totalReturn, netChange)
end

sound.play(sound.SOUNDS.BOOT)
recovery.recoverBet(true)
refreshPlayer()

local function main()
  local skipPreRoundMenu = false
  local replayBetAmount = nil

  while true do
    refreshPlayer()
    drawPlayerOverlay()

    local betAmount = nil

    if not skipPreRoundMenu then
      preRoundMenu()
    end

    if skipPreRoundMenu and canReplayBet(replayBetAmount) then
      betAmount = replayBetAmount
    else
      local selectedBet = betSelection()
      if selectedBet and selectedBet > 0 then
        betAmount = selectedBet
      end
    end
    skipPreRoundMenu = false

    if betAmount and betAmount > 0 then
      local roundChoice = playMatch(betAmount)
      hostBankBalance = currency.getHostBalance()
      dbg("Host balance updated: " .. tostring(hostBankBalance) .. ", max bet " .. tostring(getMaxBet()))
      skipPreRoundMenu = (roundChoice == "play_again")
      replayBetAmount = betAmount
    end
  end
end

main()