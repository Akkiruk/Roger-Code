local layout = require("lib.bedrock.layout")

local M = {}

local function trimText(text, maxLen)
  local value = tostring(text or "")
  if maxLen <= 0 then
    return ""
  end
  if #value <= maxLen then
    return value
  end
  if maxLen <= 2 then
    return value:sub(1, maxLen)
  end
  return value:sub(1, maxLen - 2) .. ".."
end

local function centerX(rect, text)
  return rect.x + math.max(0, math.floor((rect.w - #text) / 2))
end

function M.pill(ctx, rect, label, opts)
  local options = opts or {}
  local bg = options.background or "surface_alt"
  local fg = options.foreground or "text"

  ctx:fillRect(rect, bg, fg, " ")
  local text = trimText(label, math.max(1, rect.w - 2))
  ctx:drawText(centerX(rect, text), rect.y + math.floor((rect.h - 1) / 2), text, fg, bg)

  if type(options.onClick) == "function" then
    ctx:addHit(rect, { onClick = options.onClick })
  end
end

function M.button(ctx, rect, label, opts)
  local options = opts or {}
  local bg = options.background or "accent"
  local fg = options.foreground or "text_dark"

  ctx:fillRect(rect, bg, fg, " ")
  local text = trimText(label, math.max(1, rect.w - 2))
  ctx:drawText(centerX(rect, text), rect.y + math.floor((rect.h - 1) / 2), text, fg, bg)

  if type(options.onClick) == "function" then
    ctx:addHit(rect, { onClick = options.onClick })
  end
end

function M.progress(ctx, rect, percent, opts)
  local options = opts or {}
  local clamped = math.max(0, math.min(100, percent or 0))
  local fillWidth = math.floor((rect.w * clamped) / 100 + 0.5)
  local bg = options.background or "surface_alt"
  local fill = options.fill or "success"
  local fg = options.foreground or "text"

  ctx:fillRect(rect, bg, fg, " ")
  if fillWidth > 0 then
    ctx:fillRect(layout.rect(rect.x, rect.y, fillWidth, rect.h), fill, fg, " ")
  end

  if options.show_text ~= false and rect.w >= 4 then
    local text = trimText(tostring(math.floor(clamped + 0.5)) .. "%", rect.w - 1)
    ctx:drawText(centerX(rect, text), rect.y + math.floor((rect.h - 1) / 2), text, fg, nil)
  end
end

function M.card(ctx, rect, opts)
  local options = opts or {}
  local surface = options.surface or "surface"
  local border = options.border or "surface_alt"
  local accent = options.accent or "accent"
  local title = trimText(options.title or "", math.max(1, rect.w - 4))

  ctx:fillRect(rect, surface, "text", " ")
  if rect.h >= 1 then
    ctx:fillRect(layout.rect(rect.x, rect.y, rect.w, 1), accent, "text_dark", " ")
    if title ~= "" then
      ctx:drawText(rect.x + 1, rect.y, " " .. title, "text_dark", accent)
    end
  end

  if rect.w >= 2 and rect.h >= 2 then
    ctx:fillRect(layout.rect(rect.x, rect.y + 1, 1, rect.h - 1), border, "text", " ")
    ctx:fillRect(layout.rect(rect.x + rect.w - 1, rect.y + 1, 1, rect.h - 1), border, "text", " ")
    ctx:fillRect(layout.rect(rect.x, rect.y + rect.h - 1, rect.w, 1), border, "text", " ")
  end

  local actionX = rect.x + rect.w - 1
  for index = #(options.actions or {}), 1, -1 do
    local action = options.actions[index]
    local width = math.max(3, action.width or (#action.label + 2))
    actionX = actionX - width + 1
    M.button(ctx, layout.rect(actionX, rect.y, width, 1), action.label, {
      background = action.background or border,
      foreground = action.foreground or "text",
      onClick = action.onClick,
    })
    actionX = actionX - 1
  end

  return layout.rect(rect.x + 1, rect.y + 1, math.max(0, rect.w - 2), math.max(0, rect.h - 2))
end

function M.nav(ctx, rect, items, selectedId, opts)
  local options = opts or {}
  local gap = options.gap or 1
  local orientation = options.orientation or "horizontal"
  local activeBg = options.active_background or "accent"
  local activeFg = options.active_foreground or "text_dark"
  local inactiveBg = options.background or "surface_alt"
  local inactiveFg = options.foreground or "text"

  if orientation == "vertical" then
    local y = rect.y
    for _, item in ipairs(items or {}) do
      local itemRect = layout.rect(rect.x, y, rect.w, 1)
      local active = item.id == selectedId
      M.button(ctx, itemRect, item.label, {
        background = active and activeBg or inactiveBg,
        foreground = active and activeFg or inactiveFg,
        onClick = function()
          if type(options.onSelect) == "function" then
            options.onSelect(item.id)
          end
        end,
      })
      y = y + 1 + gap
      if y > rect.y + rect.h - 1 then
        break
      end
    end
    return
  end

  local count = math.max(1, #(items or {}))
  local totalGap = math.max(0, (count - 1) * gap)
  local width = math.max(1, math.floor((rect.w - totalGap) / count))
  local x = rect.x

  for index, item in ipairs(items or {}) do
    local itemWidth = width
    if index == count then
      itemWidth = rect.x + rect.w - x
    end

    local itemRect = layout.rect(x, rect.y, itemWidth, rect.h)
    local active = item.id == selectedId
    M.button(ctx, itemRect, item.label, {
      background = active and activeBg or inactiveBg,
      foreground = active and activeFg or inactiveFg,
      onClick = function()
        if type(options.onSelect) == "function" then
          options.onSelect(item.id)
        end
      end,
    })
    x = x + itemWidth + gap
  end
end

function M.list(ctx, rect, items, opts)
  local options = opts or {}
  local scroll = math.max(0, options.scroll or 0)
  local selectedId = options.selected_id
  local emptyText = options.empty_text or "No items"
  local textWidth = rect.w

  if #items > rect.h then
    textWidth = math.max(1, rect.w - 1)
  end

  ctx:addHit(rect, {
    onScroll = options.onScroll,
  })

  if #items == 0 then
    ctx:drawText(rect.x, rect.y + math.floor((rect.h - 1) / 2), trimText(emptyText, rect.w), "muted", nil)
    return
  end

  for row = 1, rect.h do
    local index = scroll + row
    local item = items[index]
    local rowRect = layout.rect(rect.x, rect.y + row - 1, rect.w, 1)
    local itemBg = "surface"
    local itemFg = item and item.fg or "text"

    if item and item.id == selectedId then
      itemBg = options.selected_background or "accent"
      itemFg = options.selected_foreground or "text_dark"
    elseif item and item.bg ~= nil then
      itemBg = item.bg
    else
      itemBg = options.background or "surface"
    end

    ctx:fillRect(rowRect, itemBg, itemFg, " ")

    if item then
      local text = trimText(item.text or "", math.max(1, textWidth - 1))
      ctx:drawText(rect.x + 1, rowRect.y, text, itemFg, itemBg)
      if type(options.onSelect) == "function" then
        ctx:addHit(rowRect, {
          onClick = function()
            options.onSelect(item.id, item)
          end,
          onScroll = options.onScroll,
        })
      end
    end
  end

  if #items > rect.h then
    local trackX = rect.x + rect.w - 1
    local maxScroll = math.max(1, #items - rect.h)
    local thumbHeight = math.max(1, math.floor((rect.h / #items) * rect.h + 0.5))
    local thumbStart = rect.y + math.floor((scroll / maxScroll) * math.max(0, rect.h - thumbHeight) + 0.5)

    ctx:fillRect(layout.rect(trackX, rect.y, 1, rect.h), "bg", "text", " ")
    ctx:fillRect(layout.rect(trackX, thumbStart, 1, thumbHeight), options.scrollbar or "surface_alt", "text", " ")
  end
end

function M.segmented(ctx, rect, items, selectedId, opts)
  local options = opts or {}
  local count = math.max(1, #(items or {}))
  local gap = options.gap or 1
  local totalGap = math.max(0, (count - 1) * gap)
  local width = math.max(1, math.floor((rect.w - totalGap) / count))
  local x = rect.x

  for index, item in ipairs(items or {}) do
    local itemWidth = width
    if index == count then
      itemWidth = rect.x + rect.w - x
    end

    M.button(ctx, layout.rect(x, rect.y, itemWidth, rect.h), item.label, {
      background = item.id == selectedId and (options.active_background or "accent") or (options.background or "surface_alt"),
      foreground = item.id == selectedId and (options.active_foreground or "text_dark") or (options.foreground or "text"),
      onClick = function()
        if type(options.onSelect) == "function" then
          options.onSelect(item.id)
        end
      end,
    })

    x = x + itemWidth + gap
  end
end

function M.toggle(ctx, rect, label, checked, opts)
  local options = opts or {}
  local stateRect = layout.rect(rect.x, rect.y, 6, 1)
  local labelRect = layout.rect(rect.x + 8, rect.y, math.max(0, rect.w - 8), 1)

  M.pill(ctx, stateRect, checked and " ON " or " OFF ", {
    background = checked and (options.on_background or "success") or (options.off_background or "danger"),
    foreground = options.foreground or "text_dark",
    onClick = options.onClick,
  })
  ctx:drawText(labelRect.x, labelRect.y, trimText(label, labelRect.w), options.label_foreground or "text", nil)
  ctx:addHit(rect, { onClick = options.onClick })
end

function M.stepper(ctx, rect, label, valueText, opts)
  local options = opts or {}
  local labelWidth = math.max(8, rect.w - 14)
  local labelRect = layout.rect(rect.x, rect.y, labelWidth, 1)
  local minusRect = layout.rect(labelRect.x + labelRect.w + 1, rect.y, 3, 1)
  local valueRect = layout.rect(minusRect.x + minusRect.w + 1, rect.y, 5, 1)
  local plusRect = layout.rect(valueRect.x + valueRect.w + 1, rect.y, 3, 1)

  ctx:drawText(labelRect.x, labelRect.y, trimText(label, labelRect.w), options.label_foreground or "text", nil)
  M.button(ctx, minusRect, "-", {
    background = options.button_background or "surface_alt",
    foreground = options.button_foreground or "text",
    onClick = options.onMinus,
  })
  ctx:drawText(valueRect.x, valueRect.y, trimText(valueText, valueRect.w), options.value_foreground or "gold", nil)
  M.button(ctx, plusRect, "+", {
    background = options.button_background or "surface_alt",
    foreground = options.button_foreground or "text",
    onClick = options.onPlus,
  })
end

function M.selector(ctx, rect, label, valueText, opts)
  local options = opts or {}
  local labelWidth = math.max(10, math.floor(rect.w * 0.34))
  local valueWidth = math.max(8, rect.w - labelWidth - 9)
  local labelRect = layout.rect(rect.x, rect.y, labelWidth, 1)
  local prevRect = layout.rect(labelRect.x + labelRect.w + 1, rect.y, 3, 1)
  local valueRect = layout.rect(prevRect.x + prevRect.w + 1, rect.y, valueWidth, 1)
  local nextRect = layout.rect(valueRect.x + valueRect.w + 1, rect.y, 3, 1)

  ctx:drawText(labelRect.x, labelRect.y, trimText(label, labelRect.w), options.label_foreground or "text", nil)
  M.button(ctx, prevRect, "<", {
    background = options.button_background or "surface_alt",
    foreground = options.button_foreground or "text",
    onClick = options.onPrev,
  })
  ctx:drawText(valueRect.x, valueRect.y, trimText(valueText, valueRect.w), options.value_foreground or "gold", nil)
  M.button(ctx, nextRect, ">", {
    background = options.button_background or "surface_alt",
    foreground = options.button_foreground or "text",
    onClick = options.onNext,
  })
end

return M
