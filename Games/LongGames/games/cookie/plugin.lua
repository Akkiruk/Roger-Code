-- games/cookie/plugin.lua
-- Cookie Clicker as a long game. The big cookie fills the left of the wall and the store the right: buildings, a few
-- upgrades, and pages of stats, achievements and ascension in the store's place. The game keeps its own header, so it is
-- a story game to the shell. Every tap goes through view.actionAt; nothing is drawn as a shell button.
--
-- The clock: rules.tick is a quarter second of baking, and after every tick onEvents hands the real time to rules.wake,
-- which bakes for any long gap (a save loaded later, here or on another cabinet) and leaves the greeting.

local base = require("lib.arcade.base")
local rules = require("games.cookie.rules")
local art = require("games.cookie.art")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min
local fmt, fmtShort, fmtRate = rules.fmt, rules.fmtShort, rules.fmtRate

local view = {}

local QUIT_W, QUIT_H = 15, 9   -- the shell's SAVE & QUIT, in the bottom right corner, plus a margin
local ROW_H = 5                -- a building in the store
local UP_H = 3                 -- an upgrade in the store
local LIST_H = 4               -- an upgrade on the full list
local TILE_W, TILE_H = 14, 5   -- an achievement
local GOLD_W, GOLD_H = 11, 7

-- ---------------------------------------------------------------- layout

function view.layout(W, H)
  local fh = 5
  pcall(function() fh = ui.fontHeight() end)
  local L = { W = W, H = H, x0 = 0, y0 = 0, bw = W, bh = H, hdr = 0, fh = fh }
  local split = floor(W * 0.48)
  L.split = split
  -- the left: the count, the rate, the cookie, the menu
  L.countY = 1
  L.wordY = L.countY + fh + 1
  L.rateY = L.wordY + 1
  L.buffY = L.rateY + 2
  L.menuH = 7
  L.menuY = H - L.menuH - 1
  local top, bottom = L.buffY + 2, L.menuY - 2
  local ch = max(6, min(bottom - top - 8, floor((split - 6) / 1.5)))
  local cw = floor(ch * 1.5)
  L.cookie = { x = floor((split - cw) / 2), y = top + floor((bottom - top - ch) / 2) - 2, w = cw, h = ch }
  L.cookie.cx, L.cookie.cy = L.cookie.x + floor(cw / 2), L.cookie.y + floor(ch / 2)
  L.toastY = min(L.menuY - 8, L.cookie.y + ch + 1)
  local bw = floor((split - 4) / 3)
  L.menu = {
    { x = 1, w = bw, label = "STATS", name = "stats" },
    { x = 2 + bw, w = bw, label = "AWARDS", name = "ach" },
    { x = 3 + 2 * bw, w = split - 4 - 2 * bw, label = "ASCEND", name = "ascend" },
  }
  -- the right: the store
  L.rx = split + 2
  L.rw = W - L.rx - 1
  L.quitX, L.quitY = W - QUIT_W, H - QUIT_H
  L.titleH = max(5, fh)
  L.upLabelY = L.titleH + 2 -- the upgrades bar, which opens the full list
  L.upY = L.upLabelY + 4
  L.upRows = H >= 70 and 3 or 2
  L.bY = L.upY + L.upRows * (UP_H + 1)
  L.pagerY = H - 7
  L.bRows = max(1, floor((L.pagerY - 1 - L.bY + 1) / (ROW_H + 1)))
  L.bodyY = L.titleH + 4 -- where the other pages start
  L.nextX = min(L.rx + L.rw - 16, L.quitX - 17)
  L.pagerTextX = floor((L.rx + 16 + L.nextX) / 2)
  return L
end

-- ---------------------------------------------------------------- the plan: every place a tap can land

--- Where the golden cookie is on this wall: kept out of the shell's QUIT corner.
local function goldenRect(L, live)
  local x = 1 + floor(live.x * (L.W - GOLD_W - 3))
  local y = 2 + floor(live.y * (L.H - GOLD_H - 4))
  if x + GOLD_W > L.quitX - 1 and y + GOLD_H > L.quitY - 1 then y = L.quitY - GOLD_H - 2 end
  return { x = x, y = y, w = GOLD_W, h = GOLD_H }
end

local function pages(count, per) return max(1, math.ceil(count / per)) end

--- Every button and row on the wall as it stands, for both drawing and tapping.
local function plan(L, s)
  local P = { buttons = {}, rows = {}, ups = {}, tiles = {}, list = {} }
  local function button(x, y, w, h, label, action, style)
    local b = { x = x, y = y, w = w, h = h, label = label, action = action, style = style or "plain" }
    P.buttons[#P.buttons + 1] = b
    return b
  end
  local scr = s.ui.screen
  for _, m in ipairs(L.menu) do
    local on = scr == m.name
    local style = on and "on" or "plain"
    if m.name == "ascend" and not on and rules.pendingChips(s) >= 1 then style = "glow" end
    button(m.x, L.menuY, m.w, L.menuH, m.label, { kind = "screen", name = on and "bake" or m.name }, style)
  end
  local rx, rw = L.rx, L.rw
  if scr == "bake" then
    for i, n in ipairs(rules.MODES) do
      local w = 9
      local x = rx + rw - (#rules.MODES - i + 1) * (w + 1) + 1
      button(x, 1, w, L.titleH, "x" .. n, { kind = "mode", n = n }, s.ui.mode == i and "on" or "plain")
    end
    local avail = rules.available(s)
    P.avail = avail
    for i = 1, min(L.upRows, #avail) do
      local u = avail[i]
      P.ups[i] = { x = rx, y = L.upY + (i - 1) * (UP_H + 1), w = rw, h = UP_H, u = u, action = { kind = "upgrade", id = u.id } }
    end
    P.upBar = { x = rx, y = L.upLabelY, w = rw, h = 3, action = { kind = "screen", name = "upgrades" } }
    local shown = rules.shownBuildings(s)
    local per = L.bRows
    local count = pages(shown, per)
    local page = min(s.ui.page, count)
    P.page, P.pages = page, count
    local n = rules.MODES[s.ui.mode] or 1
    for slot = 1, per do
      local i = (page - 1) * per + slot
      if i > shown then break end
      P.rows[slot] = { x = rx, y = L.bY + (slot - 1) * (ROW_H + 1), w = rw, h = ROW_H, i = i, n = n, action = { kind = "buy", i = i, n = n } }
    end
    if count > 1 then
      local pw = 16
      if page > 1 then button(rx, L.pagerY, pw, 6, "< PREV", { kind = "page", to = page - 1 }) end
      if page < count then button(L.nextX, L.pagerY, pw, 6, "NEXT >", { kind = "page", to = page + 1 }) end
    end
  else
    button(rx + rw - 14, 1, 14, L.titleH, "BACK", { kind = "screen", name = "bake" })
  end
  if scr == "upgrades" then
    local avail = rules.available(s)
    local per = max(1, floor((L.pagerY - 1 - L.bodyY) / (LIST_H + 1)))
    local count = pages(#avail, per)
    local page = min(s.ui.list, count)
    P.page, P.pages, P.avail = page, count, avail
    for slot = 1, per do
      local u = avail[(page - 1) * per + slot]
      if not u then break end
      P.list[slot] = { x = rx, y = L.bodyY + (slot - 1) * (LIST_H + 1), w = rw, h = LIST_H, u = u, action = { kind = "upgrade", id = u.id } }
    end
  elseif scr == "ach" then
    local cols = max(1, floor((rw + 1) / (TILE_W + 1)))
    local tileW = floor((rw + 1) / cols) - 1
    local rows = max(1, floor((L.pagerY - 6 - L.bodyY) / (TILE_H + 1)))
    local per = cols * rows
    local count = pages(#rules.ACHIEVEMENTS, per)
    local page = min(s.ui.list, count)
    P.page, P.pages = page, count
    for slot = 1, per do
      local a = rules.ACHIEVEMENTS[(page - 1) * per + slot]
      if not a then break end
      local col, row = (slot - 1) % cols, floor((slot - 1) / cols)
      P.tiles[slot] = { x = rx + col * (tileW + 1), y = L.bodyY + row * (TILE_H + 1), w = tileW, h = TILE_H, a = a, action = { kind = "inspect", id = a.id } }
    end
    P.infoY = L.bodyY + rows * (TILE_H + 1)
  elseif scr == "ascend" then
    local pending = rules.pendingChips(s)
    local asking = s.ui.confirm > 0
    local label = pending < 1 and "NOT YET" or (asking and "TAP AGAIN TO ASCEND" or "ASCEND")
    P.ascendButton = button(rx + 2, L.pagerY - 9, min(rw - 4, L.quitX - rx - 4), 8, label, { kind = "ascend" },
      pending < 1 and "off" or (asking and "warn" or "glow"))
  end
  if (scr == "upgrades" or scr == "ach") and (P.pages or 1) > 1 then
    local pw = 16
    if P.page > 1 then button(rx, L.pagerY, pw, 6, "< PREV", { kind = "list", to = P.page - 1 }) end
    if P.page < P.pages then button(L.nextX, L.pagerY, pw, 6, "NEXT >", { kind = "list", to = P.page + 1 }) end
  end
  if s.gold.live then P.golden = goldenRect(L, s.gold.live) end
  return P
end

local function inside(r, px, py)
  return r and px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

--- Is a cell on the big cookie? A little generous round the edge, so a quick tap still counts.
local function onCookie(L, px, py)
  local c = L.cookie
  local dx = (px - c.cx) / (c.w / 2 + 1.5)
  local dy = (py - c.cy) / (c.h / 2 + 1)
  return dx * dx + dy * dy <= 1
end

--- What a tap at (px, py) does.
function view.actionAt(L, s, px, py)
  if not s then return nil end
  if s.away then return { kind = "dismiss" } end
  local P = plan(L, s)
  if P.golden then
    local g = P.golden
    if px >= g.x - 1 and px < g.x + g.w + 1 and py >= g.y - 1 and py < g.y + g.h + 1 then return { kind = "golden" } end
  end
  for i = #P.buttons, 1, -1 do
    if inside(P.buttons[i], px, py) then return P.buttons[i].action end
  end
  if inside(P.upBar, px, py) then return P.upBar.action end
  for _, list in ipairs({ P.rows, P.ups, P.list, P.tiles }) do
    for _, r in pairs(list) do
      if inside(r, px, py) then return r.action end
    end
  end
  if px < L.split and onCookie(L, px, py) then
    -- silent: a sound on every one of hundreds of taps wears thin fast. The squash and the +N are the feedback.
    return { kind = "tap", dx = px - L.cookie.cx, dy = py - L.cookie.cy }
  end
  return nil
end

function view.controls() return {} end

-- ---------------------------------------------------------------- drawing

local STYLE = {
  plain = { C.panel, C.text }, on = { C.hi, C.bg }, glow = { C.hi, C.bg }, warn = { C.warn, C.bg },
  off = { C.panel, C.line }, small = { C.tie, C.text },
}

--- A page's name at the top of the store, in the big font when there's room.
local function title(L, text, room)
  if ui.textWidth(text) <= room then
    ui.text(text, L.rx, 1, C.hi, "left")
  else
    ui.small(text, L.rx, 1 + floor(L.titleH / 2), C.hi, C.bg, "left", room)
  end
end

local function drawButton(b)
  local st = STYLE[b.style] or STYLE.plain
  ui.fill(b.x, b.y, b.w, b.h, st[1])
  ui.small(b.label, b.x + floor(b.w / 2), b.y + floor((b.h - 1) / 2), st[2], st[1], "center", b.w - 1)
end

--- A number in the big font if it fits, otherwise in small text.
local function bigNumber(text, cx, y, w, color, fh)
  if ui.textWidth(text) <= w then
    ui.text(text, cx, y, color, "center")
  else
    ui.small(text, cx, y + floor(fh / 2), color, C.bg, "center", w)
  end
end

--- The count of cookies, split into the digits and the name under them: "1.234" over "million cookies".
local function countParts(n)
  if n < 1e6 then return fmt(n), (floor(n) == 1 and "cookie" or "cookies") end
  local text = fmt(n)
  local space = text:find(" ")
  return text:sub(1, space - 1), text:sub(space + 1) .. " cookies"
end

local function drawHeader(L, s)
  local cx, w = floor(L.split / 2), L.split - 2
  local number, word = countParts(s.cookies)
  bigNumber(number, cx, L.countY, w, C.text, L.fh)
  ui.small(word, cx, L.wordY, C.line, C.bg, "center", w)
  local rate = rules.cps(s)
  local frenzy = s.buff and s.buff.kind == "frenzy"
  ui.small("per second: " .. fmtRate(rate), cx, L.rateY, frenzy and C.hi or C.text, C.bg, "center", w)
end

local function drawBuff(L, s)
  local b = s.buff
  if not b then return end
  local label = b.kind == "frenzy" and "FRENZY x7" or "CLICK FRENZY x777"
  local secs = math.ceil(b.left / 4)
  local text = label .. "  " .. secs .. "s"
  local x = 2
  ui.small(text, x, L.buffY, C.bg, C.hi, "left")
  local barX = x + #text + 1
  local barW = L.split - 2 - barX
  if barW > 2 then
    ui.fill(barX, L.buffY, barW, 1, C.panel)
    ui.fill(barX, L.buffY, max(1, floor(barW * b.left / b.total)), 1, C.hi)
  end
end

local function drawMilk(L, s)
  local milk = rules.milk(s)
  if milk <= 0 then return end
  -- a pool of milk under the cookie, deeper with every award; its surface catches the light
  local rows = min(4, 1 + floor(milk))
  local y = L.menuY - 1 - rows
  ui.fill(0, y, L.split, 1, C.line)
  ui.fill(0, y + 1, L.split, rows, C.text)
end

local function drawCookie(L, s)
  local c = L.cookie
  art.cookie(c.x, c.y, c.w, c.h, s.fx.press > 0, s.buff ~= nil)
  -- the cookies a tap made, floating up from where it landed
  local screen = ui.screen()
  for _, p in ipairs(s.fx.pops) do
    local text = "+" .. fmtShort(p.value)
    local jitter = ((p.seq or 0) * 5) % 9 - 4 -- taps on one spot still fan out a little
    local x = c.cx + max(-c.w / 2 + 2, min(c.w / 2 - #text - 1, p.dx + jitter)) - floor(#text / 2)
    local y = c.cy + p.dy - 2 - p.age * 2
    if y >= L.buffY + 1 then screen:drawString(text, floor(x), floor(y), nil, C.text) end
  end
  if s.fx.note then
    ui.small(" " .. s.fx.note .. " ", floor(L.split / 2), max(L.buffY + 1, c.y - 2), C.bg, C.hi, "center", L.split - 2)
  end
end

local function drawToast(L, s)
  local t = s.toasts[1]
  if not t then return end
  local w = L.split - 4
  local y = L.toastY
  ui.fill(2, y, w, 6, C.panel)
  ui.frame(2, y, w, 6, C.hi)
  ui.small(t.title, 2 + floor(w / 2), y + 2, C.hi, C.panel, "center", w - 2)
  ui.small(t.text, 2 + floor(w / 2), y + 3, C.text, C.panel, "center", w - 2)
end

local function drawLeft(L, s, P)
  drawMilk(L, s)
  drawHeader(L, s)
  drawBuff(L, s)
  drawCookie(L, s)
  ui.small("+" .. fmtRate(rules.tapValue(s), true) .. " a tap", floor(L.split / 2), L.cookie.y + L.cookie.h + 1, C.line, C.bg, "center", L.split - 2)
  drawToast(L, s)
  ui.fill(L.split, 0, 1, L.H, C.panel)
end

-- the store

local function drawUpgradeRow(r, s)
  local u = r.u
  local can = s.cookies >= u.cost
  local bg = can and C.tie or C.panel
  ui.fill(r.x, r.y, r.w, r.h, bg)
  ui.fill(r.x, r.y, 1, r.h, can and C.ok or C.line)
  local price = fmtShort(u.cost)
  ui.small(u.name, r.x + 2, r.y + 1, can and C.text or C.line, bg, "left", r.w - #price - 4)
  ui.small(price, r.x + r.w - 1, r.y + 1, can and C.ok or C.red, bg, "right")
  ui.small(u.says, r.x + 2, r.y + 2, can and C.hi or C.line, bg, "left", r.w - 3)
end

local function drawBuildingRow(r, s, fh)
  local i, n = r.i, r.n
  local b = rules.BUILDINGS[i]
  local mystery = rules.mystery(s, i)
  local price = rules.cost(s, i, n)
  local can = not mystery and s.cookies >= price
  local bg = can and C.tie or C.panel
  ui.fill(r.x, r.y, r.w, r.h, bg)
  art.icon(b.id, r.x + 1, r.y, mystery)
  local tx = r.x + art.ICON_W + 2
  local owned = s.owned[i]
  local countW = owned > 0 and art.digitsWidth(tostring(owned)) or 0
  ui.small(mystery and "???" or b.name, tx, r.y + 1, can and C.text or C.line, bg, "left", r.w - (tx - r.x) - countW - 2)
  local costText = (n > 1 and (n .. " for ") or "") .. rules.fmtNice(price)
  ui.small(costText, tx, r.y + 2, can and C.ok or C.red, bg, "left", r.w - (tx - r.x) - countW - 2)
  if not mystery then
    local each = rules.eachCps(s, i)
    local line = "each " .. fmtRate(each, true) .. "/s"
    if owned > 0 then line = line .. "  all " .. fmtRate(each * owned, true) .. "/s" end
    ui.small(line, tx, r.y + 3, C.line, bg, "left", r.w - (tx - r.x) - countW - 2)
  end
  if owned > 0 then art.digits(tostring(owned), r.x + r.w - 2, r.y, can and C.text or C.line) end
end

local function drawStore(L, s, P)
  local rx, rw = L.rx, L.rw
  title(L, "STORE", rw - #rules.MODES * 10 - 1)
  local bar = P.upBar
  local affordable = 0
  for _, u in ipairs(P.avail) do
    if u.cost <= s.cookies then affordable = affordable + 1 end
  end
  ui.fill(bar.x, bar.y, bar.w, bar.h, C.panel)
  ui.small("UPGRADES", bar.x + 2, bar.y + 1, C.text, C.panel, "left")
  local count = #P.avail == 0 and "none yet" or (affordable .. " of " .. #P.avail .. " affordable")
  ui.small(count, bar.x + 12, bar.y + 1, affordable > 0 and C.ok or C.line, C.panel, "left")
  ui.small("ALL >", bar.x + bar.w - 2, bar.y + 1, C.hi, C.panel, "right")
  if #P.avail == 0 then
    ui.small("Buy buildings and bake to unlock upgrades", rx, L.upY + 1, C.line, C.bg, "left", rw)
  end
  for _, r in ipairs(P.ups) do drawUpgradeRow(r, s) end
  if P.pages > 1 then ui.small(P.page .. " of " .. P.pages, L.pagerTextX, L.pagerY + 2, C.line, C.bg, "center") end
  for _, r in ipairs(P.rows) do drawBuildingRow(r, s, L.fh) end
end

local function drawUpgradeList(L, s, P)
  title(L, "UPGRADES", L.rw - 16)
  ui.small(#P.avail .. " to buy, " .. s.upsBought .. " bought in all", L.rx, L.bodyY - 2, C.line, C.bg, "left", L.rw)
  if #P.avail == 0 then ui.small("Nothing to buy yet. Keep baking!", L.rx, L.bodyY + 1, C.text, C.bg, "left", L.rw) end
  for _, r in ipairs(P.list) do drawUpgradeRow(r, s) end
  if P.pages > 1 then ui.small(P.page .. " of " .. P.pages, L.pagerTextX, L.pagerY + 2, C.line, C.bg, "center") end
end

local function wrapInto(text, x, y, w, lines, fg, bg)
  for i, line in ipairs(ui.wrap(text, w)) do
    if i > lines then break end
    ui.small(line, x, y + i - 1, fg, bg, "left", w)
  end
end

local function drawAchievements(L, s, P)
  title(L, "AWARDS", L.rw - 16)
  ui.small(s.achCount .. " of " .. #rules.ACHIEVEMENTS .. " won, milk " .. floor(rules.milk(s) * 100 + 0.5) .. "%", L.rx, L.bodyY - 2, C.line, C.bg, "left", L.rw)
  for _, t in ipairs(P.tiles) do
    local won = s.ach[t.a.id]
    local picked = s.ui.inspect == t.a.id
    local bg = won and C.hiTint or C.panel
    ui.fill(t.x, t.y, t.w, t.h, bg)
    if picked then ui.frame(t.x, t.y, t.w, t.h, C.text) end
    if won then ui.fill(t.x + 1, t.y + 1, 1, 1, C.hi) end
    wrapInto(t.a.name, t.x + (won and 3 or 1), t.y + 1, t.w - (won and 4 or 2), 3, won and C.hi or C.line, bg)
  end
  local a = s.ui.inspect and rules.ACH_BY_ID[s.ui.inspect]
  local y = P.infoY
  if a then
    ui.small(a.name .. (s.ach[a.id] and "  - WON" or ""), L.rx, y, s.ach[a.id] and C.hi or C.text, C.bg, "left", L.rw)
    ui.small(rules.achText(a), L.rx, y + 1, C.line, C.bg, "left", L.rw)
  else
    ui.small("Tap an award to see what it asks", L.rx, y, C.line, C.bg, "left", L.rw)
  end
  if P.pages > 1 then ui.small(P.page .. " of " .. P.pages, L.pagerTextX, L.pagerY + 2, C.line, C.bg, "center") end
end

local function drawStats(L, s)
  title(L, "STATS", L.rw - 16)
  local rows = {
    { "Cookies in the bank", fmt(s.cookies) },
    { "Baked this run", fmt(s.baked) },
    { "Baked all time", fmt(s.allTime) },
    { "Per second", fmtRate(rules.cps(s)) },
    { "A tap is worth", fmtRate(rules.tapValue(s)) },
    { "Made by tapping", fmt(s.hand) },
    { "Taps", fmt(s.taps) },
    { "Golden cookies", fmt(s.goldenClicks) },
    { "Buildings", fmt(rules.totalOwned(s)) },
    { "Upgrades bought", fmt(s.upsBought) },
    { "Awards", s.achCount .. " of " .. #rules.ACHIEVEMENTS },
    { "Milk", floor(rules.milk(s) * 100 + 0.5) .. "%" },
    { "Heavenly chips", fmt(s.chips) .. " (+" .. fmt(s.chips) .. "%)" },
    { "Ascensions", fmt(s.ascensions) },
    { "Longest bake away", s.bestAway > 0 and rules.duration(s.bestAway * 1000) or "none yet" },
    { "Time played", rules.duration(s.ticks * rules.TICK_MS) },
    { "This run", rules.duration(s.runTicks * rules.TICK_MS) },
  }
  local gap = (L.pagerY - L.bodyY) >= #rows * 2 + 2 and 2 or 1
  local y = L.bodyY
  for _, r in ipairs(rows) do
    if y >= L.pagerY then break end
    ui.small(r[1], L.rx, y, C.line, C.bg, "left")
    ui.small(r[2], L.rx + L.rw, y, C.text, C.bg, "right", L.rw - #r[1] - 2)
    y = y + gap
  end
end

local function drawAscend(L, s)
  title(L, "ASCEND", L.rw - 16)
  local x, w = L.rx, L.rw
  local y = L.bodyY
  wrapInto("Start the bakery over from nothing. Every heavenly chip you hold makes all your baking 1% faster, forever. Chips come from cookies baked in all time; your awards stay.", x, y, w, 5, C.text, C.bg)
  y = y + 6
  local pending = rules.pendingChips(s)
  ui.small("Chips you hold", x, y, C.line, C.bg, "left")
  ui.small(fmt(s.chips) .. "  (+" .. fmt(s.chips) .. "%)", x + w, y, C.text, C.bg, "right")
  y = y + 2
  ui.small("Ascend now for", x, y, C.line, C.bg, "left")
  ui.small("+" .. fmt(pending) .. " chips", x + w, y, pending >= 1 and C.hi or C.text, C.bg, "right")
  y = y + 2
  ui.small("Next chip in", x, y, C.line, C.bg, "left")
  ui.small(rules.fmtNice(rules.nextChipIn(s)) .. " cookies", x + w, y, C.text, C.bg, "right", w - 14)
  y = y + 2
  ui.small("Times ascended", x, y, C.line, C.bg, "left")
  ui.small(fmt(s.ascensions), x + w, y, C.text, C.bg, "right")
  y = y + 3
  local big = pending >= 1 and ("+" .. fmtShort(pending)) or "0"
  bigNumber(big, x + floor(w / 2), y, w, pending >= 1 and C.hi or C.line, L.fh)
  ui.small("heavenly chips waiting", x + floor(w / 2), y + L.fh + 1, C.line, C.bg, "center", w)
end

local function drawGolden(L, s, P)
  local live = s.gold.live
  local g = P.golden
  art.golden(g.x, g.y, g.w, g.h, live.left, live.left <= 12)
end

local function drawAway(L, s)
  local a = s.away
  local w, h = min(L.W - 6, 86), 27
  local x, y = floor((L.W - w) / 2), floor((L.H - h) / 2)
  ui.fill(x, y, w, h, C.panel)
  ui.frame(x, y, w, h, C.hi)
  local cx = x + floor(w / 2)
  ui.text("WELCOME BACK!", cx, y + 2, C.hi, "center", w - 4)
  ui.small("While you were away you baked", cx, y + 3 + L.fh + 1, C.text, C.panel, "center", w - 2)
  local number, word = countParts(a.cookies)
  bigNumber(number, cx, y + 5 + L.fh + 1, w - 4, C.text, L.fh)
  ui.small(word, cx, y + 6 + 2 * L.fh + 2, C.line, C.panel, "center", w - 2)
  local line = "in " .. rules.duration(a.ms) .. ", at half speed"
  if a.capped then line = "in " .. rules.duration(a.ms) .. " (a day at most), at half speed" end
  if a.cookies <= 0 then line = "Buy buildings and they bake while you're gone" end
  ui.small(line, cx, y + h - 5, C.line, C.panel, "center", w - 2)
  ui.small("TAP TO CARRY ON", cx, y + h - 3, C.hi, C.panel, "center", w - 2)
end

local function paint(L, s)
  local P = plan(L, s)
  drawLeft(L, s, P)
  local scr = s.ui.screen
  if scr == "bake" then drawStore(L, s, P)
  elseif scr == "upgrades" then drawUpgradeList(L, s, P)
  elseif scr == "ach" then drawAchievements(L, s, P)
  elseif scr == "stats" then drawStats(L, s)
  elseif scr == "ascend" then drawAscend(L, s)
  end
  for _, b in ipairs(P.buttons) do drawButton(b) end
  if P.golden then drawGolden(L, s, P) end
  if s.away then drawAway(L, s) end
end

function view.draw(L, s)
  paint(L, s)
end

-- ---------------------------------------------------------------- the shell's hooks

function view.saveSummary(s)
  return rules.summary(s)
end

--- For the PLAYERS list and the play tracker: how far the bakery has come.
function view.progress(s)
  local owned = rules.totalOwned(s)
  return {
    percent = floor(100 * s.achCount / #rules.ACHIEVEMENTS),
    level = s.ascensions + 1,
    minutes = floor(s.ticks * rules.TICK_MS / 60000),
    goal = fmtRate(rules.rawCps(s), true) .. "/s, " .. fmtShort(s.allTime) .. " baked",
    place = owned .. " buildings, " .. fmtShort(s.chips) .. " heavenly chips",
    cps = rules.rawCps(s), baked = s.allTime, buildings = owned, chips = s.chips,
  }
end

-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  buy = "coin", upgrade = "powerup", nope = "ui_error", ui = "ui_tap", page = "ui_page", dismiss = "chip_stack",
  achievement = "level_up", golden_spawn = "ui_hint", golden_gone = "ui_back", ask = "ui_warning", ascend = "level_clear",
  away = "payout", buff_end = "ui_back", golden_lucky = "payout", golden_frenzy = "win_big", golden_click = "win_big",
}

--- After every tick: the real time goes to the rules, and what happened is heard.
function view.onEvents(app, s, events)
  local all = {}
  for _, ev in ipairs(events) do all[#all + 1] = ev end
  for _, ev in ipairs(rules.wake(s, os.epoch("utc"))) do all[#all + 1] = ev end
  for _, kind in ipairs(rules.takeHeard(s)) do all[#all + 1] = { type = kind } end
  base.sfx(app, all, SFX)
end

-- ---------------------------------------------------------------- the idle screen

local function demoRng(n)
  if n then return math.random(n) end
  return math.random()
end

--- A bakery a little way along, so the idle wall has something to show.
local function demoBakery()
  local s = rules.new({ rng = demoRng })
  s.owned[1], s.owned[2], s.owned[3], s.owned[4] = 12, 8, 4, 1
  s.ups.cursor1, s.ups.grandma1 = true, true
  s.cookies, s.baked, s.allTime = 20000, 60000, 60000
  s.gold.wait = 40
  return s
end

local DEMO_STEPS = 600

function view.demoStep(demo, t)
  if not demo.state or (demo.finishedAt and t - demo.finishedAt > 3000) then
    demo.state, demo.nextAt, demo.finishedAt, demo.steps = demoBakery(), t + 500, nil, 0
    demo.match = { state = demo.state }
    return true
  end
  if demo.finishedAt or t < demo.nextAt then return false end
  demo.nextAt = t + rules.TICK_MS
  demo.steps = demo.steps + 1
  local s = demo.state
  -- the demo taps less than the bot would, so the cookie's pops can be seen
  if demo.steps % 2 == 0 then
    local action = rules.bot(s, demoRng)
    if action then rules.input(s, action) end
  end
  rules.tick(s, demoRng)
  rules.takeHeard(s)
  if demo.steps >= DEMO_STEPS then demo.finishedAt = t end
  return true
end

function view.drawAttract(W, H, demo)
  local L = view.layout(W, H)
  if demo.state then paint(L, demo.state) end
  local fh = L.fh
  local w, h = min(W - 4, 80), fh * 3 + 9
  local x, y = floor((W - w) / 2), floor((H - h) / 2) - 2
  ui.fill(x, y, w, h, C.bg)
  ui.frame(x, y, w, h, C.hi)
  ui.text("COOKIE CLICKER", floor(W / 2), y + 2, C.hi, "center", w - 4)
  ui.small("Bake, buy, ascend. Your bakery bakes on while you're away.", floor(W / 2), y + fh + 3, C.line, C.bg, "center", w - 2)
  return y + fh + 5
end

return base.fill({
  id = "cookie", title = "Cookie Clicker", short = "Cookies", blurb = "Bake a billion cookies, then a trillion",
  color = "hi", accent = 0xFFC94A,
  action = true, story = true, saves = true, tickMs = rules.TICK_MS, minSize = { w = 100, h = 60 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Tap the big cookie to bake. Spend cookies in the store on buildings, which bake for you every second, and on upgrades, which make everything bake faster.",
    "",
    "Each building costs 15% more than the last. x1, x10 and x100 at the top of the store buy that many at once. Green prices you can afford.",
    "",
    "Upgrades show up as you go: owning buildings, tapping, and baking unlock them. ALL lists every one you can buy.",
    "",
    "Now and then a GOLDEN COOKIE appears somewhere on the wall for a few seconds. Tap it fast: it gives a lump of cookies, a 7x frenzy, or a frenzy for taps.",
    "",
    "AWARDS are achievements. Each one adds milk, and kitten upgrades turn milk into more baking.",
    "",
    "Your bakery keeps baking while you're away, at half speed and for a day at most, here or on any other cabinet.",
    "",
    "Once you've baked a trillion cookies in all, ASCEND starts you over with heavenly chips: each one makes all your baking 1% faster, for good.",
  },
})
