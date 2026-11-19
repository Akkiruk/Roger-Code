-- content/vehicles/boats.lua
-- Boats float on the water (stream:waterAt) and never leave it: the shore, a pier post or a quay stops them.
-- grip is how well the hull holds a line (low slides in a turn); bob is how much the waves lift it.
return {
  { id = "skiff", class = "boat", name = "Skiff", shape = "skiff", body = "white", cabin = "black", stripe = "blue",
    top = 14, accel = 5, brake = 6, turn = 1.6, grip = 1.4, bob = 0.12, health = 60, length = 4.2, width = 1.8, height = 1.0,
    mass = 0.6, value = 90, seats = 3 },
  { id = "wavecutter", class = "boat", radius = 2.0, name = "Wavecutter", shape = "speedboat", body = "red", cabin = "black", stripe = "white",
    top = 30, accel = 10, brake = 9, turn = 1.9, grip = 1.8, bob = 0.18, health = 90, length = 6.0, width = 2.2, height = 1.2,
    mass = 0.9, value = 1200, seats = 4 },
  { id = "splasher", class = "boat", name = "Splasher", shape = "jetski", body = "yellow", cabin = "black", stripe = "black",
    top = 28, accel = 14, brake = 10, turn = 2.8, grip = 2.4, bob = 0.2, health = 40, length = 2.6, width = 1.0, height = 1.0,
    mass = 0.3, value = 500, seats = 1 },
  { id = "patrol_boat", class = "boat", radius = 2.2, name = "Gull Patrol Boat", shape = "patrol", body = "white", cabin = "blue", police = true,
    top = 26, accel = 9, brake = 9, turn = 1.8, grip = 1.7, bob = 0.14, health = 180, length = 7.0, width = 2.6, height = 1.6,
    mass = 1.5, value = 0, seats = 4 },
  { id = "tidebarge", class = "boat", radius = 3.0, name = "Tide Barge", shape = "barge", body = "gray", cabin = "orange", stripe = "yellow",
    top = 9, accel = 2, brake = 3, turn = 0.7, grip = 1.0, bob = 0.05, health = 320, length = 10.0, width = 3.6, height = 2.2,
    mass = 4.0, value = 300, seats = 2 },
}
