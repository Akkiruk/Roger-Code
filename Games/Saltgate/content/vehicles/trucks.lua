-- content/vehicles/trucks.lua
-- Trucks and trailers. A cab with a hitch pulls a trailer (class "trailer"): the trailer follows the hitch like a
-- rod, so reversing folds it and a hard turn swings it wide. hitch is how far behind the cab's middle the hitch is
-- (on a trailer: how far in front of its middle the coupling is).
--   trailer   the trailer a cab is sold with (optional)
return {
  { id = "ferrybox", class = "truck", radius = 2.4, name = "Ferrybox", shape = "boxtruck", body = "white", cabin = "black", stripe = "blue",
    top = 24, accel = 7, brake = 20, turn = 1.9, grip = 4.5, slip = 0.05, stab = 0.1, climb = 0.7, rugged = 0.6,
    health = 260, length = 7.0, width = 2.4, height = 3.0, mass = 3.0, value = 500, seats = 2, traffic = true, weight = 1 },
  { id = "haulrig", class = "truck", radius = 2.3, name = "Haul Rig", shape = "cab", body = "red", cabin = "black", stripe = "yellow",
    top = 27, accel = 8, brake = 21, turn = 2.0, grip = 4.8, slip = 0.05, stab = 0.1, climb = 0.9, rugged = 0.6,
    health = 300, length = 5.2, width = 2.4, height = 3.2, mass = 3.2, value = 900, seats = 2, hitch = 2.6,
    trailer = "t_box" },
  { id = "t_flat", class = "trailer", name = "Flatbed", shape = "flatbed", body = "gray", cabin = "black",
    top = 27, accel = 1, brake = 1, turn = 1, grip = 1, health = 200, length = 9.0, width = 2.4, height = 1.6, mass = 2.0,
    value = 200, seats = 0, hitch = 4.4 },
  { id = "t_box", class = "trailer", name = "Box Trailer", shape = "boxtrailer", body = "white", cabin = "black", stripe = "blue",
    top = 27, accel = 1, brake = 1, turn = 1, grip = 1, health = 220, length = 9.0, width = 2.4, height = 3.4, mass = 2.2,
    value = 260, seats = 0, hitch = 4.4 },
  { id = "t_tank", class = "trailer", name = "Tanker", shape = "tanker", body = "lightGray", cabin = "black", stripe = "red",
    top = 27, accel = 1, brake = 1, turn = 1, grip = 1, health = 240, length = 9.0, width = 2.4, height = 3.0, mass = 2.6,
    value = 300, seats = 0, hitch = 4.4 },
}
