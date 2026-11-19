-- The 100% tracker: ten parts that add up to exactly 100 points. Each part's share is done / total of its own kind,
-- so a city with more or fewer totems or races still adds up to 100 when everything is done.
--   storyTotal: how many story jobs there are (the story's own files may say more: the larger counts)
return {
  storyTotal = 24,
  categories = {
    { id = "story", name = "Story jobs", weight = 30 },
    { id = "totems", name = "Gull totems", weight = 15 },
    { id = "postcards", name = "Postcards", weight = 5 },
    { id = "jumps", name = "Stunt jumps", weight = 10 },
    { id = "races", name = "Street races", weight = 10 },
    { id = "taxi", name = "Taxi fares", weight = 5 },
    { id = "delivery", name = "Deliveries", weight = 5 },
    { id = "property", name = "Property", weight = 5 },
    { id = "garage", name = "Garage and shops", weight = 5 },
    { id = "achievements", name = "Achievements", weight = 10 },
  },
  -- how many taxi fares and deliveries make the part complete
  taxiTarget = 20,
  deliveryTarget = 20,
  -- the garage part: the shop jobs that count (each once)
  garageGoals = { "respray", "tune", "outfit", "storecar", "tunemax" },
}
