local ui = require("lib.ui")
local constants = require("lib.vaultgear.constants")
local pages = require("lib.vaultgear.ui_pages")
local shared = require("lib.vaultgear.ui_shared")

local M = {}

local function activeInspectInterval(app)
  local configured = tonumber(app.config.runtime.scan_interval) or constants.INSPECT_INTERVAL_ACTIVE
  if configured < 0.25 then
    configured = 0.25
  end
  if configured > constants.INSPECT_INTERVAL_ACTIVE then
    configured = constants.INSPECT_INTERVAL_ACTIVE
  end
  return configured
end

local function inspectInterval(app)
  if app.ui.page == "storages" or app.ui.page == "live" then
    return activeInspectInterval(app)
  end
  return constants.INSPECT_INTERVAL_BACKGROUND
end

function M.create(app, actions)
  local runtime = ui.createRuntime({
    theme = shared.theme,
    term = term.current(),
  })

  local view = shared.createViewState()

  local function syncJobs()
    runtime:setJobInterval("inspect", inspectInterval(app))
    runtime:setJobInterval("work", constants.WORK_INTERVAL)
    runtime:setJobInterval("save", constants.SAVE_INTERVAL)
  end

  local controller = {}

  function controller:rebindTerm()
    if app.monitor and app.monitor.peripheral then
      runtime:setTerm(app.monitor.peripheral, app.monitor.name)
    else
      runtime:setTerm(term.current(), nil)
    end
    syncJobs()
  end

  function controller:refreshHeader()
    syncJobs()
    runtime:invalidate()
  end

  function controller:refreshSetup()
    syncJobs()
    runtime:invalidate()
  end

  function controller:refreshLive()
    syncJobs()
    runtime:invalidate()
  end

  function controller:refreshAll()
    syncJobs()
    runtime:invalidate()
  end

  function controller:notify(level, title, message)
    runtime:addToast(level, title, message, 3)
  end

  function controller:run()
    self:rebindTerm()
    runtime:run()
  end

  runtime:setBuild(function(ctx)
    pages.renderApp(ctx, app, actions, view)
  end)

  runtime:setHandlers({
    peripheral = function(kind)
      actions.onPeripheralEvent(kind)
    end,
    terminate = function()
      actions.onTerminate()
    end,
  })

  runtime:setJob("inspect", inspectInterval(app), actions.onInspectTimer)
  runtime:setJob("work", constants.WORK_INTERVAL, actions.onWorkTimer)
  runtime:setJob("save", constants.SAVE_INTERVAL, actions.onSaveTimer)

  return controller
end

return M
