-- plugins/d_story.lua
-- Stream D: the story. Three acts of missions told by scripts (content/story/), told through the dialogue box,
-- the cutscene player and the phone. This plugin builds the story host over the game's context, registers its screens and
-- HUD, saves the checkpoint in the save's story section, cues the music, and offers each mission when you reach its giver.
--
-- Needs from the core loop (see EXPANSION.md, stream D notes):
--   * the top screen's input(ctx, inp, dt) and (when modal) update(ctx, dt) are called each frame (the ui contract)
--   * this plugin's input(ctx, inp) is called each frame while playing (it adds the phone key, T)
-- Public: ctx.story = { host, world, idx } (the minimap can read ctx.story.target() -> x, z, kind).

local indexLib = require("sg.story.index")
local hostLib = require("sg.story.host")
local worldLib = require("sg.story.world")
local screens = require("sg.story.screens")
local phoneLib = require("sg.story.phone")

local M = { name = "d_story", order = 60 }

local TOAST_SECONDS = 3.4

local musicMod
local function musicCue(cue)
  if musicMod == nil then
    local ok, m = pcall(require, "music")
    musicMod = (ok and type(m) == "table") and m or false
  end
  if musicMod and musicMod.cue then pcall(musicMod.cue, cue) end
end

--- Make the cutscene camera work: the view's camera goes where the cutscene says while view.override is set.
local function patchCamera(view)
  if not view or view.d_patched or type(view.camera) ~= "function" then return end
  local orig = view.camera
  view.d_patched = true
  view.camera = function(self, ctx, dt)
    orig(self, ctx, dt)
    local o = self.override
    if o and self.r and self.r.frame then
      self.cam = o
      self.r.cam = o
      self.r.frame:setCamera(o.x, o.y, o.z, 0, math.deg(o.yaw), o.pitch)
    end
  end
end

function M.init(ctx)
  local idx, err = indexLib.load(ctx.content)
  if not idx then
    ctx.log("story: " .. tostring(err))
    error("the story's index did not load: " .. tostring(err))
  end
  local world = worldLib.new(ctx, idx.places)
  local state = { toast = nil, toastLeft = 0, queue = {} }
  local host
  host = hostLib.new({
    bus = ctx.bus, world = world, list = idx, script = idx.script, music = musicCue, log = ctx.log,
    onSave = function() end,
  })
  ctx.story = { host = host, world = world, idx = idx }
  ctx.story.target = function()
    local info = host:objectiveInfo()
    if info and info.target ~= nil then
      local x, z = world:pos(info.target)
      if x then return x, z, "objective" end
    end
    if host.state == "idle" and host.story then
      local def = host:next()
      if def then
        local x, z = world:pos(def.giver)
        if x then return x, z, "giver" end
      end
    end
  end
  patchCamera(ctx.view)

  -- the save
  ctx.bus:on("load", function(d)
    host:bind(d.data.story)
    host:resume()
  end, "d_story")
  ctx.bus:on("save", function(d)
    if host.story then
      host:export()
      d.data.story = host.story
    end
  end, "d_story")
  if ctx.save and ctx.save.story then
    host:bind(ctx.save.story)
  end

  -- screens
  local ui = ctx.ui
  local function backdrop(c, dt)
    if c.view and c.view.draw then c.view:draw(c, dt) end
  end

  ui.screen({ name = "d_talk", modal = true,
    draw = function(c, dt)
      backdrop(c, 0)
      screens.drawTalk(c, host, idx)
    end,
    update = function(c, dt)
      host:tickUI(dt)
      if host.state ~= "running" or not host.talk:talking() then ui.pop() end
    end,
    input = function(c, inp)
      local talk = host.talk
      if inp:pressedAction("skip") then talk:skipAll() end
      if talk.choice then
        if inp:pressedAction("up") then talk:move(-1) end
        if inp:pressedAction("down") then talk:move(1) end
        for n = 1, 4 do
          if inp:pressedAction("n" .. n) then talk:pick(n) end
        end
      end
      if inp:pressedAction("advance") then talk:advance() end
    end })

  ui.screen({ name = "d_cutscene", modal = true,
    draw = function(c, dt)
      local cut = host.cut
      if cut and c.view then
        local cam = cut:camera()
        c.view.override = cam
      end
      backdrop(c, 0)
      screens.drawCutscene(c, host, idx)
    end,
    update = function(c, dt)
      host:tickUI(dt)
      if host.state ~= "running" or not host.cut then
        if c.view then c.view.override = nil end
        ui.pop()
      end
    end,
    input = function(c, inp)
      local cut = host.cut
      if not cut then return end
      if inp:pressedAction("skip") then cut:skip() end
      if inp:pressedAction("advance") then cut:next() end
      if cut.done then host.cut, host.cutDone = nil, true end
    end })

  ui.screen({ name = "d_fail", modal = true,
    draw = function(c, dt)
      backdrop(c, 0)
      local _, args = ui.top()
      screens.drawFail(c, host, args or {})
    end,
    input = function(c, inp)
      local _, args = ui.top()
      args.sel = args.sel or 1
      if inp:pressedAction("up") then args.sel = (args.sel - 2) % 3 + 1 end
      if inp:pressedAction("down") then args.sel = args.sel % 3 + 1 end
      for n = 1, 3 do
        if inp:pressedAction("n" .. n) then args.sel = n end
      end
      if inp:pressedAction("advance") then
        local pick = args.sel
        ui.pop()
        if pick == 1 then
          host:retry("checkpoint")
        elseif pick == 2 then
          host:retry("restart")
        else
          host:giveUp()
        end
      end
    end })

  ui.screen({ name = "d_pass", modal = true,
    draw = function(c, dt)
      backdrop(c, 0)
      local _, args = ui.top()
      screens.drawPass(c, host, args or {})
    end,
    update = function(c, dt)
      local _, args = ui.top()
      args.t = (args.t or 0) + dt
      if args.t > 12 then
        ui.pop()
        host:acknowledge()
      end
    end,
    input = function(c, inp)
      if inp:pressedAction("advance") then
        ui.pop()
        host:acknowledge()
      end
    end })

  ui.screen({ name = "d_phone", modal = true,
    draw = function(c, dt)
      local _, args = ui.top()
      screens.drawPhone(c, host, idx, args or {})
    end,
    input = function(c, inp)
      local _, args = ui.top()
      local list = phoneLib.contacts(host.story, idx)
      if inp:pressedAction("phone") or inp:pressedAction("pause") then
        ui.pop()
        return
      end
      if args.mode == "call" then
        if inp:pressedAction("advance") then args.mode, args.lines = nil, nil end
        return
      end
      if inp:pressedAction("up") then args.sel = math.max(1, (args.sel or 1) - 1) end
      if inp:pressedAction("down") then args.sel = math.min(#list, (args.sel or 1) + 1) end
      local c1 = list[args.sel or 1]
      if c1 then phoneLib.markRead(host.story, c1.id) end
      if c1 and inp:pressedAction("advance") then
        args.mode = "call"
        args.lines = phoneLib.call(host.story, idx, c1.id, host.state == "running" and host.hint or nil)
      end
    end })

  screens.hud(ctx, host, idx, state)

  -- the plugin's own frame
  M.update = function(c, dt)
    world:update(dt)
    host:update(dt)
    if state.toast then
      state.toastLeft = state.toastLeft - dt
      if state.toastLeft <= 0 then state.toast = nil end
    end
    local cards = host.cards
    while #cards > 0 do
      local card = table.remove(cards, 1)
      if card.kind == "pass" then
        ui.push("d_pass", { title = card.text, sub = card.sub })
      else
        state.queue[#state.queue + 1] = card
      end
    end
    if not state.toast and #state.queue > 0 then
      state.toast = table.remove(state.queue, 1)
      state.toastLeft = TOAST_SECONDS
      if state.toast.kind == "text" and idx.phone.contacts[state.toast.sub] then
        state.toast.sub = idx.phone.contacts[state.toast.sub].name
      end
    end
    if host.state == "running" then
      if host.cut then
        if not ui.has("d_cutscene") then ui.push("d_cutscene") end
      elseif host.talk:talking() then
        if not ui.has("d_talk") then ui.push("d_talk") end
      end
    elseif host.state == "failed" then
      if not ui.has("d_fail") then ui.push("d_fail", { sel = 1 }) end
    end
  end

  M.input = function(c, inp)
    if not inp.map.phone then
      local k = inp.keys or {}
      inp.map.phone = { k.t }
      inp.map.punch = { k.g }
      inp.map.n1, inp.map.n2, inp.map.n3, inp.map.n4 = { k.one }, { k.two }, { k.three }, { k.four }
    end
    local top = ui.top()
    if top and top.name == "play" then
      if inp:pressedAction("phone") then
        ui.push("d_phone", { sel = 1 })
      end
      if inp:pressedAction("punch") then world.punch = true end
    end
  end
end

return M
