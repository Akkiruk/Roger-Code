---
applyTo: 'Games/**'
---

# Legacy CraftOS-PC Notes

The active workflow now targets the real PrismLauncher runtime under `saves/*/computercraft/computer/`.
Use the emulator notes below only when you are explicitly doing emulator-specific work.

## Live Runtime First

- Preferred deploy path: `powershell -ExecutionPolicy Bypass -File "scripts/sync-roger-code.ps1" -Game <Name>`
- Direct deploy path: `powershell -ExecutionPolicy Bypass -File "scripts/deploy-to-world.ps1" -Game <Name>`
- Discover installed computers: `powershell -ExecutionPolicy Bypass -File "scripts/deploy-to-world.ps1" -ListTargets`
- The legacy `.vscode/deploy-to-emulator.ps1` entry point now forwards to the live PrismLauncher deploy flow.

## CraftOS-PC Reference

This section remains as historical reference for CraftOS-PC testing.

## Architecture

The emulator files live in `Games/emulator/`:
- `boot.lua` — Bootstrapper that loads mock peripherals and exposes `_G.MOCK` test controls
- `mock_peripherals.lua` — Framework that monkey-patches the global `peripheral` API
- `emu_startup.lua` — Menu-based startup deployed as the emulator's `startup.lua`
- `mocks/monitor.lua` — Mock monitor (delegates to native term with fixed 71x38 size)
- `mocks/inventory.lua` — Mock barrel/chest with silver tracking and cross-inventory transfers
- `mocks/speaker.lua` — Mock speaker that logs sounds instead of playing them
- `mocks/player_detector.lua` — Mock playerDetector with configurable player list
- `mocks/chatbox.lua` — Mock chatBox that logs messages

## Emulator Filesystem

CraftOS-PC computer 0 data is at: `%APPDATA%\CraftOS-PC\computer\0\`

After deployment, the layout is:
```
computer/0/
  blackjack.lua          # Main game
  blackjack_config.lua   # Config with enums
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

## How to Deploy & Run

### From VS Code Tasks (Ctrl+Shift+B)
- **Deploy + Start CraftOS-PC** (default) — Syncs files, installs mocks, opens emulator
- **Deploy Blackjack to Emulator** — Syncs without opening
- **Deploy (No Mocks)** — Syncs only game files, no emulator mocks
- **Clean Emulator Files** — Wipes the emulator computer clean
- **View Emulator Files** — Lists deployed file tree
- **Read Emulator Logs** — Shows tail of all log files

### From AI / Terminal
Deploy files through the legacy wrapper:
```powershell
powershell -ExecutionPolicy Bypass -File ".vscode/deploy-to-emulator.ps1"
```

Start CraftOS-PC session in VS Code:
```
# Use VS Code command: craftos-pc.open
```

Read emulator files directly:
```powershell
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\<filename>"
```

Write to emulator filesystem:
```powershell
Set-Content "$env:APPDATA\CraftOS-PC\computer\0\<filename>" -Value "<content>"
```

Read logs after a test:
```powershell
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\emulator\mock_log.txt"
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\blackjack_error.log"
```

Check crash recovery state:
```powershell
Get-Content "$env:APPDATA\CraftOS-PC\computer\0\blackjack_recovery.dat"
```

## Mock Test Controls (in CraftOS shell)

After boot.lua runs, `_G.MOCK` is available:
- `MOCK.setSilver(barrelAmt, bankAmt)` — Set silver amounts
- `MOCK.setPlayer("name")` — Change detected player
- `MOCK.noPlayer()` — Simulate player leaving
- `MOCK.status()` — Print barrel/bank/sound/chat overview

Access mock objects directly:
- `MOCK.barrel._getSilverCount()` / `MOCK.barrel._setSilver(n)`
- `MOCK.bank._getSilverCount()` / `MOCK.bank._setSilver(n)`
- `MOCK.speaker._getHistory()` / `MOCK.speaker._clearHistory()`
- `MOCK.detector._setPlayers({"Name1","Name2"})`
- `MOCK.chatbox._getHistory()`

## Debugging

launch.json has two configurations:
- **Debug Blackjack** — Launches blackjack.lua with CraftOS-PC debugger (F5)
- **Debug Current File** — Launches whatever file is open

Breakpoints work on any `.lua` file. Requires CraftOS-PC v2.7+ (installed: v2.8.3).

## AI Workflow for Testing Changes

1. Make code changes to files in `Games/Blackjack/` or `Shared/lib/`
2. Run deploy: `powershell -ExecutionPolicy Bypass -File ".vscode/deploy-to-emulator.ps1"`
3. Read back the deployed file to verify: `Get-Content "$env:APPDATA\CraftOS-PC\computer\0\<file>"`
4. After user runs in emulator, read logs: `Get-Content "$env:APPDATA\CraftOS-PC\computer\0\emulator\mock_log.txt"`
5. Check for crash recovery data or error logs as needed

## CraftOS-PC API Commands (AI Integration)

The CraftOS-PC extension has been modified with programmatic API commands.
These are VS Code commands callable via `run_vscode_command` for direct emulator control.

> **Backups**: `extension.js.bak` and `package.json.bak` exist in the extension directory.
> **Path**: `%USERPROFILE%\.vscode\extensions\jackmacwindows.craftos-pc-1.2.3\`
> **Warning**: VS Code extension updates will overwrite these modifications.

### Status & Info

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.is-running` | none | `boolean` | Check if CraftOS-PC session is active |
| `craftos-pc.api.screenshot` | `windowId?` (default 0) | `{text, width, height, cursorX, cursorY, title}` | Read terminal screen as text |
| `craftos-pc.api.list-windows` | none | `{id: {title, width, height, isMonitor, computerID}}` | List all open windows/monitors |

### Input & Control

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.paste-text` | `text` (string) | `{success, pasted}` | Paste single-line text via CC paste event |
| `craftos-pc.api.type-text` | `text` (string) | `{success, typed}` | Type characters one by one (key + char events) |
| `craftos-pc.api.press-key` | `keyName` (string) | `{success, key, code}` | Press a named key (enter, backspace, tab, up, down, etc.) |
| `craftos-pc.api.send-ctrl-key` | `key` (string) | `{success, key}` | Send Ctrl+key combo (e.g., "t" for Ctrl+T terminate) |
| `craftos-pc.api.execute-line` | `luaCode` (string) | `{success, executed}` | Paste a Lua line + press Enter (single-line only) |
| `craftos-pc.api.queue-event` | `eventName`, `eventArgs?` (array) | `{success, event}` | Queue a raw CC event with typed args (string/number/boolean) |

### Named Keys for `press-key` / `send-ctrl-key`

`enter`, `return`, `backspace`, `tab`, `space`, `up`, `down`, `left`, `right`,
`home`, `end`, `delete`, `escape`, `f1`-`f12`, `ctrl`, `alt`, `shift`

### Usage Examples

```
-- Check if emulator is running
craftos-pc.api.is-running → true/false

-- Read what's on screen
craftos-pc.api.screenshot → {text: "CraftOS 1.9\n> ", width: 51, height: 19, ...}

-- Execute a Lua command
craftos-pc.api.execute-line("print('hello')") → runs print('hello') and presses Enter

-- Run a multi-line script (write file first, then execute)
1. Write Lua to: %APPDATA%\CraftOS-PC\computer\0\temp.lua
2. craftos-pc.api.execute-line("dofile('temp.lua')")

-- Send Ctrl+T to terminate a running program
craftos-pc.api.send-ctrl-key("t")

-- Queue a custom event
craftos-pc.api.queue-event("my_event", ["arg1", 42, true])
```

### Full AI Testing Workflow (Automated)

1. Deploy files: `powershell -File ".vscode/deploy-to-emulator.ps1"`
2. Start session: `craftos-pc.open`
3. Check status: `craftos-pc.api.is-running`
4. Run a script: `craftos-pc.api.execute-line("shell.run('blackjack')")`
5. Read output: `craftos-pc.api.screenshot`
6. Interact: `craftos-pc.api.press-key("enter")` / `craftos-pc.api.type-text("yes")`
7. Stop program: `craftos-pc.api.send-ctrl-key("t")`
8. Read logs: `Get-Content "$env:APPDATA\CraftOS-PC\computer\0\blackjack_error.log"`

## Key Limitations

- **Surface API**: The `surface` file is a binary/precompiled CC library. It works in-emulator since dofile loads it, but the AI cannot read or modify it.
- **Monitor size**: Mock returns fixed 71x38 (4x3 monitor at 0.5 scale). Real game may differ.
- **No real item NBT**: Mock inventories return simplified item data without NBT tags.
- **No real sounds**: Speaker mock logs sounds but doesn't play audio.
- **Rednet/modem**: Not mocked. If a game uses rednet, additional mocks would be needed.
