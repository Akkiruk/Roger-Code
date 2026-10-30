-- manifest-name: Conformance Probe
-- manifest-description: Records how this server's ComputerCraft behaves (Lua language, every CC API, ROM files, mod APIs, peripherals, compile check of installed scripts) so the emulator can be compared against it.
-- Conformance probe: run it on a real computer, then give conformance_results.json to the emulator project
-- (craftos-agent: node tools/conformance/compare.mjs --server conformance_results.json).
--
-- It only reads and uses a scratch folder (/.conformance_tmp, deleted afterwards). It never touches the
-- network or moves tokens. Usage: conformance_probe [--quiet]

local RESULT_FILE = "conformance_results.json"
local TMP = "/.conformance_tmp"
local quiet = ({ ... })[1] == "--quiet"

local checks = {}   -- { id =, mode =, v = }
local sets = {}     -- id -> sorted list of strings
local failures = 0

local function say(text)
  if not quiet then print(text) end
end

-----------------------------------------------------
-- Canonical values: the same Lua value always produces the same string, on any host.
-----------------------------------------------------
local canon

local function canonString(s)
  return "'" .. s:gsub("[^\32-\126]", function(c) return "\\" .. c:byte() end) .. "'"
end

canon = function(v, depth)
  depth = depth or 0
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v ~= v then return "nan" end
    if v == math.huge then return "inf" end
    if v == -math.huge then return "-inf" end
    return string.format("%.14g", v)
  end
  if t == "string" then return canonString(v) end
  if t == "table" then
    if depth >= 4 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      if ta == "number" or ta == "string" then return a < b end
      return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = canon(k, depth + 1) .. "=" .. canon(v[k], depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return t -- function, thread, userdata
end

--- Error messages carry "file:line:" prefixes that differ by host; drop them.
local function cleanError(msg)
  msg = tostring(msg)
  msg = msg:gsub('^%[string "[^"]*"%]:%d+: ', "")
  msg = msg:gsub("^[%w_%./%-=]+:%d+: ", "")
  return msg
end

local function pack(...)
  return { n = select("#", ...), ... }
end

--- Run fn and record what it returned (or the error it raised).
-- mode "exact": the value must match; "type": only the Lua types must match; "info": reported, never compared.
local function check(id, mode, fn)
  local r = pack(pcall(fn))
  local v
  if not r[1] then
    v = "ERR " .. cleanError(r[2])
  else
    local parts = {}
    for i = 2, r.n do
      parts[#parts + 1] = (mode == "type") and type(r[i]) or canon(r[i])
    end
    v = table.concat(parts, " | ")
  end
  checks[#checks + 1] = { id = id, mode = mode, v = v }
end

--- Evaluate Lua source (an expression, or statements when it starts with "do").
local function snippet(id, src, mode)
  check(id, mode or "exact", function()
    local code = src:match("^%s*do%f[%W]") and src or ("return " .. src)
    local f, err = load(code, "=probe")
    if not f then error(err, 0) end
    return f()
  end)
end

local function setOf(id, list)
  table.sort(list)
  sets[id] = list
end

local function yield()
  os.queueEvent("probe_yield")
  os.pullEvent("probe_yield")
end

-----------------------------------------------------
-- 1. Lua language and standard library
-----------------------------------------------------
local function languageChecks()
  check("lua.version", "info", function() return _VERSION end)
  check("lua.host", "info", function() return _HOST end)

  -- syntax the target does or does not accept
  snippet("lua.goto_statement", 'load("goto x ::x::") ~= nil')
  snippet("lua.goto_loop_continue", 'load("for i=1,2 do if i==1 then goto c end ::c:: end") ~= nil')
  snippet("lua.goto_as_identifier", 'load("local goto = 5 return goto") ~= nil')
  snippet("lua.label_syntax_error", 'select(2, load("::x::"))')
  snippet("lua.goto_syntax_error", 'select(2, load("goto x"))')
  snippet("lua.hex_escape_x41", 'load([[return "\\x41"]]) ~= nil')
  snippet("lua.escape_z", 'load([[return "a\\z   b"]]) ~= nil')
  snippet("lua.long_string_level", 'load("return [==[a]]b]==]")()')
  snippet("lua.bitwise_operator_syntax", 'load("return 1 & 2") ~= nil')
  snippet("lua.integer_division_syntax", 'load("return 7 // 2") ~= nil')
  snippet("lua.attrib_const", 'load("local x <const> = 1") ~= nil')
  snippet("lua.hex_float", 'tonumber("0x1p4")')

  -- numbers
  snippet("num.int_float_division", "10/2")
  snippet("num.tostring_float", "tostring(3.0)")
  snippet("num.tostring_big", "tostring(2^53)")
  snippet("num.tostring_1e15", "tostring(1e15)")
  snippet("num.tostring_1e100", "tostring(1e100)")
  snippet("num.tostring_neg_zero", "tostring(-0.0)")
  snippet("num.tostring_third", "tostring(1/3)")
  snippet("num.mod_negative", "{ 3 % -2, -3 % 2, -3 % -2, 5.5 % 2 }")
  snippet("num.floor_ceil", "{ math.floor(-0.5), math.ceil(-0.5), math.floor(2^31), math.ceil(0.1) }")
  snippet("num.huge_tostring", "{ tostring(math.huge), tostring(-math.huge) }")
  snippet("num.nan_tostring", "tostring(0/0)")
  snippet("num.nan_compare", "{ (0/0) == (0/0), (0/0) ~= (0/0) }")
  snippet("num.tonumber_forms", [[{ tonumber("0x10"), tonumber("  5  "), tonumber("5e2"), tonumber("1e"), tonumber("0b1"), tonumber(""), tonumber("10", 2), tonumber("z", 36), tonumber("1_0") }]])
  snippet("num.tonumber_nonstring", "{ tonumber(nil), tonumber(true), tonumber({}) }")
  snippet("num.string_arith", [[{ "10" + 5, "3" * "4", 10 .. 20 }]])
  snippet("num.string_arith_error", [[do return "a" + 1 end]])
  snippet("num.pow", "{ 2^10, 2^0.5, (-8)^(1/3) }")
  snippet("num.max_min", "{ math.max(1, 2.5), math.min(-1, -1.5), math.max(3) }")
  snippet("num.fmod_modf", "{ math.fmod(7, 3), math.fmod(-7, 3), math.modf(3.7), math.modf(-3.7) }")
  snippet("num.sqrt_exp_log", "{ math.sqrt(16), math.exp(0), math.log(1), math.log(8, 2), math.log10 and math.log10(1000) }")
  snippet("num.trig", "{ math.sin(0), math.cos(0), math.atan2 and math.atan2(1, 1), math.atan(1) }")
  snippet("num.deg_rad", "{ math.deg(math.pi), math.rad(180) }")
  snippet("num.random_range", "do local ok = true for i = 1, 300 do local r = math.random(5) if r < 1 or r > 5 or r % 1 ~= 0 then ok = false end end return ok end")
  snippet("num.random_float_range", "do local ok = true for i = 1, 300 do local r = math.random() if r < 0 or r >= 1 then ok = false end end return ok end")
  snippet("num.random_bad_range", "do return math.random(0) end")
  snippet("num.random_empty_interval", "do return math.random(5, 1) end")
  snippet("num.tostring_int_valued", "{ 1e3, 2^31, -2^31, 123456789012 }")
  snippet("num.format_g", [[{ string.format("%g", 100000), string.format("%g", 1e20), string.format("%.3g", 0.0001234) }]])

  -- strings
  snippet("str.format_d_float", [[string.format("%d", 3.0)]])
  snippet("str.format_d_fraction", [[do return string.format("%d", 3.5) end]])
  snippet("str.format_misc", [[{ string.format("%5.2f|%-5d|%05d|%x|%X|%o|%c|%e", 3.14159, 42, 42, 255, 255, 8, 65, 12345.678) }]])
  snippet("str.format_s_types", [[{ string.format("%s %s %s", nil, true, 12) }]])
  snippet("str.format_s_table", [[string.format("%s", {}):match("^table") ]])
  snippet("str.format_q", [[string.format("%q", "a\nb\"c\0d")]])
  snippet("str.format_pct", [[string.format("100%%")]])
  snippet("str.format_bad", [[do return string.format("%y", 1) end]])
  snippet("str.format_missing_arg", [[do return string.format("%d") end]])
  snippet("str.find_plain", [[{ ("a.b"):find(".", 1, true), ("a.b"):find("%."), ("abc"):find("b", -1), ("abc"):find("") }]])
  snippet("str.find_captures", [[{ ("hello world"):find("(o)(%s)") }]])
  snippet("str.find_position_capture", [[{ ("abc"):find("()b()") }]])
  snippet("str.match_anchors", [[{ ("abc"):match("^b"), ("abc"):match("c$"), ("abc"):match("^abc$") }]])
  snippet("str.gsub_forms", [[{ ("hello"):gsub("l", "L"), ("hello"):gsub("l", "L", 1), ("abc"):gsub("%w", "%0%0"), ("abc"):gsub("(a)(b)", "%2%1") }]])
  snippet("str.gsub_function_table", [[{ ("a b"):gsub("%w", function(c) return c:upper() end), ("a b"):gsub("%w", { a = "1" }) }]])
  snippet("str.gsub_bad_replacement", [[do return ("abc"):gsub("a", "%2") end]])
  snippet("str.gsub_empty_match", [[{ ("abc"):gsub("", "-") }]])
  snippet("str.gmatch", [[do local t = {} for w in ("a1b22c333"):gmatch("%d+") do t[#t + 1] = w end return t end]])
  snippet("str.pattern_balance", [[{ ("f(a(b)c)d"):match("%b()") }]])
  snippet("str.pattern_frontier", [[{ ("THE (QUICK) fox"):find("%f[%a]%a+%f[%A]") }]])
  snippet("str.pattern_classes", [[{ ("a1_ -"):gsub("%a", "A"), ("a1_ -"):gsub("%p", "P"), ("a\t"):gsub("%c", "C"), ("aB"):gsub("%l", "x"), ("aB"):gsub("%u", "x"), ("ab"):gsub("%x", "H") }]])
  snippet("str.pattern_malformed", [[do return ("abc"):find("[a") end]])
  snippet("str.pattern_malformed_pct", [[do return ("abc"):find("%") end]])
  snippet("str.pattern_too_complex", [[do return ("a"):rep(100):find(("(a)"):rep(40)) end]])
  snippet("str.rep", [[{ ("ab"):rep(3), ("ab"):rep(3, ","), ("ab"):rep(0), ("ab"):rep(-1) }]])
  snippet("str.sub_edges", [[{ ("hello"):sub(2), ("hello"):sub(-3), ("hello"):sub(2, -2), ("hello"):sub(0), ("hello"):sub(10), ("hello"):sub(-100, 2), ("hello"):sub(3, 2) }]])
  snippet("str.byte_char", [[{ ("A"):byte(), ("ABC"):byte(1, -1), string.char(72, 105), ("é"):byte(1, -1) }]])
  snippet("str.char_range_error", [[do return string.char(256) end]])
  snippet("str.upper_lower_len", [[{ ("aB"):upper(), ("aB"):lower(), #"abc", ("\0a"):len(), ("abc"):reverse() }]])
  snippet("str.embedded_zero", [[{ #"a\0b", ("a\0b"):byte(2), "a\0b" == "a\0b", ("a\0b"):find("\0", 1, true) }]])
  snippet("str.compare", [[{ "a" < "b", "a" < "B", "abc" < "abd", "" < "a", "Z" < "a" }]])
  snippet("str.concat_numbers", [[{ 1 .. "", 1.5 .. "", 2^63 .. "" }]])
  snippet("str.tostring_forms", [[{ tostring(nil), tostring(true), tostring(12), tostring("x") }]])
  snippet("str.string_methods_on_literals", [[("%d"):format(5)]])
  snippet("str.len_of_unicode", [[#"héllo"]])
  snippet("str.pack_available", [[type(string.pack)]])
  snippet("str.utf8_available", [[type(utf8)]])
  snippet("str.bit32_available", [[type(bit32)]])
  snippet("str.bit_available", [[type(bit)]])

  -- tables
  snippet("tbl.length_border", [[{ #{ 1, 2, 3 }, #{ 1, 2, nil, 4 }, #{ n = 1 }, #{} }]])
  snippet("tbl.insert_remove", [[do local t = { 1, 2, 3 } table.insert(t, 4) table.insert(t, 1, 0) local r = table.remove(t) local r2 = table.remove(t, 1) return { t, r, r2 } end]])
  snippet("tbl.insert_bad_position", [[do local t = { 1, 2, 3 } table.insert(t, 9, 5) return t end]])
  snippet("tbl.insert_wrong_arg_count", [[do local t = {} table.insert(t, 1, 2, 3) end]])
  snippet("tbl.remove_empty", [[{ table.remove({}), table.remove({}, 1) }]])
  snippet("tbl.concat", [[{ table.concat({ 1, 2, 3 }, ","), table.concat({ "a", "b", "c" }, "", 2, 3), table.concat({}) }]])
  snippet("tbl.concat_bad_value", [[do return table.concat({ 1, {}, 3 }) end]])
  snippet("tbl.sort_numbers", [[do local t = { 5, 2, 8, 1, 9, 3 } table.sort(t) return t end]])
  snippet("tbl.sort_desc", [[do local t = { 5, 2, 8, 1 } table.sort(t, function(a, b) return a > b end) return t end]])
  snippet("tbl.sort_mixed_error", [[do local t = { 1, "a", 2 } table.sort(t) return t end]])
  snippet("tbl.unpack_forms", [[{ table.unpack and table.unpack({ 1, 2, 3 }, 2) or unpack({ 1, 2, 3 }, 2) }]])
  snippet("tbl.unpack_available", [[{ type(table.unpack), type(unpack) }]])
  snippet("tbl.pack_available", [[{ type(table.pack), type(table.maxn), type(table.getn), type(table.move), type(table.foreach) }]])
  snippet("tbl.select", [[{ select("#"), select("#", nil, nil), select(2, "a", "b", "c"), select(-1, "a", "b", "c") }]])
  snippet("tbl.select_zero", [[do return select(0, "a") end]])
  snippet("tbl.next_empty", [[next({})]])
  snippet("tbl.ipairs_stops_at_nil", [[do local n = 0 for _ in ipairs({ 1, 2, nil, 4 }) do n = n + 1 end return n end]])
  snippet("tbl.pairs_array_order", [[do local t = {} for k in pairs({ "a", "b", "c", "d" }) do t[#t + 1] = k end return t end]])
  snippet("tbl.float_key_normalised", [[do local t = {} t[1.0] = "x" return { t[1], next(t) } end]])
  snippet("tbl.nan_key_error", [[do local t = {} t[0/0] = 1 end]])
  snippet("tbl.nil_key_error", [[do local t = {} t[nil] = 1 end]])
  snippet("tbl.index_nil_error", [[do local t = nil return t.x end]])
  snippet("tbl.call_nil_error", [[do local t = {} t.x() end]])
  snippet("tbl.arith_nil_error", [[do local t = {} return t.x + 1 end]])
  snippet("tbl.concat_nil_error", [[do local t = {} return "a" .. t.x end]])
  snippet("tbl.compare_error", [[do return {} < {} end]])
  snippet("tbl.rawequal_rawlen", [[{ rawequal("a", "a"), rawequal({}, {}), type(rawlen), rawget({ 1 }, 1), rawset({}, "a", 1).a }]])

  -- metatables
  snippet("meta.index_newindex", [[do local log = {} local t = setmetatable({}, { __index = function(_, k) return "idx_" .. k end, __newindex = function(_, k, v) log[#log + 1] = k end }) t.a = 1 return { t.b, log } end]])
  snippet("meta.call_tostring_len", [[do local t = setmetatable({}, { __call = function(_, a) return a * 2 end, __tostring = function() return "T" end, __len = function() return 42 end }) return { t(4), tostring(t), #t } end]])
  snippet("meta.concat_eq_lt_le", [[do local mt = { __concat = function() return "cat" end, __eq = function() return true end, __lt = function() return true end, __le = function() return false end } local a, b = setmetatable({}, mt), setmetatable({}, mt) return { a .. "x", a == b, a < b, a <= b } end]])
  snippet("meta.arith", [[do local mt = { __add = function() return "add" end, __unm = function() return "unm" end, __mod = function() return "mod" end } local a = setmetatable({}, mt) return { a + 1, -a, a % 2 } end]])
  snippet("meta.pairs_metamethod", [[do local t = setmetatable({}, { __pairs = function() return function() return nil end end }) local n = 0 for _ in pairs(t) do n = n + 1 end return n end]])
  snippet("meta.metatable_protected", [[do local t = setmetatable({}, { __metatable = "locked" }) return { getmetatable(t), pcall(setmetatable, t, {}) } end]])
  snippet("meta.string_metatable", [[getmetatable("").__index == string]])
  snippet("meta.tostring_non_string_result", [[do local t = setmetatable({}, { __tostring = function() return 1 end }) return tostring(t) end]])
  snippet("meta.gc_metamethod_ignored", [[do local t = setmetatable({}, { __gc = function() end }) return type(t) end]])
  snippet("meta.eq_different_types", [[{ 1 == "1", "a" == "a", nil == false }]])

  -- functions, scoping, errors
  snippet("fn.vararg", [[do local function f(...) return select("#", ...), ... end return { f(nil, nil) } end]])
  snippet("fn.vararg_arg_table", [[do local function f(...) return arg end return f(1) end]])
  snippet("fn.closure_loop_vars", [[do local fs = {} for i = 1, 3 do fs[i] = function() return i end end return { fs[1](), fs[2](), fs[3]() } end]])
  snippet("fn.tail_call_depth", [[do local function f(n) if n == 0 then return "done" end return f(n - 1) end return f(100000) end]])
  snippet("fn.recursion_overflow", [[do local function f() return 1 + f() end return f() end]])
  snippet("fn.setfenv_available", [[{ type(setfenv), type(getfenv), type(loadstring), type(load), type(loadfile), type(dofile), type(require), type(module) }]])
  snippet("fn.load_with_env", [[do local f = load("return x", "=c", "t", { x = 7 }) return f and f() end]])
  snippet("fn.load_chunk_function", [[do local parts = { "return ", "5" } local i = 0 local f = load(function() i = i + 1 return parts[i] end) return f and f() end]])
  snippet("fn.load_syntax_error_message", [[select(2, load("x ="))]])
  snippet("fn.load_unfinished_string", [[select(2, load('return "abc'))]])
  snippet("fn.load_unexpected_symbol", [[select(2, load("return )"))]])
  snippet("fn.load_chunkname", [[select(2, load("error('x')", "=name"))]])
  snippet("fn.error_with_table", [[do local ok, e = pcall(error, { code = 7 }) return { ok, e.code } end]])
  snippet("fn.error_levels", [[do local function f() error("m", 2) end local ok, e = pcall(function() f() end) return { ok, (e:gsub("^.-:%d+: ", "")) } end]])
  snippet("fn.error_nil", [[{ pcall(error) }]])
  snippet("fn.error_number", [[{ pcall(error, 42) }]])
  snippet("fn.assert_forms", [[{ pcall(assert, false), pcall(assert, nil, "custom"), pcall(assert, 1, "unused") }]])
  snippet("fn.xpcall_handler", [[{ xpcall(function() error("boom", 0) end, function(m) return "H:" .. m end) }]])
  snippet("fn.xpcall_args", [[{ xpcall(function(a, b) return a + b end, print, 2, 3) }]])
  snippet("fn.pcall_non_function", [[{ pcall(5) }]])
  snippet("fn.pcall_nil", [[{ pcall(nil) }]])
  snippet("fn.error_in_error_handler", [[{ xpcall(function() error("a") end, function() error("b") end) }]])
  snippet("fn.stack_traceback_available", [[type(debug) == "table" and type(debug.traceback)]])
  snippet("fn.tostring_function_form", [[tostring(print):match("^%a+")]])
  snippet("fn.type_names", [[{ type(nil), type(1), type("a"), type({}), type(print), type(coroutine.create(print)) }]])
  snippet("fn.integer_loop_float_step", [[do local t = {} for i = 1, 2, 0.5 do t[#t + 1] = i end return t end]])
  snippet("fn.for_loop_zero_step", [[do for i = 1, 2, 0 do return "ran" end return "no-run" end]])
  snippet("fn.for_loop_modify_var", [[do local n = 0 for i = 1, 3 do i = i * 2 n = n + i end return n end]])
  snippet("fn.repeat_scope", [[do local n = 0 repeat local x = n n = n + 1 until x >= 2 return n end]])
  snippet("fn.multiple_assign_order", [[do local a, b = 1, 2 a, b = b, a return { a, b } end]])
  snippet("fn.string_comparison_numbers_error", [[do return 1 < "2" end]])

  -- coroutines
  snippet("co.basic", [[do local co = coroutine.create(function(a) local b = coroutine.yield(a + 1) return b * 2 end) local _, x = coroutine.resume(co, 1) local _, y = coroutine.resume(co, 10) return { x, y, coroutine.status(co) } end]])
  snippet("co.dead_resume", [[do local co = coroutine.create(function() end) coroutine.resume(co) return { coroutine.resume(co) } end]])
  snippet("co.wrap_error", [[do local f = coroutine.wrap(function() error("x", 0) end) return { pcall(f) } end]])
  snippet("co.wrap_dead", [[do local f = coroutine.wrap(function() end) f() return { pcall(f) } end]])
  snippet("co.yield_across_pcall", [[do local co = coroutine.create(function() local ok, v = pcall(coroutine.yield, 1) return ok, v end) local _, a = coroutine.resume(co) local _, ok, v = coroutine.resume(co, "back") return { a, ok, v } end]])
  snippet("co.yield_in_metamethod", [[do local t = setmetatable({}, { __index = function() return coroutine.yield(1) end }) local co = coroutine.create(function() return t.x end) local ok, a = coroutine.resume(co) return { ok, a } end]])
  snippet("co.yield_in_sort_comparator", [[do local co = coroutine.create(function() table.sort({ 3, 2, 1 }, function(a, b) coroutine.yield() return a < b end) end) return { coroutine.resume(co) } end]])
  snippet("co.running_status", [[do local co co = coroutine.create(function() return coroutine.status(co), coroutine.running() == co end) return { coroutine.resume(co) } end]])
  snippet("co.isyieldable", [[type(coroutine.isyieldable)]])
  snippet("co.resume_self", [[do local co co = coroutine.create(function() return coroutine.resume(co) end) return { coroutine.resume(co) } end]])
  snippet("co.close_available", [[type(coroutine.close)]])
  snippet("co.nested_depth", [[do local function nest(n) if n == 0 then return "bottom" end local co = coroutine.create(nest) local _, r = coroutine.resume(co, n - 1) return r end return nest(100) end]])

  -- os / date without touching the real clock
  snippet("os.date_utc_epoch0", [[os.date("!%Y-%m-%d %H:%M:%S", 0)]])
  snippet("os.date_utc_fixed", [[os.date("!%A %B %d %j %y %p %I %%", 86400 * 400)]])
  snippet("os.date_table", [[do local t = os.date("!*t", 86400 * 400 + 3661) return { t.year, t.month, t.day, t.hour, t.min, t.sec, t.wday, t.yday, t.isdst } end]])
  snippet("os.date_bad_format", [[do return os.date("!%Ez", 0) end]])
  snippet("os.time_table_utc_free", [[os.time({ year = 2000, month = 1, day = 1, hour = 12 }) ~= nil]])
  snippet("os.time_table_missing_field", [[do return os.time({ year = 2000 }) end]])
  snippet("os.difftime", [[os.difftime(10, 4)]])
  snippet("os.getenv_available", [[{ type(os.getenv), type(os.exit), type(os.remove), type(os.rename), type(os.tmpname), type(os.execute) }]])
  snippet("io.available", [[{ type(io), io and type(io.open), io and type(io.write), io and type(io.read), io and type(io.lines) }]])
  snippet("io.open_missing", [[do local f, e = io.open("/definitely_not_here.txt", "r") return { f, e } end]])
end

-----------------------------------------------------
-- 2. API surface: every name each global exposes
-----------------------------------------------------
local API_TABLES = {
  "os", "fs", "term", "peripheral", "textutils", "colors", "colours", "keys", "redstone", "rs", "settings",
  "shell", "multishell", "http", "rednet", "parallel", "paintutils", "window", "vector", "gps", "help", "disk",
  "io", "string", "table", "math", "coroutine", "bit32", "bit", "utf8", "debug", "turtle", "pocket", "commands",
  "ccvault", "vhcc", "fs_extra", "peripherals",
}

local function listTable(tbl)
  local names = {}
  for k, v in pairs(tbl) do
    if type(k) == "string" then names[#names + 1] = k .. ":" .. type(v) end
  end
  return names
end

local function surfaceChecks()
  for _, name in ipairs(API_TABLES) do
    local value = _G[name]
    if type(value) == "table" then
      setOf("api." .. name, listTable(value))
    else
      check("api." .. name .. ".type", "exact", function() return type(value) end)
    end
  end
  setOf("api._G", listTable(_G))
  check("api.package", "exact", function()
    return type(package), package and type(package.path), package and type(package.loaded), package and type(package.preload), package and type(package.loaders)
  end)
  check("api.package.path", "info", function() return package and package.path end)
  check("api.package.loaded", "exact", function()
    local names = {}
    for k in pairs(package.loaded) do names[#names + 1] = tostring(k) end
    table.sort(names)
    return table.concat(names, ",")
  end)
  check("api.require_missing", "exact", function() return require("definitely.not.a.module") end)
  check("api.keys_constants", "exact", function()
    return { keys.enter, keys.backspace, keys.tab, keys.space, keys.a, keys.z, keys.zero, keys.one, keys.leftCtrl, keys.leftShift,
      keys.up, keys.down, keys.left, keys.right, keys.f1, keys.f12, keys.delete, keys.home, keys["end"], keys.pageUp, keys.numPad0, keys.grave }
  end)
  check("api.keys_getName", "exact", function()
    return { keys.getName(65), keys.getName(257), keys.getName(262), keys.getName(341), keys.getName(1), keys.getName(-1) }
  end)
  check("api.colors_values", "exact", function()
    return { colors.white, colors.orange, colors.magenta, colors.lightBlue, colors.yellow, colors.lime, colors.pink, colors.gray,
      colors.lightGray, colors.cyan, colors.purple, colors.blue, colors.brown, colors.green, colors.red, colors.black,
      colours.grey, colours.lightGrey }
  end)
  check("api.colors_functions", "exact", function()
    return { colors.combine(colors.red, colors.blue), colors.subtract(colors.combine(colors.red, colors.blue), colors.red),
      colors.test(colors.combine(colors.red, colors.blue), colors.red), colors.toBlit(colors.lime), colors.fromBlit("e"),
      colors.packRGB(1, 0.5, 0), colors.unpackRGB(0xff8000) }
  end)
  check("api.colors_bad_blit", "exact", function() return colors.fromBlit("z") end)
end

-----------------------------------------------------
-- 3. CC libraries with deterministic results
-----------------------------------------------------
local function libraryChecks()
  -- textutils
  snippet("tu.serialize_forms", [[{ textutils.serialize(1), textutils.serialize("a"), textutils.serialize({ 1, 2, 3 }), textutils.serialize({ a = 1 }), textutils.serialize({ { 1 }, { 2 } }), textutils.serialize(true) }]])
  snippet("tu.serialize_special_numbers", [[{ textutils.serialize(1.5), textutils.serialize(-0.0), textutils.serialize(2^53), textutils.serialize(1e100) }]])
  snippet("tu.serialize_inf_nan", [[{ pcall(textutils.serialize, math.huge) }]])
  snippet("tu.serialize_function_error", [[{ pcall(textutils.serialize, print) }]])
  snippet("tu.serialize_cycle_error", [[do local t = {} t.t = t return { pcall(textutils.serialize, t) } end]])
  snippet("tu.serialize_compact", [[textutils.serialize({ a = 1 }, { compact = true })]])
  snippet("tu.serialize_keys_needing_quotes", [[textutils.serialize({ ["a b"] = 1 })]])
  snippet("tu.serialize_nested_string_escapes", [[textutils.serialize("a\nb\"c\\d")]])
  snippet("tu.unserialize_forms", [[{ textutils.unserialize("{1,2,3}"), textutils.unserialize("'x'"), textutils.unserialize("5"), textutils.unserialize("{a=1}"), textutils.unserialize("garbage") }]])
  snippet("tu.unserialize_rejects_code", [[textutils.unserialize("os.exit()")]])
  snippet("tu.unserialize_inf", [[textutils.unserialize("math.huge")]])
  snippet("tu.json_serialize", [[{ textutils.serializeJSON({ 1, 2, 3 }), textutils.serializeJSON({ a = 1 }), textutils.serializeJSON("é\n"), textutils.serializeJSON(true), textutils.serializeJSON(12.5) }]])
  snippet("tu.json_serialize_empty", [[{ textutils.serializeJSON({}), textutils.serializeJSON({}, true) }]])
  snippet("tu.json_serialize_nbt", [[textutils.serializeJSON({ n = 5 }, true)]])
  snippet("tu.json_serialize_inf_error", [[{ pcall(textutils.serializeJSON, math.huge) }]])
  snippet("tu.json_serialize_function_error", [[{ pcall(textutils.serializeJSON, print) }]])
  snippet("tu.json_unserialize", [[{ textutils.unserializeJSON('{"a":[1,2,{"b":true}]}') }]])
  snippet("tu.json_unserialize_null", [[{ textutils.unserializeJSON("null") }]])
  snippet("tu.json_unserialize_null_option", [[{ textutils.unserializeJSON('{"a":null}', { parse_null = true }) }]])
  snippet("tu.json_unserialize_bad", [[{ textutils.unserializeJSON("{bad") }]])
  snippet("tu.json_unserialize_numbers", [[{ textutils.unserializeJSON("[1, 2.5, -3, 1e2, 0.1]") }]])
  snippet("tu.json_unserialize_unicode", [[{ textutils.unserializeJSON('"\\u00e9\\n"') }]])
  snippet("tu.json_roundtrip_big_int", [[textutils.serializeJSON({ 2^53 })]])
  snippet("tu.formatTime", [[{ textutils.formatTime(0), textutils.formatTime(13.5), textutils.formatTime(13.5, true), textutils.formatTime(23.99), textutils.formatTime(12) }]])
  snippet("tu.urlEncode", [[{ textutils.urlEncode("a b&c=d/é"), textutils.urlEncode("") }]])
  snippet("tu.empty_json_marker", [[type(textutils.empty_json_array) .. type(textutils.json_null)]])
  snippet("tu.complete_available", [[{ type(textutils.complete), type(textutils.tabulate), type(textutils.pagedPrint), type(textutils.slowPrint), type(textutils.coloredWrite) }]])
  snippet("tu.sha256_available", [[type(textutils.sha256)]])

  -- fs path functions (pure)
  snippet("fs.combine", [[{ fs.combine("a", "b"), fs.combine("/a/", "/b/"), fs.combine("a", "../b"), fs.combine("", ""), fs.combine("a/b", "..", "c"), fs.combine("/", "a") }]])
  snippet("fs.combine_parent_escape", [[{ fs.combine("..", "x"), fs.combine("a/../..") }]])
  snippet("fs.getName_getDir", [[{ fs.getName("a/b/c.lua"), fs.getName("/"), fs.getName(""), fs.getDir("a/b/c.lua"), fs.getDir("a"), fs.getDir("/"), fs.getDir("..") }]])
  snippet("fs.combine_backslash_wildcard", [[{ pcall(fs.combine, "a\\b"), pcall(fs.combine, "a*b") }]])
  snippet("fs.complete", [[{ fs.complete("ro", "/") }]])
  snippet("fs.complete_files", [[{ fs.complete("rom/pro", "/", true, false) }]])
  snippet("fs.isDriveRoot", [[{ fs.isDriveRoot("/"), fs.isDriveRoot("/rom"), fs.isDriveRoot("/rom/apis") }]])

  -- vector, window, paintutils (drawn into an offscreen window)
  snippet("vec.ops", [[do local a, b = vector.new(1, 2, 3), vector.new(4, 5, 6) return { tostring(a + b), tostring(a - b), tostring(a * 2), a:dot(b), tostring(a:cross(b)), a == vector.new(1, 2, 3), tostring(-a), a:length() } end]])
  snippet("vec.normalize_round", [[do local v = vector.new(3, 0, 4) return { tostring(v:normalize()), tostring(vector.new(1.26, 2.5, 3.14):round(0.5)), tostring(vector.new(1, 2, 3):tostring()) } end]])
  check("window.draw", "exact", function()
    local win = window.create(term.current(), 1, 1, 12, 4, false)
    win.setBackgroundColor(colors.blue)
    win.setTextColor(colors.yellow)
    win.clear()
    win.setCursorPos(2, 2)
    win.write("hello")
    win.setCursorPos(11, 3)
    win.write("overflow!")
    win.blit("ab", "01", "fe")
    local lines = {}
    for y = 1, 4 do
      local text, fg, bg = win.getLine(y)
      lines[y] = { text, fg, bg }
    end
    return { lines, win.getSize(), win.getCursorPos() }
  end)
  check("window.scroll_clearline", "exact", function()
    local win = window.create(term.current(), 1, 1, 6, 3, false)
    for y = 1, 3 do win.setCursorPos(1, y) win.write(tostring(y):rep(6)) end
    win.scroll(1)
    local a = (win.getLine(1))
    win.setCursorPos(1, 1)
    win.clearLine()
    local b = (win.getLine(1))
    win.scroll(-1)
    return { a, b, (win.getLine(1)), (win.getLine(2)) }
  end)
  check("window.palette", "exact", function()
    local win = window.create(term.current(), 1, 1, 4, 2, false)
    win.setPaletteColor(colors.red, 0.5, 0.25, 1)
    return { win.getPaletteColor(colors.red), win.getPaletteColor(colors.white) }
  end)
  check("window.reposition_visible", "exact", function()
    local win = window.create(term.current(), 2, 2, 5, 3, false)
    win.reposition(3, 3, 8, 4)
    return { win.getSize(), win.isVisible(), win.getPosition() }
  end)
  check("window.write_numbers_and_errors", "exact", function()
    local win = window.create(term.current(), 1, 1, 8, 1, false)
    win.write(12)
    local ok, err = pcall(win.write, {})
    local ok2, err2 = pcall(win.blit, "ab", "1", "1")
    return { (win.getLine(1)), ok, err, ok2, err2 }
  end)
  check("paintutils.draw", "exact", function()
    local win = window.create(term.current(), 1, 1, 10, 6, false)
    local old = term.redirect(win)
    paintutils.drawLine(1, 1, 5, 3, colors.red)
    paintutils.drawBox(2, 2, 8, 5, colors.green)
    paintutils.drawFilledBox(3, 3, 5, 4, colors.blue)
    paintutils.drawPixel(10, 6, colors.white)
    term.redirect(old)
    local rows = {}
    for y = 1, 6 do local _, _, bg = win.getLine(y) rows[y] = bg end
    return rows
  end)
  check("paintutils.parseImage", "exact", function()
    local img = paintutils.parseImage("0f\nf0")
    return img
  end)
  check("term.redirect_and_blit", "exact", function()
    local win = window.create(term.current(), 1, 1, 5, 1, false)
    local old = term.redirect(win)
    term.write("hi")
    term.setCursorPos(1, 1)
    term.blit("abc", "123", "456")
    local pos = { term.getCursorPos() }
    term.redirect(old)
    local text, fg, bg = win.getLine(1)
    return { text, fg, bg, pos, term.current() == old }
  end)
  check("term.color_state", "exact", function()
    local win = window.create(term.current(), 1, 1, 3, 1, false)
    local old = term.redirect(win)
    term.setTextColor(colors.lime)
    term.setBackgroundColor(colors.pink)
    local r = { term.getTextColor(), term.getBackgroundColor(), term.isColor(), term.getTextColour() }
    term.redirect(old)
    return r
  end)
  check("term.bad_color_error", "exact", function()
    local win = window.create(term.current(), 1, 1, 3, 1, false)
    local old = term.redirect(win)
    local ok, err = pcall(term.setTextColor, 3)
    term.redirect(old)
    return { ok, err }
  end)

  -- parallel, settings (in-memory), rednet constants, redstone
  check("parallel.waitForAny_all", "exact", function()
    local order = {}
    local r1 = parallel.waitForAny(function() order[#order + 1] = "a" yield() order[#order + 1] = "a2" end, function() order[#order + 1] = "b" end)
    local r2 = parallel.waitForAll(function() yield() order[#order + 1] = "c" end, function() order[#order + 1] = "d" end)
    return { r1, r2, order }
  end)
  check("parallel.error_propagation", "exact", function()
    return { pcall(parallel.waitForAny, function() error("boom", 0) end, function() yield() end) }
  end)
  check("settings.memory_roundtrip", "exact", function()
    settings.define("probe.sample", { default = "d", type = "string", description = "x" })
    local a = settings.get("probe.sample")
    settings.set("probe.sample", "v")
    local b = settings.get("probe.sample")
    local details = settings.getDetails("probe.sample")
    settings.unset("probe.sample")
    local c = settings.get("probe.sample")
    settings.undefine("probe.sample")
    return { a, b, c, details.default, details.value, details.type, (pcall(settings.set, "probe.sample", 5)) }
  end)
  check("settings.wrong_type", "exact", function()
    settings.define("probe.num", { default = 1, type = "number" })
    local r = { pcall(settings.set, "probe.num", "x") }
    settings.undefine("probe.num")
    return r
  end)
  snippet("rednet.constants", [[{ rednet.CHANNEL_BROADCAST, rednet.CHANNEL_REPEAT, rednet.isOpen() }]])
  snippet("rednet.bad_receive", [[{ pcall(rednet.send, 1, "x", "p") }]])
  snippet("redstone.sides", [[do local s = redstone.getSides() table.sort(s) return s end]])
  snippet("redstone.bad_side", [[{ pcall(redstone.getInput, "nowhere") }]])
  snippet("redstone.aliases", [[{ rs == redstone, type(rs.getAnalogOutput), redstone.getInput("top"), redstone.getAnalogInput("top"), redstone.getOutput("top") }]])
  snippet("gps.available", [[{ gps.CHANNEL_GPS, type(gps.locate) }]])
  snippet("peripheral.missing", [[{ peripheral.isPresent("nowhere"), peripheral.getType("nowhere"), peripheral.wrap("nowhere"), peripheral.find("nonexistent_type"), peripheral.getMethods("nowhere") }]])
  snippet("peripheral.call_missing", [[{ pcall(peripheral.call, "nowhere", "x") }]])
  snippet("peripheral.hasType", [[{ peripheral.hasType and peripheral.hasType("nowhere", "x") }]])
  snippet("http.surface", [[{ type(http), http and type(http.get), http and type(http.post), http and type(http.checkURL), http and type(http.websocket) }]])
  snippet("http.bad_url", [[do return http and http.checkURL("not a url") end]])
  snippet("http.blocked_local", [[do return http and http.checkURL("http://127.0.0.1/") end]])
  snippet("http.blocked_private", [[do return http and http.checkURL("http://192.168.0.1/") end]])
  snippet("http.blocked_metadata", [[do return http and http.checkURL("http://169.254.169.254/") end]])
  snippet("http.bad_scheme", [[do return http and http.checkURL("ftp://example.com/") end]])
end

-----------------------------------------------------
-- 4. The filesystem, in a scratch folder
-----------------------------------------------------
local function fsChecks()
  pcall(fs.delete, TMP)
  fs.makeDir(TMP)
  local function p(name) return TMP .. "/" .. name end

  check("fs.write_read", "exact", function()
    local h = fs.open(p("a.txt"), "w")
    h.write("hello")
    h.write(42)
    h.writeLine(" world")
    h.writeLine("second")
    h.flush()
    h.close()
    local r = fs.open(p("a.txt"), "r")
    local out = { r.readLine(), r.readLine(true), r.readLine(), r.readLine() }
    r.close()
    local r2 = fs.open(p("a.txt"), "r")
    local all, again = r2.readAll(), r2.readAll()
    r2.close()
    local r3 = fs.open(p("a.txt"), "r")
    local c1, c3 = r3.read(), r3.read(3)
    r3.close()
    return { out, all, again, c1, c3, fs.getSize(p("a.txt")) }
  end)
  check("fs.binary_roundtrip", "exact", function()
    local bytes = {}
    for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
    local data = table.concat(bytes)
    local h = fs.open(p("b.bin"), "wb")
    h.write(data)
    h.close()
    local r = fs.open(p("b.bin"), "rb")
    local back = r.readAll()
    r.close()
    local r2 = fs.open(p("b.bin"), "rb")
    local first, second = r2.read(), r2.read(2)
    r2.close()
    return { back == data, #back, first, second }
  end)
  check("fs.binary_write_byte", "exact", function()
    local h = fs.open(p("bytes.bin"), "wb")
    h.write(65)
    h.write(255)
    h.write("BC")
    h.close()
    local r = fs.open(p("bytes.bin"), "rb")
    local s = r.readAll()
    r.close()
    return { s:byte(1, -1) }
  end)
  check("fs.text_mode_utf8", "exact", function()
    local h = fs.open(p("u.txt"), "w")
    h.write("é\200")
    h.close()
    local r = fs.open(p("u.txt"), "rb")
    local raw = r.readAll()
    r.close()
    return { raw:byte(1, -1) }
  end)
  check("fs.append", "exact", function()
    local h = fs.open(p("ap.txt"), "w")
    h.write("1")
    h.close()
    local a = fs.open(p("ap.txt"), "a")
    a.write("2")
    a.close()
    local r = fs.open(p("ap.txt"), "r")
    local s = r.readAll()
    r.close()
    return s
  end)
  check("fs.seek", "exact", function()
    local h = fs.open(p("s.bin"), "wb")
    h.write("0123456789")
    h.close()
    local r = fs.open(p("s.bin"), "rb")
    local out = { r.seek("set", 3), r.read(2), r.seek("cur", 1), r.read(1), r.seek("end", -2), r.read(5), r.seek("cur") }
    r.close()
    return out
  end)
  check("fs.seek_text_mode_missing", "exact", function()
    local r = fs.open(p("s.bin"), "r")
    local t = type(r.seek)
    r.close()
    return t
  end)
  check("fs.write_to_read_handle", "exact", function()
    local r = fs.open(p("a.txt"), "r")
    local t = type(r.write)
    r.close()
    return t
  end)
  check("fs.readwrite_mode", "exact", function()
    local h = fs.open(p("rw.txt"), "w+")
    local a = h and type(h.read)
    if h then h.close() end
    return a
  end)
  check("fs.read_after_close", "exact", function()
    local r = fs.open(p("a.txt"), "r")
    r.close()
    return { pcall(r.readLine) }
  end)
  check("fs.close_twice", "exact", function()
    local r = fs.open(p("a.txt"), "r")
    r.close()
    return { pcall(r.close) }
  end)
  check("fs.bad_mode", "exact", function() return fs.open(p("a.txt"), "z") end)
  check("fs.open_missing", "exact", function() return fs.open(p("missing.txt"), "r") end)
  check("fs.open_dir_read", "exact", function() return fs.open(TMP, "r") end)
  check("fs.open_dir_write", "exact", function() return fs.open(TMP, "w") end)
  check("fs.open_missing_parent_write", "exact", function() return fs.open(p("no/parent/x.txt"), "w") end)
  check("fs.open_rom_write", "exact", function() return fs.open("/rom/probe.txt", "w") end)
  check("fs.open_non_string", "exact", function() return fs.open(nil, "r") end)
  check("fs.delete_missing", "exact", function() return fs.delete(p("missing")) end)
  check("fs.delete_rom", "exact", function() return fs.delete("/rom/startup.lua") end)
  check("fs.list_missing", "exact", function() return fs.list(p("missing")) end)
  check("fs.list_file", "exact", function() return fs.list(p("a.txt")) end)
  check("fs.getSize_missing", "exact", function() return fs.getSize(p("missing")) end)
  check("fs.getSize_dir", "exact", function() return fs.getSize(TMP) end)
  check("fs.makeDir_over_file", "exact", function() return fs.makeDir(p("a.txt")) end)
  check("fs.makeDir_nested", "exact", function()
    fs.makeDir(p("deep/er/est"))
    return { fs.isDir(p("deep/er/est")), fs.exists(p("deep")) }
  end)
  check("fs.copy_forms", "exact", function()
    fs.copy(p("a.txt"), p("copy.txt"))
    local into_existing = { pcall(fs.copy, p("a.txt"), p("copy.txt")) }
    local missing = { pcall(fs.copy, p("missing"), p("x")) }
    local to_rom = { pcall(fs.copy, p("a.txt"), "/rom/x") }
    local into_self = { pcall(fs.copy, TMP, p("deep/inside")) }
    return { fs.exists(p("copy.txt")), fs.getSize(p("copy.txt")), into_existing, missing, to_rom, into_self }
  end)
  check("fs.move_forms", "exact", function()
    fs.move(p("copy.txt"), p("moved.txt"))
    local onto_existing = { pcall(fs.move, p("a.txt"), p("moved.txt")) }
    local missing = { pcall(fs.move, p("missing"), p("x")) }
    local from_rom = { pcall(fs.move, "/rom/startup.lua", p("x")) }
    local into_self = { pcall(fs.move, TMP, p("deep/inside")) }
    return { fs.exists(p("copy.txt")), fs.exists(p("moved.txt")), onto_existing, missing, from_rom, into_self }
  end)
  check("fs.list_sorted", "exact", function()
    local l = fs.list(TMP)
    table.sort(l)
    return l
  end)
  check("fs.list_order_unsorted_set", "exact", function()
    local l = fs.list(TMP)
    return #l
  end)
  check("fs.find_wildcards", "exact", function()
    local a = fs.find(TMP .. "/*.txt")
    local b = fs.find(TMP .. "/deep/*/*")
    local c = fs.find(TMP .. "/nomatch*")
    table.sort(a) table.sort(b)
    return { a, b, c }
  end)
  check("fs.attributes", "exact", function()
    local a = fs.attributes(p("a.txt"))
    local d = fs.attributes(TMP)
    local keys = {}
    for k in pairs(a) do keys[#keys + 1] = k end
    table.sort(keys)
    return { keys, a.size, a.isDir, a.isReadOnly, d.isDir, type(a.created), type(a.modified), pcall(fs.attributes, p("missing")) }
  end)
  check("fs.exists_isDir_readonly", "exact", function()
    return { fs.exists("/rom"), fs.isDir("/rom"), fs.isReadOnly("/rom"), fs.isReadOnly(TMP), fs.exists(p("a.txt")), fs.isDir(p("a.txt")), fs.exists(""), fs.isDir("/") }
  end)
  check("fs.getDrive", "exact", function() return { fs.getDrive("/rom"), fs.getDrive("/rom/apis"), fs.getDrive(p("a.txt")), fs.getDrive(p("missing")) } end)
  check("fs.getCapacity_FreeSpace_types", "exact", function()
    return { type(fs.getFreeSpace("/")), type(fs.getCapacity("/")), fs.getFreeSpace("/rom"), fs.getCapacity("/rom") }
  end)
  check("fs.getFreeSpace_missing", "exact", function() return fs.getFreeSpace("/definitely/not/mounted") end)
  check("fs.open_many_handles", "exact", function()
    local handles = {}
    local opened = 0
    for i = 1, 200 do
      local h = fs.open(p("h" .. (i % 10) .. ".txt"), "w")
      if not h then break end
      handles[#handles + 1] = h
      opened = opened + 1
    end
    for _, h in ipairs(handles) do h.close() end
    return opened
  end)
  check("fs.delete_with_open_handle", "exact", function()
    local h = fs.open(p("open.txt"), "w")
    h.write("x")
    local ok, err = pcall(fs.delete, p("open.txt"))
    pcall(h.close)
    pcall(fs.delete, p("open.txt"))
    return { ok, err }
  end)
  check("fs.long_name", "exact", function()
    local ok, err = pcall(function()
      local h = fs.open(p(("n"):rep(300)), "w")
      if h then h.close() return "opened" end
      return "nil"
    end)
    pcall(fs.delete, p(("n"):rep(300)))
    return { ok, err }
  end)
  check("fs.special_names", "exact", function()
    local out = {}
    for _, name in ipairs({ "CON", "nul", "aux.txt", "a:b", "a?b", "trailing.", "trailing space ", "tab\there" }) do
      local ok, h = pcall(fs.open, p(name), "w")
      out[#out + 1] = { name, ok, h and type(h) or h }
      if ok and h then h.close() pcall(fs.delete, p(name)) end
    end
    return out
  end)
  check("fs.case_sensitivity", "exact", function()
    local h = fs.open(p("Case.txt"), "w")
    h.close()
    local r = { fs.exists(p("Case.txt")), fs.exists(p("case.txt")) }
    pcall(fs.delete, p("Case.txt"))
    return r
  end)
  check("fs.dotdot_escape", "exact", function()
    return { pcall(fs.list, TMP .. "/../../.."), fs.exists(TMP .. "/.."), pcall(fs.open, "../x", "r") }
  end)
  check("fs.unicode_name", "exact", function()
    local ok, h = pcall(fs.open, p("é.txt"), "w")
    if ok and h then h.close() pcall(fs.delete, p("é.txt")) end
    return { ok, h and "handle" or h }
  end)
  check("fs.empty_file", "exact", function()
    local h = fs.open(p("empty"), "w")
    h.close()
    local r = fs.open(p("empty"), "r")
    local out = { r.readLine(), r.readAll(), r.read(), r.read(5) }
    r.close()
    local rb = fs.open(p("empty"), "rb")
    local outb = { rb.read(), rb.read(3), rb.readAll(), rb.readLine() }
    rb.close()
    return { out, outb, fs.getSize(p("empty")) }
  end)
  check("fs.line_endings", "exact", function()
    local h = fs.open(p("crlf.txt"), "wb")
    h.write("a\r\nb\rc\nd")
    h.close()
    local r = fs.open(p("crlf.txt"), "r")
    local lines = {}
    while true do local l = r.readLine() if not l then break end lines[#lines + 1] = l end
    r.close()
    local r2 = fs.open(p("crlf.txt"), "r")
    local keep = { r2.readLine(true) }
    r2.close()
    return { lines, keep }
  end)
  check("fs.writeLine_returns", "exact", function()
    local h = fs.open(p("ret.txt"), "w")
    local r = { h.write("a"), h.writeLine("b"), h.flush() }
    h.close()
    return r
  end)

  pcall(fs.delete, TMP)
  check("fs.cleanup", "exact", function() return fs.exists(TMP) end)
end

-----------------------------------------------------
-- 5. Time, timers and events (bucketed so jitter does not matter)
-----------------------------------------------------
local function timeChecks()
  check("os.types", "exact", function()
    return { type(os.clock()), type(os.time()), type(os.epoch("utc")), type(os.epoch("local")), type(os.epoch("ingame")), type(os.day()),
      type(os.getComputerID()), type(os.version()), os.version():match("^%a+") }
  end)
  check("os.time_range", "exact", function()
    local t = os.time()
    return { t >= 0 and t < 24, os.time("utc") >= 0, os.time("ingame") >= 0, os.time("local") >= 0 }
  end)
  check("os.epoch_bad_arg", "exact", function() return os.epoch("nonsense") end)
  check("os.epoch_milliseconds", "exact", function() return os.epoch("utc") > 1.6e12 end)
  check("os.epoch_utc_vs_local_offset_hours", "info", function()
    return (os.epoch("local") - os.epoch("utc")) / 3600000
  end)
  check("os.date_default_format", "info", function() return os.date() end)
  check("os.clock_advances", "exact", function()
    local a = os.clock()
    sleep(0.1)
    return os.clock() > a
  end)
  check("timer.sleep_duration_bucket", "exact", function()
    local start = os.epoch("utc")
    sleep(0.5)
    local ms = os.epoch("utc") - start
    if ms < 400 then return "too_fast:" .. ms end
    if ms > 1500 then return "too_slow:" .. ms end
    return "ok"
  end)
  check("timer.sleep_zero", "exact", function() sleep(0) return "ok" end)
  check("timer.sleep_negative", "exact", function() return pcall(sleep, -1) end)
  check("timer.ids_increase", "exact", function()
    local a, b = os.startTimer(5), os.startTimer(5)
    os.cancelTimer(a) os.cancelTimer(b)
    return { type(a), b > a }
  end)
  check("timer.zero_fires", "exact", function()
    local id = os.startTimer(0)
    while true do
      local _, got = os.pullEvent("timer")
      if got == id then return "fired" end
    end
  end)
  check("timer.fires_order", "exact", function()
    local slow, fast = os.startTimer(0.4), os.startTimer(0.1)
    local first, second
    while not (first and second) do
      local _, id = os.pullEvent("timer")
      if id == fast or id == slow then
        if first then second = id else first = id end
      end
    end
    return first == fast and second == slow
  end)
  check("timer.cancel_prevents_fire", "exact", function()
    local id = os.startTimer(0.2)
    os.cancelTimer(id)
    local guard = os.startTimer(0.5)
    while true do
      local _, got = os.pullEvent("timer")
      if got == id then return "fired" end
      if got == guard then return "cancelled" end
    end
  end)
  check("timer.bad_args", "exact", function() return { pcall(os.startTimer, "x"), pcall(os.startTimer) } end)
  check("alarm.basic", "exact", function()
    local id = os.setAlarm(0)
    os.cancelAlarm(id)
    return { type(id), pcall(os.setAlarm, 25) }
  end)
  check("event.queue_order", "exact", function()
    os.queueEvent("probe_a", 1)
    os.queueEvent("probe_b", 2)
    local _, x = os.pullEvent("probe_a")
    local _, y = os.pullEvent("probe_b")
    return { x, y }
  end)
  check("event.filter_discards_others", "exact", function()
    os.queueEvent("probe_x")
    os.queueEvent("probe_y", "kept")
    local _, v = os.pullEvent("probe_y")
    local guard = os.startTimer(0.2)
    local sawX = false
    while true do
      local e, id = os.pullEvent()
      if e == "probe_x" then sawX = true end
      if e == "timer" and id == guard then break end
    end
    return { v, sawX }
  end)
  check("event.args_preserved", "exact", function()
    os.queueEvent("probe_args", nil, false, "s", 1.5, { 1 })
    local ev = pack(os.pullEvent("probe_args"))
    return { ev.n, ev[2], ev[3], ev[4], ev[5], type(ev[6]) }
  end)
  check("event.queue_no_name_error", "exact", function() return pcall(os.queueEvent) end)
  check("event.pullEventRaw_terminate_filter", "exact", function()
    os.queueEvent("probe_raw")
    return (os.pullEventRaw("probe_raw"))
  end)
  check("event.terminate_via_queue", "exact", function()
    os.queueEvent("terminate")
    local ok, err = pcall(os.pullEvent, "probe_never")
    return { ok, err }
  end)
  check("event.os_pullEvent_returns_name", "exact", function()
    os.queueEvent("probe_name", 7)
    local name, v = os.pullEvent()
    return { name, v }
  end)
  check("event.coroutine_filter_isolation", "exact", function()
    local seen = {}
    parallel.waitForAll(function()
      os.pullEvent("probe_one")
      seen[#seen + 1] = "one"
    end, function()
      os.pullEvent("probe_two")
      seen[#seen + 1] = "two"
    end, function()
      os.queueEvent("probe_two")
      os.queueEvent("probe_one")
    end)
    return seen
  end)
  check("event.user_timer_ids_from_threads", "exact", function()
    local ids = {}
    parallel.waitForAll(function() ids[1] = os.startTimer(0.05) sleep(0.1) end, function() ids[2] = os.startTimer(0.05) sleep(0.1) end)
    return ids[1] ~= ids[2]
  end)
  check("os.shutdown_surface", "exact", function() return { type(os.shutdown), type(os.reboot), type(os.queueEvent), type(os.run) } end)
  check("os.run_env", "exact", function()
    local env = { probe_marker = true }
    local ok = os.run(env, "/.conformance_tmp/not_a_program")
    return ok
  end)
  check("os.loadAPI_surface", "exact", function() return { type(os.loadAPI), type(os.unloadAPI), type(os.sleep), type(sleep), type(write), type(print), type(printError), type(read) } end)
  check("print.return_values", "exact", function()
    local win = window.create(term.current(), 1, 1, 10, 3, false)
    local old = term.redirect(win)
    local a = print("hi", 1, nil, true)
    local b = write("ab\ncd")
    local c = printError("e")
    term.redirect(old)
    return { a, b, c, (win.getLine(1)), (win.getLine(2)), (win.getLine(3)) }
  end)
  check("print.wrap_and_scroll", "exact", function()
    local win = window.create(term.current(), 1, 1, 5, 2, false)
    local old = term.redirect(win)
    print("abcdefghij")
    print("x")
    term.redirect(old)
    return { (win.getLine(1)), (win.getLine(2)) }
  end)
  check("read.default_and_replace", "exact", function()
    -- feed characters into read() through events
    local win = window.create(term.current(), 1, 1, 20, 2, false)
    local old = term.redirect(win)
    local result
    parallel.waitForAny(function() result = read(nil, nil, nil, "dflt") end, function()
      yield()
      os.queueEvent("key", keys.backspace, false)
      os.queueEvent("char", "Z")
      os.queueEvent("key", keys.enter, false)
      sleep(1)
    end)
    term.redirect(old)
    return result
  end)
  check("read.mask", "exact", function()
    local win = window.create(term.current(), 1, 1, 20, 2, false)
    local old = term.redirect(win)
    local result
    parallel.waitForAny(function() result = read("*") end, function()
      yield()
      os.queueEvent("char", "a")
      os.queueEvent("char", "b")
      os.queueEvent("key", keys.enter, false)
      sleep(1)
    end)
    local shown = (win.getLine(1))
    term.redirect(old)
    return { result, shown }
  end)
end

-----------------------------------------------------
-- 6. ROM files, shell, help
-----------------------------------------------------
local function adler(data)
  local a, b = 1, 0
  for i = 1, #data, 4096 do
    local chunk = { data:byte(i, math.min(i + 4095, #data)) }
    for j = 1, #chunk do
      a = (a + chunk[j]) % 65521
      b = (b + a) % 65521
    end
  end
  return b * 65536 + a
end

local rom = {}
local function walkRom(dir)
  for _, name in ipairs(fs.list(dir)) do
    local path = fs.combine(dir, name)
    if fs.isDir(path) then
      walkRom(path)
    else
      local h = fs.open(path, "rb")
      local data = h and h.readAll() or ""
      if h then h.close() end
      rom[#rom + 1] = { path = path, size = #data, sum = adler(data) }
    end
  end
  yield()
end

local function romChecks()
  walkRom("rom")
  table.sort(rom, function(a, b) return a.path < b.path end)
  check("rom.file_count", "info", function() return #rom end)

  check("shell.resolution", "exact", function()
    return { shell.resolve("a/b"), shell.resolve("/a"), shell.resolveProgram("ls"), shell.resolveProgram("list"), shell.resolveProgram("nonexistent_program"),
      shell.resolveProgram("edit"), shell.resolveProgram("lua"), shell.resolveProgram("cd") }
  end)
  check("shell.aliases", "exact", function()
    local a = shell.aliases()
    local out = {}
    for k, v in pairs(a) do out[#out + 1] = k .. "=" .. v end
    table.sort(out)
    return out
  end)
  check("shell.surface", "exact", function()
    local names = {}
    for k, v in pairs(shell) do names[#names + 1] = k .. ":" .. type(v) end
    table.sort(names)
    return names
  end)
  check("shell.completion", "exact", function()
    return { shell.complete("li") }
  end)
  check("shell.programs_rom_only", "exact", function()
    local out = {}
    for _, name in ipairs(shell.programs()) do
      if shell.resolveProgram(name):match("^rom/") then out[#out + 1] = name end
    end
    table.sort(out)
    return out
  end)
  check("shell.path_dir", "info", function() return { shell.path(), shell.dir(), shell.getRunningProgram() } end)
  check("multishell.present", "info", function() return multishell and multishell.getCount() end)
  check("help.topics", "exact", function()
    local t = help.topics()
    table.sort(t)
    return t
  end)
  check("help.lookup", "exact", function() return { help.lookup("fs"), help.lookup("nonexistent_topic"), help.path() } end)
  check("help.completeTopic", "exact", function() return help.completeTopic("sh") end)
  check("motd_and_startup_files", "exact", function()
    return { fs.exists("rom/startup.lua"), fs.exists("rom/motd.txt"), fs.exists("rom/autorun"), fs.exists("rom/help/changelog.md"), fs.exists("rom/help/whatsnew.md") }
  end)
  check("rom.lists", "exact", function()
    local out = {}
    for _, dir in ipairs({ "rom", "rom/apis", "rom/programs", "rom/modules/main", "rom/modules/command", "rom/modules/turtle", "rom/autorun", "rom/help", "rom/programs/http", "rom/programs/rednet", "rom/programs/fun", "rom/programs/advanced", "rom/programs/command", "rom/programs/pocket", "rom/programs/turtle" }) do
      local l = fs.exists(dir) and fs.list(dir) or {}
      table.sort(l)
      out[#out + 1] = { dir, l }
    end
    return out
  end)
end

-----------------------------------------------------
-- 7. Server mods: ccvault, vhcc, peripherals
-----------------------------------------------------
local peripherals = {}

local function modChecks()
  check("ccvault.surface", "exact", function()
    if type(ccvault) ~= "table" then return "absent" end
    local names = listTable(ccvault)
    table.sort(names)
    return names
  end)
  check("vhcc.surface", "exact", function()
    if type(vhcc) ~= "table" then return "absent" end
    local names = {}
    local function walk(prefix, tbl, depth)
      for k, v in pairs(tbl) do
        if type(k) == "string" then
          names[#names + 1] = prefix .. k .. ":" .. type(v)
          if type(v) == "table" and depth < 2 then walk(prefix .. k .. ".", v, depth + 1) end
        end
      end
    end
    walk("", vhcc, 0)
    table.sort(names)
    return names
  end)
  check("ccvault.isAvailable", "info", function() return ccvault and ccvault.isAvailable and ccvault.isAvailable() end)
  check("ccvault.getPlayerName_type", "type", function() return ccvault and ccvault.getPlayerName and ccvault.getPlayerName() end)
  check("ccvault.getHostName_type", "type", function() return ccvault and ccvault.getHostName and ccvault.getHostName() end)
  check("ccvault.isAuthenticated", "exact", function() return ccvault and ccvault.isAuthenticated and ccvault.isAuthenticated() end)
  check("ccvault.transfer_requires_auth", "exact", function()
    if not (ccvault and ccvault.transfer) then return "absent" end
    return { pcall(ccvault.transfer, "player", "host", 0, "probe") }
  end)
  check("ccvault.transfer_bad_identity", "exact", function()
    if not (ccvault and ccvault.transfer) then return "absent" end
    return { pcall(ccvault.transfer, "someone", "host", 1, "probe") }
  end)
  check("ccvault.transfer_bad_amount", "exact", function()
    if not (ccvault and ccvault.transfer) then return "absent" end
    return { pcall(ccvault.transfer, "player", "host", -5, "probe") }
  end)
  check("ccvault.transfer_long_reason", "exact", function()
    if not (ccvault and ccvault.transfer) then return "absent" end
    return { pcall(ccvault.transfer, "player", "host", 0, ("x"):rep(200)) }
  end)
  check("ccvault.getBalance_requires_auth", "exact", function()
    if not (ccvault and ccvault.getBalance) then return "absent" end
    return { pcall(ccvault.getBalance, "player") }
  end)

  for _, name in ipairs(peripheral.getNames()) do
    local entry = { name = name, type = peripheral.getType(name), methods = {} }
    local methods = peripheral.getMethods(name) or {}
    table.sort(methods)
    entry.methods = methods
    peripherals[#peripherals + 1] = entry
  end
  check("peripheral.names", "info", function()
    local out = {}
    for _, e in ipairs(peripherals) do out[#out + 1] = e.name .. ":" .. tostring(e.type) end
    return out
  end)
end

-----------------------------------------------------
-- 8. Every script on this computer: does it compile here?
-----------------------------------------------------
local files = {}

local SKIP = { ["/rom"] = true, ["/.conformance_tmp"] = true, ["/.vhcc_data"] = true, ["/ccunit"] = true, ["/results"] = true }

local function walkFiles(dir, depth)
  if depth > 8 or SKIP[dir] or #files >= 3000 then return end
  local ok, list = pcall(fs.list, dir)
  if not ok then return end
  for _, name in ipairs(list) do
    local path = fs.combine(dir, name)
    local abs = "/" .. path
    if not SKIP[abs] then
      if fs.isDir(path) then
        walkFiles(path, depth + 1)
      elseif name:match("%.lua$") and fs.getSize(path) <= 1048576 and #files < 3000 then
        local h = fs.open(path, "rb")
        if h then
          local data = h.readAll() or ""
          h.close()
          local f, err = load(data, "=" .. path)
          files[#files + 1] = { path = path, size = #data, sum = adler(data), ok = f ~= nil, err = err and cleanError(err) or nil }
        end
      end
    end
  end
  yield()
end

-----------------------------------------------------
-- 9. Exact tables and mod/peripheral behaviour
-----------------------------------------------------
local function extraChecks()
  -- Which of the 256 characters each pattern class matches, as a 256-digit 0/1 string per class.
  for _, class in ipairs({ "a", "c", "d", "l", "p", "s", "u", "w", "x", "A", "D", "S" }) do
    check("str.class_table." .. class, "exact", function()
      local bits = {}
      for b = 0, 255 do bits[#bits + 1] = string.char(b):find("%" .. class) and "1" or "0" end
      return table.concat(bits)
    end)
  end
  -- tostring / string.format of assorted numbers, so number printing is checked widely
  local numbers = { 0, 1, -1, 0.5, 1 / 3, 100, 1e5, 1e14, 1e15, 1e16, 2 ^ 31, 2 ^ 53, 2 ^ 63, 2 ^ 64, -2 ^ 63, 1e100, 1e-5, 123456789.123, 255 / 256 }
  check("num.tostring_table", "exact", function()
    local out = {}
    for i, n in ipairs(numbers) do out[i] = tostring(n) end
    return out
  end)
  check("num.format_table", "exact", function()
    local out = {}
    for i, n in ipairs(numbers) do out[i] = string.format("%.14g|%d|%5.2f|%g", n, math.floor(n % 2 ^ 31), n, n) end
    return out
  end)
  check("num.integer_ops", "exact", function()
    return { 7 / 2, math.floor(7 / 2), 7 % 3, -7 % 3, 2 ^ 10, 10 % 3.5, math.floor(-3.5), math.ceil(-3.5), math.abs(-0), 1e15 + 1, 2 ^ 53 + 1 }
  end)

  -- ccvault: the text of every error, called without arguments and without authentication
  if type(ccvault) == "table" then
    local skip = { requestAuth = true, claimHost = true, transfer = true, transferSelf = true }
    local names = {}
    for name, fn in pairs(ccvault) do
      if type(fn) == "function" and not skip[name] then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      check("ccvault.call." .. name, "exact", function()
        local r = pack(pcall(ccvault[name]))
        local out = {}
        for i = 1, r.n do out[i] = r[i] end
        return out
      end)
    end
  end

  -- a monitor, if the computer has one next to it
  local monitor = peripheral.find and peripheral.find("monitor")
  if monitor then
    check("mon.size_types", "exact", function()
      local w, h = monitor.getSize()
      return { type(w), type(h), monitor.isColor(), monitor.getTextScale() }
    end)
    check("mon.methods_have_no_extras", "exact", function()
      local names = {}
      for name, fn in pairs(monitor) do if type(fn) == "function" then names[#names + 1] = name end end
      table.sort(names)
      return names
    end)
    check("mon.scale_changes_size", "exact", function()
      local w1, h1 = monitor.getSize()
      local out = { w1, h1 }
      for _, s in ipairs({ 0.5, 2, 5, 1 }) do
        monitor.setTextScale(s)
        local w, h = monitor.getSize()
        out[#out + 1] = s .. "=" .. w .. "x" .. h
      end
      return out
    end)
    check("mon.scale_bad_values", "exact", function()
      local out = {}
      for _, s in ipairs({ 0, 0.4, 5.5, 0.75, -1 }) do out[#out + 1] = { s, pcall(monitor.setTextScale, s) } end
      monitor.setTextScale(1)
      return out
    end)
    check("mon.draw_and_read", "exact", function()
      monitor.setBackgroundColor(colors.blue)
      monitor.setTextColor(colors.yellow)
      monitor.clear()
      monitor.setCursorPos(2, 2)
      monitor.write("probe")
      monitor.blit("ab", "01", "fe")
      return { monitor.getCursorPos(), monitor.getBackgroundColor(), monitor.getTextColor(), monitor.getCursorBlink() }
    end)
    check("mon.palette", "exact", function()
      monitor.setPaletteColor(colors.red, 0.25, 0.5, 0.75)
      local r = { monitor.getPaletteColor(colors.red) }
      monitor.setPaletteColor(colors.red, 0xcc4c4c)
      return r
    end)
    check("mon.out_of_range_cursor", "exact", function()
      monitor.setCursorPos(0, 0)
      monitor.write("x")
      monitor.setCursorPos(1000, 1000)
      monitor.write("y")
      return { monitor.getCursorPos() }
    end)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    monitor.setTextScale(1)
  end
end

-----------------------------------------------------
-- Run everything and write the report
-----------------------------------------------------
local function section(name, fn)
  say("probing " .. name .. " ...")
  local ok, err = pcall(fn)
  if not ok then
    failures = failures + 1
    checks[#checks + 1] = { id = "probe.section_crashed." .. name, mode = "exact", v = "ERR " .. cleanError(err) }
    say("  section crashed: " .. cleanError(err))
  end
end

local started = os.epoch("utc")
section("language", languageChecks)
section("api surface", surfaceChecks)
section("libraries", libraryChecks)
section("filesystem", fsChecks)
section("time and events", timeChecks)
section("rom and shell", romChecks)
section("mods and peripherals", modChecks)
section("exact tables and monitor", extraChecks)
section("installed scripts", function() walkFiles("", 0) end)

local meta = {
  version = _VERSION,
  host = _HOST,
  osVersion = os.version(),
  computerId = os.getComputerID(),
  label = os.getComputerLabel(),
  probeFormat = 1,
  checks = #checks,
  durationMs = os.epoch("utc") - started,
  finishedAt = os.epoch("utc"),
}

local report = { meta = meta, checks = checks, sets = sets, rom = rom, files = files, peripherals = peripherals }
local out = textutils.serializeJSON(report)
local h = fs.open(RESULT_FILE, "w")
if not h then
  printError("could not write " .. RESULT_FILE)
  return
end
h.write(out)
h.close()

local badFiles = 0
for _, f in ipairs(files) do if not f.ok then badFiles = badFiles + 1 end end
print(("Conformance probe done: %d checks, %d ROM files, %d scripts compiled (%d failed to compile)."):format(#checks, #rom, #files, badFiles))
print("Wrote " .. RESULT_FILE .. " (" .. #out .. " bytes).")
if failures > 0 then printError(failures .. " probe section(s) crashed; see the probe.section_crashed checks.") end
print("Give that file to the emulator project: node tools/conformance/compare.mjs --server " .. RESULT_FILE)
