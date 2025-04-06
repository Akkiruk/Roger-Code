-------------------------
-- SPEAKER INITIALIZATION
-------------------------
local speakerSide = "top"
local speaker = peripheral.wrap(speakerSide)
if not speaker then error("No speaker detected on side: " .. speakerSide) end

-------------------------
-- SOUND EFFECTS HELPER
-------------------------
local function playSound(soundID)
  speaker.playSound(soundID, 0.5) -- volume reduced by half
end

-------------------------
-- CONFIGURATION
-------------------------
local barrelSide   = "front"     -- where the player's silver is stored
local bankSide     = "bottom"    -- the bank chest
local monitorName  = "right"     -- the monitor peripheral name
local DEBUG        = false       -- set to true for debug prints

-- Single currency: silver
local SILVER_ID = "the_vault:vault_silver"  -- must match your actual item ID
local SILVER_PER_GOLD = 9                   -- 9 silver = 1 gold (for display)

-------------------------
-- LIBRARIES & HELPERS
-------------------------
local function dbg(msg)
  if DEBUG then print("[DEBUG] " .. msg) end
end

function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

math.round = function(x) return x + 0.5 - (x + 0.5) % 1 end

-------------------------
-- PERIPHERALS
-------------------------
local barrel = peripheral.wrap(barrelSide)
if not barrel then error("No barrel on side: " .. barrelSide) end

local bank = peripheral.wrap(bankSide)
if not bank then error("No bank chest on side: " .. bankSide) end

local monitor = peripheral.wrap(monitorName)
if not monitor then error("No monitor named: " .. monitorName) end

-------------------------
-- SURFACE SETUP
-------------------------
local surface, screen, font, cardBg, cardBack
local width, height
local buttons = {}
local deck = {}

function setup()
  surface = dofile("surface")           -- load your surface API
  monitor.setTextScale(0.5)
  term.redirect(monitor)
  term.setPaletteColor(colors.lightGray, 0xc5c5c5)
  term.setPaletteColor(colors.orange, 0xf15c5c)
  term.setPaletteColor(colors.gray, 0x363636)
  term.setPaletteColor(colors.green, 0x044906)
  
  width, height = term.getSize()
  screen = surface.create(width, height)
  font = surface.loadFont(surface.load("font"))
  cardBg  = surface.load("card.nfp")
  cardBack= surface.load("cardback.nfp")
  
  -- Build the deck with six decks
  deck = {}
  local i = 1
  for d = 1, 6 do
      for _, suit in ipairs({"heart", "diamond", "club", "spade"}) do
          for _, num in ipairs({"A", "T", "J", "Q", "K"}) do
              deck[i] = num .. suit
              i = i + 1
          end
          for num = 2, 9 do
              deck[i] = tostring(num) .. suit
              i = i + 1
          end
      end
  end
  shuffle(deck)
end

-------------------------
-- CARD DRAWING
-------------------------
function drawCard(cardID)
  local number = cardID:sub(1, 1)
  if number == "T" then
    number = "10"
  end
  local suit = cardID:sub(2, -1)
  local card = surface.create(12, 15)
  local suitImg = surface.load(suit .. ".nfp")
  card:drawSurface(cardBg, 0, 0)
  card:drawSurface(suitImg, 5, 2)
  card:drawText(number, font, 2, 8, colors.black)
  return card
end

-------------------------
-- CURRENCY FUNCTIONS
-------------------------
local function getSilverCount(inv)
  local total = 0
  local list = inv.list() or {}
  for slot, item in pairs(list) do
    if item and item.name == SILVER_ID then
      total = total + item.count
    end
  end
  return total
end

local function transferSilver(fromInv, fromSide, toInv, toSide, amount)
  if amount <= 0 then return true end
  dbg("Transferring " .. amount .. " silver from " .. fromSide .. " to " .. toSide)
  local needed = amount
  local list = fromInv.list() or {}
  for slot, item in pairs(list) do
    if item and item.name == SILVER_ID then
      local available = item.count
      local toTransfer = math.min(needed, available)
      if toTransfer > 0 then
        local transferred = fromInv.pushItems(toSide, slot, toTransfer)
        dbg("  Attempted " .. toTransfer .. ", got " .. (transferred or 0))
        needed = needed - transferred
        if needed <= 0 then break end
      end
    end
  end
  if needed > 0 then
    dbg("Failed to transfer all silver. Missing " .. needed)
    return false
  end
  return true
end

-------------------------
-- BUTTON & UI HELPERS
-------------------------
function getButtonSurface(text, bg)
  local textSize = surface.getTextSize(text, font)
  local button = surface.create(textSize + 2, 7)
  button:fillRect(0, 0, textSize + 2, 7, bg)
  button:drawText(text, font, 1, 1, colors.black)
  return button
end

function button(surfaceObj, text, bg, x, y, func, center)
  local btnSurf = getButtonSurface(text, bg)
  if center then
    x = math.floor(x - btnSurf.width / 2)
  end
  surfaceObj:drawSurface(btnSurf, x, y)
  buttons[text] = { x = x, y = y, width = btnSurf.width, height = btnSurf.height, cb = func }
  return btnSurf
end

-- New helper: Layout button rows in a centered horizontal grid.
local function layoutButtonGrid(screen, buttonRows, centerX, startY, rowSpacing, colSpacing)
  for i, row in ipairs(buttonRows) do
    local totalWidth = 0
    local btnSurfs = {}
    for j, btn in ipairs(row) do
      local bs = getButtonSurface(btn.text, btn.color)
      btnSurfs[j] = { surf = bs, btn = btn }
      totalWidth = totalWidth + bs.width
      if j > 1 then totalWidth = totalWidth + colSpacing end
    end
    local x = centerX - math.floor(totalWidth / 2)
    local y = startY + (i - 1) * rowSpacing
    for j, bs in ipairs(btnSurfs) do
      screen:drawSurface(bs.surf, x, y)
      buttons[bs.btn.text] = { x = x, y = y, width = bs.surf.width, height = bs.surf.height, cb = bs.btn.func }
      x = x + bs.surf.width + colSpacing
    end
  end
end

function waitForButtonPress(ox, oy)
  while true do
    local event, side, px, py = os.pullEvent("monitor_touch")
    px = px - ox
    py = py - oy
    for _, b in pairs(buttons) do
      if px >= b.x and px <= b.x + b.width - 1 and py >= b.y and py <= b.y + b.height - 1 then
        buttons = {}
        b.cb()
        return
      end
    end
  end
end

-- Helper: Draw a column of buttons given a list, starting at (x, y) with specified spacing.
local function drawButtonsColumn(btnList, startX, startY, spacing)
  for i, b in ipairs(btnList) do
    button(screen, b.text, b.color, startX, startY + (i - 1) * spacing, b.func, true)
  end
  screen:output()
end

-- New helper function to display centered messages (one word per line, uppercase)
function displayCenteredMessage(msg, msgColor, pause)
  pause = pause or 1  -- default pause duration is 1 second
  local words = {}
  msg = msg:upper()
  for word in msg:gmatch("%S+") do
    table.insert(words, word)
  end
  local lineHeight = 10  -- adjust as needed
  local blockHeight = #words * lineHeight
  local startY = math.floor((screen.height - blockHeight) / 2)
  screen:clear(colors.green)
  for i, word in ipairs(words) do
    local textWidth = surface.getTextSize(word, font)
    local centerX = math.floor((screen.width - textWidth) / 2)
    local y = startY + (i - 1) * lineHeight
    screen:drawText(word, font, centerX, y, msgColor)
  end
  screen:output()
  os.sleep(pause)
end

-------------------------
-- BLACKJACK SCORING
-------------------------
function getHandScore(hand)
  local sum = 0
  local aceCount = 0
  for _, card in ipairs(hand) do
    local r = card:sub(1, 1)
    local num = tonumber(r)
    if not num then
      if r == "A" then
        num = 11
        aceCount = aceCount + 1
      else
        num = 10
      end
    end
    sum = sum + num
  end
  while sum > 21 and aceCount > 0 do
    sum = sum - 10
    aceCount = aceCount - 1
  end
  return sum
end

-------------------------
-- BET SELECTION UI (Vertical Column, Full Screen)
-------------------------
-- Helper: Create a button with fixed width for consistent UI
local function fixedWidthButton(screen, text, bg, x, y, func, center, fixedWidth)
  local textSize = surface.getTextSize(text, font)
  local btnWidth = fixedWidth or (textSize + 2)
  local button = surface.create(btnWidth, 7)
  button:fillRect(0, 0, btnWidth, 7, bg)
  -- Center text in the button
  local textX = math.floor((btnWidth - textSize) / 2)
  button:drawText(text, font, textX, 1, colors.black)
  
  if center then
    x = math.floor(x - button.width / 2)
  end
  screen:drawSurface(button, x, y)
  buttons[text] = { x = x, y = y, width = button.width, height = button.height, cb = func }
  return button
end

local function betSelection(screen)
  local bet = 0
  local selecting = true

  while selecting do
    screen:clear(colors.green)
    
    -- Header: "Current Bet" raised by one line (now at row 1) and bet value at row 5
    local headerStr = "Current Bet"
    screen:drawText(headerStr, font, math.round((screen.width - surface.getTextSize(headerStr, font)) / 2), 1, colors.white)
    local betGold = math.floor(bet / SILVER_PER_GOLD)
    local betStr = betGold .. " gold"
    screen:drawText(betStr, font, math.round((screen.width - surface.getTextSize(betStr, font)) / 2), 6, colors.white)
    
    buttons = {}
    -- Vertical column for bet increment buttons, reduced spacing and starting higher
    local btnStartY = 15
    local btnSpacing = 7  -- reduced spacing from 8 to 7
    local btnX = math.round(screen.width / 2)
    
    -- Calculate fixed width for all buttons based on longest text
    local buttonTexts = {"1 Silver", "1 Gold", "1 Platinum", "1 Palladium", "ALL IN", "CLEAR", "START"}
    local maxWidth = 0
    for _, text in ipairs(buttonTexts) do
      local width = surface.getTextSize(text, font) + 6  -- Add padding
      if width > maxWidth then maxWidth = width end
    end
    
    -- Ensure the width is even for better centering
    if maxWidth % 2 == 1 then maxWidth = maxWidth + 1 end
    
    local function addBet(amt)
      return function()
        if getSilverCount(barrel) >= amt then
          local potentialPayout = (bet + amt) * 1.5
          if getSilverCount(bank) >= potentialPayout then
            if transferSilver(barrel, barrelSide, bank, bankSide, amt) then
              bet = bet + amt
              -- Updated sounds for different denominations
              if amt == 1 then
                playSound("quark:ambient.clock")
              elseif amt == 9 then
                playSound("the_vault:coin_single_place")
              elseif amt == 81 then
                playSound("lightmanscurrency:coins_clinking")
              elseif amt == 729 then
                playSound("the_vault:coin_pile_break")
              end
            end
          else
            playSound("the_vault:mob_trap")
            displayCenteredMessage("Bank is poor!", colors.red)
          end
        else
          playSound("the_vault:mob_trap")
          displayCenteredMessage("Insufficient funds!", colors.red)
        end
      end
    end
    
    -- Create vertical list of bet increment buttons with labels and fixed width
    fixedWidthButton(screen, "1 Silver", colors.white, btnX, btnStartY, addBet(1), true, maxWidth)
    fixedWidthButton(screen, "1 Gold", colors.yellow, btnX, btnStartY + btnSpacing, addBet(9), true, maxWidth)
    fixedWidthButton(screen, "1 Platinum", colors.cyan, btnX, btnStartY + btnSpacing * 2, addBet(81), true, maxWidth)
    fixedWidthButton(screen, "1 Palladium", colors.magenta, btnX, btnStartY + btnSpacing * 3, addBet(729), true, maxWidth)
    
    -- ALL IN button now with the betting denominations using a unique gold color
    fixedWidthButton(screen, "ALL IN", colors.orange, btnX, btnStartY + btnSpacing * 4, function()
      local playerSilver = getSilverCount(barrel)
      if playerSilver > 0 then
        local potentialPayout = (bet + playerSilver) * 1.5
        if getSilverCount(bank) >= potentialPayout then
          if transferSilver(barrel, barrelSide, bank, bankSide, playerSilver) then
            bet = bet + playerSilver  -- Add to current bet instead of replacing it
            playSound("the_vault:coin_pile_place")  -- New sound for ALL IN
          end
        else
          playSound("the_vault:mob_trap")
          displayCenteredMessage("Bank is poor!", colors.red)
        end
      else
        playSound("the_vault:mob_trap")
        displayCenteredMessage("No silver!", colors.red)
      end
    end, true, maxWidth)
    
    -- Control buttons now side by side with spacing of 1 pixel
    local ctrlStartY = btnStartY + btnSpacing * 5 + 2  -- Added a small gap after bet buttons
    
    -- Calculate positions for side-by-side buttons with 1px spacing
    -- Use smaller width for control buttons (calculate based on text + small padding)
    local clearWidth = surface.getTextSize("CLEAR", font) + 4
    local startWidth = surface.getTextSize("START", font) + 4
    local controlBtnSpacing = 1  -- 1 pixel spacing between control buttons
    local totalControlWidth = clearWidth + startWidth + controlBtnSpacing
    local clearX = math.floor(btnX - totalControlWidth / 2)
    local startX = clearX + clearWidth + controlBtnSpacing
    
    fixedWidthButton(screen, "CLEAR", colors.red, clearX, ctrlStartY, function()
      if bet > 0 then
        transferSilver(bank, bankSide, barrel, barrelSide, bet)
        bet = 0
        playSound("the_vault:mega_jump")
      end
    end, false, clearWidth)
    
    fixedWidthButton(screen, "START", colors.magenta, startX, ctrlStartY, function()
      if bet > 0 then
        playSound("the_vault:artifact_complete")
        selecting = false
      else
        screen:drawText("Bet must be > 0!", font, 2, ctrlStartY + btnSpacing, colors.red)
        screen:output()
        os.sleep(1)
      end
    end, false, startWidth)
    
    screen:output()
    waitForButtonPress(0, 0)
  end
  
  return bet
end

-------------------------
-- BLACKJACK ROUND
-------------------------
local function blackjackRound(screen, bet)
  -- Rebuild and shuffle deck with six decks
  deck = {}
  local i = 1
  for d = 1, 6 do
      for _, suit in ipairs({"heart", "diamond", "club", "spade"}) do
          for _, num in ipairs({"A", "T", "J", "Q", "K"}) do
              deck[i] = num .. suit
              i = i + 1
          end
          for num = 2, 9 do
              deck[i] = tostring(num) .. suit
              i = i + 1
          end
      end
  end
  shuffle(deck)

  local deckIndex = 1
  local playerHands = { { deck[deckIndex], deck[deckIndex+2] } }
  local dealerHand = { deck[deckIndex+1], deck[deckIndex+3] }
  deckIndex = deckIndex + 4

  local userAction = ""
  local hasDoubled = false
  local currentHandIndex = 1

  local function drawHands(hideDealer)
    screen:clear(colors.green)
    
    local function drawPlayerHand(hand, y, hideSecond, active)
        local deltaX = cardBack.width + 2
        if deltaX * #hand > screen.width then
            deltaX = (screen.width - 7) / #hand
        end
        local startX = math.floor((screen.width - (#hand * deltaX)) / 2)
        for idx, card in ipairs(hand) do
            local img = (hideSecond and idx == 2) and cardBack or drawCard(card)
            screen:drawSurface(img, startX, y)
            startX = startX + deltaX
        end
        if active then
            -- Arrow drawn on the right side (using "←") centered vertically
            local arrowX = math.floor(startX + 2)
            local arrowY = y + math.floor(cardBack.height / 2)
            screen:drawText("←", font, arrowX, arrowY, colors.yellow)
        end
    end

    -- Draw dealer hand higher
    drawPlayerHand(dealerHand, 2, hideDealer, false)
    local dealerScoreText = " " .. (hideDealer and "?" or getHandScore(dealerHand))
    screen:drawText(dealerScoreText, font, 1, 1, colors.white)
    
    -- Reserve only bottom 15% for buttons
    local reservedButtons = math.floor(screen.height * 0.15)
    local playerAreaTop = 8      -- moved dealer area up; start player hands lower if needed
    local playerAreaBottom = screen.height - reservedButtons - 2
    local availableHeight = playerAreaBottom - playerAreaTop
    local totalHands = #playerHands
    local spacing = totalHands > 0 and availableHeight / (totalHands + 1) or 0
    
    for i, hand in ipairs(playerHands) do
        local handY = math.floor(playerAreaTop + spacing * i - cardBack.height / 2)
        local active = (i == currentHandIndex)
        drawPlayerHand(hand, handY, false, active)
        local playerScoreText = " " .. getHandScore(hand)
        screen:drawText(playerScoreText, font, 1, handY - 1, colors.white)
    end
    screen:output()
end

  -- Immediate blackjack check
  local function checkImmediateBlackjack()
    local pScore = getHandScore(playerHands[1])
    if pScore == 21 then
      -- Only peek at the dealer's face-up card
      local dealerUpScore = getHandScore({dealerHand[1]})
      if (dealerUpScore == 10 or dealerUpScore == 11) and getHandScore(dealerHand) == 21 then
        return "push"
      else
        return "blackjack"
      end
    elseif getHandScore(dealerHand) == 21 then
      return "dealer blackjack"
    end
    return ""
  end

  -- NEW: Final display helper for game over outcomes.
  local function finalDisplay(playerHand)
    screen:clear(colors.green)
    local function drawHand(hand, y)
      local deltaX = cardBack.width + 2
      if deltaX * #hand > screen.width then
        deltaX = (screen.width - 7) / #hand
      end
      local startX = math.floor((screen.width - (#hand * deltaX)) / 2)
      for _, card in ipairs(hand) do
        local img = drawCard(card)
        screen:drawSurface(img, startX, y)
        startX = startX + deltaX
      end
    end

    local dealerY = 2
    drawHand(dealerHand, dealerY)
    -- Draw dealer score centered vertically relative to dealer hand
    local dealerScore = getHandScore(dealerHand)
    local dealerScoreY = dealerY + math.floor(cardBack.height / 2)
    screen:drawText(tostring(dealerScore), font, 1, dealerScoreY, colors.white)
    
    local playerY = screen.height - cardBack.height - 2
    drawHand(playerHand, playerY)
    -- Draw player hand score centered vertically relative to player hand
    local playerScore = getHandScore(playerHand)
    local playerScoreY = playerY + math.floor(cardBack.height / 2)
    screen:drawText(tostring(playerScore), font, 1, playerScoreY, colors.white)
    
    screen:output()
  end

  -- NEW: Overlay outcome text while keeping the final hands visible.
  local function finalOutcomeDisplay(playerHand, outcome)
    finalDisplay(playerHand)
    -- Calculate center position for the text without clearing the hands.
    local textWidth = surface.getTextSize(outcome, font)
    local centerX = math.floor((screen.width - textWidth) / 2)
    local centerY = math.floor(screen.height / 2)
    screen:drawText(outcome, font, centerX, centerY, colors.yellow)
    screen:output()
    os.sleep(2.2)  -- pause 2 seconds plus extra 0.2 seconds
  end

  local outcome = checkImmediateBlackjack()

  if outcome ~= "" then
      if outcome == "push" then
          outcome = "Push."
          playSound("the_vault:rampage")
      elseif outcome == "blackjack" then
          outcome = "Blackjack!"
          playSound("the_vault:puzzle_completion_major")
      elseif outcome == "dealer blackjack" then
          outcome = "Dealer Blackjack!"
          playSound("the_vault:puzzle_completion_fail")
      end
      finalOutcomeDisplay(playerHands[1], outcome)
      os.sleep(0.2)
      local multiplier = 0
      if outcome == "Blackjack!" then
          multiplier = 1.5
      elseif outcome == "Push." then
          multiplier = 0
      elseif outcome == "Dealer Blackjack!" then
          multiplier = -1
      end
      if multiplier > 0 then
          local pay = math.floor(bet * multiplier)
          dbg("Payout: transferring " .. (bet + pay) .. " silver")
          transferSilver(bank, bankSide, barrel, barrelSide, bet + pay)
      elseif multiplier == 0 then
          dbg("Push: returning bet " .. bet .. " silver")
          transferSilver(bank, bankSide, barrel, barrelSide, bet)
      end
      return
  end

  local function updatePlayerActionButtons()
    local currentHand = playerHands[currentHandIndex]  -- fix for nil error
    buttons = {}
    local centerX = math.round(screen.width / 2)
    local actY = screen.height - 16
    local buttonAreaHeight = 16  -- reserved space for buttons
    -- Clear the button area to remove ghost buttons.
    screen:fillRect(0, actY, screen.width, buttonAreaHeight, colors.green)
    local rowSpacing = 8    -- vertical spacing between rows
    local colSpacing = 4    -- horizontal spacing between buttons
    local buttonRows = {}
    if #currentHand == 2 and not hasDoubled and (getSilverCount(barrel) >= bet) and (getSilverCount(bank) >= bet) then
      buttonRows[1] = {
        { text = "HIT", color = colors.lightBlue, func = function() userAction = "hit"; playSound("create:sanding_short") end },
        { text = "DOUBLE", color = colors.orange, func = function() userAction = "double"; playSound("create:double_down") end }
      }
      buttonRows[2] = {
        { text = "STAND", color = colors.lightBlue, func = function() userAction = "stand" end }
      }
      if #currentHand == 2 and currentHand[1]:sub(1,1) == currentHand[2]:sub(1,1) and (getSilverCount(barrel) >= bet) then
        table.insert(buttonRows[2], { text = "SPLIT", color = colors.yellow, func = function()
            if getSilverCount(barrel) >= bet then
              if transferSilver(barrel, barrelSide, bank, bankSide, bet) then
                table.insert(playerHands, { currentHand[2] })
                currentHand[2] = deck[deckIndex]
                playerHands[#playerHands][2] = deck[deckIndex + 1]
                deckIndex = deckIndex + 2
                playSound("create:split")
              end
            else
              playSound("the_vault:mob_trap")
            end
        end })
      end
    else
      buttonRows[1] = {
        { text = "HIT", color = colors.lightBlue, func = function() userAction = "hit"; playSound("create:sanding_short") end },
        { text = "STAND", color = colors.lightBlue, func = function() userAction = "stand" end }
      }
    end
    layoutButtonGrid(screen, buttonRows, centerX, actY, rowSpacing, colSpacing)
    screen:output()
  end

  local function waitForButtonPressDynamic(ox, oy, updateFunc)
    local timerID = os.startTimer(0.5)
    while true do
      local event, a, b, c = os.pullEvent()
      if event == "timer" and a == timerID then
        updateFunc()
        timerID = os.startTimer(0.5)
      elseif event == "monitor_touch" then
        local side, px, py = a, b, c
        px = px - ox
        py = py - oy
        for _, b in pairs(buttons) do
          if px >= b.x and px <= b.x + b.width - 1 and py >= b.y and py <= b.y + b.height - 1 then
            buttons = {}
            b.cb()
            return
          end
        end
      end
    end
  end

  -- Player turn loop (modified)
  while currentHandIndex <= #playerHands do
    local playerHand = playerHands[currentHandIndex]
    local pScore = getHandScore(playerHand)
    if pScore >= 21 then
      currentHandIndex = currentHandIndex + 1
      hasDoubled = false   -- Reset for next hand
    else
      drawHands(true)
      updatePlayerActionButtons()
      waitForButtonPressDynamic(0, 0, updatePlayerActionButtons)
      if userAction == "hit" or userAction == "double" then
        if userAction == "double" then
          if getSilverCount(barrel) >= bet then
            if transferSilver(barrel, barrelSide, bank, bankSide, bet) then
              bet = bet * 2
              hasDoubled = true
            end
          else
            playSound("the_vault:mob_trap")
            displayCenteredMessage("Insufficient funds!", colors.red)
          end
        end
        playerHand[#playerHand + 1] = deck[deckIndex]
        deckIndex = deckIndex + 1
        -- Added: play card drawn sound and delay for smoother drawing
        playSound("create:sanding_short")
        os.sleep(0.3)
        if userAction == "double" then
          currentHandIndex = currentHandIndex + 1
          hasDoubled = false   -- Reset for next hand after doubling
        end
      elseif userAction == "stand" then
        currentHandIndex = currentHandIndex + 1
        hasDoubled = false     -- Reset for next hand after standing
      end
      userAction = ""
    end
  end

  -- Check if any player hand is not busted
  local allBusted = true
  for _, playerHand in ipairs(playerHands) do
    if getHandScore(playerHand) <= 21 then
      allBusted = false
      break
    end
  end
  
  -- Dealer's turn: draw until score reaches at least 17, but only if player has a non-busted hand
  if not allBusted then
    while getHandScore(dealerHand) < 17 do
      dealerHand[#dealerHand + 1] = deck[deckIndex]
      deckIndex = deckIndex + 1
      -- Added: play card drawn sound for dealer and delay
      playSound("create:sanding_short")
      drawHands(false)
      os.sleep(1)
    end
  end

  -- Determine outcomes for each hand
  local dScore = getHandScore(dealerHand)
  for _, playerHand in ipairs(playerHands) do
    local pScore = getHandScore(playerHand)
    if pScore > 21 then
      outcome = "bust"
    elseif dScore > 21 then
      outcome = "player win"
    elseif dScore == pScore then
      outcome = "push"
    elseif pScore > dScore then
      outcome = "player win"
    else
      outcome = "dealer win"
    end

    if outcome == "push" then
      outcome = "Push."
      playSound("the_vault:rampage")
    elseif outcome == "blackjack" then
      outcome = "Blackjack!"
      playSound("the_vault:puzzle_completion_major")
    elseif outcome == "dealer win" then
      outcome = "Dealer Wins."
      playSound("the_vault:puzzle_completion_fail")
    elseif outcome == "bust" then
      outcome = "Bust!"
      playSound("the_vault:puzzle_completion_fail")
    elseif outcome == "player win" then
      outcome = "You Win!"
      playSound("the_vault:puzzle_completion_major")
    end

    finalOutcomeDisplay(playerHand, outcome)
    
    local multiplier = 0
    if outcome == "You Win!" then
      multiplier = 1
    elseif outcome == "Push." then
      multiplier = 0
    elseif outcome == "Blackjack!" then
      multiplier = 1.5
    else
      multiplier = -1
    end

    if multiplier > 0 then
      local pay = math.floor(bet * multiplier)
      dbg("Payout: transferring " .. (bet + pay) .. " silver")
      transferSilver(bank, bankSide, barrel, barrelSide, bet + pay)
    elseif multiplier == 0 then
      dbg("Push: returning bet " .. bet .. " silver")
      transferSilver(bank, bankSide, barrel, barrelSide, bet)
    end
  end
end

-------------------------
-- MAIN LOOP (Direct to Betting)
-------------------------
setup()
playSound("buildinggadgets:beep")  -- Program Start sound
while true do
  local bet = betSelection(screen)
  if bet > 0 then
    blackjackRound(screen, bet)
  end
end
