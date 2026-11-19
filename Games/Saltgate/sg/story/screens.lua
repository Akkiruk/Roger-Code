-- story/screens.lua
-- What the story puts on the screen: the dialogue box and the choices, the cutscene's bars and captions, the phone,
-- the failure and "job done" screens, the HUD's objective line, clock and toasts. Everything draws through the core's
-- ui registry (ctx.ui.screen / ctx.ui.widget); nothing here keeps story state: it reads the host.
--
-- Screens are modal (the game stops under them) and are fed keys by the core loop: screen.input(ctx, inp, dt) and
-- screen.update(ctx, dt) (see the ui contract in core/ui.lua). Actions used: advance (ENTER), up/down (W/S or the arrows),
-- skip (X), n1..n4 (the number keys), phone (T), pause (P), map (M).

local text = require("sg.story.text")
local phoneLib = require("sg.story.phone")
local hints = require("sg.hints")

local M = {}

local FALLBACK = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64, gray = 128,
  lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768 }

-- CC has the American spellings (gray, lightGray) in `colors` and the British (grey, lightGrey) in `colours`
local function col(name)
  local c = rawget(_G, "colors")
  if c and c[name] then return c[name] end
  c = rawget(_G, "colours")
  if c then
    local british = name:gsub("ray", "rey")
    return c[name] or c[british] or c.white
  end
  return FALLBACK[name] or FALLBACK.white
end

local function put(t, x, y, str, fg, bg)
  t.setCursorPos(x, y)
  t.setTextColour(col(fg or "white"))
  t.setBackgroundColour(col(bg or "black"))
  t.write(str)
end

local function fill(t, x, y, w, bg)
  t.setCursorPos(x, y)
  t.setBackgroundColour(col(bg or "black"))
  t.write(string.rep(" ", w))
end

M.put, M.fill, M.col = put, fill, col

-- ---------------------------------------------------------------- the dialogue box

local function speakerColour(idx, who)
  local c = idx.cast[who]
  return c and c.colour or "lightGray"
end

--- The talk box over the bottom of the screen (a line, or a choice).
function M.drawTalk(ctx, host, idx)
  local t = ctx.screen
  local w, h = t.getSize()
  local talk = host.talk
  local line, choice = talk.line, talk.choice
  if choice then
    local rows = choice.rows
    local top = h - (#rows + #choice.options + 2)
    fill(t, 1, top, w, "gray")
    put(t, 2, top, " Wren ", "lightBlue", "gray")
    for i, r in ipairs(rows) do
      fill(t, 1, top + i, w, "black")
      put(t, 3, top + i, r, "yellow")
    end
    for i, o in ipairs(choice.options) do
      local y = top + #rows + i
      local sel = i == choice.sel
      fill(t, 1, y, w, sel and "gray" or "black")
      put(t, 3, y, (sel and "> " or "  ") .. i .. ". " .. text.clip(o, text.OPTION), sel and "white" or "lightGray", sel and "gray" or "black")
    end
    fill(t, 1, h - 1, w, "black")
    put(t, 3, h - 1, "W/S or 1-" .. #choice.options .. " choose   ENTER/SPACE or click", "lightGray")
    return
  end
  if not line then return end
  local top = h - 6
  local who = line.who
  fill(t, 1, top, w, "gray")
  if who and who ~= "" then
    put(t, 2, top, " " .. who .. " ", speakerColour(idx, who), "gray")
  end
  local rows = talk:visibleRows()
  for i = 1, text.ROWS do
    fill(t, 1, top + i, w, "black")
    local r = rows[i]
    if r then put(t, 3, top + i, r, (who == "") and "lightGray" or "white") end
  end
  fill(t, 1, h - 1, w, "black")
  put(t, 3, h - 1, line.full and "ENTER/SPACE next   X skip talk" or "ENTER/SPACE show all   X skip talk", "lightGray")
  if line.full then put(t, w - 2, h - 1, "\31", "yellow") end
end

-- ---------------------------------------------------------------- the cutscene

--- Letterbox bars, the caption or title, the line of talk, the fade.
function M.drawCutscene(ctx, host, idx)
  local t = ctx.screen
  local w, h = t.getSize()
  local cut = host.cut
  if not cut then return end
  local shot = cut:shot()
  if not shot then return end
  local fade = cut:fade()
  if shot.black or fade > 0.55 then
    for y = 1, h do fill(t, 1, y, w, "black") end
  else
    for y = 1, 2 do fill(t, 1, y, w, "black") end
    for y = h - 4, h do fill(t, 1, y, w, "black") end
  end
  if shot.title then
    local lines = {}
    for l in (shot.title .. "\n"):gmatch("([^\n]*)\n") do
      for _, row in ipairs(text.wrap(l, w - 4)) do lines[#lines + 1] = row end
    end
    local top = math.floor((h - #lines) / 2)
    for i, l in ipairs(lines) do
      put(t, math.floor((w - #l) / 2) + 1, top + i, l, i == 1 and "yellow" or "lightGray")
    end
  end
  if shot.caption then
    local rows = text.wrap(shot.caption, w - 4)
    for i = 1, math.min(2, #rows) do
      put(t, math.floor((w - #rows[i]) / 2) + 1, h - 4 + i, rows[i], "white")
    end
  end
  if shot.say then
    local who, line = shot.say[1], shot.say[2]
    put(t, 3, h - 4, who, speakerColour(idx, who))
    local rows = text.wrap(line, text.TEXT)
    for i = 1, math.min(3, #rows) do put(t, 3, h - 4 + i, rows[i], "white") end
  end
  put(t, w - 14, 1, "X skip scene", "lightGray")
end

-- ---------------------------------------------------------------- failure and success

local FAIL_OPTIONS = { "Retry from the checkpoint", "Restart the job", "Give up" }

function M.drawFail(ctx, host, args)
  local t = ctx.screen
  local w, h = t.getSize()
  local top = math.floor(h / 2) - 4
  for y = top, top + 9 do fill(t, 5, y, w - 8, "black") end
  put(t, math.floor((w - 14) / 2) + 1, top + 1, "MISSION FAILED", "red")
  local reason = text.clip((host.failed and host.failed.reason) or "", w - 12)
  put(t, math.floor((w - #reason) / 2) + 1, top + 2, reason, "white")
  local cp = host.failed and host.failed.checkpoint
  if cp then put(t, 8, top + 4, "Checkpoint: " .. text.clip(cp:gsub("_", " "), w - 24), "lightGray") end
  for i, o in ipairs(FAIL_OPTIONS) do
    local sel = i == (args.sel or 1)
    put(t, 8, top + 4 + i, (sel and "> " or "  ") .. o .. string.rep(" ", 26 - #o), sel and "white" or "lightGray", sel and "gray" or "black")
  end
  put(t, 8, top + 9, "W/S choose   ENTER/SPACE or click", "lightGray")
end

-- ---------------------------------------------------------------- where a click lands (the same layout as the draws)

--- The dialogue choice under a click at screen row y, or nil.
function M.choiceAt(ctx, host, y)
  local choice = host.talk and host.talk.choice
  if not choice then return nil end
  local _, h = ctx.screen.getSize()
  local top = h - (#choice.rows + #choice.options + 2)
  local i = y - (top + #choice.rows)
  if i >= 1 and i <= #choice.options then return i end
  return nil
end

--- The MISSION FAILED option (1 retry, 2 restart, 3 give up) under a click, or nil.
function M.failAt(ctx, x, y)
  local w, h = ctx.screen.getSize()
  local top = math.floor(h / 2) - 4
  local i = y - (top + 4)
  if i >= 1 and i <= #FAIL_OPTIONS and x >= 8 and x <= 8 + 28 then return i end
  return nil
end

--- The phone contact under a click, or nil.
function M.phoneAt(ctx, host, idx, x, y)
  local list = phoneLib.contacts(host.story, idx)
  local i = y - 2
  if i >= 1 and i <= #list and x >= 2 and x <= 18 then return i end
  return nil
end

function M.drawPass(ctx, host, args)
  local t = ctx.screen
  local w, h = t.getSize()
  local top = math.floor(h / 2) - 2
  for y = top, top + 4 do fill(t, 8, y, w - 14, "black") end
  put(t, math.floor((w - 8) / 2) + 1, top, "JOB DONE", "lime")
  local title = text.clip(args.title or "", w - 16)
  put(t, math.floor((w - #title) / 2) + 1, top + 1, title, "white")
  if args.sub then put(t, math.floor((w - #args.sub) / 2) + 1, top + 2, args.sub, "yellow") end
  put(t, math.floor((w - 20) / 2) + 1, top + 4, "ENTER/SPACE continue", "lightGray")
end

-- ---------------------------------------------------------------- the phone

--- The phone: contacts on the left, the thread or the call on the right.
function M.drawPhone(ctx, host, idx, args)
  local t = ctx.screen
  local w, h = t.getSize()
  for y = 1, h do fill(t, 1, y, w, "black") end
  put(t, 2, 1, " PHONE ", "black", "yellow")
  put(t, w - 12, 1, "T or P: back", "lightGray")
  local list = phoneLib.contacts(host.story, idx)
  args.sel = math.max(1, math.min(args.sel or 1, math.max(1, #list)))
  if #list == 0 then
    put(t, 3, 4, "No contacts yet.", "lightGray")
    put(t, 3, 5, "Do a favour for someone.", "lightGray")
    return
  end
  for i, c in ipairs(list) do
    local sel = i == args.sel
    local label = text.pad((sel and "> " or "  ") .. c.name, 16)
    put(t, 2, 2 + i, label, sel and "white" or "lightGray", sel and "gray" or "black")
    if c.unread > 0 then put(t, 18, 2 + i, "*", "yellow", sel and "gray" or "black") end
  end
  local c = list[args.sel]
  local x0 = 21
  local width = w - x0 - 1
  put(t, x0, 2, text.clip(c.name, width), speakerColour(idx, c.name), "black")
  local blurb = text.wrap(c.blurb or "", width)
  for i = 1, math.min(2, #blurb) do put(t, x0, 2 + i, blurb[i], "lightGray") end
  if args.mode == "call" then
    local y = 6
    for _, l in ipairs(args.lines or {}) do
      put(t, x0, y, l[1] .. ":", speakerColour(idx, l[1]))
      y = y + 1
      for _, row in ipairs(text.wrap(l[2], width)) do
        if y < h - 1 then put(t, x0, y, row, "white") end
        y = y + 1
      end
    end
    put(t, x0, h - 1, "ENTER/SPACE hang up", "lightGray")
    return
  end
  local thread = phoneLib.thread(host.story, c.id)
  local y = 6
  local first = math.max(1, #thread - 3)
  for i = first, #thread do
    for _, row in ipairs(text.wrap(thread[i].text, width)) do
      if y < h - 2 then put(t, x0, y, row, thread[i].read and "lightGray" or "white") end
      y = y + 1
    end
    y = y + 1
  end
  if #thread == 0 then put(t, x0, 6, "No texts.", "gray") end
  put(t, x0, h - 1, "ENTER/SPACE call   W/S contacts", "lightGray")
end

-- ---------------------------------------------------------------- the HUD

--- The objective line (with an arrow and a distance), the clock, and a toast.
function M.hud(ctx, host, idx, state)
  local ui = ctx.ui
  ui.widget({ name = "d_objective", slot = "objective", priority = 1, visible = function() return host:objectiveInfo() ~= nil end,
    draw = function(c, t)
      local info = host:objectiveInfo()
      if not info then return end
      local w = (t.getSize())
      fill(t, 1, 2, w, "black")
      local label = info.text
      local tx, tz
      if info.target ~= nil and host.world.pos then
        tx, tz = host.world:pos(info.target)
      end
      local suffix = ""
      if tx and c.player then
        local p = host.world:player()
        local yaw = (c.view and c.view.camYaw) or c.player.h or 0
        local word, d = hints.direction(p.x, p.z, yaw, tx, tz)
        suffix = " " .. hints.ARROWS[word] .. math.floor(d) .. "m"
      end
      put(t, 2, 2, text.clip(label, w - 3 - #suffix), "white")
      if suffix ~= "" then put(t, w - #suffix, 2, suffix, "yellow") end
    end })
  ui.widget({ name = "d_clock", slot = "top-right", priority = 20, visible = function() return host.timer ~= nil and host.state == "running" end,
    draw = function(c, t)
      local tm = host.timer
      if not tm then return end
      local w = (t.getSize())
      local secs = math.max(0, math.ceil(tm.left))
      local s = string.format(" %s %d:%02d ", tm.text, math.floor(secs / 60), secs % 60)
      put(t, w - #s, 1, s, secs <= 10 and "white" or "black", secs <= 10 and "red" or "yellow")
    end })
  ui.widget({ name = "d_toast", slot = "centre", priority = 30, visible = function() return state.toast ~= nil end,
    draw = function(c, t)
      local to = state.toast
      if not to then return end
      local w, h = t.getSize()
      local msg = text.clip(to.text, w - 6)
      local y = math.floor(h / 3)
      local fg = (to.kind == "alarm") and "red" or ((to.kind == "text") and "cyan" or "yellow")
      fill(t, 3, y, w - 4, "black")
      put(t, math.floor((w - #msg) / 2) + 1, y, msg, fg)
      if to.sub then
        fill(t, 3, y - 1, w - 4, "black")
        put(t, math.floor((w - #to.sub - 6) / 2) + 1, y - 1, "TEXT: " .. to.sub, "lightGray")
      end
    end })
end

return M
