-- gearshop/ui.lua
-- What the shop's monitors show: the door, each display chest's own monitor, the search kiosk and the sell point.
-- Nothing here changes the shop or waits for the server. Each draw builds the whole screen in memory, sends only the lines
-- that changed, and leaves a list of buttons; a touch is looked up in that list and handed back to app.lua as an action.
-- Monitors come in any size, so every layout is worked out from the size the monitor reports.

local rules = require("lib.gearshop.rules")

local M = {}

local GRADE_COLOR = {
  SCRAPPY = "8", COMMON = "3", RARE = "4", EPIC = "2", OMEGA = "5", LEGENDARY = "1", UNIQUE = "1", SPECIAL = "9", CHAOTIC = "e",
}
M.RARITIES = { "LEGENDARY", "OMEGA", "EPIC", "RARE", "COMMON", "SCRAPPY" }

-- ---------------------------------------------------------------- a screen

local Screen = {}
Screen.__index = Screen

function M.screen(io, name, scale)
  local self = setmetatable({ io = io, name = name, drawn = {}, buttons = {}, w = 0, h = 0 }, Screen)
  io.call(name, "setTextScale", scale or 0.5)
  self:measure()
  return self
end

function Screen:measure()
  local ok, w, h = self.io.call(self.name, "getSize")
  if ok and type(w) == "number" and type(h) == "number" then
    if w ~= self.w or h ~= self.h then
      -- one clear, and every line is known to be blank: only lines with something on them are sent
      self.drawn = {}
      self.io.call(self.name, "setBackgroundColor", colors.black)
      if self.io.call(self.name, "clear") then
        local blank = (" "):rep(w) .. "\n" .. ("0"):rep(w) .. "\n" .. ("f"):rep(w)
        for y = 1, h do self.drawn[y] = blank end
      end
    end
    self.w, self.h = w, h
    return true
  end
  self.w, self.h = 0, 0
  return false
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

function Screen:box(x, y, w, h, bg)
  for row = y, y + h - 1 do
    if row >= 1 and row <= self.h then self:write(x, row, (" "):rep(w), "0", bg) end
  end
end

function Screen:button(id, value, x, y, w, h, label, fg, bg)
  self:box(x, y, w, h, bg or "7")
  label = tostring(label):sub(1, w)
  self:write(x + math.floor((w - #label) / 2), y + math.floor((h - 1) / 2), label, fg or "0", bg or "7")
  self.buttons[#self.buttons + 1] = { id = id, value = value, x = x, y = y, w = w, h = h, label = label }
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

--- Text wrapped over at most `rows` rows starting at y. Returns the rows used.
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
      self.io.call(self.name, "setCursorPos", 1, y)
      if self.io.call(self.name, "blit", self.text[y], self.fg[y], self.bg[y]) then self.drawn[y] = line end
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

-- ---------------------------------------------------------------- shared pieces

local function buttonHeight(s)
  return s.h >= 16 and 3 or 1
end

--- What a display chest holds, for its monitor: { { label, grade, level, price, n }, ... }, lowest level first.
local function holding(shop, d)
  local ds = shop:ds(d)
  local list = {}
  for key, n in pairs(ds.shown) do
    local piece = shop.stock.known[key]
    list[#list + 1] = {
      key = key, n = n,
      label = piece and piece.label or rules.typeLabel(key:match("^(.-)#") or "gear"),
      grade = piece and rules.grade(piece) or "?",
      level = piece and piece.level or 0,
      price = shop:priceOf(d, key),
    }
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.label ~= b.label then return a.label < b.label end
    return a.key < b.key
  end)
  return list
end

local function pieceRows(s, list, top, bottom, withPrice)
  local rows = bottom - top + 1
  if rows < 1 then return end
  local more = #list - rows
  for i = 1, math.min(#list, rows) do
    local y = top + i - 1
    if more > 0 and i == rows then
      s:write(1, y, "+" .. (more + 1) .. " more in the chest", "8")
    else
      local entry = list[i]
      -- every piece of a type has the same name, so the rarity is spelt out beside the colour
      local grade = entry.grade ~= "?" and (entry.grade:sub(1, 1) .. entry.grade:sub(2):lower() .. " ") or ""
      local tail = grade .. "L" .. entry.level .. (withPrice and (" " .. entry.price .. "t") or "")
      s:write(1, y, entry.label:sub(1, math.max(1, s.w - #tail - 1)), GRADE_COLOR[entry.grade] or "0")
      s:right(y, tail, "8")
    end
  end
end

local function noteRows(s, shop, monitor, y, rows)
  local note = shop:noteFor(monitor)
  if note then s:wrap(y, rows, note, "4") end
end

-- ---------------------------------------------------------------- the door

function M.door(s, shop)
  s:start()
  s:bar(1, "b")
  s:centre(1, "GEAR SHOP", "0", "b")
  local bh = buttonHeight(s)
  local buttonsTop = s.h - bh + 1
  local y = 3
  if not shop.ready then
    s:wrap(y, 2, shop.status .. "...", "8")
    y = y + 2
  else
    local names = {}
    for name in pairs(shop.state.shoppers) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
      y = y + s:wrap(y, 3, "Tap CHECK IN, take what you like from the chests, tap PAY on your way out.", "8")
    end
    for _, name in ipairs(names) do
      if y < buttonsTop - 3 then
        local credit = shop.state.credit[name]
        s:write(1, y, name, "0")
        s:right(y, "tab " .. shop:owes(name) .. (credit and ("  credit " .. rules.showMilli(credit)) or ""), "4")
        y = y + 1
      end
    end
  end
  noteRows(s, shop, s.name, buttonsTop - 3, 3)
  s:row(buttonsTop, bh, {
    { "checkin", nil, s.w >= 30 and "CHECK IN" or "IN", "f", "5" },
    { "pay", nil, "PAY", "f", "4" },
    { "checkout", nil, s.w >= 30 and "CHECK OUT" or "OUT", "0", "e" },
  })
  s:finish()
end

-- ---------------------------------------------------------------- a display chest

--- view: this monitor's own state, { mode = "types"|nil, scroll }
function M.station(s, shop, d, view)
  local ds = shop:ds(d)
  s:start()
  s:bar(1, "b")
  local owner = ds.shopper and shop.state.shoppers[ds.shopper] and ds.shopper
  if not owner then
    s:centre(1, "CHEST " .. d.id, "0", "b")
    if ds.phase then
      s:centre(math.floor(s.h / 2), "Putting gear away...", "8")
    elseif not shop.ready then
      s:wrap(3, 2, "The shop is opening...", "8")
    else
      s:centre(math.max(3, math.floor(s.h / 2) - 1), "TAP TO OPEN", "5")
      s:centre(math.max(4, math.floor(s.h / 2)), "this chest", "8")
      s.buttons[#s.buttons + 1] = { id = "claim", x = 1, y = 2, w = s.w, h = s.h - 4 }
    end
    noteRows(s, shop, s.name, s.h - 2, 3)
    s:finish()
    return
  end

  local price = rules.bracketPrice(ds.bracket or 0, shop.cfg)
  s:write(1, 1, (rules.typeLabel(ds.type or "?") .. " Lv " .. rules.bracketLabel(ds.bracket or 0)):sub(1, s.w - 9), "0", "b")
  s:right(1, " " .. price .. " each", "4", "b")

  local bh = buttonHeight(s)
  local buttonsTop = s.h - bh + 1
  if view.mode == "types" then
    local types = shop.stock:typesNear(ds.bracket or 0)
    local rows = buttonsTop - 3
    view.scroll = math.max(0, math.min(view.scroll or 0, math.max(0, #types - rows)))
    for i = 1, math.min(rows, #types - view.scroll) do
      local t = types[i + view.scroll]
      local label = rules.typeLabel(t.type)
      s:button("settype", t.type, 1, 1 + i, s.w, 1,
        label .. (" "):rep(math.max(1, s.w - #label - 8)) .. ("%4d"):format(shop.stock:summary().types[t.type].total),
        t.type == ds.type and "5" or "0", "f")
    end
    local specs = { { "back", nil, "BACK", "0", "7" } }
    if #types > rows then
      specs[#specs + 1] = { "scroll", -rows, "UP", "0", "7" }
      specs[#specs + 1] = { "scroll", rows, "DOWN", "0", "7" }
    end
    s:row(buttonsTop, bh, specs)
    s:finish()
    return
  end

  local listBottom = buttonsTop - 4
  if ds.phase ~= "open" then
    s:centre(math.floor(s.h / 2), "Fetching gear...", "8")
  else
    local list = holding(shop, d)
    if #list == 0 then
      s:wrap(3, 3, (ds.total or 0) == 0 and "None in stock at this level. Try another level or type."
        or "This chest is empty. NEXT brings more.", "8")
    else
      pieceRows(s, list, 2, listBottom, false)
    end
  end
  s:write(1, buttonsTop - 3, ("For " .. owner):sub(1, s.w), "8")
  s:right(buttonsTop - 3, "page " .. (ds.page or 1) .. "/" .. (ds.pages or 1), "8")
  noteRows(s, shop, s.name, buttonsTop - 2, 2)
  local wide = s.w >= 30
  s:row(buttonsTop, bh, {
    { "types", nil, "TYPE", "0", "b" },
    { "level", -1, wide and "LV -" or "-", "0", "7" },
    { "level", 1, wide and "LV +" or "+", "0", "7" },
    { "next", nil, s.w >= 49 and "NEXT PAGE" or "NEXT", "f", "5" },   -- five buttons share the width
    { "done", nil, "DONE", "0", "e" },
  })
  s:finish()
end

-- ---------------------------------------------------------------- the search kiosk

local KEY_ROWS = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }

--- view: { mode = nil|"types"|"keys", query = { type, bracket, rarity, text }, scroll }
function M.kiosk(s, shop, d, view)
  local ds = shop:ds(d)
  view.query = view.query or {}
  local q = view.query
  s:start()
  s:bar(1, "b")
  s:write(1, 1, "SEARCH", "0", "b")
  local owner = ds.shopper and shop.state.shoppers[ds.shopper] and ds.shopper
  if owner then s:right(1, owner, "4", "b") end
  local bh = buttonHeight(s)
  local buttonsTop = s.h - bh + 1

  if view.mode == "types" then
    local list = shop.stock:summary().typeList
    local rows = buttonsTop - 3
    view.scroll = math.max(0, math.min(view.scroll or 0, math.max(0, #list + 1 - rows)))
    for i = 1, math.min(rows, #list + 1 - view.scroll) do
      local index = i + view.scroll - 1
      if index == 0 then
        s:button("settype", false, 1, 1 + i, s.w, 1, "Any type", q.type == nil and "5" or "0", "f")
      else
        s:button("settype", list[index], 1, 1 + i, s.w, 1, rules.typeLabel(list[index]), list[index] == q.type and "5" or "0", "f")
      end
    end
    local specs = { { "back", nil, "BACK", "0", "7" } }
    if #list + 1 > rows then
      specs[#specs + 1] = { "scroll", -rows, "UP", "0", "7" }
      specs[#specs + 1] = { "scroll", rows, "DOWN", "0", "7" }
    end
    s:row(buttonsTop, bh, specs)
    s:finish()
    return
  end

  if view.mode == "keys" then
    s:write(1, 3, "Name or modifier:", "8")
    s:write(1, 4, "> " .. (q.text or "") .. "_", "0")
    local kw = math.max(2, math.min(4, math.floor(s.w / 10)))
    for r, row in ipairs(KEY_ROWS) do
      local y = 5 + (r - 1) * 2 + 1
      local x = 1 + math.floor((s.w - #row * kw) / 2)
      for i = 1, #row do
        local ch = row:sub(i, i)
        s:button("key", ch:lower(), x + (i - 1) * kw, y, kw - 1, 1, ch, "0", "7")
      end
    end
    s:row(buttonsTop, bh, {
      { "key", " ", "SPACE", "0", "7" },
      { "key", "del", "DEL", "0", "e" },
      { "back", nil, "OK", "f", "5" },
    })
    s:finish()
    return
  end

  s:button("types", nil, 1, 3, s.w, 1, "Type:   " .. (q.type and rules.typeLabel(q.type) or "Any"), "0", "7")
  s:button("bracket", nil, 1, 4, s.w, 1, "Level:  " .. (q.bracket and rules.bracketLabel(q.bracket) or "Any"), "0", "7")
  s:button("rarity", nil, 1, 5, s.w, 1, "Rarity: " .. (q.rarity or "Any"), "0", "7")
  s:button("keys", nil, 1, 6, s.w, 1, "Text:   " .. ((q.text and q.text ~= "") and q.text or "(tap to type)"), "0", "7")
  local listBottom = buttonsTop - 4
  if owner and ds.phase == "open" then
    local list = holding(shop, d)
    s:write(1, 8, ((ds.total or 0) .. " found, page " .. (ds.page or 1) .. "/" .. (ds.pages or 1)):sub(1, s.w), "8")
    pieceRows(s, list, 9, listBottom, true)
  elseif ds.phase then
    s:write(1, 8, "Fetching gear...", "8")
  else
    s:wrap(8, 3, "Pick what you are after, tap FIND, and it is brought to the chest here.", "8")
  end
  noteRows(s, shop, s.name, buttonsTop - 3, 3)
  s:row(buttonsTop, bh, {
    { "find", nil, "FIND", "f", "5" },
    { "next", nil, s.w >= 30 and "NEXT PAGE" or "NEXT", "0", "b" },
    { "done", nil, "DONE", "0", "e" },
  })
  s:finish()
end

--- A touch on the kiosk that only changes what is being typed or picked. Returns true if it was one of those.
function M.kioskTouch(view, button)
  view.query = view.query or {}
  local q = view.query
  if button.id == "types" then
    view.mode, view.scroll = "types", 0
  elseif button.id == "keys" then
    view.mode = "keys"
  elseif button.id == "back" then
    view.mode = nil
  elseif button.id == "scroll" then
    view.scroll = (view.scroll or 0) + button.value
  elseif button.id == "settype" then
    q.type = button.value or nil
    view.mode = nil
  elseif button.id == "bracket" then
    if q.bracket == nil then q.bracket = 0 elseif q.bracket >= 10 then q.bracket = nil else q.bracket = q.bracket + 1 end
  elseif button.id == "rarity" then
    local at = 0
    for i, rarity in ipairs(M.RARITIES) do
      if rarity == q.rarity then at = i end
    end
    q.rarity = M.RARITIES[at + 1]
  elseif button.id == "key" then
    local text = q.text or ""
    if button.value == "del" then
      text = text:sub(1, -2)
    elseif #text < 24 then
      text = text .. button.value
    end
    q.text = text
  else
    return false
  end
  return true
end

-- ---------------------------------------------------------------- the sell point

function M.sell(s, shop)
  s:start()
  s:bar(1, "b")
  s:centre(1, "SELL GEAR", "0", "b")
  local bh = buttonHeight(s)
  local buttonsTop = s.h - bh + 1
  local view = shop.sellView
  local y = 3
  local cfg = shop.cfg
  local tokens = rules.sellsForTokens(cfg)  -- off: store credit is the only way a sale is paid
  if not shop.ready then
    s:wrap(y, 2, "The shop is opening...", "8")
  elseif not view or (#view.accepted + #view.rejected + #view.returns) == 0 then
    y = y + s:wrap(y, 4, "Put gear in the chest. The shop buys Epic, Omega and Legendary; above level "
      .. cfg.highLevel .. " Omega and Legendary; at " .. cfg.topLevel .. " Legendary only.", "8")
    if tokens then
      s:wrap(y + 1, 3, cfg.piecesPerToken .. " pieces make 1 token, or " .. cfg.creditMultiplier .. " in store credit.", "8")
    else
      s:wrap(y + 1, 3, "The shop pays in store credit: " .. rules.showMilli(rules.creditMilli(1, cfg))
        .. " a piece, spent on gear here.", "8")
    end
  else
    local n = #view.accepted
    s:write(1, y, "Buying: " .. n, "5")
    y = y + 1
    if tokens then
      s:write(1, y, " tokens " .. rules.showMilli(n * rules.pieceMilli(cfg)), "0")
      y = y + 1
      s:write(1, y, " or store credit " .. rules.showMilli(rules.creditMilli(n, cfg)), "0")
    else
      -- wrapped, so the whole amount shows on a narrow sell monitor too
      y = y + s:wrap(y, 2, "You get " .. rules.showMilli(rules.creditMilli(n, cfg)) .. " store credit", "0") - 1
    end
    y = y + 2
    if #view.returns > 0 then
      s:write(1, y, "Back off a tab: " .. #view.returns, "4")
      y = y + 1
    end
    if #view.rejected > 0 then
      s:write(1, y, "Not wanted: " .. #view.rejected .. " (take them back)", "e")
      y = y + 1
      for _, entry in ipairs(view.rejected) do
        if y < buttonsTop - 4 then
          -- every piece of a type has the same name, so its level and rarity say which one is meant
          local what = entry.grade and ("L" .. tostring(entry.level) .. " " .. entry.grade:sub(1, 1) .. entry.grade:sub(2):lower()) or entry.label
          s:write(2, y, (what .. ": " .. tostring(entry.why)):sub(1, s.w - 1), "8")
          y = y + 1
        end
      end
    end
  end
  noteRows(s, shop, s.name, buttonsTop - 3, 3)
  if tokens then
    s:row(buttonsTop, bh, {
      { "tokens", nil, "TOKENS", "f", "4" },
      { "credit", nil, s.w >= 30 and "STORE CREDIT x" .. cfg.creditMultiplier or "CREDIT", "f", "5" },
    })
  else
    s:row(buttonsTop, bh, { { "credit", nil, s.w >= 22 and "SELL FOR STORE CREDIT" or (s.w >= 12 and "STORE CREDIT" or "CREDIT"), "f", "5" } })
  end
  s:finish()
end

return M
