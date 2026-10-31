-- playercard.lua
-- One wall page for the seated player: their record at this table, how the last rounds went, and their badges.
-- Laid out for 121x81 with cells 2 wide by 3 tall, so a block 7 wide and 5 tall looks square.
-- A table is one game, so a favourite game only means something casino-wide: it comes from the hub, for a player on its
-- leaderboard who has played more than one game, and with no hub the card leaves it off.

local audio = require("lib.casino.audio")
local badges = require("lib.casino.badges")
local net = require("lib.casino.net")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local FORM = { W = C.win, L = C.red, P = C.gold }
local MARGIN = 5
local TILES_Y, TILE_H = 16, 9
local BAR_Y, BAR_H = 26, 3
local FORM_Y, BLOCK_W, BLOCK_H, BLOCK_GAP = 34, 7, 5, 2
local BADGES_Y, BADGE_ROWS = 41, 4

M.COLUMNS = 2

local function short(text, limit)
  text = tostring(text)
  if #text <= limit then return text end
  return text:sub(1, math.max(1, limit - 1)) .. "."
end

--- Rows of badges the wall has room for.
function M.rowsFree(c)
  return math.floor((c.h - ui.ACTIONS_H - 1 - BADGES_Y - 1) / BADGE_ROWS)
end

--- The hub's word on this player's favourite game, if it has one.
local function favourite(name)
  local hub = net.hub()
  for _, entry in ipairs(hub and hub.leaders or {}) do
    if entry.name == name and type(entry.fav) == "string" then return entry.fav end
  end
  return nil
end

--- All the card needs, read once as it opens.
function M.read(name, game)
  local player = badges.player(name)
  player.name = name
  player.fav = favourite(name)
  player.list = badges.list(game)
  return player
end

local function tile(c, x, w, label, value, color)
  c:rect(x, TILES_Y, w, TILE_H, C.feltDark)
  c:text(x + 1, TILES_Y, label, C.mute)
  if c:bigWidth(value, 1) <= w - 2 then
    c:big(x + 1, TILES_Y + 2, value, color, 1)
  else
    c:text(x + 1, TILES_Y + 4, short(value, w - 2), color)
  end
end

local function winLossBar(c, p)
  local x, w = MARGIN, c.w - MARGIN * 2 + 1
  local total = p.wins + p.losses + p.pushes
  c:rect(x, BAR_Y, w, BAR_H, C.feltDark)
  if total > 0 then
    local wins = math.floor(w * p.wins / total + 0.5)
    local pushes = math.min(math.floor(w * p.pushes / total + 0.5), w - wins)
    c:rect(x, BAR_Y, wins, BAR_H, FORM.W)
    c:rect(x + wins, BAR_Y, pushes, BAR_H, FORM.P)
    c:rect(x + wins + pushes, BAR_Y, w - wins - pushes, BAR_H, FORM.L)
  end
  local line = ("%s won   %s lost   %s level"):format(ui.group(p.wins), ui.group(p.losses), ui.group(p.pushes))
  if total > 0 then line = line .. ("   %d%% won"):format(math.floor(p.wins / total * 100 + 0.5)) end
  c:textCenter(math.floor(c.w / 2), BAR_Y + BAR_H, line, C.text)
end

--- Oldest on the left, so the newest round is always the last block filled.
local function recentForm(c, p)
  c:text(MARGIN, FORM_Y - 2, ("LAST %d ROUNDS, OLDEST FIRST"):format(badges.FORM_KEPT), C.gold)
  for i = 1, badges.FORM_KEPT do
    local x = MARGIN + (i - 1) * (BLOCK_W + BLOCK_GAP)
    c:rect(x, FORM_Y, BLOCK_W, BLOCK_H, FORM[p.form:sub(i, i)] or C.feltDark)
  end
end

local function badgeRow(c, x, y, w, def, had)
  c:rect(x, y, 2, 2, had and C.gold or C.feltDark)
  c:text(x + 3, y, short(def.name, w - 4), had and C.gold or C.text)
  c:text(x + 3, y + 1, short(def.text, w - 4), had and C.text or C.mute)
end

local function badgeList(c, p)
  local got = 0
  for _, def in ipairs(p.list) do
    if p.have[def.id] then got = got + 1 end
  end
  c:text(MARGIN, BADGES_Y, ("BADGES %d OF %d"):format(got, #p.list), C.gold)
  local rows = M.rowsFree(c)
  local w = math.floor((c.w - MARGIN * 2) / M.COLUMNS)
  for i, def in ipairs(p.list) do
    local row = math.floor((i - 1) / M.COLUMNS)
    if row >= rows then break end
    local column = (i - 1) % M.COLUMNS
    badgeRow(c, MARGIN + column * w, BADGES_Y + 2 + row * BADGE_ROWS, w, def, p.have[def.id])
  end
end

--- Draw the card over whatever is there, all but the bar along the bottom.
function M.draw(c, ctx, p)
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
  ui.bar(c, ctx)
  c:big(MARGIN, ui.BAR_H + 1, short(p.name, 18), C.gold, 1)
  if p.fav then
    local line = "Favourite game " .. p.fav
    c:text(c.w - MARGIN - #line + 1, ui.BAR_H + 3, short(line, 40), C.text)
  end

  -- Money wants the room: a net has a sign and a comma, and a streak is two or three characters
  local x = MARGIN
  local streak = p.streak > 0 and ("W" .. p.streak) or p.streak < 0 and ("L" .. -p.streak) or "-"
  for _, part in ipairs({
    { 24, "ROUNDS", ui.group(p.rounds), C.text },
    { 34, "NET", ui.signed(p.net), p.net >= 0 and C.win or C.red },
    { 32, "BEST WIN", ui.group(p.best), C.gold },
    { 16, "STREAK", streak, p.streak > 0 and C.win or p.streak < 0 and C.red or C.text },
  }) do
    tile(c, x, part[1], part[2], part[3], part[4])
    x = x + part[1] + 2
  end

  winLossBar(c, p)
  recentForm(c, p)
  badgeList(c, p)
end

--- Show the card until it is closed or the player stops touching. Nothing moves here and nothing changes.
function M.open(tableObject, idleMs)
  local c, ctx = tableObject.c, tableObject.ctx
  local ok, p = pcall(M.read, ctx.seat, tableObject.game)
  if not ok then
    tableObject:toast("Your card cannot be read")
    return
  end
  local scene = { name = "card", deadline = os.epoch("utc") + idleMs }
  scene.debugState = function()
    return { rounds = p.rounds, net = p.net, best = p.best, wins = p.wins, losses = p.losses, pushes = p.pushes,
      streak = p.streak, form = p.form, fav = p.fav or false, have = p.have }
  end

  function scene.tick(s)
    if os.epoch("utc") > s.deadline then s.finished = true end
  end

  function scene.draw(s)
    M.draw(c, ctx, p)
    s.buttons = ui.newButtons()
    ui.actionBar(c, s.buttons, { { id = "close", label = "DONE", color = C.win, textColor = C.ink } })
  end

  function scene.touch(s, x, y)
    s.deadline = os.epoch("utc") + idleMs
    local hit = ui.hit(s.buttons or {}, x, y)
    if hit then
      audio.play("tap")
      s.finished = true
    end
  end

  tableObject:run(scene)
end

return M
