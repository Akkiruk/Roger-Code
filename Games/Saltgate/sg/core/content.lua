-- core/content.lua
-- Reading the game's content files from content/ (installed with the game): packed chunks, Lua data tables and
-- mission scripts, with a small cache so what is used often is read once. Pure apart from the file system it is given.
--
--   local content = contentLib.new({ fs = fs, root = "content", cache = 8, yield = function() ... end })
--   content:text(path)        -> the file's text, or nil, err
--   content:data(path)        -> a Lua data file ("return { ... }", run with no globals at all), or nil, err
--   content:chunks(path)      -> { ["cx,cz"] = chunk } from a .sgc file (one packed chunk a line), or nil, err
--   content:script(path)      -> the function a mission script file returns (see core/script.lua), or nil, err
--   content:list(dir)         -> file names in content/dir, sorted
--   content:exists(path)
-- Paths are relative to the root and may not climb out of it.

local chunkLib = require("sg.core.chunk")

local M = {}
local C = {}
C.__index = C

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    fs = opts.fs or rawget(_G, "fs"),
    root = opts.root or "content",
    cacheSize = opts.cache or 8,
    yield = opts.yield,
    cached = {},
    useCount = 0,
  }, C)
end

local function full(self, path)
  if type(path) ~= "string" or path:find("%.%.") or path:sub(1, 1) == "/" then
    return nil, "bad content path " .. tostring(path)
  end
  return self.root .. "/" .. path
end

function C:exists(path)
  local p = full(self, path)
  return p ~= nil and self.fs.exists(p)
end

function C:list(dir)
  local p = full(self, dir or "")
  if not p or not self.fs.exists(p) then return {} end
  local names = self.fs.list(p)
  table.sort(names)
  return names
end

function C:text(path)
  local p, err = full(self, path)
  if not p then return nil, err end
  if not self.fs.exists(p) then return nil, "no content file " .. path end
  local h = self.fs.open(p, "r")
  if not h then return nil, "cannot open " .. path end
  local text = h.readAll()
  h.close()
  if self.yield then self.yield() end
  return text
end

local function remember(self, key, value)
  self.useCount = self.useCount + 1
  self.cached[key] = { value = value, used = self.useCount }
  local n, oldKey, old = 0, nil, math.huge
  for k, e in pairs(self.cached) do
    n = n + 1
    if e.used < old then oldKey, old = k, e.used end
  end
  if n > self.cacheSize and oldKey then self.cached[oldKey] = nil end
  return value
end

local function recall(self, key)
  local e = self.cached[key]
  if not e then return nil end
  self.useCount = self.useCount + 1
  e.used = self.useCount
  return e.value
end

--- Compile Lua source with only the given environment (Lua 5.1 and 5.2 alike).
function M.compile(src, name, env)
  local fn, err
  local setfenv_ = rawget(_G, "setfenv")
  if setfenv_ and rawget(_G, "loadstring") then
    fn, err = loadstring(src, "=" .. name)
    if fn then setfenv_(fn, env) end
  else
    fn, err = load(src, "=" .. name, "t", env)
  end
  return fn, err
end

function C:data(path)
  local key = "data:" .. path
  local hit = recall(self, key)
  if hit then return hit end
  local text, err = self:text(path)
  if not text then return nil, err end
  local fn, cerr = M.compile(text, path, {})
  if not fn then return nil, cerr end
  local ok, value = pcall(fn)
  if not ok then return nil, value end
  if type(value) ~= "table" then return nil, path .. " did not return a table" end
  return remember(self, key, value)
end

function C:chunks(path)
  local key = "chunks:" .. path
  local hit = recall(self, key)
  if hit then return hit end
  local text, err = self:text(path)
  if not text then return nil, err end
  local list, perr = chunkLib.unpackMany(text)
  if not list then return nil, path .. ": " .. tostring(perr) end
  return remember(self, key, list)
end

--- A mission script: the file returns function(api). Its globals are the safe parts of Lua only.
function C:script(path)
  local text, err = self:text(path)
  if not text then return nil, err end
  local env = {
    math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, type = type, tostring = tostring,
    tonumber = tonumber, select = select, error = error, assert = assert, next = next, unpack = rawget(_G, "unpack") or table.unpack,
  }
  local fn, cerr = M.compile(text, path, env)
  if not fn then return nil, cerr end
  local ok, value = pcall(fn)
  if not ok then return nil, value end
  if type(value) ~= "function" then return nil, path .. " did not return a function(api)" end
  return value
end

return M
