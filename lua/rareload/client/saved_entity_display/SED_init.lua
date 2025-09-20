RARELOAD = RARELOAD or {}
RARELOAD._EntityInfo = RARELOAD._EntityInfo or {}
RARELOAD._NPCInfo = RARELOAD._NPCInfo or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.SavedEntityDisplay = RARELOAD.SavedEntityDisplay or {}
SED = RARELOAD.SavedEntityDisplay
SED.SAVED_ENTITIES_BY_ID = {}
SED.SAVED_NPCS_BY_ID = {}
SED.TrackedEntities = {}
SED.TrackedNPCs = {}
SED.MAP_LAST_BUILD = 0
SED.SAVED_LOOKUP_INTERVAL = 5
SED.LAST_RESCAN = 0
SED.RESCAN_INTERVAL = 4
SED.INFO_CACHE_LIFETIME = 1.0
SED.MAX_DRAW_PER_FRAME = 40
SED.BASE_DRAW_DISTANCE = 1000
SED.LARGE_ENTITY_DRAW_DISTANCE = 2500
SED.DRAW_DISTANCE_SQR = SED.BASE_DRAW_DISTANCE * SED.BASE_DRAW_DISTANCE
SED.BASE_SCALE = 0.11
SED.MIN_SCALE = 0.05
SED.MAX_SCALE = 0.25
SED.MAX_VISIBLE_LINES = 10
SED.SCROLL_SPEED = 3
SED.LARGE_ENTITY_THRESHOLD = 200
SED.MASSIVE_ENTITY_THRESHOLD = 800
SED.CULL_VIEW_CONE = true
SED.FOV_COS_THRESHOLD = math.cos(math.rad(70))
SED.NEARBY_DIST_SQR = 512 * 512
SED.HITTEST_ONLY_CANDIDATE = true
SED.PanelScroll = { entities = {}, npcs = {} }
SED.InteractionState = { active = false, ent = nil, id = nil, isNPC = false, lastAction = 0 }
SED.KeyStates = {}
SED.KEY_REPEAT_DELAY = 0.25
SED.CandidateEnt = nil
SED.CandidateIsNPC = nil
SED.CandidateID = nil
SED.CandidateYawDiff = nil
SED.INTERACT_KEY = KEY_E
SED.REQUIRE_SHIFT_MOD = true
SED.ScrollDelta = 0
SED.LeaveTime = 0
SED.LookingAtPanelUntil = 0
SED.EntityPanelCache = {}
SED.NPCPanelCache = {}
SED.EntityBoundsCache = {}
SED.LastFrameRenderCount = 0
SED.FrameRenderBudget = 0.003
SED.lpCache = nil
SED.lastPlayerCheck = 0
SED.THEME = _G.THEME or {
    background = Color(20, 20, 30, 220),
    header = Color(30, 30, 45, 255),
    border = Color(70, 130, 180, 255),
    text = Color(220, 220, 255)
}

SED.ENT_CATEGORIES = {
    { "basic",     "Basic",      Color(64, 152, 255) },
    { "position",  "Position",   Color(60, 179, 113) },
    { "saved",     "Saved Data", Color(255, 140, 40) },
    { "state",     "State",      Color(218, 165, 32) },
    { "physics",   "Physics",    Color(255, 120, 90) },
    { "visual",    "Visual",     Color(147, 112, 219) },
    { "ownership", "Ownership",  Color(200, 150, 255) },
    { "keyvalues", "KeyValues",  Color(180, 180, 180) },
    { "meta",      "Meta",       Color(120, 200, 220) }
}

SED.NPC_CATEGORIES = {
    { "basic",     "Basic",      Color(64, 152, 255) },
    { "position",  "Position",   Color(60, 179, 113) },
    { "saved",     "Saved Data", Color(255, 140, 40) },
    { "state",     "State",      Color(218, 165, 32) },
    { "behavior",  "Behavior",   Color(214, 80, 80) },
    { "combat",    "Combat",     Color(255, 90, 140) },
    { "visual",    "Visual",     Color(147, 112, 219) },
    { "ownership", "Ownership",  Color(200, 150, 255) },
    { "relations", "Relations",  Color(120, 200, 220) },
    { "keyvalues", "KeyValues",  Color(180, 180, 180) },
    { "meta",      "Meta",       Color(120, 200, 220) }
}

SED.surface_SetFont = surface.SetFont
SED.surface_GetTextSize = surface.GetTextSize
SED.surface_SetDrawColor = surface.SetDrawColor
SED.draw_SimpleText = draw.SimpleText
SED.draw_RoundedBox = draw.RoundedBox
