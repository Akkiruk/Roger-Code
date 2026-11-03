-- arcade_scores.lua
-- The high score table for one classic game: the best runs, kept on disk with a good copy through every save.

local M = { LIMIT = 10 }
local Scores = {}
Scores.__index = Scores

local function read(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local ok, value = pcall(textutils.unserialise, h.readAll() or "")
  h.close()
  if ok and type(value) == "table" then return value end
  return nil
end

function M.open(id)
  local self = setmetatable({ id = id, path = "arcade_scores_" .. id .. ".dat" }, Scores)
  self.rows = read(self.path) or read(self.path .. ".tmp") or read(self.path .. ".bak") or {}
  return self
end

function Scores:save()
  local tmp, bak = self.path .. ".tmp", self.path .. ".bak"
  local h = fs.open(tmp, "w")
  if not h then return end
  h.write(textutils.serialise(self.rows))
  h.close()
  if fs.exists(bak) then fs.delete(bak) end
  if fs.exists(self.path) then fs.move(self.path, bak) end
  fs.move(tmp, self.path)
  -- the play tracker keeps the floor's table, from every cabinet's (share.lua)
  pcall(function() require("lib.arcade.share").push("scores", self.id, nil, self.rows) end)
end

--- Add a finished run. Returns its place on the table, or nil if it didn't make it.
function Scores:add(name, score, level)
  if score <= 0 then return nil end
  local place = #self.rows + 1
  for i, row in ipairs(self.rows) do
    if score > row.score then
      place = i
      break
    end
  end
  if place > M.LIMIT then return nil end
  table.insert(self.rows, place, { name = name, score = score, level = level, at = os.epoch("utc") })
  while #self.rows > M.LIMIT do table.remove(self.rows) end
  self:save()
  return place
end

function Scores:best()
  local row = self.rows[1]
  return row and row.score or 0
end

return M
