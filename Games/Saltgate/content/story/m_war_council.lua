-- Act 3, job 1 (King Tide opens): three days to the surge. The crew has to be gathered, one favour at a time, and the plan
-- told. What people say depends on what you did in Act 2.
return function(api)
  api.step("morning", function()
    api.title("ACT THREE", "KING TIDE")
    api.say("Mama Juno", "Day one. The water pipes are already tapping. That is the sea checking the locks.")
    api.say("Pip", "Nana says I am not allowed to ask what the plan is. So I am asking what the plan is not.")
    api.say("Wren", "The plan is a gate, a key and a lot of people who will not move.")
    if api.recall("juno_fate") == "public" then
      api.say("Mama Juno", "And one old woman who is going to say what she did, in public, in front of Ferris's microphone. Today.")
    elseif api.recall("juno_fate") == "forgiven" then
      api.say("Mama Juno", "And one old woman who is going to spend every hour she has making it right.")
    else
      api.say("Mama Juno", "And one old woman who would like to be useful, if you will let her.")
    end
    api.say("Mama Juno", "Go and fetch your crew. They are not going to come to a cellar on their own.")
  end)

  api.step("wheels", function()
    api.anyCar("Get a car to collect the crew.")
  end, { at = "safehouse" })

  api.step("tam", function()
    api.hint("Tam's garage first. She has a surprise. She always has a surprise.")
    api.drive("tam_garage", { text = "Go to Tam's garage.", radius = 5 })
    api.say("Tam", "I have named it 'the Hiccup'. It is a key. It is a lock. It is also slightly a doorbell. I do not entirely understand it.")
    if api.recall("pitwall_satchel") then
      api.say("Tam", "I built most of it from what was in that satchel you took, by the way. I know. I should say thank you.")
    elseif api.recall("pitwall_photo") then
      api.say("Tam", "I framed that photograph of the Gilt crest. It is in the loo. It is very popular.")
    end
    local pick = api.choose("Tam shows you the Hiccup. It ticks softly.", {
      "Will it open the sea gate?",
      "Is it safe to carry?",
      "Tam, I trust you. Whatever it is.",
    })
    if pick == 1 then
      api.say("Tam", "With a fleet key and a gate key, yes. With only one, it will open a very nice biscuit tin.")
    elseif pick == 2 then
      api.say("Tam", "Mostly. Do not drop it in water. Or oil. Or a pond. Or a mood.")
    else
      api.say("Tam", "That is the nicest thing anyone has said to me this week. I am going to put it in the Hiccup.")
      api.tally("heart", 1)
    end
  end, { at = "safehouse", give = { name = "car", kind = "marlin" } })

  api.step("sable", function()
    api.drive("sable_garage", { text = "Go to Sable's lock-up.", radius = 5 })
    if api.recall("sable_crew") then
      api.say("Sable", "I have been waiting. I have the gnome in the car. It is a good luck charm. It is also a threat.")
      api.say("Sable", "Tell me where to drive and I will be there ten minutes early.")
      api.tally("sable", 1)
    else
      api.say("Sable", "Calloway. You are still looking at me like I owe you something. I do. I am not sure I know how to pay it.")
      local pick = api.choose("Sable is not sure whether you are here to forgive her.", {
        "Pay it by driving for us.",
        "I need you. That is all.",
        "Prove you aren't going to bolt.",
      })
      if pick == 1 then
        api.say("Sable", "Driving. Yes. That is the one thing I am good at. Deal.")
        api.tally("sable", 2)
      elseif pick == 2 then
        api.say("Sable", "...Do not say that twice. I will start to believe it.")
        api.tally("sable", 2)
        api.tally("heart", 1)
      else
        api.say("Sable", "Fair. Watch me. Starting now. I will not bolt even if the gnome catches fire.")
        api.tally("sable", 1)
      end
    end
  end, { at = "tam_garage", give = { name = "car", kind = "marlin" } })

  api.step("rook", function()
    api.drive("ferry", { text = "Go to Captain Rook at the ferry pier.", radius = 6 })
    api.say("Captain Rook", "Lass. They have cut the chain on the Tern. Someone in the Authority has a conscience. A small one.")
    if api.recall("plan_leave") then
      api.say("Captain Rook", "You wanted to run, last week. I would have taken you and gladly. What changed?")
      api.say("Wren", "Pip's birthday.")
    end
    api.say("Captain Rook", "The Tern holds two hundred. Old Saltgate is three hundred families. I will make four trips and I will need a head start.")
    local pick = api.choose("The Tern's horn is rusty. It makes a sound like a goose with an opinion.", {
      "You'll have your head start.",
      "We hope it doesn't come to the boat.",
      "Captain, you're a hero.",
    })
    if pick == 1 then
      api.say("Captain Rook", "Then I will have her warm by Saturday. The storm will not scare her. She has been through worse. So have I.")
    elseif pick == 2 then
      api.say("Captain Rook", "Hope is a fine thing. A boat is better. Keep both.")
      api.tally("law", 1)
    else
      api.say("Captain Rook", "I am a man who owns a boat. Hero is for the people who do the sailing. Go on, lass.")
      api.tally("heart", 1)
    end
  end, { at = "sable_garage", give = { name = "car", kind = "marlin" } })

  api.step("plan", function()
    api.hint("Back to the safehouse. The whole crew is meeting.")
    api.drive("safehouse", { text = "Back to the safehouse. Everyone is waiting.", radius = 4 })
    api.say("Tam", "Okay. Plan. Five parts. Ferris broadcasts so everyone knows. We take the gate key from Authority Hall. We stop the convoy for the second key.")
    api.say("Tam", "Then someone walks into the gate house and holds it. And at the end, the Tern takes everyone out, if all else fails.")
    api.say("Wren", "That is a lot of things.")
    api.say("Tam", "It is two lots of things. And a gull.")
    api.say("Rusty", "Also the yard is under attack. Authority trucks. They want my cranes. I will need a hand with that first.")
    api.say("Mama Juno", "Sleep tonight. Everyone. That is an order from the cook. Tomorrow we are brave.")
  end, { at = "ferry", give = { name = "car", kind = "marlin" } })
end
