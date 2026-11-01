-- games/blightmare/view_talk.lua
-- Speech: a portrait at the left of a box along the bottom, tiny text, a tap to page on. Big letters are for the moments that
-- want them. The rules do the wrapping and paging, so all this does is put them on the wall.

local rules = require("games.blightmare.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor

local M = {}

local BOX_H = 17
local TEXT_X = 24             -- right of the portrait, and the width leaves SAVE & QUIT alone
local PLAIN_X = 3             -- narration has no portrait
local ROW_H, ROW_GAP = 5, 1   -- a choice row is big enough to tap
local ROW_W = rules.SAY_WIDE

local function boxY(L) return L.H - BOX_H end

--- Where the rows of a choice sit, above the box so the question stays in sight.
local function rowY(L, count, i)
  return boxY(L) - (count - i + 1) * (ROW_H + ROW_GAP)
end

--- Who the player is facing, on foot: most people who speak in a borrowed voice are standing right there.
local function facing(s)
  local run = s.run
  if not run or run.back == "world" or s.x == nil then return nil end
  local npc = rules.npcAt(s, rules.ahead(s))
  return npc and npc.id
end

local function drawBox(L, s, talk)
  local y = boxY(L)
  ui.fill(0, y, L.W, BOX_H, C.panel)
  ui.fill(0, y, L.W, 1, C.line)
  local x, top = PLAIN_X, y + 2
  if talk.say then
    ui.fill(2, y + 1, 20, 15, C.bg)
    local art = require("games.blightmare.art")
    art.portrait(art.faceFor and art.faceFor(talk.say, talk.name, facing(s)) or talk.say, 2, y + 1)
    x, top = TEXT_X, y + 3
    ui.small(talk.name, x, y + 1, C.hi, C.panel, "left", rules.SAY_WIDE)
  end
  for i, line in ipairs(talk.lines) do ui.small(line, x, top + (i - 1) * 2, C.text, C.panel) end
  if not talk.choices then
    ui.small(talk.more and "TAP FOR MORE" or "TAP", TEXT_X + rules.SAY_WIDE - 1, y + 15, C.line, C.panel, "right")
  end
end

local function drawBig(L, talk)
  local lines = talk.big
  local step = ui.fontHeight() + 2
  local h = #lines * step + 3
  local y = floor((L.H - h) / 2) - 8
  ui.fill(2, y, L.W - 4, h, C.bg)
  ui.frame(2, y, L.W - 4, h, C.red)
  for i, line in ipairs(lines) do
    ui.text(line, floor(L.W / 2), y + 2 + (i - 1) * step, C.hi, "center", L.W - 6)
  end
end

local function drawChoices(L, talk)
  local count = #talk.choices
  for i, label in ipairs(talk.choices) do
    local y = rowY(L, count, i)
    ui.fill(TEXT_X, y, ROW_W, ROW_H, C.bg)
    ui.frame(TEXT_X, y, ROW_W, ROW_H, C.hi)
    ui.small(label, TEXT_X + 2, y + 2, C.text, C.bg, "left", ROW_W - 4)
  end
end

function M.draw(L, s)
  local talk = rules.talk(s)
  if not talk then return end
  if talk.big then drawBig(L, talk) end
  if talk.lines then drawBox(L, s, talk) end
  if talk.choices then drawChoices(L, talk) end
end

--- A tap anywhere pages on. A choice takes a tap on one of its rows and nothing else, so a stray tap can't answer it.
function M.actionAt(L, s, px, py)
  local talk = rules.talk(s)
  if not talk or talk.wait == "fade" then return nil end
  if talk.choices then
    local count = #talk.choices
    for i = 1, count do
      local y = rowY(L, count, i)
      if px >= TEXT_X and px < TEXT_X + ROW_W and py >= y and py < y + ROW_H then return { kind = "pick", i = i } end
    end
    return nil
  end
  return { kind = "tap" }
end

-- ---------------------------------------------------------------- asking a name

local KEY_W, KEY_H, KEY_X, KEY_Y, KEYS_A_ROW = 12, 10, 2, 22, 9
local DONE_X, DONE_Y, DONE_W, DONE_H = 42, 57, 38, 12

local function keyAt(key)
  local col, row = (key - 1) % KEYS_A_ROW, floor((key - 1) / KEYS_A_ROW)
  return KEY_X + col * (KEY_W + 1), KEY_Y + row * (KEY_H + 1)
end

function M.drawName(L, s)
  ui.fill(0, 0, L.W, L.H, C.bg)
  ui.text("WHAT IS YOUR NAME?", floor(L.W / 2), 2, C.hi, "center", L.W - 4)
  ui.text(s.naming.text .. "_", floor(L.W / 2), 12, C.text, "center", L.W - 4)
  for key = 1, 26 do
    local x, y = keyAt(key)
    ui.fill(x, y, KEY_W, KEY_H, C.panel)
    ui.frame(x, y, KEY_W, KEY_H, C.line)
    ui.text(string.char(64 + key), x + floor(KEY_W / 2), y + 2, C.text, "center")
  end
  local x, y = keyAt(rules.NAME_DELETE)
  ui.fill(x, y, KEY_W, KEY_H, C.panel)
  ui.frame(x, y, KEY_W, KEY_H, C.warn)
  ui.small("DEL", x + floor(KEY_W / 2), y + 4, C.warn, C.panel, "center")
  ui.fill(DONE_X, DONE_Y, DONE_W, DONE_H, C.panel)
  ui.frame(DONE_X, DONE_Y, DONE_W, DONE_H, C.ok)
  ui.text("DONE", DONE_X + floor(DONE_W / 2), DONE_Y + 3, C.ok, "center")
end

function M.nameAt(L, px, py)
  if px >= DONE_X and px < DONE_X + DONE_W and py >= DONE_Y and py < DONE_Y + DONE_H then
    return { kind = "pick", i = rules.NAME_DONE }
  end
  for key = 1, rules.NAME_DELETE do
    local x, y = keyAt(key)
    if px >= x and px < x + KEY_W and py >= y and py < y + KEY_H then return { kind = "pick", i = key } end
  end
  return nil
end

return M
