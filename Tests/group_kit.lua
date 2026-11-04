-- group_kit.lua
-- What a group game's tests lean on. kit.plugin loads a game the way its cabinet does, and kit.fuzz plays it at random, checking the
-- whole contract in Games/BigTable/games/README.md at every step. A game's own test adds its odds and its paytable on top.

local testing = require("testing")

local kit = {}

local function rootOf()
  for part in package.path:gmatch("[^;]+") do
    local root = part:match("^(.*)[/\\]Tests[/\\]%?%.lua$")
    if root then return root end
  end
  return "."
end

local function forget()
  for name in pairs(package.loaded) do
    if name:find("^games%.") then package.loaded[name] = nil end
  end
end

--- A game by cabinet and id. Both cabinets have a games.holdem, so each load gets its own cabinet's files.
function kit.plugin(cabinet, id)
  local saved = package.path
  package.path = rootOf() .. "/Games/" .. cabinet .. "/?.lua;" .. saved
  forget()
  local ok, plugin = pcall(require, "games." .. id .. ".plugin")
  package.path = saved
  forget()
  if not ok then error("could not load " .. cabinet .. " " .. id .. ": " .. tostring(plugin), 2) end
  return plugin
end

--- A deep copy that refuses anything a journal could not keep.
local function plain(value, path, seen)
  local kind = type(value)
  if kind == "function" or kind == "userdata" or kind == "thread" then error(path .. " holds a " .. kind, 0) end
  if kind ~= "table" then return value end
  if seen[value] then error(path .. " is a cycle", 0) end
  if getmetatable(value) then error(path .. " has a metatable", 0) end
  seen[value] = true
  local copy = {}
  for key, item in pairs(value) do
    if type(key) ~= "string" and type(key) ~= "number" then error(path .. " has a key of type " .. type(key), 0) end
    copy[key] = plain(item, path .. "." .. tostring(key), seen)
  end
  seen[value] = nil
  return copy
end
kit.plain = function(value, what) return plain(value, what or "value", {}) end

--- Whether two plain values are the same.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for key, item in pairs(a) do
    if not same(item, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end
kit.same = same

local function contains(view, needle, seen)
  if view == needle then return true end
  if type(view) ~= "table" or seen[view] then return false end
  seen[view] = true
  for _, item in pairs(view) do
    if contains(item, needle, seen) then return true end
  end
  return false
end

--- Whether a value appears anywhere in a view. How a game's test proves a hidden card stays hidden.
function kit.shows(view, value)
  return contains(view, value, {})
end

--- Entries for a round. seats says which seat numbers, opts.stack or opts.bet what each brings.
function kit.entries(plugin, seats, opts)
  opts = opts or {}
  local entries = {}
  for index = 1, seats do
    local entry = { seat = index, name = "P" .. index }
    if plugin.kind == "house" then
      entry.bet = opts.bet or plugin.minBet or 10
      if opts.bets then entry.bets = kit.plain(opts.bets) end
    else
      entry.stack = opts.stack or plugin.maxStack or 1000
      entry.stake = opts.stake
    end
    entries[index] = entry
  end
  return entries
end

local function listOf(value, what)
  if type(value) ~= "table" then error(what .. " must be a list", 0) end
  for key in pairs(value) do
    if type(key) ~= "number" then error(what .. " must be a list, not a map", 0) end
  end
  return value
end

--- Everything a seat could be offered now is well formed.
local function checkActions(actions, seat)
  for _, action in ipairs(listOf(actions, "actions")) do
    if type(action.id) ~= "string" or action.id == "" then error("seat " .. seat .. " has an action with no id", 0) end
    if action.label == nil then error("action " .. action.id .. " has no label", 0) end
    if action.cost ~= nil and (type(action.cost) ~= "number" or action.cost < 0) then error("action " .. action.id .. " has a bad cost", 0) end
    if action.value ~= nil and type(action.value) == "table" then error("action " .. action.id .. " has a table for a value", 0) end
  end
end

--- A random legal press for a seat, or the game's safe default when pick says so.
local function press(rules, state, seat, rng, pick)
  local actions = rules.actions(state, seat)
  if pick then
    local id, value = pick(state, seat, actions, rng)
    if id then return id, value end
  end
  local list = {}
  for _, action in ipairs(actions) do
    if not action.disabled then list[#list + 1] = action end
  end
  if #list == 0 then return rules.auto(state, seat) end
  local action = list[rng:below(#list) + 1]
  return action.id, action.value
end

--- Play one round from start to finish. Returns the state and its entries.
function kit.playRound(plugin, opts)
  opts = opts or {}
  local rules = plugin.rules
  local rng = opts.rng or testing.fastRng(opts.seed or 1)
  local entries = kit.plain(opts.entries or kit.entries(plugin, opts.seats or plugin.minSeats or 2, opts))
  local keep = opts.keep or {}
  local state, events = rules.new(entries, opts.button or 1, rng, keep)
  listOf(events, "new's events")
  kit.plain(keep, "keep")
  local steps, limit = 0, opts.steps or 20000
  while not rules.done(state) do
    steps = steps + 1
    if steps > limit then error("the round never ended", 0) end
    -- A long round (a whole board game) must still let CC breathe
    if steps % 100 == 0 then testing.breathe() end
    -- A reboot lands anywhere: a state must come back whole
    state = kit.plain(state, "state")
    if opts.check then opts.check(state, entries) end
    local before = kit.plain(state, "state")
    local waiting = listOf(rules.waitingOn(state), "waitingOn")
    local public = kit.plain(rules.viewFor(state, nil), "the public view")
    if not same(public, rules.viewFor(state, nil)) then error("viewFor is not pure", 0) end
    for _, entry in ipairs(entries) do
      kit.plain(rules.viewFor(state, entry.seat), "seat " .. entry.seat .. "'s view")
      checkActions(rules.actions(state, entry.seat), entry.seat)
    end
    if not same(before, state) then error("a view or the action list changed the state", 0) end

    -- Illegal input does nothing
    local wrong = rules.act(state, waiting[1] or (entries[1] and entries[1].seat), "no_such_action", nil, rng)
    if wrong and #wrong > 0 then error("an unknown action returned events", 0) end
    if not same(before, state) then error("an unknown action changed the state", 0) end

    if #waiting == 0 then
      local id, value = rules.auto(state, nil)
      local moved = rules.act(state, nil, id, value, rng)
      if not moved or #moved == 0 then error("the game waits on nobody and the computer's move did nothing", 0) end
    else
      local seat = waiting[rng:below(#waiting) + 1]
      local timedOut = opts.absent and rng:below(100) < opts.absent
      local id, value
      if timedOut then id, value = rules.auto(state, seat) else id, value = press(rules, state, seat, rng, opts.pick) end
      local moved = rules.act(state, seat, id, value, rng)
      if not moved or #moved == 0 then
        if timedOut then error("auto's move for seat " .. seat .. " did nothing: " .. tostring(id), 0) end
        error("a move the game offered did nothing: " .. tostring(id) .. " for seat " .. seat, 0)
      end
      listOf(moved, "act's events")
    end
  end
  return state, entries
end

--- The money at the end of a round, against the contract.
function kit.checkEnd(plugin, state, entries)
  local rules = plugin.rules
  local nets = rules.nets(state)
  local total = 0
  for _, entry in ipairs(entries) do
    local net = nets[entry.seat] or 0
    if net ~= math.floor(net) then error("seat " .. entry.seat .. "'s net is not whole: " .. net, 0) end
    total = total + net
    if plugin.kind == "players" and net < -entry.stack then
      error("seat " .. entry.seat .. " lost " .. -net .. " on a stack of " .. entry.stack, 0)
    end
    if plugin.kind == "house" and net > rules.maxWin(entry) then
      error("seat " .. entry.seat .. " won " .. net .. " past maxWin " .. rules.maxWin(entry), 0)
    end
    local result = rules.result(state, entry.seat)
    if type(result) ~= "table" or type(result.title) ~= "string" or type(result.kind) ~= "string" then
      error("seat " .. entry.seat .. "'s result is not { kind, title, detail }", 0)
    end
  end
  if plugin.kind == "players" and total ~= -(state.kept or 0) then error("nets add up to " .. total, 0) end
  local shared = rules.result(state, nil)
  if type(shared) ~= "table" or type(shared.title) ~= "string" then error("result(state, nil) is the table's line and must be a result", 0) end
  return nets
end

--- Random rounds through the whole contract. opts: rounds, seats (a list to choose from), absent (percent of turns timed out), pick,
-- check, stack, bet, bets, stake. Returns the total net by seat kind, for a game's own sums.
function kit.fuzz(plugin, opts)
  opts = opts or {}
  local rounds = opts.rounds or 300
  local rng = testing.fastRng(opts.seed or 12345)
  local keep = {}
  local seats = opts.seats or { plugin.minSeats or 2, plugin.maxSeats or 2 }
  for round = 1, rounds do
    local count = seats[rng:below(#seats) + 1]
    local options = {}
    for key, value in pairs(opts) do options[key] = value end
    options.rng, options.keep, options.seats, options.seed = rng, keep, count, nil
    options.button = rng:below(count) + 1
    local ok, state, entries = pcall(kit.playRound, plugin, options)
    if not ok then error("round " .. round .. ": " .. tostring(state), 2) end
    local good, err = pcall(kit.checkEnd, plugin, state, entries)
    if not good then error("round " .. round .. ": " .. tostring(err), 2) end
    if plugin.rules.finish then plugin.rules.finish(state, keep) end
    kit.plain(keep, "keep")
    if round % 50 == 0 then testing.breathe() end
  end
end

return kit
