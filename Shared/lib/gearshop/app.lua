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
    if not screens[name] then screens[name] = ui.screen(io, name, cfg.textScale) end
    if screens[name].w == 0 and not screens[name]:measure() then return nil end
    return screens[name]
  end
  local function viewOf(name)
    views[name] = views[name] or {}
    return views[name]
  end

  local function drawMonitors()
    local dump = debug and { ready = shop.ready, status = shop.status, version = shop.version, boot = boots, monitors = {} } or nil
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
    if used(d.door) or used(d.sell) or used(d.kiosk) or used(d.intake) or used(d.returns) or used(d.junk) then return true end
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
    elseif admin.page == 4 then
      local list = limitKeys()
      local rows = th - 3
      admin.sel = math.max(1, math.min(admin.sel, #list))
      if admin.sel <= admin.scroll then admin.scroll = admin.sel - 1 end
      if admin.sel > admin.scroll + rows then admin.scroll = admin.sel - rows end
      for i = 1 + admin.scroll, math.min(#list, admin.scroll + rows) do
        local key = list[i]
        line((i == admin.sel and "> " or "  ") .. ("%-22s %s"):format(key, tostring(cfg[key])), i == admin.sel and colors.lime or colors.white)
      end
      line("Up/Down pick, Enter change, D back to default", colors.lightGray)
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
      -- the worker watches every chest that has no job yet and is not a vault chest, until one changes
      post(nil, function()
        local names, base = {}, {}
        local function print_(name)
          local ok, list = io.call(name, "list")
          if not ok or type(list) ~= "table" then return nil end
          local parts = {}
          for slot, item in pairs(list) do parts[#parts + 1] = slot .. ":" .. rules.key(item) .. "x" .. tostring(item.count) end
          table.sort(parts)
          return table.concat(parts, ",")
        end
        for _, name in ipairs(io.names()) do
          if io.hasType(name, "inventory") and not assigned(name) and not shop:isVaultChest(name) then
            names[#names + 1] = name
            base[name] = print_(name)
          end
        end
        step.watching = #names
        admin.dirty = true
        while admin.wizard == w and w.steps[w.at] == step do
          for _, name in ipairs(names) do
            local seen = print_(name)
            if seen and base[name] and seen ~= base[name] then
              w.result.chest = name
              wizardNext(w)
              return
            end
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
      startWizard("RETURNS CHEST", "the returns chest", { { kind = "chest" } }, function(r)
        d.returns = { chest = r.chest }
        say("Returns chest set: refused gear goes there.")
      end)
    elseif ch == "j" then
      startWizard("JUNK CHEST", "the junk chest", { { kind = "chest" } }, function(r)
        d.junk = { chest = r.chest }
        say("Junk chest set: DONATE puts gear there.")
      end)
    elseif ch == "i" then
      startWizard("INTAKE CHEST", "the intake", { { kind = "chest" } }, function(r)
        d.intake = { chest = r.chest }
        say("Intake set.")
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
      if next(state.shoppers) then
        say("Someone is checked in. Wait until the shop is empty.")
        return
      end
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
    if admin.page == 5 then
      setupKey(ch)
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
    local button = s:hit(x, y)
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
      if not ui.kioskTouch(view, button) then
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
        local name = e[2]
        screens[name] = nil
        if shop.ready then post("attach:" .. name, function() shop:attached(name) end) end
        admin.dirty = true
      elseif event == "peripheral_detach" then
        local name = e[2]
        screens[name] = nil
        post("detach:" .. name, function() shop:detached(name) end)
        admin.dirty = true
      elseif event == "monitor_resize" then
        if screens[e[2]] then screens[e[2]]:measure() end
      elseif event == "char" then
        local ok, err = pcall(adminChar, e[2])
        if not ok then store.log("key: " .. tostring(err)) end
      elseif event == "key" then
        local ok, err = pcall(adminKey, e[2])
        if not ok then store.log("key: " .. tostring(err)) end
      elseif event == "rednet_message" and e[4] == M.PROTOCOL then
        local message = e[3]
        if type(message) == "table" and message.kind == "node" and type(message.id) == "number" and admin.page == 5 then
          addNode(math.floor(message.id))
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
