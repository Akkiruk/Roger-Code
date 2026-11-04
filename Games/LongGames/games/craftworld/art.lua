-- games/craftworld/art.lua
-- How everything looks, in a few fills each. A block is 6 cells wide and 4 tall, which looks near enough square on a
-- monitor, where a cell is twice as tall as it is wide. A texture is a base colour and a list of { dx, dy, w, h, colour }
-- marks on it; every other block is drawn mirrored, so a hillside doesn't look like wallpaper.

local ui = require("lib.arcade.ui")

local M = {}
local C = ui.C
local fill = ui.fill

M.TW, M.TH = 6, 4

-- ---------------------------------------------------------------- blocks

local STONE = {
  { 0, 1, 2, 1, "panel" }, { 4, 0, 1, 1, "line" }, { 3, 2, 2, 1, "panel" }, { 1, 3, 1, 1, "line" },
}

local function stoneWith(ink, marks)
  local out = {}
  for _, m in ipairs(STONE) do out[#out + 1] = m end
  for _, m in ipairs(marks) do out[#out + 1] = { m[1], m[2], m[3], m[4], ink } end
  return out
end

-- see: false for blocks drawn over what's behind them (torches, beds, glass, doors)
local TEX = {
  g = { base = "redTint", marks = { { 0, 0, 6, 1, "ok" }, { 1, 0, 1, 1, "soft" }, { 4, 0, 1, 1, "soft" }, { 0, 1, 1, 1, "ok" },
    { 3, 1, 1, 1, "ok" }, { 4, 2, 1, 1, "hiTint" }, { 1, 3, 1, 1, "hiTint" } } },
  d = { base = "redTint", marks = { { 1, 0, 1, 1, "hiTint" }, { 4, 1, 1, 1, "hiTint" }, { 2, 2, 1, 1, "warn" }, { 0, 3, 2, 1, "hiTint" },
    { 5, 3, 1, 1, "hiTint" } } },
  a = { base = "hi", marks = { { 1, 1, 1, 1, "warn" }, { 4, 2, 1, 1, "text" }, { 2, 3, 1, 1, "warn" }, { 5, 0, 1, 1, "warn" } } },
  s = { base = "tie", marks = STONE },
  c = { base = "tie", marks = { { 0, 0, 2, 1, "line" }, { 3, 0, 2, 1, "line" }, { 2, 0, 1, 2, "panel" }, { 5, 0, 1, 2, "panel" },
    { 0, 2, 6, 1, "panel" }, { 1, 3, 2, 1, "line" }, { 3, 3, 1, 1, "panel" }, { 4, 3, 2, 1, "line" } } },
  w = { base = "blueTint", marks = { { 1, 1, 2, 1, "blue" }, { 4, 3, 1, 1, "blue" } } },
  l = { base = "redTint", marks = { { 1, 0, 1, 4, "hiTint" }, { 4, 0, 1, 4, "hiTint" }, { 2, 1, 1, 1, "warn" }, { 5, 2, 1, 1, "warn" } } },
  f = { base = "ok", marks = { { 1, 0, 1, 1, "soft" }, { 4, 1, 1, 1, "soft" }, { 2, 2, 1, 1, "hiTint" }, { 0, 3, 1, 1, "hiTint" },
    { 5, 3, 1, 1, "soft" }, { 3, 0, 1, 1, "hiTint" } } },
  p = { base = "warn", marks = { { 0, 1, 6, 1, "redTint" }, { 0, 3, 6, 1, "redTint" }, { 2, 0, 1, 1, "redTint" }, { 4, 2, 1, 1, "redTint" } } },
  k = { base = "tie", marks = stoneWith("bg", { { 1, 1, 2, 1 }, { 4, 2, 1, 1 }, { 2, 3, 1, 1 }, { 5, 0, 1, 1 } }) },
  i = { base = "tie", marks = stoneWith("warn", { { 1, 1, 1, 1 }, { 4, 0, 1, 1 }, { 3, 2, 2, 1 }, { 0, 3, 1, 1 } }) },
  o = { base = "tie", marks = stoneWith("hi", { { 1, 1, 2, 1 }, { 4, 2, 1, 1 }, { 1, 3, 1, 1 }, { 5, 0, 1, 1 } }) },
  x = { base = "tie", marks = stoneWith("info", { { 1, 1, 2, 1 }, { 4, 2, 1, 1 }, { 2, 3, 1, 1 }, { 5, 0, 1, 1 }, { 1, 1, 1, 1, "text" } }) },
  B = { base = "panel", marks = { { 0, 0, 2, 1, "tie" }, { 3, 1, 2, 1, "bg" }, { 1, 2, 1, 2, "bg" }, { 4, 3, 2, 1, "tie" }, { 5, 0, 1, 1, "bg" } } },
  T = { base = "redTint", marks = { { 0, 0, 6, 1, "warn" }, { 1, 1, 1, 2, "line" }, { 2, 1, 1, 1, "line" }, { 4, 1, 1, 2, "hiTint" },
    { 3, 2, 2, 1, "hiTint" }, { 0, 3, 1, 1, "warn" }, { 5, 3, 1, 1, "warn" } }, keep = true },
  F = { base = "tie", marks = { { 0, 0, 6, 1, "line" }, { 2, 1, 2, 2, "bg" }, { 2, 2, 2, 1, "warn" }, { 0, 3, 6, 1, "panel" } }, keep = true },
  t = { see = true, marks = { { 2, 0, 2, 1, "hi" }, { 2, 1, 2, 1, "warn" }, { 2, 2, 2, 2, "redTint" } } },
  D = { see = true, marks = { { 1, 0, 4, 4, "warn" }, { 1, 0, 1, 4, "redTint" }, { 2, 0, 2, 1, "blueTint" }, { 4, 2, 1, 1, "hi" } }, keep = true },
  b = { see = true, marks = { { 0, 2, 2, 1, "text" }, { 2, 1, 4, 2, "red" }, { 2, 1, 4, 1, "red" }, { 0, 3, 6, 1, "redTint" },
    { 0, 1, 1, 1, "redTint" } }, keep = true },
  y = { see = true, marks = { { 0, 0, 6, 1, "line" }, { 0, 3, 6, 1, "line" }, { 0, 0, 1, 4, "line" }, { 5, 0, 1, 4, "line" }, { 2, 1, 1, 1, "text" },
    { 3, 2, 1, 1, "text" } }, keep = true },
}
M.TEX = TEX

--- Is a block drawn over what's behind it?
function M.seeThrough(c) return TEX[c] and TEX[c].see or false end

--- A block at screen x, y. flip mirrors it (nothing that has a right way round is flipped).
function M.block(c, x, y, flip)
  local tex = TEX[c]
  if not tex then return end
  if tex.base then fill(x, y, 6, 4, C[tex.base]) end
  local mirror = flip and not tex.keep
  for _, m in ipairs(tex.marks) do
    local dx = mirror and (6 - m[1] - m[3]) or m[1]
    fill(x + dx, y + m[2], m[3], m[4], C[m[5]])
  end
end

--- Water with air over it has a bright edge on top.
function M.waterTop(x, y)
  fill(x, y, 6, 1, C.blue)
  fill(x + 1, y, 2, 1, C.info)
end

local CRACKS = {
  { { 2, 1, 1, 1 } },
  { { 2, 1, 1, 1 }, { 3, 2, 2, 1 } },
  { { 2, 1, 1, 1 }, { 3, 2, 2, 1 }, { 1, 0, 1, 1 }, { 4, 3, 1, 1 } },
  { { 2, 1, 1, 1 }, { 3, 2, 2, 1 }, { 1, 0, 1, 1 }, { 4, 3, 1, 1 }, { 0, 2, 2, 1 }, { 4, 0, 1, 1 } },
}

--- A block part dug: share is how far, 0 to 1.
function M.cracks(x, y, share)
  local set = CRACKS[math.max(1, math.min(#CRACKS, math.floor(share * #CRACKS) + 1))]
  for _, m in ipairs(set) do fill(x + m[1], y + m[2], m[3], m[4], C.bg) end
end

-- ---------------------------------------------------------------- people and animals
-- Drawn facing right; dir -1 mirrors them. A row of -1 is the head, poking above the block.

local SPRITES = {
  player = { { 2, -1, 2, 1, "redTint" }, { 2, 0, 2, 1, "warn" }, { 3, 0, 1, 1, "blueTint" }, { 1, 1, 4, 1, "info" },
    { 0, 1, 1, 1, "warn" }, { 5, 1, 1, 1, "warn" }, { 2, 2, 2, 2, "blue" } },
  zombie = { { 2, -1, 2, 1, "ok" }, { 2, 0, 2, 1, "ok" }, { 3, 0, 1, 1, "bg" }, { 1, 1, 3, 1, "info" }, { 4, 1, 2, 1, "ok" },
    { 2, 2, 2, 2, "blueTint" } },
  skeleton = { { 2, -1, 2, 1, "text" }, { 2, 0, 2, 1, "line" }, { 3, 0, 1, 1, "bg" }, { 2, 1, 2, 1, "text" }, { 1, 1, 1, 1, "line" },
    { 4, 1, 1, 1, "line" }, { 2, 2, 1, 2, "line" }, { 3, 3, 1, 1, "line" }, { 5, 0, 1, 3, "warn" } },
  pig = { { 0, 1, 5, 2, "red" }, { 4, 0, 2, 2, "red" }, { 5, 1, 1, 1, "redTint" }, { 4, 0, 1, 1, "bg" }, { 1, 3, 1, 1, "redTint" },
    { 3, 3, 1, 1, "redTint" } },
  cow = { { 0, 1, 5, 2, "text" }, { 1, 1, 1, 1, "bg" }, { 3, 2, 1, 1, "bg" }, { 4, 0, 2, 2, "bg" }, { 5, 0, 1, 1, "line" },
    { 1, 3, 1, 1, "line" }, { 3, 3, 1, 1, "line" } },
  sheep = { { 0, 1, 5, 2, "text" }, { 1, 0, 3, 1, "text" }, { 5, 1, 1, 1, "tie" }, { 4, 1, 1, 1, "line" }, { 1, 3, 1, 1, "tie" },
    { 3, 3, 1, 1, "tie" } },
}
M.SPRITES = SPRITES

local TIER_INK = { [0] = "warn", "warn", "line", "text", "info" }

function M.sprite(kind, x, y, dir, burn)
  local list = SPRITES[kind]
  for _, m in ipairs(list) do
    local dx = dir == -1 and (6 - m[1] - m[3]) or m[1]
    fill(x + dx, y + m[2], m[3], m[4], C[m[5]])
  end
  if burn then
    fill(x + 1, y - 1, 1, 1, C.warn)
    fill(x + 4, y, 1, 1, C.hi)
  end
end

--- What the player holds out in front: the item in hand, or the pickaxe.
function M.inHand(x, y, dir, pickTier, held)
  local hx = dir == -1 and x - 1 or x + 6
  if held then
    local tex = TEX[(M.PLACE or {})[held] or ""]
    if tex and tex.base then
      fill(hx, y + 1, 1, 1, C[tex.base])
      return
    end
  end
  if pickTier > 0 then
    fill(hx, y, 1, 1, C[TIER_INK[pickTier]])
    fill(hx, y + 1, 1, 1, C.redTint)
  end
end

--- Eyes in the dark.
function M.eyes(x, y)
  fill(x + 2, y, 1, 1, C.red)
  fill(x + 4, y, 1, 1, C.red)
end

-- ---------------------------------------------------------------- icons, for the bar and the menu (6 x 4 too)

local function pickaxe(ink)
  return { { 1, 0, 4, 1, ink }, { 0, 1, 1, 1, ink }, { 5, 1, 1, 1, ink }, { 3, 1, 1, 3, "redTint" } }
end
local function sword(ink)
  return { { 4, 0, 1, 1, ink }, { 3, 1, 1, 1, ink }, { 2, 2, 1, 1, ink }, { 1, 2, 1, 1, "redTint" }, { 2, 3, 1, 1, "redTint" },
    { 0, 3, 1, 1, "redTint" } }
end
local function armour(ink)
  return { { 1, 0, 1, 1, ink }, { 4, 0, 1, 1, ink }, { 1, 1, 4, 3, ink }, { 2, 0, 2, 1, ink } }
end

local ICONS = {
  stick = { { 4, 0, 1, 1, "warn" }, { 3, 1, 1, 1, "warn" }, { 2, 2, 1, 1, "warn" }, { 1, 3, 1, 1, "warn" } },
  coal = { { 1, 1, 4, 2, "bg" }, { 2, 0, 2, 1, "bg" }, { 2, 1, 1, 1, "tie" } },
  iron = { { 1, 1, 4, 2, "line" }, { 1, 1, 4, 1, "text" } },
  gold = { { 1, 1, 4, 2, "warn" }, { 1, 1, 4, 1, "hi" } },
  diamond = { { 2, 0, 2, 1, "info" }, { 1, 1, 4, 1, "info" }, { 2, 2, 2, 1, "info" }, { 2, 1, 1, 1, "text" } },
  apple = { { 1, 1, 4, 2, "red" }, { 2, 3, 2, 1, "red" }, { 3, 0, 1, 1, "ok" }, { 2, 1, 1, 1, "text" } },
  golden_apple = { { 1, 1, 4, 2, "hi" }, { 2, 3, 2, 1, "hi" }, { 3, 0, 1, 1, "ok" }, { 2, 1, 1, 1, "text" } },
  raw_meat = { { 1, 1, 4, 2, "red" }, { 4, 1, 1, 1, "text" }, { 0, 2, 1, 1, "red" } },
  cooked_meat = { { 1, 1, 4, 2, "redTint" }, { 2, 1, 2, 1, "warn" }, { 0, 2, 1, 1, "redTint" } },
  wool = { { 0, 0, 6, 4, "text" }, { 1, 1, 1, 1, "line" }, { 4, 2, 1, 1, "line" } },
  hand = { { 2, 0, 2, 1, "warn" }, { 1, 1, 4, 2, "warn" }, { 1, 1, 1, 1, "redTint" } },
  iron_ore = TEX.i.marks, gold_ore = TEX.o.marks,
}
for tier = 1, 4 do
  ICONS["pick" .. tier] = pickaxe(TIER_INK[tier])
  ICONS["sword" .. tier] = sword(TIER_INK[tier])
end
ICONS.armour1 = armour("text")
ICONS.armour2 = armour("info")
M.TIER_INK = TIER_INK

-- items that are blocks look like the block
M.PLACE = {}

--- An item's picture at x, y, on a background of bg.
function M.icon(item, x, y)
  local tile = M.PLACE[item]
  if tile then
    M.block(tile, x, y, false)
    return
  end
  local marks = ICONS[item]
  if not marks then return end
  if item == "iron_ore" or item == "gold_ore" then fill(x, y, 6, 4, C.tie) end
  for _, m in ipairs(marks) do fill(x + m[1], y + m[2], m[3], m[4], C[m[5]]) end
end

return M
