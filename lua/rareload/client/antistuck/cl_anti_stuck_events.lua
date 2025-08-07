-- Anti-Stuck Panel Event Handlers
-- Network handlers, hooks, and console commands

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckDebug = RARELOAD.AntiStuckDebug or {}
RARELOAD.AntiStuckEvents = RARELOAD.AntiStuckEvents or {}

-- Network message handler for opening the debug panel
net.Receive("RareloadOpenAntiStuckDebug", function()
    if RARELOAD and RARELOAD.AntiStuckDebug and RARELOAD.AntiStuckDebug.OpenPanel then
        RARELOAD.AntiStuckDebug.OpenPanel()
    else
        notification.AddLegacy("[RARELOAD] Error: Debug panel function not available", NOTIFY_ERROR, 5)
    end
end)

-- Hook to refresh panel when profile changes
hook.Add("RareloadProfileChanged", "RefreshAntiStuckPanel", function(profileName, profile)
    print("[RARELOAD] Profile changed to: " .. (profileName or "unknown") .. ", refreshing anti-stuck panel")

    -- Notify server of profile change so it updates its current profile tracking
    if profileName then
        net.Start("RareloadSyncServerProfile")
        net.WriteString(profileName)
        net.SendToServer()
    end

    -- Reload methods from the new profile
    if RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.LoadMethods then
        RARELOAD.AntiStuckData.LoadMethods()
    end

    -- Send the new profile's methods to server to ensure correct order
    if profile and profile.methods then
        -- Ensure all methods have enabled field before sending
        for _, method in ipairs(profile.methods) do
            if method.enabled == nil then
                method.enabled = true
            end
        end
        print("[RARELOAD] Sending methods from profile '" .. profileName .. "' to server")
        net.Start("RareloadAntiStuckMethods")
        net.WriteTable(profile.methods)
        net.SendToServer()
    elseif profileSystem and profileSystem.GetCurrentProfilemethods then
        -- Fallback to getting methods from profile system
        local methods = profileSystem.GetCurrentProfilemethods()
        if methods and #methods > 0 then
            -- Ensure all methods have enabled field
            for _, method in ipairs(methods) do
                if method.enabled == nil then
                    method.enabled = true
                end
            end
            print("[RARELOAD] Sending current profile methods to server")
            net.Start("RareloadAntiStuckMethods")
            net.WriteTable(methods)
            net.SendToServer()
        end
    end

    -- Refresh the panel if it's currently open
    if RARELOAD.AntiStuckDebug and RARELOAD.AntiStuckDebug.currentFrame and IsValid(RARELOAD.AntiStuckDebug.currentFrame) then
        print("[RARELOAD] Anti-stuck panel is open, refreshing method list")
        if RARELOAD.AntiStuckDebug.RefreshMethodList then
            RARELOAD.AntiStuckDebug.RefreshMethodList()
        end

        -- Show a brief notification that the panel was refreshed
        if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateProfileNotification then
            local frame = RARELOAD.AntiStuckDebug.currentFrame
            RARELOAD.AntiStuckComponents.CreateProfileNotification(frame, profileName, profile.displayName)
        end
    end
end)

-- Initialize event handling
hook.Add("Initialize", "RareloadAntiStuckEvents", function()
    if RARELOAD.RegisterFonts then
        RARELOAD.RegisterFonts()
    end

    if RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.LoadMethods then
        RARELOAD.AntiStuckData.LoadMethods()
    end
end)

-- Note: Console command registration is handled in cl_rareload_antistuck_init.lua
-- to avoid duplicate command registrations
