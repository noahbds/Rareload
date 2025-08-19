-- Defaults, methods and metadata for Anti-Stuck Settings (extracted)
---@diagnostic disable: inject-field, undefined-field, param-type-mismatch, assign-type-mismatch

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

local THEME = THEME or {}

-- Default settings table
Default_Anti_Stuck_Settings = {
    MAX_UNSTUCK_ATTEMPTS = 35,
    MAX_SEARCH_TIME = 1.5,
    RETRY_DELAY = 0.05,
    DEBUG_LOGGING = false,
    ENABLE_CACHE = true,
    CACHE_DURATION = 900,

    SAFE_DISTANCE = 48,
    PLAYER_HULL_TOLERANCE = 8,
    MIN_GROUND_DISTANCE = 12,
    MAP_BOUNDS_PADDING = 128,

    VERTICAL_SEARCH_RANGE = 2048,
    HORIZONTAL_SEARCH_RANGE = 1536,
    MAX_TRACE_DISTANCE = 2048,
    NODE_SEARCH_RADIUS = 1024,
    ENTITY_SEARCH_RADIUS = 384,

    SPAWN_POINT_OFFSET_Z = 24,
    MAP_ENTITY_OFFSET_Z = 40,
    NAV_AREA_OFFSET_Z = 20,
    NAVMESH_HEIGHT_OFFSET = 24,
    FALLBACK_HEIGHT = 8192,

    GRID_RESOLUTION = 32,
    SEARCH_RESOLUTIONS = { 32, 64, 128, 256 },
    SPIRAL_RINGS = 8,
    POINTS_PER_RING = 12,
    MAX_DISTANCE = 1200,
    VERTICAL_STEPS = 7,
    VERTICAL_RANGE = 600,

    DISPLACEMENT_STEP_SIZE = 64,
    DISPLACEMENT_MAX_HEIGHT = 800,
    SPACE_SCAN_ACCURACY = 3,
    EMERGENCY_SAFE_RADIUS = 160,
    RANDOM_ATTEMPTS = 25,

    ADAPTIVE_TIMEOUTS = true,
    PROGRESSIVE_ACCURACY = true,
    EARLY_EXIT_OPTIMIZATION = true,
    DISTANCE_PRIORITY = true,
    SUCCESS_RATE_LEARNING = true,
    PERFORMANCE_MONITORING = true,
}

-- Default methods configuration
Default_Anti_Stuck_Methods = {
    { name = "Cached Positions",   func = "TryCachedPositions",   enabled = true, priority = 5,  description = "Lightning-fast: Use proven safe positions from previous successful unstucks" },
    { name = "mart Displacement",  func = "TryDisplacement",      enabled = true, priority = 10, description = "Ultra-fast: Physics-based intelligent movement with adaptive step sizing" },
    { name = "Navigation Mesh",    func = "TryNodeGraph",         enabled = true, priority = 15, description = "Optimal: Leverage Source engine navigation system for perfect pathfinding" },
    { name = "Map Entities",       func = "TryMapEntities",       enabled = true, priority = 20, description = "Fast: Smart positioning near functional map entities and spawn points" },
    { name = "3D Space Scan",      func = "Try3DSpaceScan",       enabled = true, priority = 25, description = "Thorough: Advanced volumetric analysis with adaptive precision" },
    { name = "World Brushes",      func = "TryWorldBrushes",      enabled = true, priority = 30, description = "Smart: Geometry-aware positioning using world architecture" },
    { name = "Systematic Grid",    func = "TrySystematicGrid",    enabled = true, priority = 35, description = "Comprehensive: Methodical full-area coverage with adaptive resolution" },
    { name = "Spawn Points",       func = "TrySpawnPoints",       enabled = true, priority = 40, description = "Reliable: Map-defined safe zones with validity verification" },
    { name = "Emergency Teleport", func = "TryEmergencyTeleport", enabled = true, priority = 45, description = "Failsafe: Guaranteed positioning system for critical situations" }
}

-- Setting descriptions and ranges for UI/validation
RARELOAD.AntiStuckSettings.Descriptions = {
    MAX_UNSTUCK_ATTEMPTS = "Maximum attempts to find safe position (Lower = Faster, Higher = More thorough)",
    MAX_SEARCH_TIME = "Maximum time spent per unstuck attempt (Shorter = More responsive)",
    RETRY_DELAY = "Delay between method attempts (Lower = Faster resolution)",
    DEBUG_LOGGING = "Enable detailed debug output (Disable for better performance)",
    ENABLE_CACHE = "Cache successful positions for instant reuse (Major performance boost)",
    CACHE_DURATION = "How long to keep cached positions (Longer = Better performance)",

    SAFE_DISTANCE = "Minimum clearance from obstacles (Higher = Safer positioning)",
    PLAYER_HULL_TOLERANCE = "Extra space around player collision box (Prevents tight fits)",
    MIN_GROUND_DISTANCE = "Required distance from ground surface (Prevents underground)",
    MAP_BOUNDS_PADDING = "Safety margin from map edges (Prevents out-of-bounds)",

    VERTICAL_SEARCH_RANGE = "Maximum upward/downward search distance",
    HORIZONTAL_SEARCH_RANGE = "Maximum sideways search radius",
    MAX_TRACE_DISTANCE = "Collision detection range (Lower = Better performance)",
    NODE_SEARCH_RADIUS = "Navigation mesh search radius",
    ENTITY_SEARCH_RADIUS = "Map entity detection range",

    SPAWN_POINT_OFFSET_Z = "Height offset from spawn points (Prevents spawn camping)",
    MAP_ENTITY_OFFSET_Z = "Clearance from map entities (Safer positioning)",
    NAV_AREA_OFFSET_Z = "Navigation area height adjustment",
    NAVMESH_HEIGHT_OFFSET = "NavMesh positioning offset",
    FALLBACK_HEIGHT = "Emergency teleport altitude (Last resort height)",

    GRID_RESOLUTION = "Grid search precision (Lower = Finer detail, Slower)",
    SPIRAL_RINGS = "Spiral search ring count (More rings = Better coverage)",
    POINTS_PER_RING = "Points checked per spiral ring (Higher = More thorough)",
    MAX_DISTANCE = "Maximum search radius from stuck position",
    VERTICAL_STEPS = "Vertical search precision steps",
    VERTICAL_RANGE = "Total vertical search span",
    SEARCH_RESOLUTIONS = "Progressive grid sizes (Starts fine, gets broader)",

    DISPLACEMENT_STEP_SIZE = "Physics displacement increment size",
    DISPLACEMENT_MAX_HEIGHT = "Maximum height for displacement checks",
    SPACE_SCAN_ACCURACY = "3D scan detail level (1=Fast, 5=Thorough)",
    EMERGENCY_SAFE_RADIUS = "Emergency positioning safety zone",
    RANDOM_ATTEMPTS = "Random method attempt count",

    ADAPTIVE_TIMEOUTS = "Smart timeout adjustment based on performance",
    PROGRESSIVE_ACCURACY = "Start fast, get more accurate if needed",
    EARLY_EXIT_OPTIMIZATION = "Exit immediately when good position found",
    DISTANCE_PRIORITY = "Prefer closer positions over distant ones",
    SUCCESS_RATE_LEARNING = "Learn from method success rates",
    PERFORMANCE_MONITORING = "Real-time performance optimization"
}

RARELOAD.AntiStuckSettings.Ranges = {
    MAX_UNSTUCK_ATTEMPTS = { min = 10, max = 200, step = 1 },
    SAFE_DISTANCE = { min = 16, max = 512, step = 4 },
    VERTICAL_SEARCH_RANGE = { min = 512, max = 8192, step = 64 },
    HORIZONTAL_SEARCH_RANGE = { min = 512, max = 4096, step = 64 },
    NODE_SEARCH_RADIUS = { min = 256, max = 4096, step = 64 },
    CACHE_DURATION = { min = 60, max = 1800, step = 30 },
    MIN_GROUND_DISTANCE = { min = 1, max = 64, step = 1 },
    PLAYER_HULL_TOLERANCE = { min = 1, max = 32, step = 1 },
    MAP_BOUNDS_PADDING = { min = 64, max = 1024, step = 32 },
    GRID_RESOLUTION = { min = 16, max = 256, step = 8 },
    MAX_TRACE_DISTANCE = { min = 1024, max = 8192, step = 128 },
    SPAWN_POINT_OFFSET_Z = { min = 0, max = 128, step = 2 },
    MAP_ENTITY_OFFSET_Z = { min = 0, max = 128, step = 2 },
    NAV_AREA_OFFSET_Z = { min = 0, max = 128, step = 2 },
    RETRY_DELAY = { min = 0.0, max = 2.0, step = 0.05 },
    MAX_SEARCH_TIME = { min = 0.5, max = 10.0, step = 0.1 },
    RANDOM_ATTEMPTS = { min = 10, max = 200, step = 5 },
    ENTITY_SEARCH_RADIUS = { min = 128, max = 2048, step = 32 },
    NAVMESH_HEIGHT_OFFSET = { min = 0, max = 128, step = 2 },
    FALLBACK_HEIGHT = { min = 1024, max = 32768, step = 256 },
    SPIRAL_RINGS = { min = 1, max = 30, step = 1 },
    POINTS_PER_RING = { min = 4, max = 32, step = 1 },
    MAX_DISTANCE = { min = 500, max = 5000, step = 100 },
    VERTICAL_STEPS = { min = 1, max = 20, step = 1 },
    VERTICAL_RANGE = { min = 50, max = 1000, step = 25 },
    DISPLACEMENT_STEP_SIZE = { min = 32, max = 512, step = 16 },
    DISPLACEMENT_MAX_HEIGHT = { min = 200, max = 2000, step = 100 },
    SPACE_SCAN_ACCURACY = { min = 1, max = 5, step = 1 },
    EMERGENCY_SAFE_RADIUS = { min = 50, max = 500, step = 25 }
}

RARELOAD.AntiStuckSettings.Groups = {
    General = {
        "MAX_UNSTUCK_ATTEMPTS", "RETRY_DELAY", "MAX_SEARCH_TIME", "DEBUG_LOGGING", "ENABLE_CACHE", "CACHE_DURATION"
    },
    Search = {
        "SAFE_DISTANCE", "MAX_DISTANCE", "HORIZONTAL_SEARCH_RANGE", "VERTICAL_SEARCH_RANGE",
        "MAX_TRACE_DISTANCE", "MIN_GROUND_DISTANCE", "PLAYER_HULL_TOLERANCE", "MAP_BOUNDS_PADDING"
    },
    Navigation = {
        "NODE_SEARCH_RADIUS", "ENTITY_SEARCH_RADIUS"
    },
    Grid = {
        "GRID_RESOLUTION", "SEARCH_RESOLUTIONS"
    },
    Spiral = {
        "SPIRAL_RINGS", "POINTS_PER_RING"
    },
    Vertical = {
        "VERTICAL_STEPS", "VERTICAL_RANGE"
    },
    Offsets = {
        "SPAWN_POINT_OFFSET_Z", "MAP_ENTITY_OFFSET_Z", "NAV_AREA_OFFSET_Z", "NAVMESH_HEIGHT_OFFSET", "FALLBACK_HEIGHT"
    },
    Methods = {
        "RANDOM_ATTEMPTS"
    },
    ["Method Specific"] = {
        "DISPLACEMENT_STEP_SIZE", "DISPLACEMENT_MAX_HEIGHT", "SPACE_SCAN_ACCURACY", "EMERGENCY_SAFE_RADIUS"
    }
}
