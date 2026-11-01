-- casino_hub_view.lua
-- The hub's wall: a display nobody needs to touch. The pages turn by themselves and the jackpot is always in view.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("casino_hub_rules")
local contestView = require("casino_hub_contest_view")

local C = theme.C
local M = {}

local NAME_MAX = 12
local TOP = ui.TOP + 9    -- first row under a page's title
local MIDDLE = 48         -- halfway down what a page has, for a line alone on it
local ROW_H = 7
local NAME_X = 14         -- where a name starts, after its rank
local ROUNDS_X = 72       -- where a row's small print starts, unless what is right of it needs the room
local BAR_LOW, BAR_HIGH = 0.8, 1.1
local NEAR = 0.02         -- within this of its target, a game reads as on target

local function short(name, limit)
  name = tostring(name)
  limit = limit or NAME_MAX
  if #name <= limit then return name end
  return name:sub(1, limit - 1) .. "."
end

--- A name in big letters, shortened until it fits, so it gives way before it runs into what is beside it.
local function fit(c, name, room, limit)
  name = short(name, limit)
  while #name > 2 and c:bigWidth(name, 1) > room do name = short(name, #name - 1) end
  return name
end

--- "12s ago", "3m ago", "2h ago", "4d ago".
function M.ago(ms)
  local seconds = math.max(0, math.floor(ms / 1000))
  if seconds < 60 then return seconds .. "s ago" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
  return math.floor(seconds / 86400) .. "d ago"
end

local function percent(value)
  return ("%.1f%%"):format(value * 100)
end

local function roundsText(count)
  return ui.group(count) .. (count == 1 and " round" or " rounds")
end

local function empty(c, text)
  c:textCenter(math.floor(c.w / 2), MIDDLE, text, C.mute)
end

local function title(c, text, note)
  c:big(4, ui.TOP, text, C.gold, 1)
  if note then c:text(c.w - 2 - #note, ui.TOP + 2, note, C.text) end
  c:rect(4, ui.TOP + 7, c.w - 6, 1, C.feltLight)
end

--- One band of a table, every other row, in line with the rule under the title.
local function band(c, i, y)
  if i % 2 == 1 then c:rect(4, y, c.w - 6, ROW_H, C.feltDark) end
end

--- A figure too wide for the big font goes to plain text, so it stays inside its tile.
local function tile(c, x, y, w, label, value)
  local cx = x + math.floor(w / 2)
  c:rect(x, y, w, 17, C.feltDark)
  c:rect(x, y, w, 1, C.accent)
  c:textCenter(cx, y + 2, label, C.text)
  if c:bigWidth(value, 1) > w - 4 then
    c:textCenter(cx, y + 10, value, C.gold)
    return
  end
  local scale = c:bigWidth(value, 2) <= w - 4 and 2 or 1
  c:bigCenter(cx, y + (scale == 2 and 4 or 7), value, C.gold, scale)
end

local function pageJackpot(c, data, t)
  local cx = math.floor(c.w / 2)
  c:bigCenter(cx, ui.TOP + 3, "SHARED JACKPOT", C.text, 1)
  local value = ui.group(data.jackpot)
  local scale = 4
  while scale > 1 and c:bigWidth(value, scale) > c.w - 8 do scale = scale - 1 end
  local color = math.floor(t * 2) % 2 == 0 and C.gold or C.win
  c:bigCenter(cx, 23 + (4 - scale) * 3, value, color, scale)
  c:textCenter(cx, 50, "tokens, waiting for three 7s", C.text)

  local totals = rules.totals(data)
  -- Rounds and tokens run to seven figures and more, and players do not
  tile(c, 4, 55, 44, "ROUNDS PLAYED", ui.group(totals.rounds))
  tile(c, 51, 55, 44, "TOKENS WAGERED", ui.group(totals.wagered))
  tile(c, 98, 55, 21, "PLAYERS", ui.group(totals.players))
end

local function pagePlayers(c, data)
  title(c, "TOP PLAYERS", "net winnings, all games")
  local list = rules.leaders(data, rules.TOP)
  if #list == 0 then return empty(c, "No rounds played yet") end
  for i, entry in ipairs(list) do
    local y = TOP + (i - 1) * ROW_H
    band(c, i, y)
    local color = i == 1 and C.gold or C.text
    c:big(6, y + 1, tostring(i), color, 1)
    local amount = ui.signed(entry.net)
    local amountX = c.w - 4 - c:bigWidth(amount, 1)
    c:big(amountX, y + 1, amount, entry.net >= 0 and C.win or C.red, 1)
    -- The small print gives way first: a name beside a big figure wants the room more
    local rounds = roundsText(entry.rounds)
    local roundsX = math.min(ROUNDS_X, amountX - 3 - #rounds)
    if NAME_X + c:bigWidth(short(entry.name), 1) + 3 <= roundsX then
      c:big(NAME_X, y + 1, short(entry.name), color, 1)
      c:text(roundsX, y + 3, rounds, C.text)
    else
      c:big(NAME_X, y + 1, fit(c, entry.name, amountX - 3 - NAME_X), color, 1)
    end
  end
end

--- The figure takes what it needs, and the names beside it make do with the rest of the column.
local function winRow(c, x, y, w, win)
  local amount = ui.group(win.amount)
  c:big(x, y, amount, win.jackpot and C.gold or C.win, 1)
  local textX = x + math.max(35, c:bigWidth(amount, 1) + 3)
  local room = x + w - textX
  c:text(textX, y + 1, short(win.player, room), C.text)
  c:text(textX, y + 3, short(rules.gameName(win.game), room), win.jackpot and C.gold or C.text)
end

local function pageWins(c, data)
  title(c, "BIG WINS")
  local w = math.floor((c.w - 9) / 2)
  local right = 7 + w
  c:text(4, TOP, "BIGGEST EVER", C.gold)
  c:text(right, TOP, "LATEST", C.gold)
  if #data.latest == 0 then return empty(c, "No wins yet") end
  for i, win in ipairs(data.biggest) do winRow(c, 4, TOP + 2 + (i - 1) * ROW_H, w, win) end
  for i, win in ipairs(data.latest) do winRow(c, right, TOP + 2 + (i - 1) * ROW_H, w, win) end
end

--- One game's measured return on a scale from 80% to 110%, with a mark at its target.
local function returnBar(c, x, y, w, game)
  c:rect(x, y, w, 2, C.feltDark)
  local function place(value)
    return math.floor(math.max(0, math.min(1, (value - BAR_LOW) / (BAR_HIGH - BAR_LOW))) * (w - 1))
  end
  local color = C.win
  if game.rounds < rules.SMALL_SAMPLE then
    color = C.mute
  elseif game.target and math.abs(game.measured - game.target) > NEAR then
    color = C.orange
  end
  if game.measured then c:rect(x, y, place(game.measured) + 1, 2, color) end
  if game.target then c:rect(x + place(game.target), y - 1, 1, 4, C.text) end
end

local function pageGames(c, data)
  title(c, "MEASURED RETURN", "white mark is the target")
  local list = rules.games(data)
  if #list == 0 then return empty(c, "No rounds played yet") end
  for i, game in ipairs(list) do
    if i > 10 then break end
    local y = TOP + (i - 1) * 6
    c:text(4, y, short(game.name, 16), C.text)
    c:text(4, y + 2, roundsText(game.rounds), C.mute)
    returnBar(c, 23, y + 1, 48, game)
    if game.measured then c:big(74, y, percent(game.measured), C.gold, 1) end
    c:text(106, y + 2, game.target and ("aim " .. percent(game.target)) or "no target", C.text)
  end
end

local function pageTables(c, data, _, at)
  title(c, "THE FLOOR", "tables heard from")
  local list = rules.tables(data, at)
  if #list == 0 then return empty(c, "No tables heard from yet") end
  for i, entry in ipairs(list) do
    if i > 8 then break end
    local y = TOP + (i - 1) * ROW_H
    band(c, i, y)
    c:rect(6, y + 2, 3, 3, entry.live and C.win or C.red)
    c:big(12, y + 1, fit(c, entry.name, 79, 16), entry.live and C.text or C.mute, 1)
    c:text(94, y + 2, "#" .. tostring(entry.id), C.text)
    c:text(94, y + 4, roundsText(entry.rounds), C.mute)
    local ago = M.ago(entry.ago)
    c:text(c.w - 4 - #ago, y + 2, ago, entry.live and C.win or C.orange)
  end
end

local function arcadeLine(game)
  if game.winner == 3 then return short(game.red) .. " drew " .. short(game.blue) end
  local winner, loser = game.red, game.blue
  if game.winner == 2 then winner, loser = loser, winner end
  return short(winner) .. " beat " .. short(loser)
end

local function pageArcade(c, data, _, at)
  title(c, "ARCADE", "recent games, no tokens")
  if #data.arcade == 0 then return empty(c, "No Arcade games heard yet") end
  for i, game in ipairs(data.arcade) do
    local y = TOP + (i - 1) * ROW_H
    band(c, i, y)
    c:text(6, y + 3, game.title, C.text)
    c:text(78, y + 2, arcadeLine(game), game.winner == 3 and C.text or C.gold)
    c:text(78, y + 4, game.moves .. " moves" .. (game.ranked and ", ranked" or ""), C.text)
    local ago = M.ago(at - game.at)
    c:text(c.w - 4 - #ago, y + 4, ago, C.text)
  end
end

M.PAGES = { pageJackpot, pagePlayers, pageWins, pageGames, pageTables, pageArcade }
M.PAGES[#M.PAGES + 1] = contestView.page -- always last: casino_hub_contest_view.turn counts on it

--- Draw a page. t is seconds running, at is the time now, note is a warning for the bottom line.
function M.draw(c, data, page, t, at, note)
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
  local jackpot = ui.group(data.jackpot)
  ui.bar(c, { title = "CASINO HUB" })
  local jackpotX = c.w - 2 - c:bigWidth(jackpot, 1)
  c:big(jackpotX, 2, jackpot, C.gold, 1)
  c:text(jackpotX - 3 - 7, 3, "JACKPOT", C.text)

  M.PAGES[page](c, data, t, at)

  local cx = math.floor(c.w / 2)
  local count = #M.PAGES
  for i = 1, count do
    c:rect(cx - count * 2 + (i - 1) * 4, c.h - 2, 2, 1, i == page and C.gold or C.feltLight)
  end
  if note then c:text(4, c.h - 2, note, C.orange) end
end

return M
