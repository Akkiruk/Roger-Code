-- The car radio: four stations, each a track of the soundtrack, a name, a frequency and a DJ with lines to say. The DJ
-- text runs along the radio line of the HUD.
return {
  stations = {
    { id = "gull", name = "Gull FM", freq = "98.1", track = "drive", dj = "Dot Kestrel",
      lines = {
        "Gull FM, 98.1: all the hits, none of the traffic. Mostly.",
        "That one goes out to whoever just parked on the pier.",
        "Dot Kestrel here. If you can hear this, you are driving too slow.",
        "Tide is out, tempers are in. Stay cool, Saltgate.",
        "Weather: dusk, followed by more dusk.",
      } },
    { id = "gilt", name = "Gilt Heights Smooth", freq = "101.5", track = "roam_gilt", dj = "Percival Vane",
      lines = {
        "Smooth 101.5. The harp is not a request, it is a lifestyle.",
        "Percival Vane, up on the hill, where the air is thin and the rent is thinner.",
        "A little bell for the penthouse crowd. Ting.",
        "Sip something. Sit somewhere with a view. Pretend it is yours.",
        "Smooth 101.5: sounds expensive on purpose.",
      } },
    { id = "lantern", name = "Lantern Row Echo", freq = "94.7", track = "roam_lantern", dj = "Mimi Pell",
      lines = {
        "Lantern Row Echo, 94.7. Beeps, boops and the odd bit of tape hiss.",
        "Mimi Pell: if the noodle stall is open, so are we.",
        "Echo, echo, echo. We said that thrice on purpose.",
        "Requests by paper boat only. Mind the canal.",
        "Lanterns on, lights low, volume up.",
      } },
    { id = "iron", name = "Iron Flats 88", freq = "88.3", track = "roam_cinder", dj = "Big Ruth",
      lines = {
        "Iron Flats 88. We play it on a cowbell because we can.",
        "Big Ruth here, rattling the rail yard since before you were tall.",
        "If your car does not shake, you are not listening.",
        "Shift change in ten. Turn it up for the night crew.",
        "Iron Flats 88: made of the same stuff as the bridge.",
      } },
  },
  -- how long a DJ line stays on screen, and the gap before the next one
  lineSeconds = 7,
  gapSeconds = 40,
}
