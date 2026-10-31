-- table.lua
-- A casino table: one game on one 6x6 monitor wall. Every game plugs in rules (pure) and a view (drawing).
--
-- A round's money moves once, when its result is known, and before the final reveal plays:
--   open    the bet is chosen and nothing moves. The round is journaled at every decision, so a reboot resumes it.
--   settle  the net result moves to or from the seated player, named, so nobody else's touch matters.
--   owed    whatever could not move is written down and settled the next time that player sits here.
--
-- Rules module: new(wager, rng, keep, env) -> state, events; actions(state) -> { {id, label, color, cost, sub} };
--   act(state, id, rng) -> events; auto(state) -> id; done(state); net(state); risk(state); result(state) -> {kind,title,detail};
--   finish(state, keep); maxWin(wager) -> biggest net win, in tokens.
-- View module: new(ctx) -> model; sync(model, state); event(model, ev) -> seconds, sound; commit(model, ev);
--   draw(c, model, state, anim) where anim is { ev, t } while an event plays.
--   view.attract(c, t) (optional): the idle screen's art, in place of the fanned cards. y from 52 is free.
--   view.regions(model, state) (optional) -> { {id, x, y, w, h} }: parts of the table a touch can act on, passed to act().
--   An action id of any kind goes to rules.act, so a game can use ids such as "hold3".
-- game: { id, title, felt, tagline, rules, view, help(), capTokens, stakeOf(wager) (optional),
--   bet(ctx, table, lastWager) (optional): its own bet scene for games with several bets. Run it with table:run(scene),
--   check table:liabilityRoom() against rules.maxWin(wager), and return the wager, or nil when the player leaves. }

local audio = require("lib.casino.audio")
local canvas = require("lib.casino.canvas")
local journal = require("lib.casino.journal")
local limits = require("lib.casino.limits")
local net = require("lib.casino.net")
local presence = require("lib.casino.presence")
local rng = require("lib.casino.rng")
local stats = require("lib.casino.stats")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local wallet = require("lib.casino.wallet")

local C = theme.C
local M = {}

local FRAME = 0.1
local IDLE_DECISION_MS = 60000   -- no touch for this long: the round plays its safe default. Pressing a button is a touch, so a slow decision still pays at once
local IDLE_HERE_MS = 300000      -- the same, for a player the detector can see at the table
local GONE_GRACE_MS = 5000       -- the detector has missed them this long: they left, so finish while their touch still lets the money move
local IDLE_BET_MS = 45000        -- no touch on the bet screen: the player has left
local IDLE_RESULT_MS = 30000
local RESUME_WAIT_MS = 90000     -- how long a resumed round waits for its player
local COLLECT_WAIT_MS = 25000
local WARN_MS = 10000
local LOG_FILE = "casino.log"
local LOG_MAX_BYTES = 100000
local BIG_WIN_TIMES = 10
local MIN_W, MIN_H = 120, 80     -- a 6x6 wall at text scale 0.5 is 121x81

local function now()
  return os.epoch("utc")
end

local function log(message)
  if fs.exists(LOG_FILE) and fs.getSize(LOG_FILE) > LOG_MAX_BYTES then
    if fs.exists(LOG_FILE .. ".bak") then fs.delete(LOG_FILE .. ".bak") end
    fs.move(LOG_FILE, LOG_FILE .. ".bak")
  end
  local handle = fs.open(LOG_FILE, "a")
  if handle then
    handle.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message))
    handle.close()
  end
end

local function largestMonitor()
  local best, bestArea = nil, 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "monitor") then
      local monitor = peripheral.wrap(name)
      monitor.setTextScale(0.5)
      local w, h = monitor.getSize()
      if w * h > bestArea then best, bestArea = name, w * h end
    end
  end
  return best
end

-- ------------------------------------------------------------------ the event loop

local Table = {}
Table.__index = Table

--- Run a scene until it says it is finished. Input stays live through every animation.
-- A scene has draw(self), and optionally touch(self, x, y, who) and tick(self, dt).
function Table:run(scene)
  local previous = self.scene
  self.scene = scene
  scene.dirty = true
  -- One frame timer is always pending, whichever scene is on top, so a page opened from a scene hands it back
  self.timer = self.timer or os.startTimer(FRAME)
  local last = now()
  while not scene.finished do
    local event, a, b, c = os.pullEvent()
    if event == "vhcc_touch" then
      self.toucher = a
    elseif event == "monitor_touch" and a == self.monitorName then
      local who = self.toucher or wallet.livePlayer()
      self.toucher = nil
      if self.ctx.seat and who ~= self.ctx.seat and not scene.anyone then
        self:toast("Table in use by " .. self.ctx.seat)
      elseif scene.touch then
        scene:touch(b, c, who)
        scene.dirty = true
      end
    elseif event == "monitor_resize" and a == self.monitorName then
      self:attachCanvas()
      scene.dirty = true
    elseif event == "timer" and a == self.timer then
      local time = now()
      local dt = (time - last) / 1000
      last = time
      if scene.tick then scene:tick(dt) end
      self:heartbeat(time)
      if self.toastUntil and time > self.toastUntil then
        self.toastUntil, self.toastText = nil, nil
        scene.dirty = true
      end
      if scene.dirty or scene.animating then
        scene.dirty = false
        scene:draw()
        self:drawToast()
        self.c:flush()
        if self.debug then self:writeDebug(scene) end
      end
      self.timer = os.startTimer(FRAME)
    end
  end
  self.scene = previous
  if previous then previous.dirty = true end
end

--- The supervisor reboots a table that goes silent, which is how it notices a hung game. This says the game is alive.
function Table:heartbeat(time)
  if time - (self.lastBeat or 0) > 5000 then
    self.lastBeat = time
    os.queueEvent("roger_alive")
    net.tick()
    self:refreshBalance()
  end
end

--- With casino_debug.flag on the computer, write what is on screen for the test suites to read.
function Table:writeDebug(scene)
  local buttons = {}
  for _, b in ipairs(scene.buttons or {}) do
    buttons[#buttons + 1] = { id = b.id, value = b.value, x = b.x, y = b.y, w = b.w, h = b.h, label = b.label }
  end
  local handle = fs.open("casino_ui.dat", "w")
  if handle then
    handle.write(textutils.serializeJSON({
      scene = scene.name or "?",
      buttons = buttons,
      seat = self.ctx.seat or false,
      balance = self.ctx.balance or false,
      playing = scene.playing ~= nil or (scene.queue ~= nil and #scene.queue > 0),
      w = self.c.w,
      h = self.c.h,
      toast = self.toastText or false,
      host = wallet.hostName() or false,
      hostBalance = wallet.hostBalance() or false,
      state = scene.debugState and scene.debugState() or false,
    }))
    handle.close()
  end
end

function Table:toast(text)
  self.toastText = text
  self.toastUntil = now() + 2500
  audio.play("error")
  if self.scene then self.scene.dirty = true end
end

function Table:drawToast()
  if not self.toastText then return end
  local c = self.c
  local w = #self.toastText + 4
  local x = math.floor((c.w - w) / 2)
  c:rect(x, 10, w, 3, C.orange)
  c:text(x + 2, 11, self.toastText, C.ink, C.orange)
end

function Table:attachCanvas()
  self.monitor = peripheral.wrap(self.monitorName)
  self.monitor.setTextScale(0.5)
  theme.apply(self.monitor, self.game.felt)
  self.c = canvas.new(self.monitor)
  self.ctx.c = self.c
end

-- ------------------------------------------------------------------ money

function Table:refreshBalance()
  local ctx = self.ctx
  if ctx.seat then ctx.balance = wallet.balance(ctx.seat) or ctx.balance end
  ctx.jackpot = self:jackpotValue()
end

function Table:jackpotValue()
  local rules = self.game.rules
  if not rules.JACKPOT then return nil end
  local hub = net.hub()
  if hub and hub.jackpot then return hub.jackpot end
  return self.keep.pot or rules.JACKPOT.seed
end

function Table:maxBet()
  local host = wallet.hostName()
  local balance = wallet.hostBalance() or 0
  return limits.maxBet(balance, net.otherExposure(host), self.game.rules.maxWin(1), self.game.capTokens)
end

--- The biggest net win a single round may promise right now, for games with several bets at once.
function Table:liabilityRoom()
  local balance = wallet.hostBalance() or 0
  return math.floor(limits.protected(balance, net.otherExposure(wallet.hostName())) * limits.LIABILITY_SHARE)
end

function Table:setExposure(amount)
  net.setExposure(wallet.hostName(), amount)
end

--- Try to move what a round left owed. Returns what is still left.
function Table:settleOwed(name)
  local owed = journal.owedTo(name)
  if owed == 0 then return 0 end
  local moved, left, err = wallet.settle(name, owed, self.game.title .. " owed")
  if moved ~= 0 then
    journal.addOwed(name, -moved)
    log("owed " .. name .. " moved " .. moved .. " left " .. left)
  elseif err then
    log("owed " .. name .. " unmoved: " .. tostring(err))
  end
  self:refreshBalance()
  return left
end

--- Close a round's books: the only place a round moves money.
function Table:settle(round)
  local rules = self.game.rules
  self:claimJackpot(round)
  local netResult = rules.net(round.state)
  local reason = self.game.title .. " #" .. round.id
  round.net = netResult
  round.phase = "settling"
  journal.saveRound(round)

  local moved, left, err = 0, netResult, nil
  if netResult ~= 0 then
    moved, left, err = wallet.settle(round.player, netResult, reason)
  end
  if left ~= 0 then
    journal.addOwed(round.player, left)
    log("round " .. round.id .. " " .. round.player .. " left owed " .. left .. ": " .. tostring(err))
  end
  round.left = left
  round.phase = "settled"

  stats.record(round.player, round.stake, netResult)
  net.send("round", { game = self.game.id, player = round.player, wagered = round.stake, net = netResult })
  if rules.JACKPOT then self:jackpotRound(round) end
  rules.finish(round.state, self.keep)
  journal.saveKeep(self.keep)
  journal.clearRound()
  self:setExposure(0)
  self:refreshBalance()
  log(("round %s %s %s stake=%d net=%d left=%d seed=%s"):format(round.id, self.game.id, round.player,
    round.stake, netResult, left, round.seed))
end

--- With a hub alive the pot is the hub's, and the figure a round opened with can be stale. Ask it what may be paid
-- before any money moves, so two tables cannot pay the same pot. With no answer, pay only the seed, which is always there.
-- A rules module's net must read state.jackpotHit. The claim id repeats on a retry, so the hub answers it the same way.
function Table:claimJackpot(round)
  local rules = self.game.rules
  if not (rules.JACKPOT and round.state.jackpotHit) or round.claim or not net.hub() then return end
  round.claim = round.id
  local granted = net.claim({ id = round.id, game = self.game.id, player = round.player, amount = round.state.jackpotHit })
  round.state.jackpotHit = math.min(round.state.jackpotHit, granted or rules.JACKPOT.seed)
  -- The wait above can swallow the frame timer
  self.timer = os.startTimer(FRAME)
end

function Table:jackpotRound(round)
  local rules = self.game.rules
  local share = math.floor(round.stake * rules.JACKPOT.share)
  if round.state.jackpotHit then
    -- A capped win leaves the rest of the pot for the next one
    local pot = self.keep.pot or rules.JACKPOT.seed
    self.keep.pot = math.max(rules.JACKPOT.seed, pot - round.state.jackpotHit)
    net.send("jackpot", { game = self.game.id, player = round.player, amount = round.state.jackpotHit, claim = round.claim })
  else
    self.keep.pot = (self.keep.pot or rules.JACKPOT.seed) + share
    net.send("pot", { amount = share })
  end
end

-- ------------------------------------------------------------------ scenes

local function feltBase(c)
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
end

--- The idle screen: the game's name and an invitation.
function Table:attract(message)
  local c, ctx, game = self.c, self.ctx, self.game
  local scene = { name = "attract", anyone = true, animating = true, t = 0 }

  function scene.tick(s, dt)
    s.t = s.t + dt
  end

  function scene.draw(s)
    feltBase(c)
    local cx = math.floor(c.w / 2)
    if game.view.attract then
      game.view.attract(c, s.t)
    else
      for i = 1, 5 do
        local phase = s.t * 0.7 + i * 1.3
        local x = cx - 40 + (i - 1) * 18
        local y = 52 + math.floor(math.sin(phase) * 2)
        ui.card(c, x, y, (i * 11 + math.floor(s.t / 3)) % 52, false)
      end
    end
    local titleScale = c:bigWidth(game.title, 3) <= c.w - 6 and 3 or 2 -- a long name must still fit the wall
    c:bigCenter(cx, titleScale == 3 and 14 or 18, game.title, C.gold, titleScale)
    c:textCenter(cx, 36, game.tagline or "", C.text)
    if math.floor(s.t * 1.5) % 2 == 0 then
      c:bigCenter(cx, 42, "TOUCH TO PLAY", C.text, 1)
    end
    if ctx.jackpot then
      c:textCenter(cx, 49, "JACKPOT " .. ui.group(ctx.jackpot) .. " TOKENS", C.win)
    end
    if message then c:textCenter(cx, c.h - 3, message, C.orange) end
  end

  function scene.touch(s, _, _, who)
    s.who = who or wallet.livePlayer()
    if s.who then s.finished = true end
  end

  self:run(scene)
  return scene.who
end

--- Seat a player: their approval in chat is what lets the table reach their wallet.
function Table:seat(name)
  local c, ctx = self.c, self.ctx
  if wallet.isApproved() then
    ctx.seat = name
    return true
  end
  local sent, err = wallet.requestApproval()
  if not sent and not tostring(err):find("pending", 1, true) then
    log("approval request failed: " .. tostring(err))
    self:notice("Could not ask for approval", tostring(err))
    return false
  end

  local scene = { name = "approve", anyone = true, deadline = now() + 60000 }

  function scene.tick(s)
    if wallet.isApproved() then
      s.ok, s.finished = true, true
    elseif now() > s.deadline then
      s.finished = true
    end
    s.dirty = true
  end

  function scene.draw(s)
    feltBase(c)
    local cx = math.floor(c.w / 2)
    c:bigCenter(cx, 16, "WELCOME", C.gold, 2)
    c:bigCenter(cx, 32, name, C.text, 1)
    c:textCenter(cx, 42, "Click [APPROVE] in chat to let this table use your wallet.", C.text)
    c:textCenter(cx, 44, "Nothing is charged until a round ends.", C.mute)
    c:textCenter(cx, 48, math.max(0, math.ceil((s.deadline - now()) / 1000)) .. "s", C.gold)
  end

  self:run(scene)
  if scene.ok then
    ctx.seat = name
    return true
  end
  return false
end

function Table:notice(title, detail)
  local c = self.c
  local scene = { name = "notice", anyone = true, deadline = now() + 5000 }
  function scene.tick(s)
    if now() > s.deadline then s.finished = true end
  end
  function scene.draw()
    feltBase(c)
    ui.banner(c, 30, title, detail, C.orange)
  end
  function scene.touch(s)
    s.finished = true
  end
  self:run(scene)
end

--- A pager over lines of small text: rules, stats.
function Table:page(title, lines)
  local c, ctx = self.c, self.ctx
  local perPage = c.h - ui.BAR_H - ui.ACTIONS_H - 5
  local scene = { name = "page", index = 1, deadline = now() + IDLE_BET_MS }
  local wrapped = {}
  for _, line in ipairs(lines) do
    local text = type(line) == "table" and line[1] or line
    local color = type(line) == "table" and line[2] or C.text
    if text == "" then
      wrapped[#wrapped + 1] = { "", color }
    else
      for _, part in ipairs(ui.wrap(text, c.w - 8)) do wrapped[#wrapped + 1] = { part, color } end
    end
  end
  local pages = math.max(1, math.ceil(#wrapped / perPage))

  function scene.tick(s)
    if now() > s.deadline then s.finished = true end
  end

  function scene.draw(s)
    feltBase(c)
    ui.bar(c, ctx)
    c:big(4, ui.BAR_H + 1, title, C.gold, 1)
    c:text(c.w - 10, ui.BAR_H + 2, s.index .. "/" .. pages, C.mute)
    local y = ui.BAR_H + 9
    for i = (s.index - 1) * perPage + 1, math.min(#wrapped, s.index * perPage) do
      c:text(5, y, wrapped[i][1], wrapped[i][2])
      y = y + 1
    end
    s.buttons = ui.newButtons()
    ui.actionBar(c, s.buttons, {
      { id = "prev", label = "BACK", color = C.panel2, disabled = s.index == 1 },
      { id = "next", label = "NEXT", color = C.blue, disabled = s.index == pages },
      { id = "close", label = "DONE", color = C.win, textColor = C.ink },
    })
  end

  function scene.touch(s, x, y)
    s.deadline = now() + IDLE_BET_MS
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    audio.play("tap")
    if hit.id == "prev" then s.index = s.index - 1 end
    if hit.id == "next" then s.index = s.index + 1 end
    if hit.id == "close" then s.finished = true end
  end

  self:run(scene)
end

function Table:statsPage()
  local ctx = self.ctx
  local mine = stats.player(ctx.seat)
  local lines = {
    { "YOUR RECORD AT THIS TABLE", C.gold },
    "Rounds played: " .. ui.group(mine.rounds),
    "Total wagered: " .. ui.group(mine.wagered),
    "Net result: " .. ui.signed(mine.net),
    "Best win: " .. ui.group(mine.best),
    "",
  }
  local hub = net.hub()
  local leaders = hub and hub.leaders or stats.leaders(8)
  lines[#lines + 1] = { hub and "CASINO LEADERS" or "LEADERS AT THIS TABLE", C.gold }
  for i, entry in ipairs(leaders) do
    lines[#lines + 1] = i .. ". " .. entry.name .. "  " .. ui.signed(entry.net)
  end
  self:page("STATS", lines)
end

--- The standard bet screen. Chips add up, nothing moves. Returns a bet, or nil when the player leaves.
function Table:chooseBet(lastBet)
  local c, ctx = self.c, self.ctx
  local scene = { name = "bet", bet = 0, deadline = now() + IDLE_BET_MS }
  local maxBet = self:maxBet()
  local chips = limits.chips(maxBet)
  local cx = math.floor(c.w / 2)

  local function clamp(s)
    local balance = ctx.balance or 0
    s.bet = math.min(s.bet, maxBet, balance)
  end

  function scene.tick(s)
    local left = s.deadline - now()
    if left <= 0 then s.finished = true end
    if left < WARN_MS then s.dirty = true end
  end

  function scene.draw(s)
    feltBase(c)
    ui.bar(c, ctx)
    c:bigCenter(cx, 11, "PLACE YOUR BET", C.text, 1)
    c:textCenter(cx, 38, "Table limit " .. ui.group(maxBet), C.text)
    c:bigCenter(cx, 20, ui.group(s.bet), C.gold, 3)
    s.buttons = ui.newButtons()
    if maxBet < 1 then
      c:textCenter(cx, 44, "The house cannot cover a bet right now.", C.orange)
    else
      local specs = {}
      for _, value in ipairs(chips) do
        local label = value >= 1000 and (value / 1000 .. "K") or tostring(value)
        specs[#specs + 1] = { id = "chip", value = value, label = label, color = C.accent, textColor = C.ink }
      end
      ui.actionRow(c, s.buttons, specs, 42, 11)
      ui.actionRow(c, s.buttons, {
        { id = "clear", label = "CLEAR", color = C.panel2 },
        { id = "double", label = "X2", color = C.panel2, disabled = s.bet == 0 },
        { id = "max", label = "MAX", color = C.panel2 },
        { id = "repeat", label = "SAME", color = C.panel2, disabled = not lastBet },
      }, 55, 9)
    end
    if ctx.owedNotice then c:textCenter(cx, 66, ctx.owedNotice, C.orange) end
    local left = s.deadline - now()
    if left < WARN_MS then
      c:textCenter(cx, 40, "Leaving in " .. math.ceil(left / 1000) .. "s", C.orange)
    end
    ui.actionBar(c, s.buttons, {
      { id = "leave", label = "LEAVE", color = C.red },
      { id = "rules", label = "RULES", color = C.blue },
      { id = "stats", label = "STATS", color = C.blue },
      { id = "deal", label = self.game.dealLabel or "DEAL", color = C.win, textColor = C.ink, disabled = s.bet < 1 },
    })
  end

  function scene.touch(s, x, y)
    s.deadline = now() + IDLE_BET_MS
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    if hit.id == "chip" then
      s.bet = s.bet + hit.value
      audio.play(hit.value >= 100 and "chipBig" or "chip")
    elseif hit.id == "clear" then
      s.bet = 0
      audio.play("tap")
    elseif hit.id == "double" then
      s.bet = s.bet * 2
      audio.play("chip")
    elseif hit.id == "max" then
      s.bet = maxBet
      audio.play("chipBig")
    elseif hit.id == "repeat" then
      s.bet = lastBet
      audio.play("chip")
    elseif hit.id == "leave" then
      audio.play("tap")
      s.finished = true
    elseif hit.id == "rules" then
      audio.play("tap")
      self:page("RULES", self.game.help())
    elseif hit.id == "stats" then
      audio.play("tap")
      self:statsPage()
    elseif hit.id == "deal" then
      audio.play("start")
      s.chosen, s.finished = true, true
    end
    clamp(s)
  end

  self:run(scene)
  self:refreshBalance()
  if scene.chosen and scene.bet >= 1 and scene.bet <= (ctx.balance or 0) then return scene.bet end
  return nil
end

--- Start a round: pick the seed, show its hash, save it before the first card.
function Table:openRound(wager)
  local rules = self.game.rules
  local seed = rng.freshSeed(self.ctx.seat)
  local stream = rng.new(seed)
  local env = { pot = self:jackpotValue() }
  local state, events = rules.new(wager, stream, self.keep, env)
  local round = {
    id = ("%x"):format(now() % 268435456),
    game = self.game.id,
    player = self.ctx.seat,
    wager = wager,
    stake = self.game.stakeOf and self.game.stakeOf(wager) or wager,
    seed = seed,
    commit = rng.sha256(seed),
    rng = stream:serial(),
    state = state,
    phase = "open",
  }
  journal.saveRound(round)
  self:setExposure(rules.maxWin(wager))
  return round, stream, events
end

--- Play a round to its end, new or resumed. Returns when the result has been shown and a choice made.
function Table:playRound(round, stream, firstEvents)
  local c, ctx, game = self.c, self.ctx, self.game
  local rules, view = game.rules, game.view
  local model = view.new(ctx)
  view.sync(model, round.state)

  local scene = { name = "play", animating = true, queue = firstEvents or {}, touched = now() }
  scene.debugState = function() return round.state end

  local function startNext(s)
    local ev = table.remove(s.queue, 1)
    if not ev then
      s.playing = nil
      return
    end
    local seconds, sound = view.event(model, ev)
    if sound then audio.play(sound) end
    s.playing = { ev = ev, t = 0, duration = math.max(seconds or 0, 0.01) }
  end

  local function finishPlaying(s)
    if s.playing then
      view.commit(model, s.playing.ev)
      s.playing = nil
    end
  end

  local function skipAll(s)
    finishPlaying(s)
    while #s.queue > 0 do
      local ev = table.remove(s.queue, 1)
      view.event(model, ev)
      view.commit(model, ev)
    end
  end

  local function apply(s, id)
    local events = rules.act(round.state, id, stream)
    round.rng = stream:serial()
    for _, ev in ipairs(events) do s.queue[#s.queue + 1] = ev end
    s.touched = now()
    if rules.done(round.state) then
      -- The money moves now, before the reveal plays, so nothing that happens during it can change the result
      self:settle(round)
      s.settled = true
    else
      journal.saveRound(round)
    end
  end

  function scene.tick(s, dt)
    if s.playing then
      s.playing.t = s.playing.t + dt / s.playing.duration
      if s.playing.t >= 1 then finishPlaying(s) end
    end
    if not s.playing then startNext(s) end
    if s.playing then return end
    if s.settled then
      s.finished = true
      return
    end
    local time = now()
    local away = presence.awayMs(ctx.seat)
    local left = s.touched + (away == 0 and IDLE_HERE_MS or IDLE_DECISION_MS) - time
    if away and away > 0 then left = math.min(left, GONE_GRACE_MS - away) end
    if left <= 0 then
      -- All the way to the end at once: nobody is here, so the table should not sit through more decisions or play them out
      repeat apply(s, rules.auto(round.state)) until rules.done(round.state)
      skipAll(s)
    elseif left < WARN_MS then
      s.warn = math.ceil(left / 1000)
    else
      s.warn = nil
    end
  end

  function scene.draw(s)
    view.draw(c, model, round.state, s.playing)
    ui.bar(c, ctx, ui.group(round.stake))
    s.buttons = ui.newButtons()
    if not s.playing and #s.queue == 0 and not s.settled then
      local specs = {}
      local room = (ctx.balance or 0) - (rules.risk and rules.risk(round.state) or 0)
      for _, action in ipairs(rules.actions(round.state)) do
        local spec = { id = action.id, label = action.label, color = C[action.color or "blue"],
          textColor = C[action.textColor or "text"], sub = action.sub }
        if action.cost and action.cost > room then
          spec.disabled, spec.sub = true, "need " .. ui.group(action.cost)
        end
        specs[#specs + 1] = spec
      end
      ui.actionBar(c, s.buttons, specs)
      -- Tappable parts of the table itself, such as cards to hold
      if view.regions then
        for _, region in ipairs(view.regions(model, round.state)) do s.buttons[#s.buttons + 1] = region end
      end
      if s.warn then
        c:textCenter(math.floor(c.w / 2), c.h - ui.ACTIONS_H - 1, "Auto-play in " .. s.warn .. "s, tap to wait", C.orange)
      end
    else
      c:rect(1, c.h - ui.ACTIONS_H + 1, c.w, ui.ACTIONS_H - 1, C.feltDark)
      c:textCenter(math.floor(c.w / 2), c.h - 5, "Tap to skip", C.feltLight)
    end
  end

  function scene.touch(s, x, y)
    if s.playing or #s.queue > 0 then
      skipAll(s)
      return
    end
    if s.settled then return end
    local hit = ui.hit(s.buttons or {}, x, y)
    if hit then
      audio.play("tap")
      apply(s, hit.id)
    else
      -- A tap anywhere means the player is still thinking
      s.touched = now()
    end
  end

  -- A round decided as it opens, such as a spin, has no decision to wait for: settle before the reveal plays
  if rules.done(round.state) then
    self:settle(round)
    scene.settled = true
  end

  self:run(scene)
  return self:showResult(round, model)
end

--- Show how the round ended, over the final table. Returns "again", "bet" or "leave".
function Table:showResult(round, model)
  local c, ctx, game = self.c, self.ctx, self.game
  local rules, view = game.rules, game.view
  local result = rules.result(round.state)
  local color = result.kind == "win" and C.win or result.kind == "push" and C.gold or C.red
  local bannerY = c.h - ui.ACTIONS_H - 14
  local stake = round.stake
  audio.play(result.kind == "win" and (round.net >= stake * BIG_WIN_TIMES and "bigWin" or "win")
    or result.kind == "push" and "push" or "lose")

  local scene = { name = "result", deadline = now() + IDLE_RESULT_MS, left = round.left or 0 }
  scene.debugState = function() return { net = round.net, left = scene.left, title = result.title } end

  function scene.tick(s)
    if now() > s.deadline then s.finished, s.choice = true, "leave" end
  end

  function scene.draw(s)
    view.draw(c, model, round.state, nil)
    ui.bar(c, ctx, ui.group(stake))
    local detail = result.detail or ""
    if round.net ~= 0 then detail = detail .. "  (" .. ui.signed(round.net) .. ")" end
    ui.banner(c, bannerY, result.title, detail, color)
    s.buttons = ui.newButtons()
    if s.left ~= 0 then
      c:textCenter(math.floor(c.w / 2), bannerY - 1,
        s.left > 0 and ("Owed to you: " .. ui.group(s.left)) or ("You still owe: " .. ui.group(-s.left)), C.orange)
      ui.actionBar(c, s.buttons, {
        { id = "collect", label = s.left > 0 and "COLLECT" or "SETTLE", color = C.win, textColor = C.ink },
        { id = "leave", label = "LEAVE", color = C.red },
      })
    else
      local again = stake <= (ctx.balance or 0) and rules.maxWin(round.wager) <= self:liabilityRoom()
        and stake <= (game.capTokens or stake)
      ui.actionBar(c, s.buttons, {
        { id = "again", label = "AGAIN", color = C.win, textColor = C.ink, disabled = not again },
        { id = "bet", label = "NEW BET", color = C.blue },
        { id = "fair", label = "FAIR?", color = C.panel2 },
        { id = "leave", label = "LEAVE", color = C.red },
      })
    end
  end

  function scene.touch(s, x, y)
    s.deadline = now() + IDLE_RESULT_MS
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    audio.play("tap")
    if hit.id == "collect" then
      -- Logging out ends a player's approval. This asks again, and the next touch collects
      if not wallet.isApproved() then wallet.requestApproval() end
      s.left = self:settleOwed(round.player)
      if s.left == 0 then audio.play("win") end
    elseif hit.id == "fair" then
      self:page("FAIR PLAY", {
        { "Before the deal this table fixed a secret seed and showed its hash.", C.text },
        "", { "Hash", C.gold }, round.commit,
        "", { "Seed, shown now the round is over", C.gold }, round.seed,
        "", "The SHA-256 of the seed must equal the hash. The seed drives ChaCha20, and that drives every shuffle.",
      })
    else
      s.choice, s.finished = hit.id, true
    end
  end

  self:run(scene)
  return scene.choice
end

--- A round the journal says was open: wait for its player, then carry on where it stopped.
function Table:resumeRound(round)
  local c, ctx, game = self.c, self.ctx, self.game
  local rules = game.rules
  local stream = rng.restore(round.rng)
  ctx.seat = nil

  local scene = { name = "resume", anyone = true, deadline = now() + RESUME_WAIT_MS }

  function scene.tick(s)
    if now() > s.deadline then s.finished = true end
    s.dirty = true
  end

  function scene.draw(s)
    feltBase(c)
    local cx = math.floor(c.w / 2)
    c:bigCenter(cx, 18, "ROUND IN PROGRESS", C.gold, 1)
    c:bigCenter(cx, 30, round.player, C.text, 2)
    c:textCenter(cx, 46, "Touch to carry on. Nothing has been charged.", C.text)
    c:textCenter(cx, 48, "This round plays itself in " .. math.max(0, math.ceil((s.deadline - now()) / 1000)) .. "s", C.mute)
  end

  function scene.touch(s, _, _, who)
    if who == round.player then
      s.back, s.finished = true, true
    else
      self:toast("Waiting for " .. round.player)
    end
  end

  self:run(scene)
  self:setExposure(rules.maxWin(round.wager))

  if scene.back and self:seat(round.player) then
    self:refreshBalance()
    if round.phase == "open" then
      return self:playRound(round, stream)
    end
  end

  -- They did not come back: the safe default finishes the round and the books remember the result
  while round.phase == "open" and not rules.done(round.state) do
    rules.act(round.state, rules.auto(round.state), stream)
    round.rng = stream:serial()
  end
  if round.phase == "open" then self:settle(round) end
  ctx.seat = nil
  return "leave"
end

--- Settle anything from before a crash that stopped between journaling a result and clearing it.
function Table:recover()
  local round = journal.loadRound()
  if not round then return end
  log("resuming round " .. tostring(round.id) .. " phase " .. tostring(round.phase))
  if round.phase == "open" then
    self.game.rules.resumed = true
    self:resumeRound(round)
  elseif round.phase == "settling" then
    -- The reboot landed inside settle(). If the transfer left no trace the round is still owed
    if not wallet.wasSettled("#" .. round.id) then
      journal.addOwed(round.player, round.net or 0)
    end
    journal.clearRound()
  else
    journal.clearRound()
  end
end

--- Play as the seated player until they leave.
function Table:session()
  local ctx, game = self.ctx, self.game
  if wallet.isSelfPlay(ctx.seat) then wallet.lockTerminal() end
  self:refreshBalance()

  local owed = journal.owedTo(ctx.seat)
  if owed ~= 0 then
    local left = self:settleOwed(ctx.seat)
    if left < 0 then
      self:notice("YOU OWE " .. ui.group(-left), "Bring tokens to clear it before playing here.")
      return
    elseif left == 0 then
      self:notice(owed > 0 and ("PAID " .. ui.group(owed)) or ("SETTLED " .. ui.group(-owed)), "From a round that could not finish before.")
    end
  end

  local lastWager = nil
  local wager = nil
  while true do
    if not wager then
      if game.bet then
        wager = game.bet(ctx, self, lastWager)
      else
        wager = self:chooseBet(lastWager)
      end
    end
    if not wager then return end
    lastWager = wager
    local round, stream, events = self:openRound(wager)
    local choice = self:playRound(round, stream, events)
    if choice == "leave" then return end
    wager = choice == "again" and lastWager or nil
  end
end

--- Run a table for ever.
function M.run(game)
  audio.init()
  net.open()
  local self = setmetatable({ game = game, keep = journal.loadKeep(), ctx = { title = game.title } }, Table)
  self.monitorName = largestMonitor()
  assert(self.monitorName, "this table needs a monitor")
  self:attachCanvas()
  self.ctx.table = self
  self.debug = fs.exists("casino_debug.flag")

  -- Every screen is laid out for a 6x6 wall. On anything smaller, say so instead of drawing off the edge
  while self.c.w < MIN_W or self.c.h < MIN_H do
    local c = self.c
    c:clear(C.ink)
    local lines = { game.title, "Needs a 6x6 monitor wall", "This one is " .. c.w .. "x" .. c.h }
    for i, line in ipairs(lines) do c:textCenter(math.floor(c.w / 2), 2 + i, line, i == 1 and C.gold or C.text) end
    c:flush()
    if self.debug then self:writeDebug({ name = "small" }) end
    os.pullEvent("monitor_resize")
    self:attachCanvas()
  end

  local function main()
    self:refreshBalance()
    self:recover()
    while true do
      self.ctx.seat, self.ctx.balance, self.ctx.owedNotice = nil, nil, nil
      local who = self:attract(not wallet.available() and "Economy offline" or nil)
      if who and wallet.available() and self:seat(who) then
        self:session()
      end
    end
  end

  parallel.waitForAny(main, net.worker, function() presence.worker(function() return self.ctx.seat end) end)
end

return M
