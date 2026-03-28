local runtime = require("lib.bedrock.runtime")
local layout = require("lib.bedrock.layout")
local theme = require("lib.bedrock.theme")
local widgets = require("lib.bedrock.widgets")

local M = {
  createRuntime = runtime.create,
  layout = layout,
  theme = theme,
  widgets = widgets,
}

return M
