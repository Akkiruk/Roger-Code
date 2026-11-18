-- Act 3, job 3: Authority Hall (the old Gilt Tower) has a garage that spirals up through the hill. Climb it, take the sea gate
-- key from the roof deck, meet the Commissioner, and get out down the hairpins.
return function(api)
  api.step("plan", function()
    api.say("Tam", "Authority Hall. It used to be the Gilt Tower. They scrubbed the gilt off and put 'Harbor Authority' on a very large piece of glass.")
    api.say("Tam", "The gate key lives on the roof deck in a safe disguised as a plant pot. I have checked. It is a very good plant pot.")
    api.say("Wren", "How do we get to the roof deck?")
    api.say("Tam", "The garage. It is a spiral. It has four levels and each level has a different guard. The last level has the Commissioner.")
    local pick = api.choose("Tam taps the plans on her wall.", {
      "The Commissioner is on the roof?",
      "Four guards. We can do four guards.",
      "Any chance of a plan B?",
    })
    if pick == 1 then
      api.say("Tam", "Every night at ten. She waters the plant. I do not know why. It is the only thing about her that I like.")
    elseif pick == 2 then
      api.say("Tam", "Four guards, plus a lobby full of wardens, plus the cruisers. It is a fine plan. We are not going to say the word 'plus' again.")
    else
      api.say("Tam", "Plan B is 'run'. It is the best plan I have. It always works. Until it does not.")
    end
    api.say("Tam", "Take Sable's coupe. It is fast and it is quiet and it goes up a ramp like a prayer.")
  end)

  api.step("car", function()
    api.car("sovereign", "tam_garage", { name = "car", label = "coupe" })
    api.getIn("car", "Take Sable's coupe.")
  end, { at = "tam_garage" })

  api.step("ramp", function()
    api.ensureCar("car", "sovereign", "tam_garage", { label = "coupe" })
    api.hint("The garage entrance is on the side of the Heights. Don't draw attention or the barrier closes.")
    api.drive("hall_garage", { name = "car", text = "Drive to Authority Hall's garage ramp.", noHeat = true,
      hotText = "Too hot. Lose them first." })
  end, { at = "tam_garage", give = { name = "car", kind = "sovereign" } })

  api.step("spiral", function()
    api.say("Tam", "Okay. You are in. The spiral goes up for four levels. Keep it smooth. Do not clip the pillars. They echo.")
    api.ensureCar("car", "sovereign", "hall_garage", { label = "coupe" })
    api.hint("Tight spiral. Short bursts of throttle, long sweeps. Keep your eyes on the next level.")
    api.drive("hall_roof", { name = "car", text = "Spiral up to the roof deck.", radius = 3 })
  end, { at = "hall_garage", give = { name = "car", kind = "sovereign" } })

  api.step("deck", function()
    api.say("Warden", "Roof deck is... oh. It is you. Everyone! It is that driver! The one from the news!")
    api.actor("crew", "hall_roof", { group = "hall", count = 4, look = "warden" })
    api.hint("Knock them down. They are not tough, but there are a lot of them.")
    api.defeat("hall", { text = "Knock down the roof deck wardens." })
    api.say("Tam", "The plant pot is by the railing. Hold position beside it. I will get the key out in six seconds. Five. Four.")
    api.hold("hall_roof", 6, { text = "Hold at the plant pot while Tam opens it.", away = "Get back to the plant pot!", radius = 3 })
  end, { at = "hall_roof", give = { name = "car", kind = "sovereign" } })

  api.step("vane", function()
    api.cutscene({
      { at = "hall_roof", look = "hall_garage", height = 3, seconds = 3, fade = "in", caption = "AUTHORITY HALL, ROOF DECK" },
      { at = "hall_garage", look = "hall_roof", height = 6, seconds = 4,
        say = { "Vane", "Miss Calloway. In my building. Taking my key. You have a talent for arriving where you are least wanted." } },
      { at = "hall_roof", look = "hall_garage", height = 2, drift = { 0, 3, 0 }, seconds = 4,
        say = { "Vane", "Do not move. I am watering my plant. It is a very particular plant." } },
    })
    api.say("Wren", "Commissioner Vane. I have your key. I am keeping it.")
    api.say("Vane", "Keep it. Take it to Juno. Ask her what she traded for it. I find that people value what they paid for dearly.")
    local pick = api.choose("Vane peels off one glove, slowly, and looks at her bare hand as if it is a small animal.", {
      "You'll drown three hundred families.",
      "What did Juno trade you? Tell me.",
      "You won't stop us, Commissioner.",
    })
    if pick == 1 then
      api.say("Vane", "Managed retreat is not drowning. It is a decision. Saltgate cannot protect everything, so it protects the sum. The sum is the tower and the docks.")
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Vane", "A silence. A very expensive silence. Ask her. She will say it was for you.")
      api.remember("vane_hinted", true)
      api.tally("juno", 1)
    else
      api.say("Vane", "I do not need to stop you. The tide will do that. I merely hold the door and let the weather in.")
      api.tally("greed", 1)
    end
    api.say("Vane", "My wardens will not touch you tonight. Not because I am kind. Because I do not like to waste a good Saturday.")
  end, { at = "hall_roof", give = { name = "car", kind = "sovereign" } })

  api.step("out", function()
    api.toast("The alarm just went off!", "alarm")
    api.heat(4)
    api.say("Tam", "Alarm! Barrier is down! Spiral down! Roof deck has an emergency ramp on the east side. Take it!")
    api.hint("Down the spiral, then the hairpins. The coupe likes it. You will like it less.")
    api.loseHeat("Get out of Authority Hall and lose the wardens.")
  end, { at = "hall_roof", give = { name = "car", kind = "sovereign" } })

  api.step("key", function()
    api.say("Tam", "Key. One. The gate key. The Hiccup is doing a little dance. That is a good sign. Maybe.")
    api.say("Sable", "Vane did not stop you. That is the strange part. She had you on a roof with no exit and she let you walk.")
    api.say("Wren", "She wanted me to ask Juno what she traded.")
    api.text("tam", "One key down. Convoy next. Sable has the details.")
  end, { at = "tam_garage" })
end
