-- Act 2, job 4: the Authority raised the canal bridge to cut Lantern Row off, with Ferris on the wrong side. The raised
-- span is a ramp. Take Rusty's Sovereign at speed and jump the gap.
return function(api)
  api.step("garage", function()
    api.say("Tam", "Pit Wall! Okay. Okay okay okay. Bad news and great news. Bad: the Authority raised the canal bridge. Lantern Row is cut in half.")
    api.say("Tam", "Great: it is raised at an angle. It is a ramp. I have drawn it. Look. It is a very good ramp.")
    api.say("Wren", "Tam. It is a bridge. It goes up.")
    api.say("Tam", "And then you go over! And Ferris is on the north bank with a wardens' van parked on his doorstep! He is broadcasting from a cupboard!")
    local pick = api.choose("Tam is far too happy about this.", {
      "How much speed does a bridge jump need?",
      "Tell me the ramp is solid.",
      "Why does it always have to be me?",
    })
    if pick == 1 then
      api.say("Tam", "Thirty-four. Maybe thirty-six. The Sovereign does forty-two. The numbers are your friends. Mostly.")
    elseif pick == 2 then
      api.say("Tam", "It is solid in the sense that a thing that goes up is solid. I will not say more. Legal reasons.")
    else
      api.say("Tam", "Because you did a ramp at the docks and everyone talked about it for a week. You are known for ramps.")
      api.tally("heart", 1)
    end
    api.say("Tam", "Rusty has lent you the Sovereign. He said 'bring it back' and then he said 'it is fine if you do not'. Take it.")
  end)

  api.step("car", function()
    api.car("sovereign", "rusty_door", { name = "car", label = "Sovereign" })
    api.getIn("car", "Take Rusty's gold Sovereign.")
  end, { at = "tam_garage" })

  api.step("approach", function()
    api.ensureCar("car", "sovereign", "rusty_door", { label = "Sovereign" })
    api.hint("Line up with the span. Straight, flat out, no braking on the ramp. Look for the north bank.")
    api.drive("canal_south", { name = "car", text = "Drive to the south end of the canal bridge." })
  end, { at = "rusty_door", give = { name = "car", kind = "sovereign" } })

  api.step("jump", function()
    api.say("Tam", "There she is. Span is up, ramp is angled, north bank is... over there. Further than I drew it. Do not think. Go.")
    api.ensureCar("car", "sovereign", "canal_south", { label = "Sovereign" })
    api.hint("Floor it up the span. Keep straight. The Sovereign wants to be in the air.")
    api.jump({ text = "Floor it up the raised span and jump the canal!", min = 14, place = "canal_north",
      failText = "you didn't make the jump" })
    api.toast("AIR!", "toast")
    api.say("Tam", "She flew! She actually flew! I need to sit down. I am sitting down. I am on the floor.")
  end, { at = "canal_south", give = { name = "car", kind = "sovereign" } })

  api.step("ferris", function()
    api.say("Wren", "North bank. Tyres are on the ground. Where is the wardens' van?")
    api.heat(2)
    api.hint("Ferris's studio is a couple of streets in. The wardens have noticed you.")
    api.ensureCar("car", "sovereign", "canal_north", { label = "Sovereign" })
    api.drive("studio", { name = "car", text = "Get to Ferris's studio on Lantern Row." })
    api.say("Ferris", "Wren Calloway, descending from the heavens in a golden chariot! I have not been this thrilled since the Tidewater Gala!")
    api.say("Wren", "Get in. They are right behind me.")
    api.say("Ferris", "I have a microphone and a cat. May they come? She is called Ledger.")
  end, { at = "canal_north", give = { name = "car", kind = "sovereign" } })

  api.step("home", function()
    api.loseHeat("Lose the wardens with Ferris on board.")
    api.say("Ferris", "I have an announcement. I am no longer an observer. I am a participant. Please clap.")
    local pick = api.choose("Ferris stares at the cat, then at you.", {
      "Welcome aboard. Mind the upholstery.",
      "You are a liability. But a loud one.",
      "You can ride, but the cat is in charge.",
    })
    if pick == 1 then
      api.say("Ferris", "I will mind it with my whole heart. And a small towel.")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Ferris", "A loud liability! I will put it on my business card!")
    else
      api.say("Ferris", "Ledger accepts. She says you will do.")
      api.tally("juno", 1)
    end
    api.text("ferris", "I have put you on my emergency contacts list. It is a short list. It is just you and the cat.")
  end, { at = "studio", give = { name = "car", kind = "sovereign" } })
end
