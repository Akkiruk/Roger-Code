local ui = require("lib.ui")
local constants = require("lib.vaultgear.constants")
local planner = require("lib.vaultgear.planner")
local presets = require("lib.vaultgear.presets")
local quickSetup = require("lib.vaultgear.quick_setup")
local peripherals = require("lib.vaultgear.peripherals")
local util = require("lib.vaultgear.util")

local M = {}

M.layout = ui.layout
M.widgets = ui.widgets

M.theme = {
  bg = colors.black,
  surface = colors.gray,
  surface_alt = colors.lightGray,
  text = colors.white,
  text_dark = colors.black,
  muted = colors.lightGray,
  accent = colors.cyan,
  accent_alt = colors.lightBlue,
  success = colors.green,
  danger = colors.red,
  warning = colors.orange,
  gold = colors.yellow,
  overlay = colors.black,
}

local field_support = {
  Gear = {
    min_rarity = true,
    min_level = true,
    max_level = true,
    min_crafting_potential = true,
    min_free_repair_slots = true,
    min_durability_percent = true,
  },
  Tool = {
    min_rarity = true,
    min_level = true,
    max_level = true,
    min_free_repair_slots = true,
    min_durability_percent = true,
  },
  Jewel = {
    min_rarity = true,
    min_level = true,
    max_level = true,
    max_jewel_size = true,
  },
  Trinket = {
    min_uses = true,
  },
  Charm = {
    min_rarity = true,
    min_uses = true,
  },
  Etching = {
    min_rarity = true,
    min_level = true,
    max_level = true,
  },
}

local function contains(list, value)
  for _, entry in ipairs(list or {}) do
    if entry == value then
      return true
    end
  end
  return false
end

local function selectedStorage(app)
  return planner.findStorageByInventory(app.config.storages, app.ui.selected_inventory)
end

local function inventoryLabel(app, inventoryName)
  if not inventoryName then
    return "No inventory selected"
  end

  local entry = peripherals.findInventory(app.discovery, inventoryName)
  if entry then
    return entry.label
  end

  return inventoryName .. " (missing)"
end

local function selectedInventoryLabel(app)
  return inventoryLabel(app, app.ui.selected_inventory)
end

local function roleLabel(role)
  if role == "inbox" then
    return "Inbox"
  end
  return "Home"
end

local function optionLabel(options, current, fallback)
  for _, option in ipairs(options or {}) do
    if option.id == current then
      return option.label
    end
  end
  return fallback or tostring(current or "")
end

local function cycleOption(options, current, delta)
  local ids = {}
  for _, option in ipairs(options or {}) do
    ids[#ids + 1] = option.id
  end

  if #ids == 0 then
    return current
  end

  if current == nil then
    return ids[1]
  end

  return util.cycleValue(ids, current, delta)
end

local function connectedInventoryNames(app)
  local names = {}
  local seen = {}

  for _, entry in ipairs(app.discovery.inventories or {}) do
    if not seen[entry.name] then
      names[#names + 1] = entry.name
      seen[entry.name] = true
    end
  end

  for _, storage in ipairs(app.config.storages or {}) do
    if storage.inventory and not seen[storage.inventory] then
      names[#names + 1] = storage.inventory
      seen[storage.inventory] = true
    end
  end

  table.sort(names)
  return names
end

local function storageSignature(storage)
  if not storage then
    return "open"
  end

  return table.concat({
    tostring(storage.id or ""),
    tostring(storage.role or ""),
    tostring(storage.preset_id or ""),
    tostring(storage.strictness or ""),
    tostring(storage.priority or ""),
    tostring(storage.enabled ~= false),
    tostring(storage.rescan ~= false),
  }, "|")
end

local function selectionModeLabel(app, storage)
  if not app.ui.selected_inventory then
    return "No storage selected."
  end
  if not storage then
    return "Open inventory. Choose a role to start managing it."
  end
  if storage.role == "inbox" then
    return "Inbox. New items here are routed into homes."
  end
  return "Home. Matching items belong here long-term."
end

local function storageDestinationLabel(app, storage)
  if not storage then
    return "No home"
  end
  return presets.shortLabel(storage.preset_id) .. "  " .. inventoryLabel(app, storage.inventory)
end

local function storageListEntry(app, storage)
  local entry = peripherals.findInventory(app.discovery, storage.inventory)
  local missing = not app.connected[storage.inventory]
  local prefix = storage.role == "home" and "HOME " or "INBX "
  local fg = storage.role == "home" and "gold" or "accent"

  if missing then
    fg = "warning"
  elseif storage.enabled == false then
    fg = "muted"
  end

  local text = prefix .. (entry and entry.label or (storage.inventory .. " (missing)"))
  if storage.role == "home" then
    text = string.format("P%02d %s | %s", tonumber(storage.priority) or 0, presets.shortLabel(storage.preset_id), text)
  else
    text = "Watch | " .. text
  end

  return {
    id = storage.id,
    text = text,
    fg = fg,
  }
end

local function sampleDecision(app, item)
  local homes = planner.listHomes(app.config.storages, app.connected)
  if not item or not item.supported_type then
    return nil
  end
  return planner.pickDestination(homes, item, app.ui.selected_inventory)
end

function M.createViewState()
  return {
    inventory_scroll = 0,
    storage_scroll = 0,
    recent_scroll = 0,
    health_scroll = 0,
    sample_scroll = 0,
    detail_scroll = 0,
    form_scroll = 0,
    live_scroll = 0,
    sample_selected = 1,
    draft_role = nil,
    draft_home = nil,
    last_selected_inventory = nil,
    last_storage_signature = nil,
  }
end

function M.syncDraft(view, app)
  local storage = selectedStorage(app)
  local signature = storageSignature(storage)
  local nextPriority = planner.nextHomePriority(app.config.storages)

  if storage and view.last_storage_signature ~= signature then
    view.draft_role = storage.role
    if storage.role == "home" then
      view.draft_home = quickSetup.fromStorage(storage)
    else
      view.draft_home = quickSetup.fromSuggestion(app.suggestion, nextPriority)
    end
    view.form_scroll = 0
  elseif not storage and (view.last_selected_inventory ~= app.ui.selected_inventory or view.draft_role == nil) then
    view.draft_role = "home"
    view.draft_home = quickSetup.fromSuggestion(app.suggestion, nextPriority)
    view.form_scroll = 0
  end

  if view.last_selected_inventory ~= app.ui.selected_inventory then
    view.sample_selected = 1
    view.sample_scroll = 0
    view.detail_scroll = 0
  end

  view.last_selected_inventory = app.ui.selected_inventory
  view.last_storage_signature = signature
end

function M.accentForApp(app)
  if not app.health.monitor_ok or #app.health.errors > 0 then
    return "danger"
  end
  if #app.health.warnings > 0 then
    return "warning"
  end
  if app.config.runtime.enabled then
    return "success"
  end
  return "accent"
end

function M.healthLabel(app)
  if not app.health.monitor_ok or #app.health.errors > 0 then
    return "Attention"
  end
  if #app.health.warnings > 0 then
    return "Review"
  end
  return "Ready"
end

function M.nextStep(app)
  if not app.health.monitor_ok and app.health.monitor_error then
    return app.health.monitor_error
  end
  if #app.health.errors > 0 then
    return app.health.errors[1]
  end
  if #app.config.storages == 0 then
    return "Pick a storage and give it a simple role first."
  end
  if #planner.listInboxes(app.config.storages, app.connected) == 0 then
    return "Add at least one inbox so the manager can see new items."
  end
  if #planner.listHomes(app.config.storages, app.connected) == 0 then
    return "Add at least one home so matching items have somewhere to live."
  end
  if not app.config.runtime.enabled then
    return "Start the manager when the current storage plan looks right."
  end
  if app.state.runtime.current_mode == "repair_scan" and app.state.runtime.current_target then
    return "Idle repair is rescanning " .. tostring(app.state.runtime.current_target) .. "."
  end
  if app.state.runtime.last_reason then
    return app.state.runtime.last_reason
  end
  return "Routing handles new work first, then idle repair quietly fixes drift."
end

function M.storageSummaryLines(storage)
  if not storage then
    return {
      "Unmanaged",
      "Select a role and save it when you like the setup.",
    }
  end

  if storage.role == "inbox" then
    return {
      "Inbox",
      storage.enabled == false and "Paused" or "Active",
      "New items dropped here are routed into matching homes.",
    }
  end

  local lines = presets.summaryLines(storage)
  lines[#lines + 1] = storage.enabled == false and "This home is paused." or "This home is active."
  lines[#lines + 1] = storage.rescan == false and "Idle repair is off." or "Idle repair is on."
  return lines
end

function M.quickSummaryLines(config)
  return quickSetup.summaryLines(config)
end

function M.quickFieldsForType(itemType)
  return quickSetup.fieldsForType(itemType)
end

function M.quickDraftFromSuggestion(app, priority)
  return quickSetup.fromSuggestion(app.suggestion, priority)
end

function M.selectionSummaryLines(app)
  local storage = selectedStorage(app)
  local lines = {
    selectedInventoryLabel(app),
    selectionModeLabel(app, storage),
  }

  if app.inspector.error then
    lines[#lines + 1] = app.inspector.error
    return lines
  end

  lines[#lines + 1] = string.format(
    "Sampled %d items | Vault %d | Supported %d",
    #(app.inspector.items or {}),
    tonumber(app.inspector.vault_items or 0),
    tonumber(app.inspector.supported_items or 0)
  )

  if storage then
    local summary = M.storageSummaryLines(storage)
    for index = 1, math.min(#summary, 3) do
      lines[#lines + 1] = summary[index]
    end
  elseif app.suggestion then
    lines[#lines + 1] = "Suggested: " .. presets.label(app.suggestion.preset_id) .. " | " .. tostring(app.suggestion.reason or "")
  end

  return lines
end

function M.liveSummaryLines(app)
  local lines = {
    "Mode: " .. tostring(app.state.runtime.last_summary or "Idle"),
    "Moves: " .. tostring(app.session.moves or 0) .. " stacks | Items: " .. tostring(app.session.moved_items or 0),
    "Routed: " .. tostring(app.session.routed or 0) .. " | Repaired: " .. tostring(app.session.repaired or 0),
    "Unresolved: " .. tostring(app.session.unresolved or 0) .. " | Errors: " .. tostring(app.session.errors or 0),
  }

  if app.state.runtime.current_target then
    lines[#lines + 1] = "Target: " .. tostring(app.state.runtime.current_target)
  end
  if app.state.runtime.last_reason then
    lines[#lines + 1] = "Reason: " .. tostring(app.state.runtime.last_reason)
  end

  return lines
end

function M.roleOptions()
  return constants.STORAGE_ROLES
end

function M.strictnessOptions()
  return constants.STRICTNESS
end

function M.identifiedOptions()
  return constants.IDENTIFIED_MODES
end

function M.rarityOptions()
  local items = {}
  for _, rarity in ipairs(constants.RARITIES) do
    items[#items + 1] = {
      id = rarity,
      label = rarity == "ANY" and "Any" or rarity,
    }
  end
  return items
end

function M.quickTypeOptions()
  local items = {}
  for _, itemType in ipairs(quickSetup.itemTypes()) do
    items[#items + 1] = {
      id = itemType,
      label = itemType,
    }
  end
  return items
end

function M.cycleItemType(current, delta)
  return util.cycleValue(quickSetup.itemTypes(), current or "Gear", delta)
end

function M.presetOptions()
  local items = {}
  for _, preset in ipairs(presets.list()) do
    items[#items + 1] = {
      id = preset.id,
      label = preset.short_label or preset.label,
    }
  end
  return items
end

function M.optionLabel(options, current, fallback)
  return optionLabel(options, current, fallback)
end

function M.cycleOption(options, current, delta)
  return cycleOption(options, current, delta)
end

function M.inventoryItems(app)
  local items = {}
  for _, name in ipairs(connectedInventoryNames(app)) do
    local storage = planner.findStorageByInventory(app.config.storages, name)
    local entry = peripherals.findInventory(app.discovery, name)
    local label = entry and entry.label or (name .. " (missing)")
    local fg = "text"
    local prefix = "OPEN "

    if storage and storage.role == "home" then
      prefix = string.format("P%02d  ", tonumber(storage.priority) or 0)
      label = presets.shortLabel(storage.preset_id) .. " | " .. label
      fg = app.connected[name] and "gold" or "warning"
    elseif storage and storage.role == "inbox" then
      prefix = "INBX "
      fg = app.connected[name] and "accent" or "warning"
    elseif not app.connected[name] then
      prefix = "MISS "
      fg = "warning"
    end

    items[#items + 1] = {
      id = name,
      text = prefix .. label,
      fg = fg,
    }
  end
  return items
end

function M.managedStorageItems(app)
  local items = {}
  for _, storage in ipairs(planner.normalizeStorages(app.config.storages)) do
    items[#items + 1] = storageListEntry(app, storage)
  end
  return items
end

function M.recentItems(app)
  local items = {}
  for index = #app.recent, 1, -1 do
    local entry = app.recent[index]
    local fg = "text"
    if entry.level == "error" then
      fg = "danger"
    elseif entry.level == "warning" then
      fg = "warning"
    elseif entry.level == "info" then
      fg = "text"
    end

    items[#items + 1] = {
      id = index,
      text = "[" .. util.formatTime(entry.at) .. "] " .. tostring(entry.message or ""),
      fg = fg,
    }
  end
  return items
end

function M.healthItems(app)
  local items = {}

  if not app.health.monitor_ok and app.health.monitor_error then
    items[#items + 1] = {
      id = "monitor",
      text = app.health.monitor_error,
      fg = "danger",
    }
  end

  for index, message in ipairs(app.health.errors or {}) do
    items[#items + 1] = {
      id = "error_" .. tostring(index),
      text = message,
      fg = "danger",
    }
  end

  for index, message in ipairs(app.health.warnings or {}) do
    items[#items + 1] = {
      id = "warning_" .. tostring(index),
      text = message,
      fg = "warning",
    }
  end

  if #items == 0 then
    items[1] = {
      id = "healthy",
      text = "Everything looks healthy.",
      fg = "success",
    }
  end

  return items
end

function M.sampleItems(app)
  local items = {}
  for index, entry in ipairs(app.inspector.items or {}) do
    local item = entry.item or {}
    local text = tostring(item.display_name or item.registry_name or "Item")
    local fg = "text"

    if item.supported_type then
      local picked = sampleDecision(app, item)
      if picked and picked.storage then
        if picked.storage.inventory == app.ui.selected_inventory then
          text = text .. " -> stays here"
          fg = "success"
        else
          text = text .. " -> " .. presets.shortLabel(picked.storage.preset_id)
          fg = "gold"
        end
      else
        text = text .. " -> no home"
        fg = "warning"
      end
    elseif item.vault then
      text = text .. " -> unsupported"
      fg = "muted"
    else
      text = text .. " -> ignored"
      fg = "muted"
    end

    items[#items + 1] = {
      id = index,
      text = text,
      fg = fg,
    }
  end
  return items
end

function M.storageCounts(app)
  local counts = {
    connected = 0,
    managed = 0,
    inboxes = 0,
    homes = 0,
  }

  for _ in pairs(app.connected or {}) do
    counts.connected = counts.connected + 1
  end

  for _, storage in ipairs(app.config.storages or {}) do
    counts.managed = counts.managed + 1
    if storage.role == "inbox" then
      counts.inboxes = counts.inboxes + 1
    else
      counts.homes = counts.homes + 1
    end
  end

  return counts
end

function M.selectedSample(app, view)
  local items = app.inspector.items or {}
  local index = tonumber(view.sample_selected) or 1
  if index < 1 then
    index = 1
  elseif index > #items then
    index = #items
  end
  if index < 1 then
    index = 1
  end
  view.sample_selected = index
  return (app.inspector.items or {})[index], index
end

function M.sampleDecisionLines(app, entry)
  if not entry then
    return {
      "No sampled item selected.",
    }
  end

  local item = entry.item or {}
  local lines = {}
  for _, line in ipairs(entry.lines or {}) do
    lines[#lines + 1] = line
  end

  if item.supported_type then
    local picked = sampleDecision(app, item)
    if picked and picked.storage then
      if picked.storage.inventory == app.ui.selected_inventory then
        lines[#lines + 1] = "Best home: stays in this storage."
      else
        lines[#lines + 1] = "Best home: " .. storageDestinationLabel(app, picked.storage)
      end
      if picked.reasons and picked.reasons[1] then
        lines[#lines + 1] = "Why: " .. tostring(picked.reasons[1])
      end
    else
      lines[#lines + 1] = "No connected home matches this item yet."
    end
  elseif item.vault then
    lines[#lines + 1] = "Vault item detected, but this type is not part of the supported sorter set."
  else
    lines[#lines + 1] = "This item is outside the vault sorting scope and will be ignored."
  end

  return lines
end

function M.ruleSupportsField(rule, field)
  for _, itemType in ipairs(rule and rule.item_types or {}) do
    if field_support[itemType] and field_support[itemType][field] then
      return true
    end
  end
  return false
end

function M.formatRuleValue(rule, field)
  local value = rule and rule[field] or nil
  if value == nil then
    return "Off"
  end
  if field == "min_durability_percent" then
    return tostring(value) .. "%"
  end
  return tostring(value)
end

function M.clampScroll(scroll, itemCount, visibleCount)
  local maximum = math.max(0, (itemCount or 0) - math.max(0, visibleCount or 0))
  return util.clamp(scroll or 0, 0, maximum)
end

function M.ensureVisible(scroll, selectedIndex, visibleCount, itemCount)
  local nextScroll = M.clampScroll(scroll, itemCount, visibleCount)
  if not selectedIndex or selectedIndex < 1 then
    return nextScroll
  end

  if selectedIndex <= nextScroll then
    nextScroll = selectedIndex - 1
  elseif selectedIndex > nextScroll + visibleCount then
    nextScroll = selectedIndex - visibleCount
  end

  return M.clampScroll(nextScroll, itemCount, visibleCount)
end

function M.renderScrollButtons(ctx, rect, onUp, onDown)
  if rect.w <= 0 or rect.h < 2 then
    return
  end

  local x = rect.x + rect.w - 1
  M.widgets.button(ctx, M.layout.rect(x, rect.y, 1, 1), "^", {
    background = "surface_alt",
    foreground = "text_dark",
    onClick = onUp,
  })
  M.widgets.button(ctx, M.layout.rect(x, rect.y + rect.h - 1, 1, 1), "v", {
    background = "surface_alt",
    foreground = "text_dark",
    onClick = onDown,
  })
end

function M.renderListCard(ctx, rect, options)
  local cardRect = M.widgets.card(ctx, rect, {
    title = options.title,
    accent = options.accent or "accent",
    actions = options.actions,
  })

  if cardRect.w <= 0 or cardRect.h <= 0 then
    return 0, 0
  end

  local items = options.items or {}
  local scroll = M.clampScroll(options.scroll or 0, #items, cardRect.h)
  local maxScroll = math.max(0, #items - cardRect.h)

  M.widgets.list(ctx, cardRect, items, {
    scroll = scroll,
    selected_id = options.selected_id,
    empty_text = options.empty_text or "Nothing here yet",
    onSelect = options.onSelect,
    onScroll = function(direction)
      if type(options.onScrollChange) == "function" then
        options.onScrollChange(M.clampScroll(scroll + direction, #items, cardRect.h))
      end
    end,
  })

  if maxScroll > 0 then
    M.renderScrollButtons(ctx, cardRect, function()
      if type(options.onScrollChange) == "function" then
        options.onScrollChange(M.clampScroll(scroll - 1, #items, cardRect.h))
      end
    end, function()
      if type(options.onScrollChange) == "function" then
        options.onScrollChange(M.clampScroll(scroll + 1, #items, cardRect.h))
      end
    end)
  end

  return maxScroll, scroll
end

function M.renderWrappedTextCard(ctx, rect, title, lines, scroll, onScrollChange, opts)
  local wrapped = {}
  for _, line in ipairs(lines or {}) do
    local bits = util.wrapText(line, math.max(6, rect.w - 5), 12)
    for _, bit in ipairs(bits) do
      wrapped[#wrapped + 1] = {
        id = #wrapped + 1,
        text = bit,
        fg = opts and opts.foreground or "text",
      }
    end
  end

  return M.renderListCard(ctx, rect, {
    title = title,
    accent = opts and opts.accent or "accent",
    actions = opts and opts.actions or nil,
    items = wrapped,
    scroll = scroll,
    onScrollChange = onScrollChange,
    empty_text = opts and opts.empty_text or "No details yet",
  })
end

function M.renderSectionLabel(ctx, rect, text)
  ctx:drawText(rect.x, rect.y, ctx:trimText(" " .. text, rect.w), "gold", nil)
end

function M.renderSegmentRow(ctx, rect, label, items, selectedId, onSelect)
  local labelRect, valueRect = M.layout.sliceLeft(rect, math.max(10, math.floor(rect.w * 0.23)), 1)
  ctx:drawText(labelRect.x, labelRect.y, ctx:trimText(label, labelRect.w), "text", nil)
  M.widgets.segmented(ctx, valueRect, items, selectedId, {
    onSelect = onSelect,
  })
end

function M.renderButtonRow(ctx, rect, buttons)
  local visible = {}
  for _, button in ipairs(buttons or {}) do
    if button then
      visible[#visible + 1] = button
    end
  end

  if #visible == 0 then
    return
  end

  local fractions = {}
  for index = 1, #visible do
    fractions[index] = 1 / #visible
  end

  local columns = M.layout.columns(rect, fractions, 1)
  for index, button in ipairs(visible) do
    M.widgets.button(ctx, columns[index], button.label, {
      background = button.background or "surface_alt",
      foreground = button.foreground or "text",
      onClick = button.onClick,
    })
  end
end

function M.renderFormRows(ctx, rect, rows, scroll, onScrollChange)
  local totalHeight = 0
  for _, row in ipairs(rows or {}) do
    totalHeight = totalHeight + (row.height or 1)
  end

  local maxScroll = math.max(0, totalHeight - rect.h)
  local currentScroll = util.clamp(scroll or 0, 0, maxScroll)
  local y = rect.y - currentScroll

  for _, row in ipairs(rows or {}) do
    local height = row.height or 1
    if y + height - 1 >= rect.y and y <= rect.y + rect.h - 1 then
      row.render(ctx, M.layout.rect(rect.x, y, rect.w, height))
    end
    y = y + height
  end

  ctx:addHit(rect, {
    onScroll = function(direction)
      if type(onScrollChange) == "function" then
        onScrollChange(util.clamp(currentScroll + direction, 0, maxScroll))
      end
    end,
  })

  if maxScroll > 0 then
    M.renderScrollButtons(ctx, rect, function()
      if type(onScrollChange) == "function" then
        onScrollChange(util.clamp(currentScroll - 1, 0, maxScroll))
      end
    end, function()
      if type(onScrollChange) == "function" then
        onScrollChange(util.clamp(currentScroll + 1, 0, maxScroll))
      end
    end)
  end

  return maxScroll, currentScroll
end

function M.renderItemTypeMatrix(ctx, rect, selectedTypes, onToggle)
  local rowCount = math.max(1, math.ceil(#constants.SUPPORTED_TYPES / 2))
  local fractions = {}
  for index = 1, rowCount do
    fractions[index] = 1 / rowCount
  end

  local rowRects = M.layout.rows(rect, fractions, 1)
  local index = 1

  for rowIndex = 1, #rowRects do
    local columns = M.layout.columns(rowRects[rowIndex], { 0.5, 0.5 }, 1)
    for columnIndex = 1, #columns do
      local itemType = constants.SUPPORTED_TYPES[index]
      if itemType then
        local enabled = contains(selectedTypes, itemType)
        M.widgets.pill(ctx, columns[columnIndex], itemType, {
          background = enabled and "accent" or "surface_alt",
          foreground = enabled and "text_dark" or "text",
          onClick = function()
            onToggle(itemType)
          end,
        })
      end
      index = index + 1
    end
  end
end

M.selectedStorage = selectedStorage
M.selectedInventoryLabel = selectedInventoryLabel
M.roleLabel = roleLabel
M.inventoryLabel = inventoryLabel

return M
