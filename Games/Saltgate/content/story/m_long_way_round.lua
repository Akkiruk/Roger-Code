-- Act 3, job 5: the Authority's convoy carries the second sea gate key round the whole coast road. Tail it from the start
-- without being seen, then stop it where the road bends round the harbor. (A long tail, then a chase.)
return function(api)
  api.step("lockup", function()
    api.say("Sable", "The convoy leaves from the east end of the Brine docks at eleven. Three vehicles. The middle one is a plain van. The plain van is the one.")
    api.say("Sable", "I know their route because I have driven it ten times, once as practice and nine as an act of rudeness.")
    api.say("Wren", "How do we stop a convoy?")
    api.say("Sable", "We do not. We follow it all the way round the coast. At the last bend before the gate, there is a gap. I want you in it.")
    local pick = api.choose("Sable taps the map. She looks tired and determined, in about equal parts.", {
      "You and I. Two cars. One convoy.",
      "Tam, can you give us eyes?",
      "Won't they spot a tail for that long?",
    })
    if pick == 1 then
      api.say("Sable", "Two cars. One convoy. I have not been this nervous since you saw me crash the first time.")
      api.tally("sable", 1)
    elseif pick == 2 then
      api.say("Tam", "Pit Wall is up. I have a friend with a drone. The friend is a seagull. His name is Admiral. It is a long story.")
    else
      api.say("Sable", "Yes. If you tail badly. You will not tail badly. You will tail like a dream.")
      api.tally("heart", 1)
    end
  end)

  api.step("wheels", function()
    api.anyCar("Get a car. Something nobody looks at twice.")
  end, { at = "sable_garage" })

  api.step("tail", function()
    api.say("Tam", "Convoy is moving. Middle van is the one. Stay between sixteen and eighty metres. Treat it like a dance.")
    api.actor("runner", "convoy_start", { name = "convoy", vehicle = "tidewater", route = { "hairpin_foot", "convoy_end" }, label = "convoy van" })
    api.hint("The convoy goes round the whole coast. Keep your distance. Use the straights to catch up.")
    api.tail("convoy", { text = "Tail the convoy round the coast road.", min = 16, max = 90, grace = 10, spot = 6 })
  end, { at = "sable_garage", give = { name = "car", kind = "marlin" } })

  api.step("stop", function()
    api.say("Sable", "This is the last bend. Gap on your left, wall on your right. Wren, now! Cut across!")
    api.ensureCar("car", "marlin", "convoy_end", { label = "car" })
    api.actor("runner", "convoy_end", { name = "van", vehicle = "tidewater", route = { "seawall" }, flees = true, label = "convoy van" })
    api.hint("Cut across the road in front of the van. Don't let it past you. Ram it if you have to.")
    api.chase("van", { text = "Stop the convoy's middle van before the gate.",
      failText = "the convoy reached the gate" })
  end, { at = "convoy_end", give = { name = "car", kind = "marlin" } })

  api.step("key", function()
    api.say("Warden", "(from the van) All right! All right! I am getting out! It is in the glove box! Do not hit it again!")
    api.say("Sable", "Second key. Plain steel. Very boring. I have never been happier to hold something boring.")
    api.say("Wren", "Two keys. Gate key and fleet key. The Hiccup can open the gate.")
    api.say("Sable", "And it will take everyone in the city to hold the gate when it does. Ferris's broadcast is doing something. I can feel it.")
    local pick = api.choose("The sun is setting over the sea wall. The tide is high.", {
      "We should talk about what comes after.",
      "Let's get these keys to Tam.",
      "Sable, thank you. For all of it.",
    })
    if pick == 1 then
      api.say("Sable", "After? I try not to think about after. After is where you stop being a driver and start being a person.")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Sable", "Right. Keys to Tam. Do not talk about feelings. We will be fine.")
    else
      api.say("Sable", "Do not. You will make me say something I mean.")
      api.say("Sable", "...You are welcome. I am glad I came back.")
      api.tally("sable", 2)
      api.remember("sable_thanked", true)
    end
    api.text("sable", "Convoy stopped. I am being very calm about it. I am not calm.")
  end, { at = "convoy_end", give = { name = "car", kind = "marlin" } })
end
