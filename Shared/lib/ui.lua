local bedrock = require("lib.bedrock")
local surface = require("lib.ui_surface")
local text = require("lib.ui_text")
local touch = require("lib.ui_touch")

local M = {}

for key, value in pairs(surface) do
  M[key] = value
end

M.bedrock = bedrock
M.createRuntime = bedrock.createRuntime
M.layout = bedrock.layout
M.theme = bedrock.theme
M.widgets = bedrock.widgets

M.text = text
M.touch = touch
M.trimText = text.trimText
M.truncateText = text.truncateText
M.wrapText = text.wrapText
M.isAuthorizedMonitorTouch = touch.isAuthorizedMonitorTouch

return M
