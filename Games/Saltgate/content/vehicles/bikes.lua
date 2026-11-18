-- content/vehicles/bikes.lua
-- Motorbikes: they lean into corners (the lean limit shrinks with speed so they never flip), a hard hit throws the
-- rider (knocked down, never hurt for good) and the bike stays where it fell.
--   lean   the most it leans, radians, at walking pace
return {
  { id = "scoot", class = "bike", name = "Scoot", shape = "scooter", body = "cyan", cabin = "black",
    top = 21, accel = 11, brake = 20, turn = 3.4, grip = 7, slip = 0.05, lean = 0.5, climb = 0.8, rugged = 1.0,
    health = 40, length = 1.9, width = 0.7, height = 1.2, mass = 0.25, value = 60, seats = 1, traffic = true, weight = 1 },
  { id = "stinger", class = "bike", name = "Stinger", shape = "sport", body = "yellow", cabin = "black", stripe = "black",
    top = 45, accel = 22, brake = 30, turn = 2.8, grip = 7.5, slip = 0.08, lean = 0.55, climb = 1.0, rugged = 1.0,
    health = 45, length = 2.1, width = 0.75, height = 1.2, mass = 0.3, value = 650, seats = 1 },
  { id = "bruiser", class = "bike", name = "Bruiser", shape = "cruiser", body = "red", cabin = "black", stripe = "lightGray",
    top = 34, accel = 14, brake = 24, turn = 2.3, grip = 6, slip = 0.07, lean = 0.4, climb = 1.1, rugged = 0.9,
    health = 70, length = 2.4, width = 0.85, height = 1.25, mass = 0.5, value = 400, seats = 1 },
  { id = "burr", class = "bike", name = "Burr", shape = "dirt", body = "orange", cabin = "black",
    top = 30, accel = 16, brake = 22, turn = 3.1, grip = 6, slip = 0.12, lean = 0.6, climb = 1.5, rugged = 0.4,
    health = 40, length = 2.0, width = 0.7, height = 1.3, mass = 0.25, value = 300, seats = 1 },
}
