-- The 40 achievements. Data only (content files run with no globals).
--   stat = "name", at = n        a persistent stat reaches n          (stats: see sg/progress/stats.lua)
--   set = "name", at = n         a set (districts, stations ...) has n members
--   done = "category", at = n    a completion category has n done; at = "all" means every one
--   story = "finished"           the story's end
--   completion = 100             the 100% tracker
--   reward                       cash paid when it unlocks
return {
  -- the story
  { id = "first_job", name = "First Job", desc = "Finish a job for the Low Tide crew.", stat = "missionsPassed", at = 1, reward = 100 },
  { id = "steady_hands", name = "Steady Hands", desc = "Finish eight jobs.", stat = "missionsPassed", at = 8, reward = 300 },
  { id = "low_tide", name = "Low Tide", desc = "See the story through to its end.", story = "finished", reward = 1000 },
  { id = "completionist", name = "Saltgate, All of It", desc = "Reach 100% completion.", completion = 100, reward = 2500 },
  -- getting about
  { id = "local_knowledge", name = "Local Knowledge", desc = "Set foot in five districts.", set = "districts", at = 5, reward = 200 },
  { id = "dial_hopper", name = "Dial Hopper", desc = "Tune in all four radio stations.", set = "stations", at = 4, reward = 150 },
  { id = "sea_legs", name = "Sea Legs", desc = "Walk two kilometres on foot.", stat = "onFoot", at = 2000, reward = 150 },
  { id = "first_miles", name = "First Miles", desc = "Drive one kilometre.", stat = "distance", at = 1000, reward = 100 },
  { id = "road_tripper", name = "Road Tripper", desc = "Drive ten kilometres.", stat = "distance", at = 10000, reward = 400 },
  { id = "needle_pinned", name = "Needle Pinned", desc = "Pass 150 km/h.", stat = "topSpeed", at = 150, reward = 300 },
  { id = "gull_wings", name = "Gull Wings", desc = "Spend ten seconds in the air, all told.", stat = "airtime", at = 10, reward = 250 },
  { id = "sticky_fingers", name = "Sticky Fingers", desc = "Take ten cars that were not yours.", stat = "carsStolen", at = 10, reward = 250 },
  -- money
  { id = "pocket_change", name = "Pocket Change", desc = "Earn $1,000 in all.", stat = "moneyEarned", at = 1000, reward = 100 },
  { id = "comfortable", name = "Comfortable", desc = "Earn $10,000 in all.", stat = "moneyEarned", at = 10000, reward = 500 },
  { id = "big_fish", name = "Big Fish", desc = "Earn $100,000 in all.", stat = "moneyEarned", at = 100000, reward = 2000 },
  -- the Harbor Patrol
  { id = "on_the_radar", name = "On the Radar", desc = "Get the Patrol's attention (wanted level 2).", stat = "maxHeat", at = 2, reward = 100 },
  { id = "hot_pursuit", name = "Hot Pursuit", desc = "Reach wanted level 4.", stat = "maxHeat", at = 4, reward = 300 },
  { id = "public_enemy", name = "Public Enemy", desc = "Reach wanted level 6.", stat = "maxHeat", at = 6, reward = 800 },
  { id = "shake_it", name = "Shake It Off", desc = "Lose the Patrol three times.", stat = "heatCleared", at = 3, reward = 300 },
  -- collecting
  { id = "gull_spotter", name = "Gull Spotter", desc = "Find 10 gull totems.", done = "totems", at = 10, reward = 200 },
  { id = "gull_watcher", name = "Gull Watcher", desc = "Find 25 gull totems.", done = "totems", at = 25, reward = 500 },
  { id = "gull_whisperer", name = "Gull Whisperer", desc = "Find every gull totem.", done = "totems", at = "all", reward = 1500 },
  { id = "pen_pal", name = "Pen Pal", desc = "Find 5 postcards.", done = "postcards", at = 5, reward = 250 },
  { id = "postmaster", name = "Postmaster", desc = "Find every postcard.", done = "postcards", at = "all", reward = 800 },
  -- stunt jumps
  { id = "leap_of_faith", name = "Leap of Faith", desc = "Land your first stunt jump.", done = "jumps", at = 1, reward = 100 },
  { id = "stunt_double", name = "Stunt Double", desc = "Land ten stunt jumps.", done = "jumps", at = 10, reward = 500 },
  { id = "fly_by", name = "Fly-By", desc = "Land every stunt jump.", done = "jumps", at = "all", reward = 1500 },
  { id = "long_jump", name = "Long Jump", desc = "Clear 40 metres in one jump.", stat = "longestJump", at = 40, reward = 400 },
  -- street races
  { id = "on_your_marks", name = "On Your Marks", desc = "Finish a street race.", stat = "racesRun", at = 1, reward = 100 },
  { id = "top_step", name = "Top Step", desc = "Win a gold in a street race.", stat = "racesGold", at = 1, reward = 400 },
  { id = "full_grid", name = "Full Grid", desc = "Finish every street race.", done = "races", at = "all", reward = 1000 },
  -- fares and parcels
  { id = "meter_running", name = "Meter Running", desc = "Finish 5 taxi fares.", stat = "fares", at = 5, reward = 200 },
  { id = "taxi_ace", name = "Taxi Ace", desc = "Finish 25 taxi fares.", stat = "fares", at = 25, reward = 800 },
  { id = "special_delivery", name = "Special Delivery", desc = "Deliver 5 parcels.", stat = "deliveries", at = 5, reward = 200 },
  { id = "courier_king", name = "Courier King", desc = "Deliver 25 parcels.", stat = "deliveries", at = 25, reward = 800 },
  -- property and the garage
  { id = "landlord", name = "Landlord", desc = "Buy a property.", done = "property", at = 1, reward = 300 },
  { id = "portfolio", name = "Portfolio", desc = "Own every property.", done = "property", at = "all", reward = 2000 },
  { id = "fresh_paint", name = "Fresh Paint", desc = "Have a car resprayed.", stat = "resprays", at = 1, reward = 100 },
  { id = "tuned_up", name = "Tuned Up", desc = "Take a tune to its top tier.", stat = "tuneMax", at = 3, reward = 400 },
  { id = "new_threads", name = "New Threads", desc = "Buy an outfit.", stat = "outfits", at = 1, reward = 100 },
}
