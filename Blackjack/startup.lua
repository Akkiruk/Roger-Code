---------------------------------------
-- startup.lua
-- Idle animation until user clicks,
-- then calls blackjack.lua
---------------------------------------

-- Whether to log debug info
local debugEnabled = true

-- We'll log to the computer's native terminal and debug.txt
local debugTerm = term.native()
local function debugLog(msg)
  if debugEnabled then
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " - " .. msg
    debugTerm.write(line .. "\n")
    local f = fs.open("debug.txt", "a")
    f.writeLine(line)
    f.close()
  end
end

debugLog("startup.lua: Initializing idle animation...")

local surface
local monitor
local width, height
local screen
local font
local cardBg, cardBack, logo
local deck
local bouncingCards

-- Simple easing for vertical bounce
local function ease(x)
  local n1 = 7.5625
  local d1 = 2.75
  if x < 1 / d1 then
    return n1 * x * x
  elseif x < 2 / d1 then
    x = x - 1.5 / d1
    return n1 * x * x + 0.75
  elseif x < 2.5 / d1 then
    x = x - 2.25 / d1
    return n1 * x * x + 0.9375
  else
    x = x - 2.625 / d1
    return n1 * x * x + 0.984375
  end
end

-- Draw one frame of the idle animation
local function drawIdleScreen()
  screen:clear(colors.green)
  for i, cardObj in ipairs(bouncingCards) do
    local xPos = cardObj.x
    if cardObj.mirror then
      xPos = (width - cardBack.width) - xPos
    end

    -- Build a card surface
    local cardID = cardObj.card
    local number = cardID:sub(1,1)
    if number == "T" then number = "10" end
    local suit = cardID:sub(2)
    local cardSurf = surface.create(12, 15)
    local suitSurf = surface.load(suit .. ".nfp")
    cardSurf:drawSurface(cardBg, 0, 0)
    cardSurf:drawSurface(suitSurf, 5, 2)
    cardSurf:drawText(number, font, 2, 8, colors.black)

    local y = math.floor((ease(cardObj.x / width))*(height*0.75) + (height*0.25)) - cardBack.height
    screen:drawSurface(cardSurf, math.floor(xPos), y)

    -- Move horizontally
    cardObj.x = cardObj.x + 1
    if cardObj.x > width then
      cardObj.x = -cardBack.width - 5
      cardObj.card = deck[math.random(#deck)]
    end
  end

  screen:drawSurface(logo, 0, 0)
  screen:output()
end

-- Idle loop: draws frames every 0.05s until user clicks
local function idleUntilClick()
  while true do
    drawIdleScreen()
    local timerID = os.startTimer(0.05)
    local event, side, x, y = os.pullEvent()
    if event == "timer" and side == timerID then
      -- next frame
    elseif event == "monitor_touch" then
      debugLog("startup.lua: Monitor clicked, launching blackjack...")
      return
    end
  end
end

-- Set up the idle environment
local function setupIdle()
  local ok, s = pcall(dofile, "surface")
  if not ok then
    debugLog("Error: surface API not found!")
    error("surface API not found!")
  end
  surface = s
  monitor = peripheral.find("monitor")
  if not monitor then
    debugLog("Error: No monitor found!")
    error("No monitor found!")
  end

  monitor.setTextScale(0.5)
  term.redirect(monitor)
  term.setPaletteColor(colors.lightGray, 0xc5c5c5)
  term.setPaletteColor(colors.orange,    0xf15c5c)
  term.setPaletteColor(colors.gray,      0x363636)
  term.setPaletteColor(colors.green,     0x044906)

  width, height = term.getSize()
  screen = surface.create(width, height)
  font = surface.loadFont(surface.load("font"))
  cardBg = surface.load("card.nfp")       or error("card.nfp missing")
  cardBack = surface.load("cardback.nfp") or error("cardback.nfp missing")
  logo = surface.load("logo.nfp")         or error("logo.nfp missing")

  -- Build a simple deck (for random card visuals)
  deck = {}
  local i = 1
  for _, suit in ipairs({"heart","diamond","club","spade"}) do
    for _, num in ipairs({"A","T","J","Q","K"}) do
      deck[i] = num .. suit
      i = i + 1
    end
    for n=2,9 do
      deck[i] = tostring(n) .. suit
      i = i + 1
    end
  end
  -- Shuffle
  for n = #deck,2,-1 do
    local j = math.random(n)
    deck[n], deck[j] = deck[j], deck[n]
  end

  -- Create 4 bouncing cards
  bouncingCards = {}
  for j=1,4 do
    bouncingCards[j] = {
      x      = -math.floor(math.random()*width*2),
      mirror = (math.random()>0.5),
      card   = deck[j]
    }
  end
end

-- Main
setupIdle()
debugLog("startup.lua: Idle setup complete. Entering idle loop...")

while true do
  idleUntilClick()
  -- Run blackjack, then come back here
  shell.run("blackjack.lua")
  debugLog("startup.lua: blackjack.lua finished, returning to idle.")
end
