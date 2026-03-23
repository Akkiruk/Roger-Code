---
applyTo: 'Games/**'
---

# CraftOS-PC VS Code Extension — AI Terminal API

The CraftOS-PC extension (`jackmacwindows.craftos-pc` v1.2.3) exposes 10 VS Code commands
that let Copilot interact directly with running CraftOS-PC terminals.

All commands are invoked via `run_vscode_command` with `commandId` and optional `args`.

---

## Lifecycle

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.open` | none | — | Launch a new CraftOS-PC instance (computer 0). |
| `craftos-pc.close` | none | — | Close the running CraftOS-PC process. |
| `craftos-pc.api.is-running` | none | `true` / `false` | Check if CraftOS-PC is currently running. |
| `craftos-pc.api.list-windows` | none | Array of `{id, width, height, title}` | List all open terminal/monitor windows. |

---

## Screen Reading

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.screenshot` | none | `{text, width, height, cursorX, cursorY, title}` | Read the terminal as plain text. Lines separated by `\n`. |
| `craftos-pc.api.screenshot-colors` | none | `{text, colorMap, colorSummary, width, height, cursorX, cursorY, title}` | Read text + per-cell color map. `colorMap` uses CC hex color codes (0-9a-f) per character. `colorSummary` gives total pixel counts per named CC color. |

### Color Map Reference
Each character in `colorMap` represents one cell's **background color**:

| Char | CC Color | Char | CC Color |
|------|----------|------|----------|
| `0` | white | `8` | lightGray |
| `1` | orange | `9` | cyan |
| `2` | magenta | `a` | purple |
| `3` | lightBlue | `b` | blue |
| `4` | yellow | `c` | brown |
| `5` | lime | `d` | green |
| `6` | pink | `e` | red |
| `7` | gray | `f` | black |

---

## Input — Text & Keys

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.type-text` | `["text"]` | `{success, typed}` | Type text character-by-character (handles shift for uppercase/symbols). Use for typing commands or single characters. |
| `craftos-pc.api.paste-text` | `["text"]` | `{success, pasted}` | Paste text via the paste event (first line only). |
| `craftos-pc.api.execute-line` | `["code"]` | `{success, executed}` | Paste text and press Enter. Equivalent to typing a command in the shell. |

### Typing vs Execute
- **`type-text`** — For individual characters or partial input. Does NOT press Enter.
- **`execute-line`** — For running shell commands. Pastes + presses Enter automatically.
- **`paste-text`** — For pasting content into an editor or input field.

---

## Input — Keys & Shortcuts

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.press-key` | `["keyName"]` | `{success, key, code}` | Press and release a named key. |
| `craftos-pc.api.send-ctrl-key` | `["keyName"]` | `{success}` | Send Ctrl+key combination (e.g., Ctrl+T to terminate). |

### Supported Key Names
- **Navigation:** `up`, `down`, `left`, `right`, `home`, `end`, `pageUp`, `pageDown`
- **Editing:** `enter`, `backspace`, `delete`, `tab`, `space`
- **Function:** `f1` through `f12`
- **Modifiers:** `leftShift`, `rightShift`, `leftCtrl`, `rightCtrl`, `leftAlt`, `rightAlt`
- **Note:** For letter/number keys, use `type-text` instead. `press-key` is for non-printable keys.

### Common Ctrl Combos
- `craftos-pc.api.send-ctrl-key` with `["t"]` — Terminate running program
- `craftos-pc.api.send-ctrl-key` with `["r"]` — Reboot computer
- `craftos-pc.api.send-ctrl-key` with `["s"]` — Shutdown computer

---

## Event Simulation

| Command | Args | Returns | Description |
|---------|------|---------|-------------|
| `craftos-pc.api.queue-event` | `["eventName", arg1, arg2, ...]` | `{success}` | Queue a ComputerCraft event. Args can be strings, numbers, or booleans. |

### Example Events
- Monitor touch: `["monitor_touch", "monitor_0", 5, 10]`
- Redstone: `["redstone"]`
- Timer: `["timer", 1]`
- Key: `["key", 28]` (28 = enter keycode)
- Custom: `["my_custom_event", "data"]`

---

## Typical Workflow

```
1. craftos-pc.open                        — Start emulator
2. craftos-pc.api.is-running              — Verify it's up
3. craftos-pc.api.screenshot              — See what's on screen
4. craftos-pc.api.execute-line ["ls"]     — Run a command
5. craftos-pc.api.screenshot              — Read the output
6. craftos-pc.api.press-key ["enter"]     — Press Enter
7. craftos-pc.api.screenshot-colors       — Read screen with color data
8. craftos-pc.api.send-ctrl-key ["t"]     — Kill running program
9. craftos-pc.close                       — Shut down emulator
```

## Important Notes
- The emulator must be running (`is-running` = true) before using input/screen commands.
- `execute-line` only works for single-line commands (no multi-line paste).
- `press-key` does NOT work for printable characters like letters — use `type-text` for those.
- Screen reads return the terminal buffer state; running programs may not have flushed output yet. Add a small delay if needed.
- Computer data lives at `%APPDATA%\CraftOS-PC\computer\<id>\`. Deploy files there before running.
