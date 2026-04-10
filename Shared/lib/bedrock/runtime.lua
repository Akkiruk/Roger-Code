local layout = require("lib.bedrock.layout")
local renderer = require("lib.bedrock.renderer")
local theme = require("lib.bedrock.theme")
local text = require("lib.ui_text")
local touch = require("lib.ui_touch")

local M = {}

local default_theme = {
  bg = colors.black,
  surface = colors.gray,
  surface_alt = colors.lightGray,
  text = colors.white,
  text_dark = colors.black,
  muted = colors.lightGray,
  accent = colors.lightBlue,
  accent_alt = colors.blue,
  success = colors.green,
  danger = colors.red,
  warning = colors.orange,
  gold = colors.yellow,
  overlay = colors.black,
}

local Runtime = {}
Runtime.__index = Runtime

local function nowMs()
  return os.epoch("local")
end

local function safeInvoke(fn, ...)
  if type(fn) ~= "function" then
    return true
  end
  return pcall(fn, ...)
end

local function normalizeDialogLines(message)
  local lines = {}

  if type(message) == "table" then
    for _, entry in ipairs(message) do
      lines[#lines + 1] = tostring(entry or "")
    end
  elseif message ~= nil then
    lines[1] = tostring(message)
  end

  if #lines == 0 then
    lines[1] = ""
  end

  return lines
end

local function normalizeDialogButtons(buttons)
  local normalized = {}

  for _, button in ipairs(buttons or {}) do
    if type(button) == "table" and button.label ~= nil then
      normalized[#normalized + 1] = {
        label = tostring(button.label),
        background = button.background or "accent",
        foreground = button.foreground or "text_dark",
        onClick = button.onClick,
        dismiss = button.dismiss ~= false,
      }
    end
  end

  return normalized
end

function Runtime:setBuild(fn)
  self.build = fn
  self:invalidate()
end

function Runtime:setHandlers(handlers)
  self.handlers = handlers or {}
end

function Runtime:setTerm(target, peripheralName)
  local nextTerm = target
  if type(nextTerm) ~= "table" or type(nextTerm.getSize) ~= "function" or type(nextTerm.blit) ~= "function" then
    nextTerm = term.current()
    peripheralName = nil
  end

  self.term = nextTerm
  self.term_name = peripheralName
  self.renderer:setTerm(nextTerm)
  self:invalidate()
end

function Runtime:invalidate()
  self.dirty = true
end

function Runtime:setDialog(dialog)
  if type(dialog) ~= "table" then
    self.dialog = nil
    self:invalidate()
    return
  end

  self.dialog = {
    title = tostring(dialog.title or "Notice"),
    message = normalizeDialogLines(dialog.message),
    accent = dialog.accent or "accent",
    buttons = normalizeDialogButtons(dialog.buttons),
    dismiss_on_backdrop = dialog.dismiss_on_backdrop == true,
  }

  self:invalidate()
end

function Runtime:clearDialog()
  if self.dialog ~= nil then
    self.dialog = nil
    self:invalidate()
  end
end

function Runtime:showPlayAgain(opts)
  local options = opts or {}
  self:setDialog({
    title = options.title or "Round Complete",
    message = options.message or "Want another run?",
    accent = options.accent or "success",
    dismiss_on_backdrop = options.dismiss_on_backdrop == true,
    buttons = {
      {
        label = options.play_again_label or "Play Again",
        background = options.play_again_background or "success",
        foreground = options.play_again_foreground or "text_dark",
        onClick = options.onPlayAgain,
        dismiss = options.play_again_dismiss ~= false,
      },
      options.secondary_label and {
        label = options.secondary_label,
        background = options.secondary_background or "surface_alt",
        foreground = options.secondary_foreground or "text",
        onClick = options.onSecondary,
        dismiss = options.secondary_dismiss ~= false,
      } or nil,
    },
  })
end

function Runtime:addToast(level, title, message, duration)
  self.toasts[#self.toasts + 1] = {
    level = level or "info",
    title = title or "",
    message = message or "",
    expires_at = nowMs() + math.floor((duration or 2.5) * 1000),
  }

  while #self.toasts > 3 do
    table.remove(self.toasts, 1)
  end

  self:invalidate()
end

function Runtime:removeExpiredToasts()
  local current = nowMs()
  local kept = {}

  for _, toast in ipairs(self.toasts) do
    if toast.expires_at > current then
      kept[#kept + 1] = toast
    end
  end

  self.toasts = kept
end

function Runtime:setJob(name, intervalSeconds, callback)
  self.jobs[name] = {
    interval_ms = math.max(100, math.floor((intervalSeconds or 1) * 1000)),
    next_at = nowMs() + math.max(100, math.floor((intervalSeconds or 1) * 1000)),
    callback = callback,
  }
  self:rescheduleJobs()
end

function Runtime:setJobInterval(name, intervalSeconds)
  local job = self.jobs[name]
  if not job then
    return
  end

  job.interval_ms = math.max(100, math.floor((intervalSeconds or 1) * 1000))
  job.next_at = nowMs() + job.interval_ms
  self:rescheduleJobs()
end

function Runtime:rescheduleJobs()
  if self.scheduler_timer_id then
    pcall(function()
      os.cancelTimer(self.scheduler_timer_id)
    end)
    self.scheduler_timer_id = nil
  end

  local nextAt = nil
  for _, job in pairs(self.jobs) do
    if nextAt == nil or job.next_at < nextAt then
      nextAt = job.next_at
    end
  end

  if nextAt ~= nil then
    local delay = math.max(0, (nextAt - nowMs()) / 1000)
    self.scheduler_timer_id = os.startTimer(delay)
  end
end

function Runtime:runDueJobs()
  local current = nowMs()
  for _, job in pairs(self.jobs) do
    if current >= job.next_at then
      local ok, err = safeInvoke(job.callback)
      if not ok then
        self.error_state = {
          title = "Runtime Job Failed",
          message = tostring(err),
        }
      end
      job.next_at = current + job.interval_ms
    end
  end
  self:rescheduleJobs()
  self:invalidate()
end

function Runtime:stop()
  self.running = false
  if self.scheduler_timer_id then
    pcall(function()
      os.cancelTimer(self.scheduler_timer_id)
    end)
    self.scheduler_timer_id = nil
  end
end

function Runtime:getMetrics()
  return {
    frames = self.metrics.frames,
    renders = self.metrics.renders,
    events = self.metrics.events,
    last_render_ms = self.metrics.last_render_ms,
    term_name = self.term_name,
  }
end

function Runtime:createContext()
  local ctx = {
    runtime = self,
    renderer = self.renderer,
    theme = self.theme,
    layout = layout,
    width = self.renderer.width,
    height = self.renderer.height,
  }

  function ctx:resolve(value, fallback)
    return theme.resolve(self.theme, value, fallback)
  end

  function ctx:fillRect(rect, bgValue, fgValue, char)
    self.renderer:fillRect(rect, self:resolve(bgValue, "bg"), self:resolve(fgValue, "text"), char or " ")
  end

  function ctx:drawText(x, y, text, fgValue, bgValue)
    self.renderer:drawText(x, y, text, self:resolve(fgValue, "text"), bgValue and self:resolve(bgValue) or nil)
  end

  function ctx:addHit(rect, handlers)
    if rect.w <= 0 or rect.h <= 0 then
      return
    end
    self.runtime.hits[#self.runtime.hits + 1] = {
      rect = rect,
      onClick = handlers and handlers.onClick or nil,
      onScroll = handlers and handlers.onScroll or nil,
    }
  end

  function ctx:trimText(value, maxLen)
    return text.trimText(value, maxLen)
  end

  function ctx:wrapText(value, width, maxLines)
    return text.wrapText(value, width, maxLines)
  end

  return ctx
end

function Runtime:drawErrorOverlay(ctx)
  local card = layout.inset(layout.rect(1, 1, ctx.width, ctx.height), 2, 2)
  local accent = "danger"

  ctx:fillRect(layout.rect(1, 1, ctx.width, ctx.height), "overlay", "text", " ")
  ctx:fillRect(card, "surface", "text", " ")
  ctx:fillRect(layout.rect(card.x, card.y, card.w, 1), accent, "text_dark", " ")
  ctx:drawText(card.x + 1, card.y, " UI Error ", "text_dark", accent)

  local lines = ctx:wrapText(self.error_state.message or "Unknown error", math.max(8, card.w - 4), math.max(2, card.h - 4))
  for index, line in ipairs(lines) do
    ctx:drawText(card.x + 2, card.y + index + 1, line, "text", nil)
  end

  ctx:drawText(card.x + 2, card.y + card.h - 2, "Click anywhere to retry rendering.", "muted", nil)
  ctx:addHit(layout.rect(1, 1, ctx.width, ctx.height), {
    onClick = function()
      self.error_state = nil
      self:invalidate()
    end,
  })
end

function Runtime:drawDialog(ctx)
  local dialog = self.dialog
  if not dialog then
    return
  end

  local wrapped = {}
  local maxWidth = math.max(18, math.min(ctx.width - 6, 36))
  local sideInset = math.max(2, math.floor((ctx.width - maxWidth) / 2))
  local cardWidth = math.max(16, ctx.width - (sideInset * 2))

  for _, line in ipairs(dialog.message or {}) do
    local bits = ctx:wrapText(line, math.max(8, cardWidth - 4), ctx.height)
    for _, bit in ipairs(bits) do
      wrapped[#wrapped + 1] = bit
    end
  end

  local buttonCount = math.max(1, #(dialog.buttons or {}))
  local contentHeight = math.max(2, #wrapped)
  local cardHeight = math.min(ctx.height - 2, math.max(6, contentHeight + 5))
  local topInset = math.max(1, math.floor((ctx.height - cardHeight) / 2))
  local card = layout.rect(sideInset + 1, topInset + 1, cardWidth, cardHeight)
  local body = layout.inset(card, 2, 2)
  local buttonsTop = card.y + card.h - 2
  local actionRects = layout.columns(layout.rect(card.x + 2, buttonsTop, math.max(1, card.w - 4), 1), (function()
    local fractions = {}
    local index = 1
    while index <= buttonCount do
      fractions[index] = 1 / buttonCount
      index = index + 1
    end
    return fractions
  end)(), 1)

  ctx:fillRect(layout.rect(1, 1, ctx.width, ctx.height), "overlay", "text", " ")
  ctx:fillRect(card, "surface", "text", " ")
  ctx:fillRect(layout.rect(card.x, card.y, card.w, 1), dialog.accent, "text_dark", " ")
  ctx:drawText(card.x + 1, card.y, " " .. text.trimText(dialog.title or "Notice", math.max(1, card.w - 3)), "text_dark", dialog.accent)

  local maxLines = math.max(1, buttonsTop - body.y - 1)
  for index = 1, math.min(#wrapped, maxLines) do
    ctx:drawText(body.x, body.y + index - 1, text.trimText(wrapped[index], body.w), "text", nil)
  end

  if dialog.dismiss_on_backdrop then
    ctx:addHit(layout.rect(1, 1, ctx.width, ctx.height), {
      onClick = function()
        self:clearDialog()
      end,
    })
  end

  for index, button in ipairs(dialog.buttons or {}) do
    local rect = actionRects[index]
    if rect then
      ctx:fillRect(rect, button.background, button.foreground, " ")
      ctx:drawText(rect.x + math.max(0, math.floor((rect.w - #button.label) / 2)), rect.y, text.trimText(button.label, rect.w), button.foreground, button.background)
      ctx:addHit(rect, {
        onClick = function()
          if button.dismiss ~= false then
            self.dialog = nil
          end
          local ok, err = safeInvoke(button.onClick)
          if not ok then
            self.error_state = {
              title = "Dialog Action Failed",
              message = tostring(err),
            }
          end
          self:invalidate()
        end,
      })
    end
  end
end

function Runtime:drawToasts(ctx)
  self:removeExpiredToasts()

  local y = 1
  for index = #self.toasts, 1, -1 do
    local toast = self.toasts[index]
    local width = math.min(ctx.width, 30)
    local x = math.max(1, ctx.width - width + 1)
    local accent = "accent"

    if toast.level == "success" then
      accent = "success"
    elseif toast.level == "warning" then
      accent = "warning"
    elseif toast.level == "error" then
      accent = "danger"
    end

    ctx:fillRect(layout.rect(x, y, width, 3), "surface", "text", " ")
    ctx:fillRect(layout.rect(x, y, width, 1), accent, "text_dark", " ")
    ctx:drawText(x + 1, y, " " .. text.trimText(toast.title, width - 3), "text_dark", accent)
    ctx:drawText(x + 1, y + 1, text.trimText(toast.message, width - 2), "text", nil)
    y = y + 3
  end
end

function Runtime:drawDebugOverlay(ctx)
  local info = self:getMetrics()
  local rect = layout.rect(2, math.max(1, ctx.height - 4), math.min(30, ctx.width - 2), 4)

  ctx:fillRect(rect, "surface", "text", " ")
  ctx:fillRect(layout.rect(rect.x, rect.y, rect.w, 1), "gold", "text_dark", " ")
  ctx:drawText(rect.x + 1, rect.y, " Diagnostics ", "text_dark", "gold")
  ctx:drawText(rect.x + 1, rect.y + 1, "Frames: " .. tostring(info.frames) .. " | Events: " .. tostring(info.events), "text", nil)
  ctx:drawText(rect.x + 1, rect.y + 2, "Last render: " .. tostring(info.last_render_ms) .. "ms", "muted", nil)
end

function Runtime:buildFrame()
  self.hits = {}
  self.renderer:beginFrame(theme.resolve(self.theme, "bg"), theme.resolve(self.theme, "text"))

  local ctx = self:createContext()
  local startedAt = nowMs()

  if self.error_state == nil and type(self.build) == "function" then
    local ok, err = safeInvoke(self.build, ctx)
    if not ok then
      self.error_state = {
        title = "Build Failed",
        message = tostring(err),
      }
      self.renderer:beginFrame(theme.resolve(self.theme, "bg"), theme.resolve(self.theme, "text"))
      ctx = self:createContext()
    end
  end

  if self.error_state then
    self:drawErrorOverlay(ctx)
  end

  self:drawToasts(ctx)
  if self.debug_visible then
    self:drawDebugOverlay(ctx)
  end

  if self.dialog then
    self:drawDialog(ctx)
  end

  self.renderer:render()
  self.metrics.frames = self.metrics.frames + 1
  self.metrics.renders = self.metrics.renders + 1
  self.metrics.last_render_ms = nowMs() - startedAt
  self.dirty = false
end

function Runtime:dispatchClick(x, y, button)
  for index = #self.hits, 1, -1 do
    local hit = self.hits[index]
    if layout.contains(hit.rect, x, y) and type(hit.onClick) == "function" then
      local ok, err = safeInvoke(hit.onClick, x, y, button)
      if not ok then
        self.error_state = {
          title = "Interaction Failed",
          message = tostring(err),
        }
      end
      self:invalidate()
      return true
    end
  end
  return false
end

function Runtime:dispatchScroll(direction, x, y)
  for index = #self.hits, 1, -1 do
    local hit = self.hits[index]
    if layout.contains(hit.rect, x, y) and type(hit.onScroll) == "function" then
      local ok, err = safeInvoke(hit.onScroll, direction, x, y)
      if not ok then
        self.error_state = {
          title = "Scroll Failed",
          message = tostring(err),
        }
      end
      self:invalidate()
      return true
    end
  end
  return false
end

function Runtime:handleEvent(eventName, ...)
  self.metrics.events = self.metrics.events + 1

  if eventName == "timer" then
    local timerId = ...
    if timerId == self.scheduler_timer_id then
      self.scheduler_timer_id = nil
      self:runDueJobs()
    end
    return
  end

  if eventName == "term_resize" then
    self:invalidate()
    return
  end

  if eventName == "mouse_click" then
    local button, x, y = ...
    self:dispatchClick(x, y, button)
    return
  end

  if eventName == "mouse_scroll" then
    local direction, x, y = ...
    self:dispatchScroll(direction, x, y)
    return
  end

  if eventName == "monitor_touch" then
    local side, x, y = ...
    if self.term_name and side == self.term_name and self.authorizeTouch() then
      self:dispatchClick(x, y, 1)
    end
    return
  end

  if eventName == "key" then
    local key = ...
    if key == keys.f3 then
      self.debug_visible = not self.debug_visible
      self:invalidate()
    end
    return
  end

  if eventName == "peripheral" or eventName == "peripheral_detach" then
    local handler = self.handlers and self.handlers.peripheral or nil
    local ok, err = safeInvoke(handler, eventName)
    if not ok then
      self.error_state = {
        title = "Peripheral Handler Failed",
        message = tostring(err),
      }
    end
    self:invalidate()
    return
  end

  if eventName == "terminate" then
    local handler = self.handlers and self.handlers.terminate or nil
    local ok, err = safeInvoke(handler)
    if not ok then
      self.error_state = {
        title = "Shutdown Handler Failed",
        message = tostring(err),
      }
    end
    self:stop()
  end
end

function Runtime:run()
  self.running = true
  self:rescheduleJobs()

  while self.running do
    if self.dirty then
      self:buildFrame()
    end

    local event = { os.pullEventRaw() }
    local ok, err = safeInvoke(function()
      self:handleEvent(unpack(event))
    end)

    if not ok then
      self.error_state = {
        title = "Runtime Failed",
        message = tostring(err),
      }
      self:invalidate()
    end
  end
end

function M.create(opts)
  local options = opts or {}
  local mergedTheme = theme.merge(default_theme, options.theme or {})
  local target = options.term or term.current()
  local instance = setmetatable({
    theme = mergedTheme,
    term = target,
    term_name = options.term_name,
    renderer = renderer.new(target, theme.resolve(mergedTheme, "bg"), theme.resolve(mergedTheme, "text")),
    build = nil,
    handlers = {},
    hits = {},
    jobs = {},
    scheduler_timer_id = nil,
    toasts = {},
    metrics = {
      frames = 0,
      renders = 0,
      events = 0,
      last_render_ms = 0,
    },
    debug_visible = false,
    dirty = true,
    running = false,
    error_state = nil,
    dialog = nil,
    authorizeTouch = options.authorizeTouch or touch.isAuthorizedMonitorTouch,
  }, Runtime)

  return instance
end

return M
