-- gearlocker/judge.lua
-- Which pieces in a player's ME are junk and which beat what they wear. Pure: locker.lua reads the ME and the player
-- and hands everything in, so Tests/gearlocker_test.lua runs this on its own.
-- Pieces are lib.gearshop.rules.piece records with an `fp` (the ME fingerprint); a read is improve.lua's player read.

local rules = require("lib.gearshop.rules")
local builds = require("lib.gearshop.builds")
local improve = require("lib.gearshop.improve")

local M = {}

M.DEFAULTS = {
  keepPerSlot = 3,
  maxBelow = 20,
  minRarity = "RARE",
  keepLegendary = true,
  auto = false,
  autoEvery = 300,
}

local SLOT_WORDS = { head = "Helmets", chest = "Chestplates", legs = "Leggings", feet = "Boots", weapon = "Weapons",
  offhand = "Offhands", magnet = "Magnets" }
M.SLOT_WORDS = SLOT_WORDS

function M.settings(cfg)
  local out = {}
  for k, v in pairs(M.DEFAULTS) do out[k] = v end
  for k, v in pairs(type(cfg) == "table" and cfg or {}) do out[k] = v end
  return out
end

local function word(rarity)
  rarity = tostring(rarity)
  return rarity:sub(1, 1):upper() .. rarity:sub(2):lower()
end

function M.build(read, picked)
  local all = builds.all()
  if picked == "gs" then return "gs", "Best rolled (Gear Score)", "your pick" end
  if picked and all[picked] then return picked, all[picked].label, "your pick" end
  if not read then return "balanced", all.balanced.label, "can't read you right now" end
  local id, _, why = improve.infer(read, all)
  return id, all[id].label, why
end

function M.upgrades(pieces, read, buildId, cfg)
  cfg = M.settings(cfg)
  if not read then return {}, {}, {}, "can't read you right now" end
  local scored = false
  for _, p in ipairs(pieces) do
    if (buildId == "gs" and p.gs) or (buildId ~= "gs" and p.stats) then scored = true break end
  end
  -- 2.2.36 gives no numbers on a piece, so there's nothing to compare
  if not scored and #pieces > 0 then return {}, {}, {}, "upgrades need vhcctweaks 2.2.37" end
  local worn = read.worn or {}
  local list, counts
  if buildId == "gs" then
    local gs = {}
    for slot, p in pairs(worn) do gs[slot] = p.gs end
    list, counts = rules.improvements(pieces, gs, read.level, "any", cfg)
  else
    list, counts = improve.search(pieces, read, buildId or "balanced", "any", cfg)
  end
  local best = {}
  for _, e in ipairs(list) do
    e.worn = worn[e.piece.slot]
    if not best[e.piece.slot] then best[e.piece.slot] = e end
  end
  return list, best, counts
end

function M.junk(pieces, read, buildId, cfg, spared)
  cfg = M.settings(cfg)
  spared = spared or {}
  local all = builds.all(cfg.buildWeights)
  local caps = read and read.caps

  -- how good a piece is for ranking in its slot; nil when the server gave no numbers for it
  local function score(p)
    if not p then return nil end
    if buildId == "gs" then return p.gs end
    if not p.stats and not p.abil then return nil end
    local id = buildId
    if id == "looter" and p.slot ~= "feet" and p.slot ~= "magnet" then id = "balanced" end
    return improve.fit(p, all[id] or all.balanced, nil, nil, caps)
  end

  local ups = {}
  if read then
    for _, e in ipairs((M.upgrades(pieces, read, buildId, cfg))) do ups[e.piece.fp] = true end
  end

  local bySlot, sc = {}, {}
  for _, p in ipairs(pieces) do
    if p.kind == "Gear" and p.slot and not p.unidentified then
      sc[p] = score(p)
      bySlot[p.slot] = bySlot[p.slot] or {}
      table.insert(bySlot[p.slot], p)
    end
  end
  local rank, better = {}, {}
  for _, list in pairs(bySlot) do
    table.sort(list, function(a, b)
      local sa, sb = sc[a], sc[b]
      if (sa ~= nil) ~= (sb ~= nil) then return sa ~= nil end
      if sa and sa ~= sb then return sa > sb end
      if (a.legendary and 1 or 0) ~= (b.legendary and 1 or 0) then return a.legendary == true end
      local ra, rb = rules.rarityRank(a.rarity), rules.rarityRank(b.rarity)
      if ra ~= rb then return ra > rb end
      if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
      return tostring(a.fp) < tostring(b.fp)
    end)
    local above = 0
    for i, p in ipairs(list) do
      rank[p.fp] = i
      -- ties don't count as better, so twins never push each other out
      if i > 1 and sc[list[i - 1]] ~= sc[p] then above = i - 1 end
      if sc[p] ~= nil then better[p.fp] = above end
    end
  end

  local level = read and math.min(100, math.floor(tonumber(read.level) or 0))
  local minRank = rules.rarityRank(cfg.minRarity)
  local junk, keep = {}, {}
  for _, p in ipairs(pieces) do
    local why
    if p.kind ~= "Gear" then keep[p.fp] = "not gear"
    elseif not p.slot then keep[p.fp] = "no slot"
    elseif p.unidentified then keep[p.fp] = "unidentified"
    elseif spared[p.fp] then keep[p.fp] = "spared"
    elseif ups[p.fp] then keep[p.fp] = "upgrade"
    elseif p.legendary and cfg.keepLegendary then keep[p.fp] = "legendary"
    elseif p.broken then keep[p.fp] = "broken, can be repaired"
    elseif rank[p.fp] <= cfg.keepPerSlot then
      keep[p.fp] = "top " .. cfg.keepPerSlot .. " " .. SLOT_WORDS[p.slot]
    else
      local lv = p.level or 0
      if level and lv < level - cfg.maxBelow then
        why = "lvl " .. lv .. ", " .. (level - lv) .. " under you"
      elseif rules.rarityRank(p.rarity) > 0 and rules.rarityRank(p.rarity) < minRank then
        why = word(p.rarity)
      elseif read and better[p.fp] and better[p.fp] >= cfg.keepPerSlot then
        -- only when it's no better than what they have on
        local w = score((read.worn or {})[p.slot])
        if w == nil or sc[p] <= w then why = better[p.fp] .. " better " .. SLOT_WORDS[p.slot] end
      end
      if why then junk[#junk + 1] = { piece = p, reason = why } else keep[p.fp] = "fine" end
    end
  end
  table.sort(junk, function(a, b)
    if (a.piece.level or 0) ~= (b.piece.level or 0) then return (a.piece.level or 0) < (b.piece.level or 0) end
    return tostring(a.piece.fp) < tostring(b.piece.fp)
  end)
  return junk, keep
end

return M
