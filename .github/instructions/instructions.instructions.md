---
applyTo: '**'
---

You are writing Lua 5.1 code for ComputerCraft.

Core rules
- Never use the `goto` keyword or labels.
- Declare or define every variable or function before its first reference. Use `local <name> = nil` for forward declarations.
- Prefer local variables over globals unless a global is truly needed.
- Stick to syntax and standard libraries that exist in Lua 5.1.
- Use idiomatic ComputerCraft APIs for I/O, networking, and multitasking.
- For complex flow control, use loops or helper functions, not goto.

Time-saving and bug-preventing habits
- Scan inventories with `inventory.list()`; call `getItemDetail()` only on slots that need full NBT.
- Wrap peripherals once: `local chest = peripheral.wrap("right")`.
- Pull only the events you need: `os.pullEvent("redstone")`, `os.pullEvent("timer")`, etc.
- Add `os.sleep(0)` inside tight `while true do` loops so the computer yields.
- Cache hot functions to locals: `local select, sleep = turtle.select, os.sleep`
- Use `parallel.waitForAny` / `parallel.waitForAll` instead of manual state machines.
- Predeclare forward-referenced functions: `local main; main = function() ... end`
- Buffer monitor frames, then `term.blit()` once per tick to avoid flicker.
- Use `settings.define` keys to toggle debug prints without editing code.
- Send structured tables over rednet with `textutils.serializeJSON`.

Defensive coding
- Validate arguments with `assert(type(path) == "string", "path must be a string")`.
- Wrap risky calls in `pcall` so errors don't crash the whole loop.
- Always check `fs.open()` return -- it returns nil on failure.
- Always close file handles: `local h = fs.open(p, "w"); h.write(data); h.close()`.
- Use constants for sides: `local LEFT, RIGHT, TOP, BOTTOM = "left", "right", "top", "bottom"`.
- Convert rednet IDs with `tonumber()` when parsed from JSON.
- `term.getSize()` before UI layout so it adapts to any monitor.
- Fallback stubs when a peripheral is missing for graceful degradation.
- Use `colors.*` consistently (not `colours.*`).
- `textutils.serialize()` for file persistence, `textutils.serializeJSON()` only for rednet/HTTP.
- Use `require()` consistently for shared config (not `dofile()`).

Nil Function / Nil Upvalue Prevention (Critical)
- Never pass a potentially-nil function reference to `pcall`, `safeCall`, or any wrapper.
- Always validate `fn` in safe-call wrappers: check `type(fn) ~= "function"` before calling.
- Never pass bare method refs to `pcall` -- always wrap: `pcall(function() return obj.method(arg) end)`.
- Check method existence before calling on external APIs (`ccvault.*`, `vhcc.*`, peripheral methods).

Error Logging Requirements
- All scripts must log errors to a file. Do not rely solely on screen output.
- `safeCall` wrappers must log errors, not just return them silently.
- Main loops need a top-level error handler writing to `<script_name>_error.log`.
- Timestamps: `os.epoch("local")` (milliseconds, real time) -- never `os.time()`.

Time API Gotcha
- `os.time()` = in-game Minecraft time (0-24), NOT real time.
- For elapsed/duration: `os.epoch("local")` (milliseconds).
- `os.startTimer()` leaks if not cancelled -- always `os.cancelTimer(id)` before starting a new timer in a loop.

Modular Programming
- Pre-declare and assign for forward references (`local myHelper`; later `myHelper = function(...) ... end`).
- Modules return a table of public API only (`return { fn = fn }`).
- Local by default. Globals only when truly needed across unlinked code.
- Never re-declare a `local` that's already in scope -- it shadows the original.