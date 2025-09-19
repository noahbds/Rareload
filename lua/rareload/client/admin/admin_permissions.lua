RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.AdminPanel.Permissions = RARELOAD.AdminPanel.Permissions or {}

-- Create the permissions panel
function RARELOAD.AdminPanel.Permissions.Create(parent, onSavePermissions)
    local THEME = RARELOAD.AdminPanel.Theme.COLORS
    local DrawRoundedBoxEx = RARELOAD.AdminPanel.Theme.DrawRoundedBoxEx

    ---@class DPanel
    local permPanel = vgui.Create("DPanel", parent)
    permPanel:Dock(FILL)
    permPanel:DockMargin(0, 0, 0, 0)
    permPanel.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panel, true, true, true, true)
    end

    local noPlayerSelectedLabel = vgui.Create("DPanel", permPanel)
    noPlayerSelectedLabel:Dock(FILL)
    noPlayerSelectedLabel:DockMargin(20, 20, 20, 20)
    noPlayerSelectedLabel.Paint = function(pnl, w, h)
        local pulseIntensity = math.abs(math.sin(CurTime() * 1.5)) * 0.5 + 0.5

        local boxW, boxH = w * 0.8, h * 0.6
        local boxX, boxY = (w - boxW) / 2, (h - boxH) / 2
        DrawRoundedBoxEx(0, boxX, boxY, boxW, boxH, THEME.panelLight, true, true, true, true)

        surface.SetDrawColor(THEME.textSecondary)
        surface.SetMaterial(Material("icon16/user.png"))
        surface.DrawTexturedRect(w / 2 - 16, boxY + boxH * 0.3 - 16, 32, 32)

        draw.SimpleText("Select a player to edit permissions", "DermaLarge", w / 2, boxY + boxH * 0.6,
            Color(THEME.text.r, THEME.text.g, THEME.text.b, 180 + 75 * pulseIntensity),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        draw.SimpleText("Players are shown in the left panel", "DermaDefault", w / 2, boxY + boxH * 0.6 + 30,
            THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        surface.SetDrawColor(THEME.textSecondary)
        local arrowX = boxX - 40 + math.sin(CurTime() * 3) * 10
        local arrowY = h / 2
        surface.DrawLine(arrowX + 30, arrowY, arrowX, arrowY)
        surface.DrawLine(arrowX + 10, arrowY - 10, arrowX, arrowY)
        surface.DrawLine(arrowX + 10, arrowY + 10, arrowX, arrowY)
    end

    -- Permissions container
    local permContainer = vgui.Create("DPanel", permPanel)
    permContainer:Dock(FILL)
    permContainer:DockMargin(15, 15, 15, 15)
    permContainer.Paint = function() end
    permContainer:SetVisible(false)

    -- Player info section
    local playerInfo = vgui.Create("DPanel", permContainer)
    playerInfo:Dock(TOP)
    playerInfo:SetTall(90)
    playerInfo:DockMargin(0, 0, 0, 10)
    playerInfo.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panelLight, true, true, true, true)
    end

    local playerAvatar = vgui.Create("AvatarImage", playerInfo)
    playerAvatar:SetSize(64, 64)
    playerAvatar:SetPos(13, 13)

    local avatarBorder = vgui.Create("DPanel", playerInfo)
    avatarBorder:SetSize(70, 70)
    avatarBorder:SetPos(10, 10)
    avatarBorder:MoveToBack()
    avatarBorder.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.accent, true, true, true, true)
    end

    local playerName = vgui.Create("DLabel", playerInfo)
    playerName:SetFont("DermaLarge")
    playerName:SetTextColor(THEME.textHighlight)
    playerName:SetPos(90, 15)

    local playerSteamID = vgui.Create("DLabel", playerInfo)
    playerSteamID:SetFont("DermaDefault")
    playerSteamID:SetTextColor(THEME.textSecondary)
    playerSteamID:SetPos(90, 45)

    local playerAdminStatus = vgui.Create("DLabel", playerInfo)
    playerAdminStatus:SetFont("DermaDefault")
    playerAdminStatus:SetPos(90, 65)

    -- Permissions header
    local permHeader = vgui.Create("DPanel", permContainer)
    permHeader:Dock(TOP)
    permHeader:SetTall(40)
    permHeader:DockMargin(0, 0, 0, 5)
    permHeader.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.header, true, true, true, true)
        draw.SimpleText("Permissions", "DermaLarge", 15, h / 2, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local legendX = w - 190
        draw.SimpleText("Enabled", "DermaDefault", legendX + 25, h / 2, THEME.success, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.RoundedBoxEx(0, legendX, h / 2 - 8, 20, 16, THEME.success, true, true, true, true)

        legendX = w - 100
        draw.SimpleText("Disabled", "DermaDefault", legendX + 25, h / 2, THEME.textSecondary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.RoundedBoxEx(0, legendX, h / 2 - 8, 20, 16, THEME.panel, true, true, true, true)
    end

    -- Permissions list
    local permList = vgui.Create("DScrollPanel", permContainer)
    permList:Dock(FILL)
    permList:DockMargin(0, 5, 0, 10)

    local permScrollBar = permList:GetVBar()
    permScrollBar:SetWide(8)
    permScrollBar:SetHideButtons(true)
    permScrollBar.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(THEME.background.r, THEME.background.g, THEME.background.b, 100))
    end
    permScrollBar.btnGrip.Paint = function(_, w, h)
        draw.RoundedBox(0, 2, 0, w - 4, h, THEME.accent)
    end

    -- Save button
    local saveButton = vgui.Create("DButton", permContainer)
    saveButton:SetText("Save Changes")
    saveButton:SetFont("DermaDefaultBold")
    saveButton:SetTextColor(Color(255, 255, 255))
    saveButton:Dock(BOTTOM)
    saveButton:SetTall(40)
    saveButton:DockMargin(0, 10, 0, 0)

    saveButton.Paint = function(pnl, w, h)
        local btnColor = THEME.success
        if pnl:IsHovered() then
            btnColor = Color(btnColor.r * 1.1, btnColor.g * 1.1, btnColor.b * 1.1)
            surface.SetDrawColor(btnColor.r, btnColor.g, btnColor.b, 30)
            surface.DrawRect(0, 0, w, h)
        end

        if pnl:IsDown() then
            btnColor = Color(btnColor.r * 0.9, btnColor.g * 0.9, btnColor.b * 0.9)
        end

        DrawRoundedBoxEx(0, 0, 0, w, h, btnColor, true, true, true, true)

        surface.SetDrawColor(255, 255, 255, 200)
        surface.SetMaterial(Material("icon16/disk.png"))
        surface.DrawTexturedRect(w / 2 - 60, h / 2 - 8, 16, 16)
    end
    saveButton.DoClick = function()
        if onSavePermissions then
            onSavePermissions()
        end
    end

    -- Store references
    permPanel.noPlayerSelectedLabel = noPlayerSelectedLabel
    permPanel.permContainer = permContainer
    permPanel.playerInfo = playerInfo
    permPanel.playerAvatar = playerAvatar
    permPanel.playerName = playerName
    permPanel.playerSteamID = playerSteamID
    permPanel.playerAdminStatus = playerAdminStatus
    permPanel.permList = permList
    permPanel.saveButton = saveButton
    permPanel.checkboxes = {}

    -- Show player selection
    function permPanel:ShowPlayerSelection()
        self.noPlayerSelectedLabel:SetVisible(true)
        self.permContainer:SetVisible(false)
    end

    -- Show permissions for player
    function permPanel:ShowPermissions(steamID, playerData)
        self.permContainer:SetVisible(true)
        self.noPlayerSelectedLabel:SetVisible(false)

        self.playerInfo:SetAlpha(0)
        self.playerInfo:AlphaTo(255, 0.3, 0)

        if playerData.isOnline and IsValid(playerData.player) then
            self.playerAvatar:SetPlayer(playerData.player, 64)
        else
            self.playerAvatar:SetSteamID(steamID, 64)
        end

        self.playerName:SetText(playerData.nick)
        self.playerName:SizeToContents()

        self.playerSteamID:SetText(steamID)
        self.playerSteamID:SizeToContents()

        local adminStatus = ""
        local statusColor = THEME.player
        if playerData.isSuperAdmin then
            adminStatus = "SuperAdmin (All permissions granted automatically)"
            statusColor = THEME.superadmin
        elseif playerData.isAdmin then
            adminStatus = "Admin"
            statusColor = THEME.admin
        else
            adminStatus = playerData.isBot and "Bot" or "Player"
            statusColor = THEME.player
        end

        if not playerData.isOnline then
            adminStatus = adminStatus .. " (Offline)"
            if playerData.lastSeen then
                adminStatus = adminStatus .. " - Last seen: " .. os.date("%Y-%m-%d %H:%M", playerData.lastSeen)
            end
            statusColor = Color(statusColor.r, statusColor.g, statusColor.b, 180)
        end

        self.playerAdminStatus:SetText(adminStatus)
        self.playerAdminStatus:SetTextColor(statusColor)
        self.playerAdminStatus:SizeToContents()

        self:RefreshPermissions(steamID, playerData)
    end

    -- Show error message
    function permPanel:ShowError(message, details)
        self.noPlayerSelectedLabel:SetVisible(true)
        self.permContainer:SetVisible(false)

        self.noPlayerSelectedLabel.Paint = function(pnl, w, h)
            local boxW, boxH = w * 0.8, h * 0.6
            local boxX, boxY = (w - boxW) / 2, (h - boxH) / 2
            DrawRoundedBoxEx(0, boxX, boxY, boxW, boxH, THEME.panelLight, true, true, true, true)

            surface.SetDrawColor(THEME.warning)
            surface.SetMaterial(Material("icon16/error.png"))
            surface.DrawTexturedRect(w / 2 - 16, boxY + boxH * 0.3 - 16, 32, 32)

            draw.SimpleText(message, "DermaLarge", w / 2, boxY + boxH * 0.6,
                THEME.warning, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            if details then
                draw.SimpleText(details, "DermaDefault", w / 2, boxY + boxH * 0.6 + 30,
                    THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- Refresh permissions list
    function permPanel:RefreshPermissions(steamID, playerData)
        self.permList:Clear()
        self.checkboxes = {}

        if not RARELOAD.Permissions.DEFS then
            self:ShowError("Error: Permission definitions not loaded!", "Attempting to load permissions from server...")

            net.Start("RareloadRequestPermissions")
            net.SendToServer()
            return
        end

        local permCategories = RARELOAD.AdminPanel.Utils.CategorizePermissions()

        for catName, perms in pairs(permCategories) do
            if table.Count(perms) > 0 then
                local catDisplayName, catColor = RARELOAD.AdminPanel.Utils.GetCategoryInfo(catName)

                local categoryPanel = vgui.Create("DPanel", self.permList)
                categoryPanel:Dock(TOP)
                categoryPanel:SetTall(30)
                categoryPanel:DockMargin(5, 5, 5, 0)
                categoryPanel.Paint = function(pnl, w, h)
                    DrawRoundedBoxEx(0, 0, 0, w, h, catColor, true, true, true, true)
                    draw.SimpleText(catDisplayName, "DermaDefaultBold", 10, h / 2, THEME.textHighlight, TEXT_ALIGN_LEFT,
                        TEXT_ALIGN_CENTER)
                end

                for permName, permData in SortedPairs(perms) do
                    self:AddPermissionRow(permName, permData, playerData, steamID)
                end
            end
        end
    end

    -- Add permission row
    function permPanel:AddPermissionRow(permName, permData, playerData, steamID)
        local permissionPanel = vgui.Create("DPanel", self.permList)
        permissionPanel:Dock(TOP)
        permissionPanel:DockMargin(5, 5, 5, 5)
        permissionPanel:SetTall(50)

        permissionPanel.hoverFrac = 0
        permissionPanel.Paint = function(pnl, w, h)
            pnl.hoverFrac = Lerp(FrameTime() * 8, pnl.hoverFrac, pnl:IsHovered() and 1 or 0)

            local baseColor = THEME.panelLight
            if pnl.hoverFrac > 0 then
                baseColor = RARELOAD.AdminPanel.Theme.LerpColor(pnl.hoverFrac, baseColor, THEME.panelHover)
            end

            DrawRoundedBoxEx(0, 0, 0, w, h, baseColor, true, true, true, true)
        end

        local permTitle = vgui.Create("DLabel", permissionPanel)
        permTitle:SetText(permData.name)
        permTitle:SetFont("DermaDefaultBold")
        permTitle:SetTextColor(THEME.text)
        permTitle:SetPos(10, 8)
        permTitle:SizeToContents()

        local permDesc = vgui.Create("DLabel", permissionPanel)
        permDesc:SetText(permData.desc)
        permDesc:SetFont("DermaDefault")
        permDesc:SetTextColor(THEME.textSecondary)
        permDesc:SetPos(10, 27)
        permDesc:SizeToContents()

        local toggleSwitch = vgui.Create("DButton", permissionPanel)
        toggleSwitch:SetSize(50, 26)
        toggleSwitch:SetText("")
        toggleSwitch:SetPos(permissionPanel:GetWide() - 70, 12)

        local isEnabled = RARELOAD.AdminPanel.Utils.GetPermissionValue(steamID, permName)
        toggleSwitch.switched = isEnabled
        toggleSwitch.switchFrac = isEnabled and 1 or 0

        toggleSwitch.Paint = function(pnl, w, h)
            local disabled = playerData.isSuperAdmin

            pnl.switchFrac = Lerp(FrameTime() * 6, pnl.switchFrac, pnl.switched and 1 or 0)

            local trackColor = pnl.switched and THEME.success or THEME.panel
            if disabled then trackColor = THEME.superadmin end

            DrawRoundedBoxEx(0, 0, 0, w, h, trackColor, true, true, true, true)

            local knobSize = h - 6
            local knobX = 3 + (w - knobSize - 6) * pnl.switchFrac

            knobX = math.Clamp(knobX, 3, w - knobSize - 3)

            if pnl:IsHovered() and not disabled then
                surface.SetDrawColor(THEME.textHighlight.r, THEME.textHighlight.g, THEME.textHighlight.b, 100)
                surface.DrawOutlinedRect(knobX, 3, knobSize, knobSize, 1)
            end

            DrawRoundedBoxEx(0, knobX, 3, knobSize, knobSize, THEME.textHighlight, true, true, true, true)
        end

        toggleSwitch.DoClick = function(pnl)
            local disabled = playerData.isSuperAdmin
            if disabled then return end

            pnl.switched = not pnl.switched
            surface.PlaySound(pnl.switched and "ui/buttonclick.wav" or "ui/buttonclickrelease.wav")
        end

        self.checkboxes[permName] = toggleSwitch

        local disabled = playerData.isSuperAdmin
        if disabled then
            toggleSwitch:SetEnabled(false)
            toggleSwitch.switched = true

            local lockIcon = vgui.Create("DImage", permissionPanel)
            lockIcon:SetSize(16, 16)
            lockIcon:SetPos(permissionPanel:GetWide() - 95, 18)
            lockIcon:SetImage("icon16/lock.png")

            local superAdminHint = vgui.Create("DLabel", permissionPanel)
            superAdminHint:SetPos(10, permDesc:GetTall() + 26)
            superAdminHint:SetText("SuperAdmin: Always granted")
            superAdminHint:SetTextColor(THEME.superadmin)
            superAdminHint:SetFont("DermaDefaultBold")
            superAdminHint:SizeToContents()
        end

        permissionPanel.PerformLayout = function(pnl, w, h)
            toggleSwitch:SetPos(w - 60, 12)
        end

        return permissionPanel
    end

    return permPanel
end
