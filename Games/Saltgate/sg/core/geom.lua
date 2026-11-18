-- core/geom.lua
-- Shapes the world is made of: polygons, polylines (with heights), rotated boxes. Pure.
-- Points are flat lists: a polygon is { x1, z1, x2, z2, ... }; a 3D polyline is { x1, y1, z1, x2, y2, z2, ... }.

local M = {}

local sqrt, floor = math.sqrt, math.floor

--- Is (x, z) inside the polygon pts (any simple polygon, either winding)?
function M.inPolygon(pts, x, z)
  local inside = false
  local n = #pts / 2
  local j = n
  for i = 1, n do
    local xi, zi = pts[i * 2 - 1], pts[i * 2]
    local xj, zj = pts[j * 2 - 1], pts[j * 2]
    if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then inside = not inside end
    j = i
  end
  return inside
end

--- The bounding box of a flat point list with stride (2 for x,z; 3 for x,y,z).
function M.bounds(pts, stride)
  stride = stride or 2
  local zOff = stride == 3 and 2 or 1
  local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, #pts, stride do
    local x, z = pts[i], pts[i + zOff]
    if x < x0 then x0 = x end
    if x > x1 then x1 = x end
    if z < z0 then z0 = z end
    if z > z1 then z1 = z end
  end
  return x0, z0, x1, z1
end

--- Nearest point on segment a-b to p: returns t (0..1) and the squared distance.
function M.segmentNearest(ax, az, bx, bz, px, pz)
  local dx, dz = bx - ax, bz - az
  local len2 = dx * dx + dz * dz
  local t = 0
  if len2 > 0 then t = math.max(0, math.min(1, ((px - ax) * dx + (pz - az) * dz) / len2)) end
  local qx, qz = ax + dx * t, az + dz * t
  local ex, ez = px - qx, pz - qz
  return t, ex * ex + ez * ez, qx, qz
end

--- The nearest place on a 3D polyline to (x, z): distance, the height there, the segment index, t on it, the
-- point (qx, qz), and the direction of travel (dx, dz, unit).
function M.polylineNearest(pts, x, z)
  local best, bi, bt, by, bqx, bqz = math.huge, nil, 0, 0, 0, 0
  local bdx, bdz = 1, 0
  for i = 1, #pts - 3, 3 do
    local ax, ay, az = pts[i], pts[i + 1], pts[i + 2]
    local bx, byy, bz = pts[i + 3], pts[i + 4], pts[i + 5]
    local t, d2, qx, qz = M.segmentNearest(ax, az, bx, bz, x, z)
    if d2 < best then
      best, bi, bt, by, bqx, bqz = d2, (i + 2) / 3, t, ay + (byy - ay) * t, qx, qz
      local dx, dz = bx - ax, bz - az
      local len = sqrt(dx * dx + dz * dz)
      if len > 0 then bdx, bdz = dx / len, dz / len end
    end
  end
  return sqrt(best), by, bi, bt, bqx, bqz, bdx, bdz
end

--- Length of a 3D polyline, measured flat.
function M.polylineLength(pts)
  local len = 0
  for i = 1, #pts - 3, 3 do
    local dx, dz = pts[i + 3] - pts[i], pts[i + 5] - pts[i + 2]
    len = len + sqrt(dx * dx + dz * dz)
  end
  return len
end

--- The point s units along a 3D polyline (flat distance): x, y, z, dx, dz.
function M.polylineAt(pts, s)
  local walked = 0
  local n = #pts
  for i = 1, n - 3, 3 do
    local dx, dz = pts[i + 3] - pts[i], pts[i + 5] - pts[i + 2]
    local len = sqrt(dx * dx + dz * dz)
    if walked + len >= s or i + 3 >= n - 2 then
      local t = len > 0 and math.max(0, math.min(1, (s - walked) / len)) or 0
      return pts[i] + dx * t, pts[i + 1] + (pts[i + 4] - pts[i + 1]) * t, pts[i + 2] + dz * t,
        len > 0 and dx / len or 1, len > 0 and dz / len or 0
    end
    walked = walked + len
  end
  return pts[1], pts[2], pts[3], 1, 0
end

--- A Catmull-Rom curve through control points (x, y, z triples), sampled every step units: a 3D polyline.
-- This is how content makes curved roads: a few control points, then this.
function M.curve(ctrl, step)
  step = step or 4
  local out = {}
  local n = #ctrl / 3
  if n < 2 then
    for i = 1, #ctrl do out[i] = ctrl[i] end
    return out
  end
  local function P(i)
    i = math.max(1, math.min(n, i))
    return ctrl[i * 3 - 2], ctrl[i * 3 - 1], ctrl[i * 3]
  end
  for i = 1, n - 1 do
    local x0, y0, z0 = P(i - 1)
    local x1, y1, z1 = P(i)
    local x2, y2, z2 = P(i + 1)
    local x3, y3, z3 = P(i + 2)
    local seg = sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
    local pieces = math.max(1, floor(seg / step + 0.5))
    for k = 0, pieces - 1 do
      local t = k / pieces
      local t2, t3 = t * t, t * t * t
      local function cr(a, b, c, d)
        return 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
      end
      out[#out + 1] = cr(x0, x1, x2, x3)
      out[#out + 1] = cr(y0, y1, y2, y3)
      out[#out + 1] = cr(z0, z1, z2, z3)
    end
  end
  local lx, ly, lz = P(n)
  out[#out + 1], out[#out + 2], out[#out + 3] = lx, ly, lz
  return out
end

--- A circle (or arc) as a closed 3D polyline at height y: centre, radius, pieces.
function M.circle(cx, y, cz, r, pieces, a0, a1)
  a0, a1 = a0 or 0, a1 or math.pi * 2
  local out = {}
  for k = 0, pieces do
    local a = a0 + (a1 - a0) * k / pieces
    out[#out + 1] = cx + math.cos(a) * r
    out[#out + 1] = y
    out[#out + 1] = cz + math.sin(a) * r
  end
  return out
end

--- A rotated box { cx, cz, w (along its angle), d (across), angle, ... }: (x, z) in its own frame.
function M.boxLocal(b, x, z)
  local c, s = math.cos(b[5]), math.sin(b[5])
  local dx, dz = x - b[1], z - b[2]
  return dx * c + dz * s, -dx * s + dz * c
end

function M.inBox(b, x, z, pad)
  pad = pad or 0
  local lx, lz = M.boxLocal(b, x, z)
  return math.abs(lx) < b[3] / 2 + pad and math.abs(lz) < b[4] / 2 + pad
end

--- Push a circle (x, z, r) out of a rotated box. Returns new x, z and the push normal, or nil if not touching.
function M.pushOutOfBox(b, x, z, r)
  local hw, hd = b[3] / 2, b[4] / 2
  local lx, lz = M.boxLocal(b, x, z)
  local qx, qz = math.max(-hw, math.min(hw, lx)), math.max(-hd, math.min(hd, lz))
  local ex, ez = lx - qx, lz - qz
  local d = sqrt(ex * ex + ez * ez)
  local nlx, nlz
  if d > 0.0001 then
    if d >= r then return nil end
    local k = (r - d) / d
    lx, lz = lx + ex * k, lz + ez * k
    nlx, nlz = ex / d, ez / d
  else
    local m = math.min(hw - lx, lx + hw, hd - lz, lz + hd)
    if m == hw - lx then lx, nlx, nlz = hw + r, 1, 0
    elseif m == lx + hw then lx, nlx, nlz = -hw - r, -1, 0
    elseif m == hd - lz then lz, nlx, nlz = hd + r, 0, 1
    else lz, nlx, nlz = -hd - r, 0, -1 end
  end
  local c, s = math.cos(b[5]), math.sin(b[5])
  return b[1] + lx * c - lz * s, b[2] + lx * s + lz * c, nlx * c - nlz * s, nlx * s + nlz * c
end

--- Push a circle out of a polygon (x, z pairs) by its nearest edge. Returns x, z, nx, nz, or nil if outside.
function M.pushOutOfPolygon(pts, x, z, r)
  local inside = M.inPolygon(pts, x, z)
  local best, bqx, bqz = math.huge, x, z
  local n = #pts / 2
  local j = n
  for i = 1, n do
    local _, d2, qx, qz = M.segmentNearest(pts[j * 2 - 1], pts[j * 2], pts[i * 2 - 1], pts[i * 2], x, z)
    if d2 < best then best, bqx, bqz = d2, qx, qz end
    j = i
  end
  local d = sqrt(best)
  if not inside and d >= r then return nil end
  local nx, nz = x - bqx, z - bqz
  local len = sqrt(nx * nx + nz * nz)
  if len < 0.0001 then return nil end
  nx, nz = nx / len, nz / len
  if inside then nx, nz = -nx, -nz end
  return bqx + nx * r, bqz + nz * r, nx, nz
end

return M
