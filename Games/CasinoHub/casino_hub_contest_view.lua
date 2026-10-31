-- casino_hub_contest_view.lua
-- The hub wall's tournament page, and the menu the owner gets by touching the wall. Nobody else's touch opens it.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local contest = require("casino_hub_contest")
local rules = require("casino_hub_rules")

local C = theme.C
local M = {}

M.MENU_MS = 30000   -- a menu left alone closes by itself

local TOP = 18      -- first row under the title
local ROW_H = 7
local NAME_MAX = 16

local function short(name)
  name = tostring(name)
  if #name <= NAME_MAX then return name end
  return name:sub(1, NAME_MAX - 1) .. "."
end

local function title(c, text, note)
  c:big(4, 10, text, C.gold, 1)
  if note then c:text(c.w - 2 - #note, 11, note, C.text) end
  c:rect(4, 16, c.w - 6, 1, C.feltLight)
end

local function minutesLeft(ms)
  if ms <= 0 then return "time up" end
  return math.ceil(ms / 60000) .. " min left"
end

--- A row of a standings table: rank, name, chips, and how many rounds it took.
local function standingRow(c, y, rank, row)
  if rank % 2 == 1 then c:rect(3, y, c.w - 4, ROW_H, C.feltDark) end
  local color = rank == 1 and C.gold or C.text
  c:big(5, y + 1, tostring(rank), color, 1)
  c:big(12, y + 1, short(row.name), color, 1)
  local amount = ui.group(row.chips)
  c:big(c.w - 3 - c:bigWidth(amount, 1), y + 1, amount, row.final and C.red or C.win, 1)
  c:text(76, y + 3, row.rounds .. (row.rounds == 1 and " round" or " rounds"), C.text)
end

local function standings(c, list)
  if #list == 0 then
    c:textCenter(math.floor(c.w / 2), 44, "No scores yet", C.mute)
    return
  end
  for i, row in ipairs(list) do
    if i > contest.TOP then break end
    standingRow(c, TOP + (i - 1) * ROW_H, i, row)
  end
end

local function pageLive(c, live, at)
  title(c, "TOURNAMENT", rules.gameName(live.game) .. ", " .. minutesLeft(live.ends - at))
  standings(c, contest.standings(live, contest.TOP))
  c:textCenter(math.floor(c.w / 2), c.h - 4, ("Chips, not tokens. Everyone starts with %s. Best chips at the end wins."):format(ui.group(live.chips)), C.text)
end

local function pageFinal(c, record)
  title(c, "FINAL STANDINGS", rules.gameName(record.game))
  standings(c, record.top)
  c:textCenter(math.floor(c.w / 2), c.h - 4, "Chips, not tokens.", C.text)
end

local function pagePast(c, past, at)
  title(c, "WINNERS", "owner: touch the wall to start a tournament")
  if #past == 0 then
    c:textCenter(math.floor(c.w / 2), 44, "No tournaments played yet", C.mute)
    return
  end
  for i, record in ipairs(past) do
    local y = TOP + (i - 1) * ROW_H
    local winner = record.top[1]
    if i % 2 == 1 then c:rect(3, y, c.w - 4, ROW_H, C.feltDark) end
    c:big(5, y + 1, short(winner.name), C.gold, 1)
    c:text(76, y + 2, rules.gameName(record.game), C.text)
    c:text(76, y + 4, ui.group(winner.chips) .. " chips", C.text)
    local ago = math.floor((at - record.at) / 3600000)
    local when = ago < 1 and "today" or ago < 24 and (ago .. "h ago") or (math.floor(ago / 24) .. "d ago")
    c:text(c.w - 3 - #when, y + 4, when, C.text)
  end
end

--- The wall's tournament page: the live board, then the final standings, then past winners.
function M.page(c, data, _, at)
  local book = data.contest
  if book.live then
    pageLive(c, book.live, at)
  elseif contest.showing(book, at) then
    pageFinal(c, book.past[1])
  else
    pagePast(c, book.past, at)
  end
end

--- The next page. With a contest on, every other page is the tournament's. back is the page to go on from, and the result
-- gives the new one.
function M.turn(page, back, count, showing)
  local own = count
  if page == own and back then return back % (own - 1) + 1, nil end
  if showing then return own, page end
  return page % count + 1, nil
end

-- ------------------------------------------------------------------ the owner's menu

--- A menu for the owner: stopping what runs, or starting something new.
function M.openMenu(book, at)
  return { step = contest.running(book.live, at) and "stop" or book.live and "closing" or "game", deadline = at + M.MENU_MS }
end

local function drawGames(c, menu)
  local width = math.floor((c.w - 8) / 2)
  title(c, "START A TOURNAMENT", "no tokens move")
  c:text(4, TOP - 1, "Pick a game", C.text)
  for i, id in ipairs(contest.GAMES) do
    local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
    ui.button(c, menu.buttons, { id = "game", value = id, label = rules.gameName(id), x = 4 + column * (width + 2),
      y = TOP + 1 + row * 10, w = width, h = 9, color = C.blue })
  end
  ui.actionBar(c, menu.buttons, { { id = "cancel", label = "CANCEL", color = C.red } })
end

local function drawLengths(c, menu)
  local specs = {}
  title(c, rules.gameName(menu.game), "no tokens move")
  c:textCenter(math.floor(c.w / 2), TOP + 4, "How long?", C.text)
  for _, minutes in ipairs(contest.LENGTHS) do
    specs[#specs + 1] = { id = "length", value = minutes, label = minutes .. " MIN", color = C.win, textColor = C.ink }
  end
  ui.actionRow(c, menu.buttons, specs, TOP + 8, 13)
  ui.actionBar(c, menu.buttons, { { id = "back", label = "BACK", color = C.panel2 }, { id = "cancel", label = "CANCEL", color = C.red } })
end

local function drawStop(c, menu, book, at)
  title(c, "TOURNAMENT", rules.gameName(book.live.game) .. ", " .. minutesLeft(book.live.ends - at))
  c:textCenter(math.floor(c.w / 2), TOP + 8, "End it now? Rounds still playing get to finish.", C.text)
  ui.actionBar(c, menu.buttons, { { id = "stop", label = "END IT", color = C.red }, { id = "cancel", label = "KEEP GOING", color = C.win, textColor = C.ink } })
end

local function drawClosing(c, menu)
  title(c, "TOURNAMENT", "time up")
  c:textCenter(math.floor(c.w / 2), TOP + 8, "The last scores are coming in. Touch again in a minute.", C.text)
  ui.actionBar(c, menu.buttons, { { id = "cancel", label = "OK", color = C.blue } })
end

--- Draw the menu in place of a page, and keep its buttons on it.
function M.drawMenu(c, menu, book, at)
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
  ui.bar(c, { title = "CASINO HUB" })
  menu.buttons = ui.newButtons()
  if menu.step == "game" then
    drawGames(c, menu)
  elseif menu.step == "length" then
    drawLengths(c, menu)
  elseif menu.step == "stop" then
    drawStop(c, menu, book, at)
  else
    drawClosing(c, menu)
  end
end

--- The owner touched the open menu. Returns the menu to keep open, or nil, and true if the contest changed.
function M.touch(menu, hit, book, by, at)
  menu.deadline = at + M.MENU_MS
  if not hit then return menu end
  if hit.id == "game" then
    menu.step, menu.game = "length", hit.value
  elseif hit.id == "back" then
    menu.step, menu.game = "game", nil
  elseif hit.id == "length" then
    return nil, contest.start(book, menu.game, hit.value, by, at) ~= nil
  elseif hit.id == "stop" then
    return nil, contest.stop(book, at)
  elseif hit.id == "cancel" then
    return nil
  end
  return menu
end

return M
