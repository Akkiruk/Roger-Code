# SALTGATE: the expansion (King Tide)

Step 0, the core interfaces, is built and runs behind a flag. This file is the plan and the brief for the five streams.
Read sections 2 and 3 before you write a line.

## 1. The budget

| What | Value |
|---|---|
| Disk per computer on the server | **25 MB** (confirmed by the owner). Local test worlds use 1 MB: raise `computer_space_limit` there. |
| Lua threads for every computer on the server | **1** (`computer_threads = 1`): a slow frame here is a slow frame for every computer. |
| Lua memory | no per-computer limit, but every computer shares the server's heap. CC has no `collectgarbage`, so memory is measured under desktop Lua (`tools/saltgate/heap.lua`). |
| Without yielding | aborted after about 7 s. Long work yields; streamed work runs in coroutines under a time budget. |
| Soft limits (checked by `node tools/saltgate/budget.mjs`) | disk ≤ 8 MB, emulator v2 frame p90 ≤ 16 ms on 51x19 (to tighten), heap ≤ 6 MB after a collection |
| Install | everything ships through the normal installer inside `Games/Saltgate/`: code in `sg/`, content in `content/` (a few dozen packed files, not thousands) |

Step 0 measured, emulator, 51x19, testbed island, autopilot:

| Measure | Value |
|---|---|
| v2 frame | mean 7.6–8.8 ms, p90 12 ms |
| Render | 6 ms, of which Pine3D triangles 2.9, blit 1.2, minimap 0.6–0.8, scene 0.9 |
| Physics for 5 cars | 0.9 ms |
| Heap (desktop) | 3.5 MB live, 8.5 MB peak with garbage, all 16 chunks loaded |

Today's live game: 3–6 ms (it varies with machine load).

## 2. What the city must be (owner's requirements, for every stream)

- **Not a grid.** Roads are curves: polylines and splines with real bends, diagonals, roundabouts, irregular blocks, cul-de-sacs, alleys, a coast road along an organic shoreline, and hairpins up the hill. A planned grid only where it fits (downtown).
- **Real height that matters:**
  - hills you crest and get air off, ramps;
  - bridges and overpasses where roads cross at different heights, tunnels;
  - the funicular slope, cliffs down to the water, multi-level docks and car parks.
  - Cars and people follow the ground, pitch and roll, jump and fall.
- **Varied districts:** organic coastlines, a park with winding paths, an old town of crooked streets, an industrial area with rail lines, a downtown grid.
- **Every system works with curves and height:** the chunk format, collision, AI routing (a road graph, never grid cells), the minimap and the map. The step 0 testbed (`sg/core/testbed.lua`) has all of these and passes the gate.

## 3. Step 0: the core, and how to use it

Turn it on: create `saltgate_v2.flag` on the computer (or put `engine = "v2"` in `saltgate_settings.lua`). Without the flag the live game runs exactly as before. v2 saves to `saltgate_save2.dat`; it reads today's `saltgate_save.dat` once and migrates it, and never writes it.

**Files: `Games/Saltgate/sg/core/*`, owned by step 0. Streams call these; they never edit them.** Need a change? Ask the integrator (step 0's owner).

### Events: `core/events.lua`

```lua
local id = ctx.bus:on(name, function(data) end, "a_world")   -- owner tag, for offOwner
ctx.bus:emit(name, data)       ctx.bus:off(id)       ctx.bus:offOwner("a_world")
```

Every name must be in `events.NAMES`. An unknown name is an error. To add one, ask the integrator.

| Event | Data |
|---|---|
| `vehicle_enter` | vehicle, stolen |
| `vehicle_exit` | vehicle, sunk (the car flooded under you) |
| `vehicle_sunk` | vehicle (a land vehicle that drove into deep water stalls, floods after 1.2 s and is a wreck; the driver swims out) |
| `district_enter` | district, previous |
| `player_hurt` | amount, by |
| `player_down` | kind (`nabbed` or `ko`) |
| `respawn` | place |
| `money` | amount, reason, total |
| `pickup` | kind, id, value |
| `crime` | kind, level |
| `heat_changed` | level, previous |
| `mission_start` | id |
| `mission_end` | id, result (`pass` or `fail`), reason |
| `checkpoint` | id, name |
| `choice` | id, key, pick |
| `achievement` | id |
| `jump` | id, distance, landed |
| `time_of_day` | hour, phase |
| `weather` | kind, previous |
| `chunk_loaded` | cx, cz, lod |
| `chunk_unloaded` | cx, cz |
| `interior_enter` | id |
| `interior_exit` | id |
| `screen_push` | name |
| `screen_pop` | name |
| `save` | data: add your section's fields here |
| `load` | data |
| `quality` | level 0–3, previous |

### Entities: `core/entity.lua`

```lua
local e = ctx.world:add({ kind = "car", x =, y =, z =, h =, radius =, health =, tags = { traffic = true } })
ctx.world:move(e, x, z)      -- always move through this
ctx.world:remove(e)
ctx.world:each("cop")        -- a fresh list
ctx.world:near(x, z, r [, tag])   -- nearest first
ctx.world:system({ name = "c_traffic", order = 20, rate = nil or Hz, update = function(world, dt) end })
-- e.lod is "near" (< 60), "mid" (< 120) or "far": update far things at a low rate or not at all
```

### Chunks: `core/chunk.lua` (format SGC2, one chunk per line in `.sgc` files)

- Size 88 units; the height grid is 17x17. `TERRAIN = -9999` means "the ground here".
- Sections (each a list of records):

| Section | Record |
|---|---|
| ground | `{ kind, y, pts }` |
| water | `{ level, pts }` |
| buildings | `{ x, z, w, d, angle, base, h, style, solid }` |
| props | `{ kind, x, z, h, y }` |
| nodes | `{ id, x, y, z }` |
| roads | `{ id, a, b, width, lanes, speed, kind, pts3 }` |
| floors | `{ kind, y, pts }` |
| ribbons | `{ kind, width, pts3 }` |
| doors | `{ x, z, y, interior }` |
| spawns | `{ kind, x, z, h }` |
| landmarks | `{ model, x, z, h, y }` |

- `pts` is x,z pairs; `pts3` is x,y,z triples.
- `roads` are road-graph edges. `lanes = 1` means one way, a to b. Kinds: `road`, `avenue`, `alley`, `path`, `highway`, `rail`.
- `ribbons` kinds: `bridge`, `overpass`, `ramp`, `tunnel`, `pier`, `stairs`.
- A thing belongs to the chunk its centre is in. It may reach at most 44 units outside it.

```lua
chunk.pack(c) -> line          chunk.unpack(line) -> c | nil, err        chunk.packMany / unpackMany
chunk.validate(c) -> true | false, err
chunk.terrainY(c, x, z)        chunk.groundAt(c, x, z, y) -> height, kind
chunk.surface(c, x, z)         chunk.collide(c, x, z, r, y)
```

`core/geom.lua` has the shape helpers:

```lua
curve(ctrl, step)   -- Catmull-Rom to a 3D polyline
circle(cx, y, cz, r, n, a0, a1)
polylineNearest   polylineAt   polylineLength   inPolygon   inBox   pushOutOfBox   pushOutOfPolygon
```

### Streaming: `core/stream.lua`

```lua
ctx.stream:groundAt(x, z, y) -> height, kind   -- y matters: on the bridge or under it
ctx.stream:surface(x, z)
ctx.stream:waterAt(x, z) -> level | nil
ctx.stream:collide(x, z, r, y)                  -- unloaded world = wall
ctx.stream:chunkAt(x, z)
ctx.stream:loaded()
ctx.stream.roads                               -- the road graph of what is loaded
-- ctx.stream.full and ctx.stream.low are the detail rings: core lowers them when the budget's quality drops
```

### Road graph: `core/roadgraph.lua`

```lua
roads:nearest(x, z, maxDist [, kinds]) -> edge, s, d, qx, qz, y, dirX, dirZ
roads:pointAt(edge, s, side) -> x, y, z, dx, dz       -- side: a lane offset
roads:exits(nodeId, fromEdge)
roads:path(fromId, toId [, kinds]) -> nodeIds, edges   -- A*
roads:node(id)    roads:edge(id)
```

`core/follow.lua` is a simple reference driver; stream C replaces it with the real AI.

### Moving over the ground: `core/motion.lua`, `core/drive.lua`

```lua
motion.move(e, ctx.stream, nx, nz, dt, { radius, speed, length, width, swims, tilt })
  -> { hit, nx, nz, landed, impact, airborne, water, surface }
-- keeps e.y, e.vy, e.airborne, e.pitch, e.roll; steep rises are walls; leaving a crest at speed flies
drive.step(car, input, dt, ctx.stream [, { tilt = bool }])
  -> { impact, airborne, landed, landImpact, water, surface }
```

### Content: `core/content.lua` (files in `Games/Saltgate/content/`)

```lua
ctx.content:text(path)
ctx.content:data(path)      -- "return {...}" with no globals at all
ctx.content:chunks(path)    -- an .sgc file
ctx.content:script(path)    -- a mission
ctx.content:list(dir)
```

Paths may not climb out of `content/`.

### Missions: `core/script.lua`

A mission file returns `function(api) ... end`, made of `api.step(name, fn)` checkpoints.

```lua
api.say(who, text)      api.choose(prompt, options) -> index
api.objective(text, target)
api.waitUntil(fn, timeout) -> ok      api.wait(seconds)
api.goTo(place, { car, radius, text, timeout })
api.spawn(kind, at, opts)      api.cutscene(shots)
api.setHeat(n)      api.reward(n)
api.flag(name [, v])      api.var(name [, v])      api.fail(reason)      api.time()

script.new(id, fn, hooks [, savedState])
runner:update(dt) -> "running" | "pass" | "fail"
runner:saveState()
```

A save made in the middle of a mission resumes at its step, with its flags.

### Vehicles: `core/vehicles.lua`

```lua
vehicles.define({ id, class = "car"|"bike"|"truck"|"trailer"|"boat"|"heli", name, top, accel, brake, turn, grip,
  health, length, width, height?, mass?, seats?, value?, paint?, tune?, damage?, police?, special?, traffic?,
  weight?, model? })
vehicles.get(id)    vehicles.list(class)    vehicles.traffic()    vehicles.stage(def, healthFraction)
vehicles.physics(class, fn(entity, input, dt, world) -> impact)    vehicles.physicsFor(def)
```

Today's cars are already defined as class `car` (`registerLegacy`).

### Screens and HUD: `core/ui.lua`

```lua
ctx.ui.screen({ name, draw(ctx, dt), modal?, update?, input? })
ctx.ui.push(name, args)    ctx.ui.pop()    ctx.ui.top()    ctx.ui.modal()
ctx.ui.widget({ name, slot, priority, draw(ctx, term), visible?(ctx) })
-- slots: top-left, top-right, objective, centre, status, hints, bottom-right
```

### Saves: `core/save.lua` (version 2)

- Sections: `player`, `story`, `world`, `garage`, `activities`, `progress`, `settings`, plus your own.
- `save.section(name, { version, owner, blank(), migrate(old, fromVersion) })`
- Write your fields in the `save` event's `data`; read them in `load`.
- Version 1 saves migrate automatically.
- A save from a newer version is refused, never overwritten.

### Plugins: `core/plugins.lua`

Each stream adds files `sg/plugins/<letter>_<name>.lua` (for example `a_world.lua`, `c_police.lua`). Each returns:

```lua
{ name = "<file name>", order = n, needs = { ... }, init(ctx), input(ctx, inp)?, update(ctx, dt)?, draw(ctx)? }
```

- They are found by themselves; nobody edits a list.
- A plugin that fails to load is logged and left out.
- Every frame the core calls, in this order:
  1. each plugin's `input(ctx, inp)`;
  2. the top screen's `input(ctx, inp, dt)` and `update(ctx, dt)`, if a plugin registered that screen;
  3. the world (cars, `car.brain`, the world's systems, streaming);
  4. each plugin's `update(ctx, dt)`, while no modal screen is up;
  5. the top screen's `draw`, then each plugin's `draw(ctx)`.
- `ctx` holds: `bus`, `world`, `stream`, `roads`, `content`, `ui`, `save`, `vehicles`, `budget`, `player`, `cars`, `view`, `log`, and:

| Field | What it is |
|---|---|
| `ctx.input` | the keys (`sg/input.lua`). `ctx.input:bind(action, { keys.x, ... })` at init adds your own action; read it with `down(action)` and `pressedAction(action)`. |
| `ctx.objective` | where the player should go: a table `{ text, x, z, kind, colour }` or a function returning one. The core draws the beacon, the minimap dot (pinned to the edge) and the arrow, distance and text at the top. Without it, the core falls back to `ctx.story.target()`. |
| `ctx.sfx(name)` | a sound effect from `sg/sound.lua`'s cues. Capped at 2 notes a tick while the soundtrack plays. |
| `ctx.music.cue(name)`, `ctx.music.setDistrict(d)` | the soundtrack (no-ops without one). The core sends `driving`/`free_roam` on getting in and out, the district when it changes, and calls `init`/`update` itself. |
| `ctx.clock.hour` | the time of day, 0–24, a game hour a real minute, saved in `save.world.time`. The core emits `time_of_day` once a game minute (hour, phase dawn/day/dusk/night). Stream A's sky reads it. |
| `ctx.bump(a, b)` | if set, replaces car-against-car contact. |
| `ctx.coreSendsVehicleEvents` | `true`: `vehicle_enter { vehicle, stolen }` and `vehicle_exit { vehicle }` come from the core. |
| `car.brain(ctx, car, dt)` | a car's own driver. It returns the input (`throttle`, `steer`, `handbrake`) for the physics. Used before `car.follow`. |
| `ctx.setWorld(def)` | puts the game in a world: `{ id, source(cx, cz), spawn = { x, z, h }, view?, build?, drop?, chunks?, drawMap?, at? }`. It clears the streamer, loads round the start (or the saved place if the save is from the same world id), and moves you and your car there. Stream A's plugin calls it with the city. Without `content/world` the core uses the testbed. |
| `ctx.worldDef` | the world in use. |
| `ctx.setPalette(pal)` | colours by name (`{ purple = 0x5A4785, ... }`). Sets the screen and the 3D frame's window (a window pushes its own palette on every blit), then re-tunes the pixel mixer. Use it for every palette change. |
| `ctx.clock.owner` | a plugin that runs the day (A's sky) sets this and keeps `ctx.clock.hour` up to date; the core then neither moves the clock nor sends `time_of_day`. |
| `ctx.noTitle` | true on benches (or with `saltgate_notitle.flag`): no title screen. |
| `ctx.routesScreenInput` | true: the core calls plugin and screen input (no need to read `os.pullEventRaw` yourself). |
| `ctx.player.outfit` | `{ shirt, legs }` colour names for Wren; the views draw them. |
| Paint | never the sky's slots (`purple`, `magenta`, `pink`, `lightBlue`): they change with the hour. |

### Budget: `core/budget.lua`

```lua
ctx.budget:time(name, fn)
ctx.budget.quality       -- 0–3; listen to the "quality" event and do less at higher levels
```

F3 shows the timings in game.

### Drawing: `core/view.lua`, `core/chunkmodel.lua`, `core/mapview.lua`

These are the reference renderer: terrain mesh, roads along curves, decks and pillars, rotated buildings, a heading-up minimap with contour lines, and the map. **Stream A takes these over**, starting by forking them into `sg/world/`; core keeps the interface (`builder()`, `draw(ctx, dt)`, `drawMap(ctx, chunks)`).

**The drawing hooks** (one API for every stream; stream A's renderer keeps them):

```lua
ctx.view:layer(name, function(ctx, view, list, cam) end)
  -- add 3D objects to the scene each frame: view:place(list, view:variant(key, heading, makeModel), x, y, z)
ctx.view:minimapLayer(name, function(ctx, view, dot) end)
  -- dot(x, z, colour [, pinToEdge])
ctx.view:effectLayer(name, function(ctx, view, rows, cam) end)
  -- pixels after the 3D and before the blit (particles, tracers, rain, flashes);
  -- rows[y][x] = colour; view.r.frame:map3dTo2d(x, y, z) -> px, py, inFront
ctx.view.override = { x, y, z, yaw, pitch }
  -- take the camera (cutscenes); the minimap hides while it is set
vehicles.model(idOrClass, function(car) return model end)
  -- how a vehicle class or id looks; car.damageStage picks a dented model
vehicles.physics(class, fn(car, input, dt, world, opts))
  -- a class's physics; cars default to core/drive.lua
```

Please move to these instead of wrapping `view.scene`, `view.minimap`, `view.camera`, `frame.drawBuffer`, `follow.input`, `drive.step`, `vehicle.bump`, `models.car` or `sg.input.new`. The wrappers still work for now.

**Ground rules that changed after step 0:**
- A road is a surface itself: on a road, the ground is the road's height.
- The player swims (slowly, at the surface) in deep water.
- The camera never goes under water.

### Tests and tools

| Command | What it does |
|---|---|
| `lua Tests/run.lua` | Desktop Lua 5.1, every test; or `lua -e "TEST_FILES={'saltgate_core_test'}" Tests/run.lua` |
| `node tools/casinotest/unit.mjs saltgate` | craftos-agent: every Saltgate test file in the emulator |
| `node tools/saltgate/emu.mjs <out> v2-bench v2-overpass v2-hill v2-jump v2-map` | v2 frame times and the gate screenshots |
| `node tools/saltgate/budget.mjs` | disk, frame and memory against the limits |
| `node tools/saltgate/emu.mjs <out> bench story chase` | the live game still works |

Point the tools at a worktree with `ROGER_DIR=<checkout>`.

Light use: one emulator process at a time, other agents share the machine.

## 4. The five streams

**Every stream:**
- works in its own worktree from origin/main;
- adds only files it owns (below) plus its own `sg/plugins/<letter>_*.lua` and `Tests/saltgate_<letter>_*_test.lua`;
- writes Lua 5.1: no `goto`, locals, forward declarations;
- passes its tests, the core tests and the live game's tests before asking for integration;
- leaves the pushing to the integrator.

**Don't touch, for every stream:**
- `saltgate.lua`, `startup.lua` and `sg/core/*` (ask the integrator);
- `music/` (the music agent's);
- the live game's `sg/*.lua` files outside `sg/core` (they keep running until v2 replaces them);
- another stream's folders.

### A. World and look

- **Scope:**
  - the real city in packed chunks, from a build tool:
    - 3 islands and 10 districts;
    - curved roads, roundabouts, hairpins, an old town, rail lines;
    - bridges, overpasses, tunnels, cliffs, the funicular, multi-level docks and car parks;
  - landmarks;
  - interiors behind doors;
  - day/night palette keyframes and night lighting;
  - weather;
  - particles (tyre smoke, sparks, splashes, rain, fire);
  - the skyline beyond the streamed rings;
  - LOD and the renderer's speed, toward 5 ms;
  - the minimap and the map.
- **Owns:**
  - `sg/world/*` (a fork of `core/view.lua`, `chunkmodel.lua`, `mapview.lua` to start);
  - `content/world/*.sgc`, `content/interiors/*`;
  - `sg/plugins/a_*.lua`;
  - craftos-agent `tools/saltgate/citybuild.mjs`, which writes the `.sgc` files.
- **Uses:** the chunk format, `geom.curve`, stream, content, events `time_of_day`, `weather`, `chunk_loaded`, `interior_enter`/`interior_exit`, `quality`.
- **Gate:**
  - every chunk passes `chunk.validate`;
  - every road node is reachable on the graph (the testbed joins stragglers with `connectAll`);
  - no road steeper than 1 in 5 (`testbed.MAX_GRADE`: ends meet their junctions' heights, then the grade is eased);
  - the ground under every road is flattened to it within a whole height cell, and blended beyond;
  - switchbacks at least 20 units apart;
  - no building stands on a road;
  - emulator screenshots, top-down and in game, for every district at dawn, noon, dusk and night, showing curves and height;
  - `budget.mjs` passes.
- **Size:** code ~130 KB, content ~1.7 MB.

### B. Vehicles and combat

- **Scope:**
  - vehicle definitions for 12+ cars, bikes (lean), trucks and trailers, boats (buoyancy on `waterAt`), and the police helicopter's model;
  - physics per class through `vehicles.physics`;
  - visible damage stages;
  - garage and customization data (paint, tune tiers);
  - **combat: cartoony guns** (pistols, shotguns, an SMG and the like, plus melee):
    - bright tracer pixels and puffs;
    - **no blood and no gore**;
    - anyone shot is **knocked down** (they fall, see stars, get back up or are out), never killed on screen;
  - ammo pickups;
  - aiming fitted to the keyboard (lock on to the nearest target in front; a key to cycle targets);
  - cover behind cars.
- **Owns:** `sg/vehicles/*`, `sg/combat/*`, `content/vehicles/*`, `sg/plugins/b_*.lua`.
- **Uses:** vehicles, entities, `drive` and `motion`, events `vehicle_enter`, `crime`, `player_hurt`, `player_down`.
- **Gate:**
  - every vehicle corners without wall hits (as the live game's test does);
  - boats stay on water, bikes don't flip at speed;
  - damage stages;
  - knockdown rules (no one is ever removed as dead);
  - a no-NaN soak per class;
  - `budget.mjs`.
- **Size:** code ~110 KB, data ~60 KB.

### C. AI, the Harbor Patrol and people

- **Scope:**
  - traffic on the road graph (lanes, junctions, one-way edges, overtaking);
  - pedestrians on paths with time-of-day routines;
  - gangs per district who fight back with B's cartoony guns;
  - the six heat levels: cruisers, boxing in, roadblocks placed ahead on the graph, spike strips, the helicopter with its searchlight, a patrol boat;
  - the "last seen" search circle;
  - hideouts and bribes.
- **Owns:** `sg/ai/*`, `sg/heat/*`, `sg/plugins/c_*.lua`.
- **Uses:** entities (with LOD rates), the road graph (`path`, `exits`, `pointAt`), `motion`, `drive`, events `crime`, `heat_changed`, `district_enter`, `quality`.
- **Gate:**
  - AI stays on roads on the testbed's curves and hills;
  - roadblocks appear ahead of you;
  - the search circle shrinks and ends;
  - crowd caps;
  - a 10-minute heat-6 soak with no errors within the frame budget.
- **Size:** code ~90 KB.

### D. Story and characters

- **Scope:**
  - 24+ mission scripts in 3 acts (Low Tide, Riptide, King Tide) with set pieces;
  - cutscenes (camera shots, letterboxing, skippable);
  - dialogue with 2–4 choices that are remembered;
  - 3 endings;
  - the phone and its contacts;
  - characters' lines.
- **Owns:** `sg/story/*` (the cutscene player, phone screen, mission hooks), `content/story/*`, `sg/plugins/d_*.lua`.
- **Uses:** `core/script.lua`, ui screens and widgets, content, events `mission_start`, `mission_end`, `checkpoint`, `choice`, `save`/`load`.
- **Gate:**
  - every mission plays start to finish by script;
  - every choice path reaches an ending;
  - saving and loading at every step resumes it;
  - every line fits 51 columns.
- **Size:** code ~45 KB, scripts ~500 KB.

### E. Activities, progress, UI and radio

- **Scope:**
  - races with ghosts, taxi, deliveries;
  - 50 gull totems and 10 postcards;
  - 20 stunt jumps;
  - shops (respray, tune, clothes);
  - property with income;
  - the garage screen;
  - stats, 40 achievements, the 100% tracker;
  - the settings menu, HUD polish, transitions, the loading screen;
  - the car radio: 4 stations driven by the music module's API.
- **Owns:** `sg/activities/*`, `sg/progress/*`, `sg/ui/*`, `sg/radio.lua`, `content/activities/*`, `sg/plugins/e_*.lua`.
- **Uses:** ui, events (`money`, `pickup`, `jump`, `achievement`), save sections, the music module's public functions (ask the music agent for tracks).
- **Gate:**
  - every activity can be completed;
  - race times are exact;
  - property income over game days;
  - 100% adds up to exactly 100;
  - each achievement fires once;
  - settings persist.
- **Size:** code ~100 KB, data ~80 KB.

## 5. How a change gets in

1. A stream finishes a milestone in its worktree with its gate green and asks the integrator.
2. The integrator merges the streams' folders, runs every test, the soak, `budget.mjs` and the gate screenshots, and pushes once.
3. When the new city and the story are playable end to end, v2 becomes the default. Today's game stays one file away until then.
