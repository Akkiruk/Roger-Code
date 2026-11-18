-- content/vehicles/cars.lua
-- The cars of Saltgate beyond today's six (Pipit, Marlin, Kestrel, Tidewater, Sovereign, Cruiser), each handling its
-- own way. A data file: no globals. Numbers are units (about a metre) a second and radians a second.
--   top, accel, brake, turn, grip   the same as the core's vehicle definitions
--   slip     how readily the tail steps out in a corner (0.1 planted .. 0.35 loose)
--   stab     how much the steering goes light near top speed (0 none .. 0.5 twitchy)
--   climb    how well it takes a hill (1 normal; less loses speed on a slope)
--   rugged   how much of a hard landing it takes (1 normal, 0.4 shrugs jumps off)
--   shape    the model builder's body: see sg/vehicles/models.lua
--   body, cabin, stripe   the colours it comes in (names from the game's 16)
return {
  { id = "tern", class = "car", name = "Tern GT", shape = "hatch", body = "lime", cabin = "black",
    top = 33, accel = 14, brake = 27, turn = 3.2, grip = 8, slip = 0.12, stab = 0.1, climb = 1.0, rugged = 1.0,
    health = 85, length = 3.7, width = 1.8, height = 1.45, mass = 0.8, value = 420, seats = 2, traffic = true, weight = 1 },
  { id = "cinder", class = "car", name = "Cinder 8", shape = "muscle", body = "red", cabin = "black", stripe = "white",
    top = 40, accel = 17, brake = 26, turn = 2.4, grip = 4.2, slip = 0.34, stab = 0.25, climb = 1.1, rugged = 1.0,
    health = 120, length = 4.9, width = 2.1, height = 1.3, mass = 1.3, value = 1100, seats = 2 },
  { id = "lantern", class = "car", name = "Lantern Estate", shape = "wagon", body = "green", cabin = "black",
    top = 27, accel = 9, brake = 25, turn = 2.5, grip = 6, slip = 0.1, stab = 0.05, climb = 0.9, rugged = 0.9,
    health = 120, length = 4.9, width = 2.0, height = 1.6, mass = 1.1, value = 260, seats = 5, traffic = true, weight = 1 },
  { id = "bulwark", class = "car", radius = 2.1, name = "Bulwark", shape = "suv", body = "gray", cabin = "black",
    top = 30, accel = 10, brake = 24, turn = 2.2, grip = 5.5, slip = 0.14, stab = 0.1, climb = 1.25, rugged = 0.5,
    health = 220, length = 4.8, width = 2.2, height = 1.9, mass = 1.6, value = 700, seats = 5, traffic = true, weight = 1 },
  { id = "reef_runner", class = "car", name = "Reef Runner", shape = "buggy", body = "orange", cabin = "black", stripe = "yellow",
    top = 31, accel = 15, brake = 22, turn = 3.4, grip = 6.5, slip = 0.22, stab = 0.1, climb = 1.4, rugged = 0.35,
    health = 70, length = 3.4, width = 2.0, height = 1.5, mass = 0.6, value = 380, seats = 2 },
  { id = "ghost", class = "car", radius = 2.2, name = "Gilded Ghost", shape = "limo", body = "white", cabin = "black", stripe = "yellow",
    top = 34, accel = 9, brake = 22, turn = 1.7, grip = 5, slip = 0.08, stab = 0.1, climb = 0.8, rugged = 1.2,
    health = 130, length = 6.6, width = 2.1, height = 1.5, mass = 1.5, value = 1500, seats = 6, special = true },
  { id = "sprocket", class = "car", name = "Sprocket", shape = "micro", body = "purple", cabin = "black",
    top = 20, accel = 10, brake = 20, turn = 3.6, grip = 7, slip = 0.1, stab = 0.0, climb = 0.7, rugged = 1.2,
    health = 55, length = 2.8, width = 1.5, height = 1.5, mass = 0.45, value = 70, seats = 2, traffic = true, weight = 2 },
  { id = "ember", class = "car", name = "Ember Roadster", shape = "roadster", body = "magenta", cabin = "black",
    top = 37, accel = 15, brake = 27, turn = 3.1, grip = 6.2, slip = 0.2, stab = 0.15, climb = 1.0, rugged = 1.0,
    health = 80, length = 4.0, width = 1.9, height = 1.1, mass = 0.85, value = 800, seats = 2 },
  { id = "gullwing", class = "car", name = "Gullwing", shape = "wedge", body = "white", cabin = "black", stripe = "cyan",
    top = 48, accel = 21, brake = 32, turn = 2.6, grip = 6.8, slip = 0.26, stab = 0.4, climb = 1.0, rugged = 1.3,
    health = 75, length = 4.5, width = 2.1, height = 1.0, mass = 0.9, value = 2400, seats = 2, special = true },
  { id = "dockhand", class = "car", radius = 2.2, name = "Dockhand", shape = "pickup", body = "brown", cabin = "black",
    top = 28, accel = 10, brake = 23, turn = 2.4, grip = 5, slip = 0.16, stab = 0.1, climb = 1.15, rugged = 0.7,
    health = 150, length = 5.2, width = 2.1, height = 1.7, mass = 1.3, value = 300, seats = 3, traffic = true, weight = 1 },
  { id = "brackish", class = "car", name = "Brackish Rally", shape = "rally", body = "blue", cabin = "black", stripe = "white",
    top = 36, accel = 16, brake = 29, turn = 3.0, grip = 9.5, slip = 0.1, stab = 0.1, climb = 1.3, rugged = 0.6,
    health = 100, length = 4.1, width = 1.9, height = 1.45, mass = 0.9, value = 900, seats = 2 },
  { id = "mercy", class = "car", radius = 2.2, name = "Mercy Van", shape = "ambulance", body = "white", cabin = "black", stripe = "red",
    top = 31, accel = 11, brake = 26, turn = 2.2, grip = 5.5, slip = 0.12, stab = 0.1, climb = 0.9, rugged = 0.8,
    health = 160, length = 5.4, width = 2.2, height = 2.4, mass = 1.4, value = 0, seats = 3, special = true },
  { id = "rustler", class = "car", name = "Rustler", shape = "banger", body = "brown", cabin = "black",
    top = 22, accel = 8, brake = 18, turn = 2.3, grip = 3.8, slip = 0.2, stab = 0.05, climb = 0.8, rugged = 0.8,
    health = 60, length = 4.4, width = 1.9, height = 1.5, mass = 1.0, value = 40, seats = 4, traffic = true, weight = 2 },
}
