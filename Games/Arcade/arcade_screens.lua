-- arcade_screens.lua
-- The screens every game shares: lobby, results, stats, settings and the scoreboard monitor.
-- A game only supplies words and its own settings, through its plugin.

local hw = require("arcade_hw")
local Records = require("arcade_records")
local ui = require("arcade_ui")

local M = {}
local C = ui.C
local floor, max = math.floor, math.max

local app, S, env

function M.bind(appTable)
  app, S, env = appTable, appTable.S, appTable.env
end

local function fmtDuration(sec)
  sec = floor(sec or 0)
  if sec >= 3600 then return string.format("%dh%02dm", floor(sec / 3600), floor(sec % 3600 / 60)) end
  return string.format("%d:%02d", floor(sec / 60), sec % 60)
end
M.fmtDuration = fmtDuration

local function signed(n)
  if n > 0 then return "+" .. n end
  return tostring(n)
end
M.signed = signed

local function nowMs() return os.epoch("local") end

local function background()
  ui.screen():clear(C.bg, nil, " ")
end

-- ------------------------------------------------------------------ lobby

local function drawLobby()
  background()
  ui.clearButtons()
  local W, H = env.W, env.H
  local l = S.lobby
  -- a short wall (5 blocks high) gets the same screen with tighter rows
  local compact = H < 78
  local titleY, slotY, slotH, nameDy, subDy = 1, 10, 15, 5, 13
  local listY, rowH, rowGap, utilGap = 27, 9, 10, 10
  if compact then
    titleY, slotY, slotH, nameDy, subDy = 0, 8, 12, 3, 10
    listY, rowH, rowGap, utilGap = 21, 7, 8, 8
  end
  ui.text("WHO IS PLAYING?", floor(W / 2), titleY, C.text, "center")

  -- the two colour slots
  local sw = floor((W - 8) / 2)
  local function slotPanel(num, x)
    local slot = num == 1 and l.red or l.blue
    local color = num == 1 and C.red or C.blue
    local key = num == 1 and "red" or "blue"
    local y = slotY
    ui.fill(x, y, sw, slotH, C.panel)
    ui.fill(x, y, 3, slotH, color)
    if l.picking == key then ui.frame(x, y, sw, slotH, C.hi, 1) end
    ui.small(app.plugin.view.seatLabels[num], x + 5, y + 1, color, C.panel, "left")
    if slot then
      ui.name(slot.name, x + 5, y + nameDy, sw - 8, C.text, "left", C.panel)
      local sub = slot.cpu and "COMPUTER" or (slot.guest and "GUEST - UNRANKED" or nil)
      if not sub then
        local p = app.store:get(slot.name)
        sub = p and string.format("%d ELO  W%d L%d D%d", p.elo, p.wins, p.losses, p.draws) or "NEW PLAYER"
      end
      ui.small(sub, x + 5, y + subDy, C.line, C.panel, "left", sw - 7)
    else
      ui.small(l.picking == key and "Tap your name below" or "Waiting...", x + 5, y + nameDy + 2, l.picking == key and C.hi or C.line, C.panel, "left", sw - 7)
    end
  end
  ui.region("redSlot", 4, slotY, sw, slotH)
  ui.region("blueSlot", 4 + sw, slotY, sw, slotH)
  slotPanel(1, 4)
  slotPanel(2, 4 + sw)
  ui.button("back", 2, compact and 0 or 1, 16, compact and 6 or 7, "BACK", C.panel, { small = true })

  -- nearby players
  local near, ok = hw.nearby()
  local label
  if ok or #near > 0 then label = "NEARBY PLAYERS (" .. #near .. ")" else label = "NO PLAYER DETECTED - USE GUEST OR COMPUTER" end
  ui.small(label, 4, listY, C.hi, C.bg, "left")
  local cols = 3
  local bw = floor((W - 8 - (cols - 1) * 2) / cols)
  local perPage = 6
  local pages = max(1, math.ceil(#near / perPage))
  if l.page > pages then l.page = pages end
  local first = (l.page - 1) * perPage
  for i = 1, perPage do
    local name = near[first + i]
    local col = (i - 1) % cols
    local row = floor((i - 1) / cols)
    local x = 4 + col * (bw + 2)
    local y = listY + 2 + row * rowGap
    if name then
      local taken = (l.red and l.red.name == name and not l.red.cpu) or (l.blue and l.blue.name == name and not l.blue.cpu)
      local p = app.store:get(name)
      local label2 = name .. (p and (" " .. p.elo) or "")
      local color = C.panel
      if l.red and l.red.name == name then color = C.redTint elseif l.blue and l.blue.name == name then color = C.blueTint end
      ui.button("player", x, y, bw, rowH, label2, color, { small = true, data = name, fg = taken and C.text or C.text })
    else
      ui.fill(x, y, bw, rowH, C.bg)
      ui.frame(x, y, bw, rowH, C.panel, 1)
    end
  end
  if pages > 1 then
    ui.button("page", W - 22, listY - 1, 18, 7, "MORE " .. l.page .. "/" .. pages, C.panel, { small = true })
  end

  -- computer opponents
  local cpuY = listY + 2 + 2 * rowGap + 1
  for i, level in ipairs(app.plugin.cpuLevels) do
    if i <= cols then
      ui.button("cpu", 4 + (i - 1) * (bw + 2), cpuY, bw, rowH, "CPU " .. string.upper(level), C.panel, { small = true, data = level })
    end
  end

  -- utilities
  local utilY = cpuY + utilGap
  ui.button("guest", 4, utilY, bw, rowH, "GUEST", C.panel, { small = true })
  ui.button("swap", 4 + (bw + 2), utilY, bw, rowH, "SWAP COLORS", C.panel, { small = true })
  ui.button("stats", 4 + 2 * (bw + 2), utilY, bw, rowH, "STATS", C.panel, { small = true })

  -- options line and start
  local startY = utilY + utilGap + (compact and 0 or 1)
  local firstText = l.first == "random" and "RANDOM" or (l.first == "blue" and "BLUE" or "RED")
  local info = firstText .. " FIRST  /  " .. app.plugin.optionsLine(app.store)
  local half = floor((W - 8) * 0.55)
  ui.button("options", 4, startY, half, rowH, info, C.panel, { small = true })
  local ready = l.red ~= nil and l.blue ~= nil
  ui.button("start", 4 + half + 2, startY, W - 8 - half - 2, rowH, ready and "START" or "PICK 2", ready and C.ok or C.panel, { small = true, enabled = ready })
  app.drawToast()
end

-- ------------------------------------------------------------------ results

local function drawResult()
  background()
  ui.clearButtons()
  local r = S.result
  local W, H = env.W, env.H
  local winnerColor = r.winner == 1 and C.red or (r.winner == 2 and C.blue or C.hi)
  local title
  if r.winner == 3 then
    title = "DRAW"
  else
    local w = r.winner == 1 and r.red or r.blue
    title = w.name .. " WINS!"
  end
  local howY = 11
  if ui.textWidth(title) > W - 4 then
    ui.text("WINNER", floor(W / 2), 1, winnerColor, "center")
    ui.small(r.winner == 1 and r.red.name or r.blue.name, floor(W / 2), 9, C.text, C.bg, "center")
    howY = 12
  else
    ui.text(title, floor(W / 2), 2, winnerColor, "center")
  end
  ui.small(app.plugin.view.howLine(r, fmtDuration(r.seconds)), floor(W / 2), howY, C.line, C.bg, "center", W - 2)

  -- two player panels (a short wall keeps the facts and drops the streak line)
  local compact = H < 78
  local panelH = compact and 20 or 24
  local pw = floor((W - 10) / 2)
  local function panel(num, x)
    local slot = num == 1 and r.red or r.blue
    local sum = r.summary[num == 1 and "red" or "blue"]
    local color = num == 1 and C.red or C.blue
    local won = r.winner == num
    ui.fill(x, 15, pw, panelH, C.panel)
    ui.fill(x, 15, 3, panelH, color)
    if won then ui.frame(x, 15, pw, panelH, C.hi, 1) end
    ui.name(slot.name, x + 6, 17, pw - 10, C.text, "left", C.panel)
    ui.small(app.plugin.view.seatMarks[num], x + 6, 26, color, C.panel, "left")
    if r.ranked and sum and sum.elo then
      local d = sum.delta or 0
      ui.small(string.format("RATING %d  (%s)", sum.elo, signed(d)), x + 6, 29, d > 0 and C.ok or (d < 0 and C.warn or C.line), C.panel, "left", pw - 8)
      local rb, ra = r.rankBefore[num == 1 and "red" or "blue"], r.rankAfter[num == 1 and "red" or "blue"]
      local rk = ra and ("RANK #" .. ra) or "UNRANKED"
      if rb and ra and ra < rb then rk = rk .. "  UP" elseif rb and ra and ra > rb then rk = rk .. "  DOWN" end
      ui.small(rk, x + 6, 31, C.text, C.panel, "left", pw - 8)
      local st = sum.streak or 0
      if not compact then
        ui.small(string.format("STREAK %s   GAMES %d", st > 0 and ("W" .. st) or (st < 0 and ("L" .. -st) or "-"), sum.games or 0), x + 6, 33, C.line, C.panel, "left", pw - 8)
      end
    else
      ui.small(slot.cpu and "COMPUTER" or (slot.guest and "GUEST" or "UNRANKED GAME"), x + 6, 29, C.line, C.panel, "left")
      if not r.ranked and not r.guest then ui.small("vs computer: no rating change", x + 6, 31, C.line, C.panel, "left", pw - 8) end
    end
  end
  panel(1, 3)
  panel(2, 3 + pw + 4)

  -- achievements
  local y = 15 + panelH + 2
  local ach = r.summary.achievements or {}
  for i, a in ipairs(ach) do
    if i <= (compact and 1 or 3) then
      ui.small("* " .. a.player .. " unlocked " .. a.name, floor(W / 2), y, C.accent, C.bg, "center", W - 2)
      y = y + 2
    end
  end
  if #ach == 0 and r.ranked then
    local h2h = app.store:headToHead(r.red.name, r.blue.name)
    ui.small(string.format("%s vs %s: %d - %d - %d", r.red.name, r.blue.name, h2h.w, h2h.l, h2h.d), floor(W / 2), y, C.line, C.bg, "center", W - 2)
    y = y + 2
  end

  -- leaderboard strip
  local rows = app.store:leaderboard("elo", 5)
  ui.small("TOP RATED", 4, y + 2, C.hi, C.bg, "left")
  for i, row in ipairs(rows) do
    local ry = y + 3 + i * 2
    local color = (row.name == r.red.name or row.name == r.blue.name) and C.text or C.line
    ui.small(string.format("%d. %s", row.rank, row.name), 4, ry, color, C.bg, "left", 30)
    ui.small(tostring(row.value), 40, ry, color, C.bg, "right")
  end

  -- buttons
  local bx = 52
  local bw = W - bx - 4
  local by = y + 2
  local bh = compact and 5 or 7
  local step = bh + 1
  ui.button("rematch", bx, by, bw, bh, "REMATCH (SWAP COLORS)", C.ok, { small = true })
  ui.button("newgame", bx, by + step, bw, bh, "NEW GAME", C.panel, { small = true })
  ui.button("stats", bx, by + 2 * step, bw, bh, "STATS", C.panel, { small = true })
  ui.button("done", bx, by + 3 * step, bw, bh, "DONE", C.panel, { small = true })
  app.drawToast()
end

-- ------------------------------------------------------------------ stats

local METRIC_LABEL = { elo = "RATING", wins = "WINS", rate = "WIN %", streak = "STREAK" }

local function drawLeaders()
  local W = env.W
  ui.text("LEADERBOARD", floor(W / 2), 1, C.hi, "center")
  local tabW = floor((W - 8 - 4 * 2) / 5)
  for i, key in ipairs(Records.BOARD_ORDER) do
    local active = S.stats.metric == key
    ui.button("metric", 4 + (i - 1) * (tabW + 2), 10, tabW, 7, METRIC_LABEL[key] or app.plugin.view.scoreName, active and C.hi or C.panel, { small = true, data = key })
  end
  local rows, total = app.store:leaderboard(S.stats.metric)
  local perPage = max(3, floor((env.H - 38) / 6))
  local pages = max(1, math.ceil(#rows / perPage))
  if S.stats.page > pages then S.stats.page = pages end
  local first = (S.stats.page - 1) * perPage
  local def = Records.BOARDS[S.stats.metric]
  if #rows == 0 then
    ui.small("No ranked players yet - finish a game to appear here", floor(W / 2), 30, C.line, C.bg, "center", W - 2)
  end
  for i = 1, perPage do
    local row = rows[first + i]
    local y = 19 + (i - 1) * 6
    if row then
      local color = row.rank == 1 and C.hi or (row.rank <= 3 and C.text or C.line)
      ui.button("player", 4, y, W - 8, 5, nil, i % 2 == 0 and C.panel or C.bg, { data = row.name })
      ui.small("#" .. row.rank, 6, y + 2, color, i % 2 == 0 and C.panel or C.bg, "left")
      ui.small(row.name, 14, y + 2, color, i % 2 == 0 and C.panel or C.bg, "left", 24)
      local p = row.player
      ui.small(string.format("%dW %dL %dD", p.wins, p.losses, p.draws), 62, y + 2, C.line, i % 2 == 0 and C.panel or C.bg, "left")
      ui.small(row.value .. (def.suffix or ""), W - 6, y + 2, color, i % 2 == 0 and C.panel or C.bg, "right")
    end
  end
  if pages > 1 then
    ui.button("prevPage", W - 44, env.H - 18, 20, 7, "< PREV", C.panel, { small = true })
    ui.button("nextPage", W - 22, env.H - 18, 20, 7, "NEXT >", C.panel, { small = true })
  end
  ui.small(total .. " ranked players", 4, env.H - 16, C.line, C.bg, "left")
end

local function drawHistory()
  local W = env.W
  ui.text("RECENT GAMES", floor(W / 2), 1, C.hi, "center")
  local rows = app.store:recent(floor((env.H - 26) / 6))
  if #rows == 0 then ui.small("No games recorded yet", floor(W / 2), 30, C.line, C.bg, "center") end
  for i, h in ipairs(rows) do
    local y = 11 + (i - 1) * 6
    local bg = i % 2 == 0 and C.panel or C.bg
    ui.fill(4, y, W - 8, 5, bg)
    local when = os.date("%m/%d %H:%M", floor((h.at or 0) / 1000))
    ui.small(when, 6, y + 2, C.line, bg, "left")
    local rn = h.red .. (h.redCpu and " (CPU)" or "")
    local bn = h.blue .. (h.blueCpu and " (CPU)" or "")
    local label
    if h.winner == 3 then
      label = rn .. " drew " .. bn
    else
      label = (h.winner == 1 and rn or bn) .. " beat " .. (h.winner == 1 and bn or rn)
    end
    ui.small(label, 24, y + 2, h.winner == 1 and C.red or (h.winner == 2 and C.blue or C.text), bg, "left", 56)
    ui.small(app.plugin.view.historyLine(h), W - 6, y + 2, C.line, bg, "right")
  end
  local t = app.store.data.totals
  ui.small(string.format("%d games, %d moves, %d draws", t.games, t.moves, t.draws), 4, env.H - 14, C.line, C.bg, "left")
end

local function drawPlayerCard()
  local W = env.W
  local p = app.store:get(S.stats.player)
  if not p then
    ui.small("Unknown player", floor(W / 2), 30, C.line, C.bg, "center")
    return
  end
  ui.name(p.name, floor(W / 2), 1, W - 6, C.hi, "center")
  local rank, total = app.store:rank(p.name, "elo")
  ui.small(string.format("RATING %d   PEAK %d   RANK %s", p.elo, p.peak, rank and ("#" .. rank .. " of " .. total) or "unranked"),
    floor(W / 2), 10, C.text, C.bg, "center", W - 2)

  -- W / L / D bar
  local bx, bw = 6, W - 12
  local gm = max(1, p.games)
  local wW, wD = floor(bw * p.wins / gm), floor(bw * p.draws / gm)
  ui.fill(bx, 13, bw, 3, C.panel)
  ui.fill(bx, 13, wW, 3, C.ok)
  ui.fill(bx + wW, 13, wD, 3, C.line)
  ui.fill(bx + wW + wD, 13, bw - wW - wD, 3, p.games > 0 and C.warn or C.panel)
  ui.small(string.format("%d W    %d L    %d D    %d%% win rate", p.wins, p.losses, p.draws, floor(Records.winRate(p) * 100 + 0.5)),
    floor(W / 2), 17, C.text, C.bg, "center")

  local col1, col2 = 6, floor(W / 2) + 2
  local function stat(x, y, name, value)
    ui.small(name, x, y, C.line, C.bg, "left")
    ui.small(tostring(value), x + 26, y, C.text, C.bg, "left")
  end
  local avg = p.games > 0 and floor(p.moves / p.games * 10) / 10 or 0
  stat(col1, 21, "STREAK", p.streak > 0 and ("W" .. p.streak) or (p.streak < 0 and ("L" .. -p.streak) or "-"))
  stat(col1, 23, "BEST", p.bestStreak)
  stat(col1, 25, app.plugin.view.scoreName, p.boardsWon .. " won / " .. p.boardsLost .. " lost")
  stat(col1, 27, "FASTEST", p.fastestWin and (p.fastestWin .. " moves") or "-")
  stat(col1, 29, "LONGEST", p.longest .. " moves")
  stat(col2, 21, "AS RED", p.asRed.wins .. "/" .. p.asRed.games .. " won")
  stat(col2, 23, "AS BLUE", p.asBlue.wins .. "/" .. p.asBlue.games .. " won")
  stat(col2, 25, "PLAYED", fmtDuration(p.seconds))
  stat(col2, 27, "AVG MOVES", avg)
  stat(col2, 29, "GAMES", p.games)

  -- versus the computer
  local y = 33
  ui.small("VS COMPUTER", col1, y, C.hi, C.bg, "left")
  local x = col1 + 14
  for _, lvl in ipairs(app.plugin.cpuLevels or {}) do
    local r = p.vsCpu[lvl] or { w = 0, l = 0, d = 0 }
    ui.small(string.format("%s %d-%d-%d", lvl:sub(1, 1):upper() .. lvl:sub(2), r.w, r.l, r.d), x + 4, y, C.text, C.bg, "left")
    x = x + 26
  end

  -- rivals: most-played opponents
  local rivals = {}
  for name, r in pairs(p.h2h) do
    local other = app.store:get(name)
    rivals[#rivals + 1] = { name = other and other.name or name, r = r, n = r.w + r.l + r.d }
  end
  table.sort(rivals, function(a, b) return a.n > b.n end)
  ui.small("RIVALS", col1, 37, C.hi, C.bg, "left")
  for i = 1, 3 do
    local rv = rivals[i]
    if rv then ui.small(string.format("%s  %d-%d-%d", rv.name, rv.r.w, rv.r.l, rv.r.d), col1 + 8, 37 + i * 2, C.text, C.bg, "left", 40) end
  end

  -- achievements
  ui.small("BADGES", col2, 37, C.hi, C.bg, "left")
  local ach = app.store:achievements(p.name)
  if #ach == 0 then ui.small("none yet", col2 + 8, 39, C.line, C.bg, "left") end
  for i, a in ipairs(ach) do
    if i <= 5 then ui.small("* " .. a.name, col2 + 8, 37 + i * 2, C.accent, C.bg, "left", 24) end
  end

  -- recent form: the last 12 games as coloured blocks, newest on the left
  ui.small("FORM", col1, 51, C.hi, C.bg, "left")
  local key = string.lower(p.name)
  local x = col1 + 8
  local shown = 0
  local hist = app.store.data.history
  for i = #hist, 1, -1 do
    local h = hist[i]
    local side = (not h.redCpu and string.lower(h.red) == key) and 1 or ((not h.blueCpu and string.lower(h.blue) == key) and 2 or nil)
    if side and shown < 12 then
      local color = h.winner == 3 and C.line or (h.winner == side and C.ok or C.warn)
      ui.fill(x, 51, 6, 3, color)
      x = x + 8
      shown = shown + 1
    end
  end
  if shown == 0 then ui.small("no recent games", col1 + 8, 51, C.line, C.bg, "left") end
end

local function drawStats()
  background()
  ui.clearButtons()
  local W, H = env.W, env.H
  if S.stats.mode == "leaders" then drawLeaders()
  elseif S.stats.mode == "history" then drawHistory()
  else drawPlayerCard() end
  local y = H - 9
  local bw = floor((W - 10) / 4)
  ui.button("tab", 2, y, bw, 7, "LEADERS", S.stats.mode == "leaders" and C.hi or C.panel, { small = true, data = "leaders" })
  ui.button("tab", 2 + (bw + 2), y, bw, 7, "HISTORY", S.stats.mode == "history" and C.hi or C.panel, { small = true, data = "history" })
  ui.button("settings", 2 + 2 * (bw + 2), y, bw, 7, "SETTINGS", C.panel, { small = true })
  ui.button("back", 2 + 3 * (bw + 2), y, bw, 7, "BACK", C.panel, { small = true })
  app.drawToast()
end

-- ------------------------------------------------------------------ settings

local function drawSettings()
  background()
  ui.clearButtons()
  local W, H = env.W, env.H
  ui.text("SETTINGS", floor(W / 2), 1, C.hi, "center")
  local bw = floor((W - 10) / 2)
  local rowStep = H < 78 and 8 or 10

  local function onoff(v) return v and "ON" or "OFF" end
  local rows = {
    { "sound", "SOUND: " .. onoff(app.prefs.sound) },
    { "vol", "VOLUME: " .. floor(app.prefs.volume * 100) .. "%" },
    { "announce", "CHAT ANNOUNCE: " .. onoff(app.prefs.announce) },
    { "redstone", "REDSTONE LAMPS: " .. onoff(app.prefs.redstone) },
    { "testsound", "TEST SOUNDS" },
  }
  for i, row in ipairs(app.plugin.settingsRows(app.store)) do table.insert(rows, 2 + i, row) end
  local hwY = 10 + math.ceil(#rows / 2) * rowStep + 2
  for i, row in ipairs(rows) do
    local col = (i - 1) % 2
    local r = floor((i - 1) / 2)
    ui.button(row[1], 4 + col * (bw + 2), 10 + r * rowStep, bw, rowStep - 2, row[2], C.panel, { small = true })
  end
  -- attached hardware
  local rep = hw.report()
  ui.small("HARDWARE", 4, hwY, C.hi, C.bg, "left")
  local lines = {
    "monitor: " .. tostring(rep.monitor) .. " (" .. env.W .. "x" .. env.H .. ")" .. (rep.wall2 and ("   second wall: " .. rep.wall2) or ""),
    "scoreboard: " .. tostring(rep.scoreboard or "none"),
    "speaker: " .. tostring(rep.speaker or "none"),
    "player detector: " .. tostring(rep.detector or "none"),
    "chat box: " .. tostring(rep.chat or "none") .. "   redstone: " .. tostring(rep.redstone),
  }
  for i, l in ipairs(lines) do ui.small(l, 4, hwY + i * 2, C.text, C.bg, "left", W - 6) end
  local wipe = S.confirm and S.confirm.id == "wipe" and nowMs() < S.confirm.untilAt
  ui.button("wipe", 4, H - 9, 50, 7, wipe and "TAP AGAIN TO WIPE" or "RESET ALL STATS", wipe and C.warn or C.panel, { small = true })
  ui.button("back", W - 24, H - 9, 20, 7, "BACK", C.panel, { small = true })
  app.drawToast()
end

-- ------------------------------------------------------------------ scoreboard monitor

local function drawScoreboard()
  local board2 = env.board2
  if not board2 then return end
  local sc = board2.surf
  local prev = ui.screen()
  ui.setScreen(sc)
  sc:clear(C.bg, nil, " ")
  local W, H = board2.W, board2.H
  ui.text("LEADERBOARD", floor(W / 2), 1, C.hi, "center")
  local rows = app.store:leaderboard("elo", 8)
  if #rows == 0 then ui.small("Play a game to get on the board", floor(W / 2), 14, C.line, C.bg, "center") end
  for i, row in ipairs(rows) do
    local y = 10 + (i - 1) * 4
    local color = i == 1 and C.hi or (i <= 3 and C.text or C.line)
    local bg = i % 2 == 0 and C.panel or C.bg
    ui.fill(2, y, W - 4, 3, bg)
    ui.small("#" .. row.rank, 4, y + 1, color, bg, "left")
    ui.small(row.name, 10, y + 1, color, bg, "left", W - 28)
    ui.small(row.value .. "", W - 4, y + 1, color, bg, "right")
  end
  local y = 10 + 8 * 4 + 1
  if y < H - 8 then
    local g = S.match
    ui.fill(2, y, W - 4, 1, C.panel)
    if g then
      ui.small("NOW PLAYING", 4, y + 2, C.hi, C.bg, "left")
      ui.small(g.red.name .. " vs " .. g.blue.name, 4, y + 4, C.text, C.bg, "left", W - 6)
      ui.small(app.plugin.view.scoreLine(g), 4, y + 6, C.line, C.bg, "left", W - 6)
    else
      local r = app.store:recent(1)[1]
      ui.small("LAST GAME", 4, y + 2, C.hi, C.bg, "left")
      if r then
        ui.small(r.winner == 3 and (r.red .. " drew " .. r.blue) or ((r.winner == 1 and r.red or r.blue) .. " won"), 4, y + 4, C.text, C.bg, "left", W - 6)
      else
        ui.small("none yet", 4, y + 4, C.line, C.bg, "left")
      end
    end
  end
  sc:output(board2.mon, 0, 0)
  ui.setScreen(prev)
end

M.drawLobby, M.drawResult, M.drawStats, M.drawSettings, M.drawScoreboard = drawLobby, drawResult, drawStats, drawSettings, drawScoreboard

return M
