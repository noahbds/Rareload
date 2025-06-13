RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.AdminPanel.PlayerList = RARELOAD.AdminPanel.PlayerList or {}

-- Create the player list panel
function RARELOAD.AdminPanel.PlayerList.Create(parent, onPlayerSelected)
    local THEME = RARELOAD.AdminPanel.Theme.COLORS
    local DrawRoundedBoxEx = RARELOAD.AdminPanel.Theme.DrawRoundedBoxEx

    ---@class DPanel
    local playerList = vgui.Create("DPanel", parent)
    playerList:Dock(LEFT)
    playerList:SetWide(280)
    playerList:DockMargin(0, 0, 10, 0)
    playerList.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panel, true, true, true, true)

        surface.SetDrawColor(THEME.accent.r, THEME.accent.g, THEME.accent.b, 40)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Title
    local playerListTitle = vgui.Create("DPanel", playerList)
    playerListTitle:SetText("Players")
    playerListTitle:Dock(TOP)
    playerListTitle:SetTall(40)
    playerListTitle.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.header, true, true, false, false)
        draw.SimpleText("All Players", "DermaLarge", w / 2, h / 2, THEME.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Offline toggle
    local playerToggle = vgui.Create("DPanel", playerList)
    playerToggle:Dock(TOP)
    playerToggle:SetTall(40)
    playerToggle:DockMargin(8, 5, 8, 8)
    playerToggle.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, Color(THEME.panelLight.r + 15, THEME.panelLight.g + 15, THEME.panelLight.b + 15),
            true, true, true, true)

        surface.SetDrawColor(THEME.accent.r, THEME.accent.g, THEME.accent.b, 120)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        surface.SetDrawColor(0, 0, 0, 30)
        surface.DrawRect(1, 1, w - 2, 2)
    end

    local showOfflineToggle = vgui.Create("DButton", playerToggle)
    showOfflineToggle:SetText("")
    showOfflineToggle:Dock(FILL)
    showOfflineToggle:DockMargin(10, 6, 10, 6)
    showOfflineToggle.showOffline = false
    showOfflineToggle.toggleFrac = 0

    showOfflineToggle.Paint = function(pnl, w, h)
        pnl.toggleFrac = Lerp(FrameTime() * 6, pnl.toggleFrac, pnl.showOffline and 1 or 0)

        if pnl:IsHovered() then
            surface.SetDrawColor(255, 255, 255, 10)
            surface.DrawRect(0, 0, w, h)
        end

        local switchW, switchH = 50, 24
        local switchX = w - switchW - 10
        local switchY = (h - switchH) / 2

        local trackColor = pnl.showOffline and THEME.success or
            Color(THEME.panel.r + 30, THEME.panel.g + 30, THEME.panel.b + 30)
        DrawRoundedBoxEx(0, switchX, switchY, switchW, switchH, trackColor, true, true, true, true)

        surface.SetDrawColor(0, 0, 0, 50)
        surface.DrawRect(switchX + 1, switchY + 1, switchW - 2, 2)

        local knobSize = switchH - 6
        local knobX = switchX + 3 + (switchW - knobSize - 6) * pnl.toggleFrac
        DrawRoundedBoxEx(0, knobX, switchY + 3, knobSize, knobSize, THEME.textHighlight, true, true, true, true)

        surface.SetDrawColor(255, 255, 255, 100)
        surface.DrawRect(knobX + 1, switchY + 4, knobSize - 2, 2)

        draw.SimpleText("Show Offline Players", "DermaDefaultBold", 10, h / 2, THEME.text, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        local statusText = pnl.showOffline and "ON" or "OFF"
        local statusColor = pnl.showOffline and THEME.success or THEME.textSecondary
        draw.SimpleText(statusText, "DermaDefaultBold", switchX - 30, h / 2, statusColor, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_CENTER)

        surface.SetDrawColor(THEME.textSecondary)
        surface.SetMaterial(Material("icon16/disconnect.png"))
        surface.DrawTexturedRect(switchX - 50, h / 2 - 8, 16, 16)
    end

    showOfflineToggle.DoClick = function(pnl)
        pnl.showOffline = not pnl.showOffline
        surface.PlaySound(pnl.showOffline and "ui/buttonclick.wav" or "ui/buttonclickrelease.wav")
        playerList:RefreshPlayerList()
    end

    -- Search box
    local searchContainer = vgui.Create("DPanel", playerList)
    searchContainer:Dock(TOP)
    searchContainer:SetTall(50)
    searchContainer:DockMargin(10, 10, 10, 5)
    searchContainer.Paint = function() end

    local searchBox = vgui.Create("DTextEntry", searchContainer)
    searchBox:Dock(FILL)
    searchBox:SetPlaceholderText("Search players...")
    searchBox:SetFont("DermaDefault")
    searchBox.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panelLight, true, true, true, true)
        pnl:DrawTextEntryText(THEME.textHighlight, THEME.accent, THEME.textHighlight)

        if pnl:GetValue() == "" and not pnl:HasFocus() then
            draw.SimpleText(pnl:GetPlaceholderText(), pnl:GetFont(), 5, h / 2, THEME.textSecondary, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
        end

        surface.SetDrawColor(THEME.textSecondary)
        surface.SetMaterial(Material("icon16/magnifier.png"))
        surface.DrawTexturedRect(w - 20, h / 2 - 8, 16, 16)
    end
    searchBox.OnChange = function()
        playerList:RefreshPlayerList()
    end

    -- Scrollable player list
    local playerScroll = vgui.Create("DScrollPanel", playerList)
    playerScroll:Dock(FILL)
    playerScroll:DockMargin(10, 5, 10, 10)

    local scrollBar = playerScroll:GetVBar()
    scrollBar:SetWide(8)
    scrollBar:SetHideButtons(true)
    scrollBar.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(THEME.background.r, THEME.background.g, THEME.background.b, 100))
    end
    scrollBar.btnGrip.Paint = function(_, w, h)
        draw.RoundedBox(0, 2, 0, w - 4, h, THEME.accent)
    end

    -- Store references
    playerList.showOfflineToggle = showOfflineToggle
    playerList.searchBox = searchBox
    playerList.playerScroll = playerScroll
    playerList.onPlayerSelected = onPlayerSelected

    -- Refresh method
    function playerList:RefreshPlayerList()
        self.playerScroll:Clear()

        local filter = string.lower(self.searchBox:GetValue() or "")
        local includeOffline = self.showOfflineToggle.showOffline

        local players = RARELOAD.AdminPanel.Utils.GetAllPlayers(includeOffline)
        local filteredPlayers = RARELOAD.AdminPanel.Utils.FilterPlayers(players, filter)
        local sortedPlayers = RARELOAD.AdminPanel.Utils.SortPlayers(filteredPlayers)

        for _, playerData in ipairs(sortedPlayers) do
            self:AddPlayerButton(playerData)
        end
    end

    -- Add player button method
    function playerList:AddPlayerButton(playerData)
        local button = vgui.Create("DButton", self.playerScroll)
        button:SetText("")
        button:Dock(TOP)
        button:DockMargin(0, 0, 0, 5)
        button:SetTall(50)

        button.player = playerData.player
        button.steamid = playerData.steamid
        button.playerData = playerData
        button.isSelected = false
        button.hoverFrac = 0
        button.selectFrac = 0

        local avatar = vgui.Create("AvatarImage", button)
        avatar:SetSize(40, 40)
        avatar:SetPos(5, 5)
        if playerData.isOnline and IsValid(playerData.player) then
            avatar:SetPlayer(playerData.player, 64)
        else
            avatar:SetSteamID(playerData.steamid, 64)
        end

        local avatarBorder = vgui.Create("DPanel", button)
        avatarBorder:SetSize(44, 44)
        avatarBorder:SetPos(3, 3)
        avatarBorder:MoveToBack()
        avatarBorder.Paint = function(pnl, w, h)
            local statusColor = THEME.player
            if playerData.isSuperAdmin then
                statusColor = THEME.superadmin
            elseif playerData.isAdmin then
                statusColor = THEME.admin
            end

            if not playerData.isOnline then
                statusColor = Color(statusColor.r, statusColor.g, statusColor.b, 150)
            end

            DrawRoundedBoxEx(0, 0, 0, w, h, statusColor, true, true, true, true)
        end

        button.Paint = function(self, w, h)
            self.hoverFrac = Lerp(FrameTime() * 8, self.hoverFrac, self:IsHovered() and 1 or 0)
            self.selectFrac = Lerp(FrameTime() * 6, self.selectFrac, self.isSelected and 1 or 0)

            local baseColor = THEME.panel
            if self.isSelected then
                baseColor = THEME.accent
            elseif self.hoverFrac > 0 then
                baseColor = RARELOAD.AdminPanel.Theme.LerpColor(self.hoverFrac, THEME.panel, THEME.panelHover)
            end

            if not playerData.isOnline then
                baseColor = Color(baseColor.r, baseColor.g, baseColor.b, 180)
            end

            DrawRoundedBoxEx(0, 0, 0, w, h, baseColor, true, true, true, true)

            if self.selectFrac > 0 then
                surface.SetDrawColor(THEME.textHighlight.r, THEME.textHighlight.g, THEME.textHighlight.b,
                    30 * self.selectFrac)
                surface.DrawRect(0, 0, 3, h)
            end

            if self.hoverFrac > 0 and not self.isSelected then
                surface.SetDrawColor(255, 255, 255, 10 * self.hoverFrac)
                surface.DrawRect(0, 0, w, h)
            end

            local nameColor = playerData.isOnline and THEME.text or Color(THEME.text.r, THEME.text.g, THEME.text.b, 180)
            draw.SimpleText(playerData.nick, "DermaDefault", 55, 15, nameColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local statusText, statusColor
            if playerData.isSuperAdmin then
                statusText = "SuperAdmin"
                statusColor = THEME.superadmin
            elseif playerData.isAdmin then
                statusText = "Admin"
                statusColor = THEME.admin
            else
                statusText = playerData.isBot and "Bot" or "Player"
                statusColor = THEME.player
            end

            if not playerData.isOnline then
                statusText = statusText .. " (Offline)"
                statusColor = Color(statusColor.r, statusColor.g, statusColor.b, 150)
            elseif playerData.isBot then
                statusText = statusText .. " (Bot)"
            end

            draw.SimpleText(statusText, "DermaDefaultBold", 55, 30, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            if self.hoverFrac > 0 or self.isSelected then
                local rightText = playerData.steamid
                if not playerData.isOnline and playerData.lastSeen then
                    rightText = "Last seen: " .. os.date("%m/%d/%y", playerData.lastSeen)
                end

                draw.SimpleText(rightText, "DermaDefault", w - 10, 25,
                    Color(THEME.textSecondary.r, THEME.textSecondary.g, THEME.textSecondary.b,
                        THEME.textSecondary.a * math.max(self.hoverFrac, self.selectFrac)),
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end

            if not playerData.isOnline then
                surface.SetDrawColor(THEME.textSecondary.r, THEME.textSecondary.g, THEME.textSecondary.b, 100)
                surface.SetMaterial(Material("icon16/disconnect.png"))
                surface.DrawTexturedRect(w - 25, 5, 16, 16)
            end
        end

        button.DoClick = function()
            if button.isSelected then return end

            surface.PlaySound("ui/buttonclick.wav")

            for _, child in pairs(playerList.playerScroll:GetCanvas():GetChildren()) do
                child.isSelected = (child.steamid == button.steamid)
            end

            if playerList.onPlayerSelected then
                playerList.onPlayerSelected(button.steamid)
            end
        end

        button.OnCursorEntered = function()
            surface.PlaySound("ui/buttonrollover.wav")
        end

        return button
    end

    return playerList
end
