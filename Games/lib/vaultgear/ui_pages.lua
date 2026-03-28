local constants = require("lib.vaultgear.constants")
local shared = require("lib.vaultgear.ui_shared")
local util = require("lib.vaultgear.util")

local M = {}

local layout = shared.layout
local widgets = shared.widgets

local function buildRuleRows(app, actions, itemType)
  local rows = {}
  local profile = app.config.type_profiles[itemType] or {}

  local function addRow(render)
    rows[#rows + 1] = { height = 1, render = render }
  end

  local function addSpacer()
    addRow(function() end)
  end

  local function addSection(text)
    addRow(function(ctx, rect)
      shared.renderSectionLabel(ctx, rect, text)
    end)
  end

  local presets = {}
  for _, preset in ipairs(constants.PROFILE_PRESETS[itemType] or {}) do
    presets[#presets + 1] = { id = preset.id, label = preset.label }
  end

  addSection("Quick Presets")
  if #presets > 0 then
    addRow(function(ctx, rect)
      widgets.nav(ctx, rect, presets, nil, {
        gap = 1,
        onSelect = function(id)
          actions.applyPreset(itemType, id)
        end,
      })
    end)
  end

  addSpacer()
  addSection("Flow")
  addRow(function(ctx, rect)
    widgets.toggle(ctx, rect, "Profile Enabled", profile.enabled ~= false, {
      onClick = function()
        actions.setProfileFlag(itemType, "enabled", profile.enabled ~= true)
      end,
    })
  end)
  addRow(function(ctx, rect)
    widgets.selector(ctx, rect, "Misses", shared.actionText(profile.miss_action), {
      onPrev = function()
        actions.setProfileChoice(itemType, "miss_action", shared.cycleOption(shared.choice_options.miss_action, profile.miss_action, -1))
      end,
      onNext = function()
        actions.setProfileChoice(itemType, "miss_action", shared.cycleOption(shared.choice_options.miss_action, profile.miss_action, 1))
      end,
    })
  end)
  addRow(function(ctx, rect)
    widgets.selector(ctx, rect, "Unidentified", shared.unidentifiedText(profile.unidentified_mode), {
      onPrev = function()
        actions.setProfileChoice(
          itemType,
          "unidentified_mode",
          shared.cycleOption(shared.choice_options.unidentified_mode, profile.unidentified_mode, -1)
        )
      end,
      onNext = function()
        actions.setProfileChoice(
          itemType,
          "unidentified_mode",
          shared.cycleOption(shared.choice_options.unidentified_mode, profile.unidentified_mode, 1)
        )
      end,
    })
  end)
  addRow(function(ctx, rect)
    widgets.selector(ctx, rect, "Wanted Mode", shared.optionLabel(shared.choice_options.wanted_modifier_mode, profile.wanted_modifier_mode, "Any"), {
      onPrev = function()
        actions.setProfileChoice(
          itemType,
          "wanted_modifier_mode",
          shared.cycleOption(shared.choice_options.wanted_modifier_mode, profile.wanted_modifier_mode, -1)
        )
      end,
      onNext = function()
        actions.setProfileChoice(
          itemType,
          "wanted_modifier_mode",
          shared.cycleOption(shared.choice_options.wanted_modifier_mode, profile.wanted_modifier_mode, 1)
        )
      end,
    })
  end)
  if shared.supportsField(itemType, "min_rarity") then
    addRow(function(ctx, rect)
      widgets.selector(ctx, rect, "Min Rarity", shared.optionLabel(shared.choice_options.min_rarity, profile.min_rarity, "Off"), {
        onPrev = function()
          actions.setProfileChoice(itemType, "min_rarity", shared.cycleOption(shared.choice_options.min_rarity, profile.min_rarity, -1))
        end,
        onNext = function()
          actions.setProfileChoice(itemType, "min_rarity", shared.cycleOption(shared.choice_options.min_rarity, profile.min_rarity, 1))
        end,
      })
    end)
  end

  addSpacer()
  addSection("Thresholds")
  local thresholdCount = 0
  for _, field in ipairs(shared.numeric_order) do
    if shared.supportsField(itemType, field) then
      thresholdCount = thresholdCount + 1
      addRow(function(ctx, rect)
        widgets.stepper(ctx, rect, shared.numeric_labels[field] or field, tostring(profile[field] or "Off"), {
          onMinus = function()
            actions.adjustProfileNumber(itemType, field, -1)
          end,
          onPlus = function()
            actions.adjustProfileNumber(itemType, field, 1)
          end,
        })
      end)
    end
  end
  if thresholdCount == 0 then
    addRow(function(ctx, rect)
      ctx:drawText(rect.x, rect.y, ctx:trimText("No numeric thresholds for this item type.", rect.w), "muted", nil)
    end)
  end

  local safetyCount = 0
  for _, field in ipairs(shared.safety_fields) do
    if shared.supportsField(itemType, field) then
      if safetyCount == 0 then
        addSpacer()
        addSection("Safety Keeps")
      end
      safetyCount = safetyCount + 1
      addRow(function(ctx, rect)
        widgets.toggle(ctx, rect, constants.PROFILE_LABELS[field] or field, profile[field] == true, {
          onClick = function()
            actions.setProfileFlag(itemType, field, profile[field] ~= true)
          end,
        })
      end)
    end
  end

  addSpacer()
  addSection("Modifier Rules")
  addRow(function(ctx, rect)
    local textRect, buttonRect = layout.sliceLeft(rect, math.max(10, rect.w - 17), 1)
    local countText = string.format("Keep %d | Block %d", #(profile.wanted_modifiers or {}), #(profile.blocked_modifiers or {}))
    ctx:drawText(textRect.x, textRect.y, ctx:trimText(countText, textRect.w), "text", nil)
    widgets.button(ctx, buttonRect, "Open Modifiers", {
      background = "accent",
      foreground = "text_dark",
      onClick = function()
        actions.setPage("modifiers")
      end,
    })
  end)

  return rows
end

local function renderHeader(ctx, rect, app, actions)
  local running = app.config.runtime.enabled
  local accent = shared.accentForApp(app)
  local inner = widgets.card(ctx, rect, {
    title = constants.APP_NAME,
    accent = accent,
    actions = {
      {
        label = "Scan",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.scanNow,
      },
      {
        label = running and "Pause" or "Start",
        background = running and "warning" or "success",
        foreground = "text_dark",
        onClick = actions.toggleRuntime,
      },
    },
  })

  if inner.w <= 0 or inner.h <= 0 then
    return
  end

  local row1, rest = layout.sliceTop(inner, 1, 0)
  local row2, rest = layout.sliceTop(rest, 1, 0)
  local row3, row4 = layout.sliceTop(rest, 1, 0)
  local runtimeRect, remainder = layout.sliceLeft(row1, 10, 1)
  local healthRect, infoRect = layout.sliceLeft(remainder, 12, 1)

  widgets.pill(ctx, runtimeRect, running and "LIVE" or "PAUSED", {
    background = running and "success" or "warning",
    foreground = "text_dark",
  })
  widgets.pill(ctx, healthRect, shared.healthLabel(app), {
    background = accent,
    foreground = "text_dark",
  })

  local inputText = "Input: " .. shared.findInventoryLabel(app, app.config.routing.input)
  local routeText = shared.routeFlowSummary(app)
  ctx:drawText(infoRect.x, infoRect.y, ctx:trimText(inputText .. " | " .. routeText, infoRect.w), "text", nil)

  if row2.h > 0 then
    local metricRects = layout.columns(row2, { 0.21, 0.21, 0.21, 0.17, 0.20 }, 1)
    widgets.pill(ctx, metricRects[1], "Preview " .. tostring(#(app.preview.items or {})), {
      background = "surface_alt",
      foreground = "text",
    })
    widgets.pill(ctx, metricRects[2], "Sorted " .. tostring(app.session.scanned or 0), {
      background = "surface_alt",
      foreground = "text",
    })
    widgets.pill(ctx, metricRects[3], "Keep " .. tostring(app.session.kept or 0), {
      background = "success",
      foreground = "text_dark",
    })
    widgets.pill(ctx, metricRects[4], "Trash " .. tostring(app.session.discarded or 0), {
      background = "danger",
      foreground = "text_dark",
    })
    local lastCycle = app.last_cycle_at and util.formatTime(app.last_cycle_at) or "--:--:--"
    widgets.pill(ctx, metricRects[5], "Last " .. lastCycle, {
      background = "surface_alt",
      foreground = "text",
    })
  end

  if row3.h > 0 then
    local labelRect, progressRect = layout.sliceLeft(row3, 11, 1)
    local processed = (app.session.kept or 0) + (app.session.discarded or 0)
    local keepRatio = processed > 0 and math.floor(((app.session.kept or 0) / processed) * 100 + 0.5) or 0
    ctx:drawText(labelRect.x, labelRect.y, ctx:trimText("Keep Ratio", labelRect.w), "muted", nil)
    widgets.progress(ctx, progressRect, keepRatio, {
      fill = "success",
      show_text = true,
    })
  end

  if row4.h > 0 then
    local tone = accent == "danger" and "danger" or "muted"
    ctx:drawText(row4.x, row4.y, ctx:trimText(shared.nextStep(app), row4.w), tone, nil)
  end
end

local function renderDashboard(ctx, rect, app, actions, view)
  local previewItems = shared.buildPreviewItems(app)
  local selectedEntry = shared.selectedPreviewEntry(app)
  local focusType = shared.focusedType(app)
  view.preview_scroll = shared.ensureVisible(view.preview_scroll, app.ui.preview_selected or 1, math.max(1, rect.h - 2), #previewItems)

  local function handlePreviewSelect(id)
    local index = tonumber(id) or id
    view.detail_scroll = 0
    actions.selectPreview(index)
    local picked = (app.preview.items or {})[index]
    if picked and picked.item and picked.item.supported_type and picked.item.item_type ~= app.ui.selected_type then
      actions.selectType(picked.item.item_type)
    end
  end

  if rect.w >= 86 and rect.h >= 10 then
    local leftRect, rightRect = layout.sliceLeft(rect, math.max(20, math.floor(rect.w * 0.43)), 1)
    local detailRect, bottomRect = layout.sliceTop(rightRect, math.max(5, math.floor(rightRect.h * 0.6)), 1)
    local focusRect, recentRect = layout.sliceLeft(bottomRect, math.max(18, math.floor(bottomRect.w * 0.46)), 1)

    local _, previewScroll = shared.renderListCard(ctx, leftRect, {
      title = "Live Preview",
      accent = "accent",
      items = previewItems,
      selected_id = app.ui.preview_selected,
      scroll = view.preview_scroll,
      onScrollChange = function(value)
        view.preview_scroll = value
      end,
      onSelect = handlePreviewSelect,
      empty_text = "Input inventory is empty",
    })
    view.preview_scroll = previewScroll

    local _, detailScroll = shared.renderWrappedTextCard(
      ctx,
      detailRect,
      "Decision",
      shared.selectedDecisionLines(app, selectedEntry),
      view.detail_scroll,
      function(value)
        view.detail_scroll = value
      end,
      { accent = "accent_alt" }
    )
    view.detail_scroll = detailScroll

    shared.renderWrappedTextCard(ctx, focusRect, "Focus", shared.summaryLinesForProfile(app, focusType), 0, nil, {
      accent = "gold",
      actions = {
        {
          label = "Rules",
          background = "surface_alt",
          foreground = "text",
          onClick = function()
            actions.selectType(focusType)
            actions.setPage("rules")
          end,
        },
        {
          label = "Mods",
          background = "surface_alt",
          foreground = "text",
          onClick = function()
            actions.selectType(focusType)
            actions.setPage("modifiers")
          end,
        },
      },
    })

    local _, recentScroll = shared.renderListCard(ctx, recentRect, {
      title = "Recent Activity",
      accent = "accent_alt",
      actions = {
        {
          label = "Reset",
          background = "surface_alt",
          foreground = "text",
          onClick = actions.resetSession,
        },
      },
      items = shared.buildRecentItems(app),
      scroll = view.recent_scroll,
      onScrollChange = function(value)
        view.recent_scroll = value
      end,
      empty_text = "Waiting for activity",
    })
    view.recent_scroll = recentScroll
    return
  end

  local previewRect, detailRect = layout.sliceTop(rect, math.max(5, math.floor(rect.h * 0.46)), 1)
  local _, previewScroll = shared.renderListCard(ctx, previewRect, {
    title = "Live Preview",
    accent = "accent",
    items = previewItems,
    selected_id = app.ui.preview_selected,
    scroll = view.preview_scroll,
    onScrollChange = function(value)
      view.preview_scroll = value
    end,
    onSelect = handlePreviewSelect,
    empty_text = "Input inventory is empty",
  })
  view.preview_scroll = previewScroll

  local detailLines = shared.selectedDecisionLines(app, selectedEntry)
  detailLines[#detailLines + 1] = ""
  for _, line in ipairs(shared.summaryLinesForProfile(app, focusType)) do
    detailLines[#detailLines + 1] = line
  end

  local _, detailScroll = shared.renderWrappedTextCard(
    ctx,
    detailRect,
    "Decision",
    detailLines,
    view.detail_scroll,
    function(value)
      view.detail_scroll = value
    end,
    { accent = "accent_alt" }
  )
  view.detail_scroll = detailScroll
end

local function renderRules(ctx, rect, app, actions, view)
  local typeRect, contentRect = layout.sliceLeft(rect, 12, 1)
  shared.renderTypeRail(ctx, typeRect, app.ui.selected_type, actions.selectType)

  local summary = shared.summaryLinesForProfile(app, app.ui.selected_type)
  local rows = buildRuleRows(app, actions, app.ui.selected_type)
  local cardInner = widgets.card(ctx, contentRect, {
    title = app.ui.selected_type .. " Rules",
    accent = shared.selectedTypeWarning(app, app.ui.selected_type) and "warning" or "accent",
    actions = {
      {
        label = "Mods",
        background = "surface_alt",
        foreground = "text",
        onClick = function()
          actions.setPage("modifiers")
        end,
      },
    },
  })

  if cardInner.w <= 0 or cardInner.h <= 0 then
    return
  end

  local summaryRect, formRect = layout.sliceTop(cardInner, math.min(3, cardInner.h), 1)
  local summaryLines = shared.flattenLines(summary, math.max(8, summaryRect.w), 6)
  for index = 1, math.min(#summaryLines, summaryRect.h) do
    local tone = index == 3 and shared.selectedTypeWarning(app, app.ui.selected_type) and "warning" or (index == 1 and "gold" or "text")
    ctx:drawText(summaryRect.x, summaryRect.y + index - 1, ctx:trimText(summaryLines[index], summaryRect.w), tone, nil)
  end

  if formRect.h > 0 then
    local scrollKey = app.ui.selected_type
    local maxScroll, currentScroll = shared.renderFormRows(
      ctx,
      formRect,
      rows,
      view.rules_scroll[scrollKey] or 0,
      function(value)
        view.rules_scroll[scrollKey] = value
      end
    )
    view.rules_scroll[scrollKey] = util.clamp(currentScroll, 0, maxScroll)
  end
end

local function renderModifiers(ctx, rect, app, actions, view)
  local typeRect, contentRect = layout.sliceLeft(rect, 12, 1)
  shared.renderTypeRail(ctx, typeRect, app.ui.selected_type, actions.selectType)

  local profile = app.config.type_profiles[app.ui.selected_type] or {}
  local summaryRect, listRect = layout.sliceTop(contentRect, 5, 1)
  local summaryCard = widgets.card(ctx, summaryRect, {
    title = app.ui.selected_type .. " Modifiers",
    accent = "gold",
    actions = {
      {
        label = "Keep",
        background = "success",
        foreground = "text_dark",
        onClick = function()
          actions.addRule("wanted_modifiers")
        end,
      },
      {
        label = "Block",
        background = "danger",
        foreground = "text_dark",
        onClick = function()
          actions.addRule("blocked_modifiers")
        end,
      },
      {
        label = "Del",
        background = "surface_alt",
        foreground = "text",
        onClick = function()
          if app.ui.selected_keep_key then
            actions.removeRule("wanted_modifiers")
          elseif app.ui.selected_block_key then
            actions.removeRule("blocked_modifiers")
          else
            actions.removeRule("wanted_modifiers")
          end
        end,
      },
      {
        label = "Clear",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.clearRules,
      },
    },
  })

  if summaryCard.w > 0 and summaryCard.h > 0 then
    local textRect, modeBarRect = layout.sliceTop(summaryCard, math.max(1, summaryCard.h - 1), 0)
    local lines = shared.flattenLines(shared.selectedModifierLines(app), math.max(8, textRect.w), math.max(1, textRect.h))
    for index = 1, math.min(#lines, textRect.h) do
      local tone = index == 1 and "gold" or "text"
      ctx:drawText(textRect.x, textRect.y + index - 1, ctx:trimText(lines[index], textRect.w), tone, nil)
    end
    if modeBarRect.h > 0 then
      shared.renderSegmentRow(ctx, modeBarRect, "Keep When", shared.choice_options.wanted_modifier_mode, profile.wanted_modifier_mode, function(value)
        actions.setProfileChoice(app.ui.selected_type, "wanted_modifier_mode", value)
      end)
    end
  end

  local columns = layout.columns(listRect, { 0.34, 0.33, 0.33 }, 1)
  local scrollKey = app.ui.selected_type

  local _, catalogScroll = shared.renderListCard(ctx, columns[1], {
    title = "Catalog",
    accent = "gold",
    items = shared.buildCatalogItems(app),
    selected_id = app.ui.selected_modifier_key,
    scroll = view.catalog_scroll[scrollKey] or 0,
    onScrollChange = function(value)
      view.catalog_scroll[scrollKey] = value
    end,
    onSelect = function(id)
      actions.selectCatalogModifier(id)
    end,
    empty_text = "Scan Vault gear to discover modifiers",
  })
  view.catalog_scroll[scrollKey] = catalogScroll

  local _, keepScroll = shared.renderListCard(ctx, columns[2], {
    title = "Keep",
    accent = "success",
    items = shared.buildRuleItems(profile.wanted_modifiers, "success"),
    selected_id = app.ui.selected_keep_key,
    scroll = view.keep_scroll[scrollKey] or 0,
    onScrollChange = function(value)
      view.keep_scroll[scrollKey] = value
    end,
    onSelect = function(id)
      actions.selectKeepRule(id)
    end,
    empty_text = "No keep modifiers saved",
  })
  view.keep_scroll[scrollKey] = keepScroll

  local _, blockScroll = shared.renderListCard(ctx, columns[3], {
    title = "Block",
    accent = "danger",
    items = shared.buildRuleItems(profile.blocked_modifiers, "danger"),
    selected_id = app.ui.selected_block_key,
    scroll = view.block_scroll[scrollKey] or 0,
    onScrollChange = function(value)
      view.block_scroll[scrollKey] = value
    end,
    onSelect = function(id)
      actions.selectBlockRule(id)
    end,
    empty_text = "No blocked modifiers saved",
  })
  view.block_scroll[scrollKey] = blockScroll
end

local function renderSetup(ctx, rect, app, actions, view)
  local leftRect, rightRect = layout.sliceLeft(rect, math.max(22, math.floor(rect.w * 0.36)), 1)
  local systemHeight = math.max(6, math.min(7, leftRect.h - 3))
  local systemRect, healthRect = layout.sliceTop(leftRect, systemHeight, 1)

  local system = widgets.card(ctx, systemRect, {
    title = "System",
    accent = shared.accentForApp(app),
    actions = {
      {
        label = "Refresh",
        background = "surface_alt",
        foreground = "text",
        onClick = function()
          actions.refreshPeripherals(true)
        end,
      },
    },
  })

  if system.w > 0 and system.h > 0 then
    local monitorText = nil
    if app.monitor and app.monitor.peripheral then
      monitorText = string.format("Display: %s %dx%d", app.monitor.name or "monitor", app.monitor.width or 0, app.monitor.height or 0)
    elseif app.config.monitor.name then
      monitorText = "Display missing: " .. tostring(app.config.monitor.name)
    else
      monitorText = "Display: auto-detect"
    end

    local monitorRow, rest = layout.sliceTop(system, 1, 0)
    local inputRow, rest = layout.sliceTop(rest, 1, 0)
    local scanRow, batchRow = layout.sliceTop(rest, 1, 0)
    ctx:drawText(monitorRow.x, monitorRow.y, ctx:trimText(monitorText, monitorRow.w), app.health.monitor_ok and "text" or "warning", nil)

    local inputChoices = shared.buildInventoryChoices(app, {
      include_none = false,
      current = app.config.routing.input,
    })
    widgets.selector(ctx, inputRow, "Input", shared.inventoryLabelFromChoices(inputChoices, app.config.routing.input), {
      onPrev = function()
        actions.setInputInventory(shared.cycleInventory(app, app.config.routing.input, -1, { include_none = false }))
      end,
      onNext = function()
        actions.setInputInventory(shared.cycleInventory(app, app.config.routing.input, 1, { include_none = false }))
      end,
    })

    widgets.stepper(ctx, scanRow, "Scan Interval", tostring(app.config.runtime.scan_interval or 1) .. "s", {
      onMinus = function()
        actions.adjustRuntime("scan_interval", -1)
      end,
      onPlus = function()
        actions.adjustRuntime("scan_interval", 1)
      end,
    })

    if batchRow.h > 0 then
      widgets.stepper(ctx, batchRow, "Batch Size", tostring(app.config.runtime.batch_size or 1), {
        onMinus = function()
          actions.adjustRuntime("batch_size", -1)
        end,
        onPlus = function()
          actions.adjustRuntime("batch_size", 1)
        end,
      })
    end
  end

  local _, healthScroll = shared.renderListCard(ctx, healthRect, {
    title = "Checks",
    accent = shared.accentForApp(app),
    items = shared.buildHealthItems(app),
    scroll = view.health_scroll,
    onScrollChange = function(value)
      view.health_scroll = value
    end,
    empty_text = "All checks passed",
  })
  view.health_scroll = healthScroll

  local routingCard = widgets.card(ctx, rightRect, {
    title = "Routing",
    accent = "accent_alt",
    actions = {
      {
        label = "Add",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.addDestination,
      },
      {
        label = "Del",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.removeDestination,
      },
      {
        label = "^",
        background = "surface_alt",
        foreground = "text",
        onClick = function()
          actions.moveDestination(-1)
        end,
      },
      {
        label = "v",
        background = "surface_alt",
        foreground = "text",
        onClick = function()
          actions.moveDestination(1)
        end,
      },
    },
  })

  if routingCard.w <= 0 or routingCard.h <= 0 then
    return
  end

  local routeListRect, editorRect = layout.sliceLeft(routingCard, math.max(18, math.floor(routingCard.w * 0.38)), 1)
  local _, routeScroll = shared.renderListCard(ctx, routeListRect, {
    title = "Destinations",
    accent = "accent",
    items = shared.buildRouteItems(app),
    selected_id = app.ui.selected_destination_id,
    scroll = view.route_scroll,
    onScrollChange = function(value)
      view.route_scroll = value
    end,
    onSelect = function(id)
      actions.selectDestination(id)
    end,
    empty_text = "No destinations configured",
  })
  view.route_scroll = routeScroll

  local destination = shared.selectedDestination(app)
  local selectedConfig = destination or {}
  local editor = widgets.card(ctx, editorRect, {
    title = selectedConfig.id and ("Route " .. tostring(selectedConfig.id)) or "Route Details",
    accent = "gold",
  })

  if editor.w <= 0 or editor.h <= 0 then
    return
  end

  if not selectedConfig.id then
    ctx:drawText(editor.x, editor.y, ctx:trimText("Select or create a destination to edit it.", editor.w), "muted", nil)
    return
  end

  local enabledRow, rest = layout.sliceTop(editor, 1, 0)
  local inventoryRow, rest = layout.sliceTop(rest, 1, 0)
  local actionRow, rest = layout.sliceTop(rest, 1, 0)
  local modeRow, typeRect = layout.sliceTop(rest, 1, 1)

  widgets.toggle(ctx, enabledRow, "Route Enabled", selectedConfig.enabled ~= false, {
    onClick = function()
      actions.setDestinationEnabled(selectedConfig.enabled == false)
    end,
  })

  local routeInventoryChoices = shared.buildInventoryChoices(app, {
    include_none = true,
    exclude_input = true,
    current = selectedConfig.inventory,
  })
  widgets.selector(ctx, inventoryRow, "Inventory", shared.inventoryLabelFromChoices(routeInventoryChoices, selectedConfig.inventory), {
    onPrev = function()
      actions.setDestinationChoice("inventory", shared.cycleInventory(app, selectedConfig.inventory, -1, {
        include_none = true,
        exclude_input = true,
      }))
    end,
    onNext = function()
      actions.setDestinationChoice("inventory", shared.cycleInventory(app, selectedConfig.inventory, 1, {
        include_none = true,
        exclude_input = true,
      }))
    end,
  })

  shared.renderSegmentRow(ctx, actionRow, "Action", shared.choice_options.route_action, selectedConfig.match_action, function(value)
    actions.setDestinationChoice("match_action", value)
  end)
  shared.renderSegmentRow(ctx, modeRow, "Types", shared.choice_options.route_type_mode, selectedConfig.type_mode, function(value)
    actions.setDestinationChoice("type_mode", value)
  end)

  if typeRect.h > 0 then
    if selectedConfig.type_mode == "selected" then
      shared.renderTypeMatrix(ctx, typeRect, selectedConfig, actions)
    else
      ctx:drawText(typeRect.x, typeRect.y, ctx:trimText("All supported Vault types can use this route.", typeRect.w), "muted", nil)
    end
  end
end

function M.renderApp(ctx, app, actions, view)
  if view.last_preview_selected ~= app.ui.preview_selected then
    view.last_preview_selected = app.ui.preview_selected
    view.detail_scroll = 0
  end
  if view.last_selected_type ~= app.ui.selected_type then
    view.last_selected_type = app.ui.selected_type
  end

  local root = layout.rect(1, 1, ctx.width, ctx.height)
  ctx:fillRect(root, "bg", "text", " ")

  local headerRect, remainder = layout.sliceTop(root, 6, 1)
  local tabsRect, bodyRect = layout.sliceTop(remainder, 1, 1)

  renderHeader(ctx, headerRect, app, actions)
  widgets.nav(ctx, tabsRect, constants.TABS, app.ui.page, {
    onSelect = function(id)
      actions.setPage(id)
    end,
  })

  if bodyRect.w <= 0 or bodyRect.h <= 0 then
    return
  end

  if app.ui.page == "rules" then
    renderRules(ctx, bodyRect, app, actions, view)
  elseif app.ui.page == "modifiers" then
    renderModifiers(ctx, bodyRect, app, actions, view)
  elseif app.ui.page == "setup" then
    renderSetup(ctx, bodyRect, app, actions, view)
  else
    renderDashboard(ctx, bodyRect, app, actions, view)
  end
end

return M
