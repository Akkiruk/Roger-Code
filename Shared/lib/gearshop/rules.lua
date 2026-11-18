-- gearshop/rules.lua
-- The gear shop's rules as plain maths: what a piece costs, what the shop buys and for how much, how a tab is paid, which
-- pieces go on display. No peripherals, no ccvault and no screen, so Tests/gearshop_test.lua runs it on its own.
--
-- Money that can be a fraction (what a seller is owed, store credit) is kept in thousandths of a token, as whole numbers,
-- so nothing is ever lost to rounding. Prices and the tab are whole tokens.

local M = {}

M.MILLI = 1000

--- Every limit the owner can change (config.lua keeps the owner's own values over these).
M.DEFAULTS = {
  pricePerLevel = 1,        -- a piece costs this many tokens per level of the gear: level 50 is 50, level 100 is 100
  minPrice = 1,             -- no piece costs less than this (a level 0 piece costs 1). The same for every rarity
  creditPerPiece = 1,       -- a seller gets this much store credit for each accepted piece
  tokensPerPiece = 1,       -- with sellForTokens on, a seller who picks tokens gets this many for each accepted piece
  ownerFloor = 1000,        -- a token payout never takes the owner's balance below this
  sellForTokens = false,    -- off: selling to the shop pays store credit only, so the shop never pays tokens out for gear.
                            -- Anything already owed from an earlier token sale is still paid. On: sellers pick tokens or credit.
  acceptRarities = { "EPIC", "OMEGA" },  -- bought from players, besides anything legendary
  highLevel = 70,           -- above this level only OMEGA and legendary pieces are bought
  highRarities = { "OMEGA" },
  topLevel = 100,           -- from this level only legendary pieces are bought
  sellTypes = { "Gear" },   -- the vaultData.itemType values the shop puts on display
  chargeAsTaken = true,     -- a piece is paid for as it is taken, and a tab on the next tap or at check-out, whenever the
                            -- server lets the shop charge the player. Off: pieces only go on the tab, paid with PAY
  improveMargin = 25,       -- IMPROVEMENTS at the kiosk: a piece counts when its Gear Score beats what the shopper wears in
                            -- that slot by at least this much
  improveBelow = 20,        -- and is no more than this many levels under the shopper's level
  improveAbove = 3,         -- or up to this many over it (those come after the ones usable now)
  buildWeights = {},        -- the owner's own weights for the IMPROVEMENTS builds (page 4, B), over lib/gearshop/builds.lua:
                            -- { build = { attribute = weight } }
  stationsPerShopper = 3,   -- display stations one shopper may hold at once: tapping one more frees the one they used
                            -- longest ago. 0 is no limit. Check-in fills none; a station fills when its shopper taps it
  stationIdleMinutes = 5,   -- a station whose shopper has not tapped it or taken from it this long is emptied and freed
  stationLeaveDistance = 12,  -- a shopper this far from a station they hold (two looks running) has walked away: it is freed
  defaultLevel = 0,        -- the level used for a shopper whose vault level cannot be read
  idleMinutes = 30,         -- a shopper who touches nothing this long is checked out
  presenceSeconds = 20,     -- how often the shop looks for its shoppers
  leaveDistance = 48,       -- a shopper further than this from the shop is checked out
  chargeRange = 6,          -- how far a display chest's detector looks for whoever took a piece
  stationPollSeconds = 5,   -- open display chests are looked at this often, in case a change event was missed
  rescanSeconds = 3,        -- one vault chest that is not watched is looked at this often
  maxWatches = 64,          -- the server's inventory.maxWatchesPerComputer
  maxBatchMoves = 256,      -- the server's inventory.maxBatchMoves
  vaultMatch = "sophisticated",  -- every unassigned inventory whose type has this in it is a vault chest
  textScale = 0.5,
  -- The wings a display chest can be given in setup (G on the setup page), each with the gear types it shows: a name
  -- matches a type exactly or as the start of one ("idol" is every idol). A wing with rest = true has every type no
  -- other wing names. A chest with no wing shows any type, as before there were wings. A station given one gear type
  -- (the usual way: one station per type) is put in that type's wing for its label.
  categories = {
    { name = "Weapons", types = { "sword", "axe", "battlestaff", "trident", "rang" } },
    { name = "Armour", types = { "helmet", "chestplate", "leggings", "boots", "shield" } },
    { name = "Magic", types = { "wand", "focus", "idol" } },
    { name = "Oddities", rest = true },
  },
}

local function has(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then return true end
  end
  return false
end

-- ---------------------------------------------------------------- levels and prices

--- The 10-level bracket a level is in: 0 for 0-9, 4 for 40-49, 10 for 100 and up.
function M.bracket(level)
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  local b = math.floor(level / 10)
  if b > 10 then b = 10 end
  return b
end

function M.bracketLabel(b)
  if b <= 0 then return "1-9" end
  if b >= 10 then return "100" end
  return (b * 10) .. "-" .. (b * 10 + 9)
end

--- What a piece of this level costs, in whole tokens: pricePerLevel a level, never under minPrice. The same for every rarity.
function M.price(level, cfg)
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  local per = (cfg and cfg.pricePerLevel) or M.DEFAULTS.pricePerLevel
  local least = math.floor((cfg and cfg.minPrice) or M.DEFAULTS.minPrice)
  return math.max(least, math.floor(level * per + 0.5), 0)
end

--- The cheapest and dearest price a piece in a bracket can have: 1-9 is 1 and 9, 40-49 is 40 and 49, 100 is 100 and 100.
function M.bracketPrices(b, cfg)
  if b >= 10 then return M.price(100, cfg), M.price(100, cfg) end
  return M.price(b * 10, cfg), M.price(b * 10 + 9, cfg)
end

--- "40-49", or "100" when the cheapest and dearest are the same.
function M.priceRange(low, high)
  if not low then return "" end
  if low == high then return tostring(low) end
  return low .. "-" .. high
end

-- ---------------------------------------------------------------- pieces

--- The name one item goes by everywhere in the shop. Gear does not stack, and its NBT hash tells two swords apart.
function M.key(item)
  return tostring(item.name) .. "#" .. tostring(item.nbt or "")
end

function M.typeLabel(kind)
  local path = tostring(kind):match(":(.+)$") or tostring(kind)
  path = path:gsub("_", " ")
  return (path:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b:lower() end))
end

local AFFIXES = { "implicits", "prefixes", "suffixes" }

local function legendary(vd)
  if vd.isLegendary == true then return true end
  for _, affix in ipairs(AFFIXES) do
    local list = vd[affix]
    if type(list) == "table" then
      for _, mod in ipairs(list) do
        if type(mod) == "table" and mod.legendary == true then return true end
      end
    end
  end
  return false
end

--- What the shop remembers about one item, from what getItemDetail (or listDetailed) says about it.
-- Anything can be stored, so an item with no vault data still gets a record; only `kind` says it is gear.
function M.piece(detail)
  if type(detail) ~= "table" or type(detail.name) ~= "string" then return nil end
  local vd = type(detail.vaultData) == "table" and detail.vaultData or {}
  local words = {}
  for _, affix in ipairs(AFFIXES) do
    local list = vd[affix]
    if type(list) == "table" then
      for _, mod in ipairs(list) do
        if type(mod) == "table" and type(mod.name) == "string" then words[#words + 1] = mod.name end
      end
    end
  end
  -- the numbers the advanced search and IMPROVEMENTS work from (vhcctweaks 2.2.37 details): each modifier's attribute
  -- (registry id, kept without "the_vault:") and numeric value, summed when a piece has several lines of one attribute
  local stats, abil
  for _, affix in ipairs(AFFIXES) do
    local list = vd[affix]
    if type(list) == "table" then
      for _, mod in ipairs(list) do
        if type(mod) == "table" and type(mod.attribute) == "string" and type(mod.value) == "number" then
          local a = mod.attribute:gsub("^the_vault:", "")
          stats = stats or {}
          stats[a] = (stats[a] or 0) + mod.value
        elseif type(mod) == "table" and type(mod.value) == "table" and mod.value.ability then
          -- "+2 Fireball Volley": { ability, levelChange }, for IMPROVEMENTS by build
          abil = abil or {}
          abil[#abil + 1] = { ab = tostring(mod.value.ability), lv = tonumber(mod.value.levelChange) or 1 }
        end
      end
    end
  end
  local label = vd.gearName or vd.name or detail.displayName or M.typeLabel(detail.name)
  local piece = {
    key = M.key(detail),
    id = detail.name,
    type = detail.name,
    kind = type(vd.itemType) == "string" and vd.itemType or nil,
    level = tonumber(vd.level) or 0,
    rarity = type(vd.rarity) == "string" and vd.rarity:upper() or nil,
    legendary = legendary(vd) or nil,
    -- vhcctweaks gives UNIDENTIFIED, ROLLING or IDENTIFIED; anything but IDENTIFIED cannot be judged yet
    unidentified = (type(vd.state) == "string" and vd.state:upper() ~= "IDENTIFIED") or nil,
    label = tostring(label),
    stats = stats,
    abil = abil,
    -- the slot it is worn in: head, chest, legs, feet, weapon (mainhand), offhand; a magnet has no equipmentSlot
    slot = (vd.equipmentSlot == "mainhand" and "weapon") or (type(vd.equipmentSlot) == "string" and vd.equipmentSlot)
      or (detail.name == "the_vault:magnet" and "magnet") or nil,
    -- the piece's own Gear Score, when the scorer counts it
    gs = (type(vd.gearScore) == "number" and (vd.gearScoreStatus == nil or vd.gearScoreStatus == "COUNTED")) and vd.gearScore or nil,
    greed = tonumber(vd.greedTier),
    broken = (type(vd.durability) == "table" and vd.durability.current == 0) or nil,
  }
  piece.search = (piece.label .. " " .. table.concat(words, " ")):lower()
  return piece
end

-- ---------------------------------------------------------------- stats, for the advanced search

--- "ability_power" reads "Ability Power".
function M.statName(a)
  return (tostring(a):gsub("^.*:", ""):gsub("_", " "):gsub("(%a)([%w]*)", function(x, y) return x:upper() .. y:lower() end))
end

--- Which group a stat is listed under on the kiosk, from words in its name: Offense, Defense or Utility.
local OFFENSE = { "damage", "attack", "crit", "power", "fatal", "cleave", "thorns_damage", "execute", "chaining", "shocking",
  "sweeping", "hammer", "spell", "ability", "stun", "lightning", "fire", "poison", "freeze" }
local DEFENSE = { "armor", "armour", "resist", "health", "block", "knockback", "dodge", "toughness", "healing", "heal",
  "regen", "thorns", "immunity", "absorb", "shield" }
function M.statGroup(a)
  a = tostring(a):lower()
  for _, word in ipairs(OFFENSE) do
    if a:find(word, 1, true) then return "Offense" end
  end
  for _, word in ipairs(DEFENSE) do
    if a:find(word, 1, true) then return "Defense" end
  end
  return "Utility"
end

--- A stat's value for the screen: 0.125 reads "0.13", 12.5 reads "12.5", 120 reads "120".
function M.showStat(v)
  v = tonumber(v) or 0
  if v == math.floor(v) then return tostring(v) end
  if math.abs(v) < 10 then return (("%.2f"):format(v):gsub("0$", "")) end
  return ("%.1f"):format(v)
end

--- How much one tap of + or - changes a stat's minimum: about a tenth of the best in stock, rounded to a plain step.
function M.statStep(max)
  max = math.abs(tonumber(max) or 0)
  if max <= 0 then return 1 end
  local raw = max / 10
  local p = 10 ^ math.floor(math.log10 and math.log10(raw) or (math.log(raw) / math.log(10)))
  for _, m in ipairs({ 1, 2, 5, 10 }) do
    if raw <= m * p then return m * p end
  end
  return 10 * p
end

--- LEGENDARY, or the piece's own rarity.
function M.grade(piece)
  if piece.legendary then return "LEGENDARY" end
  return piece.rarity or "?"
end

--- Whether the shop puts this on display at all.
function M.forSale(piece, cfg)
  return piece.kind ~= nil and has((cfg and cfg.sellTypes) or M.DEFAULTS.sellTypes, piece.kind)
end

-- ---------------------------------------------------------------- buying from players

--- Whether the shop buys this piece. Returns true, or false and why not.
function M.accepts(piece, cfg)
  cfg = cfg or M.DEFAULTS
  if not piece or not M.forSale(piece, cfg) then return false, "not gear" end
  if piece.unidentified then return false, "identify it first" end
  local level = piece.level or 0
  if piece.legendary then return true end
  if level >= cfg.topLevel then return false, "Legendary only at " .. cfg.topLevel end
  if level > cfg.highLevel then
    if has(cfg.highRarities, piece.rarity) then return true end
    return false, "Omega+ above " .. cfg.highLevel
  end
  if has(cfg.acceptRarities, piece.rarity) then return true end
  return false, "Epic+ only"
end

--- What the shop buys, in words, from the limits: "Epic, Omega and Legendary; above level 70 Omega and Legendary; at 100
-- Legendary only". The sell screen and the how-it-works screen both say it, so they never disagree with accepts().
function M.buysText(cfg)
  cfg = cfg or M.DEFAULTS
  local function words(list)
    local out = {}
    for _, rarity in ipairs(list or {}) do
      if rarity ~= "LEGENDARY" then out[#out + 1] = rarity:sub(1, 1) .. rarity:sub(2):lower() end
    end
    out[#out + 1] = "Legendary"
    if #out == 1 then return out[1] end
    return table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out]
  end
  local high = cfg.highLevel or M.DEFAULTS.highLevel
  local top = cfg.topLevel or M.DEFAULTS.topLevel
  return words(cfg.acceptRarities or M.DEFAULTS.acceptRarities) .. "; above level " .. high .. " "
    .. words(cfg.highRarities or M.DEFAULTS.highRarities) .. "; at " .. top .. " Legendary only"
end

--- What the shop buys as one rule a line, for the sell screen: { "Epic, Omega, Legendary", "Above level 70: Omega,
-- Legendary", "Level 100 and up: Legendary only", "Identified gear only" }.
function M.buysLines(cfg)
  cfg = cfg or M.DEFAULTS
  local function words(list)
    local out = {}
    for _, rarity in ipairs(list or {}) do
      if rarity ~= "LEGENDARY" then out[#out + 1] = rarity:sub(1, 1) .. rarity:sub(2):lower() end
    end
    out[#out + 1] = "Legendary"
    return table.concat(out, ", ")
  end
  local high = cfg.highLevel or M.DEFAULTS.highLevel
  local top = cfg.topLevel or M.DEFAULTS.topLevel
  return {
    words(cfg.acceptRarities or M.DEFAULTS.acceptRarities),
    "Above level " .. high .. ": " .. words(cfg.highRarities or M.DEFAULTS.highRarities),
    "Level " .. top .. " and up: Legendary only",
    "Identified gear only",
  }
end

--- What one accepted piece is worth in a sale for tokens, in thousandths of a token.
function M.pieceMilli(cfg)
  local per = (cfg and cfg.tokensPerPiece) or M.DEFAULTS.tokensPerPiece
  return math.max(0, math.floor(per * M.MILLI + 0.5))
end

--- The store credit n accepted pieces are worth, in thousandths of a token.
function M.creditMilli(n, cfg)
  local per = (cfg and cfg.creditPerPiece) or M.DEFAULTS.creditPerPiece
  return n * math.max(0, math.floor(per * M.MILLI + 0.5))
end

--- Whether a seller may be paid in tokens at all, or only in store credit.
function M.sellsForTokens(cfg)
  local v = cfg and cfg.sellForTokens
  if v == nil then v = M.DEFAULTS.sellForTokens end
  return v == true
end

--- The way a sale is paid: what the seller asked for, unless tokens are off, when it is store credit.
function M.saleMode(mode, cfg)
  if mode == "tokens" and M.sellsForTokens(cfg) then return "tokens" end
  return "credit"
end

--- A sale for tokens: whole tokens are paid, and the fraction is carried to the seller's next sale.
-- @return tokens number, carry number (thousandths, under 1000)
function M.settleSale(carry, n, cfg)
  local total = (carry or 0) + n * M.pieceMilli(cfg)
  local tokens = math.floor(total / M.MILLI)
  return tokens, total - tokens * M.MILLI
end

--- How much of a payout can go now without taking the owner below the floor.
function M.payable(owed, hostBalance, floor)
  if not hostBalance then return 0 end
  local room = math.floor(hostBalance - floor)
  if room <= 0 or owed <= 0 then return 0 end
  return math.min(owed, room)
end

-- ---------------------------------------------------------------- the tab

function M.tabTotal(lines)
  local total = 0
  for _, line in ipairs(lines or {}) do total = total + (line.price or 0) end
  return total
end

--- Paying a tab: store credit goes first, in whole tokens, and tokens cover the rest. Credit is never paid out.
-- @return creditTokens number, tokens number
function M.splitPayment(total, creditMilli)
  local credit = math.min(math.floor((creditMilli or 0) / M.MILLI), total)
  if credit < 0 then credit = 0 end
  return credit, total - credit
end

--- 3600 thousandths reads "3.6".
function M.showMilli(milli)
  local text = ("%.3f"):format((milli or 0) / M.MILLI)
  text = text:gsub("0+$", ""):gsub("%.$", "")
  return text
end

-- ---------------------------------------------------------------- what goes on display

--- Put pieces in the order they are shown: nearest the shopper's level first, then by key so the order
-- never changes between two looks. Each entry has .level and .key.
function M.order(list, level)
  level = tonumber(level) or 0
  table.sort(list, function(a, b)
    local da, db = math.abs((a.level or 0) - level), math.abs((b.level or 0) - level)
    if da ~= db then return da < db end
    return a.key < b.key
  end)
  return list
end

--- One page of an ordered list. A page past the end wraps to the first.
-- @return entries table, page number, pages number
function M.page(list, page, perPage)
  local pages = math.max(1, math.ceil(#list / perPage))
  page = ((math.max(1, page or 1) - 1) % pages) + 1
  local out = {}
  for i = (page - 1) * perPage + 1, math.min(#list, page * perPage) do out[#out + 1] = list[i] end
  return out, page, pages
end

--- Whether a piece is what a search asked for. query: { type, bracket, rarity, text }, each optional.
--- Whether a piece is what a kiosk search asks for. query: { type, lo, hi (levels, inclusive), rarity, legendary (only),
-- minGs, stats = { { a = attribute, min = value }, ... } (every one must be on the piece, at least min) }. bracket and text
-- are from searches saved by older versions.
function M.matches(piece, query)
  if query.type and not M.ofType(piece.type, query.type) then return false end
  if query.bracket and M.bracket(piece.level) ~= query.bracket then return false end
  if query.lo and (piece.level or 0) < query.lo then return false end
  if query.hi and (piece.level or 0) > query.hi then return false end
  if query.rarity and M.grade(piece) ~= query.rarity then return false end
  if query.legendary and not piece.legendary then return false end
  if query.minGs and (piece.gs or 0) < query.minGs then return false end
  for _, want in ipairs(query.stats or {}) do
    local have = piece.stats and piece.stats[want.a]
    if have == nil or have < (want.min or 0) then return false end
  end
  if query.text and query.text ~= "" and not piece.search:find(query.text:lower(), 1, true) then return false end
  return true
end

--- Best matches first: by Gear Score (the default), level ("level"), or one stat ("stat:<attribute>"), highest first;
-- then nearest the shopper's level, then by key so the order never changes between two looks.
-- list: { { key, level, piece }, ... }
function M.rank(list, query, level)
  level = tonumber(level) or 0
  local sort = query and query.sort or "gs"
  local stat = sort:match("^stat:(.+)$")
  local function score(e)
    local p = e.piece or {}
    if stat then return p.stats and p.stats[stat] or -math.huge end
    if sort == "level" then return p.level or 0 end
    return p.gs or -math.huge
  end
  table.sort(list, function(a, b)
    local sa, sb = score(a), score(b)
    if sa ~= sb then return sa > sb end
    local da, db = math.abs((a.level or 0) - level), math.abs((b.level or 0) - level)
    if da ~= db then return da < db end
    return a.key < b.key
  end)
  return list
end

--- IMPROVEMENTS, Phase 1 (no build logic): pieces with a better Gear Score than what the shopper wears in the same slot,
-- by at least cfg.improveMargin, from improveBelow levels under theirs up to improveAbove over it (those come last: they
-- are usable once the shopper reaches their level). Identified pieces only.
-- pieces: { piece, ... }; worn: { slot = gearScore }; slot: one slot or "any". Returns { { piece, gain, later } },
-- ordered usable-now first, biggest gain first; and counts: { slot = n } for every slot.
function M.improvements(pieces, worn, playerLevel, slot, cfg)
  cfg = cfg or M.DEFAULTS
  local level = math.floor(tonumber(playerLevel) or 0)
  local top = math.min(100, level)
  local lo = math.max(0, top - (cfg.improveBelow or M.DEFAULTS.improveBelow))
  local hi = math.min(100, level + (cfg.improveAbove or M.DEFAULTS.improveAbove))
  if level >= 100 then lo, hi = math.max(0, 100 - (cfg.improveBelow or M.DEFAULTS.improveBelow)), 100 end
  local margin = cfg.improveMargin or M.DEFAULTS.improveMargin
  local out, counts = {}, {}
  for _, p in ipairs(pieces) do
    if p.slot and p.gs and not p.unidentified and not p.broken and (p.level or 0) >= lo and (p.level or 0) <= hi then
      local gain = p.gs - (worn[p.slot] or 0)
      if gain >= margin then
        counts[p.slot] = (counts[p.slot] or 0) + 1
        if slot == "any" or slot == p.slot then
          out[#out + 1] = { piece = p, key = p.key, level = p.level, gain = gain, later = (p.level or 0) > level }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.later ~= b.later then return not a.later end
    if a.gain ~= b.gain then return a.gain > b.gain end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.key < b.key
  end)
  return out, counts
end

--- Display chests in the order they fill: nearest the shopper first. Chests with no known position come last, in their own order.
-- stations: list of { id, pos = {x,y,z}|nil }
function M.nearest(stations, pos)
  local list = {}
  for i, s in ipairs(stations) do
    local d = math.huge
    if pos and s.pos then
      local dx, dy, dz = s.pos.x - pos.x, s.pos.y - pos.y, s.pos.z - pos.z
      d = math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    list[#list + 1] = { s = s, d = d, i = i }
  end
  table.sort(list, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.i < b.i
  end)
  local out = {}
  for i, entry in ipairs(list) do out[i] = entry.s end
  return out
end

-- ---------------------------------------------------------------- wings

--- The wing called `name` (any case), or nil.
function M.category(name, cfg)
  if type(name) ~= "string" then return nil end
  for _, c in ipairs((cfg and cfg.categories) or M.DEFAULTS.categories) do
    if type(c) == "table" and type(c.name) == "string" and c.name:lower() == name:lower() then return c end
  end
  return nil
end

local function names(c, path)
  for _, t in ipairs(type(c.types) == "table" and c.types or {}) do
    if path == t or path:sub(1, #t + 1) == t .. "_" then return true end
  end
  return false
end

--- Whether a gear type ("the_vault:sword") belongs in a wing. No wing (nil, or a name no wing has) takes every type.
function M.inCategory(kind, name, cfg)
  local c = M.category(name, cfg)
  if not c then return true end
  local path = tostring(kind):match(":(.+)$") or tostring(kind)
  if not c.rest then return names(c, path) end
  for _, other in ipairs((cfg and cfg.categories) or M.DEFAULTS.categories) do
    if type(other) == "table" and not other.rest and names(other, path) then return false end
  end
  return true
end

--- Only the entries of a list of { type = ... } that belong in a wing, in the same order.
function M.inCategoryList(list, name, cfg)
  if not M.category(name, cfg) then return list end
  local out = {}
  for _, t in ipairs(list) do
    if M.inCategory(t.type, name, cfg) then out[#out + 1] = t end
  end
  return out
end

--- The wing a gear type belongs in: the first wing that names it, else the wing for the rest, else nil.
function M.wingOf(kind, cfg)
  local path = tostring(kind):match(":(.+)$") or tostring(kind)
  local rest
  for _, c in ipairs((cfg and cfg.categories) or M.DEFAULTS.categories) do
    if type(c) == "table" and type(c.name) == "string" then
      if c.rest then
        rest = rest or c.name
      elseif names(c, path) then
        return c.name
      end
    end
  end
  return rest
end

--- What the owner typed in setup as a station's gear type, as the type's id ("the_vault:sword"), or a family ("idol":
-- "the_vault:idol", every idol), or nil.
-- "sword", "Swords", "idol benevolent" and "the_vault:sword" all work. A type is known when the vault holds some
-- (known: the stock's type ids) or a wing names it; a full id with a ':' is taken as typed.
function M.gearTypeFor(text, known, cfg)
  if type(text) ~= "string" then return nil end
  local word = text:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "_")
  if word == "" then return nil end
  if word:find(":", 1, true) then return word end
  local tries = { word }
  if word:sub(-1) == "s" then tries[#tries + 1] = word:sub(1, -2) end
  if word:sub(-2) == "es" then tries[#tries + 1] = word:sub(1, -3) end
  for _, try in ipairs(tries) do
    for _, id in ipairs(known or {}) do
      local path = tostring(id):match(":(.+)$") or tostring(id)
      if path == try then return id end
    end
  end
  -- a family of types: "idol" is every idol (the_vault:idol_benevolent, ...), in stock or named by a wing
  for _, try in ipairs(tries) do
    for _, id in ipairs(known or {}) do
      local space, path = tostring(id):match("^(.-):(.+)$")
      if path and path:sub(1, #try + 1) == try .. "_" then return space .. ":" .. try end
    end
  end
  for _, try in ipairs(tries) do
    for _, c in ipairs((cfg and cfg.categories) or M.DEFAULTS.categories) do
      for _, t in ipairs(type(c) == "table" and type(c.types) == "table" and c.types or {}) do
        if t == try then return "the_vault:" .. try end
      end
    end
  end
  return nil
end

--- Whether a gear type is what a station of one type shows: the type itself, or one of its family ("the_vault:idol" is
-- every "the_vault:idol_..."), as a wing names its types.
function M.ofType(kind, want)
  if kind == nil or want == nil then return false end
  kind, want = tostring(kind), tostring(want)
  if kind == want then return true end
  return kind:sub(1, #want + 1) == want .. "_"
end

--- A station type's stock from the stock summary, its family's counts added together: { total, brackets = { b = n } },
-- or nil when there is none.
function M.typeCounts(summary, want)
  local out
  for kind, t in pairs((summary and summary.types) or {}) do
    if M.ofType(kind, want) then
      out = out or { total = 0, brackets = {} }
      out.total = out.total + (t.total or 0)
      for b, n in pairs(t.brackets or {}) do out.brackets[b] = (out.brackets[b] or 0) + n end
    end
  end
  return out
end

--- A type's name for a station's title: "Swords", "Leggings", "Idol Benevolent".
function M.typePlural(kind)
  local label = M.typeLabel(kind)
  if label:find(" ", 1, true) or label:sub(-1):lower() == "s" then return label end
  if label:sub(-2):lower() == "sh" or label:sub(-2):lower() == "ch" or label:sub(-1):lower() == "x" then return label .. "es" end
  return label .. "s"
end

function M.distance(a, b)
  if not a or not b then return nil end
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The bracket to show when the wanted one has nothing of a type: the nearest one that has, lower first.
-- counts: { [bracket] = n }
function M.nearestBracket(counts, wanted)
  for step = 0, 10 do
    for _, b in ipairs({ wanted - step, wanted + step }) do
      if b >= 0 and b <= 10 and (counts[b] or 0) > 0 then return b end
    end
  end
  return nil
end

return M
