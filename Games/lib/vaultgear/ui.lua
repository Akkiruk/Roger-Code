local bedrock = require("lib.bedrock")
local pages = require("lib.vaultgear.ui_pages")
local shared = require("lib.vaultgear.ui_shared")

local M = {}

function M.create(app, actions)
  local runtime = bedrock.createRuntime({
    theme = shared.theme,
    term = term.current(),
  })

  local view = shared.createViewState()

  local function syncJobs()
    runtime:setJobInterval("sort", app.config.runtime.scan_interval or 2)
  end

  local controller = {}

  function controller:rebindTerm()
    syncJobs()
    if app.monitor and app.monitor.peripheral then
      runtime:setTerm(app.monitor.peripheral, app.monitor.name)
    else
      runtime:setTerm(term.current(), nil)
    end
  end

  function controller:refreshHeader()
    syncJobs()
    runtime:invalidate()
  end

  function controller:refreshDashboard()
    syncJobs()
    runtime:invalidate()
  end

  function controller:refreshModifiers()
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

  runtime:setJob("preview", 2, actions.onPreviewTimer)
  runtime:setJob("sort", app.config.runtime.scan_interval or 2, actions.onSortTimer)
  runtime:setJob("save", 10, actions.onSaveTimer)

  return controller
end

return M
