-- games/blightmare/view_menu.lua
-- The menu and shops: rows of native text down the left to tap, with the party or the purse to the right. Every row comes
-- from the rules, so a row here and a pick there can't disagree.

local rules = require("games.blightmare.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor

local M = {}

local ROWS_X, ROWS_Y, ROWS_W = 3, 11, 44
local ROW_H, ROW_GAP = 5, 1
local SIDE_X = 50
local BACK_W, BACK_H = 18, 7

local function party() return require("games.blightmare.party") end

local function memberName(s, member)
  if member.id == "hero" then return s.heroName end
  local char = party().CHARS[member.id]
  return char and char.name or member.id
end

local function gearName(id)
  local def = id and party().GEAR[id]
  return def and def.name or "-"
end

local function drawBar(x, y, w, share, color)
  ui.fill(x, y, w, 1, C.bg)
  ui.fill(x, y, math.max(share > 0 and 1 or 0, floor(w * math.min(1, share))), 1, color)
end

local function hpColor(share)
  if share > 0.5 then return C.ok end
  return share > 0.25 and C.warn or C.red
end

local function drawRows(rows, right)
  for i, row in ipairs(rows) do
    local y = ROWS_Y + (i - 1) * (ROW_H + ROW_GAP)
    local ink = row.dim and C.line or C.text
    ui.fill(ROWS_X, y, ROWS_W, ROW_H, C.panel)
    ui.small(row.label, ROWS_X + 2, y + 2, ink, C.panel, "left", ROWS_W - 12)
    if right and right(row) then ui.small(right(row), ROWS_X + ROWS_W - 2, y + 2, row.afford == false and C.red or C.hi, C.panel, "right") end
  end
end

local function drawTop(L, title)
  ui.fill(0, 0, L.W, L.H, C.bg)
  ui.text(title, ROWS_X, 1, C.hi)
  ui.fill(L.W - BACK_W - 2, 1, BACK_W, BACK_H, C.panel)
  ui.small("BACK", L.W - 2 - floor(BACK_W / 2), 4, C.text, C.panel, "center")
end

local function drawPartyLine(s, member, y)
  local stats = party().stats(member)
  local share = member.hp / stats.maxHp
  ui.small(memberName(s, member), SIDE_X, y, C.text, C.bg, "left", 22)
  ui.small("LV " .. member.lvl, SIDE_X + 24, y, C.hi, C.bg)
  ui.small("HP", SIDE_X, y + 1, C.line, C.bg)
  drawBar(SIDE_X + 3, y + 1, 26, share, hpColor(share))
  ui.small(member.hp .. "/" .. stats.maxHp, SIDE_X + 31, y + 1, hpColor(share), C.bg)
  if stats.maxMp > 0 then
    ui.small("MP", SIDE_X, y + 2, C.line, C.bg)
    drawBar(SIDE_X + 3, y + 2, 26, member.mp / stats.maxMp, C.blueTint)
    ui.small(member.mp .. "/" .. stats.maxMp, SIDE_X + 31, y + 2, C.blueTint, C.bg)
  end
end

local function drawParty(s, y)
  for i, member in ipairs(s.party) do drawPartyLine(s, member, y + (i - 1) * 5) end
end

--- One character in full.
local function drawStatus(s, member, y)
  local stats = party().stats(member)
  local char = party().CHARS[member.id]
  drawPartyLine(s, member, y)
  local rows = {
    { "ROLE", (char.role or ""):upper() }, { "SPECIAL", char.special or "-" },
    { "ATTACK", stats.atk }, { "DEFENCE", stats.def }, { "MAGIC", stats.mag }, { "SPEED", stats.spd },
    { "WEAPON", gearName(member.weapon) }, { "ARMOUR", gearName(member.armour) }, { "ACCESSORY", gearName(member.accessory) },
    { "XP TO NEXT", math.max(0, party().xpFor(member.lvl + 1) - member.xp) },
  }
  for i, row in ipairs(rows) do
    ui.small(row[1], SIDE_X, y + 3 + i * 2, C.line, C.bg)
    ui.small(row[2], SIDE_X + 14, y + 3 + i * 2, C.text, C.bg)
  end
end

local PAGE_TITLE = { main = "MENU", items = "ITEMS", useon = "USE ON", gear = "GEAR", equip = "EQUIP", status = "STATUS", party = "PARTY", travel = "TRAVEL" }

local function drawMenu(L, s)
  local menu = s.menu
  drawTop(L, PAGE_TITLE[menu.page] or "MENU")
  local rows = rules.menuRows(s)
  for _, row in ipairs(rows) do row.dim = (row.item and not row.field) or (row.swap and row.picked) end
  drawRows(rows)
  if menu.page == "items" and #rows == 0 then ui.small("Nothing in the bag.", ROWS_X, ROWS_Y, C.line, C.bg) end
  if menu.page == "equip" and #rows == 0 then ui.small("No spare gear to wear.", ROWS_X, ROWS_Y, C.line, C.bg) end
  local member = menu.who and s.party[menu.who]
  if menu.page == "status" then
    drawStatus(s, member or s.party[1], ROWS_Y)
  else
    drawParty(s, ROWS_Y)
  end
  if menu.page == "equip" and member then
    local y = ROWS_Y + #s.party * 5 + 1
    ui.small(memberName(s, member) .. " wears", SIDE_X, y, C.hi, C.bg, "left", 50)
    ui.small("WEAPON " .. gearName(member.weapon), SIDE_X, y + 1, C.text, C.bg)
    ui.small("ARMOUR " .. gearName(member.armour), SIDE_X, y + 2, C.text, C.bg)
    ui.small("ACCESSORY " .. gearName(member.accessory), SIDE_X, y + 3, C.text, C.bg)
  end
  ui.small("GOLD " .. s.gold, ROWS_X, L.H - 5, C.hi, C.bg)
  if menu.line then ui.small(menu.line, ROWS_X, L.H - 3, C.text, C.bg, "left", 100) end
end

local function drawShop(L, s)
  drawTop(L, "SHOP")
  drawRows(rules.shopRows(s), function(row) return row.price and tostring(row.price) end)
  ui.small("GOLD " .. s.gold, SIDE_X, ROWS_Y, C.hi, C.bg)
  local y = ROWS_Y + 2
  local party_ = party()
  for _, id in ipairs(party_.ITEM_ORDER) do
    if s.bag[id] then
      ui.small(rules.itemName(id) .. " x" .. s.bag[id], SIDE_X, y, C.text, C.bg)
      y = y + 1
    end
  end
  if s.shop.line then ui.small(s.shop.line, ROWS_X, L.H - 3, C.text, C.bg, "left", 100) end
end

function M.draw(L, s)
  if s.mode == "shop" then drawShop(L, s) else drawMenu(L, s) end
end

--- A row is a pick, and BACK goes up a page.
function M.actionAt(L, s, px, py)
  if px >= L.W - BACK_W - 2 and py <= BACK_H + 1 then return { kind = "back" } end
  if px < ROWS_X or px >= ROWS_X + ROWS_W or py < ROWS_Y then return nil end
  local i = floor((py - ROWS_Y) / (ROW_H + ROW_GAP)) + 1
  local into = (py - ROWS_Y) % (ROW_H + ROW_GAP)
  local rows = s.mode == "shop" and rules.shopRows(s) or rules.menuRows(s)
  if into < ROW_H and rows[i] then return { kind = "pick", i = i } end
  return nil
end

return M
