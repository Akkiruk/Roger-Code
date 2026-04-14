---
applyTo: 'Games/**'
---

# Dedicated Server Workflow

Do not use local PrismLauncher saves, CraftOS-PC files, or direct runtime log inspection for this repo.

- Source changes happen in this repository only.
- Distribution happens through GitHub pushes plus the deploy-index installer/update flow.
- Runtime evidence must come from the user, the dedicated server, or artifacts they explicitly provide.

Local emulator and world-deploy instructions are intentionally retired here to prevent accidental direct-file workflows.
- **Monitor size**: Mock returns fixed 71x38 (4x3 monitor at 0.5 scale). Real game may differ.
- **No real item NBT**: Mock inventories return simplified item data without NBT tags.
- **No real sounds**: Speaker mock logs sounds but doesn't play audio.
- **Rednet/modem**: Not mocked. If a game uses rednet, additional mocks would be needed.
