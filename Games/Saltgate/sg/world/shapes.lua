-- world/shapes.lua
-- Triangle shapes for Pine3D beyond boxes: roofs, cylinders, cones, pyramids, strips. Every solid shape orients its own
-- triangles so the faces point out (Pine3D draws a triangle only from the side its winding faces). Pure.
--
--   shapes.tri(list, x1,y1,z1, x2,y2,z2, x3,y3,z3, colour, refx, refy, refz)   a triangle facing away from the ref point
--   shapes.box(list, x0,y0,z0, x1,y1,z1, top, sideX, sideZ, opts)           models.box (noTop, bottom)
--   shapes.gable(list, x0,y,z0, x1,z1, rise, roof, end_, alongX)             a prism roof; ridge along x (or z)
--   shapes.pyramid(list, x0,y,z0, x1,z1, rise, c1, c2)                       a hip roof
--   shapes.cyl(list, cx,y0,cz, r0,r1, height, sides, side1, side2, top)      a tapering round tower
--   shapes.flat(list, ax,ay,az, bx,by,bz, cx,cy,cz, dx,dy,dz, colour)        a two-sided quad (always drawn)
--   shapes.rotate(list, h) / shapes.move(list, dx, dy, dz)

local models = require("sg.models")

local M = {}
local cos, sin, pi = math.cos, math.sin, math.pi

function M.tri(list, x1, y1, z1, x2, y2, z2, x3, y3, z3, c, rx, ry, rz)
  local ux, uy, uz = x2 - x1, y2 - y1, z2 - z1
  local vx, vy, vz = x3 - x1, y3 - y1, z3 - z1
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  if nx * (x1 - rx) + ny * (y1 - ry) + nz * (z1 - rz) < 0 then
    x2, y2, z2, x3, y3, z3 = x3, y3, z3, x2, y2, z2
  end
  list[#list + 1] = { x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2, x3 = x3, y3 = y3, z3 = z3, c = c }
end

M.box = models.box

--- A quad drawn from both sides (thin walls, rails, signs). Corners in order round it.
function M.flat(list, ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, c)
  list[#list + 1] = { x1 = ax, y1 = ay, z1 = az, x2 = bx, y2 = by, z2 = bz, x3 = cx, y3 = cy, z3 = cz, c = c, forceRender = true }
  list[#list + 1] = { x1 = ax, y1 = ay, z1 = az, x2 = cx, y2 = cy, z2 = cz, x3 = dx, y3 = dy, z3 = dz, c = c, forceRender = true }
end

--- A gabled roof over x0..x1, z0..z1 sitting at height y, its ridge `rise` higher, along x (alongX) or z.
function M.gable(list, x0, y, z0, x1, z1, rise, roof, gableEnd, alongX)
  local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
  local ry = y + rise / 3
  if alongX then
    local t = M.tri
    t(list, x0, y, z0, x1, y, z0, x1, y + rise, mz, roof, mx, ry, mz)
    t(list, x0, y, z0, x1, y + rise, mz, x0, y + rise, mz, roof, mx, ry, mz)
    t(list, x0, y, z1, x1, y, z1, x1, y + rise, mz, roof, mx, ry, mz)
    t(list, x0, y, z1, x1, y + rise, mz, x0, y + rise, mz, roof, mx, ry, mz)
    t(list, x0, y, z0, x0, y, z1, x0, y + rise, mz, gableEnd, mx, ry, mz)
    t(list, x1, y, z0, x1, y, z1, x1, y + rise, mz, gableEnd, mx, ry, mz)
  else
    local t = M.tri
    t(list, x0, y, z0, x0, y, z1, mx, y + rise, z1, roof, mx, ry, mz)
    t(list, x0, y, z0, mx, y + rise, z1, mx, y + rise, z0, roof, mx, ry, mz)
    t(list, x1, y, z0, x1, y, z1, mx, y + rise, z1, roof, mx, ry, mz)
    t(list, x1, y, z0, mx, y + rise, z1, mx, y + rise, z0, roof, mx, ry, mz)
    t(list, x0, y, z0, x1, y, z0, mx, y + rise, z0, gableEnd, mx, ry, mz)
    t(list, x0, y, z1, x1, y, z1, mx, y + rise, z1, gableEnd, mx, ry, mz)
  end
end

--- A four-sided hip roof.
function M.pyramid(list, x0, y, z0, x1, z1, rise, c1, c2)
  local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
  local ty = y + rise
  local ry = y + rise / 3
  local t = M.tri
  t(list, x0, y, z0, x1, y, z0, mx, ty, mz, c2, mx, ry, mz)
  t(list, x0, y, z1, x1, y, z1, mx, ty, mz, c2, mx, ry, mz)
  t(list, x0, y, z0, x0, y, z1, mx, ty, mz, c1, mx, ry, mz)
  t(list, x1, y, z0, x1, y, z1, mx, ty, mz, c1, mx, ry, mz)
end

--- A round tower of `sides` flat faces, radius r0 at the bottom and r1 at the top, with a flat cap (top = colour or nil).
function M.cyl(list, cx, y0, cz, r0, r1, height, sides, c1, c2, top)
  sides = sides or 8
  local y1 = y0 + height
  local midY = y0 + height / 2
  local px, pz, qx, qz
  for k = 0, sides - 1 do
    local a0, a1 = k / sides * 2 * pi, (k + 1) / sides * 2 * pi
    local ax, az = cx + cos(a0) * r0, cz + sin(a0) * r0
    local bx, bz = cx + cos(a1) * r0, cz + sin(a1) * r0
    local tx, tz = cx + cos(a0) * r1, cz + sin(a0) * r1
    local ux, uz = cx + cos(a1) * r1, cz + sin(a1) * r1
    local col = (k % 2 == 0) and c1 or (c2 or c1)
    M.tri(list, ax, y0, az, bx, y0, bz, ux, y1, uz, col, cx, midY, cz)
    M.tri(list, ax, y0, az, ux, y1, uz, tx, y1, tz, col, cx, midY, cz)
    if top then M.tri(list, tx, y1, tz, ux, y1, uz, cx, y1, cz, top, cx, midY, cz) end
    px, pz, qx, qz = ax, az, bx, bz
  end
  local _ = px and pz and qx and qz
end

--- Add dx, dy, dz to every vertex of a list, in place.
function M.move(list, dx, dy, dz)
  for _, p in ipairs(list) do
    p.x1, p.x2, p.x3 = p.x1 + dx, p.x2 + dx, p.x3 + dx
    p.y1, p.y2, p.y3 = p.y1 + dy, p.y2 + dy, p.y3 + dy
    p.z1, p.z2, p.z3 = p.z1 + dz, p.z2 + dz, p.z3 + dz
  end
  return list
end

--- Rotate about y so local +x points along heading h (models.rotated, but keeps forceRender).
function M.rotate(list, h)
  local c, s = cos(h), sin(h)
  local out = {}
  for i, p in ipairs(list) do
    out[i] = {
      x1 = p.x1 * c - p.z1 * s, y1 = p.y1, z1 = p.x1 * s + p.z1 * c,
      x2 = p.x2 * c - p.z2 * s, y2 = p.y2, z2 = p.x2 * s + p.z2 * c,
      x3 = p.x3 * c - p.z3 * s, y3 = p.y3, z3 = p.x3 * s + p.z3 * c,
      c = p.c, forceRender = p.forceRender,
    }
  end
  return out
end

return M
