-- gearshop/improve.lua
-- IMPROVEMENTS by build (Phase 2 of IMPROVEMENTS-SEARCH-DESIGN.md in the lobby build folder): which build a player plays,
-- how well a piece fits it, and which pieces in stock beat what they wear. Pure: shop.lua reads the player (vhcctweaks
-- 2.2.37) and hands the answers in, so Tests/gearshop_test.lua runs all of this on its own.
--
-- A player read: { level, greed, gearScore, worn = { slot = piece }, temper = { might, magic, vigor } (levels),
--   skills = { { id, specialization, level, selected } } or nil, totals = { attribute = value } or nil (stat screen,
--   uncapped), caps = { attribute = the player's own cap } or nil, trinkets = { "spellbook", ... }, limited = true when
--   the server could not give everything (an older vhcctweaks) }.
-- Pieces are rules.piece records: stats = { attribute = value }, abil = { { ab, lv } }, slot, type, level, gs, greed, broken.

local builds = require("lib.gearshop.builds")
local rules = require("lib.gearshop.rules")

local M = {}

local function matchesAny(name, patterns)
  if type(name) ~= "string" then return false end
  for _, p in ipairs(patterns or {}) do
    if name:find(p) then return true end
  end
  return false
end

-- ---------------------------------------------------------------- inference

local SKIP = {}
for a in pairs(builds.UNIVERSAL) do SKIP[a] = true end
for a in pairs(builds.IGNORE) do SKIP[a] = true end

--- The cosine of two attribute vectors, leaving out the survival floor and the ignored stats (every piece has armor).
local function cosine(v, w)
  local dot, nv, nw = 0, 0, 0
  for a, x in pairs(v) do
    if not SKIP[a] then
      nv = nv + x * x
      dot = dot + x * (w[a] or 0)
    end
  end
  for a, y in pairs(w) do
    if not SKIP[a] then nw = nw + y * y end
  end
  if nv == 0 or nw == 0 then return 0 end
  return dot / math.sqrt(nv * nw)
end

local TYPE_WORDS = { ["the_vault:wand"] = "Wand", ["the_vault:focus"] = "Focus", ["the_vault:shield"] = "Shield",
  ["the_vault:battlestaff"] = "Battlestaff" }

--- Which build a player plays. Returns id, confidence (0..1), a one-line reason, scores { id = score }.
function M.infer(read, all)
  all = all or builds.all()
  local worn = read.worn or {}
  local s, why = {}, {}
  local function bump(id, by, reason)
    if s[id] == nil then return end
    s[id] = s[id] + by
    if reason and by > 0 then why[id] = why[id] or {}; why[id][#why[id] + 1] = { by, reason } end
  end
  -- 1. what they wear, in REF units
  local v, counted, lines = {}, 0, {}
  for _, piece in pairs(worn) do
    if piece.stats then
      counted = counted + 1
      for a, x in pairs(piece.stats) do
        local ref = builds.REF[a]
        if ref and type(x) == "number" then
          v[a] = (v[a] or 0) + x / ref
          lines[a] = (lines[a] or 0) + 1
        end
      end
    end
  end
  -- 2. gear similarity
  for _, id in ipairs(builds.ORDER) do
    if id ~= "balanced" then s[id] = cosine(v, all[id].weights) end
  end
  for id in pairs(s) do
    -- the stat that build weighs most that they wear most of, as the reason
    local best, most = nil, 0
    for a, n in pairs(lines) do
      local w = all[id].weights[a] or 0
      if not SKIP[a] and w >= 2 and n > most then best, most = a, n end
    end
    if best then why[id] = { { s[id], most .. " " .. rules.statName(best) .. (most == 1 and " line" or " lines") } } end
  end
  -- 3. Temper: Might is attack damage, Magic ability power, Vigor health
  local t = read.temper
  if t and ((t.might or 0) + (t.magic or 0) + (t.vigor or 0)) > 0 then
    local mi, ma, vi = t.might or 0, t.magic or 0, t.vigor or 0
    local lean = (ma - mi) / math.max(1, ma + mi)
    for _, id in ipairs({ "caster", "summoner", "healer" }) do bump(id, 0.20 * lean, lean > 0.2 and "Magic Temper" or nil) end
    for _, id in ipairs({ "melee", "lucky" }) do bump(id, -0.20 * lean, lean < -0.2 and "Might Temper" or nil) end
    bump("hybrid", 0.10 * (1 - math.abs(lean)))
    local vigor = vi / (mi + ma + vi)
    bump("tank", 0.25 * (vigor - 1 / 3), vigor > 0.5 and "Vigor Temper" or nil)
    bump("thorns", 0.15 * (vigor - 1 / 3))
  end
  -- 4. what they hold
  local off, main = worn.offhand and worn.offhand.type, worn.weapon and worn.weapon.type
  local hints = {
    ["the_vault:wand"] = { caster = 0.10, summoner = 0.05 },
    ["the_vault:focus"] = { caster = 0.05, healer = 0.05, summoner = 0.05 },
    ["the_vault:shield"] = { tank = 0.08, thorns = 0.05 },
  }
  for id, by in pairs(hints[off] or {}) do bump(id, by, TYPE_WORDS[off]) end
  if worn.offhand and worn.offhand.stats and worn.offhand.stats.thorns_damage_flat then bump("thorns", 0.15, "Thorns shield") end
  if main == "the_vault:battlestaff" then bump("hybrid", 0.12, "Battlestaff") end
  for _, slot in ipairs({ "weapon", "offhand" }) do
    if worn[slot] and worn[slot].stats and worn[slot].stats.summon_damage then bump("summoner", 0.12, "Summon damage") end
  end
  -- 5. abilities: boosted on their gear, and (2.2.37) the ones they learned, the one on their key most of all
  for _, piece in pairs(worn) do
    for _, line in ipairs(piece.abil or {}) do
      for _, id in ipairs(builds.ORDER) do
        if id ~= "balanced" and matchesAny(line.ab, all[id].abilities) then bump(id, 0.06, (line.ab:gsub("_", " ")) .. " on gear") end
      end
    end
  end
  for _, ab in ipairs(read.skills or {}) do
    local names = { ab.specialization, ab.id }
    for _, id in ipairs(builds.ORDER) do
      if id ~= "balanced" and (matchesAny(names[1], all[id].abilities) or matchesAny(names[2], all[id].abilities)) then
        bump(id, ab.selected and 0.12 or 0.05, ab.selected and ((ab.name or ab.id) .. " on your key") or nil)
      end
    end
  end
  -- 6. trinkets
  for _, name in ipairs(read.trinkets or {}) do
    local id = builds.TRINKETS[tostring(name):gsub("^.*:", "")]
    if id then bump(id, 0.06, rules.statName(tostring(name):gsub("^.*:", ""))) end
  end
  -- 7. how sure
  local best, second
  for _, id in ipairs(builds.ORDER) do
    if s[id] then
      if not best or s[id] > s[best] then best, second = id, best
      elseif not second or s[id] > s[second] then second = id end
    end
  end
  local coverage = math.min(1, counted / 6)
  local conf = 0
  if best and s[best] > 0 then
    -- How far the best is ahead of the next: a lead of 0.15 is sure. (The design divided the lead by the best score,
    -- but builds that share their main stat, caster and summoner, stay close in score even for a plain caster, which
    -- kept a clear caster under the 0.35 line.) Fewer pieces worn, less sure.
    conf = math.max(0, math.min(1, (s[best] - (s[second] or 0)) / 0.15)) * (0.4 + 0.6 * coverage)
  end
  if not best or conf < 0.35 or (read.gearScore and read.gearScore < 250) then
    return "balanced", conf, "Not sure from what you wear: pick your build", s
  end
  local reasons = why[best] or {}
  table.sort(reasons, function(a, b) return a[1] > b[1] end)
  local parts, seen = {}, {}
  for _, r in ipairs(reasons) do
    if #parts < 3 and not seen[r[2]] then
      seen[r[2]] = true
      parts[#parts + 1] = r[2]
    end
  end
  return best, conf, (#parts > 0 and table.concat(parts, ", ") or "what you wear"), s
end

-- ---------------------------------------------------------------- fit

--- A piece's fit to a build, in fit points (100 = one best-roll line at weight 1). Capped stats count only up to the cap:
-- totals are what the player has in all (stat screen, or the sum of what they wear), slotCur what the piece it would
-- replace gives, caps the caps (the player's own, else the build's).
function M.fit(piece, build, totals, slotCur, caps)
  if not piece or not piece.stats and not piece.abil then return 0 end
  local pts = 0
  for a, val in pairs(piece.stats or {}) do
    local w = builds.weight(build, a)
    local ref = builds.REF[a]
    if w > 0 and ref and type(val) == "number" then
      local cap = (caps and caps[a]) or build.caps[a]
      if cap then
        local others = math.max(0, (totals and totals[a] or 0) - (slotCur and slotCur[a] or 0))
        val = math.max(0, math.min(cap, others + val) - math.min(cap, others))
      end
      pts = pts + w * val / ref
    end
  end
  local abil = 0
  for _, line in ipairs(piece.abil or {}) do
    if matchesAny(line.ab, build.abilities) then abil = abil + (line.lv or 0) end
  end
  pts = pts + builds.weight(build, "added_ability_level") * abil * 0.5
  return pts * 100
end

local function allowed(build, piece)
  local list = build.require and build.require[piece.slot]
  if not list then return true end
  for _, t in ipairs(list) do
    if piece.type == t then return true end
  end
  return false
end

--- Whether a piece would lose too much of a stat the build lives on, against what is worn there.
local function losesCore(build, cand, cur)
  if not cur or not cur.stats then return false end
  if build.keepSlots and not build.keepSlots[cand.slot] then return false end
  local limit = build.keepLoss or 0.10
  local function loss(k)
    local was = cur.stats[k] or 0
    if was <= 0 then return 0 end
    return (was - ((cand.stats or {})[k] or 0)) / was
  end
  for _, k in ipairs(build.keep or {}) do
    if loss(k) > limit then return true end
  end
  if build.keepAny then
    local worst = true
    for _, k in ipairs(build.keepAny) do
      if loss(k) <= limit then worst = false end
    end
    if worst then return true end
  end
  return false
end
M.losesCore = losesCore

--- How much a piece improves on what is worn in its slot, for a build: { delta, fit, worth }, or nil when the build may not
-- use it (its type, or it costs a core stat).
function M.upgrade(cand, cur, build, ctx)
  if not allowed(build, cand) then return nil end
  if losesCore(build, cand, cur) then return nil end
  local slotCur = cur and cur.stats or {}
  local fc = M.fit(cand, build, ctx.totals, slotCur, ctx.caps)
  local fo = cur and M.fit(cur, build, ctx.totals, slotCur, ctx.caps) or 0
  local delta = fc - fo
  local worth = delta >= math.max(builds.WORTH.minPoints, builds.WORTH.minRel * fo)
  return { delta = delta, fit = fc, worth = worth }
end

-- ---------------------------------------------------------------- the search

--- The player's totals for the caps: the stat screen's when the server gives it, else the sum of what they wear.
local function totalsOf(read)
  if read.totals then return read.totals end
  local t = {}
  for _, piece in pairs(read.worn or {}) do
    for a, v in pairs(piece.stats or {}) do
      if type(v) == "number" then t[a] = (t[a] or 0) + v end
    end
  end
  return t
end

--- Pieces in stock that are worth it for a build: { { piece, key, level, delta, later } } usable-now first, biggest gain
-- first; and counts { slot = n }. The level window is the same as Phase 1 (improveBelow, improveAbove); identified,
-- unbroken pieces only, and no greedier than the player can wear. The looter build judges only boots and magnets; for
-- anything else it falls back to balanced.
function M.search(pieces, read, buildId, slot, cfg, all)
  cfg = cfg or rules.DEFAULTS
  all = all or builds.all(cfg.buildWeights)
  local level = math.floor(tonumber(read.level) or 0)
  local below = cfg.improveBelow or rules.DEFAULTS.improveBelow
  local lo = math.max(0, math.min(100, level) - below)
  local hi = math.min(100, level + (cfg.improveAbove or rules.DEFAULTS.improveAbove))
  if level >= 100 then lo, hi = math.max(0, 100 - below), 100 end
  local ctx = { totals = totalsOf(read), caps = read.caps }
  local out, counts = {}, {}
  for _, p in ipairs(pieces) do
    if p.slot and p.stats and not p.unidentified and not p.broken and (p.level or 0) >= lo and (p.level or 0) <= hi
      and not (p.greed and read.greed and p.greed > read.greed) then
      local id = buildId
      if id == "looter" and p.slot ~= "feet" and p.slot ~= "magnet" then id = "balanced" end
      local up = M.upgrade(p, (read.worn or {})[p.slot], all[id] or all.balanced, ctx)
      if up and up.worth then
        counts[p.slot] = (counts[p.slot] or 0) + 1
        if slot == "any" or slot == p.slot then
          out[#out + 1] = { piece = p, key = p.key, level = p.level, delta = up.delta, later = (p.level or 0) > level,
            gs = (p.gs or 0) - (((read.worn or {})[p.slot] or {}).gs or 0) }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.later ~= b.later then return not a.later end
    local da, db = math.floor(a.delta / 5 + 0.5), math.floor(b.delta / 5 + 0.5)
    if da ~= db then return da > db end
    if a.gs ~= b.gs then return a.gs > b.gs end
    return a.key < b.key
  end)
  return out, counts
end

return M
