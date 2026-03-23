-- game_setup.lua
-- One-call initialization for surface-based casino games.
-- Sets up monitor, palette, surface API, font, card assets, CCVault auth, and all lib modules.
-- Usage:
--   local setup = require("lib.game_setup")
--   local env = setup.init({
--     monitorName = "right",
--     speakerSide = "top",
--     deckCount   = 6,
--     gameName    = "Blackjack",
--   })
--   -- env contains: surface, screen, font, cardBg, cardBack, monitor,
--   --   width, height, deck

local peripherals     = require("lib.peripherals")
local sound           = require("lib.sound")
local alert           = require("lib.alert")
local cards           = require("lib.cards")
local ui              = require("lib.ui")
local playerDet       = require("lib.player_detection")
local currency        = require("lib.currency")

-- Default palette overrides used by all casino games
local DEFAULT_PALETTE = {
  [colors.lightGray] = 0xc5c5c5,
  [colors.orange]    = 0xf15c5c,
  [colors.gray]      = 0x363636,
  [colors.green]     = 0x044906,
}

--- Initialize a casino game environment in one call.
-- @param cfg table  Required keys: monitorName
--   Optional: speakerSide, deckCount, gameName, adminName, logFile,
--             surfacePath, fontPath, cardBgPath, cardBackPath, palette,
--             authTimeout, skipAuth
-- @return table  An environment table with all initialized objects
local function init(cfg)
  assert(type(cfg) == "table", "init expects a config table")
  assert(cfg.monitorName, "monitorName is required")

  local env = {}

  -- Alert module (adminName resolved after auth below)
  alert.configure({
    adminName = cfg.adminName,
    gameName  = cfg.gameName  or "Casino",
    logFile   = cfg.logFile   or "casino_error.log",
  })

  -- Speaker
  sound.init(cfg.speakerSide)

  -- Monitor
  env.monitor = peripherals.require(cfg.monitorName, "monitor", "monitor")

  -- CCVault authentication
  if not cfg.skipAuth then
    local authOk = currency.authenticate(cfg.authTimeout or 60)
    if not authOk then
      error("CCVault authentication failed — cannot run game")
    end

    -- Resolve host name for admin alerts
    local hostName = currency.getHostName()
    if hostName then
      alert.configure({ adminName = hostName })
    end
    env.hostName = hostName

    -- Session info: detect self-play mode (server-authoritative)
    local sessionInfo = currency.getSessionInfo()
    env.sessionInfo = sessionInfo
    env.isSelfPlay = sessionInfo and sessionInfo.isSelfPlay or false
  end

  -- Surface API
  local surfacePath = cfg.surfacePath or "surface"
  env.surface = dofile(surfacePath)

  -- Monitor setup
  if type(env.monitor.setTextScale) == "function" then
    env.monitor.setTextScale(0.5)
  end
  term.redirect(env.monitor)

  -- Palette
  local palette = cfg.palette or DEFAULT_PALETTE
  for colorID, hex in pairs(palette) do
    term.setPaletteColor(colorID, hex)
  end

  env.width, env.height = term.getSize()

  -- Screen buffer
  env.screen = env.surface.create(env.width, env.height)

  -- Font
  local fontPath = cfg.fontPath or "font"
  env.font = env.surface.loadFont(env.surface.load(fontPath))

  -- Card assets
  local cardBgPath   = cfg.cardBgPath   or "card.nfp"
  local cardBackPath = cfg.cardBackPath or "cardback.nfp"
  env.cardBg   = env.surface.load(cardBgPath)
  env.cardBack = env.surface.load(cardBackPath)

  -- Initialize card renderer
  cards.initRenderer(env.surface, env.font, env.cardBg)

  -- Initialize UI module
  ui.init(env.surface, env.font)

  -- Player detection
  local detectionRange = cfg.playerDetectionRange or 10
  playerDet.init(detectionRange)

  -- Player stats (optional — only if caller provides statsInit)
  if cfg.initPlayerStats then
    local ok, pStats = pcall(require, "lib.player_stats")
    if ok then pcall(pStats.init) end
  end

  -- Build and shuffle deck
  local deckCount = cfg.deckCount or 1
  env.deck = cards.buildDeck(deckCount)
  cards.shuffle(env.deck)

  -- Store config for reference
  env.monitorName = cfg.monitorName

  -- Player state (shared by refreshPlayer/drawPlayerOverlay helpers)
  env.currentPlayer = "Unknown"

  return env
end

--- Refresh the active player name via player_detection lib.
-- Updates env.currentPlayer and returns the name.
-- @param env table  The environment from init()
-- @return string
local function refreshPlayer(env)
  local name = playerDet.refresh()
  if name and name ~= "" then
    env.currentPlayer = name
  end
  return env.currentPlayer
end

--- Draw the player overlay on the monitor.
-- @param env table  The environment from init()
local function drawPlayerOverlay(env)
  ui.drawPlayerOverlay(env.monitor, env.currentPlayer)
end

return {
  init               = init,
  DEFAULT_PALETTE    = DEFAULT_PALETTE,
  refreshPlayer      = refreshPlayer,
  drawPlayerOverlay  = drawPlayerOverlay,
}
