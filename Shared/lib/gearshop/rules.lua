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
  pricePerBracket = 2,      -- a 10-level bracket costs this much more than the one below: 1-9 is 2, 40-49 is 10, 100 is 22
  piecesPerToken = 10,      -- a seller gets one token for this many accepted pieces
  creditMultiplier = 4,     -- store credit pays this many times the tokens
  ownerFloor = 1000,        -- a token payout never takes the owner's balance below this
  sellForTokens = false,    -- off: selling to the shop pays store credit only, so the shop never pays tokens out for gear.
                            -- Anything already owed from an earlier token sale is still paid. On: sellers pick tokens or credit.
  acceptRarities = { "EPIC", "OMEGA" },  -- bought from players, besides anything legendary
  highLevel = 70,           -- above this level only OMEGA and legendary pieces are bought
  highRarities = { "OMEGA" },
  topLevel = 100,           -- from this level only legendary pieces are bought
  sellTypes = { "Gear" },   -- the vaultData.itemType values the shop puts on display
  chestsPerShopper = 6,     -- display chests filled for one shopper when they check in
  defaultLevel = 0,         -- the level used for a shopper whose vault level cannot be read
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
  -- other wing names. A chest with no wing shows any type, as before there were wings.
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

--- What everything in a bracket costs. The same for every rarity.
function M.bracketPrice(b, cfg)
  return ((cfg and cfg.pricePerBracket) or M.DEFAULTS.pricePerBracket) * (b + 1)
end

function M.price(level, cfg)
  return M.bracketPrice(M.bracket(level), cfg)
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
  }
  piece.search = (piece.label .. " " .. table.concat(words, " ")):lower()
  return piece
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

--- What one accepted piece is worth, in thousandths of a token.
function M.pieceMilli(cfg)
  return math.floor(M.MILLI / math.max(1, (cfg and cfg.piecesPerToken) or M.DEFAULTS.piecesPerToken) + 0.5)
end

function M.creditMilli(n, cfg)
  return n * M.pieceMilli(cfg) * ((cfg and cfg.creditMultiplier) or M.DEFAULTS.creditMultiplier)
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
function M.matches(piece, query)
  if query.type and piece.type ~= query.type then return false end
  if query.bracket and M.bracket(piece.level) ~= query.bracket then return false end
  if query.rarity and M.grade(piece) ~= query.rarity then return false end
  if query.text and query.text ~= "" and not piece.search:find(query.text:lower(), 1, true) then return false end
  return true
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

--- Which display chests a shopper gets when they check in, and in what order they are filled.
-- stations: free chests nearest the shopper first, each { category = name|nil }; hasStock(category) says whether a wing
-- has anything to show. First the nearest chest of every wing that has stock (chests with no wing count as one wing of
-- their own), so a shopper finds something in each wing of a big district; then the nearest of the rest. Returns the
-- chosen chests, nearest first, at most `count`.
function M.spread(stations, count, hasStock)
  local chosen, taken, seen = {}, {}, {}
  for i, s in ipairs(stations) do
    if #chosen >= count then break end
    local key = s.category or ""
    if not seen[key] then
      seen[key] = true
      if hasStock(s.category) then
        chosen[#chosen + 1] = i
        taken[i] = true
      end
    end
  end
  for i, s in ipairs(stations) do
    if #chosen >= count then break end
    if not taken[i] and hasStock(s.category) then
      chosen[#chosen + 1] = i
      taken[i] = true
    end
  end
  table.sort(chosen)
  local out = {}
  for k, i in ipairs(chosen) do out[k] = stations[i] end
  return out
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
