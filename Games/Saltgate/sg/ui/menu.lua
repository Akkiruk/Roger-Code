-- ui/menu.lua
-- A list menu: rows you move through, select and change. Pure: it takes actions ("up", "down", "left", "right",
-- "select") from ui/keys.lua and draws on any term-shaped table.
--
--   local m = menu.new({
--     { id = "resume", label = "Resume", action = function(m, item) end },
--     { id = "sound", label = "Sound", value = function() return "ON" end, change = function(dir) end },  -- A/D change it
--     { label = "---" , header = true },       -- a heading: skipped by the cursor
--     { label = "Locked", enabled = function() return false end },
--   })
--   m:handle("down")   m:handle("select")  -> the item selected, if it had an action
--   m:draw(t, x, y, w, rows)

local theme = require("sg.ui.theme")
local C = theme.C

local M = {}
local Menu = {}
Menu.__index = Menu

function M.new(items, opts)
  local m = setmetatable({ items = items, sel = 1, top = 1, opts = opts or {} }, Menu)
  m:settle(1)
  return m
end

local function usable(item)
  if item.header then return false end
  if item.enabled and not item.enabled() then return false end
  return true
end

--- Put the cursor on a usable row at or after the current one (in direction dir).
function Menu:settle(dir)
  local n = #self.items
  if n == 0 then return end
  for _ = 1, n do
    if usable(self.items[self.sel]) then return end
    self.sel = self.sel + dir
    if self.sel < 1 then self.sel = n end
    if self.sel > n then self.sel = 1 end
  end
end

function Menu:current()
  return self.items[self.sel]
end

function Menu:select(id)
  for i, it in ipairs(self.items) do
    if it.id == id then self.sel = i self:settle(1) return true end
  end
  return false
end

function Menu:move(dir)
  local n = #self.items
  if n == 0 then return end
  for _ = 1, n do
    self.sel = self.sel + dir
    if self.sel < 1 then self.sel = n end
    if self.sel > n then self.sel = 1 end
    if usable(self.items[self.sel]) then return end
  end
end

--- One action. Returns the item that was selected or changed (nil when nothing happened).
function Menu:handle(action)
  local item = self.items[self.sel]
  if action == "up" then
    self:move(-1)
  elseif action == "down" then
    self:move(1)
  elseif (action == "left" or action == "right") and item and usable(item) and item.change then
    item.change(action == "right" and 1 or -1, self, item)
    return item
  elseif action == "select" and item and usable(item) then
    if item.action then item.action(self, item) return item end
    if item.change then item.change(1, self, item) return item end
  end
  return nil
end

--- Draw the rows in a w-wide, rows-tall window at (x, y), scrolling to keep the cursor in view.
function Menu:draw(t, x, y, w, rows)
  local n = #self.items
  rows = rows or n
  if self.sel < self.top then self.top = self.sel end
  if self.sel > self.top + rows - 1 then self.top = self.sel - rows + 1 end
  if self.top < 1 then self.top = 1 end
  local bg = self.opts.bg or theme.PANEL
  for r = 0, rows - 1 do
    local i = self.top + r
    local item = self.items[i]
    local yy = y + r
    if not item then
      theme.fill(t, x, yy, w, 1, bg)
    else
      local on = usable(item)
      local selected = i == self.sel
      local rowBg = selected and C.orange or bg
      local fg = selected and C.black or (on and C.white or C.lightGray)
      if item.header then fg, rowBg = C.yellow, bg end
      theme.fill(t, x, yy, w, 1, rowBg)
      local label = (item.header and "" or " ") .. item.label
      if item.swatch then
        -- a colour chip before the label
        theme.put(t, x + 1, yy, "  ", fg, theme.C[item.swatch] or C.white)
        theme.put(t, x + 3, yy, theme.fit(" " .. item.label, w - 3), fg, rowBg)
        label = "    " .. item.label
      else
        theme.put(t, x, yy, theme.fit(label, w), fg, rowBg)
      end
      if item.value then
        local v = tostring(item.value())
        local arrows = item.change and selected
        local text = arrows and ("< " .. v .. " >") or v
        local vx = x + w - #text - 1
        if vx > x + #label then theme.put(t, vx, yy, text, selected and C.black or C.yellow, rowBg) end
      end
    end
  end
  -- a scroll cue when there is more above or below
  if self.top > 1 then theme.put(t, x + w - 1, y, "\30", C.lightGray, bg) end
  if self.top + rows - 1 < n then theme.put(t, x + w - 1, y + rows - 1, "\31", C.lightGray, bg) end
end

return M
