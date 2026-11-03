-- tracker/app.lua
-- The tracker computer: collects every Arcade cabinet's and casino table's own record of who played what (rules.lua says
-- how), keeps the sum on disk, and shows it on the biggest monitor it has. It asks every computer for anything new when it
-- starts, every couple of minutes, and at once when a game finishes; anything it misses while off, it catches up on. Four pages, NOW, PLAYERS, GAMES and RECENT, along the top;
-- tap a player for their games. Left alone it turns the pages by itself. With no monitor it shows them on its own screen.
-- It sends nothing and moves nothing: a cabinet never waits for it, and a tracker that's off just misses the time.

local rules = require("lib.tracker.rules")
local shared = require("lib.tracker.shared")

local M = {}

local SAVE_FILE = "tracker_data.dat"
local SHARED_FILE = "tracker_shared.dat" -- the floor's master copy of every cabinet's saves, scores and records
local SHARED_SAVE_MS = 5000
local SAVE_MS = 30000
local REDRAW_MS = 5000
local CYCLE_MS = 20000     -- left alone, the next page this often
local HANDS_OFF_MS = 60000 -- and only after nobody has touched it for this long
local PAGES = { "NOW", "PLAYERS", "GAMES", "RECENT" }
local ASK_MS = 120000      -- everyone is asked for anything new this often
local PROTOCOLS = { "arcade.v1", "casino.v2" }

local function now() return os.epoch("utc") end

-- ---------------------------------------------------------------- the books on disk

local function loadShared()
  for _, path in ipairs({ SHARED_FILE, SHARED_FILE .. ".bak" }) do
    if fs.exists(path) then
      local h = fs.open(path, "r")
      if h then
        local ok, sh = pcall(textutils.unserialise, h.readAll() or "")
        h.close()
        if ok and type(sh) == "table" and sh.v == 1 and type(sh.entries) == "table" then return sh end
      end
    end
  end
  return shared.new()
end

local function load()
  for _, path in ipairs({ SAVE_FILE, SAVE_FILE .. ".bak" }) do
    if fs.exists(path) then
      local h = fs.open(path, "r")
      if h then
        local ok, d = pcall(textutils.unserialise, h.readAll() or "")
        h.close()
        if ok and type(d) == "table" and d.v == 2 and type(d.cabinets) == "table" then
          for _, key in ipairs({ "tables", "players", "games", "live", "recent", "want" }) do d[key] = d[key] or {} end
          return d
        end
      end
    end
  end
  return rules.new()
end

local function writeFile(path, value)
  local ok, text = pcall(textutils.serialise, value, { compact = true })
  if not ok then return false end
  local tmp = path .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then return false end
  h.write(text)
  h.close()
  if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
  if fs.exists(path) then fs.move(path, path .. ".bak") end
  fs.move(tmp, path)
  return true
end

local function save(d) return writeFile(SAVE_FILE, d) end

-- ---------------------------------------------------------------- the screen

local function biggestMonitor()
  local best, area = nil, 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "monitor") then
      local m = peripheral.wrap(name)
      m.setTextScale(0.5)
      local w, h = m.getSize()
      if w * h > area then best, area = { obj = m, name = name }, w * h end
    end
  end
  return best
end

local function openModems()
  local any = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") then
      pcall(rednet.open, name)
      any = true
    end
  end
  return any
end

--- Write text at x, y in colours, cut to the width left.
local function put(out, x, y, str, fg, bg)
  local w = out.getSize()
  if x > w then return end
  str = tostring(str):sub(1, w - x + 1)
  out.setCursorPos(x, y)
  out.setTextColor(fg or colors.white)
  out.setBackgroundColor(bg or colors.black)
  out.write(str)
end

local function fill(out, y, bg)
  local w = out.getSize()
  put(out, 1, y, string.rep(" ", w), colors.white, bg)
end

local function bar(out, x, y, width, share, color)
  local filled = math.max(0, math.min(width, math.floor(width * share + 0.5)))
  put(out, x, y, string.rep(" ", filled), color, color)
  put(out, x + filled, y, string.rep(" ", width - filled), colors.gray, colors.gray)
end

local function drawTabs(out, ui)
  fill(out, 1, colors.gray)
  put(out, 2, 1, "PLAY TRACKER", colors.yellow, colors.gray)
  if ui.held then
    local w = out.getSize()
    local c = ui.held
    local line = "holding " .. c.save .. " saved games, " .. (c.scores + c.versus) .. " score tables, " .. c.records .. " records "
    put(out, w - #line + 1, 1, line, colors.lightGray, colors.gray)
  end
  local x = 16
  ui.tabs = {}
  for i, name in ipairs(PAGES) do
    local label = " " .. name .. " "
    local on = ui.page == name
    put(out, x, 1, label, on and colors.black or colors.white, on and colors.yellow or colors.gray)
    ui.tabs[#ui.tabs + 1] = { x1 = x, x2 = x + #label - 1, page = name }
    x = x + #label + 1
  end
end

local function players(list)
  local out = {}
  for _, name in ipairs(list or {}) do out[#out + 1] = name end
  return table.concat(out, " vs ")
end

local function drawNow(out, d, t, w, h)
  local list = rules.now(d)
  put(out, 2, 3, #list == 0 and "Nobody is playing right now." or (#list .. " playing now"), colors.lightGray)
  for i, live in ipairs(list) do
    local y = 3 + i * 2
    if y > h - 1 then break end
    put(out, 2, y, players(live.players), colors.white)
    put(out, 30, y, live.title or live.game, colors.yellow)
    put(out, 56, y, rules.duration(live.ms), colors.lime)
    local extra = live.goal or (live.percent and (live.percent .. "%")) or (live.score and ("score " .. live.score))
      or (live.rounds and (live.rounds .. " rounds")) or ""
    put(out, 66, y, extra, colors.lightGray)
    if live.cabinet then put(out, w - #live.cabinet, y, live.cabinet, colors.gray) end
  end
end

local function drawPlayers(out, d, t, w, h, ui)
  local list = rules.players(d)
  ui.rows = {}
  put(out, 2, 3, #list .. " players. Tap a name for their games.", colors.lightGray)
  local most = list[1] and list[1].ms or 1
  for i, p in ipairs(list) do
    local y = 3 + i * 2
    if y > h - 1 then break end
    put(out, 2, y, p.name, colors.white)
    put(out, 22, y, rules.duration(p.ms), colors.lime)
    bar(out, 32, y, 16, p.ms / math.max(1, most), colors.lime)
    put(out, 50, y, (p.count == 1 and "1 game" or p.count .. " games") .. ", mostly " .. (p.top or "?"), colors.lightGray)
    put(out, w - 12, y, rules.ago(p.last, t), colors.gray)
    ui.rows[y] = p.name
  end
end

local function drawGames(out, d, t, w, h)
  local list = rules.games(d)
  put(out, 2, 3, #list == 0 and "No games played yet." or "Every game, most played first", colors.lightGray)
  local most = list[1] and list[1].ms or 1
  for i, g in ipairs(list) do
    local y = 3 + i * 2
    if y > h - 1 then break end
    put(out, 2, y, g.title, colors.yellow)
    put(out, 24, y, rules.duration(g.ms), colors.lime)
    bar(out, 34, y, 16, g.ms / math.max(1, most), colors.lime)
    local what = g.players .. (g.players == 1 and " player, " or " players, ")
      .. (g.rounds > 0 and (g.rounds .. " rounds") or (g.sessions .. (g.sessions == 1 and " game" or " games")))
    put(out, 52, y, what, colors.lightGray)
    put(out, w - 12, y, rules.ago(g.last, t), colors.gray)
  end
end

local function drawRecent(out, d, t, w, h)
  put(out, 2, 3, #d.recent == 0 and "Nothing finished yet." or "Games just finished", colors.lightGray)
  for i, r in ipairs(d.recent) do
    local y = 3 + i * 2
    if y > h - 1 then break end
    put(out, 2, y, players(r.players), colors.white)
    put(out, 30, y, r.title or "?", colors.yellow)
    put(out, 56, y, rules.duration(r.ms), colors.lime)
    put(out, 66, y, r.note or "", colors.lightGray)
    put(out, w - 12, y, rules.ago(r.at, t), colors.gray)
  end
end

local function drawPlayer(out, d, t, w, h, name)
  local p = rules.player(d, name)
  if not p then return end
  put(out, 2, 3, name, colors.yellow)
  put(out, 2 + #name + 2, 3, rules.duration(p.ms) .. " in all, " .. p.sessions .. " sittings, last " .. rules.ago(p.last, t), colors.lightGray)
  put(out, w - 7, 3, " BACK ", colors.black, colors.lightGray)
  for i, e in ipairs(p.games) do
    local y = 3 + i * 2
    if y > h - 1 then break end
    put(out, 2, y, e.title, colors.white)
    put(out, 24, y, rules.duration(e.ms), colors.lime)
    local bits = {}
    if e.percent then bits[#bits + 1] = e.percent .. "% of the story" end
    if e.goal then bits[#bits + 1] = e.goal end
    if e.level and not e.percent then bits[#bits + 1] = "level " .. e.level end
    if e.best then bits[#bits + 1] = "best " .. e.best end
    if (e.wins or 0) + (e.losses or 0) > 0 then bits[#bits + 1] = e.wins .. " won, " .. e.losses .. " lost" end
    if (e.rounds or 0) > 0 then
      bits[#bits + 1] = e.rounds .. " rounds, " .. (e.net >= 0 and "+" or "") .. e.net .. " tokens"
    end
    put(out, 34, y, table.concat(bits, ", "), colors.lightGray)
  end
end

local function draw(out, d, ui)
  local t = now()
  local w, h = out.getSize()
  out.setBackgroundColor(colors.black)
  out.clear()
  drawTabs(out, ui)
  if ui.player then
    drawPlayer(out, d, t, w, h, ui.player)
  elseif ui.page == "NOW" then
    drawNow(out, d, t, w, h)
  elseif ui.page == "PLAYERS" then
    drawPlayers(out, d, t, w, h, ui)
  elseif ui.page == "GAMES" then
    drawGames(out, d, t, w, h)
  else
    drawRecent(out, d, t, w, h)
  end
  if not ui.heard then put(out, 2, h, "No modem: put an ender modem on this computer.", colors.orange) end
end
M.draw = draw

--- A tap on the screen: a tab, a player's name, or BACK.
local function touch(out, ui, x, y)
  local w = out.getSize()
  ui.touchedAt = now()
  if y == 1 then
    for _, tab in ipairs(ui.tabs or {}) do
      if x >= tab.x1 and x <= tab.x2 then ui.page, ui.player = tab.page, nil end
    end
  elseif ui.player and y == 3 and x >= w - 7 then
    ui.player = nil
  elseif ui.page == "PLAYERS" and not ui.player and ui.rows and ui.rows[y] then
    ui.player = ui.rows[y]
  end
end
M.touch = touch

--- Ask for anything new: everyone, or just the computers given.
local function ask(d, who)
  local msg = rules.ask(d)
  for _, protocol in ipairs(PROTOCOLS) do
    if who then
      for _, id in ipairs(who) do pcall(rednet.send, id, msg, protocol) end
    else
      pcall(rednet.broadcast, msg, protocol)
    end
  end
end

function M.run()
  local d = load()
  local sh = loadShared()
  local sharedDirty, sharedSavedAt = false, 0
  local ui = { page = "NOW", touchedAt = 0, held = shared.counts(sh) }
  local mon = biggestMonitor()
  local out = mon and mon.obj or term.current()
  ui.heard = openModems()
  local dirty, changedAt, savedAt, pagedAt, askedAt = true, 0, now(), now(), now()
  local timer = os.startTimer(1)
  local asked = {}
  ask(d)
  while true do
    if dirty then
      draw(out, d, ui)
      dirty = false
    end
    local ev = { os.pullEvent() }
    local kind, t = ev[1], now()
    if kind == "rednet_message" then
      local sender, msg, protocol = ev[2], ev[3], ev[4]
      if rules.hear(d, sender, protocol, msg, t) then changedAt, dirty = t, true end
      if protocol == "arcade.v1" and type(msg) == "table" then
        if msg.kind == "share" and shared.put(sh, msg, t) then
          sharedDirty, ui.held, dirty = true, shared.counts(sh), true
        elseif msg.kind == "shareask" then
          pcall(rednet.send, sender, shared.since(sh, msg.after, msg.games), "arcade.v1")
        end
      end
    elseif kind == "monitor_touch" and mon and ev[2] == mon.name then
      touch(out, ui, ev[3], ev[4])
      dirty = true
    elseif kind == "mouse_click" and not mon then
      touch(out, ui, ev[3], ev[4])
      dirty = true
    elseif kind == "peripheral" or kind == "peripheral_detach" or kind == "monitor_resize" then
      mon = biggestMonitor()
      out = mon and mon.obj or term.current()
      ui.heard = openModems()
      dirty = true
    elseif kind == "timer" and ev[2] == timer then
      timer = os.startTimer(REDRAW_MS / 1000)
      if rules.expire(d, t) then changedAt = t end
      if sharedDirty and t - sharedSavedAt >= SHARED_SAVE_MS then
        writeFile(SHARED_FILE, sh)
        sharedDirty, sharedSavedAt = false, t
      end
      -- a computer with news is asked at once, but no one more than every 30 seconds: a busy table plays a round a minute
      local who = {}
      for _, id in ipairs(rules.wanted(d)) do
        if t - (asked[id] or 0) >= 30000 then
          who[#who + 1], asked[id] = id, t
        else
          d.want[tostring(id)] = true
        end
      end
      if #who > 0 then ask(d, who) end
      if t - askedAt >= ASK_MS then
        ask(d)
        askedAt = t
      end
      if changedAt > savedAt and t - savedAt >= SAVE_MS then
        save(d)
        savedAt = t
      end
      if t - ui.touchedAt > HANDS_OFF_MS and t - pagedAt > CYCLE_MS then
        local at = 1
        for i, name in ipairs(PAGES) do
          if name == ui.page then at = i end
        end
        ui.page, ui.player, pagedAt = PAGES[at % #PAGES + 1], nil, t
      end
      dirty = true
    elseif kind == "terminate" then
      save(d)
      if sharedDirty then writeFile(SHARED_FILE, sh) end
      return
    end
  end
end

return M
