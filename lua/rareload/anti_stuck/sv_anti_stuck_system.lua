RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}

if SERVER then
    -- This file now only ensures the system initializes once. All includes are handled elsewhere.
    RARELOAD.AntiStuck.Initialized = RARELOAD.AntiStuck.Initialized or false
    local function EnsureInit()
        if RARELOAD.AntiStuck.Initialized then return end
        if RARELOAD.AntiStuck.Initialize then
            RARELOAD.AntiStuck.Initialize()
            RARELOAD.AntiStuck.Initialized = true
        end
    end

    hook.Add("Initialize", "RARELOAD_AntiStuck_Init", function()
        timer.Simple(2, EnsureInit)
    end)
    EnsureInit()
end
print("[RARELOAD] Anti-Stuck system loaded")
