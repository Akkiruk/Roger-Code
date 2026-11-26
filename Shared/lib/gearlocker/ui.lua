-- gearlocker/ui.lua
-- The locker's pages: home, bad gear, upgrades, the build picker and settings. Each draw builds the whole screen in
-- memory, sends only the lines that changed and leaves a list of buttons; app.lua looks a touch up in that list.
-- Nothing here moves items or waits for the server. Every layout comes from the size the screen reports, so the same
-- pages work on a 4x4 monitor at scale 1 (39x26), a 2x2 at 0.5 and on the computer's own terminal (51x19).

local rules = require("lib.gearshop.rules")
local builds = require("lib.gearshop.builds")

local M = {}

M.SLOTS = { "head", "chest", "legs", "feet", "weapon", "offhand", "magnet" }
M.SLOT_NAMES = { head = "Helmet", chest = "Chestplate", legs = "Leggings", feet = "Boots", weapon = "Weapon",
  offhand = "Offhand", magnet = "Magnet" }
M.RARITIES = { "SCRAPPY", "COMMON", "RARE", "EPIC", "OMEGA" }
local RARITY_FG = { SCRAPPY = "8", COMMON = "0", RARE = "4", EPIC = "2", OMEGA = "5", LEGENDARY = "1" }

local Screen = {}
Screen.__index = Screen

local SCALES = { 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5 }

-- Biggest text that still leaves 39x18 (a 4x4 at scale 1), else 0.5. Worked out from the current size with CC's
-- monitor formula instead of trying each scale, since every setTextScale fires monitor_resize and app.lua
-- re-attaches on that.
function M.pickScale(w, h, cur)
  local bw = (w * 6 * cur + 20) / 64
  local bh = (h * 9 * cur + 20) / 64
  for _, sc in ipairs(SCALES) do
    local cw = math.floor((bw * 64 - 20) / (6 * sc) + 0.5)
    local ch = math.floor((bh * 64 - 20) / (9 * sc) + 0.5)
    if cw >= 39 and ch >= 18 then return sc end
  end
  return 0.5
end

--- target: a wrapped monitor or term. A monitor that goes away mid-draw only makes that draw fail.
--- Monitors pick their own scale; scale is only used when the monitor can't say what it's at.
function M.screen(target, scale)
  local self = setmetatable({ t = target, drawn = {}, buttons = {}, w = 0, h = 0 }, Screen)
  if target.setTextScale then
    local ok, cur = pcall(target.getTextScale)
    local okSize, w, h = pcall(target.getSize)
    if ok and type(cur) == "number" and okSize and type(w) == "number" then
      local want = M.pickScale(w, h, cur)
      if want ~= cur then pcall(target.setTextScale, want) end
    elseif scale then
      pcall(target.setTextScale, scale)
    end
  end
  self:measure()
  return self
end

function Screen:measure()
  local ok, w, h = pcall(self.t.getSize)
  if not ok or type(w) ~= "number" then
    self.w, self.h = 0, 0
    return false
  end
  if w ~= self.w or h ~= self.h then
    self.drawn = {}
    pcall(self.t.setBackgroundColor, colors.black)
    pcall(self.t.clear)
  end
  self.w, self.h = w, h
  return true
end

function Screen:start()
  self.text, self.fg, self.bg, self.buttons = {}, {}, {}, {}
  for y = 1, self.h do
    self.text[y] = (" "):rep(self.w)
    self.fg[y] = ("0"):rep(self.w)
    self.bg[y] = ("f"):rep(self.w)
  end
end

local function splice(line, x, piece)
  return line:sub(1, x - 1) .. piece .. line:sub(x + #piece)
end

function Screen:write(x, y, text, fg, bg)
  if y < 1 or y > self.h or x > self.w then return end
  text = tostring(text)
  if x < 1 then
    text = text:sub(2 - x)
    x = 1
  end
  text = text:sub(1, self.w - x + 1)
  if #text == 0 then return end
  self.text[y] = splice(self.text[y], x, text)
  self.fg[y] = splice(self.fg[y], x, (fg or "0"):rep(#text))
  if bg then self.bg[y] = splice(self.bg[y], x, bg:rep(#text)) end
end

function Screen:right(y, text, fg, bg)
  self:write(self.w - #text + 1, y, text, fg, bg)
end

function Screen:centre(y, text, fg, bg)
  self:write(math.max(1, math.floor((self.w - #text) / 2) + 1), y, text, fg, bg)
end

function Screen:bar(y, bg)
  if y >= 1 and y <= self.h then self.bg[y] = bg:rep(self.w) end
end

function Screen:button(id, value, x, y, w, h, label, fg, bg)
  for row = y, y + h - 1 do self:write(x, row, (" "):rep(w), "0", bg or "7") end
  label = tostring(label):sub(1, w)
  self:write(x + math.floor((w - #label) / 2), y + math.floor((h - 1) / 2), label, fg or "0", bg or "7")
  self.buttons[#self.buttons + 1] = { id = id, value = value, x = x, y = y, w = w, h = h }
end

--- A row of buttons sharing the width. specs: { { id, value, label, fg, bg }, ... }
function Screen:row(y, h, specs)
  local n = #specs
  if n == 0 then return end
  local each = math.floor((self.w - (n - 1)) / n)
  local x = 1
  for i, spec in ipairs(specs) do
    local w = i == n and (self.w - x + 1) or each
    self:button(spec[1], spec[2], x, y, w, h, spec[3], spec[4], spec[5])
    x = x + w + 1
  end
end

function Screen:wrap(y, rows, text, fg)
  local used, line = 0, ""
  for word in tostring(text):gmatch("%S+") do
    if #line + #word + 1 > self.w and #line > 0 then
      if used < rows then self:write(1, y + used, line, fg) end
      used = used + 1
      line = word
    else
      line = #line > 0 and (line .. " " .. word) or word
    end
  end
  if #line > 0 then
    if used < rows then self:write(1, y + used, line, fg) end
    used = used + 1
  end
  return math.min(used, rows)
end

function Screen:finish()
  for y = 1, self.h do
    local line = self.text[y] .. "\n" .. self.fg[y] .. "\n" .. self.bg[y]
    if self.drawn[y] ~= line then
      local ok = pcall(function()
        self.t.setCursorPos(1, y)
        self.t.blit(self.text[y], self.fg[y], self.bg[y])
      end)
      self.drawn[y] = ok and line or nil
    end
  end
end

function Screen:hit(x, y)
  for i = #self.buttons, 1, -1 do
    local b = self.buttons[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b end
  end
  return nil
end

local function bh(s) return s.h >= 30 and 4 or s.h >= 16 and 3 or 1 end

local function title(s, text, extra)
  s:bar(1, "b")
  s:write(2, 1, text, "0", "b")
  if extra then s:right(1, extra .. " ", "0", "b") end
end

local function ago(ms)
  if not ms then return "never" end
  local secs = math.max(0, math.floor((os.epoch("utc") - ms) / 1000))
  if secs < 60 then return "just now" end
  if secs < 3600 then return math.floor(secs / 60) .. "m ago" end
  return math.floor(secs / 3600) .. "h ago"
end
M.ago = ago

local function grade(piece)
  local g = rules.grade(piece)
  return g:sub(1, 1) .. g:sub(2):lower(), RARITY_FG[g] or "0"
end

local function fit(text, w)
  text = tostring(text)
  if #text <= w then return text end
  return w > 1 and (text:sub(1, w - 1) .. ".") or text:sub(1, w)
end

-- the note (last thing that happened) and what is busy, just above the buttons
local function footer(s, st, y)
  if st.busy then
    local p = st.progress
    local msg = st.busy .. ((p and p.total and p.total > 0) and (" " .. p.done .. "/" .. p.total) or "") .. "..."
    s:write(1, y, fit(msg, s.w), "4")
  elseif st.note then
    s:write(1, y, fit(st.note, s.w), st.noteFg or "8")
  elseif s.isTerm then
    -- the only way to add nodes after the first setup, so say it somewhere
    s:write(1, y, fit("Press S to run setup again", s.w), "8")
  end
end

function M.buildLabel(id)
  if id == "gs" then return "Best Gear Score" end
  return builds.LABELS[id] or tostring(id or "?")
end

-- ---------------------------------------------------------------- home

function M.home(s, st)
  s:start()
  title(s, "GEAR LOCKER", st.player)
  local b = bh(s)
  local top = s.h - b + 1
  local y = 3
  local n = #(st.pieces or {})
  s:write(2, y, n .. " pieces in ME", "0")
  s:right(y, "last scan " .. ago(st.lastScan) .. " ", "8")
  y = y + 2

  -- gear per slot, two columns where there is room
  local counts = st.slotCounts or {}
  local cols = s.w >= 40 and 2 or 1
  local colW = math.floor((s.w - 2) / cols)
  local rows = math.ceil(#M.SLOTS / cols)
  for i, slot in ipairs(M.SLOTS) do
    local col, row = math.floor((i - 1) / rows), (i - 1) % rows
    local x = 2 + col * colW
    s:write(x, y + row, M.SLOT_NAMES[slot], "8")
    local c = tostring(counts[slot] or 0)
    s:write(x + colW - #c - 2, y + row, c, "0")
  end
  y = y + rows + 1

  if st.missing and #st.missing > 0 then
    y = y + s:wrap(y, 2, "Missing: " .. table.concat(st.missing, ", "), "e")
  end
  if st.nodes and #st.nodes > 0 and y < top - 2 then
    -- one tag per node computer, red when it's unloaded
    s:write(2, y, "Nodes:", "8")
    local x = 9
    for _, nd in ipairs(st.nodes) do
      local tag = "#" .. tostring(nd.id) .. (nd.loaded and "" or " off")
      if x + #tag > s.w and x > 9 then
        y, x = y + 1, 9
        if y >= top - 2 then break end
      end
      s:write(x, y, tag, nd.loaded and "5" or "e")
      x = x + #tag + 1
    end
    y = y + 1
  end
  if y < top - 2 then
    local buildText = "Build: " .. M.buildLabel(st.buildId) .. (st.picked and "" or " (guess)")
    s:write(2, y, fit(buildText, s.w - 2), "3")
    y = y + 1
  end
  if y < top - 2 and st.readWhy then
    s:write(2, y, fit(st.readWhy, s.w - 2), "8")
    y = y + 1
  elseif y < top - 2 and st.limited then
    s:write(2, y, fit("Upgrades need vhcctweaks 2.2.37 on the server", s.w - 2), "8")
    y = y + 1
  end
  footer(s, st, top - 1)

  local junkN, upN = #(st.junk or {}), st.upgradeSlots or 0
  local wide = s.w >= 48
  s:row(top, b, {
    { "scan", nil, "SCAN", "f", st.canScan and "5" or "7" },
    { "page", "bad", (wide and "BAD GEAR " or "BAD ") .. junkN, junkN > 0 and "0" or "8", junkN > 0 and "e" or "7" },
    { "page", "up", (wide and "UPGRADES " or "UP ") .. upN, upN > 0 and "f" or "8", upN > 0 and "4" or "7" },
    { "page", "settings", wide and "SETTINGS" or "SET", "0", "7" },
  })
  s:finish()
end

-- ---------------------------------------------------------------- bad gear

--- What the bad gear page lists: the junk, then what the player spared (so a tap can undo it).
function M.badRows(st)
  local list = {}
  for _, j in ipairs(st.junk or {}) do list[#list + 1] = { piece = j.piece, reason = j.reason } end
  for _, p in ipairs(st.sparedPieces or {}) do list[#list + 1] = { piece = p, spared = true } end
  return list
end

-- narrow but tall screens (a 4x4 at scale 1) get the reason on its own line instead of cutting both in half
local function badTwoLine(s)
  return s.w < 45 and (s.h - 3 - bh(s) - 1) >= 16
end

function M.badPerPage(s)
  local rows = math.max(1, s.h - 3 - bh(s) - 1)
  return badTwoLine(s) and math.floor(rows / 2) or rows
end

function M.bad(s, st)
  s:start()
  local list = M.badRows(st)
  local per = M.badPerPage(s)
  local pages = math.max(1, math.ceil(#list / per))
  st.badPage = math.max(1, math.min(st.badPage or 1, pages))
  title(s, "BAD GEAR", #(st.junk or {}) .. " to pull")
  s:write(1, 2, fit("Tap a piece to keep it. Nothing is destroyed: PULL moves it to the junk chest.", s.w), "8")
  local b = bh(s)
  local top = s.h - b + 1
  if #list == 0 then
    s:centre(math.floor(top / 2) + 1, "Nothing to pull.", "5")
  end
  local two = badTwoLine(s)
  local reasonW = two and s.w - 2 or math.min(24, math.floor(s.w * 0.4))
  for i = 1, per do
    local row = list[(st.badPage - 1) * per + i]
    if not row then break end
    local y = two and (1 + i * 2) or (2 + i)
    local p = row.piece
    local g, gfg = grade(p)
    local lvl = "lv" .. tostring(p.level or 0)
    local right = row.spared and "kept by you" or tostring(row.reason or "")
    right = fit(right, reasonW)
    local nameW = s.w - #lvl - #g - (two and 2 or reasonW + 4)
    s:write(1, y, fit(p.label or p.type or "?", nameW), row.spared and "8" or "0")
    s:write(nameW + 2, y, lvl, "8")
    s:write(nameW + 3 + #lvl, y, g, gfg)
    if two then
      s:write(3, y + 1, right, row.spared and "5" or "e")
    else
      s:right(y, right, row.spared and "5" or "e")
    end
    s.buttons[#s.buttons + 1] = { id = "spare", value = p.fp, on = not row.spared, x = 1, y = y, w = s.w, h = two and 2 or 1 }
  end
  footer(s, st, top - 1)
  if pages > 1 then s:right(top - 1, " " .. st.badPage .. "/" .. pages, "8") end
  local n = #(st.junk or {})
  s:row(top, b, {
    { "back", nil, "BACK", "0", "7" },
    { "badprev", nil, "<", st.badPage > 1 and "0" or "8", "7" },
    { "badnext", nil, ">", st.badPage < pages and "0" or "8", "7" },
    { "pull", nil, "PULL ALL " .. n, n > 0 and st.canPull and "0" or "8", n > 0 and st.canPull and "e" or "7" },
  })
  s:finish()
end

-- ---------------------------------------------------------------- upgrades

local function gainText(e)
  if not e then return "" end
  if e.delta then return "+" .. math.floor(e.delta + 0.5) .. " fit" end
  if e.gain then return "+" .. math.floor(e.gain + 0.5) .. " GS" end
  return ""
end

function M.upgrades(s, st)
  s:start()
  title(s, "UPGRADES", M.buildLabel(st.buildId))
  local b = bh(s)
  local top = s.h - b + 1
  local why = st.readWhy or (st.picked and "Your pick" or ("Guess: " .. tostring(st.buildWhy or "")))
  if st.limited and not st.readWhy then why = why .. " (rough, server lacks 2.2.37)" end
  local y = 2 + s:wrap(2, 2, why, "8")
  local best = st.best or {}
  -- two lines a slot when there is room: what is best, then what is worn
  local room = top - 1 - y
  local tall = room >= #M.SLOTS * 2
  local takeW = 6
  for _, slot in ipairs(M.SLOTS) do
    if y >= top - 1 then break end
    local e = best[slot]
    s:write(1, y, M.SLOT_NAMES[slot], "3")
    local x = 12
    local w = s.w - x - takeW - 1
    if e then
      local p = e.piece
      local g, gfg = grade(p)
      local gain = gainText(e) .. (e.later and (" at " .. (p.level or 0)) or "")
      local ok = st.canTake
      if tall then
        -- name up top, the rest underneath so narrow screens still fit it all
        s:write(x, y, fit(p.label or "?", w), "0")
        local lv = "lv" .. (p.level or 0)
        s:write(3, y + 1, lv, "8")
        s:write(4 + #lv, y + 1, g, gfg)
        local gx = 5 + #lv + #g
        s:write(gx, y + 1, gain, e.later and "8" or "5")
        local worn = e.worn
        local wtxt = worn and ("now " .. (worn.label or "?") .. " lv" .. (worn.level or 0)) or "now nothing"
        local wx = gx + #gain + 2
        s:write(wx, y + 1, fit(wtxt, s.w - takeW - wx), "8")
        s:button("take", p.fp, s.w - takeW + 1, y, takeW, 2, "TAKE", ok and "f" or "8", ok and "4" or "7")
      else
        local txt = fit(p.label or "?", w - 14)
        s:write(x, y, txt, "0")
        s:write(x + #txt + 1, y, "lv" .. (p.level or 0), "8")
        s:write(x + w - #gain, y, gain, e.later and "8" or "5")
        s:button("take", p.fp, s.w - takeW + 1, y, takeW, 1, "TAKE", ok and "f" or "8", ok and "4" or "7")
      end
    else
      s:write(x, y, (st.counts and (st.counts[slot] or 0) > 0) and "see list" or "nothing better", "8")
    end
    y = y + (tall and 2 or 1)
  end
  footer(s, st, top - 1)
  s:row(top, b, {
    { "back", nil, "BACK", "0", "7" },
    { "page", "builds", "CHANGE BUILD", "f", "3" },
  })
  s:finish()
end

-- ---------------------------------------------------------------- build picker

function M.buildChoices()
  local out = {}
  for _, id in ipairs(builds.ORDER) do out[#out + 1] = { id = id, label = builds.LABELS[id] } end
  out[#out + 1] = { id = "gs", label = "Best Gear Score" }
  out[#out + 1] = { id = false, label = "Let it guess" }
  return out
end

function M.builds(s, st)
  s:start()
  title(s, "PICK YOUR BUILD")
  local b = bh(s)
  local top = s.h - b + 1
  local choices = M.buildChoices()
  local cols = (top - 4 < #choices) and 2 or 1
  local per = math.ceil(#choices / cols)
  local colW = math.floor((s.w - (cols - 1)) / cols)
  -- taller buttons with a gap when the screen has the rows for it
  local step = math.max(1, math.min(4, math.floor((top - 4) / per)))
  local hgt = step > 1 and step - 1 or 1
  for i, c in ipairs(choices) do
    local col, row = math.floor((i - 1) / per), (i - 1) % per
    local y = 3 + row * step
    if y + hgt - 1 < top - 1 then
      local on = (c.id == false and not st.picked) or (c.id and st.picked and st.buildId == c.id)
      s:button("build", c.id, 1 + col * (colW + 1), y, colW, hgt, fit(c.label, colW - 2), on and "f" or "0", on and "5" or "7")
    end
  end
  footer(s, st, top - 1)
  s:row(top, b, { { "page", "up", "BACK", "0", "7" } })
  s:finish()
end

-- ---------------------------------------------------------------- settings

--- The settings rows: { label, value text, key }, each with - and + (or a toggle) on the right.
function M.settingRows(r)
  return {
    { "Keep best per slot", tostring(r.keepPerSlot), "keepPerSlot" },
    { "Junk lvls under you", tostring(r.maxBelow), "maxBelow" },
    { "Lowest rarity kept", tostring(r.minRarity), "minRarity" },
    { "Keep legendary", r.keepLegendary and "ON" or "OFF", "keepLegendary", toggle = true },
    { "Auto pull", r.auto and "ON" or "OFF", "auto", toggle = true },
    { "Auto pull every", math.floor((r.autoEvery or 300) / 60) .. " min", "autoEvery" },
  }
end

function M.settings(s, st)
  s:start()
  title(s, "SETTINGS")
  local b = bh(s)
  local top = s.h - b + 1
  local r = st.rules or {}
  local y = 3
  local gap = (top - 3 >= 12) and 2 or 1
  for _, row in ipairs(M.settingRows(r)) do
    if y >= top - 1 then break end
    s:write(2, y, fit(row[1], s.w - 20), "0")
    if row.toggle then
      local on = row[2] == "ON"
      s:button("set", row[3], s.w - 12, y, 12, 1, row[2], on and "f" or "0", on and "5" or "7")
    else
      s:button("dec", row[3], s.w - 18, y, 3, 1, "-", "0", "7")
      local v = row[2]
      s:write(s.w - 14 + math.floor((10 - #v) / 2), y, v, "4")
      s:button("inc", row[3], s.w - 3, y, 3, 1, "+", "0", "7")
    end
    y = y + gap
  end
  if y < top - 1 then
    s:write(2, y, fit((st.sparedCount or 0) .. " pieces kept by you", s.w - 14), "8")
    if (st.sparedCount or 0) > 0 then s:button("unspareall", nil, s.w - 12, y, 12, 1, "FORGET", "0", "7") end
  end
  footer(s, st, top - 1)
  s:row(top, b, { { "back", nil, "BACK", "0", "7" } })
  s:finish()
end

-- ---------------------------------------------------------------- not ready yet

function M.waiting(s, text)
  s:start()
  title(s, "GEAR LOCKER")
  s:wrap(3, s.h - 3, text, "8")
  s:finish()
end

M.PAGES = { home = M.home, bad = M.bad, up = M.upgrades, builds = M.builds, settings = M.settings }

function M.draw(s, st)
  if s.w == 0 and not s:measure() then return end
  local page = M.PAGES[st.page] or M.home
  page(s, st)
end

return M
