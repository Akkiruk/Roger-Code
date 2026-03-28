local bedrock = require("lib.bedrock")
local constants = require("lib.vaultgear.constants")
local evaluator = require("lib.vaultgear.evaluator")
local peripherals = require("lib.vaultgear.peripherals")
local routing = require("lib.vaultgear.routing")
local util = require("lib.vaultgear.util")

local M = {}

M.layout = bedrock.layout
M.widgets = bedrock.widgets

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

M.choice_options = {
  miss_action = {
    { label = "Keep", value = "keep" },
    { label = "Trash", value = "discard" },
  },
  unidentified_mode = {
    { label = "Keep", value = "keep" },
    { label = "Trash", value = "discard" },
    { label = "Basic", value = "evaluate_basic" },
  },
  wanted_modifier_mode = {
    { label = "Any", value = "any" },
    { label = "All", value = "all" },
  },
  route_action = {
    { label = "Keep", value = "keep" },
    { label = "Trash", value = "discard" },
    { label = "Any", value = "any" },
  },
  route_type_mode = {
    { label = "All Types", value = "all" },
    { label = "Selected", value = "selected" },
  },
  min_rarity = {
    { label = "Off", value = "ANY" },
    { label = "Scrappy+", value = "SCRAPPY" },
    { label = "Common+", value = "COMMON" },
    { label = "Rare+", value = "RARE" },
    { label = "Epic+", value = "EPIC" },
    { label = "Omega+", value = "OMEGA" },
    { label = "Unique+", value = "UNIQUE" },
    { label = "Special+", value = "SPECIAL" },
    { label = "Chaotic+", value = "CHAOTIC" },
  },
}

M.numeric_labels = {
  min_level = "Min Level",
  max_level = "Max Level",
  min_crafting_potential = "Min CP",
  min_free_repair_slots = "Free Repairs",
  min_durability_percent = "Durability %",
  max_jewel_size = "Max Jewel Size",
  min_uses = "Min Uses",
}

M.numeric_order = {
  "min_level",
  "max_level",
  "min_crafting_potential",
  "min_free_repair_slots",
  "min_durability_percent",
  "max_jewel_size",
  "min_uses",
}

M.safety_fields = {
  "keep_legendary",
  "keep_soulbound",
  "keep_unique",
}

M.type_nav_items = {}
for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
  M.type_nav_items[#M.type_nav_items + 1] = {
    id = itemType,
    label = itemType,
  }
end

function M.supportsField(itemType, field)
  for _, entry in ipairs(constants.PROFILE_FIELDS[itemType] or {}) do
    if entry == field then
      return true
    end
  end
  return false
end

function M.actionText(action)
  if action == "discard" then
    return "Trash"
  end
  if action == "any" then
    return "Any"
  end
  return "Keep"
end

function M.unidentifiedText(mode)
  if mode == "discard" then
    return "Trash"
  end
  if mode == "evaluate_basic" then
    return "Basic"
  end
  return "Keep"
end

function M.currentFilterText(profile)
  if not profile then
    return "No profile"
  end
  if not evaluator.profileHasActiveFilters(profile) then
    return "No keep filters"
  end
  if profile.min_rarity and profile.min_rarity ~= "ANY" then
    return profile.min_rarity .. "+"
  end
  if profile.min_uses then
    return tostring(profile.min_uses) .. "+ uses"
  end
  if profile.max_jewel_size then
    return "size <= " .. tostring(profile.max_jewel_size)
  end
  if profile.min_level and profile.max_level then
    return "Lv " .. tostring(profile.min_level) .. "-" .. tostring(profile.max_level)
  end
  if profile.min_level then
    return "Lv " .. tostring(profile.min_level) .. "+"
  end
  if profile.max_level then
    return "Lv <= " .. tostring(profile.max_level)
  end
  if profile.min_crafting_potential then
    return "CP >= " .. tostring(profile.min_crafting_potential)
  end
  if profile.min_free_repair_slots then
    return "repairs >= " .. tostring(profile.min_free_repair_slots)
  end
  if profile.min_durability_percent then
    return "durability >= " .. tostring(profile.min_durability_percent) .. "%"
  end
  if profile.wanted_modifiers and #profile.wanted_modifiers > 0 then
    if profile.wanted_modifier_mode == "all" then
      return "all wanted mods"
    end
    return "any wanted mod"
  end
  if profile.blocked_modifiers and #profile.blocked_modifiers > 0 then
    return "blocked mod rules"
  end
  return "Active rules"
end

function M.selectedTypeWarning(app, itemType)
  for _, warning in ipairs(app.health.warnings or {}) do
    if warning:find(itemType, 1, true) == 1 then
      return warning
    end
  end
  return nil
end

local function firstConfiguredRouteText(app)
  if not app.config.routing.input or app.config.routing.input == "" then
    return "Choose the input inventory first."
  end

  local destinations = app.config.routing.destinations or {}
  if #destinations == 0 then
    return "Add at least one destination."
  end

  for _, destination in ipairs(destinations) do
    if destination.enabled ~= false and destination.inventory and destination.inventory ~= "" then
      return nil
    end
  end

  return "Give at least one destination an inventory."
end

function M.nextStep(app)
  if not app.health.monitor_ok and app.health.monitor_error then
    return app.health.monitor_error
  end
  if #app.health.errors > 0 then
    return app.health.errors[1]
  end

  local routingStep = firstConfiguredRouteText(app)
  if routingStep then
    return routingStep
  end

  local gearProfile = app.config.type_profiles.Gear
  if gearProfile and evaluator.profileHasActiveFilters(gearProfile) and gearProfile.miss_action == "keep" then
    return "Gear misses still go to Keep. Flip Misses Go To when you want misses trashed."
  end
  if gearProfile and evaluator.profileHasActiveFilters(gearProfile) and gearProfile.unidentified_mode == "keep" then
    return "Unidentified gear is bypassing filters. Use Basic or Trash when you are ready."
  end
  if not app.config.runtime.enabled then
    return "Review the flow, then press Start when the preview matches your intent."
  end
  if #(app.preview.items or {}) == 0 then
    return "Drop Vault gear into the input inventory to generate a live preview."
  end
  return "Tap any preview item to inspect the exact decision path."
end

function M.summaryLinesForProfile(app, itemType)
  local profile = app.config.type_profiles[itemType]
  if not profile then
    return {
      "No profile loaded.",
      "Misses -> Keep | Unidentified -> Keep",
      "Apply a preset to start shaping the profile.",
    }
  end

  local line1 = itemType .. ": " .. M.currentFilterText(profile)
  local line2 = "Misses -> " .. M.actionText(profile.miss_action) .. " | Unidentified -> " .. M.unidentifiedText(profile.unidentified_mode)
  local line3 = M.selectedTypeWarning(app, itemType)

  if not line3 then
    local alwaysKeep = {}
    if profile.keep_legendary then
      alwaysKeep[#alwaysKeep + 1] = "Legendary"
    end
    if profile.keep_soulbound then
      alwaysKeep[#alwaysKeep + 1] = "Soulbound"
    end
    if profile.keep_unique then
      alwaysKeep[#alwaysKeep + 1] = "Unique"
    end

    if #alwaysKeep > 0 then
      line3 = "Safety keeps: " .. table.concat(alwaysKeep, ", ")
    else
      line3 = string.format(
        "Modifiers: Keep %d | Block %d",
        #(profile.wanted_modifiers or {}),
        #(profile.blocked_modifiers or {})
      )
    end
  end

  return { line1, line2, line3 }
end

function M.previewBadge(entry)
  if entry and entry.decision and entry.decision.action == "discard" then
    return "TRASH", "danger"
  end
  return "KEEP", "success"
end

function M.findInventoryLabel(app, inventoryName)
  if not inventoryName or inventoryName == "" then
    return "Not set"
  end
  local entry = peripherals.findInventory(app.discovery, inventoryName)
  if entry then
    return entry.label
  end
  return inventoryName .. " (missing)"
end

function M.selectedDestination(app)
  return routing.findDestination(app.config.routing.destinations, app.ui.selected_destination_id)
end

local function destinationTitle(app, destination, index)
  local prefix = tostring(index or "?") .. ". "
  local inventory = M.findInventoryLabel(app, destination and destination.inventory)
  if destination and destination.enabled == false then
    return prefix .. "Paused -> " .. inventory
  end
  return prefix .. routing.actionSummary(destination) .. " -> " .. inventory
end

function M.routeFlowSummary(app)
  local parts = {}
  for index, destination in ipairs(app.config.routing.destinations or {}) do
    if destination.enabled ~= false then
      parts[#parts + 1] = string.format(
        "%d:%s->%s",
        index,
        routing.actionSummary(destination),
        M.findInventoryLabel(app, destination.inventory)
      )
      if #parts >= 3 then
        break
      end
    end
  end

  if #parts == 0 then
    return "Routes: none configured"
  end
  return "Routes: " .. table.concat(parts, " | ")
end

local function formatRecentEntry(entry)
  local stamp = util.formatTime(entry.at)
  return "[" .. stamp .. "] " .. tostring(entry.message or "")
end

function M.flattenLines(sourceLines, width, limit)
  local lines = {}
  for _, source in ipairs(sourceLines or {}) do
    local wrapped = util.wrapText(source, width, limit - #lines)
    for _, wrappedLine in ipairs(wrapped) do
      lines[#lines + 1] = wrappedLine
      if #lines >= limit then
        return lines
      end
    end
  end
  return lines
end

function M.selectedDecisionLines(app, entry)
  if not entry then
    return {
      "No preview item selected yet.",
      "Scan the input inventory to populate the preview list.",
    }
  end

  local item = entry.item or {}
  local decision = entry.decision or {}
  local destination = entry.destination
  local reasons = decision.reasons or {}
  local lines = {}

  lines[#lines + 1] = tostring(item.display_name or item.registry_name or "Item")
  lines[#lines + 1] = string.upper(M.actionText(decision.action)) .. ": " .. tostring(reasons[1] or "No decision details")
  if destination then
    lines[#lines + 1] = "Route: " .. routing.actionSummary(destination) .. " -> " .. M.findInventoryLabel(app, destination.inventory)
  else
    lines[#lines + 1] = "Route: no matching destination"
  end

  local stats = {
    item.item_type or "Non-Vault",
    item.rarity or "-",
    "Lv" .. tostring(item.level or "-"),
  }
  if item.identified == false then
    stats[#stats + 1] = "Unidentified"
  end
  lines[#lines + 1] = table.concat(stats, " | ")

  if type(item.crafting_potential_current) == "number" and type(item.crafting_potential_max) == "number" then
    lines[#lines + 1] = "Crafting potential: " .. item.crafting_potential_current .. "/" .. item.crafting_potential_max
  end
  if type(item.repair_free) == "number" and type(item.repair_total) == "number" then
    lines[#lines + 1] = "Repair slots: " .. item.repair_free .. " free of " .. item.repair_total
  end
  if type(item.durability_percent) == "number" then
    lines[#lines + 1] = "Durability: " .. util.formatPercent(item.durability_percent)
  end
  if type(item.jewel_size) == "number" then
    lines[#lines + 1] = "Jewel size: " .. tostring(item.jewel_size)
  end
  if type(item.uses) == "number" then
    lines[#lines + 1] = "Uses: " .. tostring(item.uses)
  end

  local tags = {}
  if item.is_soulbound then
    tags[#tags + 1] = "Soulbound"
  end
  if item.is_unique then
    tags[#tags + 1] = "Unique"
  end
  if item.is_legendary then
    tags[#tags + 1] = "Legendary"
  end
  if #tags > 0 then
    lines[#lines + 1] = "Tags: " .. table.concat(tags, ", ")
  end

  for index = 2, math.min(#reasons, 5) do
    lines[#lines + 1] = "Reason: " .. reasons[index]
  end

  local modifiers = {}
  for _, modifier in ipairs(item.modifiers and item.modifiers.all or {}) do
    modifiers[#modifiers + 1] = modifier.label
    if #modifiers >= 4 then
      break
    end
  end
  if #modifiers > 0 then
    lines[#lines + 1] = "Seen mods: " .. table.concat(modifiers, ", ")
  end

  return lines
end

function M.levelTone(level)
  if level == "error" then
    return "danger"
  end
  if level == "warning" then
    return "warning"
  end
  if level == "success" then
    return "success"
  end
  return "text"
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

function M.optionLabel(options, value, fallback)
  for _, option in ipairs(options or {}) do
    if option.value == value then
      return option.label
    end
  end
  return fallback or tostring(value or "Off")
end

function M.cycleOption(options, current, delta)
  if type(options) ~= "table" or #options == 0 then
    return current
  end

  local index = 1
  for candidateIndex, option in ipairs(options) do
    if option.value == current then
      index = candidateIndex
      break
    end
  end

  index = index + delta
  if index < 1 then
    index = #options
  elseif index > #options then
    index = 1
  end
  return options[index].value
end

function M.buildInventoryChoices(app, opts)
  local options = {}
  local seen = {}
  local settings = opts or {}
  local current = settings.current

  local function push(label, value)
    local key = tostring(value)
    if seen[key] then
      return
    end
    seen[key] = true
    options[#options + 1] = { label = label, value = value }
  end

  if settings.include_none then
    push("Not set", nil)
  end

  if current ~= nil and current ~= "" then
    local found = peripherals.findInventory(app.discovery, current)
    if settings.exclude_input and current == app.config.routing.input then
      push(M.findInventoryLabel(app, current) .. " (input)", current)
    elseif not found then
      push(current .. " (missing)", current)
    end
  end

  for _, entry in ipairs(app.discovery.inventories or {}) do
    if not (settings.exclude_input and entry.name == app.config.routing.input) then
      push(entry.label, entry.name)
    end
  end

  return options
end

function M.inventoryLabelFromChoices(options, current)
  for _, option in ipairs(options or {}) do
    if option.value == current then
      return option.label
    end
  end
  if current == nil or current == "" then
    return "Not set"
  end
  return tostring(current)
end

function M.cycleInventory(app, current, delta, opts)
  return M.cycleOption(M.buildInventoryChoices(app, {
    include_none = opts and opts.include_none or false,
    exclude_input = opts and opts.exclude_input or false,
    current = current,
  }), current, delta)
end

function M.selectedPreviewEntry(app)
  return (app.preview.items or {})[app.ui.preview_selected or 1]
end

function M.focusedType(app)
  local selected = M.selectedPreviewEntry(app)
  if selected and selected.item and selected.item.supported_type and selected.item.item_type then
    return selected.item.item_type
  end
  return app.ui.selected_type
end

function M.buildPreviewItems(app)
  local items = {}
  for index, entry in ipairs(app.preview.items or {}) do
    local badge, tone = M.previewBadge(entry)
    local name = entry.item and entry.item.display_name or ("Slot " .. tostring(entry.slot))
    local itemType = entry.item and entry.item.item_type or "Item"
    items[#items + 1] = {
      id = index,
      text = string.format("%s  %s  [%s]", badge, name, itemType),
      fg = tone,
    }
  end
  return items
end

function M.buildRecentItems(app)
  local items = {}
  for index = #app.recent, 1, -1 do
    local entry = app.recent[index]
    items[#items + 1] = {
      id = index,
      text = formatRecentEntry(entry),
      fg = M.levelTone(entry.level),
    }
  end
  return items
end

function M.buildHealthItems(app)
  local items = {}
  if not app.health.monitor_ok and app.health.monitor_error then
    items[#items + 1] = { id = "monitor", text = app.health.monitor_error, fg = "danger" }
  end
  for index, message in ipairs(app.health.errors or {}) do
    items[#items + 1] = { id = "error_" .. tostring(index), text = message, fg = "danger" }
  end
  for index, message in ipairs(app.health.warnings or {}) do
    items[#items + 1] = { id = "warning_" .. tostring(index), text = message, fg = "warning" }
  end
  if #items == 0 then
    items[1] = {
      id = "healthy",
      text = "Routing, monitor, and profiles look healthy.",
      fg = "success",
    }
  end
  return items
end

function M.affixSummary(entry)
  local kinds = {}
  for key, enabled in pairs(entry and entry.affix_types or {}) do
    if enabled then
      kinds[#kinds + 1] = key
    end
  end
  table.sort(kinds)
  if #kinds == 0 then
    return "catalog"
  end
  return table.concat(kinds, "/")
end

function M.buildCatalogItems(app)
  local items = {}
  for _, entry in ipairs(app.catalog_entries or {}) do
    items[#items + 1] = {
      id = entry.key,
      text = string.format("%s  x%d  [%s]", entry.label or entry.key, entry.seen or 0, M.affixSummary(entry)),
      fg = "gold",
    }
  end
  return items
end

function M.buildRuleItems(entries, tone)
  local items = {}
  for _, entry in ipairs(entries or {}) do
    items[#items + 1] = {
      id = entry.key,
      text = entry.label or entry.key,
      fg = tone,
    }
  end
  return items
end

function M.buildRouteItems(app)
  local items = {}
  for index, destination in ipairs(app.config.routing.destinations or {}) do
    items[#items + 1] = {
      id = destination.id,
      text = destinationTitle(app, destination, index),
      fg = destination.enabled == false and "muted" or "text",
    }
  end
  return items
end

function M.findCatalogEntry(app, key)
  for _, entry in ipairs(app.catalog_entries or {}) do
    if entry.key == key then
      return entry
    end
  end
  return nil
end

function M.selectedModifierLines(app)
  local profile = app.config.type_profiles[app.ui.selected_type] or {}
  local key = app.ui.selected_modifier_key or app.ui.selected_keep_key or app.ui.selected_block_key
  if not key then
    return {
      "Choose a modifier from the catalog or your Keep/Block lists.",
      string.format(
        "Discovered %d | Keep %d | Block %d",
        #(app.catalog_entries or {}),
        #(profile.wanted_modifiers or {}),
        #(profile.blocked_modifiers or {})
      ),
      "Use Keep or Block to turn the catalog into actual rules.",
    }
  end

  local source = "Catalog"
  if app.ui.selected_keep_key == key then
    source = "Keep"
  elseif app.ui.selected_block_key == key then
    source = "Block"
  end

  local catalogEntry = M.findCatalogEntry(app, key)
  local label = catalogEntry and (catalogEntry.label or catalogEntry.key) or key
  if source == "Keep" then
    local entry = util.findByKey(profile.wanted_modifiers, key)
    label = entry and (entry.label or entry.key) or label
  elseif source == "Block" then
    local entry = util.findByKey(profile.blocked_modifiers, key)
    label = entry and (entry.label or entry.key) or label
  end

  local lines = { source .. ": " .. tostring(label) }
  if catalogEntry then
    lines[#lines + 1] = "Seen " .. tostring(catalogEntry.seen or 0) .. " times | " .. M.affixSummary(catalogEntry)
  else
    lines[#lines + 1] = "Not yet rediscovered in the live catalog."
  end
  lines[#lines + 1] = string.format(
    "Keep %d | Block %d for %s",
    #(profile.wanted_modifiers or {}),
    #(profile.blocked_modifiers or {}),
    app.ui.selected_type
  )
  return lines
end

function M.createViewState()
  return {
    preview_scroll = 0,
    detail_scroll = 0,
    recent_scroll = 0,
    rules_scroll = {},
    catalog_scroll = {},
    keep_scroll = {},
    block_scroll = {},
    health_scroll = 0,
    route_scroll = 0,
    last_preview_selected = nil,
    last_selected_type = nil,
  }
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
    selected_background = options.selected_background,
    selected_foreground = options.selected_foreground,
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
  local wrapped = M.flattenLines(lines, math.max(6, rect.w - 5), 200)
  local items = {}
  for index, line in ipairs(wrapped) do
    items[#items + 1] = {
      id = index,
      text = line,
      fg = opts and opts.foreground or "text",
    }
  end

  return M.renderListCard(ctx, rect, {
    title = title,
    accent = opts and opts.accent or "accent",
    actions = opts and opts.actions or nil,
    items = items,
    scroll = scroll,
    onScrollChange = onScrollChange,
    empty_text = opts and opts.empty_text or "No details yet",
  })
end

function M.renderSectionLabel(ctx, rect, text)
  ctx:drawText(rect.x, rect.y, ctx:trimText(" " .. text, rect.w), "gold", nil)
end

function M.renderSegmentRow(ctx, rect, label, options, selectedValue, onSelect)
  local labelRect, valueRect = M.layout.sliceLeft(rect, math.max(12, math.floor(rect.w * 0.24)), 1)
  ctx:drawText(labelRect.x, labelRect.y, ctx:trimText(label, labelRect.w), "text", nil)

  local items = {}
  for _, option in ipairs(options or {}) do
    items[#items + 1] = { id = option.value, label = option.label }
  end

  M.widgets.segmented(ctx, valueRect, items, selectedValue, {
    onSelect = onSelect,
  })
end

function M.renderTypeRail(ctx, rect, selectedType, onSelect)
  local rail = M.widgets.card(ctx, rect, {
    title = "Types",
    accent = "accent_alt",
  })
  if rail.w <= 0 or rail.h <= 0 then
    return
  end
  M.widgets.nav(ctx, rail, M.type_nav_items, selectedType, {
    orientation = "vertical",
    gap = 0,
    onSelect = onSelect,
  })
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

function M.renderTypeMatrix(ctx, rect, destination, actions)
  local rowRects = M.layout.rows(rect, { 0.34, 0.33, 0.33 }, 0)
  local index = 1
  for rowIndex = 1, #rowRects do
    local columns = M.layout.columns(rowRects[rowIndex], { 0.5, 0.5 }, 1)
    for columnIndex = 1, #columns do
      local itemType = constants.SUPPORTED_TYPES[index]
      if itemType then
        local enabled = false
        for _, matched in ipairs(destination.match_types or {}) do
          if matched == itemType then
            enabled = true
            break
          end
        end
        M.widgets.pill(ctx, columns[columnIndex], itemType, {
          background = enabled and "accent" or "surface_alt",
          foreground = enabled and "text_dark" or "text",
          onClick = function()
            actions.setDestinationType(itemType, not enabled)
          end,
        })
      end
      index = index + 1
    end
  end
end

return M
