RARELOAD = RARELOAD or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.SavedEntityDisplay = RARELOAD.SavedEntityDisplay or {}

-- The SavedEntityDisplay (SED) module is responsible for managing and displaying information about saved entities and NPCs in the game. It maintains a cache of tracked entities, their properties, and handles user interactions with the display panel.
SED = RARELOAD.SavedEntityDisplay

function SED.Require(key, path)
    local mod = SED[key]
    if not (mod and mod._initialized) then
        include(path)
        mod = SED[key]
    end
    return mod
end

SED.SAVED_ENTITIES_BY_ID = {}
SED.SAVED_NPCS_BY_ID = {}
SED.TrackedEntities = {}
SED.TrackedNPCs = {}
SED.MAP_LAST_BUILD = 0
SED.SAVED_LOOKUP_INTERVAL = 0.5
SED.LAST_RESCAN = 0
SED.RESCAN_INTERVAL = 0.5
SED.INFO_CACHE_LIFETIME = 5.0
SED.MAX_DRAW_PER_FRAME = 16
SED.BASE_DRAW_DISTANCE = 500
SED.DRAW_DISTANCE_SQR = SED.BASE_DRAW_DISTANCE * SED.BASE_DRAW_DISTANCE
SED.INTERACT_DIST = 200
SED.INTERACT_DIST_SQR = SED.INTERACT_DIST * SED.INTERACT_DIST
SED.PHANTOM_CULL_DIST = 10000
SED.PHANTOM_CULL_DIST_SQR = SED.PHANTOM_CULL_DIST * SED.PHANTOM_CULL_DIST
SED.BASE_SCALE = 0.11
SED.MIN_SCALE = 0.05
SED.MAX_SCALE = 0.25
SED.PANEL_CLUSTER_DIST = 150
SED.PANEL_EYE_BAND = 150
SED.MAX_VISIBLE_LINES = 7
SED.SCROLL_SPEED = 3
SED.CULL_VIEW_CONE = true
SED.FOV_COS_THRESHOLD = math.cos(math.rad(50))
SED.FOV_COS_THRESHOLD_SQR = SED.FOV_COS_THRESHOLD * SED.FOV_COS_THRESHOLD
SED.NEARBY_DIST_SQR = 150 * 150
SED.HITTEST_ONLY_CANDIDATE = true
SED.PanelScroll = { entities = {}, npcs = {} }
SED.InteractionState = { active = false, ent = nil, id = nil, isNPC = false, lastAction = 0 }
SED.KeyStates = {}
SED.KEY_REPEAT_DELAY = 0.25
SED.CandidateEnt = nil
SED.CandidateIsNPC = nil
SED.CandidateID = nil
SED.INTERACT_KEY = KEY_E
SED.REQUIRE_SHIFT_MOD = true
SED.ScrollDelta = 0
SED.LeaveTime = 0
SED.LookingAtPanelUntil = 0
SED.EntityPanelCache = {}
SED.NPCPanelCache = {}
SED.EntityBoundsCache = {}
SED.lpCache = nil
SED.lastPlayerCheck = 0

if not RARELOAD.Theme or not RARELOAD.Theme.IsLightMode then
    if file.Exists("rareload/client/shared/theme_utils.lua", "LUA") then
        include("rareload/client/shared/theme_utils.lua")
    end
end

SED.THEME = _G.THEME or {
    background = Color(20, 20, 30, 220),
    header = Color(30, 30, 45, 255),
    border = Color(70, 130, 180, 255),
    text = Color(220, 220, 255)
}

if RARELOAD.Theme and RARELOAD.Theme.IsLightMode and RARELOAD.Theme.IsLightMode() then
    SED.THEME = {
        background = Color(248, 249, 251, 230),
        header = Color(236, 239, 242, 255),
        border = Color(120, 160, 210, 255),
        text = Color(25, 30, 36)
    }
end

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
    { "vjbase",    "VJ Base",    Color(100, 255, 150) },
    { "weapons",   "Weapons",    Color(255, 200, 100) },
    { "ai",        "AI",         Color(150, 200, 255) },
    { "sounds",    "Sounds",     Color(200, 150, 255) },
    { "ownership", "Ownership",  Color(200, 150, 255) },
    { "relations", "Relations",  Color(120, 200, 220) },
    { "keyvalues", "KeyValues",  Color(180, 180, 180) },
    { "meta",      "Meta",       Color(120, 200, 220) }
}
