-- The phone's contacts. A contact appears once a job has introduced them (list.lua unlocks) or they have texted you.
-- calls: when you ring them, the newest entry whose `after` mission you have finished is the one that picks up
-- (an entry without `after` is the fallback). Each is a short exchange, { who, text } lines, nothing longer than the box.
-- tam is special: a call to Tam during a job gives the job's hint instead.
return {
  order = { "juno", "rusty", "tam", "ferris", "sable", "bart", "harrow", "pip" },
  contacts = {
    juno = { name = "Mama Juno", blurb = "Noodles, schemes, you owe her.",
      calls = {
        { say = { { "Mama Juno", "Wren, are you eating? You are not eating. Come by the stall." }, { "Wren", "On my way, Juno." } } },
        { after = "low_tide", say = { { "Mama Juno", "The harbor is shut, the stove is hot. Come in out of the wind." }, { "Wren", "Keep a bowl warm." } } },
        { after = "double_dealing", say = { { "Mama Juno", "I did what I did for a street full of people. I would do it again." }, { "Wren", "I know. That is the problem." } } },
        { after = "riptide", say = { { "Mama Juno", "Three days to the tide. I have never cooked so much in my life." }, { "Wren", "Save me a plate for after." } } },
      } },
    rusty = { name = "Rusty", blurb = "Chop yard. Doesn't talk much.",
      calls = {
        { say = { { "Rusty", "Yard." }, { "Wren", "Just checking in." }, { "Rusty", "Admiral says hello. He means he wants chips." } } },
        { after = "gilded", say = { { "Rusty", "That Sovereign is a work of art. I have not cut it up. Yet." }, { "Wren", "Cut it up. It is evidence." } } },
        { after = "double_dealing", say = { { "Rusty", "Cell has a window. Gulls sit on it. I am fine." }, { "Wren", "Hang on, Rusty." } } },
      } },
    tam = { name = "Tam", blurb = "Pit Wall. Wren's voice in the headset.",
      calls = {
        { say = { { "Tam", "Pit Wall! Hi! No, do not touch that, I was not talking to you." }, { "Wren", "Tam, it is a phone." }, { "Tam", "It is a pit wall with a phone in it." } } },
        { after = "static", say = { { "Tam", "I named the transmitter Big Mouth. It was named before it worked. That is bad luck, right?" }, { "Wren", "It worked." } } },
        { after = "bridge_out", say = { { "Tam", "I have seen a car fly. I have seen it with my own eyes. Do it again." }, { "Wren", "No." } } },
        { after = "riptide", say = { { "Tam", "Every gate in this city has a key and every key has a boring little flaw." }, { "Wren", "Find me the flaw." } } },
      } },
    ferris = { name = "Ferris", blurb = "Radio Lantern. The voice of the Row.",
      calls = {
        { say = { { "Ferris", "You have reached the finest voice in Lantern Row. Leave a scandal after the tone." }, { "Wren", "Ferris, it is me." } } },
        { after = "ledger_run", say = { { "Ferris", "Do you know what a ledger does on the air? It sings." }, { "Wren", "Keep it down, they will trace it." } } },
        { after = "cannery_row", say = { { "Ferris", "Breaking: a radio host is brave and also terrified. More at eleven." }, { "Wren", "More at eleven." } } },
      } },
    sable = { name = "Sable", blurb = "Used to be your partner. Used to.",
      calls = {
        { say = { { "Sable", "Calloway." }, { "Wren", "Quinn." }, { "Sable", "Good. We both still know our names." } } },
        { after = "quiet_hours", say = { { "Sable", "Keys in my pocket, guards asleep. You are welcome." }, { "Wren", "I did the knocking down." } } },
        { after = "double_dealing", say = { { "Sable", "Whatever Juno did, I have done worse. Doesn't make it right. Makes it familiar." }, { "Wren", "Thanks. I think." } } },
      } },
    bart = { name = "Captain Rook", blurb = "Skipper of the ferry Tern.",
      calls = {
        { say = { { "Captain Rook", "Tide's on the turn, lass. I can smell it in my teeth." }, { "Wren", "Is that a good thing?" }, { "Captain Rook", "It is a tide thing." } } },
        { after = "riptide", say = { { "Captain Rook", "The Tern has never run in a king tide. She has never been asked." }, { "Wren", "Is she up for it?" }, { "Captain Rook", "She's a ferry. She does what she's told." } } },
      } },
    harrow = { name = "Harrow", blurb = "Harbor Patrol. The one who keeps catching you.",
      calls = {
        { say = { { "Harrow", "Calloway. I am eating. This better be a confession." }, { "Wren", "Wrong number." }, { "Harrow", "I know your number. That is what is so tiring." } } },
        { after = "double_dealing", say = { { "Harrow", "Everything I have been told to do lately has turned out to be wrong. I am noticing." }, { "Wren", "Noticing is a start." } } },
      } },
    pip = { name = "Pip", blurb = "Juno's grand-nephew. Twelve, and he knows everyone.",
      calls = {
        { say = { { "Pip", "Hi Wren! Did you know a cruiser's siren is a B-flat?" }, { "Wren", "I did not know that." }, { "Pip", "Now you do. I have to go. Dumplings." } } },
        { after = "riptide", say = { { "Pip", "Everyone on our street is packing. Nana says we are not leaving." }, { "Wren", "Then we had better win." } } },
      } },
  },
}
