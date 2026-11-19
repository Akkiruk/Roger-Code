-- gearshop/app.lua
-- The shop's computer. Two coroutines:
--   the screen  takes every event (touches, chest changes, keys), never calls anything that waits for the server, draws the
--               monitors and the owner's terminal, and turns what happens into jobs
--   the worker  does the jobs one at a time through shop.lua: every inventory, detector and money call lives there
-- Inventory, detector and money calls lose every event that arrives while they wait, which is why they are kept apart: a
-- touch during a fill still reaches the screen.
--
-- The owner's terminal has five pages (keys 1-5): status, stock, players, limits and setup. Setup finds the other computers,
-- links them, and has the owner show which peripheral is which: tap a monitor, drop an item in a chest, stand at a detector.

local rules = require("lib.gearshop.rules")
local store = require("lib.gearshop.store")
local shopLib = require("lib.gearshop.shop")
local ui = require("lib.gearshop.ui")
local builds = require("lib.gearshop.builds")
local journal = require("lib.casino.journal")
local wallet = require("lib.casino.wallet")

local M = {}

M.PROTOCOL = "gearshop.v1"
local TICK = 0.5
local DEBUG_FLAG, DEBUG_FILE, BOOTS_FILE = "gearshop_debug.flag", "gearshop_ui.dat", "gearshop_boots.dat"

-- ---------------------------------------------------------------- peripherals, never throwing

local io = {}

function io.isPresent(name)
  local ok, present = pcall(peripheral.isPresent, name)
  return ok and present == true
end

--- ok, results...  A peripheral that is not there (its computer unloaded) is a plain failure.
function io.call(name, method, ...)
  if type(name) ~= "string" or not io.isPresent(name) then return false, "not attached" end
  return pcall(peripheral.call, name, method, ...)
end

function io.names()
  local ok, names = pcall(peripheral.getNames)
  return ok and names or {}
end

function io.types(name)
  local result = table.pack(pcall(peripheral.getType, name))
  local out = {}
  if result[1] then
    for i = 2, result.n do
      if type(result[i]) == "string" then out[#out + 1] = result[i] end
    end
  end
  return out
end

function io.hasType(name, kind)
  for _, t in ipairs(io.types(name)) do
    if t == kind then return true end
  end
  return false
end

--- The methods a peripheral has, or nil when it is not there (vhcctweaks 2.2.37 inventories add identify and the rest).
function io.methods(name)
  if type(name) ~= "string" or not io.isPresent(name) then return nil end
  local ok, methods = pcall(peripheral.getMethods, name)
  return ok and type(methods) == "table" and methods or nil
end

M.io = io

-- ---------------------------------------------------------------- first boot: shop or node

local function askRole()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("GEAR SHOP")
  print("")
  print("What is this computer?")
  print("")
  print(" 1  The shop: runs everything. One of these.")
  print(" 2  A node: only lends its chests, monitors")
  print("    and detectors to the shop computer.")
  print("")
  print("Both need an ender modem. Press 1 or 2.")
  while true do
    local _, ch = os.pullEvent("char")
    if ch == "1" or ch == "2" then
      local role = ch == "1" and "shop" or "node"
      store.saveRole(role)
      return role
    end
  end
end

-- ---------------------------------------------------------------- the shop computer

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function runShop()
  local cfg, setup, state = store.loadConfig(), store.loadSetup(), store.loadState()
  local shop = shopLib.new(io, cfg, setup, state)
  local debug = fs.exists(DEBUG_FLAG)
  -- for the test suites: how many times this computer has started, so a dump from before a restart is not taken for a new one
  local boots = 0
  if debug then
    local h = fs.exists(BOOTS_FILE) and fs.open(BOOTS_FILE, "r")
    if h then
      boots = tonumber(h.readAll()) or 0
      h.close()
    end
    boots = boots + 1
    h = fs.open(BOOTS_FILE, "w")
    if h then
      h.write(tostring(boots))
      h.close()
    end
  end

  -- ---- jobs
  local jobs, queued = {}, {}
  local function post(key, fn)
    if key then
      if queued[key] then return end
      queued[key] = true
    end
    jobs[#jobs + 1] = { key = key, fn = fn }
    os.queueEvent("gs_job")
  end
  --- A job that goes ahead of every other waiting: one that must happen while a player's tap is still fresh.
  local function postFirst(key, fn)
    if queued[key] then return end
    queued[key] = true
    table.insert(jobs, 1, { key = key, fn = fn })
    os.queueEvent("gs_job")
  end

  local function worker()
    local ok, err = pcall(function() shop:boot() end)
    if not ok then
      store.log("boot: " .. tostring(err))
      shop.trouble = "Starting failed: " .. tostring(err)
      shop.ready = true
      shop.status = "Open"
    end
    os.queueEvent("gs_draw")
    while true do
      while #jobs > 0 do
        local job = table.remove(jobs, 1)
        if job.key then queued[job.key] = nil end
        local fine, why = pcall(job.fn)
        if not fine then
          if why == "Terminated" then error(why, 0) end
          store.log("job " .. tostring(job.key) .. ": " .. tostring(why))
        end
        os.queueEvent("gs_draw")
      end
      os.pullEvent()
    end
  end

  -- ---- monitors
  local screens, views = {}, {}
  local function screenOf(name)
    if not io.isPresent(name) then
      screens[name] = nil
      return nil
    end
    if not screens[name] then
      local role = shop.monitorRole[name]
      if role and role.role == "info" then
        -- the help screen reads best at scale 1 on its 4x4 monitor (39 columns); a smaller one goes to 0.5
        local s = ui.screen(io, name, 1)
        if s.w > 0 and s.w < ui.INFO_MIN_WIDTH then
          io.call(name, "setTextScale", 0.5)
          s:measure()
        end
        screens[name] = s
      else
        screens[name] = ui.screen(io, name, cfg.textScale)
      end
    end
    if screens[name].w == 0 and not screens[name]:measure() then return nil end
    return screens[name]
  end
  local function viewOf(name)
    views[name] = views[name] or {}
    return views[name]
  end
  -- The monitors the shop can reach that have no job: worked out again when peripherals come or go. Asking every
  -- peripheral its type is a call that can wait on a linked computer, so the worker does it (screen coroutine: never).
  -- spareGen counts the changes: a list worked out while peripherals were still coming (a node being linked) is worked
  -- out again, not kept.
  local spare, spareList, spareAsked, spareGen = nil, {}, false, 0
  local function spareMonitors()
    if not spare and not spareAsked then
      spareAsked = true
      local gen = spareGen
      post("spare", function()
        local list = {}
        for _, name in ipairs(io.names()) do
          if not shop.monitorRole[name] and io.hasType(name, "monitor") then list[#list + 1] = name end
        end
        spareList, spareAsked = list, false
        spare = gen == spareGen or nil
        os.queueEvent("gs_draw")
      end)
    end
    return spareList
  end
  local function spareChanged()
    spare, spareGen = nil, spareGen + 1
  end

  local function drawMonitors()
    local dump = debug and { ready = shop.ready, status = shop.status, version = shop.version, boot = boots, monitors = {}, spare = {} } or nil
    -- a monitor with no job says so, so nothing older (the installer's update screen) lingers on it
    for _, name in ipairs(spareMonitors()) do
      local s = screenOf(name)
      if s then
        local ok, err = pcall(ui.idle, s)
        if not ok then store.log("drawing " .. name .. ": " .. tostring(err)) end
        if dump then dump.spare[name] = s.text end
      end
    end
    for name, role in pairs(shop.monitorRole) do
      local s = screenOf(name)
      if s then
        local ok, err = pcall(function()
          if role.role == "door" then
            ui.door(s, shop)
          elseif role.role == "station" then
            ui.station(s, shop, role.d, viewOf(name))
          elseif role.role == "kiosk" then
            ui.kiosk(s, shop, role.d, viewOf(name))
          elseif role.role == "sell" then
            ui.sell(s, shop)
          elseif role.role == "info" then
            ui.info(s, shop, viewOf(name))
          end
        end)
        if not ok then store.log("drawing " .. name .. ": " .. tostring(err)) end
        if dump then
          dump.monitors[name] = { role = role.role, id = role.d and role.d.id, w = s.w, h = s.h, buttons = s.buttons, lines = s.text }
        end
      end
    end
    if dump then
      dump.shoppers, dump.tabs, dump.credit, dump.carry = state.shoppers, state.tabs, state.credit, state.carry
      dump.displays, dump.stats, dump.owed = state.displays, state.stats, journal.owed()
      dump.returnsBy, dump.moving = state.returnsBy, state.moving
      dump.stock = shop.ready and shop.stock:summary() or nil
      dump.trouble, dump.linkTrouble, dump.watches = shop.trouble, shop.linkTrouble, shop.watches
      dump.sale, dump.payment, dump.payout = state.sale, state.payment, state.payout
      dump.paid, dump.refunds, dump.collecting, dump.paying = state.paid, state.refunds, state.collecting, state.paying
      dump.unpack, dump.unpackFailed = state.unpack, state.unpackFailed
      local ok, text = pcall(textutils.serializeJSON, dump)
      if ok then
        local h = fs.open(DEBUG_FILE .. ".tmp", "w")
        if h then
          h.write(text)
          h.close()
          pcall(fs.delete, DEBUG_FILE)
          pcall(fs.move, DEBUG_FILE .. ".tmp", DEBUG_FILE)
        end
      end
    end
  end

  -- ---- the owner's terminal
  local admin = { page = (#setup.stations == 0 and not setup.door) and 5 or 1, scroll = 0, sel = 1, draft = copy(setup), dirty = true }
  local PAGES = { "STATUS", "STOCK", "PLAYERS", "LIMITS", "SETUP" }
  local tw, th = term.getSize()

  local function say(text)
    admin.msg = text
    admin.dirty = true
  end

  local function limitKeys()
    local list = {}
    for key, default in pairs(rules.DEFAULTS) do
      if type(default) ~= "table" then list[#list + 1] = key end
    end
    table.sort(list)
    return list
  end

  local function assigned(name)
    local d = admin.draft
    local function used(role)
      return role and (role.monitor == name or role.chest == name or role.detector == name)
    end
    if used(d.door) or used(d.sell) or used(d.kiosk) or used(d.intake) or used(d.returns) or used(d.junk) or used(d.info) then
      return true
    end
    if d.unpack and (d.unpack.router == name or d.unpack.integrator == name) then return true end
    for _, s in ipairs(d.stations) do
      if used(s) then return true end
    end
    return false
  end

  local function count(kind)
    local n = 0
    for _, name in ipairs(io.names()) do
      if io.hasType(name, kind) then n = n + 1 end
    end
    return n
  end

  local function describe(role, fields)
    if not role then return "not set" end
    local parts = {}
    for _, field in ipairs(fields) do parts[#parts + 1] = role[field] or "-" end
    return table.concat(parts, " / ")
  end

  local function drawAdmin()
    if not admin.dirty then return end
    admin.dirty = false
    term.setBackgroundColor(colors.black)
    term.clear()
    local y = 1
    local function line(text, color)
      if y > th then return end
      term.setCursorPos(1, y)
      term.setTextColor(color or colors.white)
      term.write(tostring(text):sub(1, tw))
      y = y + 1
    end
    local tabs = {}
    for i, name in ipairs(PAGES) do tabs[#tabs + 1] = (i == admin.page and "[" or " ") .. i .. " " .. name .. (i == admin.page and "]" or " ") end
    line(table.concat(tabs, ""), colors.yellow)

    if admin.wizard then
      local w = admin.wizard
      local step = w.steps[w.at]
      line("")
      line(w.title .. "  (step " .. w.at .. " of " .. #w.steps .. ")", colors.lime)
      line("")
      if step.kind == "monitor" then
        line("Tap the monitor of " .. w.what .. ".")
        if step.optional then line(step.hint or "No monitor yet? S skips it: M sets it later.") end
      elseif step.kind == "chest" then
        line("Put any item into the chest of " .. w.what)
        line("(or take one out). Watching " .. (step.watching or 0) .. " chests.")
        if (step.slow or 0) > 0 then
          -- a Sophisticated barrel or chest is looked at a few at a time: it can take some seconds to be seen
          line("And " .. step.slow .. " Sophisticated: give those a few seconds.")
        end
      elseif step.kind == "stand" then
        if step.text then
          -- a display station: its own monitor need not be up yet, any monitor of the shop will do
          line(step.text)
          line("any shop monitor, or press Enter here.")
        else
          line("Stand at " .. w.what .. ".")
        end
        if step.detector then
          line("Its own detector is optional: if it has")
          line("one, stand nearer it than any other.")
        end
        if not step.text then
          line("Then tap any shop monitor there, or press")
          line("Enter here.")
        end
      end
      line("")
      line("T type its name   " .. (step.optional and "S skip   " or "") .. "Q cancel", colors.lightGray)
    elseif admin.page == 1 then
      line("Shop: " .. shop.status .. (shop.trouble and ("  ! " .. shop.trouble) or ""), shop.ready and colors.lime or colors.orange)
      if shop.linkTrouble then line("Link: " .. shop.linkTrouble, colors.orange) end
      local summary = shop.ready and shop.stock:summary() or { total = 0, forSale = 0, chests = 0, used = 0, slots = 0, unread = 0 }
      line(("Stock: %d pieces (%d for sale) in %d chests"):format(summary.total, summary.forSale, summary.chests))
      line(("Room: %d/%d slots, %d unread, %d watched"):format(summary.used, summary.slots, summary.unread, shop.watches))
      line("Owner balance: " .. tostring(admin.hostBalance or "?") .. "   floor " .. cfg.ownerFloor)
      line("Sellers are paid: " .. (rules.sellsForTokens(cfg) and "tokens or store credit" or "store credit only"))
      local stats = state.stats
      line(("Sold %d pieces: %d tokens, %d store credit"):format(stats.sold, stats.takings, stats.creditSpent))
      line(("Bought %d pieces: %d tokens paid, %s credit given"):format(stats.bought, stats.paidOut, rules.showMilli(stats.creditGiven)))
      if stats.unaccounted > 0 then line("Pieces gone with nobody to charge: " .. stats.unaccounted, colors.orange) end
      line("")
      line("Checked in:", colors.lightGray)
      local any = false
      for name, shopper in pairs(state.shoppers) do
        any = true
        local chests = {}
        for _, d in ipairs(shop.all) do
          if shop:ds(d).shopper == name then chests[#chests + 1] = d.id end
        end
        line((" %s  level %d  owes %d  chests %s"):format(name, shopper.level or 0, shop:owes(name), table.concat(chests, ",")))
      end
      if not any then line(" nobody") end
    elseif admin.page == 2 then
      local summary = shop.ready and shop.stock:summary() or nil
      if not summary then
        line(shop.status .. "...")
      else
        line(("%d pieces for sale, by type and level bracket:"):format(summary.forSale), colors.lightGray)
        local rows = th - 3
        admin.scroll = math.max(0, math.min(admin.scroll, math.max(0, #summary.typeList - rows)))
        for i = 1 + admin.scroll, math.min(#summary.typeList, admin.scroll + rows) do
          local t = summary.types[summary.typeList[i]]
          local parts = {}
          for b = 0, 10 do
            if t.brackets[b] then parts[#parts + 1] = (b == 10 and "100" or tostring(b * 10)) .. ":" .. t.brackets[b] end
          end
          line(("%-12s %5d  %s"):format(rules.typeLabel(t.type):sub(1, 12), t.total, table.concat(parts, " ")))
        end
        line("Up/Down scroll", colors.lightGray)
      end
    elseif admin.page == 3 then
      local names, seen = {}, {}
      local owed = journal.owed()
      for _, source in ipairs({ state.tabs, state.credit, state.carry, owed, state.shoppers }) do
        for name in pairs(source) do
          if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
          end
        end
      end
      table.sort(names)
      line(("%-16s %5s %6s %8s %6s"):format("player", "tab", "owed", "credit", "carry"), colors.lightGray)
      -- who left refused gear in the returns chest: a record only, nothing is held back
      local left, leftNames = {}, {}
      for _, by in pairs(state.returnsBy or {}) do
        if not left[by] then leftNames[#leftNames + 1] = by end
        left[by] = (left[by] or 0) + 1
      end
      table.sort(leftNames)
      local rows = th - 3 - (#leftNames > 0 and 1 or 0)
      admin.scroll = math.max(0, math.min(admin.scroll, math.max(0, #names - rows)))
      for i = 1 + admin.scroll, math.min(#names, admin.scroll + rows) do
        local name = names[i]
        line(("%-16s %5d %6d %8s %6s"):format(name:sub(1, 16), rules.tabTotal(state.tabs[name]), owed[name] or 0,
          rules.showMilli(state.credit[name] or 0), rules.showMilli(state.carry[name] or 0)))
      end
      if #leftNames > 0 then
        local parts = {}
        for _, by in ipairs(leftNames) do parts[#parts + 1] = (by == "?" and "someone" or by) .. " " .. left[by] end
        line("In returns: " .. table.concat(parts, ", "), colors.orange)
      end
      line("owed: + the shop owes them, - they owe", colors.lightGray)
    elseif admin.page == 4 and admin.bw then
      -- the IMPROVEMENTS build weights: a list of builds, then one build's weights
      local bw = admin.bw
      local all = builds.all(cfg.buildWeights)
      local mine = type(cfg.buildWeights) == "table" and cfg.buildWeights or {}
      local list, rows = {}, th - 4
      if bw.build then
        local defaults = builds.defaults()[bw.build]
        line("BUILD WEIGHTS: " .. all[bw.build].label, colors.yellow)
        for _, a in ipairs(builds.attributes()) do list[#list + 1] = a end
        bw.sel = math.max(1, math.min(bw.sel, #list))
        if bw.sel <= bw.scroll then bw.scroll = bw.sel - 1 end
        if bw.sel > bw.scroll + rows then bw.scroll = bw.sel - rows end
        for i = 1 + bw.scroll, math.min(#list, bw.scroll + rows) do
          local a = list[i]
          local own = mine[bw.build] and mine[bw.build][a]
          local text = ("%-26s %4s"):format(a:sub(1, 26), tostring(builds.weight(all[bw.build], a)))
            .. (own ~= nil and ("  (default " .. tostring(defaults[a] or 0) .. ")") or "")
          line((i == bw.sel and "> " or "  ") .. text, i == bw.sel and colors.lime or (own ~= nil and colors.orange or colors.white))
        end
        line("Enter change (0-3), D default, Q back", colors.lightGray)
      else
        line("BUILD WEIGHTS: which build?", colors.yellow)
        bw.sel = math.max(1, math.min(bw.sel, #builds.ORDER))
        for i, id in ipairs(builds.ORDER) do
          local changed = 0
          for _ in pairs(mine[id] or {}) do changed = changed + 1 end
          line((i == bw.sel and "> " or "  ") .. ("%-10s %s"):format(id, all[id].label)
            .. (changed > 0 and ("  " .. changed .. " changed") or ""), i == bw.sel and colors.lime or colors.white)
        end
        line("Up/Down pick, Enter open, Q back", colors.lightGray)
      end
    elseif admin.page == 4 then
      local list = limitKeys()
      local rows = th - 4
      admin.sel = math.max(1, math.min(admin.sel, #list))
      if admin.sel <= admin.scroll then admin.scroll = admin.sel - 1 end
      if admin.sel > admin.scroll + rows then admin.scroll = admin.sel - rows end
      for i = 1 + admin.scroll, math.min(#list, admin.scroll + rows) do
        local key = list[i]
        line((i == admin.sel and "> " or "  ") .. ("%-22s %s"):format(key, tostring(cfg[key])), i == admin.sel and colors.lime or colors.white)
      end
      line("Up/Down pick, Enter change, D default, B build weights", colors.lightGray)
      line("V what we buy: " .. rules.bandsText(cfg) .. " (legendary roll)", colors.lightGray)
    elseif admin.page == 5 then
      local d = admin.draft
      local ids = {}
      for _, id in ipairs(d.nodes) do ids[#ids + 1] = tostring(id) .. (shop.linked[id] and "" or "?") end
      -- as many as fit on the line, then how many more
      local nodes, shown = "Nodes (" .. #ids .. "):", 0
      for i, id in ipairs(ids) do
        local more = #ids - i
        local tail = more > 0 and (" +" .. more) or ""
        if #nodes + 1 + #id + #tail > tw then break end
        nodes, shown = nodes .. " " .. id, i
      end
      if shown < #ids then nodes = nodes .. " +" .. (#ids - shown) end
      line(#ids > 0 and nodes or "Nodes: none")
      line("F find nodes   N add one   X drop the last", colors.lightGray)
      line(("Seen: %d inventories, %d monitors, %d detectors"):format(count("inventory"), count("monitor"), count("playerDetector")), colors.lightGray)
      line("D door    " .. describe(d.door, { "monitor", "detector" }) .. (d.door and "" or " (optional)"))
      line("S sell    " .. describe(d.sell, { "monitor", "chest" }))
      line("K kiosk   " .. describe(d.kiosk, { "monitor", "chest" }))
      line("I intake  " .. describe(d.intake, { "chest" }))
      line("U returns " .. describe(d.returns, { "chest" }))
      line("J junk    " .. describe(d.junk, { "chest" }))
      line("H info    " .. describe(d.info, { "monitor" }) .. (d.info and "" or " (the how-it-works screen)"))
      line("P unpack  " .. (d.unpack and (tostring(d.unpack.router) .. " / " .. tostring(d.unpack.integrator) .. " " .. tostring(d.unpack.side))
        or "not set (backpacks at the sell point)"))
      line("A add a display station  R drop the last  (" .. #d.stations .. " set)")
      line("G a station's gear type or wing   M its monitor", colors.lightGray)
      local rows = th - y - 2
      for i = math.max(1, #d.stations - rows + 1), #d.stations do
        local s = d.stations[i]
        local what = s.gearType and ("  " .. rules.typePlural(s.gearType)) or (s.category and ("  " .. s.category) or "")
        line((" %d %s / %s / %s%s"):format(i, s.monitor or "-", s.chest or "-", s.detector or "-", what), colors.lightGray)
      end
      y = th - 1
      line("V add a vault chest by name (" .. #d.vault .. ")   C clear all")
      line("W write this and restart the shop", colors.lime)
    end
    if admin.input then
      term.setCursorPos(1, th)
      term.setTextColor(colors.yellow)
      term.clearLine()
      term.write((admin.input.prompt .. admin.input.text .. "_"):sub(-tw))
    elseif admin.msg then
      term.setCursorPos(1, th)
      term.setTextColor(colors.orange)
      term.clearLine()
      term.write(admin.msg:sub(1, tw))
    end
  end

  local function ask(prompt, done)
    admin.input = { prompt = prompt, text = "", done = done }
    admin.dirty = true
  end

  -- ---- setup: showing the shop which peripheral is which
  local function wizardNext(w)
    w.at = w.at + 1
    admin.dirty = true
    if w.at > #w.steps then
      admin.wizard = nil
      w.done(w.result)
      return
    end
    local step = w.steps[w.at]
    if step.kind == "chest" then
      -- The worker watches every chest that has no job yet and is not a vault chest, until one changes. A step that may
      -- be a Sophisticated block (the returns, junk or intake container: a netherite barrel is the usual returns one)
      -- watches the unassigned Sophisticated storage too, which is otherwise all vault: a few of those at a time, as a
      -- shop has a hundred or more. Nothing else moves items meanwhile (this is the worker's only job), so a change is
      -- the owner's. The container the step is redoing counts as free, so the owner can show the same one again.
      post(nil, function()
        local names, base, slow = {}, {}, {}
        local function print_(name)
          local ok, list = io.call(name, "list")
          if not ok or type(list) ~= "table" then return nil end
          local parts = {}
          for slot, item in pairs(list) do parts[#parts + 1] = slot .. ":" .. rules.key(item) .. "x" .. tostring(item.count) end
          table.sort(parts)
          return table.concat(parts, ",")
        end
        for _, name in ipairs(io.names()) do
          if io.hasType(name, "inventory") and (not assigned(name) or name == step.current) then
            if not shop:isVaultChest(name) then
              names[#names + 1] = name
              base[name] = print_(name)
            elseif step.vaultToo then
              slow[#slow + 1] = name
            end
          end
        end
        -- every one is read once before the step says it is watching, so an item dropped from then on is seen
        for _, name in ipairs(slow) do
          if admin.wizard ~= w or w.steps[w.at] ~= step then return end
          base[name] = print_(name)
        end
        step.watching, step.slow = #names, #slow
        admin.dirty = true
        local turn = 0
        local function found(name)
          w.result.chest = name
          local chest = shop.stock.chests[name]
          if chest and (chest.used or 0) > 0 then
            -- it was vault until now: whatever the shop filed in it is no longer stock once this is written
            w.result.warning = " It holds vault stock: empty it before W."
          end
          wizardNext(w)
        end
        while admin.wizard == w and w.steps[w.at] == step do
          for _, name in ipairs(names) do
            local seen = print_(name)
            if seen and base[name] and seen ~= base[name] then return found(name) end
            base[name] = seen or base[name]
          end
          for _ = 1, math.min(8, #slow) do
            turn = turn % #slow + 1
            local name = slow[turn]
            local seen = print_(name)
            if seen and base[name] and seen ~= base[name] then return found(name) end
            base[name] = seen or base[name]
          end
          sleep(0.3)
        end
      end)
    end
  end

  local function startWizard(title, what, steps, done)
    admin.wizard = { title = title, what = what, steps = steps, at = 0, result = {}, done = done }
    admin.msg = nil
    wizardNext(admin.wizard)
  end

  --- Where the owner is standing, and the detector they stand at when the step has one (it need not).
  local function stand(w, step, toucher)
    post(nil, function()
      local who = toucher or wallet.livePlayer() or wallet.hostName()
      local found, why = shopLib.standAt(io, who, step.detector, assigned)
      if not found then
        say(why)
        return
      end
      w.result.detector, w.result.pos = found.detector, found.pos
      if admin.wizard == w and w.steps[w.at] == step then wizardNext(w) end
    end)
  end

  local function linkDraft()
    post("linkdraft", function()
      local modem = shopLib.localEnderModem(io)
      if not modem then
        say("This computer has no ender modem.")
        return
      end
      for _, id in ipairs(admin.draft.nodes) do
        local ok, linked, why = io.call(modem, "link", id)
        if ok and linked == true then
          shop.linked[id] = true
        else
          say("Computer " .. id .. " did not link: " .. tostring(ok and why or linked))
        end
      end
      admin.dirty = true
    end)
  end

  local function addNode(id)
    for _, known in ipairs(admin.draft.nodes) do
      if known == id then return end
    end
    table.insert(admin.draft.nodes, id)
    table.sort(admin.draft.nodes)
    linkDraft()
    admin.dirty = true
  end

  --- Give a station of the draft one gear type, typed by the owner. Returns nil, or what is wrong.
  local function giveType(s, text)
    local known = shop.ready and shop.stock:summary().typeList or {}
    local kind = rules.gearTypeFor(text, known, cfg)
    if not kind then return "There is no gear type or wing called " .. text .. "." end
    s.gearType = kind
    s.category = rules.wingOf(kind, cfg)
    return nil
  end

  local function setupKey(ch)
    local d = admin.draft
    if ch == "f" then
      local modem = shopLib.localEnderModem(io)
      if not modem then
        say("This computer has no ender modem.")
        return
      end
      pcall(rednet.open, modem)
      pcall(rednet.broadcast, { kind = "who" }, M.PROTOCOL)
      say("Asked the nodes. They are added as they answer.")
    elseif ch == "n" then
      ask("Node computer id: ", function(text)
        local id = tonumber(text)
        if id then addNode(math.floor(id)) else say("That is not a number.") end
      end)
    elseif ch == "x" then
      table.remove(d.nodes)
    elseif ch == "d" then
      -- the door's detector, if it has one, is given its job here so that no display chest near the door takes it as its own
      startWizard("THE DOOR", "the door", { { kind = "monitor", optional = true, hint = "No door monitor? S skips it: PAY is on stations." },
        { kind = "stand", detector = true, optional = true } }, function(r)
        d.door = { monitor = r.monitor, detector = r.detector, pos = r.pos }
        say("Door set.")
      end)
    elseif ch == "s" then
      -- where it is, so refused gear left there is put down to whoever was standing at it
      startWizard("SELL POINT", "the sell point", { { kind = "monitor" }, { kind = "chest" }, { kind = "stand", optional = true } }, function(r)
        d.sell = { monitor = r.monitor, chest = r.chest, pos = r.pos }
        say("Sell point set.")
      end)
    elseif ch == "k" then
      startWizard("SEARCH KIOSK", "the search kiosk",
        { { kind = "monitor" }, { kind = "chest" }, { kind = "stand", detector = true, optional = true } }, function(r)
          d.kiosk = { monitor = r.monitor, chest = r.chest, detector = r.detector, pos = r.pos }
          say("Kiosk set.")
        end)
    elseif ch == "u" then
      -- these three may be Sophisticated blocks (a netherite barrel for returns): their step watches those too, and once
      -- one has this job it is never vault
      startWizard("RETURNS CHEST", "the returns chest",
        { { kind = "chest", vaultToo = true, current = d.returns and d.returns.chest } }, function(r)
          d.returns = { chest = r.chest }
          say("Returns chest set: refused gear goes there." .. (r.warning or ""))
        end)
    elseif ch == "j" then
      startWizard("JUNK CHEST", "the junk chest", { { kind = "chest", vaultToo = true, current = d.junk and d.junk.chest } }, function(r)
        d.junk = { chest = r.chest }
        say("Junk chest set: DONATE puts gear there." .. (r.warning or ""))
      end)
    elseif ch == "i" then
      startWizard("INTAKE CHEST", "the intake", { { kind = "chest", vaultToo = true, current = d.intake and d.intake.chest } }, function(r)
        d.intake = { chest = r.chest }
        say("Intake set." .. (r.warning or ""))
      end)
    elseif ch == "p" then
      -- the backpack unpacker at the sell point: its Modular Router and the Redstone Integrator that pulses it
      local routers, integrators = {}, {}
      for _, name in ipairs(io.names()) do
        local own = d.unpack and (d.unpack.router == name or d.unpack.integrator == name)
        if own or not assigned(name) then
          for _, kind in ipairs(io.types(name)) do
            if kind:lower():find("modular_router", 1, true) then routers[#routers + 1] = name end
            if kind == "redstoneIntegrator" then integrators[#integrators + 1] = name end
          end
        end
      end
      local function side(router, integrator)
        ask("Integrator side to the router [up]: ", function(text)
          d.unpack = { router = router, integrator = integrator, side = text ~= "" and text:lower() or "up" }
          say("Unpacker set. W to write it.")
        end)
      end
      local function pickIntegrator(router)
        if #integrators == 1 then return side(router, integrators[1]) end
        say(#integrators == 0 and "No Redstone Integrator is attached." or ("Integrators: " .. table.concat(integrators, " ")))
        ask("Redstone integrator name: ", function(text)
          if not io.hasType(text, "redstoneIntegrator") then
            say("That is no Redstone Integrator.")
            return
          end
          side(router, text)
        end)
      end
      if #routers == 0 and d.unpack then
        d.unpack = nil
        say("Unpacker removed. W to write it.")
      elseif #routers == 1 then
        pickIntegrator(routers[1])
      else
        say(#routers == 0 and "No Modular Router is attached." or ("Routers: " .. table.concat(routers, " ")))
        ask("Router name: ", function(text)
          if not (io.isPresent(text) and io.hasType(text, "inventory")) then
            say("No inventory is called that.")
            return
          end
          pickIntegrator(text)
        end)
      end
    elseif ch == "h" then
      -- the how-it-works screen: a monitor that only explains the shop
      startWizard("HOW-IT-WORKS SCREEN", "the how-it-works screen", { { kind = "monitor" } }, function(r)
        d.info = { monitor = r.monitor }
        say("How-it-works screen set. W to write it.")
      end)
    elseif ch == "a" then
      -- Where it is first: the owner stands on the station's chest (it sits on the station's computer), so the place is
      -- exact, and that works before its monitor is up. Then its chest, its monitor (skippable: M later), its gear type.
      local n = #d.stations + 1
      startWizard("DISPLAY STATION " .. n, "display station " .. n, {
        { kind = "stand", detector = true, optional = true, text = "Stand on this station's chest, then tap" },
        { kind = "chest" },
        { kind = "monitor", optional = true },
      }, function(r)
        d.stations[n] = { monitor = r.monitor, chest = r.chest, detector = r.detector, pos = r.pos }
        -- kept short: the terminal is 51 wide and shows the end of a long line. Blank: any type (the TYPE picker)
        ask("Gear type for station " .. n .. " (sword, idol...): ", function(text)
          if text ~= "" then
            local why = giveType(d.stations[n], text)
            if why then
              say(why .. " G to try again.")
              return
            end
          end
          local s = d.stations[n]
          say("Station " .. n .. " set" .. (s.gearType and (": " .. rules.typePlural(s.gearType)) or "")
            .. (s.monitor and "" or ", no monitor yet") .. ". A for the next.")
        end)
      end)
    elseif ch == "r" then
      table.remove(d.stations)
    elseif ch == "m" then
      ask("Display station number: ", function(text)
        local n = tonumber(text)
        if not (n and d.stations[n]) then
          say("There is no display station " .. tostring(text) .. ".")
          return
        end
        startWizard("STATION " .. n .. " MONITOR", "display station " .. n, { { kind = "monitor" } }, function(r)
          d.stations[n].monitor = r.monitor
          say("Station " .. n .. " has its monitor. W to write it.")
        end)
      end)
    elseif ch == "g" then
      -- one gear type (the usual: a station per type), or a wing (it shows its wing's types, from the categories limit)
      ask("Display station number: ", function(text)
        local n = tonumber(text)
        local s = n and d.stations[n]
        if not s then
          say("There is no display station " .. tostring(text) .. ".")
          return
        end
        -- short enough for the 51-wide terminal, which shows the end of a long line: a gear type ("sword", "idol"), a
        -- wing's name (the categories limit: Weapons, Armour, Magic, Oddities), or blank for every type
        ask("Type or wing for station " .. n .. ": ", function(name)
          if name == "" then
            s.category, s.gearType = nil, nil
            say("Display station " .. n .. " shows every type.")
            return
          end
          local c = rules.category(name, cfg)
          if c then
            s.category, s.gearType = c.name, nil
            say("Display station " .. n .. " is in " .. c.name .. ". W to write it.")
            return
          end
          local why = giveType(s, name)
          if why then
            say(why)
            return
          end
          say("Display station " .. n .. " shows " .. rules.typePlural(s.gearType) .. ". W to write it.")
        end)
      end)
    elseif ch == "v" then
      ask("Vault chest name: ", function(text)
        if io.isPresent(text) and io.hasType(text, "inventory") then
          table.insert(d.vault, text)
        else
          say("No inventory is called that.")
        end
      end)
    elseif ch == "c" then
      admin.draft = store.newSetup()
      admin.draft.nodes = d.nodes
      say("Cleared. Nothing is written until W.")
    elseif ch == "w" then
      local function write()
        if store.saveSetup(admin.draft) then
          term.clear()
          term.setCursorPos(1, 1)
          print("Written. Restarting...")
          sleep(0.5)
          os.reboot()
        else
          say("Could not write the setup.")
        end
      end
      if next(state.shoppers) then
        -- A shop with no door has no CHECK OUT, and the owner is often checked in himself: a second W checks everyone
        -- out first (their stations are emptied into the vault, their tabs kept), in the worker, then writes.
        if not admin.confirmWrite then
          admin.confirmWrite = true
          -- kept under the terminal's 51 columns
          say("Shoppers in. W again checks them out (tabs kept).")
          return
        end
        admin.confirmWrite = nil
        say("Checking everyone out, then writing...")
        post(nil, function()
          local names = {}
          for name in pairs(state.shoppers) do names[#names + 1] = name end
          for _, name in ipairs(names) do shop:checkOut(name, "the owner wrote the setup") end
          if next(state.shoppers) then
            say("Could not check everyone out. Try W again.")
            return
          end
          write()
        end)
        return
      end
      write()
    end
    if ch ~= "w" then admin.confirmWrite = nil end
    admin.dirty = true
  end

  local function wizardKey(ch)
    local w = admin.wizard
    local step = w.steps[w.at]
    if ch == "q" then
      admin.wizard = nil
      say("Cancelled.")
    elseif ch == "s" and step.optional then
      wizardNext(w)
    elseif ch == "t" then
      local field = step.kind == "stand" and "detector" or step.kind
      ask("Name of the " .. field .. ": ", function(text)
        if not io.isPresent(text) then
          say("Nothing is called that.")
          return
        end
        w.result[field] = text
        if admin.wizard == w then wizardNext(w) end
      end)
    end
    admin.dirty = true
  end

  local function adminChar(ch)
    if admin.input then
      admin.input.text = admin.input.text .. ch
      admin.dirty = true
      return
    end
    ch = ch:lower()
    if admin.wizard then return wizardKey(ch) end
    local page = tonumber(ch)
    if page and PAGES[page] then
      admin.page, admin.scroll, admin.msg, admin.dirty = page, 0, nil, true
      return
    end
    if admin.page ~= 4 then admin.bw = nil end
    if admin.page == 5 then
      setupKey(ch)
    elseif admin.page == 4 and admin.bw then
      local bw = admin.bw
      if ch == "q" then
        if bw.build then bw.build, bw.sel, bw.scroll = nil, bw.pick or 1, 0 else admin.bw = nil end
      elseif ch == "d" and bw.build then
        local a = builds.attributes()[bw.sel]
        if type(cfg.buildWeights) == "table" and cfg.buildWeights[bw.build] then
          cfg.buildWeights[bw.build][a] = nil
          if not next(cfg.buildWeights[bw.build]) then cfg.buildWeights[bw.build] = nil end
          store.saveConfig(cfg)
          shop.improveCounts, shop.wornCache = nil, nil
        end
      end
      admin.dirty = true
    elseif admin.page == 4 and ch == "b" then
      admin.bw = { sel = 1, scroll = 0 }
      admin.dirty = true
    elseif admin.page == 4 and ch == "v" then
      -- what the shop buys: a least rarity a level band, every piece with a legendary roll (buyBands)
      ask("Bands, level:rarity (empty: default) = ", function(text)
        if text == "" then
          cfg.buyBands = rules.DEFAULTS.buyBands
        else
          local bands, why = rules.parseBands(text)
          if not bands then
            say(why)
            return
          end
          cfg.buyBands = bands
        end
        store.saveConfig(cfg)
        say("Buys " .. rules.buysText(cfg))
        shop:changed()
      end)
    elseif admin.page == 4 and ch == "d" then
      local key = limitKeys()[admin.sel]
      cfg[key] = rules.DEFAULTS[key]
      store.saveConfig(cfg)
      admin.dirty = true
    end
  end

  local function adminKey(key)
    if admin.input then
      local input = admin.input
      if key == keys.enter then
        admin.input = nil
        input.done(input.text)
      elseif key == keys.backspace then
        input.text = input.text:sub(1, -2)
      end
      admin.dirty = true
      return
    end
    if admin.wizard then
      local w = admin.wizard
      local step = w.steps[w.at]
      if key == keys.enter and step.kind == "stand" then stand(w, step) end
      return
    end
    if admin.page == 4 and admin.bw then
      local bw = admin.bw
      if key == keys.up then
        bw.sel = math.max(1, bw.sel - 1)
      elseif key == keys.down then
        bw.sel = bw.sel + 1
      elseif key == keys.enter and not bw.build then
        bw.build, bw.pick, bw.sel, bw.scroll = builds.ORDER[bw.sel], bw.sel, 1, 0
      elseif key == keys.enter and bw.build then
        local id, a = bw.build, builds.attributes()[bw.sel]
        ask(id .. " " .. a .. " = ", function(text)
          local v = tonumber(text)
          if not v or v < 0 or v > 3 then
            say("A weight is a number from 0 to 3.")
            return
          end
          if type(cfg.buildWeights) ~= "table" then cfg.buildWeights = {} end
          cfg.buildWeights[id] = cfg.buildWeights[id] or {}
          cfg.buildWeights[id][a] = v
          store.saveConfig(cfg)
          -- every shopper's counts are worked out again with the new weight
          shop.improveCounts, shop.wornCache = nil, nil
          say(id .. " " .. a .. " is now " .. v)
        end)
      end
      admin.dirty = true
      return
    end
    if key == keys.up then
      admin.scroll, admin.sel = admin.scroll - 1, admin.sel - 1
    elseif key == keys.down then
      admin.scroll, admin.sel = admin.scroll + 1, admin.sel + 1
    elseif key == keys.enter and admin.page == 4 then
      local name = limitKeys()[admin.sel]
      if type(rules.DEFAULTS[name]) == "boolean" then
        -- an on/off limit flips with Enter
        cfg[name] = not cfg[name]
        store.saveConfig(cfg)
        say(name .. " is now " .. tostring(cfg[name]))
        admin.dirty = true
        return
      end
      ask(name .. " = ", function(text)
        local default = rules.DEFAULTS[name]
        local value = text
        if type(default) == "number" then value = tonumber(text) end
        if value == nil or (type(default) == "number" and value < 0) then
          say("That is not a number.")
          return
        end
        cfg[name] = value
        store.saveConfig(cfg)
        say(name .. " is now " .. tostring(value))
      end)
    end
    admin.scroll = math.max(0, admin.scroll)
    admin.sel = math.max(1, admin.sel)
    admin.dirty = true
  end

  -- ---- touches
  -- The owner's first touch of any shop monitor locks this computer's terminal, as on a casino table: the limits and the
  -- setup are on it. A locked terminal still opens for its owner.
  local lockSettled = false
  local function touched(monitor, x, y, who)
    if who and not lockSettled then
      post("lock", function()
        if wallet.terminalLocked() ~= false or wallet.lockIfOwner(who) then lockSettled = true end
      end)
    end
    if admin.wizard then
      local w = admin.wizard
      local step = w.steps[w.at]
      if step and step.kind == "monitor" then
        if assigned(monitor) then
          say(monitor .. " already has a job.")
        else
          w.result.monitor = monitor
          wizardNext(w)
        end
      elseif step and step.kind == "stand" then
        -- the owner is standing at the chest, out of reach of this terminal: a tap on a monitor is their Enter
        stand(w, step, who)
      end
      return
    end
    local role = shop.monitorRole[monitor]
    local s = screens[monitor]
    if not role or not s then return end
    -- The one-time APPROVE is asked for first, ahead of everything waiting, while this tap is fresh: on vhcctweaks
    -- 2.2.36 the server only lets the shop ask (and charge) within 30 s of a touch, and filling a station or reading
    -- a player can take longer than that on a busy server. A player already approved is not asked.
    if who and shop.ready then postFirst("approve:" .. who, function() shop:askApproval(who) end) end
    local button = s:hit(x, y)
    -- Any tap on a shop screen (a button or not, the how-it-works screen too) by someone who owes the shop pays it first:
    -- jobs run in order, so this goes before what the tap asked for. PAY does it itself.
    if who and not (button and button.id == "pay") then
      post("collect:" .. who, function() shop:collectOnTap(who, monitor) end)
    end
    if role.role == "info" then
      -- help pages turn here, at once: nothing on it waits for the server
      ui.infoTouch(viewOf(monitor), button)
      os.queueEvent("gs_draw")
      return
    end
    if role.role == "sell" and not button then
      -- a tap anywhere on the sell screen says who is selling: what waits in the chest for a seller goes on. Who it was
      -- is asked in the worker when the touch did not say (the server's player lookup waits)
      post("selltap", function()
        local name = who or wallet.livePlayer()
        if name then shop:sellTapped(name, monitor) end
      end)
      return
    end
    if not button then return end
    local function player() return who or wallet.livePlayer() end
    if role.role == "door" then
      if button.id == "checkin" then
        post(nil, function() shop:checkIn(player(), monitor) end)
      elseif button.id == "pay" then
        post(nil, function() shop:pay(player(), monitor) end)
      elseif button.id == "checkout" then
        post(nil, function() shop:checkOut(player(), "checked out", monitor) end)
      end
    elseif role.role == "station" then
      local view, d = viewOf(monitor), role.d
      if button.id == "types" then
        view.mode, view.scroll = "types", 0
      elseif button.id == "back" then
        view.mode = nil
      elseif button.id == "scroll" then
        view.scroll = (view.scroll or 0) + button.value
      elseif button.id == "settype" then
        view.mode = nil
        post(nil, function() shop:stationAction(d, player(), "type", button.value) end)
      elseif button.id == "level" then
        post(nil, function() shop:stationAction(d, player(), "level", button.value) end)
      else
        post(nil, function() shop:stationAction(d, player(), button.id) end)
      end
    elseif role.role == "kiosk" then
      local view = viewOf(monitor)
      if button.id == "improve" then
        -- IMPROVEMENTS: the slot picker, with how many better pieces each slot has once the worker has read their gear
        ui.kioskTouch(view, button, shop)
        local who2 = player()
        view.who = who2
        if shop.improveCounts and who2 then shop.improveCounts[who2] = nil end
        post("improvecount:" .. tostring(who2), function() if who2 then shop:improvements(who2, "any") end end)
      elseif button.id == "setbuild" then
        -- their own build for IMPROVEMENTS: kept, and the counts worked out again for it
        local id, who2 = button.value, player()
        view.mode, view.who = "improve", who2
        if shop.improveCounts and who2 then shop.improveCounts[who2] = nil end
        post(nil, function() shop:kioskAction(who2, "setbuild", { build = id }) end)
      elseif button.id == "improveslot" then
        local slot = button.value
        post(nil, function() shop:kioskAction(player(), "improve", { slot = slot }) end)
      elseif not ui.kioskTouch(view, button, shop) then
        local query = copy(view.query or {})
        post(nil, function() shop:kioskAction(player(), button.id, query) end)
      end
    elseif role.role == "sell" then
      local mode = button.id
      if mode == "donate" then
        post(nil, function() shop:donate(player(), monitor) end)
      else
        post(nil, function() shop:sell(player(), mode, monitor) end)
      end
    end
  end

  local function chestChanged(name)
    local role = shop.chestRole[name]
    if not role then return end
    if role.d then
      post("reconcile:" .. role.d.id, function() shop:reconcile(role.d) end)
    elseif role.role == "sell" then
      post("sellscan", function() shop:sellScan() end)
    elseif role.role == "intake" then
      post("intake", function() shop:intake() end)
    elseif role.role == "vault" then
      post("index:" .. name, function() shop.stock:index(name) end)
    end
  end

  local function screen()
    -- listening from the start: a node that restarts says so, and its monitors are drawn again (see rednet_message)
    local modem = shopLib.localEnderModem(io)
    if modem then pcall(rednet.open, modem) end
    local tick = os.startTimer(TICK)
    local ticked, balanceAt = os.clock(), -math.huge
    local toucher
    drawAdmin()
    while true do
      local e = table.pack(os.pullEvent())
      local event = e[1]
      if event == "timer" and e[2] == tick then
        tick = os.startTimer(TICK)
        ticked = os.clock()
        post("upkeep", function() shop:upkeep() end)
        if admin.page <= 3 and not admin.wizard then admin.dirty = true end
        if os.clock() - balanceAt > 30 and shop.ready then
          balanceAt = os.clock()
          post("balance", function()
            admin.hostBalance = wallet.hostBalance()
            admin.dirty = true
          end)
        end
      elseif event == "vhcc_touch" then
        toucher = e[2]
      elseif event == "monitor_touch" then
        local ok, err = pcall(touched, e[2], e[3], e[4], toucher)
        if not ok then store.log("touch: " .. tostring(err)) end
        toucher = nil
      elseif event == "inventory_changed" then
        chestChanged(e[2])
      elseif event == "peripheral" then
        -- A peripheral the shop already has needs nothing: the link attaches every node's peripherals again at boot,
        -- right after the first draw, and a full redraw of each screen then held up the shop's first wallet call by
        -- 16-36 s under load (a tap's touch is only fresh for 30 s on vhcctweaks 2.2.36). A screen already measured
        -- and drawn stays as it is; a detach clears it, and a node that restarts says so and is drawn again in full.
        local name = e[2]
        if not shop:knows(name) then
          spareChanged()
          if shop.ready then post("attach:" .. name, function() shop:attached(name) end) end
          admin.dirty = true
        end
      elseif event == "peripheral_detach" then
        local name = e[2]
        screens[name] = nil
        spareChanged()
        post("detach:" .. name, function() shop:detached(name) end)
        admin.dirty = true
      elseif event == "monitor_resize" then
        -- a real change of size: made again, so its text scale is picked again (the help screen) and it is drawn in
        -- full. Setting a text scale can raise this event too; then the size is what was measured and nothing happens.
        local s = screens[e[2]]
        if s then
          local w, h = s.w, s.h
          s:measure()
          if s.w ~= w or s.h ~= h then screens[e[2]] = nil end
        end
      elseif event == "char" then
        local ok, err = pcall(adminChar, e[2])
        if not ok then store.log("key: " .. tostring(err)) end
      elseif event == "key" then
        local ok, err = pcall(adminKey, e[2])
        if not ok then store.log("key: " .. tostring(err)) end
      elseif event == "rednet_message" and e[4] == M.PROTOCOL then
        local message = e[3]
        if type(message) == "table" and message.kind == "node" and type(message.id) == "number" then
          local id = math.floor(message.id)
          if admin.page == 5 then addNode(id) end
          -- a node says this when it starts, after blanking its monitors: what is on them is no longer what was sent,
          -- so each is drawn again in full
          local prefix = id .. ":"
          for name in pairs(screens) do
            if name:sub(1, #prefix) == prefix then screens[name] = nil end
          end
          spareChanged()
          os.queueEvent("gs_draw")
        end
      end
      if os.clock() - ticked > TICK * 4 then
        -- the tick was lost: start it again
        tick = os.startTimer(TICK)
        ticked = os.clock()
      end
      if (event == "timer" and e[2] == tick) or event == "gs_draw" or event == "monitor_touch" or event == "peripheral"
        or event == "peripheral_detach" or event == "monitor_resize" then
        drawMonitors()
      end
      drawAdmin()
    end
  end

  parallel.waitForAny(screen, worker)
end

function M.run()
  local role = store.loadRole() or askRole()
  if role == "node" then return require("lib.gearshop.node").run() end
  return runShop()
end

return M
