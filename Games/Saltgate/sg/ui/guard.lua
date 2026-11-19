-- ui/guard.lua
-- A fault in a menu or a side activity must not take the whole game down with it: these wrap a plugin's update and draw, and
-- a screen's draw, so an error is logged (once per distinct message) and the game goes on. A screen that fails to draw is
-- popped, so nobody is left behind a menu that cannot be left. Pure apart from the ctx it is given.
--
--   guard.plugin(plugin)            wraps plugin.update and plugin.draw in place
--   guard.screen(ctx, screenDef)    wraps screenDef.draw; on an error the screen is popped

local M = {}

M.errors = {}
M.seen = {}
M.strict = false -- tests set it: an error is thrown, not logged, so a test sees it

local function report(ctx, name, err)
  local key = name .. ": " .. tostring(err)
  M.errors[#M.errors + 1] = key
  if #M.errors > 50 then table.remove(M.errors, 1) end
  if ctx and ctx.log and not M.seen[key] then
    M.seen[key] = true
    ctx.log("guarded " .. key)
  end
end

--- Wrap update and draw of a plugin table so an error is logged and skipped.
function M.plugin(p)
  for _, fnName in ipairs({ "update", "draw" }) do
    local fn = p[fnName]
    if type(fn) == "function" and not p["_guarded_" .. fnName] then
      p["_guarded_" .. fnName] = true
      p[fnName] = function(ctx, ...)
        if M.strict then return fn(ctx, ...) end
        local ok, err = pcall(fn, ctx, ...)
        if not ok then report(ctx, p.name .. "." .. fnName, err) end
      end
    end
  end
  return p
end

--- Wrap a registered screen's draw: on an error the screen is popped (if it is on top) and the error logged.
function M.screen(ctx, def)
  local fn = def.draw
  if def._guarded then return def end
  def._guarded = true
  def.draw = function(c, ...)
    if M.strict then return fn(c, ...) end
    local ok, err = pcall(fn, c, ...)
    if not ok then
      report(c or ctx, "screen " .. tostring(def.name), err)
      local top = c.ui.top()
      if top == def and c.ui.depth() > 1 then c.ui.pop() end
    end
  end
  return def
end

return M
