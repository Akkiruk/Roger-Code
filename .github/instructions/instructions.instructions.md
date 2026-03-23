---
applyTo: '**'
---

You are writing Lua 5.1 code for ComputerCraft.

Core rules
• Never use the goto keyword or labels.
• Declare or define every variable or function before its first reference.  
  - If something is filled later, put `local <name> = nil` or a stub up top.
• Prefer local variables over globals unless a global is truly needed.
• Stick to syntax and standard libraries that exist in Lua 5.1.
• Use idiomatic ComputerCraft APIs for I/O, networking, and multitasking.
• For complex flow control, use loops or helper functions, not goto.

Time-saving and bug-preventing habits
• Scan inventories with `inventory.list()`; call `getItemDetail()` only on slots that need full NBT.  
• Wrap peripherals once: `local chest = peripheral.wrap("right")`.
• Pull only the events you need: `os.pullEvent("redstone")`, `os.pullEvent("timer")`, etc.
• Add `os.sleep(0)` inside tight `while true do` loops so the computer yields.
• Cache hot functions to locals:  
  ```lua
  local select, sleep = turtle.select, os.sleep
```

• Combine tasks with `parallel.waitForAny` or `parallel.waitForAll` instead of manual state machines.
• Predeclare forward-referenced functions:

```lua
local main
main = function() … end
```

• Stream big files line by line; for ≤128 kB just `fs.open(path,"r").readAll()`.
• Build monitor frames in a buffer, then `term.blit()` once per tick to avoid flicker.
• Poll turtle fuel or inventory every 20–40 ticks, not every loop pass.
• Use `settings.define` keys to toggle debug prints without editing code.
• Send structured tables over rednet as JSON with `textutils.serializeJSON`.
• Run `luac -p <file.lua>` locally before uploading to catch syntax errors fast.
• Keep a one-command bootstrap (disk, pastebin, or Git URL) with your favorite libraries.

Extra defensive tricks
• Validate arguments:

```lua
local function writeData(path, data)
    assert(type(path) == "string", "path must be a string")
    …
end
```

• Wrap risky calls in `pcall` so a bad move or file error doesn’t crash the whole loop.
• Always close file handles:

```lua
local h = fs.open(p,"w") … h.close()
```

• Use constants for sides or directions to avoid typos:

```lua
local LEFT, RIGHT, TOP, BOTTOM = "left","right","top","bottom"
```

• Call `turtle.getFuelLevel()` once per batch and cache the result.
• Treat rednet IDs as numbers; convert with `tonumber()` if you parse them from JSON.
• Call `term.getSize()` before laying out UI so it adapts to any monitor.
• Use `colors.test(mask, colors.red)` for quick colored-redstone checks.
• Provide fallback stubs when a peripheral is missing so scripts degrade gracefully.
• Add a tiny logger helper:

```lua
local DEBUG = settings.get("debug") or false
local function log(msg) if DEBUG then print(os.time(),msg) end end
```

Avoid re-declaring variables: When pre-declaring functions or variables, ensure you are not re-declaring an identifier that is already defined and in scope earlier in the file.
Re-declaring a local variable in the same or a more specific scope will shadow the original, potentially leading to nil value errors if the new declaration is not immediately assigned 
to the intended value.

**Nil Function / Nil Upvalue Prevention (Critical)**

Never pass a potentially-nil function reference to `pcall`, `safeCall`, or any wrapper.
This causes the cryptic error `"attempt to call upvalue 'fn' (a nil value)"` and masks the real problem.

• Always validate `fn` in safe-call wrappers:
```lua
local function safeCall(fn, ...)
  if type(fn) ~= "function" then
    return false, "safeCall: expected function, got " .. type(fn)
  end
  local args = { ... }
  local ok, result = pcall(function() return fn(table.unpack(args)) end)
  return ok, result
end
```

• Never pass bare method references to `pcall` — always wrap in a closure:
```lua
-- BAD:  pcall(obj.method)         — if obj.method is nil, error is cryptic
-- BAD:  pcall(obj.method, arg)    — same problem
-- GOOD: pcall(function() return obj.method(arg) end)
```

• Check method existence before calling when the API table may lack the method:
```lua
if type(vhcc.write) == "function" then
  local ok, err = pcall(function() return vhcc.write(path, data) end)
else
  outFail("vhcc.write not available in this mod version")
end
```

• Applies to all external APIs (`ccvault.*`, `vhcc.*`, peripheral methods) — never assume a method exists just because the parent table exists.

**Error Logging Requirements**

All scripts must automatically log errors to a file when they occur. Do not rely solely on screen output for error reporting.

• Every script that uses `pcall` should log failures:
```lua
local ok, err = pcall(function() return riskyOperation() end)
if not ok then
  local f = fs.open("script_error.log", "a")
  if f then
    f.writeLine("[" .. os.epoch("local") .. "] " .. tostring(err))
    f.close()
  end
end
```

• safeCall / safeCallResult wrappers must log errors, not just return them silently.
• Main program loops should have a top-level error handler that writes crashes to `<script_name>_error.log`.
• Test suites must log all [FAIL] results to a log file in addition to displaying them on screen.
• Use `os.epoch("local")` for timestamps in logs (milliseconds, real time), never `os.time()`.

**Modular Programming and Scope Management**
*   **Pre-declare and Assign for Forward References:** If functions within the same scope call each other and their definitions are not strictly top-down, pre-declare them (e.g., `local myHelperFunction`). Later, assign the function definition (e.g., `myHelperFunction = function(...) ... end`). This resolves issues with functions being called before they are fully defined.
*   **Module API Design (Return Table):** When creating modules (separate files intended to be loaded as libraries), ensure the script returns a table. This table should contain only the functions and variables you intend to expose as the module's public API (e.g., `return { usefulFunction = usefulFunction, configValue = myConfig }`).
*   **Prioritize Local Scope:** Declare variables and functions as `local` by default. Only use global variables when absolutely necessary (e.g., for values that truly need to be accessible across different, unlinked parts of a program without explicit passing). This minimizes accidental variable overwrites and makes code dependencies clearer.
*   **Mindful Execution Order:** Always consider the sequence in which your code executes. Ensure that variables are initialized, data is loaded, and necessary setup operations (like peripheral wrapping or configuration loading) are completed *before* any functions or logic that depend on them are invoked. For example, load configuration settings before calling functions that use those settings.

Follow all of the above unless the user explicitly overrides.

```

