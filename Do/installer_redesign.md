# Installer And Auto-Updater Redesign

## Goals

- Keep `main` as the live deployment branch.
- Remove `Games/manifest.json` as the canonical deployment source.
- Avoid relying on humans or AI agents to remember release bookkeeping.
- Let multiple people and agents work in the repo without shared release-file conflicts.
- Make installed programs answer the exact question: "what commit and package am I running?"
- Make installs self-contained so unrelated `Games/lib/` churn does not force cross-program updates.
- Preserve the current user-facing simplicity of `installer.lua` and background auto-updates.

## Non-Goals

- No manual release promotion flow.
- No handwritten per-program package file as canonical truth.
- No direct on-device source-tree crawling of GitHub contents.
- No requirement that runtime installs preserve a shared live `lib_version`.

## Current Problems

- `Games/manifest.json` is serving too many roles at once: discovery, file inventory, versioning, shared-lib inventory, and installer self-update.
- `Games/installer.lua` already tries to resolve a commit SHA and prefers commit-pinned raw URLs, while `Games/lib/updater.lua` still fetches floating `main`.
- Installed state is version/hash oriented instead of commit oriented.
- Shared `manifest.lib.version` couples unrelated programs together.
- Manifest generation reflects the working tree and depends on regeneration discipline.

## Final Direction

Replace the checked-in manifest with a generated deploy index produced from a clean checkout on every push to `main`.

That deploy index becomes the only source the installer and updater trust for package discovery and update decisions.

Development still uses the existing repo layout:

- `Games/<Program>/`
- `Utilities/`
- `Games/lib/`

Production installs stop using "shared library version X" as a deployment primitive. Instead, each installed program gets:

- its own program files
- its own traced `lib/` closure
- its own generated package spec
- commit-pinned provenance

## Architecture Overview

### 1. Clean Packaging Job

Run a GitHub Action on every push to `main` that:

1. Checks out the exact pushed commit in a clean environment.
2. Discovers installable programs automatically from the repo tree.
3. Computes each program's install-delivered file set.
4. Traces the exact `Games/lib/` dependency closure for each program.
5. Computes hashes for each file and for the package as a whole.
6. Publishes a generated deploy index and generated package specs keyed to that commit.

### 2. Generated Deploy Index

Publish generated metadata to a dedicated deployment location rather than committing it back into the source tree.

Preferred publication target:

- branch: `deploy-index`

Alternative:

- GitHub Pages or release artifacts if raw-branch publishing becomes awkward

The deploy location must expose stable raw URLs for:

- `latest.json`
- `programs/<program>.json`
- optional historical commit snapshots if desired later

### 3. Commit-Pinned Install And Update

Both installer and updater follow the same flow:

1. Fetch `latest.json`.
2. Read the current source commit for the requested program.
3. Fetch that program's generated package spec.
4. Download exact files from `raw.githubusercontent.com/<repo>/<commit>/...`.
5. Verify file hashes in staging.
6. Swap into place atomically.
7. Write an install record containing the exact package provenance.

### 4. Self-Contained Installs

Source remains shared for developer ergonomics.

Installed runtime does not depend on a separately versioned shared library catalog. Each install includes only the traced `lib/` files required for that program, stored under local `lib/`.

This keeps runtime stable even when another program changes unrelated shared modules.

## Discovery Rules

Discovery must stay mechanical so humans and agents do not need to maintain a central catalog.

### Package Roots

- Each `Games/<Name>/` folder containing at least one installable `.lua` file is a package root.
- Each standalone `Utilities/*.lua` file can remain an installable single-file utility.
- `Games/lib/` is not a package root.

### File Inclusion

Each package includes:

- all `.lua` source files under its root except ignored files
- non-Lua assets under its root except ignored files
- config files matched by preservation rules

Ignore patterns should start from the current manifest generator rules and move into the packaging job:

- `*.bak`
- `*.old`
- `*.log`
- `*.md`
- local debug files
- generated deployment metadata

### Config Preservation

Preserved config is inferred automatically using filename rules:

- `*_config.lua`
- `*_settings.lua`

Future extension:

- allow an optional in-source inline annotation if a program needs a rare preserve rule outside the filename convention

### User-Facing Metadata

Display metadata can still be inferred from source comments in the entrypoint, similar to the current generator:

- key
- display name
- description
- category

This metadata is informational. It is not trusted for file inventory or dependency resolution.

## Dependency Tracing

This is the biggest upgrade over the current `uses_lib` boolean.

### Required Output

For each program, generate the exact runtime closure of required `Games/lib/` modules.

Example:

- `lib.alert`
- `lib.currency`
- `lib.ui`
- `lib.monitor_scale`

becomes:

- `Games/lib/alert.lua`
- `Games/lib/currency.lua`
- `Games/lib/ui.lua`
- `Games/lib/monitor_scale.lua`

plus any nested `lib.*` dependencies those modules require.

### Tracing Rules

- Parse literal `require("...")` and `require('...')` calls.
- Resolve only repo-local modules that map to install-delivered files.
- Recurse through package-local modules and `Games/lib/` modules.
- Deduplicate and sort deterministically.

### Validation Rules

Packaging should fail loudly when a program depends on:

- a dynamic `require(...)` that cannot be resolved statically
- a missing module
- a cyclic resolution bug in the packager

This is important. Silent fallback to "ship the entire lib folder" would reintroduce the coupling we are trying to remove.

### Special Cases

- `lib/updater.lua` should remain part of the traced closure for programs that use background updates.
- If a bootstrap module needs to remain globally available, treat it as an explicit reserved runtime file, not a side effect of shared-lib deployment.
- Pre-bundled third-party single-file libraries like `basalt.lua` are fine as normal traced modules.

## Deploy Index Format

## `latest.json`

`latest.json` is the lightweight discovery document the installer and updater fetch first.

Example shape:

```json
{
  "schema_version": 1,
  "generated_at": "2026-03-28T12:34:56Z",
  "repo": {
    "owner": "Akkiruk",
    "name": "Roger-Code",
    "branch": "main"
  },
  "installer": {
    "commit": "8f2d3d6b5d8a4b5d5cb6a6b1b5f55c1111111111",
    "path": "Games/installer.lua",
    "sha256": "f6d06a7e3d3b6b1dbaf9d65d4dcbcf6e3f3d8e0e8d5c1f3ac2fa7d9d9a8d1111",
    "version": "2.0.0"
  },
  "programs": {
    "roulette": {
      "name": "Roulette",
      "category": "Games",
      "commit": "8f2d3d6b5d8a4b5d5cb6a6b1b5f55c1111111111",
      "package_hash": "9a8f6e4d1b5c7a9e0d2f4a6b8c1d3e5f11111111111111111111111111111111",
      "spec_url": "https://raw.githubusercontent.com/Akkiruk/Roger-Code/deploy-index/programs/roulette.json"
    },
    "vaultgear": {
      "name": "VaultGear",
      "category": "Utilities",
      "commit": "8f2d3d6b5d8a4b5d5cb6a6b1b5f55c1111111111",
      "package_hash": "3d0a4d6c8b2e1f9a7c5b3e1d8f6a4c2b11111111111111111111111111111111",
      "spec_url": "https://raw.githubusercontent.com/Akkiruk/Roger-Code/deploy-index/programs/vaultgear.json"
    }
  }
}
```

### Notes

- `latest.json` should stay small.
- It should not list every install file inline.
- Installer and updater only need enough data to discover packages and decide whether the local install record still matches.

## Per-Program Spec Format

Each program gets one generated spec file.

Example `programs/roulette.json`:

```json
{
  "schema_version": 1,
  "program": {
    "key": "roulette",
    "name": "Roulette",
    "category": "Games",
    "description": "European Roulette with a single-screen felt UI and multi-bet support.",
    "source_root": "Games/Roulette",
    "entrypoint": "startup.lua"
  },
  "build": {
    "commit": "8f2d3d6b5d8a4b5d5cb6a6b1b5f55c1111111111",
    "generated_at": "2026-03-28T12:34:56Z",
    "package_hash": "9a8f6e4d1b5c7a9e0d2f4a6b8c1d3e5f11111111111111111111111111111111"
  },
  "install": {
    "preserve": [
      "roulette_config.lua"
    ],
    "files": [
      {
        "repo_path": "Games/Roulette/Roulette.lua",
        "install_path": "Roulette.lua",
        "sha256": "..."
      },
      {
        "repo_path": "Games/Roulette/startup.lua",
        "install_path": "startup.lua",
        "sha256": "..."
      },
      {
        "repo_path": "Games/Roulette/roulette_config.lua",
        "install_path": "roulette_config.lua",
        "sha256": "...",
        "preserve_existing": true
      },
      {
        "repo_path": "Games/lib/alert.lua",
        "install_path": "lib/alert.lua",
        "sha256": "..."
      },
      {
        "repo_path": "Games/lib/updater.lua",
        "install_path": "lib/updater.lua",
        "sha256": "..."
      }
    ]
  },
  "runtime": {
    "requires_updater": true,
    "lib_modules": [
      "lib.alert",
      "lib.currency",
      "lib.game_setup",
      "lib.idle_screen",
      "lib.monitor_scale",
      "lib.safe_runner",
      "lib.sound",
      "lib.ui",
      "lib.updater"
    ]
  }
}
```

### Notes

- `files` is the authoritative install plan.
- `repo_path` plus `build.commit` defines the exact download URL.
- `install_path` allows source layout and runtime layout to differ safely.
- `preserve_existing` replaces the old config overwrite rules cleanly.

## Installed State Format

Replace the current version-centric `.installed_program` with commit-centric provenance.

Example:

```lua
{
  schema_version = 1,
  program = "roulette",
  name = "Roulette",
  source_commit = "8f2d3d6b5d8a4b5d5cb6a6b1b5f55c1111111111",
  package_hash = "9a8f6e4d1b5c7a9e0d2f4a6b8c1d3e5f11111111111111111111111111111111",
  spec_url = "https://raw.githubusercontent.com/Akkiruk/Roger-Code/deploy-index/programs/roulette.json",
  installed_at = 1774719296000,
  updated_at = 1774719296000
}
```

Optional debugging fields:

- `installer_version`
- `last_update_status`
- `last_update_error`
- `previous_commit`

## Update Decision Rules

Updater logic becomes simple and deterministic:

1. Load `.installed_program`.
2. Fetch `latest.json`.
3. Find the current program entry.
4. Compare:
   - `source_commit`
   - `package_hash`
5. If both match, report up to date.
6. If either differs, fetch the program spec and apply the staged update.

`version` strings can remain as display-only metadata if desired, but they should not be the primary correctness check.

## Atomic Install And Update Flow

Every install and update should use staging.

### Flow

1. Create a staging directory, for example `.install_staging/<timestamp>/`.
2. Download every file into staging.
3. Verify each file hash against the package spec.
4. If all files pass, copy staged files into final locations.
5. Preserve existing config files when marked.
6. Write `.installed_program`.
7. Remove staging.

### Failure Rules

- If any download fails, do not touch the current install.
- If any hash check fails, abort and keep the current install.
- If config preservation conflicts with a directory/file mismatch, abort and log.
- Only write the new install record after the swap is successful.

## Installer Responsibilities

`Games/installer.lua` should own:

- fetching `latest.json`
- showing the install menu
- self-updating itself from the generated installer metadata
- first-time install
- manual reinstall
- forced update of the currently installed program

The installer should stop knowing about:

- repo-wide manifest structure
- global shared-lib version
- auto-version bump logic

## Updater Responsibilities

`Games/lib/updater.lua` should own:

- background polling
- commit/package comparison
- staged updates
- log output
- reboot after successful update when requested by the caller

The updater should stop knowing about:

- floating `main` file downloads
- global shared-lib version checks
- manifest-specific program schemas

## Backward Compatibility

The rewrite should read the current `.installed_program` format and map it into the new flow where possible.

Fallback strategy:

- if only `program` exists, updater can still fetch `latest.json` and compare against a missing commit as "update needed"
- if only old `version` fields exist, do not trust them beyond selecting the installed program key

`installer.lua` can silently migrate the install record during the first successful install or update under the new system.

## Migration Plan

### Phase 1: Add Packaging Generator

- Add a new packaging script, separate from `.vscode/generate-manifest.ps1`.
- Keep the current manifest flow alive temporarily.
- Generate:
  - `latest.json`
  - `programs/<program>.json`
- Implement exact dependency tracing and hash generation.

Deliverable:

- reproducible deploy metadata from a clean checkout

### Phase 2: Teach Installer The New Index

- Update `Games/installer.lua` to consume `latest.json` and per-program specs.
- Preserve current UI behavior as much as practical.
- Add new `.installed_program` schema.
- Keep a temporary fallback path to the old manifest for emergency rollback only if needed.

Deliverable:

- first-time install works without relying on `Games/manifest.json`

### Phase 3: Rewrite Updater

- Update `Games/lib/updater.lua` to consume the generated deploy index.
- Switch to commit/package comparisons.
- Add atomic staging and hash verification.
- Remove `lib_version` logic.

Deliverable:

- live tables update from commit-pinned package specs instead of floating manifest/main

### Phase 4: Remove Manifest Dependency

- Remove runtime dependence on `Games/manifest.json`.
- Remove `manifest.lib.version` logic.
- Retire the old manifest generator from the deployment path.
- Optionally keep a lightweight source-only manifest if some local tool still benefits from it, but it must not be trusted by installer or updater.

Deliverable:

- manifest no longer matters for production installs

### Phase 5: Cleanup

- remove dead compatibility code
- simplify docs and scripts
- rename the packaging script to the canonical deployment generator

## Implementation Notes

### Entry Point Detection

Keep entrypoint detection deterministic and simple:

- prefer `startup.lua`
- else prefer `<dirname>.lua` or known explicit entrypoint
- else first top-level `.lua`

This should be a build-time rule, not a user-maintained declaration.

### Hashing

- Use SHA-256 for file hashes and package hashes.
- Package hash should be derived from the ordered list of install records, not just concatenated bytes from arbitrary file order.
- The package hash must change if any install path, preserve flag, or file hash changes.

### Determinism

All generated output must be stable for the same commit:

- sorted program keys
- sorted file lists
- stable JSON formatting
- stable module resolution order

### Reserved Runtime Files

Installer and updater should explicitly reserve a few local files that are not part of package payloads:

- `.installed_program`
- `installer_error.log`
- `updater.log`
- `.update_lock`
- `.vhcc_unlock`

Do not accidentally delete or overwrite these during package swaps.

## Recommended First Implementation Target

Start with `Roulette` as the first migrated package.

Why:

- already actively used
- small enough to reason about
- uses the shared updater path
- depends on several `lib.*` modules, which exercises dependency tracing properly

Then validate against:

- `VaultGear` because of nested `lib.vaultgear.*`
- `PhoneOS` because of nested package-local modules and config preservation

## Hard Constraints For The Rewrite

- No manual "regenerate manifest" step for deployability.
- No global shared `lib` runtime version as update truth.
- No update decisions based primarily on semver bumping.
- No floating-branch file downloads during actual install/update execution.
- No partial live-file overwrite before payload verification completes.

## Open Questions

- Whether the deploy metadata should live on a dedicated branch or a GitHub Pages path.
- Whether installer self-update should stay tied to every push or use a separate compatibility gate.
- Whether package specs should expose display `version` fields at all, or only commit plus package hash.
- Whether the updater should keep automatic reboot-on-update as the default for every program.
