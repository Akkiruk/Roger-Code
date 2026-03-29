# Sound Browser Feature Plan

This document turns the strongest ideas from existing SFX tools into a concrete roadmap for `Roger-Code`.

## Goal

Build a ComputerCraft-friendly sound review system that:

1. helps audition sounds in meaningful game contexts
2. saves structured human decisions
3. generates recommendations for future sound choices
4. exposes final approved decisions to game configs

Existing tools inspired this roadmap:

- `SoundQ`: metadata editing, color states, waveform-style review workflow
- `Soundly`: UCS-style categories and library organization
- `Sononym`: similarity discovery and alternate-finding
- `Orion`: meaning/tone-based discovery
- `Soundminer`: pro metadata depth and search structure
- `Label Studio`: explicit review schemas

## Top 12 Features To Copy

### 1. Review Buckets

Source inspiration: `SoundQ`

Add and keep:

- `favorite`
- `maybe`
- `reject`
- `best`
- `good`
- `avoid`

Why:

- Fast triage is more important than full notes on first pass.

Status:

- Basic support already exists.

Next:

- add visual counts by bucket
- add “show only unreviewed”
- add “review next likely candidate”

### 2. Role-Centric Review

Source inspiration: `Label Studio`

Every sound should be reviewable against a specific role, not just globally.

Examples:

- `spin_start`
- `spin_tick`
- `spin_final`
- `bet_place_inside`
- `bet_place_outside`
- `timeout_warning`
- `ui_select`
- `ui_error`

Status:

- Basic role focus and verdicts already exist.

Next:

- add role-specific score prompts
- add “top reviewed for this role”
- add “show current assigned sound vs challenger”

### 3. Shared Decision Layer

Source inspiration: custom layer, because off-the-shelf tools do not solve this part

Canonical file:

- `Games/lib/sound_decisions.lua`

Purpose:

- final approved sound picks by role and by game
- rationale
- confidence
- fallback candidates

Status:

- Initial version already exists.

Next:

- let more games consume it
- let review data promote or replace defaults automatically with an approval step

### 4. Recommendation Engine

Source inspiration: `Orion` plus `Sononym`

Use:

- AI-style metadata
- review bucket
- role verdict
- role fit score
- confidence

Outputs:

- top candidates by role
- alternatives to current assignment
- “safe repeat-use” shortlist
- “dramatic but not reward-like” shortlist

Status:

- Basic recommendation module already exists.

Next:

- expose recommendations in browser UI
- add “why recommended” expanded view
- generate machine-readable exports

### 5. Report Export

Source inspiration: `Soundminer` / library audit workflows

Outputs:

- `sound_review_report.txt`
- role summaries
- top candidates
- gaps where nothing is reviewed well enough

Status:

- Basic report export already exists.

Next:

- include current assigned sound
- include rejected near-matches
- include unresolved roles

### 6. UCS-Like Category Layer

Source inspiration: `Soundly`, `UCS`

Introduce a structured tag vocabulary for sound families.

Suggested top-level groups:

- `ui`
- `casino`
- `currency`
- `mechanical`
- `industrial`
- `magical`
- `vault`
- `alert`
- `creature`
- `ambient`
- `reward`
- `failure`

Status:

- heuristic tags already approximate this

Next:

- define a canonical tag dictionary
- distinguish `auto_tags` from `approved_tags`
- map role expectations to canonical tags only

### 7. Similarity / Alternate Discovery

Source inspiration: `Sononym`

Goal:

- “I like this, show me nearby options.”

Implementation options:

1. filename / token similarity
2. namespace-family similarity
3. shared tag similarity
4. offline PC-side audio feature extraction later

Status:

- not implemented yet

Next:

- add lightweight similarity based on shared tags and tokens
- add “find alternatives” command in browser

### 8. Meaning / Tone Discovery

Source inspiration: `Orion`

Goal:

- ask in human terms, not only by exact tag

Examples:

- “dramatic machine start”
- “soft mechanical click”
- “warning but not hostile”

Implementation approach:

- start with a controlled phrase-to-tag mapping
- optionally add richer PC-side semantic preprocessing later

Status:

- not implemented yet

Next:

- add query presets that translate to filters
- add search aliases like `vibe:dramatic`, `feel:rewarding`

### 9. Context Audition Presets

Source inspiration: real workflow gap in current browser

Need:

- review sounds in context, not only one-shot playback

Presets to build first:

- `roulette_spin`
- `betting_loop`
- `timeout_warning`
- `small_win`
- `big_win`

Example:

- `roulette_spin` should play:
  - start cue
  - repeated tick cue
  - slowdown cue
  - final cue
  - result cue

Status:

- not implemented yet

Next:

- add an “audition mode” menu
- let current selected sound temporarily replace one role in the sequence

### 10. Repetition Fatigue Testing

Source inspiration: practical sound design need

Need:

- hear whether a sound becomes annoying after many repeats

Modes:

- repeat 5 times
- repeat 20 times
- repeat at fast cadence
- alternate between two candidate sounds

Status:

- not implemented yet

Next:

- add hotkeys for repeat tests
- save a human verdict like `repeat_safe = yes/no`

### 11. Richer Notes

Source inspiration: `SoundQ`/`Soundminer`

Need explicit notes for:

- why rejected
- why approved
- best pitch
- best volume
- good only for rare events
- too harsh for repetition
- too similar to another cue

Status:

- basic note support exists

Next:

- add structured note fields instead of only free text
- add “use only for rare events” and “spam safe” toggles

### 12. Batch Review Workflow

Source inspiration: `SoundQ`, `Soundminer`

Need:

- review top 20 likely candidates for a role without manual searching

Examples:

- “show next 10 `spin_start` candidates”
- “review only unreviewed `timeout_warning` candidates”
- “show favorites that are not yet assigned anywhere”

Status:

- partially enabled by filters, but not guided

Next:

- add review queues
- add next/previous candidate shortcuts
- add “mark and continue”

## Build Order

### Phase 1: Decision Workflow

Highest value, lowest complexity.

- expose recommendations in browser
- add review queue per role
- add unresolved role report
- extend `sound_decisions.lua` usage to more games

### Phase 2: Better Discovery

- add canonical tag dictionary
- add similarity based on tags/tokens
- add phrase-to-tag query presets
- add “find alternatives” workflow

### Phase 3: Better Audition

- add context audition sequences
- add repetition/fatigue testing
- add A/B comparison mode

### Phase 4: Deeper Offline Analysis

PC-side optional tooling:

- inspect actual sound file durations
- loudness heuristics
- envelope / attack style
- clustering
- richer semantic suggestions

## Recommended Immediate Next Tasks

1. Add a recommendation pane to `SoundBrowser`.
2. Add a role review queue: top candidates not yet marked `best/good/avoid`.
3. Add a “current assignment vs selected candidate” compare view.
4. Add first context preset: `roulette_spin`.
5. Move the next game after Roulette onto `sound_decisions.lua`.
