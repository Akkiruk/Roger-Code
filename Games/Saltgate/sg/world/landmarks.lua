-- world/landmarks.lua
-- The city's landmarks as triangle lists, each standing on y = 0 at its own middle, facing +x. The chunk's `landmarks`
-- section names them ({ model, x, z, h, y }); chunkmodel places them. Original shapes, drawn from boxes, prisms and
-- round towers so a whole one costs 30 to 150 triangles.
--
--   landmarks.build(name) -> triangle list, or nil for an unknown name
--   landmarks.NAMES

local shapes = require("sg.world.shapes")

local M = {}
local C = rawget(_G, "colors") or setmetatable({}, { __index = function() return 1 end })
local box, cyl, gable, pyramid, flat = shapes.box, shapes.cyl, shapes.gable, shapes.pyramid, shapes.flat
local cos, sin, pi = math.cos, math.sin, math.pi

local B = {}

function B.manor()
  local l = {}
  box(l, -11, 0, -10, 11, 0.9, 10, C.lightGray, C.lightGray, C.gray)
  box(l, -7.5, 0.9, -6, 7.5, 8, 6, C.white, C.white, C.lightGray)
  pyramid(l, -8, 8, -6.5, 8, 6.5, 3.4, C.red, C.brown)
  box(l, -4, 0.9, 6, 4, 5.5, 12, C.white, C.lightGray, C.white)
  pyramid(l, -4.4, 5.5, 5.6, 4.4, 12.4, 2.4, C.red, C.brown)
  box(l, -4, 0.9, -12, 4, 5.5, -6, C.white, C.lightGray, C.white)
  pyramid(l, -4.4, 5.5, -12.4, 4.4, -5.6, 2.4, C.red, C.brown)
  for k = -3, 3 do box(l, 7.6, 0.9, k * 1.7 - 0.25, 8.2, 7.2, k * 1.7 + 0.25, C.white, C.white, C.lightGray, { noTop = true }) end
  box(l, 7.4, 7.2, -5.6, 8.6, 7.9, 5.6, C.lightGray, C.white, C.lightGray)
  box(l, -2.6, 11.0, -2.6, 2.6, 11.3, 2.6, C.lightGray, C.lightGray, C.lightGray)
  cyl(l, 0, 11.3, 0, 2.4, 0.4, 3, 8, C.yellow, C.orange, C.yellow)
  box(l, 8.6, 0.9, -1.2, 9.2, 2.2, 1.2, C.lightBlue, C.lightBlue, C.lightBlue)
  return l
end

function B.clocktower()
  local l = {}
  box(l, -3.6, 0, -3.6, 3.6, 1.2, 3.6, C.lightGray, C.lightGray, C.gray)
  box(l, -2.6, 1.2, -2.6, 2.6, 21, 2.6, C.white, C.white, C.lightGray)
  box(l, -3, 21, -3, 3, 24.5, 3, C.lightGray, C.lightGray, C.lightGray)
  -- a clock face on each side
  box(l, 3.0, 21.6, -1.6, 3.15, 24, 1.6, C.yellow, C.yellow, C.yellow)
  box(l, -3.15, 21.6, -1.6, -3.0, 24, 1.6, C.yellow, C.yellow, C.yellow)
  box(l, -1.6, 21.6, 3.0, 1.6, 24, 3.15, C.yellow, C.yellow, C.yellow)
  box(l, -1.6, 21.6, -3.15, 1.6, 24, -3.0, C.yellow, C.yellow, C.yellow)
  pyramid(l, -3.2, 24.5, -3.2, 3.2, 3.2, 6, C.red, C.brown)
  box(l, -0.15, 30.4, -0.15, 0.15, 33, 0.15, C.black, C.black, C.black)
  return l
end

function B.fountain()
  local l = {}
  cyl(l, 0, 0, 0, 5.2, 5.0, 0.9, 10, C.lightGray, C.white, C.lightBlue)
  cyl(l, 0, 0.9, 0, 0.9, 0.7, 2.6, 6, C.white, C.lightGray, nil)
  cyl(l, 0, 3.3, 0, 2.2, 1.6, 0.7, 8, C.white, C.lightGray, C.cyan)
  cyl(l, 0, 4.0, 0, 0.25, 0.1, 1.8, 4, C.cyan, C.lightBlue, C.white)
  return l
end

function B.chimney()
  local l = {}
  cyl(l, 0, 0, 0, 3.4, 2.8, 4, 8, C.gray, C.lightGray, nil)
  for k = 0, 5 do cyl(l, 0, 4 + k * 6, 0, 2.5 - k * 0.1, 2.4 - k * 0.1, 6, 8, (k % 2 == 0) and C.red or C.white, (k % 2 == 0) and C.brown or C.lightGray, nil) end
  cyl(l, 0, 40, 0, 1.9, 2.1, 1.2, 8, C.black, C.gray, C.black)
  return l
end

function B.gasometer()
  local l = {}
  cyl(l, 0, 0, 0, 11.5, 11.5, 22, 14, C.lightGray, C.gray, C.gray)
  cyl(l, 0, 22, 0, 11.5, 9, 2.4, 14, C.gray, C.black, C.gray)
  for k = 0, 6 do
    local a = k / 7 * 2 * pi
    box(l, cos(a) * 11.6 - 0.25, 0, sin(a) * 11.6 - 0.25, cos(a) * 11.6 + 0.25, 22, sin(a) * 11.6 + 0.25, C.black, C.black, C.black, { noTop = true })
  end
  return l
end

function B.silos()
  local l = {}
  for k = -1, 1 do
    cyl(l, 0, 0, k * 4.6, 2.3, 2.3, 16, 8, C.lightGray, C.white, C.gray)
    cyl(l, 0, 16, k * 4.6, 2.3, 0.5, 1.6, 8, C.gray, C.lightGray, C.gray)
  end
  box(l, -3.2, 0, -7, -2.2, 3, 7, C.gray, C.gray, C.black)
  box(l, 2.5, 0, -2, 6.5, 5, 2, C.red, C.red, C.brown)
  return l
end

function B.crane()
  local l = {}
  for _, p in ipairs({ { -1.3, -1.3 }, { 1.3, -1.3 }, { -1.3, 1.3 }, { 1.3, 1.3 } }) do
    box(l, p[1] - 0.25, 0, p[2] - 0.25, p[1] + 0.25, 20, p[2] + 0.25, C.yellow, C.yellow, C.orange, { noTop = true })
  end
  box(l, -2, 9.8, -2, 2, 10.3, 2, C.yellow, C.yellow, C.orange)
  box(l, -2, 19.8, -2, 2, 20.4, 2, C.yellow, C.yellow, C.orange)
  box(l, -9, 20.4, -0.9, 22, 22.2, 0.9, C.yellow, C.orange, C.yellow)
  box(l, -9, 20, -1.2, -4, 24, 1.2, C.gray, C.black, C.gray)
  box(l, 17.5, 14, -0.1, 17.7, 20.4, 0.1, C.black, C.black, C.black)
  box(l, 16.5, 12.6, -0.7, 18.7, 14, 0.7, C.red, C.red, C.brown)
  box(l, -1.7, 22.2, -1.7, 1.7, 24.5, 1.7, C.white, C.lightGray, C.lightGray)
  return l
end

function B.lighthouse()
  local l = {}
  box(l, -5, 0, -5, 5, 4.5, 5, C.white, C.white, C.lightGray)
  pyramid(l, -5.4, 4.5, -5.4, 5.4, 5.4, 2, C.red, C.brown)
  for k = 0, 4 do cyl(l, 0, 4.5 + k * 6.4, 0, 3.8 - k * 0.22, 3.6 - k * 0.22, 6.4, 10, (k % 2 == 0) and C.white or C.red, (k % 2 == 0) and C.lightGray or C.brown, nil) end
  cyl(l, 0, 36.5, 0, 3.8, 3.8, 0.7, 10, C.black, C.black, C.black)
  box(l, -2, 37.2, -2, 2, 40.2, 2, C.lightBlue, C.lightBlue, C.yellow)
  cyl(l, 0, 40.2, 0, 3.2, 0.3, 3.4, 10, C.red, C.brown, C.red)
  return l
end

function B.windmill()
  local l = {}
  cyl(l, 0, 0, 0, 3.4, 2.2, 8, 8, C.white, C.lightGray, nil)
  cyl(l, 0, 8, 0, 2.5, 0.2, 3.6, 8, C.brown, C.gray, C.brown)
  for k = 0, 3 do
    local a = k * pi / 2 + 0.4
    local dy, dz = cos(a), sin(a)
    local py, pz = -dz * 0.9, dy * 0.9
    flat(l, 2.6, 9 + py * 0.3, pz * 0.3, 2.6, 9 + dy * 7 + py * 0.3, dz * 7 + pz * 0.3, 2.6, 9 + dy * 7 + py, dz * 7 + pz, 2.6, 9 + py, pz, C.white)
  end
  return l
end

function B.bandstand()
  local l = {}
  cyl(l, 0, 0, 0, 5.4, 5.2, 0.9, 10, C.lightGray, C.white, C.white)
  for k = 0, 5 do
    local a = k / 6 * 2 * pi
    box(l, cos(a) * 4.5 - 0.2, 0.9, sin(a) * 4.5 - 0.2, cos(a) * 4.5 + 0.2, 4.2, sin(a) * 4.5 + 0.2, C.white, C.white, C.lightGray, { noTop = true })
  end
  cyl(l, 0, 4.2, 0, 6, 0.4, 3, 10, C.red, C.brown, C.red)
  return l
end

function B.ferris()
  local l = {}
  local R, cy = 11, 13
  box(l, -6, 0, -2.4, 6, 1.2, 2.4, C.lightGray, C.gray, C.gray)
  for _, z in ipairs({ -1.6, 1.6 }) do
    flat(l, -5, 0.6, z, 0, cy, z, 0.7, cy, z, -4.2, 0.6, z, C.white)
    flat(l, 5, 0.6, z, 0, cy, z, -0.7, cy, z, 4.2, 0.6, z, C.white)
  end
  local n = 16
  local cols = { C.yellow, C.cyan, C.red, C.lime }
  for k = 0, n - 1 do
    local a0, a1 = k / n * 2 * pi, (k + 1) / n * 2 * pi
    for _, z in ipairs({ -1.1, 1.1 }) do
      flat(l, cos(a0) * R, cy + sin(a0) * R, z, cos(a1) * R, cy + sin(a1) * R, z, cos(a1) * (R - 0.5), cy + sin(a1) * (R - 0.5), z,
        cos(a0) * (R - 0.5), cy + sin(a0) * (R - 0.5), z, (k % 2 == 0) and C.red or C.white)
    end
    if k % 2 == 0 then
      local gx, gy = cos(a0) * R, cy + sin(a0) * R
      flat(l, 0, cy, -1.1, gx, gy, -1.1, gx, gy + 0.15, 1.1, 0, cy, 1.1, C.lightGray)
      local col = cols[(k / 2) % 4 + 1]
      box(l, gx - 0.9, gy - 1.9, -1.2, gx + 0.9, gy - 0.5, 1.2, col, col, col)
    end
  end
  box(l, -0.7, cy - 0.7, -1.7, 0.7, cy + 0.7, 1.7, C.black, C.gray, C.gray)
  return l
end

function B.funicular()
  local l = {}
  box(l, -4, 0, -3.5, 4, 4.5, 3.5, C.white, C.lightGray, C.white)
  gable(l, -4.4, 4.5, -4, 4.4, 4, 2.2, C.red, C.lightGray, false)
  box(l, 4, 0.2, -1.2, 9, 1.6, 1.2, C.yellow, C.yellow, C.orange)
  return l
end

function B.crusher()
  local l = {}
  box(l, -8, 0, -6, 4, 7, 6, C.gray, C.lightGray, C.gray)
  pyramid(l, -9, 7, -7, 5, 7, 3, C.black, C.gray)
  box(l, 4, 3, -0.8, 14, 4, 0.8, C.yellow, C.yellow, C.orange)
  for k = 0, 2 do box(l, 6 + k * 3.5, 0, -0.4, 6.6 + k * 3.5, 3, 0.4, C.gray, C.gray, C.black, { noTop = true }) end
  box(l, -3, 7, -1.2, -1, 12, 1.2, C.red, C.red, C.brown)
  return l
end

function B.span_tower()
  local l = {}
  local H = 52
  for _, z in ipairs({ -7.4, 7.4 }) do
    box(l, -1.5, 0, z - 1.5, 1.5, H, z + 1.5, C.lightGray, C.white, C.gray)
    box(l, -1.9, H, z - 1.9, 1.9, H + 1.5, z + 1.9, C.gray, C.gray, C.black)
    box(l, -0.3, H + 1.5, z - 0.3, 0.3, H + 3.5, z + 0.3, C.red, C.red, C.red)
  end
  for _, y in ipairs({ H - 4, H * 0.6 + 6 }) do box(l, -1.2, y, -6.5, 1.2, y + 2.2, 6.5, C.gray, C.lightGray, C.gray) end
  return l
end

M.NAMES = {}
for name in pairs(B) do M.NAMES[#M.NAMES + 1] = name end
table.sort(M.NAMES)

function M.build(name)
  local f = B[name]
  return f and f() or nil
end

return M
