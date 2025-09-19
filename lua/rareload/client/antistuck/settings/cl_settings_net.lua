-- Networking and console commands extracted from monolithic file
---@diagnostic disable: inject-field, undefined-field

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}
RARELOAD.AntiStuck.profileSystem = RARELOAD.AntiStuck.profileSystem or {}

net.Receive("RareloadAntiStuckConfig", function()
    local tbl = net.ReadTable()
    if not istable(tbl) then return end
    local settings = istable(tbl.settings) and tbl.settings or tbl
    RARELOAD.AntiStuckSettings._loadedSettings = settings
    if RARELOAD.AntiStuckSettings.RefreshSettingsPanel then
        RARELOAD.AntiStuckSettings.RefreshSettingsPanel()
    end
end)

net.Receive("RareloadReceiveSharedProfile", function()
    local profile = net.ReadTable()
    if RARELOAD.AntiStuck and RARELOAD.AntiStuck.profileSystem and RARELOAD.AntiStuck.profileSystem.ReceiveSharedProfile then
        RARELOAD.AntiStuck.profileSystem.ReceiveSharedProfile(profile)
    end
end)

concommand.Add("rareload_antistuck_autosave_server", function(ply, _, args)
    local enable = tobool(args and args[1])
    net.Start("RareloadAntiStuckSettings")
    net.WriteString("toggle_autosave")
    net.WriteBool(enable)
    net.SendToServer()
end)

concommand.Add("rareload_test_profile_system", function()
    net.Start("RareloadAntiStuckSettings")
    net.WriteString("request_config")
    net.SendToServer()
end)
