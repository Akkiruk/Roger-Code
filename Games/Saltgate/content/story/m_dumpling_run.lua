-- Act 2, job 3: Juno's grand-nephew Pip has to get a van of dumplings (and the street's sandbags) to the safehouse.
-- Escort the van through Old Saltgate, then stop the Authority warden who is trying to ram it.
return function(api)
  api.step("stall", function()
    api.say("Mama Juno", "Pip! Come here and meet Wren. Wren, this is Pip. He is twelve, he knows every shortcut and he does not stop talking.")
    api.say("Pip", "I know five hundred and twelve shortcuts. Fifty of them are real. Hi! Are you the getaway driver? Is it true you drove off a pier?")
    api.say("Wren", "It was a ramp. It looked like a pier.")
    api.say("Pip", "That is so cool. Can I sit in the car? Can I honk?")
    api.say("Mama Juno", "No. Pip drives the van. You drive beside him. The warden cars have been sniffing round the old town all morning.")
    local pick = api.choose("Juno hands Pip the keys to a van full of dumplings. He is twelve.", {
      "He is twelve. Is this wise?",
      "Pip, you lead. I'll cover you.",
      "I should take the van. He rides with me.",
    })
    if pick == 1 then
      api.say("Mama Juno", "Pip has been driving that van since he was nine. Only on private land, and only in reverse. Today he goes forward.")
      api.say("Pip", "I am a very safe driver! I have never hit anything that was not already broken!")
    elseif pick == 2 then
      api.say("Pip", "Cover me! Yes! I am the lead! This is the best day of my life!")
      api.tally("heart", 1)
    else
      api.say("Mama Juno", "No. He needs to be seen driving it. A boy and a van are invisible. A woman in a fast car is not.")
      api.tally("juno", 1)
    end
    api.unlock("pip")
    api.text("pip", "Hi Wren! I put my number in your phone. I also put in a joke. It is in the notes.")
  end)

  api.step("wheels", function()
    api.anyCar("Get a car to ride beside Pip's van.")
  end, { at = "juno" })

  api.step("escort", function()
    api.say("Pip", "Okay! Dumplings are on! Van is rolling! I am a professional!")
    api.actor("runner", "juno", { name = "pip", vehicle = "tidewater", route = { "old_gate", "safehouse" }, label = "Pip's van" })
    api.hint("Stay beside him and block anything that comes in from the side streets. He does not brake very well.")
    api.escort("pip", "safehouse", { text = "Escort Pip's van to the safehouse.", max = 60,
      failText = "Pip's van didn't make it" })
  end, { at = "juno", give = { name = "car", kind = "marlin" } })

  api.step("warden", function()
    api.say("Pip", "Wren! There is a cruiser behind me! It is not the Patrol! It says AUTHORITY on the door!")
    api.say("Tam", "That is a warden car. It is going for the van. Stop it before it gets close. Ram it, spin it, I do not care.")
    api.actor("runner", "juno", { name = "pip", vehicle = "tidewater", route = { "safehouse" }, label = "Pip's van" })
    api.actor("runner", "old_gate", { name = "warden", vehicle = "cruiser", route = { "safehouse" }, flees = false, label = "warden car" })
    api.guard("pip", "Pip's van was wrecked")
    api.hint("Cut in front of the warden car and slow it. Don't let it past you.")
    api.chase("warden", { text = "Stop the warden car before it reaches Pip's van.", failText = "the warden reached the van" })
  end, { at = "old_gate", give = { name = "car", kind = "marlin" } })

  api.step("safe", function()
    api.say("Pip", "We made it! That was the best thing that has ever happened! Can we do it again? Can the van have a name?")
    api.say("Mama Juno", "The van's name is Dumpling. It always has been. Pip, take the pots inside. Wren, with me.")
    api.say("Mama Juno", "Sandbags in the cellar, boxes on the high shelves. I am packing for a flood. I do not like that I am doing it.")
    local pick = api.choose("Juno's hands are shaking, just slightly.", {
      "Juno, what do you know that I don't?",
      "Whatever it is, we can handle it.",
      "You're scaring me.",
    })
    if pick == 1 then
      api.say("Mama Juno", "Enough to be afraid. Not enough to be certain. When I am certain, you will be first to know.")
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Mama Juno", "That is what I like about you. You never ask what it will cost.")
      api.tally("juno", 1)
    else
      api.say("Mama Juno", "Good. A little fear keeps the soup from boiling over. Eat something.")
      api.tally("heart", 1)
    end
  end, { at = "safehouse" })
end
