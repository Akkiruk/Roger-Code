---
applyTo: 'Games/**'
---

# Dedicated Server Workflow

Do not use CraftOS-PC local files or emulator-driven file deployment as the default workflow for this repo.

- Source changes happen in this repository only.
- Distribution happens through GitHub pushes plus the deploy-index installer/update flow.
- Runtime evidence must come from the user, the dedicated server, or artifacts they explicitly provide.
- If emulator work is ever needed again, treat it as an explicit opt-in task rather than a default validation path.
