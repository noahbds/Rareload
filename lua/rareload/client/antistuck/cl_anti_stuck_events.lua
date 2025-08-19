RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckDebug = RARELOAD.AntiStuckDebug or {}
RARELOAD.AntiStuckEvents = RARELOAD.AntiStuckEvents or {}

net.Receive("RareloadOpenAntiStuckDebug", function()
    if RARELOAD and RARELOAD.AntiStuckDebug and RARELOAD.AntiStuckDebug.OpenPanel then
        RARELOAD.AntiStuckDebug.OpenPanel()
    else
        notification.AddLegacy("[RARELOAD] Error: Debug panel function not available", NOTIFY_ERROR, 5)
    end
end)

hook.Add("RareloadProfileChanged", "RefreshAntiStuckPanel", function(profileName, profile)
    print("[RARELOAD] Profile changed to: " .. (profileName or "unknown") .. ", refreshing anti-stuck panel")

    if profileName then
        net.Start("RareloadSyncServerProfile")
        net.WriteString(profileName)
        net.SendToServer()
    end

    if RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.LoadMethods then
        RARELOAD.AntiStuckData.LoadMethods()
    end

    if profile and profile.methods then
        for _, method in ipairs(profile.methods) do
            if method.enabled == nil then
                method.enabled = true
            end
        end
        print("[RARELOAD] Sending methods from profile '" .. profileName .. "' to server")
        net.Start("RareloadAntiStuckMethods")
        net.WriteTable(profile.methods)
        net.SendToServer()
    elseif RARELOAD.AntiStuck.profileSystem and RARELOAD.AntiStuck.profileSystem.GetCurrentProfilemethods then
        local methods = RARELOAD.AntiStuck.profileSystem.GetCurrentProfilemethods()
        if methods and #methods > 0 then
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

    if RARELOAD.AntiStuckDebug and RARELOAD.AntiStuckDebug.currentFrame and IsValid(RARELOAD.AntiStuckDebug.currentFrame) then
        print("[RARELOAD] Anti-stuck panel is open, refreshing method list")
        if RARELOAD.AntiStuckDebug.RefreshMethodList then
            RARELOAD.AntiStuckDebug.RefreshMethodList()
        end

        if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateProfileNotification then
            local frame = RARELOAD.AntiStuckDebug.currentFrame
            RARELOAD.AntiStuckComponents.CreateProfileNotification(frame, profileName, profile.displayName)
        end
    end
end)

hook.Add("Initialize", "RareloadAntiStuckEvents", function()
    if RARELOAD.RegisterFonts then
        RARELOAD.RegisterFonts()
    end

    if RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.LoadMethods then
        RARELOAD.AntiStuckData.LoadMethods()
    end
end)
