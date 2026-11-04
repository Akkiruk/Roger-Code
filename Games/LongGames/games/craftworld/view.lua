-- games/craftworld/view.lua
-- The wall: the world round the player, the bar along the bottom, and the menu. Nothing moves until the player does, so the
-- picture is painted once for each change into a surface of its own and the shell's steady redraw only copies it across,
-- as Dungeon does. A row of sky, or of darkness, is one fill however many blocks it crosses.

local art = require("games.craftworld.art")
local rules = require("games.craftworld.rules")
local ui = require("lib.arcade.ui")

local world = rules.world
local C = ui.C
local floor, max, min = math.floor, math.max, math.min
local TW, TH = art.TW, art.TH

local M = {}

local HUD_H = 13            -- the status line and the hotbar
local QUIT_X = 106          -- the shell's SAVE & QUIT is right of this, in the bottom rows
local SLOT_W, SLOT_H, SLOT_STEP = 10, 7, 11

for _, item in ipairs(rules.ITEMS) do
  if item.place then art.PLACE[item.id] = item.place end
end

--- Where everything goes on a wall of W x H cells.
function M.layout(W, H)
  local L = { W = W, H = H, x0 = 0, y0 = 0, bw = W, bh = H, statusY = 1 }
  L.hudY = H - HUD_H
  L.rows = floor(L.hudY / TH)
  L.hudY = L.rows * TH
  L.cols = floor(W / TW) + 2
  L.px = floor((W - TW) / 2)                  -- the player's block, on the screen
  L.prow = floor(L.rows * 0.42)
  L.py = L.prow * TH
  L.left = -(floor(L.px / TW) + 1)            -- the leftmost block column drawn, from the player's
  L.slotsY = H - SLOT_H - 1
  L.statusTop = L.hudY + 1
  return L
end

--- The block offset from the player under a screen cell.
function M.cellAt(L, px, py)
  return floor((px - L.px) / TW), floor((py - L.py) / TH)
end

-- ---------------------------------------------------------------- the world

local SKY = { day = "blue", dusk = "accent", night = "bg", dawn = "accent" }

local function skyInk(s) return C[SKY[rules.phase(s)]] end

local function starAt(x, y) return world.hash(x, y, 77) < 0.08 end

--- A cloud is a wide flat lump high in the sky, fixed to the world.
local function cloudAt(x, y)
  if y < 16 or y > 26 or y % 5 ~= 1 then return false end
  local band = floor(x / 7)
  return world.hash(band, y, 78) < 0.35 and x % 7 ~= 0
end

local function drawWorld(L, s)
  local p = s.p
  local x0, y0 = p.x + L.left, p.y - L.prow
  local cols, rows = L.cols, L.rows
  local lit, sky = world.lightWindow(s, x0, y0, cols, rows, p.x, p.y)
  local skyC = skyInk(s)
  local night = rules.phase(s) == "night"
  local mobs = {}
  for _, m in ipairs(s.mobs) do mobs[m.y * 65536 + m.x] = m end
  local sx0 = L.px + L.left * TW
  for row = 1, rows do
    local y = y0 + row - 1
    local sy = (row - 1) * TH
    local litRow, skyRow = lit[row], sky[row]
    -- first the backgrounds, in runs: sky, lit cave, darkness
    local runFrom, runInk = 1, nil
    local inks = {}
    for col = 1, cols do
      local x = x0 + col - 1
      local c = world.tileAt(s, x, y)
      local ink
      if not litRow[col] then
        ink = C.bg
      elseif c == " " or art.seeThrough(c) then
        ink = skyRow[col] and skyC or C.panel
      else
        ink = false -- a block that covers its whole cell
      end
      inks[col] = { c = c, ink = ink }
    end
    for col = 1, cols + 1 do
      local ink = col <= cols and inks[col].ink or nil
      if ink ~= runInk then
        if runInk then ui.fill(sx0 + (runFrom - 1) * TW, sy, (col - runFrom) * TW, TH, runInk) end
        runFrom, runInk = col, ink
      end
    end
    -- then the blocks, and what's in the sky
    for col = 1, cols do
      local x = x0 + col - 1
      local cell = inks[col]
      local sx = sx0 + (col - 1) * TW
      if litRow[col] then
        local c = cell.c
        if c ~= " " then
          art.block(c, sx, sy, (x + y) % 2 == 1)
          if c == "w" and world.tileAt(s, x, y - 1) == " " then art.waterTop(sx, sy) end
        elseif skyRow[col] then
          if night and starAt(x, y) then
            ui.fill(sx + 2 + floor(world.hash(x, y, 79) * 3), sy + 1, 1, 1, C.text)
          elseif not night and cloudAt(x, y) then
            ui.fill(sx, sy, TW, 1, C.text)
            if world.hash(x, y, 80) < 0.5 then ui.fill(sx + 1, sy + 1, TW - 2, 1, C.text) end
          end
        end
        local d = s.dig
        if d and d.x == x and d.y == y then art.cracks(sx, sy, d.n / max(1, d.of)) end
      elseif cell.c ~= " " and cell.c ~= "w" then
        -- rock in the dark: a dot or two, so a cave shows as a cave without giving away what's in the walls
        local h = world.hash(x, y, 81)
        ui.fill(sx + floor(h * 5), sy + floor(h * 37) % 4, 1, 1, C.panel)
        if h < 0.5 then ui.fill(sx + 5 - floor(h * 9), sy + 3 - floor(h * 23) % 4, 1, 1, C.panel) end
      end
      local m = mobs[y * 65536 + x]
      if m then
        if litRow[col] then
          art.sprite(m.k, sx, sy, m.dir or -1, m.burn and rules.phase(s) == "day")
        elseif rules.MOBS[m.k].hostile then
          art.eyes(sx, sy)
        end
      end
    end
  end
  -- anyone else in the world, with their name over them; off the wall, a pointer at its edge
  local mine = "player"
  local everyone = rules.players(s)
  for _, e in ipairs(everyone) do
    if e.p == p then
      mine = e.seat and "friend" or "player"
    elseif #everyone > 1 then
      local sx, sy = L.px + (e.p.x - p.x) * TW, L.py + (e.p.y - p.y) * TH
      local name = (e.name or "PLAYER"):upper()
      if sx > -TW and sx < L.W and sy > 0 and sy < L.hudY - TH then
        art.sprite(e.seat and "friend" or "player", sx, sy, e.p.facing or 1)
        local tagY = sy - 3
        if tagY >= 0 then ui.small(name, sx + 3, tagY, C.text, C.bg, "center", 14) end
      else
        local left = e.p.x < p.x
        local tagY = max(3, min(L.hudY - 2, sy))
        local text = left and ("< " .. name) or (name .. " >")
        ui.small(text, left and 0 or L.W, tagY, C.hi, C.bg, left and "left" or "right", 18)
      end
    end
  end
  -- the player, and what they hold
  local held = rules.held(s)
  art.sprite(mine, L.px, L.py, p.facing or 1)
  art.inHand(L.px, L.py, p.facing or 1, p.pick, held)
  local arrow = s.fx.arrow
  if arrow then
    local ax, ay = L.px + (arrow[1] - p.x) * TW + 3, L.py + (arrow[2] - p.y) * TH + 1
    ui.line(ax, ay, L.px + 3, L.py + 1, C.text)
  end
  if s.fx.hurt > 0 then ui.frame(0, 0, L.W, L.hudY, C.red, 2) end
end

-- ---------------------------------------------------------------- the bar along the bottom

local function pips(x, y, value, full, empty)
  for i = 1, 10 do
    local px = x + (i - 1) * 3
    local have = value - (i - 1) * 2
    if have >= 2 then
      ui.fill(px, y, 2, 1, full)
    elseif have == 1 then
      ui.fill(px, y, 1, 1, full)
      ui.fill(px + 1, y, 1, 1, empty)
    else
      ui.fill(px, y, 2, 1, empty)
    end
  end
end

local function slotRect(L, i) -- i = 0 is the hand
  return 1 + i * SLOT_STEP, L.slotsY, SLOT_W, SLOT_H
end
M.slotRect = slotRect

local function drawHud(L, s)
  local p = s.p
  local y = L.hudY
  ui.fill(0, y, L.W, L.H - y, C.panel)
  ui.fill(0, y, L.W, 1, C.tie)
  local row = L.statusTop
  ui.small("HP", 1, row, C.text, C.panel)
  pips(4, row, p.hp, C.red, C.redTint)
  ui.small("FOOD", 35, row, C.text, C.panel)
  pips(40, row, p.food, C.warn, C.hiTint)
  local ph = rules.phase(s)
  local clock = ph == "night" and "NIGHT" or (ph == "day" and "DAY" or ph:upper())
  ui.small(clock .. " " .. rules.dayNumber(s), 71, row, ph == "night" and C.info or C.hi, C.panel)
  local depth = world.depth(p.y)
  ui.small(depth > 0 and ("DEPTH " .. depth) or "SURFACE", 84, row, C.line, C.panel)
  ui.small(s.mode == "menu" and " CLOSE " or " MENU ", L.W - 2, row, C.bg, C.hi, "right")
  local goal = rules.nextGoal(s)
  ui.small(goal and ("GOAL: " .. goal.text) or "Every goal done! Keep building.", 1, row + 2, C.accent, C.panel, "left", L.W - 22)
  ui.small("TAP BAR: CRAFT", L.W - 2, row + 2, C.line, C.panel, "right")
  -- the hotbar: the hand, then the items
  for i = 0, rules.BAR_SLOTS do
    local x, sy, w, h = slotRect(L, i)
    if x + w > QUIT_X then break end
    local item = i == 0 and "hand" or p.bar[i]
    local chosen = p.sel == i
    ui.fill(x, sy, w, h, chosen and C.hi or C.bg)
    ui.fill(x + 1, sy + 1, w - 2, h - 2, C.bg)
    if item then
      if i == 0 then
        art.icon(p.pick > 0 and ("pick" .. p.pick) or "hand", x + 2, sy + 1)
      else
        art.icon(item, x + 2, sy + 1)
        ui.small(tostring(p.inv[item] or 0), x + w - 2, sy + h - 2, C.text, C.bg, "right")
      end
    end
  end
end

-- ---------------------------------------------------------------- the menu

local TAB_Y, TAB_H = 1, 5
local LIST_Y, ROW_H = 9, 6
local PAGE_Y = 61

--- Every tappable part of the menu, with what it does and how to draw it: the drawing and the touches share this list,
--- so they can never disagree.
local function menuParts(L, s)
  local parts = {}
  local W = L.W
  local tabs = { { "craft", "CRAFT" }, { "items", "ITEMS" }, { "goals", "GOALS" } }
  for i, t in ipairs(tabs) do
    parts[#parts + 1] = { x = 2 + (i - 1) * 25, y = TAB_Y, w = 23, h = TAB_H, action = { kind = "tab", tab = t[1] }, tab = t[1], label = t[2] }
  end
  parts[#parts + 1] = { x = W - 26, y = TAB_Y, w = 24, h = TAB_H, action = { kind = "close" }, label = "BACK TO WORLD" }
  local fits = floor((PAGE_Y - 1 - LIST_Y) / ROW_H)
  local entries = {}
  if s.tab == "craft" then
    for _, e in ipairs(rules.recipeList(s)) do entries[#entries + 1] = { kind = "recipe", e = e } end
  elseif s.tab == "items" then
    for _, item in ipairs(rules.ITEMS) do
      if (s.p.inv[item.id] or 0) > 0 then entries[#entries + 1] = { kind = "item", item = item } end
    end
    fits = fits * 2
  end
  local pages = max(1, math.ceil(#entries / max(1, fits)))
  local page = min(s.page, pages)
  for i = (page - 1) * fits + 1, min(#entries, page * fits) do
    local at = i - (page - 1) * fits - 1
    local e = entries[i]
    if e.kind == "recipe" then
      parts[#parts + 1] = { x = 2, y = LIST_Y + at * ROW_H, w = W - 4, h = ROW_H - 1, action = { kind = "craft", id = e.e.r.id }, recipe = e.e }
    else
      local half = floor((W - 6) / 2)
      local colX = 2 + (at % 2) * (half + 2)
      local rowY = LIST_Y + floor(at / 2) * ROW_H
      local def = e.item
      parts[#parts + 1] = { x = colX, y = rowY, w = half, h = ROW_H - 1, item = def,
        action = (def.place or def.food) and { kind = "pick", item = def.id } or nil }
    end
  end
  if pages > 1 then
    if page > 1 then parts[#parts + 1] = { x = 2, y = PAGE_Y, w = 22, h = 5, action = { kind = "page", d = -1 }, label = "< BACK" } end
    if page < pages then parts[#parts + 1] = { x = W - 24, y = PAGE_Y, w = 22, h = 5, action = { kind = "page", d = 1 }, label = "MORE >" } end
  end
  return parts, page, pages, #entries
end

local function needLine(r)
  local bits = {}
  for _, need in ipairs(r.need) do bits[#bits + 1] = need[2] .. " " .. rules.ITEM[need[1]].name end
  local line = table.concat(bits, " + ")
  if r.smelt then line = line .. " + fuel, at a furnace" elseif r.at then line = line .. ", at a crafting table" end
  return line
end

local function recipeIcon(r)
  if r.tool == "pick" then return "pick" .. r.tier end
  if r.tool == "sword" then return "sword" .. r.tier end
  if r.tool == "armour" then return "armour" .. r.tier end
  return r.out
end

local function drawPart(s, part)
  if part.label then
    local on = part.tab and part.tab == s.tab
    ui.fill(part.x, part.y, part.w, part.h, on and C.hi or C.panel)
    ui.small(part.label, part.x + floor(part.w / 2), part.y + floor(part.h / 2), on and C.bg or C.text, on and C.hi or C.panel, "center")
    return
  end
  local x, y, w, h = part.x, part.y, part.w, part.h
  if part.recipe then
    local e, r = part.recipe, part.recipe.r
    ui.fill(x, y, w, h, C.panel)
    if e.ok then ui.fill(x, y, 1, h, C.ok) end
    ui.fill(x + 2, y, 8, h, C.bg)
    art.icon(recipeIcon(r), x + 3, y)
    local name = r.name .. ((r.n or 1) > 1 and (" x" .. r.n) or "")
    ui.small(name, x + 12, y + 1, e.ok and C.text or C.line, C.panel, "left", w - 34)
    ui.small(e.ok and needLine(r) or e.why, x + 12, y + 3, e.ok and C.line or C.warn, C.panel, "left", w - 34)
    if e.ok then
      local word = r.smelt and " SMELT " or " MAKE "
      ui.small(word, x + w - 3, y + 2, C.bg, C.ok, "right")
    end
  elseif part.item then
    local def = part.item
    local usable = def.place or def.food
    ui.fill(x, y, w, h, C.panel)
    ui.fill(x + 1, y, 8, h, C.bg)
    art.icon(def.id, x + 2, y)
    ui.small(def.name, x + 11, y + 1, C.text, C.panel, "left", w - 18)
    ui.small("x" .. (s.p.inv[def.id] or 0), x + w - 2, y + 1, C.hi, C.panel, "right")
    ui.small(def.place and "tap: hold to place" or (def.food and ("tap: hold to eat, +" .. def.food) or "for crafting"),
      x + 11, y + 3, usable and C.line or C.tie, C.panel, "left", w - 13)
  end
end

local function drawGoals(L, s)
  local W = L.W
  local half = floor((W - 6) / 2)
  for i, g in ipairs(rules.GOALS) do
    local col = (i - 1) % 2
    local row = floor((i - 1) / 2)
    local x, y = 2 + col * (half + 2), LIST_Y + row * 4
    local done = s.ach[g.id]
    ui.fill(x, y, half, 3, C.panel)
    ui.fill(x, y, 3, 3, done and C.ok or C.bg)
    ui.small(g.text, x + 5, y + 1, done and C.text or C.line, C.panel, "left", half - 6)
  end
  local st = s.stats
  local y = LIST_Y + 8 * 4 + 1
  ui.small("DAYS " .. rules.dayNumber(s) .. "    DEEPEST " .. st.deepest .. "    DIAMONDS " .. st.diamonds .. "    BLOCKS DUG " .. st.mined,
    floor(W / 2), y, C.hi, C.bg, "center")
  ui.small("BUILT " .. st.placed .. "    MADE " .. st.crafted .. "    MONSTERS BEATEN " .. st.kills .. "    FAINTED " .. st.deaths,
    floor(W / 2), y + 2, C.line, C.bg, "center")
  local lines = {
    "Tap a block beside you to dig it. Tap far left or right to walk, high above you to jump.",
    "Hold a block (tap it in the bar), then tap an empty space beside you to place it. Tap yourself to eat.",
  }
  for i, line in ipairs(lines) do ui.small(line, floor(W / 2), y + 3 + i * 2, C.text, C.bg, "center", W - 2) end
end

local function drawMenu(L, s)
  ui.fill(0, 0, L.W, L.hudY, C.bg)
  local parts, page, pages, total = menuParts(L, s)
  for _, part in ipairs(parts) do drawPart(s, part) end
  local W = L.W
  if s.tab == "craft" then
    local T, F = rules.stationNear(s, "T"), rules.stationNear(s, "F")
    ui.small("Crafting table: " .. (T and "near" or "none near") .. "     Furnace: " .. (F and "near" or "none near")
      .. "     Fuel stored: " .. s.p.heat, 2, 7, C.line, C.bg, "left", W - 4)
    if total == 0 then
      ui.small("Nothing to make yet.", floor(W / 2), 20, C.text, C.bg, "center")
      ui.small("Chop a tree for logs: stand beside the trunk and tap it.", floor(W / 2), 23, C.line, C.bg, "center", W - 2)
    end
  elseif s.tab == "items" then
    local p = s.p
    ui.small("PICKAXE " .. rules.TIER_NAME[p.pick] .. "    SWORD " .. rules.TIER_NAME[p.sword] .. "    ARMOUR "
      .. (p.armour == 0 and "NONE" or (p.armour == 1 and "IRON" or "DIAMOND")), 2, 7, C.hi, C.bg, "left", W - 4)
    if total == 0 then ui.small("Your pockets are empty.", floor(W / 2), 20, C.line, C.bg, "center") end
  else
    drawGoals(L, s)
  end
  if pages > 1 then ui.small("PAGE " .. page .. " OF " .. pages, floor(W / 2), PAGE_Y + 2, C.line, C.bg, "center") end
  if s.msg ~= "" then ui.small(" " .. s.msg .. " ", floor(W / 2), L.hudY - 1, C.text, C.panel, "center", W - 2) end
end

-- ---------------------------------------------------------------- the whole picture

local HINT = {
  "WELCOME TO CRAFT WORLD",
  "Tap a block right beside you to dig it.",
  "Tap far left or right to walk. Tap high above you to jump.",
  "Choose a block in the bar below, then tap an empty space beside you to build.",
  "Tap yourself to eat. Tap the bar under the world for crafting.",
}

local function drawHint(L)
  local w = min(L.W - 4, 84)
  local x = floor((L.W - w) / 2)
  local y = 3
  ui.fill(x, y, w, #HINT * 2 + 1, C.panel)
  ui.frame(x, y, w, #HINT * 2 + 1, C.hi)
  for i, line in ipairs(HINT) do
    ui.small(line, floor(L.W / 2), y + i * 2 - 1, i == 1 and C.hi or C.text, C.panel, "center", w - 2)
  end
end

function M.paint(L, s)
  ui.fill(0, 0, L.W, L.H, C.bg)
  if s.mode == "menu" then
    drawMenu(L, s)
  else
    drawWorld(L, s)
    if s.hint > 0 and s.stats.mined < 3 then
      drawHint(L)
    elseif s.msg ~= "" then
      ui.small(" " .. s.msg .. " ", floor(L.W / 2), 1, C.text, C.bg, "center", L.W - 2)
    end
  end
  drawHud(L, s)
end

--- What a touch does.
function M.actionAt(L, s, px, py)
  if not s then return nil end
  if py >= L.hudY then
    if py < L.slotsY - 1 then return { kind = "menu" } end
    for i = 0, rules.BAR_SLOTS do
      local x, y, w, h = slotRect(L, i)
      if px >= x and px < x + w and py >= y and py < y + h then
        if i > #s.p.bar then return nil end
        return { kind = "select", slot = i }
      end
    end
    return nil
  end
  if s.mode == "menu" then
    local parts = menuParts(L, s)
    for i = #parts, 1, -1 do
      local part = parts[i]
      if px >= part.x and px < part.x + part.w and py >= part.y and py < part.y + part.h then return part.action end
    end
    return nil
  end
  local dx, dy = M.cellAt(L, px, py)
  return { kind = "tap", dx = dx, dy = dy }
end

return M
