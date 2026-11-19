-- What the shops sell. Prices are in dollars; tune tiers 1 to 3 are bought in order.
return {
  respray = {
    price = 150,
    colours = { "orange", "blue", "red", "lightGray", "green", "white", "purple", "cyan", "yellow", "pink", "brown", "gray" },
  },
  tune = {
    -- slot: label and the price of each tier
    slots = {
      { id = "engine", label = "Engine", prices = { 400, 900, 1800 } },
      { id = "brakes", label = "Brakes", prices = { 250, 600, 1200 } },
      { id = "grip", label = "Tyres", prices = { 300, 700, 1400 } },
      { id = "armour", label = "Armour", prices = { 500, 1100, 2200 } },
    },
  },
  clothes = {
    outfits = {
      { id = "deckhand", name = "Deckhand", shirt = "orange", legs = "gray", price = 0 },
      { id = "gull", name = "Gull Grey", shirt = "lightGray", legs = "blue", price = 120 },
      { id = "lamplighter", name = "Lamplighter", shirt = "yellow", legs = "brown", price = 160 },
      { id = "harbour", name = "Harbour Blue", shirt = "blue", legs = "gray", price = 180 },
      { id = "cinder", name = "Cinder Red", shirt = "red", legs = "black", price = 220 },
      { id = "gilt", name = "Gilt Gala", shirt = "white", legs = "purple", price = 400 },
      { id = "brine", name = "Brine Green", shirt = "green", legs = "brown", price = 260 },
      { id = "night", name = "Night Run", shirt = "black", legs = "cyan", price = 320 },
    },
  },
  garage = { base = 3 }, -- cars a garage holds before property adds more
}
