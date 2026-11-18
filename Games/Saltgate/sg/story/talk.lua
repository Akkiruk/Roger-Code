-- story/talk.lua
-- Dialogue as a small state machine: one line of talk at a time (letters appear over a moment; ENTER shows the rest, then
-- moves on), and choices (W/S or the number keys, ENTER). Pure: the screen draws it and feeds it keys.
--
--   local t = talk.new()
--   t:say(who, text)           t:choose(prompt, options)
--   t:update(dt)               t:advance()  (ENTER)   t:move(dir)  (W/S)   t:pick(n)   t:skipAll()  (X)
--   t.line   -> { who, text, rows, shown, full } or nil     t.choice -> { prompt, options, sel } or nil
--   t:talking()   t:chosen() -> the index picked (and forgets it) or nil
--   t.history   the lines already said (the phone and the log read it)

local text = require("sg.story.text")

local M = {}
local T = {}
T.__index = T

M.RATE = 70 -- letters a second

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    line = nil, choice = nil, picked = nil, queue = {}, history = {}, rate = opts.rate or M.RATE, skipping = false,
  }, T)
end

local function open(self, entry)
  if entry.kind == "say" then
    local rows = text.wrap(entry.text, text.TEXT)
    self.line = { who = entry.who, text = entry.text, rows = rows, shown = 0, full = false, total = #entry.text }
  else
    self.choice = { prompt = entry.prompt, options = entry.options, sel = 1, rows = text.wrap(entry.prompt, text.TEXT) }
  end
end

local function nextEntry(self)
  self.line, self.choice = nil, nil
  local e = table.remove(self.queue, 1)
  if e then open(self, e) end
end

function T:say(who, line)
  local e = { kind = "say", who = who, text = line }
  if self.line or self.choice then
    self.queue[#self.queue + 1] = e
  else
    open(self, e)
  end
end

function T:choose(prompt, options)
  local e = { kind = "choose", prompt = prompt, options = options }
  if self.line or self.choice then
    self.queue[#self.queue + 1] = e
  else
    open(self, e)
  end
end

function T:talking() return self.line ~= nil or self.choice ~= nil or #self.queue > 0 end

function T:chosen()
  local p = self.picked
  self.picked = nil
  return p
end

function T:update(dt)
  local l = self.line
  if l and not l.full then
    l.shown = l.shown + self.rate * dt
    if l.shown >= l.total then l.shown, l.full = l.total, true end
  end
end

--- The letters of the line shown so far, as rows.
function T:visibleRows()
  local l = self.line
  if not l then return {} end
  local left = math.floor(l.shown)
  local out = {}
  for _, row in ipairs(l.rows) do
    if left <= 0 then break end
    out[#out + 1] = row:sub(1, left)
    left = left - #row - 1
  end
  return out
end

--- ENTER: finish the line's reveal, or move to what is next.
function T:advance()
  local l = self.line
  if l then
    if not l.full then
      l.shown, l.full = l.total, true
      return "reveal"
    end
    self.history[#self.history + 1] = { l.who, l.text }
    while #self.history > 40 do table.remove(self.history, 1) end
    nextEntry(self)
    return "next"
  end
  local c = self.choice
  if c then
    self.picked = c.sel
    nextEntry(self)
    return "picked"
  end
end

function T:move(dir)
  local c = self.choice
  if c then c.sel = ((c.sel - 1 + dir) % #c.options) + 1 end
end

function T:pick(n)
  local c = self.choice
  if c and n >= 1 and n <= #c.options then
    c.sel = n
    return self:advance()
  end
end

--- X: drop every line waiting; a choice still has to be made (it takes the one highlighted only by ENTER).
function T:skipAll()
  local keep = {}
  for _, e in ipairs(self.queue) do
    if e.kind == "choose" then keep[#keep + 1] = e end
  end
  self.queue = keep
  if self.line then
    self.history[#self.history + 1] = { self.line.who, self.line.text }
    nextEntry(self)
  end
end

--- Forget everything (a mission ended).
function T:clear()
  self.line, self.choice, self.picked, self.queue = nil, nil, nil, {}
end

return M
