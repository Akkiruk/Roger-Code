# Copilot Instructions — Roger Code Workspace

## Language & Platform

You are writing **Lua 5.1** code for **ComputerCraft** (CC: Tweaked / CC: Restitched).

---

## Core Rules

- Never use the `goto` keyword or labels.
- Declare or define every variable or function before its first reference.
  - If something is filled later, put `local <name> = nil` or a stub up top.
- Prefer `local` variables over globals unless a global is truly needed.
- Stick to syntax and standard libraries that exist in Lua 5.1.
- Use idiomatic ComputerCraft APIs for I/O, networking, and multitasking.
- For complex flow control, use loops or helper functions — not `goto`.

---

## Modular Programming & Scope

- **Pre-declare and Assign for Forward References:** If functions within the same scope call each other and definitions aren't top-down, pre-declare them (`local myHelper`), then assign later (`myHelper = function(...) ... end`).
- **Module API Design:** Modules must return a table containing only the public API (`return { fn = fn, cfg = cfg }`).
- **Prioritize Local Scope:** Declare everything `local` by default. Globals only when truly needed across unlinked code.
- **Mindful Execution Order:** Ensure variables, configs, and peripheral wraps are initialized *before* any code that depends on them runs.
- **No re-declarations:** Never re-declare a `local` that's already in scope — it shadows the original and causes nil bugs.

---

## Performance & Bug Prevention

- Scan inventories with `inventory.list()`; call `getItemDetail()` only on slots that need full NBT.
- Wrap peripherals once: `local chest = peripheral.wrap("right")`.
- Pull only needed events: `os.pullEvent("redstone")`, `os.pullEvent("timer")`, etc.
- Add `os.sleep(0)` inside tight `while true do` loops so the computer yields.
- Cache hot functions to locals:
  ```lua
  local select, sleep = turtle.select, os.sleep
  ```
- Use `parallel.waitForAny` / `parallel.waitForAll` instead of manual state machines.
- Stream big files line by line; for ≤128 kB just `fs.open(path,"r").readAll()`.
- Build monitor frames in a buffer, then `term.blit()` once per tick to avoid flicker.
- Poll turtle fuel or inventory every 20–40 ticks, not every loop pass.
- Use `settings.define` keys to toggle debug prints without editing code.
- Send structured tables over rednet as JSON with `textutils.serializeJSON`.

---

## Defensive Coding

- Validate arguments:
  ```lua
  local function writeData(path, data)
      assert(type(path) == "string", "path must be a string")
  end
  ```
- Wrap risky calls in `pcall` so a bad move or file error doesn't crash the whole loop.
- Always close file handles:
  ```lua
  local h = fs.open(p, "w"); h.write(data); h.close()
  ```
- Use constants for sides/directions to avoid typos:
  ```lua
  local LEFT, RIGHT, TOP, BOTTOM = "left", "right", "top", "bottom"
  ```
- Cache `turtle.getFuelLevel()` once per batch.
- Treat rednet IDs as numbers; convert with `tonumber()` if parsed from JSON.
- Call `term.getSize()` before laying out UI so it adapts to any monitor.
- Use `colors.test(mask, colors.red)` for quick colored-redstone checks.
- Provide fallback stubs when a peripheral is missing so scripts degrade gracefully.
- Use `colors.*` consistently (not `colours.*`) across the project.
- Use `textutils.serialize()` for file persistence, `textutils.serializeJSON()` only for rednet/HTTP.
- Tiny logger helper:
  ```lua
  local DEBUG = settings.get("debug") or false
  local function log(msg) if DEBUG then print(os.time(), msg) end end
  ```

---

## Nil Function / Nil Upvalue Prevention (Critical)

**Never pass a potentially-nil function reference to `pcall`, `safeCall`, or any wrapper.**
This causes the cryptic error `"attempt to call upvalue 'fn' (a nil value)"` and masks the real problem (missing method on a table).

- **Always validate `fn` in safe-call wrappers:**
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
- **Never pass bare method references to `pcall`** — always wrap in a closure:
  ```lua
  -- BAD:  pcall(obj.method)         — if obj.method is nil, error is cryptic
  -- BAD:  pcall(obj.method, arg)    — same problem
  -- GOOD: pcall(function() return obj.method(arg) end)
  ```
- **Check method existence before calling** when the API table may lack the method:
  ```lua
  if type(vhcc.write) == "function" then
    local ok, err = pcall(function() return vhcc.write(path, data) end)
  else
    outFail("vhcc.write not available in this mod version")
  end
  ```
- **Applies to all external APIs** (`ccvault.*`, `vhcc.*`, peripheral methods) — never assume a method exists just because the parent table exists.

---

## Error Logging Requirements

All scripts must automatically log errors to a file when they occur. Do not rely solely on screen output for error reporting.

- **Every script that uses `pcall` should log failures:**
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
- **safeCall / safeCallResult wrappers must log errors**, not just return them silently. At minimum, write to a log file.
- **Main program loops should have a top-level error handler** that writes crashes to `<script_name>_error.log`:
  ```lua
  local ok, err = pcall(mainLoop)
  if not ok then
    local f = fs.open("myprogram_error.log", "a")
    if f then
      f.writeLine("[" .. os.epoch("local") .. "] CRASH: " .. tostring(err))
      f.close()
    end
    error(err) -- re-raise so user sees it too
  end
  ```
- **Test suites must log all [FAIL] results to a log file** in addition to displaying them on screen.
- Use `os.epoch("local")` for timestamps in logs (milliseconds, real time), never `os.time()`.

---

## Time API Gotcha

- `os.time()` returns in-game Minecraft time (0–24), NOT real time.
- For elapsed/duration timing, use `os.epoch("local")` (returns milliseconds).
- `os.startTimer()` leaks if not cancelled — always `os.cancelTimer(id)` before starting a new timer in a loop.

---

## CraftOS-PC Emulator Integration

This workspace has a CraftOS-PC emulator fully integrated for testing ComputerCraft code.

### Emulator Filesystem

CraftOS-PC computer 0 data is at: `%APPDATA%\CraftOS-PC\computer\0\`

After deployment, the layout is:
```
computer/0/
  blackjack.lua          # Main game
  blackjack_config.lua   # Config with enums
  statistics.lua         # Stats wrapper
  stats_ui.lua           # Stats UI
  startup.lua            # <- emulator/emu_startup.lua
  surface, font, gothic  # Graphics assets
  *.nfp                  # Card/suit sprites
  lib/                   # All shared libraries
  emulator/              # Mock framework + stubs
    boot.lua
    mock_peripherals.lua
    emu_startup.lua
    mocks/
      monitor.lua
      inventory.lua
      speaker.lua
      player_detector.lua
      chatbox.lua
```

### Emulator Mock Architecture

The emulator files live in `Games/emulator/`:
- `boot.lua` — Bootstrapper that loads mock peripherals and exposes `_G.MOCK` test controls
- `mock_peripherals.lua` — Framework that monkey-patches the global `peripheral` API
- `emu_startup.lua` — Menu-based startup deployed as the emulator's `startup.lua`
- `mocks/monitor.lua` — Mock monitor (fixed 71×38 size)
- `mocks/inventory.lua` — Mock barrel/chest with silver tracking and cross-inventory transfers
- `mocks/speaker.lua` — Mock speaker that logs sounds
- `mocks/player_detector.lua` — Mock playerDetector with configurable player list
- `mocks/chatbox.lua` — Mock chatBox that logs messages

### Deploy & Run (VS Code Tasks — Ctrl+Shift+B)

- **Deploy + Start CraftOS-PC** (default build) — Syncs files, installs mocks, opens emulator
- **Deploy Blackjack to Emulator** — Syncs without opening
- **Deploy (No Mocks)** — Syncs only game files, no emulator mocks
- **Clean Emulator Files** — Wipes the emulator computer clean
- **View Emulator Files** — Lists deployed file tree
- **Read Emulator Logs** — Shows tail of all log files

### Deploy & Run (Terminal / AI)

```powershell
# Deploy files
powershell -ExecutionPolicy Bypass -File ".vscode/deploy-to-emulator.ps1"

# Read emulator files
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\<filename>"

# Write to emulator filesystem
Set-Content "$env:APPDATA\CraftOS-PC\computer\0\<filename>" -Value "<content>"

# Read logs after a test
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\emulator\mock_log.txt"
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\blackjack_error.log"
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\statistics_error.log"

# Read player stats data
Get-ChildItem "$env:APPDATA\CraftOS-PC\computer\0\player_data" | Get-Content

# Check crash recovery state
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\blackjack_recovery.dat"
```

### Mock Test Controls (in CraftOS shell)

After `boot.lua` runs, `_G.MOCK` is available:
- `MOCK.setSilver(barrelAmt, bankAmt)` — Set silver amounts
- `MOCK.setPlayer("name")` — Change detected player
- `MOCK.noPlayer()` — Simulate player leaving
- `MOCK.autoPlay(true/false)` — Toggle auto-play bot
- `MOCK.status()` — Print barrel/bank/sound/chat overview

Direct mock object access:
- `MOCK.barrel._getSilverCount()` / `MOCK.barrel._setSilver(n)`
- `MOCK.bank._getSilverCount()` / `MOCK.bank._setSilver(n)`
- `MOCK.speaker._getHistory()` / `MOCK.speaker._clearHistory()`
- `MOCK.detector._setPlayers({"Name1","Name2"})`
- `MOCK.chatbox._getHistory()`

---

## CraftOS-PC AI Terminal API

The CraftOS-PC VS Code extension (`jackmacwindows.craftos-pc` v1.2.3) exposes commands
that let Copilot interact directly with running CraftOS-PC terminals via `run_vscode_command`.

### Lifecycle

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.open` | none | — | Launch CraftOS-PC (computer 0) |
| `craftos-pc.close` | none | — | Close the running CraftOS-PC process |
| `craftos-pc.api.is-running` | none | `true`/`false` | Check if emulator is running |
| `craftos-pc.api.list-windows` | none | `[{id, width, height, title}]` | List all open windows |

### Screen Reading

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.screenshot` | none | `{text, width, height, cursorX, cursorY, title}` | Read terminal as plain text |
| `craftos-pc.api.screenshot-colors` | none | `{text, colorMap, colorSummary, width, height, ...}` | Read text + per-cell color data |

Color map hex codes: `0`=white, `1`=orange, `2`=magenta, `3`=lightBlue, `4`=yellow, `5`=lime, `6`=pink, `7`=gray, `8`=lightGray, `9`=cyan, `a`=purple, `b`=blue, `c`=brown, `d`=green, `e`=red, `f`=black.

### Text & Key Input

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.type-text` | `["text"]` | `{success, typed}` | Type characters one by one (no Enter) |
| `craftos-pc.api.paste-text` | `["text"]` | `{success, pasted}` | Paste via CC paste event (first line only) |
| `craftos-pc.api.execute-line` | `["code"]` | `{success, executed}` | Paste + press Enter (single-line commands) |
| `craftos-pc.api.press-key` | `["keyName"]` | `{success, key, code}` | Press a named key |
| `craftos-pc.api.send-ctrl-key` | `["key"]` | `{success}` | Send Ctrl+key combo |
| `craftos-pc.api.queue-event` | `["eventName", ...]` | `{success}` | Queue a raw CC event |

**Supported key names:** `enter`, `backspace`, `tab`, `space`, `up`, `down`, `left`, `right`, `home`, `end`, `delete`, `escape`, `f1`–`f12`, `pageUp`, `pageDown`, `leftShift`, `rightShift`, `leftCtrl`, `rightCtrl`, `leftAlt`, `rightAlt`.

**Common Ctrl combos:** `["t"]` = terminate, `["r"]` = reboot, `["s"]` = shutdown.

### Full AI Testing Workflow

1. Deploy: `powershell -File ".vscode/deploy-to-emulator.ps1"`
2. Start: `craftos-pc.open`
3. Verify: `craftos-pc.api.is-running`
4. Run: `craftos-pc.api.execute-line` `["shell.run('blackjack')"]`
5. Read: `craftos-pc.api.screenshot`
6. Interact: `craftos-pc.api.press-key` `["enter"]` / `craftos-pc.api.type-text` `["yes"]`
7. Stop: `craftos-pc.api.send-ctrl-key` `["t"]`
8. Logs: `Get-Content "$env:APPDATA\CraftOS-PC\computer\0\blackjack_error.log"`

---

## Key Limitations

- **Surface API**: The `surface` file is a binary/precompiled CC library — works in-emulator but AI cannot read/modify it.
- **Monitor size**: Mock returns fixed 71×38 (4×3 monitor at 0.5 scale). Real game may differ.
- **No real item NBT**: Mock inventories return simplified item data without NBT tags.
- **No real sounds**: Speaker mock logs sounds but doesn't play audio.
- **Rednet/modem**: Not mocked. If a game uses rednet, additional mocks would be needed.

---

## Debugging

`launch.json` has two configurations:
- **Debug Blackjack** — Launches `blackjack.lua` with CraftOS-PC debugger (F5)
- **Debug Current File** — Launches whatever file is open

Breakpoints work on any `.lua` file. Requires CraftOS-PC v2.7+ (installed: v2.8.3).
