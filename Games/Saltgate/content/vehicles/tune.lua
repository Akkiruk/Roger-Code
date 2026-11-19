-- content/vehicles/tune.lua
-- What the garage sells (stream E's shops read this). Paint colours are names from the game's 16. A tune slot has
-- tiers 1-3: each multiplies the car's numbers and costs a fraction of its value.
return {
  -- not purple, magenta, pink or lightBlue: the sky and the lit windows use those slots, and they change with the hour
  paints = { "red", "orange", "yellow", "lime", "green", "cyan", "blue",
    "brown", "white", "lightGray", "gray", "black" },
  stripes = { "none", "white", "black", "yellow", "red", "blue", "cyan" },
  -- shares of the car's value, never of less than priceFloor (so a cheap car's respray is still about $120, against
  -- jobs that pay $200 and up)
  priceFloor = 1500,
  paintPrice = 0.08, -- of the car's value
  stripePrice = 0.03,
  slots = {
    engine = { names = { "Tuned", "Sport", "Race" }, top = { 1.04, 1.08, 1.13 }, accel = { 1.1, 1.22, 1.4 }, price = { 0.08, 0.16, 0.3 } },
    brakes = { names = { "Pads", "Discs", "Race" }, brake = { 1.1, 1.2, 1.35 }, price = { 0.05, 0.1, 0.2 } },
    grip = { names = { "Tyres", "Sport", "Slicks" }, grip = { 1.1, 1.22, 1.38 }, turn = { 1.03, 1.06, 1.1 }, price = { 0.06, 0.12, 0.24 } },
    armour = { names = { "Plates", "Cage", "Plated" }, health = { 1.25, 1.6, 2.2 }, mass = { 1.05, 1.12, 1.25 }, price = { 0.07, 0.14, 0.28 } },
  },
}
