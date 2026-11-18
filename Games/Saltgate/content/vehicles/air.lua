-- content/vehicles/air.lua
-- Aircraft. Only the police helicopter's model for now: the Harbor Patrol (stream C) flies it, so it has no player
-- physics.
return {
  { id = "gullhawk", class = "heli", name = "Gullhawk", shape = "heli", body = "white", cabin = "blue", police = true,
    top = 55, accel = 14, brake = 14, turn = 1.8, grip = 1, health = 250, length = 8.0, width = 2.2, height = 3.0,
    mass = 2.0, value = 0, seats = 4 },
}
