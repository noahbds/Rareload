RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}

include("rareload/client/admin/admin_theme.lua")
include("rareload/client/admin/admin_utils.lua")
include("rareload/client/admin/admin_networking.lua")
include("rareload/client/admin/admin_player_list.lua")
include("rareload/client/admin/admin_permissions.lua")
include("rareload/client/admin/admin_panel_main.lua")

function RARELOAD.AdminPanel.Open()
    if IsValid(RARELOAD.AdminPanel.Frame) then
        RARELOAD.AdminPanel.Frame:Remove()
    end

    RARELOAD.AdminPanel.Frame = vgui.Create("RareloadAdminPanel")
    return RARELOAD.AdminPanel.Frame
end
