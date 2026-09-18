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
SED.SavedLookupDirty = true       -- rebuild the saved lookup on next use (set by position syncs)
SED.SAVED_LOOKUP_FALLBACK = 10    -- safety re-sync interval if a dirty trigger is ever missed
SED.LAST_RESCAN = 0
SED.RESCAN_INTERVAL = 0.5
SED.INFO_CACHE_LIFETIME = 5.0
SED.MAX_DRAW_PER_FRAME = 16
SED.BASE_DRAW_DISTANCE = 500
SED.DRAW_DISTANCE_SQR = SED.BASE_DRAW_DISTANCE * SED.BASE_DRAW_DISTANCE
SED.INTERACT_DIST = 2000
SED.INTERACT_DIST_SQR = SED.INTERACT_DIST * SED.INTERACT_DIST
SED.PHANTOM_CULL_DIST = 10000
SED.PHANTOM_CULL_DIST_SQR = SED.PHANTOM_CULL_DIST * SED.PHANTOM_CULL_DIST
SED.BASE_SCALE = 0.11
SED.MIN_SCALE = 0.05
SED.MAX_SCALE = 0.25
SED.PANEL_WORLD_WIDTH_FACTOR = 1.15 -- panel world width ≈ this × the entity's max OBB dimension
SED.PANEL_MIN_WORLD_WIDTH    = 42   -- floor (world units) so tiny props stay readable
SED.PANEL_MAX_WORLD_WIDTH    = 130  -- ceiling (world units) so huge entities don't get giant panels
SED.PANEL_REF_WIDTH          = 480  -- fallback panel pixel width if a caller omits it
SED.PANEL_CLUSTER_DIST = 8    -- extra horizontal gap (beyond both footprint radii) to still group; ~touching only
SED.PANEL_EYE_BAND = 150
SED.MAX_VISIBLE_LINES = 7
SED.SCROLL_SPEED = 3
SED.PILE_Z_GATE     = 8     -- extra vertical gap (beyond both half-heights) to still group; ~touching only
SED.PILE_MAX_PEEK   = 2     -- how many cards peek out behind the active one
SED.PILE_ANIM_DUR   = 0.28  -- card-swap animation length (seconds)
SED.PILE_PEEK_DX    = 26    -- per-peek horizontal offset (panel px, up-right)
SED.PILE_PEEK_DY    = 22    -- per-peek vertical offset (panel px, up-right)
SED.PILE_PEEK_SCALE = 0.94  -- per-peek scale falloff
SED.PileState       = {}    -- key -> { active, anim, lastSeen }: persistent per-pile flip state
SED.ActiveGroups    = {}    -- frame-scoped list of the current groups
SED.CandidateGroup  = nil   -- group currently under the crosshair (nil when none)
SED.FocusedPileMulti = false -- true while the inspected pile has >= 2 cards (◄ ► flips them)
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
SED.PreviewItems = SED.PreviewItems or {} -- Save Timeline preview phantoms (rendered via QueueAllSavedPanels)
SED.PreviewRecordsByID = SED.PreviewRecordsByID or {} -- id -> saved record, for preview panel interaction
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
    -- second element is a localization key, resolved via RARELOAD.L at draw time
    { "basic",     "sed.cat.basic",     Color(64, 152, 255) },
    { "position",  "sed.cat.position",  Color(60, 179, 113) },
    { "saved",     "sed.cat.saved",     Color(255, 140, 40) },
    { "state",     "sed.cat.state",     Color(218, 165, 32) },
    { "physics",   "sed.cat.physics",   Color(255, 120, 90) },
    { "visual",    "sed.cat.visual",    Color(147, 112, 219) },
    { "ownership", "sed.cat.ownership", Color(200, 150, 255) },
    { "keyvalues", "sed.cat.keyvalues", Color(180, 180, 180) },
    { "meta",      "sed.cat.meta",      Color(120, 200, 220) }
}

SED.VEHICLE_CATEGORIES = {
    { "basic",      "sed.cat.basic",      Color(64, 152, 255) },
    { "vehicle",    "sed.cat.vehicle",    Color(0, 200, 255) },
    { "drivetrain", "sed.cat.drivetrain", Color(255, 170, 50) },
    { "combat",     "sed.cat.combat",     Color(255, 90, 140) },
    { "systems",    "sed.cat.systems",    Color(120, 220, 150) },
    { "state",      "sed.cat.state",      Color(218, 165, 32) },
    { "position",   "sed.cat.position",   Color(60, 179, 113) },
    { "saved",      "sed.cat.saved",      Color(255, 140, 40) },
    { "physics",    "sed.cat.physics",    Color(255, 120, 90) },
    { "visual",     "sed.cat.visual",     Color(147, 112, 219) },
    { "ownership",  "sed.cat.ownership",  Color(200, 150, 255) },
    { "keyvalues",  "sed.cat.keyvalues",  Color(180, 180, 180) },
    { "meta",       "sed.cat.meta",       Color(120, 200, 220) }
}

SED.NPC_CATEGORIES = {
    { "basic",     "sed.cat.basic",     Color(64, 152, 255) },
    { "position",  "sed.cat.position",  Color(60, 179, 113) },
    { "saved",     "sed.cat.saved",     Color(255, 140, 40) },
    { "state",     "sed.cat.state",     Color(218, 165, 32) },
    { "behavior",  "sed.cat.behavior",  Color(214, 80, 80) },
    { "combat",    "sed.cat.combat",    Color(255, 90, 140) },
    { "visual",    "sed.cat.visual",    Color(147, 112, 219) },
    { "vjbase",    "sed.cat.vjbase",    Color(100, 255, 150) },
    { "weapons",   "sed.cat.weapons",   Color(255, 200, 100) },
    { "ai",        "sed.cat.ai",        Color(150, 200, 255) },
    { "sounds",    "sed.cat.sounds",    Color(200, 150, 255) },
    { "ownership", "sed.cat.ownership", Color(200, 150, 255) },
    { "relations", "sed.cat.relations", Color(120, 200, 220) },
    { "keyvalues", "sed.cat.keyvalues", Color(180, 180, 180) },
    { "meta",      "sed.cat.meta",      Color(120, 200, 220) }
}

-- Stable identity of a saved record, matching the id the interaction lookups expect
-- (object phantoms use rec.id, player phantoms use "phantom_"..steamID, previews their own id).
function SED.SavedRecID(saved)
    if not saved then return "unknown?" end
    return saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID or
        ((saved.class or saved.Class or saved.ClassName or "unknown") .. "?")
end

-- Class-name fallback for vehicle detection, used only when DataUtils can't
-- resolve the class (e.g. the addon is not installed on this client). Covers
-- stock prop_vehicle_* plus the common framework class prefixes.
local VEHICLE_CLASS_PATTERNS = {
    "vehicle", "jeep", "airboat",
    "^lvs_", "^lfs_", "_lfs_", "lunasflightschool",
    "fphysics", "^wac_", "^glide_", "^sent_sakarias_car",
}

-- Single source of truth for "is this saved record (or its live entity) a
-- vehicle?" Replaces the detection hack that used to be copy-pasted across the
-- interaction, renderer and collector files (including guessed .IsLVS/.IsWAC
-- fields that DataUtils.IsVehicleEntity already covers).
function SED.IsVehicleRecord(saved, liveEnt)
    if saved and saved.isVehicle == true then return true end

    local DU = RARELOAD.DataUtils
    if IsValid(liveEnt) then
        if DU and DU.IsVehicleEntity and DU.IsVehicleEntity(liveEnt) then return true end
        if isfunction(liveEnt.IsVehicle) and liveEnt:IsVehicle() then return true end
    end

    local class = saved and (saved.class or saved.Class or saved.ClassName)
    if not isstring(class) then return false end
    if DU and DU.ClassLooksLikeVehicle and DU.ClassLooksLikeVehicle(class) then return true end

    class = string.lower(class)
    for _, pat in ipairs(VEHICLE_CLASS_PATTERNS) do
        if string.find(class, pat) then return true end
    end
    return false
end
