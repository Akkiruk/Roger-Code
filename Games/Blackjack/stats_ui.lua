-- stats_ui.lua
-- Statistics UI screens for Blackjack: achievement browser, player stats,
-- leaderboard, and the main statistics menu.
-- Extracted from statistics.lua.  Does NOT override term.write.

local uiLib       = require("lib.ui")
local pStats      = require("lib.player_stats")
local achLib      = require("lib.achievements")
local playerDet   = require("lib.player_detection")

local ACHIEVEMENTS = achLib.ACHIEVEMENTS

-----------------------------------------------------
-- UI helper delegates (same signatures as the old locals)
-----------------------------------------------------
local function safeWrite(text, textColor)
  local x, y = term.getCursorPos()
  uiLib.blitWrite(x, y, text, textColor)
  term.setCursorPos(x + #text, y)
end

local drawCenteredText = uiLib.drawCenteredText
local drawBox          = uiLib.drawBox
local drawButton       = uiLib.drawTermButton
local wrapText         = uiLib.wrapText

local function writeWithBg(x, y, text, textColor, bgColor)
  uiLib.blitWrite(x, y, text, textColor, bgColor)
  term.setCursorPos(x + #text, y)
  return { x = x, y = y, text = text }
end

-----------------------------------------------------
-- Player detection (quiet, no logging)
-----------------------------------------------------
local getActivePlayer = playerDet.getActive

-----------------------------------------------------
-- Shared nav helper for simple paged screens
-- Returns new page number or nil (back)
-----------------------------------------------------
local function drawNavAndWait(page, maxPage)
  local w, h = term.getSize()
  local navY = h - 3
  if page > 1 then drawButton(3, navY, 10, "< PREV", false) end
  if page < maxPage then drawButton(w - 13, navY, 10, "NEXT >", false) end
  drawButton(math.floor(w / 2) - 5, navY, 10, "BACK", false)

  local ev, btn, ex, ey = os.pullEvent()
  if ev == "monitor_touch" then
    if page > 1 and ex >= 3 and ex <= 13 and ey == navY then return page - 1
    elseif page < maxPage and ex >= (w - 13) and ex <= (w - 3) and ey == navY then return page + 1
    elseif ex >= (math.floor(w / 2) - 5) and ex <= (math.floor(w / 2) + 5) and ey == navY then return nil end
  elseif ev == "key" then
    if btn == keys.left and page > 1 then return page - 1
    elseif btn == keys.right and page < maxPage then return page + 1
    elseif btn == keys.q or btn == keys.escape then return nil end
  end
  return page
end

-----------------------------------------------------
-- Achievement Browser
-----------------------------------------------------
local function showAchievementsBrowser()
  local currentPage = 1
  local achievementsPerPage = 10
  local currentCategory = nil

  -- Pre-compute stats reference (refreshed each loop iteration)
  local playerName = getActivePlayer()
  local stats = nil
  if playerName then stats = pStats.loadPlayerStats(playerName) end

  local sortOptions = {
    { id = "category", name = "Category", sortFunc = function(a, b)
        if a.category and b.category then
          if a.category.id == b.category.id then return a._index < b._index end
          return a.category.id < b.category.id
        elseif a.category then return true
        elseif b.category then return false
        else return a._index < b._index end
      end },
    { id = "default", name = "Default", sortFunc = function(a, b) return a._index < b._index end },
    { id = "name",    name = "A-Z",     sortFunc = function(a, b) return a.name < b.name end },
    { id = "status",  name = "Status",  sortFunc = function(a, b)
        local aU = (stats and stats.achievements and stats.achievements[a.id]) and 1 or 0
        local bU = (stats and stats.achievements and stats.achievements[b.id]) and 1 or 0
        if aU ~= bU then return aU > bU end
        return a._index < b._index
      end },
  }
  local currentSort = 1

  -- Deep copy with index
  local sortedAchievements = {}
  for i, ach in ipairs(ACHIEVEMENTS) do
    local copy = {}
    for k, v in pairs(ach) do copy[k] = v end
    copy._index = i
    table.insert(sortedAchievements, copy)
  end

  -- Unique categories
  local categories, catExists = {}, {}
  for _, ach in ipairs(ACHIEVEMENTS) do
    if ach.category and not catExists[ach.category.id] then
      table.insert(categories, ach.category)
      catExists[ach.category.id] = true
    end
  end
  table.sort(categories, function(a, b) return a.name < b.name end)

  -- Helper: count unlocked in a category (or all)
  local function countUnlocked(cat)
    local total, unlocked = 0, 0
    for _, ach in ipairs(ACHIEVEMENTS) do
      if not cat or (ach.category and ach.category.id == cat.id) then
        total = total + 1
        if stats and stats.achievements and stats.achievements[ach.id] then
          unlocked = unlocked + 1
        end
      end
    end
    return unlocked, total
  end

  local needsSort = true
  while true do
    -- Refresh stats each loop
    playerName = getActivePlayer()
    if playerName then stats = pStats.loadPlayerStats(playerName) end

    -- Sort only when sort option changes
    if needsSort then
      table.sort(sortedAchievements, sortOptions[currentSort].sortFunc)
      needsSort = false
    end

    -- Filter
    local display = {}
    for _, ach in ipairs(sortedAchievements) do
      if not currentCategory or (ach.category and ach.category.id == currentCategory.id) then
        table.insert(display, ach)
      end
    end

    local totalPages = math.max(1, math.ceil(#display / achievementsPerPage))
    if currentPage > totalPages then currentPage = totalPages end

    term.setBackgroundColor(colors.black)
    term.clear()

    local w, h = term.getSize()

    -- Title + progress summary
    local uAll, tAll = countUnlocked(nil)
    local pctAll = tAll > 0 and math.floor((uAll / tAll) * 100) or 0
    drawCenteredText("ACHIEVEMENTS", 2, colors.yellow)

    if playerName then
      local summary = playerName .. " - " .. uAll .. "/" .. tAll .. " (" .. pctAll .. "%)"
      drawCenteredText(summary, 3, colors.lime)
    else
      drawCenteredText("No player detected", 3, colors.red)
    end

    -- Visual progress bar (row 4)
    local barX1 = 3
    local barX2 = w - 4
    local barW = barX2 - barX1 + 1
    local filledW = tAll > 0 and math.floor((uAll / tAll) * barW) or 0
    if filledW > 0 then
      drawBox(barX1, 4, barX1 + filledW - 1, 4, colors.lime)
    end
    if filledW < barW then
      drawBox(barX1 + filledW, 4, barX2, 4, colors.gray)
    end

    -- Sort buttons (row 5)
    local sortY = 5
    local sortButtons = {}
    local availWidth = w - 6
    local bSpacing = 2
    local totalBtnW, btnCount = 0, 0
    for _, opt in ipairs(sortOptions) do
      local bw = #opt.name + 4
      if totalBtnW + bw + bSpacing <= availWidth + bSpacing then
        totalBtnW = totalBtnW + bw + bSpacing
        btnCount = btnCount + 1
      else break end
    end
    local sx = math.floor((w - totalBtnW + bSpacing) / 2)
    for i = 1, btnCount do
      local opt = sortOptions[i]
      local bw = #opt.name + 4
      sortButtons[i] = drawButton(sx, sortY, bw, opt.name, i == currentSort)
      sx = sx + bw + bSpacing
    end

    -- Category filter (row 7+)
    local catY = sortY + 2
    local categoryButtons = {}

    local cx = 3
    local uCatAll, tCatAll = countUnlocked(nil)
    local allLabel = "All " .. uCatAll .. "/" .. tCatAll
    local allBtn = drawButton(cx, catY, #allLabel + 4, allLabel, currentCategory == nil)
    table.insert(categoryButtons, { btn = allBtn, category = nil })
    cx = cx + #allLabel + 6

    local maxRowW = w - 3
    local curRowW = cx
    local curRowY = catY
    local maxRows = 4
    local rowCnt = 1

    for _, cat in ipairs(categories) do
      local uC, tC = countUnlocked(cat)
      local label = cat.name .. " " .. uC .. "/" .. tC
      local bw = #label + 4
      if curRowW + bw > maxRowW and rowCnt < maxRows then
        curRowY = curRowY + 1
        curRowW = 3; cx = 3
        rowCnt = rowCnt + 1
      end
      if rowCnt <= maxRows then
        local isSelected = currentCategory and currentCategory.id == cat.id
        local btn = drawButton(cx, curRowY, bw, label, isSelected)
        table.insert(categoryButtons, { btn = btn, category = cat })
        cx = cx + bw + 2
        curRowW = curRowW + bw + 2
      end
    end

    -- Category description / progress under filters
    local descY = curRowY + 2
    if currentCategory then
      term.setTextColor(currentCategory.color or colors.white)
      term.setCursorPos(3, descY)
      term.write(currentCategory.description or "")
    end

    -- Achievement list
    local achY = descY + 1
    local startIdx = (currentPage - 1) * achievementsPerPage + 1
    local endIdx   = math.min(startIdx + achievementsPerPage - 1, #display)

    -- Calculate how many fit before nav area
    local navReserve = 4
    local maxAchY = h - navReserve
    local cardHeight = 3

    if #display == 0 then
      term.setCursorPos(5, achY + 2)
      term.setTextColor(colors.red)
      term.write("No achievements match the current filter.")
    else
      for idx = startIdx, endIdx do
        if achY + cardHeight - 1 > maxAchY then break end
        local ach = display[idx]
        local unlocked = stats and stats.achievements and stats.achievements[ach.id]
        local unlockDay = unlocked and stats.achievements[ach.id]

        -- Card color: category color for unlocked, dark gray for locked
        local catColor = ach.category and ach.category.color or colors.green
        local boxClr = unlocked and catColor or colors.gray

        drawBox(3, achY, w - 4, achY + cardHeight - 1, boxClr)

        -- Row 1: status icon + name + category badge
        local namePrefix = unlocked and "[OK] " or "[ ] "
        local nameText = namePrefix .. ach.name
        local nameColor = unlocked and colors.black or colors.white
        writeWithBg(4, achY, nameText, nameColor, boxClr)

        if ach.category and not currentCategory then
          local badge = "[" .. ach.category.name .. "]"
          local maxBW = w - 10 - #nameText
          if #badge > maxBW then badge = "[" .. ach.category.name:sub(1, math.max(3, maxBW - 5)) .. "..]" end
          if #badge > 3 then
            writeWithBg(w - 4 - #badge, achY, badge, nameColor, boxClr)
          end
        end

        -- Row 2: description
        local dl = wrapText(ach.description, w - 10)
        writeWithBg(5, achY + 1, dl[1] or "",
                    unlocked and colors.black or colors.lightGray, boxClr)

        -- Row 3: unlock status or locked hint
        if unlocked and unlockDay then
          local dd = os.day() - unlockDay
          local ut = dd == 0 and "Unlocked today!" or
                     dd == 1 and "Unlocked yesterday" or
                     "Unlocked " .. dd .. " days ago"
          writeWithBg(5, achY + 2, ut, colors.black, boxClr)
        else
          writeWithBg(5, achY + 2, "Locked", colors.lightGray, boxClr)
        end

        achY = achY + cardHeight + 1
      end
    end

    -- Page indicator + nav buttons
    local navY = h - 2
    local pageText = "Page " .. currentPage .. "/" .. totalPages
          .. " (" .. #display .. " achievements)"
    term.setCursorPos(math.floor((w - #pageText) / 2), navY - 1)
    term.setTextColor(colors.lightGray)
    term.write(pageText)

    -- Nav buttons on navY
    local btnTotalW = 0
    if currentPage > 1    then btnTotalW = btnTotalW + 12 end
    if currentPage < totalPages then btnTotalW = btnTotalW + 12 end
    btnTotalW = btnTotalW + 12 + 12
    local btnStartX = math.floor((w - btnTotalW) / 2)
    local curX = btnStartX

    if currentPage > 1 then
      drawButton(curX, navY, 10, "< PREV", false)
      curX = curX + 12
    end
    local nextBtnX = curX
    if currentPage < totalPages then
      drawButton(curX, navY, 10, "NEXT >", false)
      curX = curX + 12
    end
    local backBtnX = curX
    drawButton(backBtnX, navY, 10, "BACK", false)
    curX = curX + 12
    local statsBtnX = curX
    drawButton(statsBtnX, navY, 10, "STATS", false)

    -- Input
    local event, button, ex, ey = os.pullEvent()
    if event == "monitor_touch" then
      for i, btn in ipairs(sortButtons) do
        if ex >= btn.x1 and ex <= btn.x2 and ey >= btn.y1 and ey <= btn.y2 then
          if currentSort ~= i then currentSort = i; currentPage = 1; needsSort = true end
        end
      end
      for _, cb in ipairs(categoryButtons) do
        if ex >= cb.btn.x1 and ex <= cb.btn.x2 and ey >= cb.btn.y1 and ey <= cb.btn.y2 then
          if currentCategory ~= cb.category then currentCategory = cb.category; currentPage = 1 end
        end
      end
      if currentPage > 1 and ex >= btnStartX and ex <= btnStartX + 10 and ey == navY then
        currentPage = currentPage - 1
      end
      if currentPage < totalPages and ex >= nextBtnX and ex <= nextBtnX + 10 and ey == navY then
        currentPage = currentPage + 1
      end
      if ex >= backBtnX and ex <= backBtnX + 10 and ey == navY then return "back" end
      if ex >= statsBtnX and ex <= statsBtnX + 10 and ey == navY then return "stats" end
    elseif event == "key" then
      if button == keys.up then
        if currentCategory == nil then
          currentCategory = categories[1]
        else
          local found = false
          for i = #categories, 1, -1 do
            if found then currentCategory = categories[i]; found = false; break
            elseif categories[i].id == currentCategory.id then found = true end
          end
          if found then currentCategory = nil end
        end
        currentPage = 1
      elseif button == keys.down then
        if currentCategory == nil then
          currentCategory = categories[1]
        else
          local found = false
          for i = 1, #categories do
            if found then currentCategory = categories[i]; found = false; break
            elseif categories[i].id == currentCategory.id then found = true end
          end
          if found then currentCategory = nil end
        end
        currentPage = 1
      elseif button == keys.s then return "stats"
      elseif button == keys.q or button == keys.escape then return "back"
      elseif button == keys.left  and currentPage > 1         then currentPage = currentPage - 1
      elseif button == keys.right and currentPage < totalPages then currentPage = currentPage + 1
      end
    end
  end
end

-----------------------------------------------------
-- Player Stats Screen
-----------------------------------------------------
local function showPlayerStats()
  local playerName = getActivePlayer()
  if not playerName then
    term.setBackgroundColor(colors.black); term.clear()
    drawCenteredText("No player detected", 10, colors.red)
    drawCenteredText("Please stand closer to the machine", 12, colors.yellow)
    drawCenteredText("Press any key to continue", 14, colors.white)
    os.pullEvent("key")
    return
  end

  local stats = pStats.loadPlayerStats(playerName)
  if not stats then
    term.setBackgroundColor(colors.black); term.clear()
    drawCenteredText("No stats found for " .. playerName, 10, colors.yellow)
    drawCenteredText("Play some blackjack to start tracking!", 12, colors.white)
    drawCenteredText("Press any key to continue", 14, colors.white)
    os.pullEvent("key")
    return
  end

  local page = 1
  local maxPage = 3

  while true do
    term.setBackgroundColor(colors.black); term.clear()
    local w, h = term.getSize()
    drawCenteredText(playerName .. "'s Statistics", 2, colors.yellow)
    drawCenteredText("Page " .. page .. " of " .. maxPage, 3, colors.lightGray)

    if page == 1 then
      local col1X = 3
      local col2X = math.floor(w / 2) + 3
      local y = 5
      local lh = 2

      term.setCursorPos(col1X, y); safeWrite("Games played: " .. (stats.gamesPlayed or 0), colors.white); y = y + lh
      term.setCursorPos(col1X, y); safeWrite("Wins: " .. (stats.wins or 0), colors.green); y = y + lh
      term.setCursorPos(col1X, y); safeWrite("Losses: " .. (stats.losses or 0), colors.red); y = y + lh
      term.setCursorPos(col1X, y); safeWrite("Pushes: " .. (stats.pushes or 0), colors.lightGray); y = y + lh
      term.setCursorPos(col1X, y); safeWrite("Blackjacks: " .. (stats.blackjacks or 0), colors.yellow); y = y + lh
      term.setCursorPos(col1X, y); safeWrite("Busts: " .. (stats.busts or 0), colors.orange); y = y + lh

      local wr = (stats.gamesPlayed or 0) > 0 and math.floor(((stats.wins or 0) / stats.gamesPlayed) * 100) or 0
      term.setCursorPos(col1X, y); safeWrite("Win rate: " .. wr .. "%", colors.cyan)

      y = 5
      local bwG  = math.floor((stats.biggestWin or 0) / 9)
      local bbG  = math.floor((stats.biggestBet or 0) / 9)
      local twG  = math.floor((stats.totalBet or 0) / 9)
      local tWnG = math.floor((stats.totalWinnings or 0) / 9)
      local tLG  = math.floor((stats.totalLosses or 0) / 9)
      local np   = (stats.totalWinnings or 0) - (stats.totalLosses or 0)
      local npG  = math.floor(np / 9)

      term.setCursorPos(col2X, y); safeWrite("Biggest win: " .. bwG .. " gold", colors.green); y = y + lh
      term.setCursorPos(col2X, y); safeWrite("Biggest bet: " .. bbG .. " gold", colors.white); y = y + lh
      term.setCursorPos(col2X, y); safeWrite("Total wagered: " .. twG .. " gold", colors.gray); y = y + lh
      term.setCursorPos(col2X, y); safeWrite("Total won: " .. tWnG .. " gold", colors.green); y = y + lh
      term.setCursorPos(col2X, y); safeWrite("Total lost: " .. tLG .. " gold", colors.red); y = y + lh
      term.setCursorPos(col2X, y); safeWrite("Net profit: " .. (np >= 0 and "+" or "") .. npG .. " gold",
                                              np >= 0 and colors.green or colors.red); y = y + lh
      if stats.averageBet then
        term.setCursorPos(col2X, y); safeWrite("Average bet: " .. math.floor(stats.averageBet / 9) .. " gold", colors.cyan)
      end

    elseif page == 2 then
      local y, lh = 5, 2
      term.setCursorPos(3, y); safeWrite("Current win streak: " .. (stats.winStreak or 0), colors.green); y = y + lh
      term.setCursorPos(3, y); safeWrite("Current lose streak: " .. (stats.loseStreak or 0), colors.red); y = y + lh

      local ac = 0
      for _ in pairs(stats.achievements or {}) do ac = ac + 1 end
      term.setCursorPos(3, y); safeWrite("Achievements: " .. ac .. "/" .. #ACHIEVEMENTS, colors.magenta); y = y + lh
      term.setCursorPos(3, y); safeWrite("Session hands: " .. (stats.sessionHandsPlayed or 0), colors.cyan); y = y + lh
      term.setCursorPos(3, y); safeWrite("Session blackjacks: " .. (stats.sessionBlackjacks or 0), colors.yellow); y = y + lh

      if stats.softHandWins then
        term.setCursorPos(3, y); safeWrite("Soft hand wins: " .. stats.softHandWins, colors.lightBlue); y = y + lh
      end
      if stats.dealerBustWins then
        term.setCursorPos(3, y); safeWrite("Dealer bust wins: " .. stats.dealerBustWins, colors.lime); y = y + lh
      end
      if stats.tripleHitSuccess then
        term.setCursorPos(3, y); safeWrite("Triple hit successes: " .. stats.tripleHitSuccess, colors.orange); y = y + lh
      end
      if stats.splitCount and stats.splitCount > 0 then
        term.setCursorPos(3, y); safeWrite("Splits: " .. stats.splitCount, colors.yellow); y = y + lh
      end

      if stats.lastUpdated then
        local td = os.epoch("local") - stats.lastUpdated
        local msg = "Last played: "
        if td < 60000 then msg = msg .. "Just now"
        elseif td < 3600000 then msg = msg .. math.floor(td / 60000) .. " minutes ago"
        elseif td < 86400000 then msg = msg .. math.floor(td / 3600000) .. " hours ago"
        else msg = msg .. math.floor(td / 86400000) .. " days ago" end
        term.setCursorPos(3, h - 5); safeWrite(msg, colors.lightGray)
      end

    elseif page == 3 then
      local y, lh = 5, 2
      drawCenteredText("Action Breakdown", y, colors.yellow); y = y + lh

      local act = stats.actions or {}
      local hitT  = act.hit    and act.hit.total    or 0
      local stdT  = act.stand  and act.stand.total  or 0
      local dblT  = act.double and act.double.total or 0
      local splT  = act.split  and act.split.total  or 0
      local total = hitT + stdT + dblT + splT

      if total > 0 then
        local pct = function(n) return math.floor((n / total) * 100) end
        term.setCursorPos(3, y); safeWrite("Hit: " .. hitT .. " (" .. pct(hitT) .. "%)", colors.lightBlue); y = y + lh
        term.setCursorPos(3, y); safeWrite("Stand: " .. stdT .. " (" .. pct(stdT) .. "%)", colors.lightBlue); y = y + lh
        term.setCursorPos(3, y); safeWrite("Double: " .. dblT .. " (" .. pct(dblT) .. "%)", colors.orange); y = y + lh
        term.setCursorPos(3, y); safeWrite("Split: " .. splT .. " (" .. pct(splT) .. "%)", colors.yellow); y = y + lh * 2
      else
        term.setCursorPos(3, y); safeWrite("No detailed action data available yet", colors.lightGray); y = y + lh * 2
      end

      drawCenteredText("Card Value Win Rates", y, colors.yellow); y = y + lh
      if act.stand and act.stand.outcomes then
        for _, val in ipairs({17, 18, 19, 20}) do
          local o = act.stand.outcomes[val]
          if o then
            local t = (o.win or 0) + (o.loss or 0) + (o.push or 0)
            if t > 0 then
              local wr = math.floor(((o.win or 0) / t) * 100)
              local clr = wr >= 70 and colors.lime or (wr >= 40 and colors.yellow or colors.red)
              term.setCursorPos(3, y); safeWrite("Standing on " .. val .. ": " .. wr .. "% win rate", clr); y = y + lh
            end
          end
        end
      end
    end

    local result = drawNavAndWait(page, maxPage)
    if result == nil then return end
    page = result
  end
end

-----------------------------------------------------
-- Leaderboard Screen
-----------------------------------------------------
local function showLeaderboard()
  local lb = pStats.loadLeaderboard()
  if not lb or not lb.topWins then
    lb = { lastUpdated = os.epoch("local"), topWins = {}, topProfit = {}, topBets = {}, topBlackjacks = {} }
    pStats.saveLeaderboard(lb)
  end

  local page = 1
  local maxPage = 4

  while true do
    term.setBackgroundColor(colors.black); term.clear()
    local w, h = term.getSize()
    drawCenteredText("BLACKJACK LEADERBOARD", 2, colors.yellow)
    drawCenteredText("Page " .. page .. " of " .. maxPage, 3, colors.lightGray)

    local entries, title
    if page == 1 then title = "Top Winners";      entries = lb.topWins or {}
    elseif page == 2 then title = "Highest Profit";   entries = lb.topProfit or {}
    elseif page == 3 then title = "Biggest Bets";     entries = lb.topBets or {}
    else                   title = "Most Blackjacks";  entries = lb.topBlackjacks or {} end

    drawCenteredText(title, 5, colors.cyan)

    local sortKey = ({ "wins", "netProfit", "biggestBet", "blackjacks" })[page]
    table.sort(entries, function(a, b) return (a[sortKey] or 0) > (b[sortKey] or 0) end)

    local startY = 7
    local lh = 2
    if #entries == 0 then
      term.setCursorPos(3, startY); safeWrite("No entries yet. Play more blackjack!", colors.lightGray)
    else
      for i = 1, math.min(10, #entries) do
        local e = entries[i]
        local y = startY + (i - 1) * lh
        term.setCursorPos(3, y); safeWrite("#" .. i, i <= 3 and colors.yellow or colors.white)
        term.setCursorPos(7, y); safeWrite(e.player or "Unknown", colors.lime)
        term.setCursorPos(w - 15, y)
        if page == 1 then     safeWrite("Wins: " .. (e.wins or 0), colors.white)
        elseif page == 2 then safeWrite("Profit: " .. math.floor((e.netProfit or 0) / 9) .. " gold", colors.white)
        elseif page == 3 then safeWrite("Bet: " .. math.floor((e.biggestBet or 0) / 9) .. " gold", colors.white)
        else                  safeWrite("Blackjacks: " .. (e.blackjacks or 0), colors.white) end
      end
    end

    if lb.lastUpdated then
      local td = os.epoch("local") - lb.lastUpdated
      local msg = "Last updated: "
      if td < 60000 then msg = msg .. "Just now"
      elseif td < 3600000 then msg = msg .. math.floor(td / 60000) .. " minutes ago"
      elseif td < 86400000 then msg = msg .. math.floor(td / 3600000) .. " hours ago"
      else msg = msg .. math.floor(td / 86400000) .. " days ago" end
      term.setCursorPos(3, h - 5); safeWrite(msg, colors.lightGray)
    end

    local result = drawNavAndWait(page, maxPage)
    if result == nil then return end
    page = result
  end
end

-----------------------------------------------------
-- Statistics Menu
-----------------------------------------------------
local function showStatisticsMenu()
  local playerName = getActivePlayer()
  if playerName then
    local stats = pStats.loadPlayerStats(playerName)
    if stats then pStats.updateLeaderboard(playerName, stats) end
  end

  while true do
    term.setBackgroundColor(colors.black); term.clear()
    local w, h = term.getSize()
    drawCenteredText("BLACKJACK STATISTICS", 3, colors.yellow)

    if playerName then
      drawCenteredText("Player: " .. playerName, 5, colors.lime)
    else
      drawCenteredText("No player detected", 5, colors.red)
    end

    local cx = math.floor(w / 2)
    local by = 8
    local bh = 3
    local sp = 3

    -- Player Stats button
    drawBox(cx - 13, by, cx + 13, by + bh, colors.blue)
    local t1 = "Player Stats"
    term.setCursorPos(cx - math.floor(#t1 / 2), by + 1)
    term.blit(t1, string.rep(colors.toBlit(colors.white), #t1),
                  string.rep(colors.toBlit(colors.blue), #t1))

    -- Leaderboard button
    local ly = by + bh + sp
    drawBox(cx - 13, ly, cx + 13, ly + bh, colors.purple)
    local t2 = "Leaderboard"
    term.setCursorPos(cx - math.floor(#t2 / 2), ly + 1)
    term.blit(t2, string.rep(colors.toBlit(colors.white), #t2),
                  string.rep(colors.toBlit(colors.purple), #t2))

    -- Achievements button
    local ay = ly + bh + sp
    drawBox(cx - 13, ay, cx + 13, ay + bh, colors.green)
    local t3 = "Achievements"
    term.setCursorPos(cx - math.floor(#t3 / 2), ay + 1)
    term.blit(t3, string.rep(colors.toBlit(colors.white), #t3),
                  string.rep(colors.toBlit(colors.green), #t3))

    -- Back button
    drawBox(cx - 10, h - 5, cx + 10, h - 3, colors.red)
    local t4 = "BACK"
    term.setCursorPos(cx - math.floor(#t4 / 2), h - 4)
    term.blit(t4, string.rep(colors.toBlit(colors.white), #t4),
                  string.rep(colors.toBlit(colors.red), #t4))

    local ev, btn, ex, ey = os.pullEvent()
    if ev == "monitor_touch" then
      if ex >= cx - 13 and ex <= cx + 13 then
        if ey >= by and ey <= by + bh then showPlayerStats()
        elseif ey >= ly and ey <= ly + bh then showLeaderboard()
        elseif ey >= ay and ey <= ay + bh then
          local result = showAchievementsBrowser()
          if result == "stats" then showPlayerStats() end
        end
      end
      if ex >= cx - 10 and ex <= cx + 10 and ey >= h - 5 and ey <= h - 3 then return end
    elseif ev == "key" then
      if btn == keys.s then showPlayerStats()
      elseif btn == keys.l then showLeaderboard()
      elseif btn == keys.a then
        local result = showAchievementsBrowser()
        if result == "stats" then showPlayerStats() end
      elseif btn == keys.q or btn == keys.escape then return end
    end
  end
end

return {
  showAchievementsBrowser = showAchievementsBrowser,
  showPlayerStats         = showPlayerStats,
  showLeaderboard         = showLeaderboard,
  showStatisticsMenu      = showStatisticsMenu,
}
