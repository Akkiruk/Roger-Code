-- gearshop/ui.lua
-- What the shop's monitors show: the door, each display chest's own monitor, the search kiosk, the sell point and the
-- how-it-works screen.
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
      local tail = grade .. "L" .. entry.level .. (withPrice and (" " .. entry.price .. "t") or "")      s:write(1, y, entry.label:sub(1, math.max(1, s.w - #tail - 1)), GRADE_COLOR[entry.grade] or "0")
      s:right(y, tail, "8")
    end
  end
end

local function noteRows(s, shop, monitor, y, rows)
  local note = shop:noteFor(monitor)
  if note then
    -- the rows are cleared first: on a small screen they may hold other text, whose tail would show past a short note
    for row = y, y + rows - 1 do s:write(1, row, (" "):rep(s.w), "0", "f") end
    s:wrap(y, rows, note, "4")
  end
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
      y = y + s:wrap(y, 3, "Tap any station to start shopping. PAY here or at any station.", "8")
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
-- The shopper opens the chest to see the gear, so its monitor lists none of it. It says what the chest is showing, the
-- price of a piece, the shopper's own tab and store credit, and which page this is; its buttons change the type, the
-- level and the page, and give the chest back. The main target is a 2x1 monitor flush in the floor in front of the chest
-- (36x10 at scale 0.5); every size gets the same screen, bigger where there is room.

--- Rows of buttons from the bottom of the screen up, each bh lines high. Returns the top line of the first row.
local function buttonRows(s, rows, bh)
  local top = s.h - bh * #rows + 1
  for i, specs in ipairs(rows) do s:row(top + (i - 1) * bh, bh, specs) end
  return top
end

--- Lines of text centred in the rows from top to bottom, with a blank row between them when there is room.
-- lines: { { text, fg }, ... }; a line too wide is wrapped, and its rows stay together.
local function centred(s, top, bottom, lines)
  local rows = {}
  for idx, line in ipairs(lines) do
    local text, piece = line[1], ""
    for word in text:gmatch("%S+") do
      if #piece > 0 and #piece + 1 + #word > s.w then
        rows[#rows + 1] = { piece, line[2], idx }
        piece = word
      else
        piece = #piece > 0 and (piece .. " " .. word) or word
      end
    end
    if #piece > 0 then rows[#rows + 1] = { piece, line[2], idx } end
  end
  local room = bottom - top + 1
  -- too many: the first lines give way, so a note (always last) is never cut
  while #rows > math.max(0, room) do table.remove(rows, 1) end
  -- a blank row between lines, not between the rows of one wrapped line
  local gaps = 0
  for i = 2, #rows do
    if rows[i][3] ~= rows[i - 1][3] then gaps = gaps + 1 end
  end
  local spaced = #rows + gaps <= room
  local used = spaced and (#rows + gaps) or math.min(#rows, room)
  local y = top + math.floor((room - used) / 2)
  for i, row in ipairs(rows) do
    if y > bottom then break end
    if spaced and i > 1 and row[3] ~= rows[i - 1][3] then y = y + 1 end
    s:centre(y, row[1]:sub(1, s.w), row[2])
    y = y + 1
  end
end

--- view: this monitor's own state, { mode = "types"|nil, scroll }
function M.station(s, shop, d, view)
  local ds = shop:ds(d)
  s:start()
  s:bar(1, "b")
  local owner = ds.shopper and shop.state.shoppers[ds.shopper] and ds.shopper
  if not owner then
    if d.gearType then
      -- a station of one type is titled with it even when nobody is at it
      local title = rules.typePlural(d.gearType):upper()
      local long = title .. " - tap to browse"
      s:centre(1, #long <= s.w and long or title:sub(1, s.w), "0", "b")
    else
      s:centre(1, (d.category and (d.category:upper() .. " ") or "CHEST ") .. d.id, "0", "b")
    end
    if not shop.ready then
      s:wrap(3, 2, "The shop is opening...", "8")
      noteRows(s, shop, s.name, s.h - 2, 3)
      s:finish()
      return
    end
    -- PAY is on every station's screen, free or not: a tap anywhere else opens it
    s.buttons[#s.buttons + 1] = { id = "claim", x = 1, y = 1, w = s.w, h = s.h }
    local idleBh = s.h >= 16 and 3 or 2
    local buttonsTop = buttonRows(s, { { { "pay", nil, "PAY", "f", "4" } } }, idleBh)
    local lines = {}
    if ds.phase then
      lines[#lines + 1] = { "Putting gear away...", "8" }
    else
      lines[#lines + 1] = { "TAP TO OPEN", "5" }
      local sub = "this chest"
      if d.gearType then
        local t = rules.typeCounts(shop.stock:summary(), d.gearType)
        sub = t and (t.total .. " in stock") or "none in stock"
      end
      lines[#lines + 1] = { sub, "8" }
    end
    local note = shop:noteFor(s.name)
    if note then lines[#lines + 1] = { note, "4" } end
    centred(s, 2, buttonsTop - 1, lines)
    s:finish()
    return
  end

  local narrow = s.w < 24
  local bh = s.h >= 16 and 3 or 2
  -- each piece costs its own level's price: the screen shows the range of what is in the chest ("40-49 each"),
  -- or of the level it is showing while nothing is in it yet
  local low, high
  for key in pairs(ds.shown) do
    local p = shop:priceOf(d, key)
    if not low or p < low then low = p end
    if not high or p > high then high = p end
  end
  if not low then low, high = rules.bracketPrices(ds.bracket or 0, shop.cfg) end
  local kind = rules.typeLabel(ds.type or "?")
  local level = "Lv " .. rules.bracketLabel(ds.bracket or 0)
  local each = rules.priceRange(low, high) .. " each"
  local top
  if narrow then
    -- one block across: the type on its own line, the level and the price under it
    s:centre(1, kind:sub(1, s.w), "0", "b")
    s:bar(2, "b")
    s:write(1, 2, level, "0", "b")
    s:right(2, each, "4", "b")
    top = 3
  else
    local title = kind .. " " .. level
    s:write(1, 1, title:sub(1, s.w - #each - 1), "0", "b")
    s:right(1, each, "4", "b")
    top = 2
  end

  if view.mode == "types" then
    local types = shop:typesFor(d, ds.bracket or 0)
    local cols = math.max(1, math.floor(s.w / 16))
    local buttonsTop = s.h - bh + 1
    local perCol = math.max(1, math.floor((buttonsTop - top) / bh))
    local page = perCol * cols
    view.scroll = math.max(0, math.min(view.scroll or 0, math.max(0, #types - page)))
    local colW = math.floor((s.w - (cols - 1)) / cols)
    for i = 1, math.min(page, #types - view.scroll) do
      local t = types[i + view.scroll]
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      local x, w = 1 + col * (colW + 1), col == cols - 1 and (s.w - col * (colW + 1)) or colW
      local count = tostring(shop.stock:summary().types[t.type].total)
      local label = rules.typeLabel(t.type):sub(1, math.max(1, w - #count - 1))
      label = label .. (" "):rep(math.max(1, w - #label - #count)) .. count
      -- alternate shades so neighbouring entries read as separate buttons
      s:button("settype", t.type, x, top + row * bh, w, bh, label,
        t.type == ds.type and "5" or "0", (col + row) % 2 == 0 and "7" or "f")
    end
    local specs = { { "back", nil, "BACK", "0", "e" } }
    if #types > page then
      specs[#specs + 1] = { "scroll", -page, "UP", "0", "b" }
      specs[#specs + 1] = { "scroll", page, "DOWN", "0", "b" }
    end
    buttonRows(s, { specs }, bh)
    s:finish()
    return
  end

  -- a tap anywhere off the buttons, by someone else, tells them whose station it is
  s.buttons[#s.buttons + 1] = { id = "claim", x = 1, y = 1, w = s.w, h = s.h }
  local rows
  if d.gearType then
    -- one type: no TYPE picker. PAY is on every station, so a shopper pays wherever they are
    rows = narrow and {
      { { "level", -1, "LV -", "0", "7" }, { "level", 1, "LV +", "0", "7" } },
      { { "next", nil, "NEXT", "f", "5" }, { "done", nil, "DONE", "0", "e" } },
      { { "pay", nil, "PAY", "f", "4" } },
    } or {
      { { "level", -1, "LV -", "0", "7" }, { "level", 1, "LV +", "0", "7" }, { "pay", nil, "PAY", "f", "4" } },
      { { "next", nil, "NEXT PAGE", "f", "5" }, { "done", nil, "DONE", "0", "e" } },
    }
  else
    rows = narrow and {
      { { "types", nil, "TYPE", "0", "b" }, { "pay", nil, "PAY", "f", "4" } },
      { { "level", -1, "LV -", "0", "7" }, { "level", 1, "LV +", "0", "7" } },
      { { "next", nil, "NEXT", "f", "5" }, { "done", nil, "DONE", "0", "e" } },
    } or {
      { { "types", nil, "TYPE", "0", "b" }, { "level", -1, "LV -", "0", "7" }, { "level", 1, "LV +", "0", "7" } },
      { { "next", nil, "NEXT PAGE", "f", "5" }, { "pay", nil, "PAY", "f", "4" }, { "done", nil, "DONE", "0", "e" } },
    }
  end
  local buttonsTop = buttonRows(s, rows, bh)

  local lines = {}
  local function add(text, fg) lines[#lines + 1] = { text, fg } end
  -- one screen for everyone: whoever walks up sees whose it is
  add(d.gearType and ("In use by " .. owner) or (owner .. "'s chest"), "8")
  local tab = shop:owes(owner)
  local credit = shop.state.credit[owner]
  local money = "Tab " .. tab
  if credit and credit > 0 then money = money .. "   Credit " .. rules.showMilli(credit) end
  add(money, tab > 0 and "4" or "0")
  -- a piece is charged as it is taken: a tab is only what could not be, and the next tap pays it
  if tab > 0 then add("Paid on your next tap, or PAY", "8") end
  if ds.phase ~= "open" then
    add("Fetching gear...", "8")
  elseif (ds.total or 0) == 0 then
    add(d.gearType and "None in stock at this level. Try LV - or LV +." or "None in stock at this level. Try another level or type.", "8")
  else
    add("Page " .. (ds.page or 1) .. " of " .. (ds.pages or 1), "0")
  end
  local note = shop:noteFor(s.name)
  if note then add(note, "4") end
  centred(s, top, buttonsTop - 1, lines)
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
  -- On a tall screen (the usual kiosk is a 3x3 monitor, 57x38 at scale 0.5) a one-row button is a sliver a player can
  -- hardly hit, so every button is three rows high there, with a gap or a change of shade between neighbours.
  -- (a 3x2 one keeps one-row buttons: taller ones would leave it no room to list what was found)
  local tall = s.h >= 30

  if view.mode == "types" then
    local list = shop.stock:summary().typeList
    local ih = tall and 3 or 1
    local rows = math.max(1, math.floor((buttonsTop - 2) / ih))
    view.scroll = math.max(0, math.min(view.scroll or 0, math.max(0, #list + 1 - rows)))
    for i = 1, math.min(rows, #list + 1 - view.scroll) do
      local index = i + view.scroll - 1
      local y = 2 + (i - 1) * ih
      local shade = (tall and i % 2 == 0) and "7" or "f"
      if index == 0 then
        s:button("settype", false, 1, y, s.w, ih, "Any type", q.type == nil and "5" or "0", shade)
      else
        s:button("settype", list[index], 1, y, s.w, ih, rules.typeLabel(list[index]), list[index] == q.type and "5" or "0", shade)
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
    local kw = math.max(2, math.min(tall and 5 or 4, math.floor(s.w / 10)))
    local kh = tall and 3 or 1
    for r, row in ipairs(KEY_ROWS) do
      local y = 6 + (r - 1) * (kh + 1)
      local x = 1 + math.floor((s.w - #row * kw) / 2)
      for i = 1, #row do
        local ch = row:sub(i, i)
        s:button("key", ch:lower(), x + (i - 1) * kw, y, kw - 1, kh, ch, "0", "7")
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

  local qh = tall and 3 or 1
  local y = 3
  local function query(id, label)
    s:button(id, nil, 1, y, s.w, qh, label, "0", "7")
    y = y + qh + (tall and 1 or 0)
  end
  query("types", "Type:   " .. (q.type and rules.typeLabel(q.type) or "Any"))
  query("bracket", "Level:  " .. (q.bracket and rules.bracketLabel(q.bracket) or "Any"))
  query("rarity", "Rarity: " .. (q.rarity or "Any"))
  query("keys", "Text:   " .. ((q.text and q.text ~= "") and q.text or "(tap to type)"))
  local at = y + (tall and 0 or 1)
  local listBottom = buttonsTop - 4
  if owner and ds.phase == "open" then
    local list = holding(shop, d)
    s:write(1, at, ((ds.total or 0) .. " found, page " .. (ds.page or 1) .. "/" .. (ds.pages or 1)):sub(1, s.w), "8")
    pieceRows(s, list, at + 1, listBottom, true)
  elseif ds.phase then
    s:write(1, at, "Fetching gear...", "8")
  else
    s:wrap(at, 3, "Pick what you are after, tap FIND, and it is brought to the chest here. Taking a piece puts it on your tab.", "8")
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

-- ---------------------------------------------------------------- the how-it-works screen
-- Help on a wall: a home screen of topics as big buttons, each topic a page of text (NEXT and BACK when it runs long, HOME
-- always), and an FAQ whose questions open their answers. Back to the home screen after a minute untouched. Every number
-- and rule comes from the limits and the setup, so it says what the shop really does. Made for a 4x4 monitor (39x26 at
-- text scale 1, app.lua picks the scale); a 3x3 gets scale 0.5 (57x38); smaller ones show what fits. A tap here is also a
-- shop tap: app.lua collects what the tapper owes first, as on every screen.

local INFO_TITLE_BG = "b"
local INFO_IDLE_MS = 60000
M.INFO_MIN_WIDTH = 36   -- below this many columns at scale 1 the help screen uses scale 0.5

--- Word-wrap text into lines of at most width characters.
local function wrapLines(text, width)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if #line > 0 and #line + 1 + #word > width then
      out[#out + 1] = line
      line = word
    else
      line = #line > 0 and (line .. " " .. word) or word
    end
    while #line > width do
      out[#out + 1] = line:sub(1, width)
      line = line:sub(width + 1)
    end
  end
  if #line > 0 then out[#out + 1] = line end
  return out
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

--- The help topics, from the limits and the setup: { { id, title, colour, paragraphs }, ... }. The FAQ is last.
function M.infoTopics(shop)
  local cfg, setup = shop.cfg, shop.setup or {}
  local list = {}
  local function add(id, title, colour, paragraphs) list[#list + 1] = { id = id, title = title, colour = colour, text = paragraphs } end
  local credit = rules.showMilli(rules.creditMilli(1, cfg))
  local returns, junk = setup.returns and setup.returns.chest, setup.junk and setup.junk.chest

  add("buy", "How to buy", "5", {
    "Tap the floor screen in front of any station. Its chest fills with that station's gear, near your vault level.",
    "Open the chest and take what you want. LV - and LV + step to a lower or higher level, NEXT PAGE shows more.",
    "The first time, click APPROVE in chat once. That lets the shop charge you as you take.",
  })
  if cfg.chargeAsTaken == false then
    add("pay", "Paying & your tab", "4", {
      "Take a piece and its price goes on your tab. Put it back and it comes off.",
      "Tap PAY on any station to pay: store credit first, then tokens. A tab left unpaid waits for your next visit.",
    })
  else
    add("pay", "Paying & your tab", "4", {
      "You are charged the moment you take a piece: store credit first, then tokens. Put it back and you get it back the same way.",
      "If a charge cannot go through (not approved yet, not enough tokens) the piece goes on your tab.",
      "Your next tap on any screen here pays the tab first. PAY on any station pays it by hand.",
      "Leave with a tab and it is charged as you are checked out, or kept for your next visit.",
    })
  end
  if setup.sell and setup.sell.chest then
    local paid
    if rules.sellsForTokens(cfg) then
      paid = "then tap TOKENS or STORE CREDIT: " .. rules.showMilli(rules.pieceMilli(cfg)) .. " tokens or " .. credit .. " store credit a piece."
    else
      paid = "then tap STORE CREDIT. Each piece the shop buys pays " .. credit .. " store credit, spent on gear here. No tokens are paid for gear."
    end
    add("sell", "Selling", "3", {
      "Put gear in the sell chest, " .. paid,
      "Gear the shop does not buy is not taken: see What we buy" .. (returns and ", and Returns." or "."),
    })
  end
  add("buys", "What we buy", "1", {
    "Identified gear only: " .. rules.buysText(cfg) .. ".",
    "Unidentified gear is refused: identify it first.",
  })
  local per = cfg.pricePerLevel or rules.DEFAULTS.pricePerLevel
  add("prices", "Prices", "6", {
    plural(per, "token", "tokens") .. " per gear level, any rarity.",
    "Level 10 is " .. rules.price(10, cfg) .. ", level 50 is " .. rules.price(50, cfg) .. ", level 100 is "
      .. rules.price(100, cfg) .. ". Nothing costs less than " .. plural(cfg.minPrice or rules.DEFAULTS.minPrice, "token", "tokens") .. ".",
    "A station's screen shows the price range of what is in its chest.",
  })
  if setup.kiosk and setup.kiosk.chest then
    add("kiosk", "Search kiosk", "a", {
      "Looking for something? At the search kiosk pick a type, a level, a rarity or a name, and tap FIND.",
      "What matches comes to the kiosk's chest. Take what you want: it is charged the same way. DONE puts the rest back.",
    })
  end
  if returns or junk then
    local p = {}
    if returns then p[#p + 1] = "Gear the shop will not buy goes straight to the returns chest. Take yours back from there." end
    if junk then p[#p + 1] = "Rather not carry it? Tap DONATE at the sell point to give your refused gear to the shop." end
    add("returns", "Returns & DONATE", "e", p)
  end
  local times = { "Tap DONE when you have finished with a station: it empties back into the shop." }
  if (cfg.stationLeaveDistance or 0) > 0 or (cfg.stationIdleMinutes or 0) > 0 then
    local also = {}
    if (cfg.stationLeaveDistance or 0) > 0 then also[#also + 1] = "you walk " .. cfg.stationLeaveDistance .. " blocks away" end
    if (cfg.stationIdleMinutes or 0) > 0 then also[#also + 1] = "nobody uses it for " .. cfg.stationIdleMinutes .. " min" end
    times[#times + 1] = "A station also frees itself when " .. table.concat(also, " or ") .. "."
  end
  if (cfg.stationsPerShopper or 0) > 0 then
    times[#times + 1] = "You can hold " .. cfg.stationsPerShopper .. " at once: opening one more frees the one you used longest ago."
  end
  times[#times + 1] = "You are checked out after " .. cfg.idleMinutes .. " min without a tap, or " .. cfg.leaveDistance
    .. " blocks from the shop. Your tab is charged then, or kept."
  add("stations", "Stations & timeouts", "9", times)
  add("faq", "Questions", "0", {})
  return list
end

--- The FAQ: { { q, a }, ... }.
function M.infoFaq(shop)
  local cfg, setup = shop.cfg, shop.setup or {}
  local returns = setup.returns and setup.returns.chest
  local list = {}
  local function add(q, a) list[#list + 1] = { q = q, a = a } end
  add("Why was my gear refused?", "The shop buys identified " .. rules.buysText(cfg) .. ". The sell screen gives the reason for each piece."
    .. (returns and " Refused gear is in the returns chest." or " Refused gear stays in the sell chest."))
  add("Where does my store credit go?", "It stays with you at this shop and is spent by itself, before tokens, on anything you take. It is never paid out as tokens.")
  add("I walked away. What happened to my tab?", "Your stations emptied back into the shop. What was still on your tab was charged when you were checked out if the shop could; if not, it waits, and your next tap here pays it.")
  add("How do I get my stuff back?", "Took something by mistake? Put it back in any station's chest while you are still in the shop and you get your tokens or credit back."
    .. (returns and " Gear the shop refused is in the returns chest." or ""))
  add("Do I have to tap PAY?", "No. Pieces are charged as you take them. PAY is there for anything left on your tab.")
  add("Someone else has my station.", "Its screen says who has it and roughly when it frees. Stations free themselves when their shopper walks off or stops using them.")
  add("Why did it ask me to APPROVE?", "The first time, the shop needs your OK in chat before it can take tokens from you. It asks once per session.")
  return list
end

--- A row of buttons along the bottom: as tall as there is room for.
local function infoButtons(s, specs)
  local bh = s.h >= 20 and 3 or 1
  local top = s.h - bh + 1
  s:row(top, bh, specs)
  return top
end

local function infoTitle(s, title, colour, right)
  s:bar(1, colour)
  s:write(2, 1, title:sub(1, s.w - 2 - (right and #right + 1 or 0)), colour == "0" and "f" or "f", colour)
  if right then s:right(1, right .. " ", "f", colour) end
end

--- view: this monitor's own state, { page = "home"|topic id, sub = page number, q = open question, at = last tap }
function M.info(s, shop, view)
  view = view or {}
  local clock = os.epoch and os.epoch("utc") or 0
  if view.at and clock - view.at > INFO_IDLE_MS then
    view.page, view.sub, view.q, view.at = nil, nil, nil, nil
  end
  local topics = M.infoTopics(shop)
  local topic
  for _, t in ipairs(topics) do
    if t.id == view.page then topic = t end
  end
  s:start()

  if not topic then
    -- home: the topics as a grid of big buttons
    s:bar(1, INFO_TITLE_BG)
    s:bar(2, INFO_TITLE_BG)
    s:centre(1, "GEAR SHOP", "0", INFO_TITLE_BG)
    s:centre(2, "Tap a topic", "3", INFO_TITLE_BG)
    local cols = s.w >= 30 and 2 or 1
    local rows = math.ceil(#topics / cols)
    local top, bottom = 4, s.h - 2
    local room = bottom - top + 1
    local bh = math.max(1, math.min(3, math.floor((room + 1) / rows) - 1))
    local gap = (bh + 1) * rows - 1 <= room and 1 or 0
    local colW = math.floor((s.w - (cols - 1)) / cols)
    for i, t in ipairs(topics) do
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      local x = 1 + col * (colW + 1)
      local w = col == cols - 1 and (s.w - x + 1) or colW
      local y = top + row * (bh + gap)
      if y + bh - 1 <= bottom then
        s:button("topic", t.id, x, y, w, bh, t.title:upper(), t.colour == "0" and "f" or "f", t.colour == "0" and "8" or t.colour)
      end
    end
    s:bar(s.h, "7")
    s:centre(s.h, "Tap any station's floor screen to shop", "5", "7")
    noteRows(s, shop, s.name, s.h - 3, 3)
    s:finish()
    return
  end

  local body = {}
  local bodyTop, width = 3, s.w - 2
  if topic.id == "faq" then
    local faq = M.infoFaq(shop)
    local open = view.q and faq[view.q]
    if not open then
      -- the questions, each a button that opens its answer
      infoTitle(s, "QUESTIONS", "8")
      local buttonsTop = infoButtons(s, { { "home", nil, "HOME", "0", "b" } })
      local qh = s.h >= 20 and 2 or 1
      local y = bodyTop
      for i, item in ipairs(faq) do
        if y + qh - 1 <= buttonsTop - 2 then
          s:button("question", i, 1, y, s.w, qh, item.q, "0", "7")
          y = y + qh + (s.h >= 20 and 1 or 0)
        end
      end
      noteRows(s, shop, s.name, buttonsTop - 3, 3)
      s:finish()
      return
    end
    infoTitle(s, "QUESTIONS", "8")
    for _, line in ipairs(wrapLines(open.q, width)) do body[#body + 1] = { line, "4" } end
    body[#body + 1] = { "", "0" }
    for _, line in ipairs(wrapLines(open.a, width)) do body[#body + 1] = { line, "0" } end
    local buttonsTop = infoButtons(s, { { "home", nil, "HOME", "0", "b" }, { "questions", nil, "ALL QUESTIONS", "0", "7" } })
    for i, line in ipairs(body) do
      if bodyTop + i - 1 < buttonsTop - 1 then s:write(2, bodyTop + i - 1, line[1], line[2]) end
    end
    noteRows(s, shop, s.name, buttonsTop - 3, 3)
    s:finish()
    return
  end

  -- a topic: its paragraphs, paged
  for i, paragraph in ipairs(topic.text) do
    if i > 1 then body[#body + 1] = "" end
    for _, line in ipairs(wrapLines(paragraph, width)) do body[#body + 1] = line end
  end
  local bh = s.h >= 20 and 3 or 1
  local per = math.max(1, (s.h - bh) - bodyTop)
  local pages = math.max(1, math.ceil(#body / per))
  view.sub = math.max(1, math.min(view.sub or 1, pages))
  infoTitle(s, topic.title:upper(), topic.colour == "0" and "8" or topic.colour, pages > 1 and (view.sub .. "/" .. pages) or nil)
  for i = 1, per do
    local line = body[(view.sub - 1) * per + i]
    if line then s:write(2, bodyTop + i - 1, line, "0") end
  end
  local specs = { { "home", nil, "HOME", "0", "b" } }
  if view.sub > 1 then specs[#specs + 1] = { "prev", nil, "BACK", "0", "7" } end
  if view.sub < pages then specs[#specs + 1] = { "next", nil, "NEXT", "f", "5" } end
  local buttonsTop = infoButtons(s, specs)
  noteRows(s, shop, s.name, buttonsTop - 3, 3)
  s:finish()
end

--- A tap on the help screen: only where it is looking changes. Returns true when the tap was one of its buttons.
function M.infoTouch(view, button)
  view.at = os.epoch and os.epoch("utc") or 0
  if not button then return false end
  if button.id == "topic" then
    view.page, view.sub, view.q = button.value, 1, nil
  elseif button.id == "home" then
    view.page, view.sub, view.q = nil, nil, nil
  elseif button.id == "next" then
    view.sub = (view.sub or 1) + 1
  elseif button.id == "prev" then
    view.sub = math.max(1, (view.sub or 1) - 1)
  elseif button.id == "question" then
    view.q = button.value
  elseif button.id == "questions" then
    view.q = nil
  else
    return false
  end
  return true
end

-- ---------------------------------------------------------------- a monitor with no job yet

--- A monitor the shop can reach that setup has not given a job: a plain notice, so nothing older lingers on it.
function M.idle(s)
  s:start()
  s:bar(1, "b")
  s:centre(1, "GEAR SHOP", "0", "b")
  s:centre(math.max(2, math.floor(s.h / 2) + 1), "Not set up yet", "8")
  s:finish()
end

-- ---------------------------------------------------------------- the sell point

--- "L71 Epic: Omega+ above 70": which refused piece (every piece of a type has the same name, so its level and rarity
-- say which one is meant; an unidentified one goes by its name) and why.
local function refusal(entry)
  local what = entry.grade and ("L" .. tostring(entry.level) .. " " .. entry.grade:sub(1, 1) .. entry.grade:sub(2):lower()) or entry.label
  return what .. ": " .. tostring(entry.why)
end

local REFUSED_MS = 120000

--- One piece of a batch as a line: "L45 Epic  Sword ........ +1 credit" or "L30 Rare  Sword ..... Epic+ only".
local function batchLine(s, y, item)
  local result = tostring(item.why or (item.ok and "bought" or "refused"))
  local colour = item.ok and "5" or "e"
  local room = s.w - #result - 1
  if item.grade and item.grade ~= "?" then
    local what = "L" .. tostring(item.level or 0) .. " " .. item.grade:sub(1, 1) .. item.grade:sub(2):lower()
    s:write(1, y, what:sub(1, room), colour)
    local x = #what + 2
    if room - x + 1 >= 3 then s:write(x, y, tostring(item.label):sub(1, room - x + 1), "8") end
  else
    -- no rarity to show (unidentified, or not gear): its name says which it is
    s:write(1, y, tostring(item.label or "?"):sub(1, room), colour)
  end
  s:right(y, result, colour)
end

--- The sell point on a monitor at least 20 rows high (the owner's 2x2 in the floor, 36x24): what to do, what the shop
-- buys one rule a line, the pieces in the chest now or the last batch one a line (green bought, red refused and why),
-- the seller's store credit, and big buttons. Laid out from the top down, so a later "drop in a backpack" line or an
-- automatic identify step fits in as one more line.
local function sellBig(s, shop)
  local cfg, setup = shop.cfg, shop.setup or {}
  local tokens = rules.sellsForTokens(cfg)
  local junk = setup.junk and setup.junk.chest
  local returnsChest = setup.returns and setup.returns.chest
  local view = shop.sellView
  local clock = os.epoch and os.epoch("utc") or 0
  local batch = shop.lastBatch and (clock - (shop.lastBatch.at or 0)) < REFUSED_MS and shop.lastBatch or nil
  local bh = 3
  local buttonsTop = s.h - bh + 1
  s:start()
  s:bar(1, "b")
  s:centre(1, "SELL GEAR", "0", "b")
  local y = 3
  local function heading(text, colour)
    s:write(1, y, text, colour)
    y = y + 1
  end
  if not shop.ready then
    s:wrap(y, 2, "The shop is opening...", "8")
    s:finish()
    return
  end

  heading("PUT GEAR IN THE CHEST", "4")
  local each = rules.showMilli(rules.creditMilli(1, cfg))
  y = y + s:wrap(y, 2, tokens and ("Each piece bought pays " .. rules.showMilli(rules.pieceMilli(cfg)) .. " token or " .. each .. " store credit.")
    or ("Each piece bought pays " .. each .. " store credit, spent on gear here."), "0")
  y = y + 1

  heading("WHAT WE BUY", "3")
  for _, line in ipairs(rules.buysLines(cfg)) do
    s:write(2, y, ("- " .. line):sub(1, s.w - 1), "0")
    y = y + 1
  end
  y = y + 1

  -- the pieces: what is in the chest now, or else what became of the last batch
  local items, title = {}, nil
  if view and (#view.accepted + #view.rejected + #view.returns) > 0 then
    title = "IN THE CHEST"
    for _, e in ipairs(view.accepted) do
      items[#items + 1] = { label = e.label, level = e.level, grade = e.grade, ok = true,
        why = tokens and "buys" or ("+" .. each .. " credit") }
    end
    for _, e in ipairs(view.returns) do
      items[#items + 1] = { label = e.label, ok = true, why = "put back" }
    end
    for _, e in ipairs(view.rejected) do
      items[#items + 1] = { label = e.label, level = e.level, grade = e.grade, ok = false, why = e.why }
    end
    -- refused a moment ago and already moved to the returns chest: still listed, with why
    for _, item in ipairs(batch and batch.items or {}) do
      if not item.ok then items[#items + 1] = item end
    end
  elseif batch then
    title = "LAST BATCH"
    items = batch.items
  end
  local seller = batch and batch.by
  local credit = seller and shop.state and shop.state.credit and shop.state.credit[seller]
  local listBottom = buttonsTop - 2 - (seller and 1 or 0)
  local note = shop:noteFor(s.name)
  if note then listBottom = math.min(listBottom, buttonsTop - 5) end
  if title then
    local bought, refused = 0, 0
    for _, item in ipairs(items) do
      if item.ok then bought = bought + 1 else refused = refused + 1 end
    end
    if title == "IN THE CHEST" then
      heading("IN THE CHEST  Buying: " .. bought .. (refused > 0 and ("  Refused: " .. refused) or ""), "1")
    else
      heading(title .. ": " .. bought .. " bought, " .. refused .. " refused", "1")
    end
    for i, item in ipairs(items) do
      if y > listBottom then break end
      if y == listBottom and i < #items then
        s:write(1, y, "+" .. (#items - i + 1) .. " more", "8")
        y = y + 1
        break
      end
      batchLine(s, y, item)
      y = y + 1
    end
    if refused > 0 and y <= listBottom then
      s:write(1, y, (returnsChest and "Refused gear is in the returns chest." or "No returns chest: they stay here."):sub(1, s.w), "8")
      y = y + 1
    end
  end
  if seller then
    s:write(1, buttonsTop - 2, (seller .. "'s store credit: " .. rules.showMilli(credit or 0)):sub(1, s.w), "5")
  end
  if note then noteRows(s, shop, s.name, buttonsTop - 4, 3) end

  local specs
  if tokens then
    specs = { { "tokens", nil, "TOKENS", "f", "4" }, { "credit", nil, "STORE CREDIT", "f", "5" } }
  else
    specs = { { "credit", nil, "STORE CREDIT", "f", "5" } }
  end
  local giveable = view and #view.rejected > 0
  if returnsChest then giveable = shop.state and next(shop.state.returnsBy or {}) ~= nil end
  if junk and giveable then specs[#specs + 1] = { "donate", nil, "DONATE", "0", "7" } end
  s:row(buttonsTop, bh, specs)
  s:finish()
end

function M.sell(s, shop)
  if s.h >= 20 then return sellBig(s, shop) end
  s:start()
  s:bar(1, "b")
  s:centre(1, "SELL GEAR", "0", "b")
  -- The owner's sell point is a 2x1 monitor in the floor (36x10): there the button is two rows high (one is a sliver a
  -- player can hardly hit), the words are fewer, and the reasons for a refusal use every free row.
  local small = s.h < 16
  local bh = small and 2 or buttonHeight(s)
  local buttonsTop = s.h - bh + 1
  local view = shop.sellView
  local y = 3
  local cfg = shop.cfg
  local tokens = rules.sellsForTokens(cfg)  -- off: store credit is the only way a sale is paid
  local junk = shop.setup and shop.setup.junk and shop.setup.junk.chest
  local returnsChest = shop.setup and shop.setup.returns and shop.setup.returns.chest
  -- what was just refused and moved to the returns chest, with its reasons, for a couple of minutes
  local clock = os.epoch and os.epoch("utc") or 0
  local refused = shop.refused and (clock - (shop.refused.at or 0)) < REFUSED_MS and shop.refused.entries or nil
  -- the note takes the three rows over the buttons while it shows; otherwise those are free for reasons
  local lastRow = shop:noteFor(s.name) and (buttonsTop - 4) or (small and buttonsTop - 1 or buttonsTop - 4)
  local function reasons(list)
    for _, entry in ipairs(list) do
      if y <= lastRow then
        s:write(2, y, refusal(entry):sub(1, s.w - 1), "8")
        y = y + 1
      end
    end
  end
  if not shop.ready then
    s:wrap(y, 2, "The shop is opening...", "8")
  elseif not view or (#view.accepted + #view.rejected + #view.returns) == 0 then
    if refused then
      s:write(1, y, ("Refused: " .. #refused .. ", in the returns chest"):sub(1, s.w), "e")
      y = y + 1
      reasons(refused)
    elseif small then
      y = y + s:wrap(y, 3, "Buys " .. rules.buysText(cfg) .. ".", "8")
      if tokens then
        local each = rules.showMilli(rules.pieceMilli(cfg))
        s:wrap(y + 1, 2, "Put gear in: " .. each .. (each == "1" and " token or " or " tokens or ")
          .. rules.showMilli(rules.creditMilli(1, cfg)) .. " credit a piece.", "0")
      else
        s:wrap(y + 1, 2, "Put gear in: " .. rules.showMilli(rules.creditMilli(1, cfg)) .. " store credit a piece.", "0")
      end
    else
      y = y + s:wrap(y, 4, "Put gear in the chest. The shop buys " .. rules.buysText(cfg) .. ".", "8")
      if tokens then
        local each = rules.showMilli(rules.pieceMilli(cfg))
        s:wrap(y + 1, 3, "Each piece pays " .. each .. (each == "1" and " token, or " or " tokens, or ")
          .. rules.showMilli(rules.creditMilli(1, cfg)) .. " in store credit.", "8")
      else
        s:wrap(y + 1, 3, "The shop pays in store credit: " .. rules.showMilli(rules.creditMilli(1, cfg))
          .. " a piece, spent on gear here.", "8")
      end
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
    y = y + (small and 1 or 2)
    if #view.returns > 0 then
      s:write(1, y, "Back off a tab: " .. #view.returns, "4")
      y = y + 1
    end
    if #view.rejected > 0 then
      s:write(1, y, "Not wanted: " .. #view.rejected .. " (take them back)", "e")
      y = y + 1
      if not returnsChest then
        -- no returns chest set up: refused gear stays here, as it always did
        s:write(2, y, "No returns chest: they stay here.", "8")
        y = y + 1
      end
      reasons(view.rejected)
    elseif refused then
      s:write(1, y, ("Refused: " .. #refused .. ", in the returns chest"):sub(1, s.w), "e")
      y = y + 1
      reasons(refused)
    end
  end
  noteRows(s, shop, s.name, buttonsTop - 3, 3)
  local specs
  if tokens then
    specs = {
      { "tokens", nil, "TOKENS", "f", "4" },
      { "credit", nil, s.w >= 30 and "STORE CREDIT" or "CREDIT", "f", "5" },
    }
  else
    specs = { { "credit", nil, s.w >= 22 and "SELL FOR STORE CREDIT" or (s.w >= 12 and "STORE CREDIT" or "CREDIT"), "f", "5" } }
  end
  -- DONATE gives refused gear to the shop for nothing (to the junk chest), offered only when there is a junk chest and
  -- refused gear to give
  local giveable = view and #view.rejected > 0
  if returnsChest then giveable = shop.state and next(shop.state.returnsBy or {}) ~= nil end
  if junk and giveable and shop.ready then
    if tokens then
      specs[#specs + 1] = { "donate", nil, "DONATE", "0", "7" }
    else
      specs[1][3] = s.w >= 40 and "SELL FOR STORE CREDIT" or "STORE CREDIT"
      specs[2] = { "donate", nil, s.w >= 30 and "DONATE REFUSED" or "DONATE", "0", "7" }
    end
  end
  s:row(buttonsTop, bh, specs)
  s:finish()
end

return M
