RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}

local PANEL = {}

function PANEL:Init()
    local THEME = RARELOAD.AdminPanel.Theme.COLORS
    local DrawRoundedBoxEx = RARELOAD.AdminPanel.Theme.DrawRoundedBoxEx

    self.selectedPlayer = nil
    self.animationTime = 0

    self:SetTitle("")
    self:SetSize(900, 650)
    self:Center()
    self:MakePopup()
    self:SetDraggable(true)
    self:ShowCloseButton(false)
    self:SetBackgroundBlur(true)

    self.startTime = SysTime()

    self.Paint = function(self, w, h)
        Derma_DrawBackgroundBlur(self, self.startTime)

        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.background, true, true, true, true)

        DrawRoundedBoxEx(0, 0, 0, w, 40, THEME.header, true, true, false, false)

        draw.SimpleText("Rareload Admin Panel", "DermaLarge", 20, 20, THEME.textHighlight, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        local version = RARELOAD.version or "v1.0"
        draw.SimpleText(version, "DermaDefault", w - 50, 20, THEME.textSecondary, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        DrawRoundedBoxEx(0, 0, h - 30, w, 30, THEME.header, false, false, true, true)

        draw.SimpleText("By Noahbds • Select a player to edit permissions", "DermaDefault", w / 2, h - 15,
            THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local closeBtn = vgui.Create("DButton", self)
    closeBtn:SetText("")
    closeBtn:SetSize(30, 30)
    closeBtn:SetPos(self:GetWide() - 40, 5)
    closeBtn.Paint = function(pnl, w, h)
        local color = THEME.textSecondary
        if pnl:IsHovered() then
            color = THEME.danger
            surface.SetDrawColor(THEME.danger.r, THEME.danger.g, THEME.danger.b, 40)
            surface.DrawRect(0, 0, w, h)
        end
        surface.SetDrawColor(color)
        surface.DrawLine(8, 8, w - 8, h - 8)
        surface.DrawLine(w - 8, 8, 8, h - 8)
    end
    closeBtn.DoClick = function()
        self:AlphaTo(0, 0.3, 0, function()
            self:Remove()
        end)
        surface.PlaySound("ui/buttonclickrelease.wav")
    end

    local contentPanel = vgui.Create("DPanel", self)
    contentPanel:Dock(FILL)
    contentPanel:DockMargin(15, 50, 15, 40)
    contentPanel.Paint = function() end

    self.playerList = RARELOAD.AdminPanel.PlayerList.Create(contentPanel, function(steamID)
        self:SelectPlayer(steamID)
    end)

    self.permissionsPanel = RARELOAD.AdminPanel.Permissions.Create(contentPanel, function()
        self:SavePermissions()
    end)

    self.permissionsPanel:ShowPlayerSelection()

    self:SetAlpha(0)
    self:AlphaTo(255, 0.3, 0)
    self:RefreshPlayerList()

    net.Start("RareloadRequestPermissions")
    net.SendToServer()

    net.Start("RareloadRequestOfflinePlayerData")
    net.SendToServer()
end

function PANEL:RefreshPlayerList()
    if self.playerList then
        self.playerList:RefreshPlayerList()
    end
end

function PANEL:SelectPlayer(steamID)
    self.selectedPlayer = steamID

    local playerData = RARELOAD.AdminPanel.Utils.GetPlayerData(steamID)

    if not playerData then
        self.permissionsPanel:ShowError("Player not found", "The player may have been removed from records")
        return
    end

    self.permissionsPanel:ShowPermissions(steamID, playerData)
end

function PANEL:SavePermissions()
    if not self.selectedPlayer or not self.permissionsPanel.checkboxes then return end

    local changedCount = 0
    local totalCount = 0

    for permName, toggleBtn in pairs(self.permissionsPanel.checkboxes) do
        totalCount = totalCount + 1
        local currentValue = RARELOAD.AdminPanel.Utils.GetPermissionValue(self.selectedPlayer, permName)
        local newValue = toggleBtn.switched

        if currentValue ~= newValue then
            changedCount = changedCount + 1
            net.Start("RareloadUpdatePermissions")
            net.WriteString(self.selectedPlayer)
            net.WriteString(permName)
            net.WriteBool(newValue)
            net.SendToServer()
        end
    end

    self:ShowSaveMessage(changedCount, totalCount)
end

function PANEL:ShowSaveMessage(changedCount, totalCount)
    local THEME = RARELOAD.AdminPanel.Theme.COLORS
    local DrawRoundedBoxEx = RARELOAD.AdminPanel.Theme.DrawRoundedBoxEx

    local savedMsg = vgui.Create("DPanel", self)
    savedMsg:SetSize(400, 120)
    savedMsg:SetPos(self:GetWide() / 2 - 150, self:GetTall() / 2 - 50)
    savedMsg:SetAlpha(0)

    local msgColor = changedCount > 0 and THEME.success or THEME.accent
    local msgIcon = changedCount > 0 and "icon16/accept.png" or "icon16/information.png"
    local msgText = changedCount > 0
        and "Changes saved successfully!"
        or "No changes were needed"

    local detailText = changedCount > 0
        and changedCount .. " of " .. totalCount .. " permissions updated"
        or "All permissions were already set correctly"

    savedMsg.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panelLight, true, true, true, true)
        surface.SetDrawColor(msgColor.r, msgColor.g, msgColor.b, 40)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(Material(msgIcon))
        surface.DrawTexturedRect(w / 2 - 16, 15, 32, 32)

        draw.SimpleText(msgText, "DermaLarge", w / 2, 60, msgColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(detailText, "DermaDefault", w / 2, 85, THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    savedMsg:AlphaTo(255, 0.3, 0, function()
        savedMsg:AlphaTo(0, 0.3, 1.5, function()
            savedMsg:Remove()
        end)
    end)

    surface.PlaySound(changedCount > 0 and "buttons/button14.wav" or "ui/buttonclickrelease.wav")
end

function PANEL:OnRemove()
end

vgui.Register("RareloadAdminPanel", PANEL, "DFrame")
