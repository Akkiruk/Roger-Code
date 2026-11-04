-- games/catan/draw.lua
-- Drawing the island, at any size: the wall's big board and the seat's small one are the same code with a different hex width.
-- Land hexes sit in a slate channel, so roads run in the channels between them in their owner's colour and every colour stands out.
--
-- A layout is worked out once for a size and a place on the screen and kept: which cell is which hex, which is channel and which is
-- sea, and which side of which hex each channel cell runs along. Cells are 2 wide by 3 tall, so everything is measured in those
-- units before it is turned back into cells.

local board = require("games.catan.board")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

local SQ3 = math.sqrt(3)
local floor = math.floor

-- Colours, by the island felt (theme.lua): sand for the desert, brick red, a dark forest, green pasture, gold fields, grey mountains
M.TERRAIN = { [0] = C.accent, C.card, C.feltLight, C.win, C.gold, C.mute }
M.RES = { C.card, C.feltLight, C.win, C.gold, C.mute }
-- Text that reads on each resource's colour
M.RES_INK = { C.text, C.text, C.ink, C.ink, C.ink }
M.PLAYER = { red = C.red, blue = C.blue, white = C.text, orange = C.orange }
M.CHANNEL = C.line

function M.playerColor(player)
  return M.PLAYER[player and player.color or ""] or C.mute
end

-- ------------------------------------------------------------------ layouts

local cache = {}

local function round(x)
  return floor(x + 0.5)
end

--- Where things are for a hex width w (in cells) with the island's centre at cell (cx, cy). land is how much of a hex is land.
function M.layout(w, cx, cy, land)
  local key = w .. ":" .. cx .. ":" .. cy .. ":" .. land
  if cache[key] then return cache[key] end
  local geo = { w = w, cx = cx, cy = cy, land = land, hexAt = {}, vertexAt = {}, edgeAt = {} }
  -- A position in half-units (x2, y2) to cells
  local ky = w / (3 * SQ3)
  local function cell(x2, y2) return cx + x2 * w / 2, cy + y2 * ky end
  geo.cell = cell
  for h, hex in ipairs(board.hexes) do
    local x, y = cell(hex.x2, hex.y2)
    geo.hexAt[h] = { x = x, y = y }
  end
  for v, vertex in ipairs(board.vertices) do
    local x, y = cell(vertex.x2, vertex.y2)
    geo.vertexAt[v] = { x = x, y = y }
  end
  for e, edge in ipairs(board.edges) do
    local x, y = cell(edge.x2 / 2, edge.y2 / 2)
    geo.edgeAt[e] = { x = x, y = y }
  end

  -- Every cell near the island: a land hex, the channel (and the side it runs along), or sea
  local byAxial = {}
  for h, hex in ipairs(board.hexes) do byAxial[hex.q .. "," .. hex.r] = h end
  local apothem = SQ3 / 2
  local function hexNorm(fx2, fy2, q, r)
    local dx = (fx2 - (2 * q + r)) * SQ3 / 2
    local dy = (fy2 - 3 * r) / 2
    return math.max(math.abs(dx), math.abs(dx / 2 + dy * SQ3 / 2), math.abs(-dx / 2 + dy * SQ3 / 2)) / apothem
  end
  local rows = {}
  local halfW = 3 * w + 2
  local halfH = floor(9.5 * ky) + 2
  local x1, x2 = floor(cx - halfW), floor(cx + halfW) + 1
  local y1, y2 = floor(cy - halfH), floor(cy + halfH) + 1
  geo.box = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
  local channelEdge = {}
  for y = y1, y2 do
    local runs = {}
    local row = {}
    for x = x1, x2 do
      local fx2 = (x - cx) * 2 / w
      local fy2 = (y - cy) / ky
      local rf = fy2 / 3
      local qf = (fx2 - rf) / 2
      -- Cube rounding
      local sf = -qf - rf
      local q, r, s = round(qf), round(rf), round(sf)
      local dq, dr, ds = math.abs(q - qf), math.abs(r - rf), math.abs(s - sf)
      if dq > dr and dq > ds then q = -r - s elseif dr > ds then r = -q - s end
      -- Adding nought turns a negative zero into zero, which would otherwise print as "-0" and miss the middle hex
      local h = byAxial[(q + 0) .. "," .. (r + 0)]
      local kind = nil
      if h then
        kind = hexNorm(fx2, fy2, q, r) <= land and h or 0
      else
        local near = 99
        for _, d in ipairs({ { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } }) do
          if byAxial[(q + d[1]) .. "," .. (r + d[2])] then near = math.min(near, hexNorm(fx2, fy2, q + d[1], r + d[2])) end
        end
        if near <= 1 + 2 * (1 - land) then kind = 0 end
      end
      row[x] = kind
      if kind == 0 then
        -- The side this bit of channel runs along: the nearest middle of a side
        local best, bestD = nil, nil
        for e, at in ipairs(geo.edgeAt) do
          local dx, dy = (x - at.x) * 2, (y - at.y) * 3
          local d = dx * dx + dy * dy
          if not bestD or d < bestD then best, bestD = e, d end
        end
        -- Close to a corner the channel belongs to the corner's building, not a side
        local edge = board.edges[best]
        local nearCorner = false
        for _, v in ipairs({ edge.a, edge.b }) do
          local at = geo.vertexAt[v]
          local dx, dy = (x - at.x) * 2, (y - at.y) * 3
          if dx * dx + dy * dy < (w * 0.42) ^ 2 then nearCorner = true end
        end
        if not nearCorner then
          channelEdge[best] = channelEdge[best] or {}
          local list = channelEdge[best]
          list[#list + 1] = { x = x, y = y }
        end
      end
      local last = runs[#runs]
      if last and last.kind == kind and last.x + last.n == x then
        last.n = last.n + 1
      else
        runs[#runs + 1] = { x = x, n = 1, kind = kind }
      end
    end
    rows[y] = runs
    geo[y] = row
  end
  geo.rows = rows
  geo.channel = channelEdge
  cache[key] = geo
  return geo
end

--- The cell of a corner, a side's middle and a hex's centre, rounded.
function M.vertexCell(geo, v)
  local at = geo.vertexAt[v]
  return round(at.x), round(at.y)
end

function M.edgeCell(geo, e)
  local at = geo.edgeAt[e]
  return round(at.x), round(at.y)
end

function M.hexCell(geo, h)
  local at = geo.hexAt[h]
  return round(at.x), round(at.y)
end

-- ------------------------------------------------------------------ the pieces

--- Land, channel and sea. The sea is the felt the canvas was cleared to.
local function ground(c, geo, view)
  for y, runs in pairs(geo.rows) do
    for _, run in ipairs(runs) do
      local kind = run.kind
      if kind == 0 then
        c:rect(run.x, y, run.n, 1, M.CHANNEL)
      elseif kind then
        c:rect(run.x, y, run.n, 1, M.TERRAIN[view.terrain[kind]] or C.mute)
      end
    end
  end
end

local function roads(c, geo, view)
  for e, owner in ipairs(view.road) do
    if owner ~= 0 then
      local color = M.playerColor(view.players[owner])
      for _, at in ipairs(geo.channel[e] or {}) do c:rect(at.x, at.y, 1, 1, color) end
    end
  end
end

-- The wall's pieces, k the rim and c the player's colour
local TOWN = { ".kck.", "kccck", "kccck" }
local CITY = { ".kck...", "kccckkk", "kcccccc", "kcccccc" }

--- A settlement or a city at a corner. big is the wall's size.
local function building(c, geo, v, color, city, big)
  local x, y = M.vertexCell(geo, v)
  if big then
    -- A house with a pointed roof, or a city's house with a hall beside it, in an ink rim so a white or orange piece reads on any
    -- land
    local rows = city and CITY or TOWN
    c:sprite(x - math.floor(#rows[1] / 2), y - 1, rows, { k = C.ink, c = color })
  else
    if city then
      c:rect(x - 1, y, 3, 1, color)
      c:text(x, y, "C", C.ink, color)
    else
      c:rect(x, y, 2, 1, color)
      c:text(x, y, "^", C.ink, color)
    end
  end
end

local function dots(n)
  local pips = board.PIPS[n] or 0
  return string.rep("\7", pips)
end

--- A token just big enough for its number and the dots under it, its corners rounded off, the number's top row at y - 2.
local function disc(c, x, y, w, bg)
  local left = x + 1 - math.floor(w / 2)
  c:rect(left + 1, y - 3, w - 2, 1, bg)
  c:rect(left, y - 2, w, 5, bg)
  c:rect(left + 1, y + 3, w - 2, 1, bg)
end

-- The robber: a hooded piece
local ROBBER = { ".###.", "#####", ".###.", "..#..", ".###.", "#####" }

--- A hex's number on the wall: on a cream token the way the board game prints them, red for 6 and 8, its odds as dots under it,
-- inside the token where no settlement can cover them. The robber stands on its token, black, with the number it is blocking
-- beside it.
local function bigToken(c, geo, view, h, rolled)
  local x, y = M.hexCell(geo, h)
  local t, n = view.terrain[h], view.number[h]
  local name = t == 0 and "DESERT" or board.RES_NAME[t]
  local labelInk = (t == 1 or t == 2) and C.text or C.ink
  c:textCenter(x + 1, y - 4, name, labelInk)
  if view.robber == h then
    disc(c, x, y, 10, C.ink)
    c:sprite(x - 3, y - 3, ROBBER, { ["#"] = C.mute })
    if n > 0 then c:text(x + 3, y - 1, tostring(n), C.mute, C.ink) end
    c:text(x - 2, y + 3, "ROBBER", C.red, C.ink)
    return
  end
  if n == 0 then return end
  local text = tostring(n)
  local red = n == 6 or n == 8
  -- Just rolled, the token turns black with a gold number: gold on cream would vanish on a grain field
  local hit = rolled == n
  local bg = hit and C.ink or C.text
  local ink = hit and C.gold or (red and C.red or C.ink)
  disc(c, x, y, math.max(c:bigWidth(text, 1), board.PIPS[n] or 0) + 2, bg)
  c:bigCenter(x + 1, y - 2, text, ink, 1)
  c:textCenter(x + 1, y + 3, dots(n), ink, bg)
end

local function smallToken(c, geo, view, h)
  local x, y = M.hexCell(geo, h)
  local n = view.number[h]
  if view.robber == h then
    c:rect(x - 1, y, 3, 1, C.ink)
    c:text(x - 1, y, n > 0 and (n < 10 and ("R" .. n .. " ") or ("R" .. n)) or "R", C.red, C.ink)
    return
  end
  if n == 0 then return end
  local text = tostring(n)
  local red = n == 6 or n == 8
  c:rect(x - 1, y, 3, 1, C.text)
  c:text(x - (#text == 2 and 1 or 0), y, text, red and C.red or C.ink, C.text)
end

--- A harbour on the wall: a ship with its sail in the colour of what it takes, white for anything, and its rate on the hull, moored
-- by two sand piers to the two corners that use it.
local function ship(c, geo, harbor, x, y)
  local edge = board.edges[harbor.edge]
  -- The piers first, over sea only, so they never cross land, a channel or the ship
  for _, v in ipairs({ edge.a, edge.b }) do
    local vx, vy = M.vertexCell(geo, v)
    local tx, ty = x, y + 1
    local steps = math.max(math.abs(vx - tx), math.abs(vy - ty))
    for i = 1, steps - 1 do
      local px, py = round(tx + (vx - tx) * i / steps), round(ty + (vy - ty) * i / steps)
      local row = geo[py]
      local sea = not row or row[px] == nil
      local onShip = math.abs(px - x) <= 3 and py >= y - 1 and py <= y + 2
      if sea and not onShip then c:rect(px, py, 1, 1, C.accent) end
    end
  end
  local sail, ink, name
  if harbor.res == 0 then
    sail, ink, name = C.text, C.ink, "ANY"
  else
    sail, ink, name = M.RES[harbor.res], M.RES_INK[harbor.res], board.RES_NAME[harbor.res]
  end
  -- Seven wide at the hull, five at the sail: the longest name, BRICK or GRAIN, just fills it
  c:rect(x - 2, y - 1, 5, 1, sail)
  c:textCenter(x, y - 1, name, ink, sail)
  c:rect(x, y, 1, 1, C.ink)
  c:rect(x - 3, y + 1, 7, 1, C.ink)
  c:rect(x - 2, y + 2, 5, 1, C.ink)
  c:textCenter(x, y + 1, harbor.res == 0 and "3:1" or "2:1", C.gold, C.ink)
end

--- Harbours just off the coast: what they trade, in the resource's colour, white for any.
local function harbors(c, geo, view, big)
  for _, harbor in ipairs(view.harbors) do
    local at = geo.edgeAt[harbor.edge]
    local dx, dy = (at.x - geo.cx) * 2, (at.y - geo.cy) * 3
    local len = math.sqrt(dx * dx + dy * dy)
    local push = big and 10 or 5
    -- A ship goes further out to the side than up or down, clear of the corner numbers along the coast
    local x = round(at.x + dx / len * (big and 16 or push) / 2)
    local y = round(at.y + dy / len * push / 3)
    if big then
      -- Kept on the screen, inside the board's own half of the wall
      ship(c, geo, harbor, math.max(4, math.min(2 * geo.cx - 4, x)), y - 1)
    else
      local label, bg, fg
      if harbor.res == 0 then
        label, bg, fg = "3:1", C.text, C.ink
      else
        label = "2:1" .. board.RES_SHORT[harbor.res]
        bg, fg = M.RES[harbor.res], M.RES_INK[harbor.res]
      end
      local w = #label + 2
      c:rect(x - floor(w / 2), y, w, 1, bg)
      c:text(x - floor(w / 2) + 1, y, label, fg, bg)
    end
  end
end

--- Labels on the places a player may pick, the picked one in gold. kind is town, city, road or robber.
local function spots(c, geo, placing, color, big)
  for _, spot in ipairs(placing.spots or {}) do
    local x, y, label
    if placing.kind == "robber" then
      x, y = M.hexCell(geo, spot)
      y = y + (big and -6 or -1)
      label = board.hexLabel(spot)
    elseif placing.kind == "road" then
      x, y = M.edgeCell(geo, spot)
      label = tostring(spot)
    else
      x, y = M.vertexCell(geo, spot)
      label = tostring(spot)
    end
    local picked = spot == placing.sel
    local bg = picked and C.gold or color
    local fg = C.ink
    if picked then
      label = big and ("[" .. label .. "]") or label
    end
    local w = #label
    c:text(x - floor((w - 1) / 2), y, label, fg, bg)
    if picked and not big then
      -- On the small board the pick also gets a ring, so it stands out at a glance
      c:text(x - floor((w - 1) / 2) - 1, y, ">", C.ink, C.gold)
      c:text(x - floor((w - 1) / 2) + w, y, "<", C.ink, C.gold)
    end
  end
end

--- The whole island. big is the wall's board; otherwise the seat's small one.
function M.island(c, geo, view, big)
  ground(c, geo, view)
  roads(c, geo, view)
  local rolled = view.dice and (view.dice[1] + view.dice[2]) or nil
  if view.phase == "setup" or view.phase == "over" then rolled = nil end
  for h = 1, #board.hexes do
    if big then bigToken(c, geo, view, h, rolled) else smallToken(c, geo, view, h) end
  end
  harbors(c, geo, view, big)
  for v, owner in ipairs(view.owner) do
    if owner ~= 0 then building(c, geo, v, M.playerColor(view.players[owner]), view.city[v], big) end
  end
  local placing = view.placing
  if placing and placing.spots then
    local who = view.players[placing.p]
    spots(c, geo, placing, M.playerColor(who), big)
  end
end

-- ------------------------------------------------------------------ dice

local PIPS = { { 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 } }

--- A die 7 wide by 5 tall, which looks square on a monitor.
function M.die(c, x, y, face, bg, ink)
  c:rect(x, y, 7, 5, bg or C.text)
  for _, spot in ipairs(PIPS[face] or {}) do
    local col, row = (spot - 1) % 3, floor((spot - 1) / 3)
    c:rect(x + 1 + col * 2, y + 1 + row, 1, 1, ink or C.ink)
  end
end

return M
