-- gearlocker/app.lua
-- The Gear Locker on one player's base: first-run setup on the terminal, then the pages from ui.lua on the monitor
-- (the terminal shows the same pages). One worker does everything slow (scan, pull, take) so a touch never waits on it.

local Locker = require("lib.gearlocker.locker")
local judge = require("lib.gearlocker.judge")
local ui = require("lib.gearlocker.ui")

local M = {}

local RESCAN = 180

local function inventories(skip)
  local out = {}
  for _, name in ipairs(peripheral.getNames()) do
    if not skip[name] and peripheral.hasType(name, "inventory") then out[#out + 1] = name end
  end
  return out
end

local function snapshot(name)
  local ok, list = pcall(peripheral.call, name, "list")
  if not ok or type(list) ~= "table" then return nil end
  local parts = {}
  for slot, item in pairs(list) do parts[#parts + 1] = slot .. ":" .. tostring(item.name) .. "x" .. tostring(item.count) end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- Drop an item in the chest, or type its name. Whichever comes first.
local function pickChest(what, skip)
  print("")
  print("Drop any item into the " .. what .. ", or type its name:")
  local names = inventories(skip)
  local base = {}
  for _, name in ipairs(names) do base[name] = snapshot(name) end
  local picked
  parallel.waitForAny(function()
    while not picked do
      write("> ")
      local typed = read()
      if typed and typed ~= "" then
        if peripheral.isPresent(typed) and peripheral.hasType(typed, "inventory") then
          picked = typed
        else
          print("No chest called " .. typed)
        end
      end
    end
  end, function()
    while not picked do
      for _, name in ipairs(names) do
        local seen = snapshot(name)
        if seen and base[name] and seen ~= base[name] then picked = name break end
        base[name] = seen or base[name]
      end
      sleep(0.3)
    end
  end)
  print("")
  print(what .. ": " .. picked)
  return picked
end

local function setup(L)
  local cfg = L.cfg
  term.clear()
  term.setCursorPos(1, 1)
  print("Gear Locker setup")
  if not cfg.player then
    write("Your Minecraft name: ")
    cfg.player = read()
  end
  if not (cfg.bridge and peripheral.isPresent(cfg.bridge)) then
    local bridge = peripheral.find("meBridge")
    if not bridge then
      print("No ME Bridge found. Put one next to the computer or on its network, then restart.")
      return false
    end
    cfg.bridge = peripheral.getName(bridge)
    print("ME Bridge: " .. cfg.bridge)
  end
  if not (cfg.monitor and peripheral.isPresent(cfg.monitor)) then
    local mon = peripheral.find("monitor")
    cfg.monitor = mon and peripheral.getName(mon) or nil
    print("Monitor: " .. tostring(cfg.monitor or "none, using this screen"))
  end
  local taken = { [cfg.bridge] = true }
  for _, role in ipairs({ "staging", "junk", "pickup" }) do
    if cfg[role] and peripheral.isPresent(cfg[role]) then taken[cfg[role]] = true end
  end
  local words = { staging = "staging chest (keep it empty)", junk = "junk chest", pickup = "pickup chest" }
  for _, role in ipairs({ "staging", "junk", "pickup" }) do
    if not (cfg[role] and peripheral.isPresent(cfg[role])) then
      cfg[role] = pickChest(words[role], taken)
      taken[cfg[role]] = true
    end
  end
  L:saveConfig()
  print("All set. Take the items back out of the chests.")
  sleep(1)
  return true
end

function M.run(opts)
  opts = opts or {}
  local L = (opts.Locker or Locker).new(opts.locker or {})
  local cfg = L.cfg
  if not (cfg.player and cfg.bridge and cfg.staging and cfg.junk and cfg.pickup) then
    if not setup(L) then return end
  end

  local st = { page = "home", player = cfg.player, picked = cfg.build ~= nil, buildId = cfg.build }
  local screens = {}
  local function attach()
    screens = {}
    local mon = cfg.monitor and peripheral.isPresent(cfg.monitor) and peripheral.wrap(cfg.monitor)
    if mon then screens[cfg.monitor] = ui.screen(mon, 0.5) end
    screens.term = ui.screen(term.current())
  end
  attach()

  local function draw()
    for _, s in pairs(screens) do
      s:measure()
      ui.draw(s, st)
    end
  end

  local function check()
    local missing = {}
    for _, role in ipairs({ "bridge", "staging", "junk", "pickup" }) do
      if not (cfg[role] and peripheral.isPresent(cfg[role])) then missing[#missing + 1] = role .. " (" .. tostring(cfg[role]) .. ")" end
    end
    st.missing = missing
    local ready = #missing == 0 and not st.busy
    st.canScan, st.canPull, st.canTake = ready, ready, ready
  end

  local function refresh()
    local pieces = L:pieces()
    local read, why = L:readPlayer()
    local r = judge.settings(cfg.rules)
    local buildId, _, buildWhy = judge.build(read, cfg.build)
    local junk = judge.junk(pieces, read, buildId, r, cfg.spared or {})
    local _, best, counts, note = judge.upgrades(pieces, read, buildId, r)
    local slotCounts, spared, nSpared = {}, {}, 0
    for _, p in ipairs(pieces) do
      if p.slot then slotCounts[p.slot] = (slotCounts[p.slot] or 0) + 1 end
      if cfg.spared and cfg.spared[p.fp] then spared[#spared + 1] = p end
    end
    for _ in pairs(cfg.spared or {}) do nSpared = nSpared + 1 end
    local upSlots = 0
    for _ in pairs(best) do upSlots = upSlots + 1 end
    st.pieces, st.junk, st.best, st.counts, st.slotCounts = pieces, junk, best, counts, slotCounts
    st.sparedPieces, st.sparedCount, st.upgradeSlots = spared, nSpared, upSlots
    st.rules, st.buildId, st.buildWhy, st.picked = r, buildId, buildWhy, cfg.build ~= nil
    st.readWhy = not read and (why or "can't read you right now") or nil
    st.limited = note ~= nil and note:find("2.2.37", 1, true) ~= nil
    check()
  end

  local jobs = {}
  local function post(name, fn)
    if st.busy then return end
    jobs[#jobs + 1] = { name = name, fn = fn }
    st.busy = name
    check()
    os.queueEvent("gearlocker_job")
  end

  local function say(text, fg)
    st.note, st.noteFg = text, fg
  end

  local function scan()
    local n, err = L:scan(function(done, total)
      st.progress = { done = done, total = total }
      draw()
    end)
    st.progress = nil
    if err then say("Scan: " .. tostring(err), "e") else say(#L:pieces() .. " pieces, " .. tostring(n) .. " new", "5") end
    st.lastScan = os.epoch("utc")
  end

  local function pullAll()
    local list = {}
    for _, j in ipairs(st.junk or {}) do list[#list + 1] = j.piece end
    if #list == 0 then return end
    local moved, failed = L:pull(list)
    local text = "Pulled " .. tostring(moved) .. " to the junk chest"
    if failed and #failed > 0 then text = text .. ", " .. #failed .. " stuck: " .. tostring(failed[1][2] or failed[1].why) end
    say(text, failed and #failed > 0 and "1" or "5")
    scan()
  end

  local function worker()
    post("Checking staging", function()
      L:recover()
      scan()
    end)
    while true do
      local job = table.remove(jobs, 1)
      if job then
        local ok, err = pcall(job.fn)
        if not ok then say(job.name .. " failed: " .. tostring(err), "e") end
        st.busy = nil
        pcall(refresh)
        draw()
      else
        os.pullEvent("gearlocker_job")
      end
    end
  end

  local STEPS = { keepPerSlot = { 1, 0, 10 }, maxBelow = { 5, 0, 100 }, autoEvery = { 60, 60, 3600 } }
  local function nudge(key, dir)
    cfg.rules = cfg.rules or {}
    local r = judge.settings(cfg.rules)
    if key == "minRarity" then
      local at = 1
      for i, name in ipairs(ui.RARITIES) do if name == r.minRarity then at = i end end
      at = math.max(1, math.min(#ui.RARITIES, at + dir))
      cfg.rules.minRarity = ui.RARITIES[at]
    elseif STEPS[key] then
      local step, lo, hi = table.unpack(STEPS[key])
      cfg.rules[key] = math.max(lo, math.min(hi, (r[key] or lo) + dir * step))
    end
    L:saveConfig()
  end

  local function touch(b)
    if not b then return end
    local id, v = b.id, b.value
    if id == "page" then
      st.page = v
    elseif id == "back" then
      st.page = "home"
    elseif id == "scan" then
      if st.canScan then post("Scanning", scan) end
    elseif id == "pull" then
      if st.canPull and #(st.junk or {}) > 0 then post("Pulling", pullAll) end
    elseif id == "take" then
      if st.canTake then
        post("Taking", function()
          local ok, why = L:take(v)
          if ok then say("In the pickup chest", "5") else say("Couldn't take it: " .. tostring(why), "e") end
          scan()
        end)
      end
    elseif id == "spare" then
      L:spare(v, b.on)
    elseif id == "unspareall" then
      for fp in pairs(cfg.spared or {}) do L:spare(fp, false) end
    elseif id == "badprev" then
      st.badPage = math.max(1, (st.badPage or 1) - 1)
    elseif id == "badnext" then
      st.badPage = (st.badPage or 1) + 1
    elseif id == "build" then
      cfg.build = v or nil
      L:saveConfig()
      st.page = "up"
    elseif id == "set" then
      cfg.rules = cfg.rules or {}
      cfg.rules[v] = not judge.settings(cfg.rules)[v]
      L:saveConfig()
    elseif id == "inc" or id == "dec" then
      nudge(v, id == "inc" and 1 or -1)
    end
    pcall(refresh)
  end

  local function events()
    local rescan = os.startTimer(RESCAN)
    local lastPull = os.epoch("utc")
    local tick = os.startTimer(5)
    while true do
      local ev = { os.pullEvent() }
      local e = ev[1]
      if e == "monitor_touch" and screens[ev[2]] then
        touch(screens[ev[2]]:hit(ev[3], ev[4]))
      elseif e == "mouse_click" then
        touch(screens.term:hit(ev[3], ev[4]))
      elseif e == "timer" and ev[2] == rescan then
        rescan = os.startTimer(RESCAN)
        if st.canScan then post("Scanning", scan) end
      elseif e == "timer" and ev[2] == tick then
        tick = os.startTimer(5)
        pcall(refresh)
        local r = st.rules or {}
        if r.auto and st.canPull and #(st.junk or {}) > 0
            and os.epoch("utc") - lastPull >= (r.autoEvery or 300) * 1000 then
          lastPull = os.epoch("utc")
          post("Pulling", pullAll)
        end
      elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" or e == "term_resize" then
        attach()
        check()
      end
      draw()
    end
  end

  pcall(refresh)
  draw()
  parallel.waitForAny(worker, events)
end

return M
