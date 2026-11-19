-- combat/aim.lua
-- Aiming for a keyboard. You do not steer a cursor: the game locks on to the best target in front of you, shows it
-- with a bracket, and K cycles to the next one. On foot the cone is narrow (you turn with A and D); in a car or on a
-- bike it is wide, so a drive-by finds whoever is beside you. Pure: it works on lists of things with x and z.
--
--   aim.rank(list, x, z, h, range, cone) -> { { e, d, a, score }, ... } best first
--   aim.best(list, x, z, h, range, cone) -> e | nil
--   aim.cycle(ranked, current) -> the next one after current in the ranking (wrapping), or the first
--   aim.angle(x, z, tx, tz) -> the heading from one point to another

local M = {}

M.FOOT_CONE = 1.15 -- radians either side of where you face (66 degrees)
M.CAR_CONE = 1.9 -- a drive-by sees nearly everything but straight behind (109 degrees)

local atan2 = math.atan2 or math.atan
local abs, sqrt = math.abs, math.sqrt

function M.angle(x, z, tx, tz) return atan2(tz - z, tx - x) end

local function wrap(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

--- Candidates within range and the cone, best first: near beats far, straight ahead beats off to the side, and
-- someone hostile beats someone who is not.
function M.rank(list, x, z, h, range, cone)
  local out = {}
  for _, e in ipairs(list) do
    local dx, dz = e.x - x, e.z - z
    local d = sqrt(dx * dx + dz * dz)
    if d <= range and d > 0.05 then
      local a = wrap(atan2(dz, dx) - h)
      if abs(a) <= cone then
        local score = d + 14 * abs(a) - ((e.hostile or (e.tags and (e.tags.hostile or e.tags.enemy))) and 6 or 0)
        out[#out + 1] = { e = e, d = d, a = a, score = score }
      end
    end
  end
  table.sort(out, function(p, q)
    if p.score ~= q.score then return p.score < q.score end
    return (p.e.id or 0) < (q.e.id or 0)
  end)
  return out
end

function M.best(list, x, z, h, range, cone)
  local r = M.rank(list, x, z, h, range, cone)
  return r[1] and r[1].e or nil
end

--- The one after current in a ranking (the first if current is not in it).
function M.cycle(ranked, current)
  if #ranked == 0 then return nil end
  for i, r in ipairs(ranked) do
    if r.e == current then return ranked[i % #ranked + 1].e end
  end
  return ranked[1].e
end

return M
