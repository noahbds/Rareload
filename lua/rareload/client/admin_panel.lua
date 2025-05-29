RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}
RARELOAD.Permissions.PlayerPerms = RARELOAD.Permissions.PlayerPerms or {}
RARELOAD.Permissions.DEFS = RARELOAD.Permissions.DEFS or {}

net.Receive("RareloadSendPermissionsDefinitions", function()
    RARELOAD.Permissions.DEFS = net.ReadTable()

    if RARELOAD.AdminPanel.Frame and IsValid(RARELOAD.AdminPanel.Frame) then
        local steamID = RARELOAD.AdminPanel.Frame.selectedPlayer
        if steamID then
            RARELOAD.AdminPanel.Frame:SelectPlayer(steamID)
        end
    end

    print("[Rareload] Permission definitions loaded: " .. table.Count(RARELOAD.Permissions.DEFS) .. " permissions")
end)

local PANEL = {}

local THEME = {
    -- Main colors
    background = Color(25, 28, 36),
    header = Color(32, 36, 46),
    panel = Color(35, 39, 51),
    panelLight = Color(40, 45, 59),
    panelHover = Color(45, 50, 66),

    -- Text colors
    text = Color(225, 230, 240),
    textSecondary = Color(180, 185, 200),
    textHighlight = Color(255, 255, 255),
    textDark = Color(50, 55, 65),

    -- Accent colors
    accent = Color(88, 133, 236),
    accentDark = Color(72, 110, 196),
    accentLight = Color(105, 155, 255),
    success = Color(75, 195, 135),
    warning = Color(240, 195, 80),
    danger = Color(235, 75, 75),

    -- Status colors
    admin = Color(80, 170, 245),
    superadmin = Color(255, 175, 75),
    player = Color(180, 185, 195),

    -- Visual effects
    shadow = Color(15, 17, 23, 180),
    overlay = Color(0, 0, 0, 100),
    glow = Color(100, 140, 255, 40)
}

local function DrawRoundedBoxEx(cornerRadius, x, y, w, h, color, topLeft, topRight, bottomLeft, bottomRight)
    local radius = 0
    draw.RoundedBoxEx(radius, x, y, w, h, color, topLeft, topRight, bottomLeft, bottomRight)

    surface.SetDrawColor(255, 255, 255, 5)
    surface.DrawRect(x, y, w, h / 4)
end

-- Not used
local function DrawGlow(x, y, w, h, color, intensity)
    local glow = intensity or 1
    surface.SetDrawColor(color.r, color.g, color.b, (color.a or 255) * 0.3 * glow)
    surface.DrawOutlinedRect(x, y, w, h, 1)
end

function PANEL:Init()
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
        local hoverFrac = pnl:IsHovered() and 1 or 0
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

    self.playerList = vgui.Create("DPanel", contentPanel)
    self.playerList:Dock(LEFT)
    self.playerList:SetWide(280)
    self.playerList:DockMargin(0, 0, 10, 0)
    self.playerList.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panel, true, true, true, true)

        surface.SetDrawColor(THEME.accent.r, THEME.accent.g, THEME.accent.b, 40)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    self.playerListTitle = vgui.Create("DPanel", self.playerList)
    self.playerListTitle:SetText("Players")
    self.playerListTitle:Dock(TOP)
    self.playerListTitle:SetTall(40)
    self.playerListTitle.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.header, true, true, false, false)
        draw.SimpleText("Players Online", "DermaLarge", w / 2, h / 2, THEME.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local searchContainer = vgui.Create("DPanel", self.playerList)
    searchContainer:Dock(TOP)
    searchContainer:SetTall(50)
    searchContainer:DockMargin(10, 10, 10, 5)
    searchContainer.Paint = function() end

    self.searchBox = vgui.Create("DTextEntry", searchContainer)
    self.searchBox:Dock(FILL)
    self.searchBox:SetPlaceholderText("Search players...")
    self.searchBox:SetFont("DermaDefault")
    self.searchBox.Paint = function(pnl, w, h)
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
    self.searchBox.OnChange = function()
        self:RefreshPlayerList()
    end

    self.playerScroll = vgui.Create("DScrollPanel", self.playerList)
    self.playerScroll:Dock(FILL)
    self.playerScroll:DockMargin(10, 5, 10, 10)

    local scrollBar = self.playerScroll:GetVBar()
    scrollBar:SetWide(8)
    scrollBar:SetHideButtons(true)
    scrollBar.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(THEME.background.r, THEME.background.g, THEME.background.b, 100))
    end
    scrollBar.btnGrip.Paint = function(_, w, h)
        draw.RoundedBox(0, 2, 0, w - 4, h, THEME.accent)
    end

    self.permPanel = vgui.Create("DPanel", contentPanel)
    self.permPanel:Dock(FILL)
    self.permPanel:DockMargin(0, 0, 0, 0)
    self.permPanel.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panel, true, true, true, true)
    end

    self.noPlayerSelectedLabel = vgui.Create("DPanel", self.permPanel)
    self.noPlayerSelectedLabel:Dock(FILL)
    self.noPlayerSelectedLabel:DockMargin(20, 20, 20, 20)
    self.noPlayerSelectedLabel.Paint = function(pnl, w, h)
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

    self.permContainer = vgui.Create("DPanel", self.permPanel)
    self.permContainer:Dock(FILL)
    self.permContainer:DockMargin(15, 15, 15, 15)
    self.permContainer.Paint = function() end
    self.permContainer:SetVisible(false)

    self.playerInfo = vgui.Create("DPanel", self.permContainer)
    self.playerInfo:Dock(TOP)
    self.playerInfo:SetTall(90)
    self.playerInfo:DockMargin(0, 0, 0, 10)
    self.playerInfo.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panelLight, true, true, true, true)
    end

    self.playerAvatar = vgui.Create("AvatarImage", self.playerInfo)
    self.playerAvatar:SetSize(64, 64)
    self.playerAvatar:SetPos(13, 13)

    local avatarBorder = vgui.Create("DPanel", self.playerInfo)
    avatarBorder:SetSize(70, 70)
    avatarBorder:SetPos(10, 10)
    avatarBorder:MoveToBack()
    avatarBorder.Paint = function(pnl, w, h)
        DrawRoundedBoxEx(0, 0, 0, w, h, THEME.accent, true, true, true, true)
    end

    self.playerName = vgui.Create("DLabel", self.playerInfo)
    self.playerName:SetFont("DermaLarge")
    self.playerName:SetTextColor(THEME.textHighlight)
    self.playerName:SetPos(90, 15)

    self.playerSteamID = vgui.Create("DLabel", self.playerInfo)
    self.playerSteamID:SetFont("DermaDefault")
    self.playerSteamID:SetTextColor(THEME.textSecondary)
    self.playerSteamID:SetPos(90, 45)

    self.playerAdminStatus = vgui.Create("DLabel", self.playerInfo)
    self.playerAdminStatus:SetFont("DermaDefault")
    self.playerAdminStatus:SetPos(90, 65)

    local permHeader = vgui.Create("DPanel", self.permContainer)
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

    self.permList = vgui.Create("DScrollPanel", self.permContainer)
    self.permList:Dock(FILL)
    self.permList:DockMargin(0, 5, 0, 10)

    local permScrollBar = self.permList:GetVBar()
    permScrollBar:SetWide(8)
    permScrollBar:SetHideButtons(true)
    permScrollBar.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(THEME.background.r, THEME.background.g, THEME.background.b, 100))
    end
    permScrollBar.btnGrip.Paint = function(_, w, h)
        draw.RoundedBox(0, 2, 0, w - 4, h, THEME.accent)
    end

    self.saveButton = vgui.Create("DButton", self.permContainer)
    self.saveButton:SetText("Save Changes")
    self.saveButton:SetFont("DermaDefaultBold")
    self.saveButton:SetTextColor(Color(255, 255, 255))
    self.saveButton:Dock(BOTTOM)
    self.saveButton:SetTall(40)
    self.saveButton:DockMargin(0, 10, 0, 0)

    self.saveButton.Paint = function(pnl, w, h)
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
    self.saveButton.DoClick = function()
        self:SavePermissions()
    end

    self:SetAlpha(0)
    self:AlphaTo(255, 0.3, 0)
    self:RefreshPlayerList()

    net.Start("RareloadRequestPermissions")
    net.SendToServer()

    net.Receive("RareloadSendPermissions", function()
        RARELOAD.Permissions.PlayerPerms = net.ReadTable()
        if self.selectedPlayer then
            self:SelectPlayer(self.selectedPlayer)
        end
    end)
end

function PANEL:RefreshPlayerList()
    self.playerScroll:Clear()

    local filter = string.lower(self.searchBox:GetValue() or "")
    local players = player.GetAll()

    table.sort(players, function(a, b)
        if a:IsSuperAdmin() and not b:IsSuperAdmin() then return true end
        if b:IsSuperAdmin() and not a:IsSuperAdmin() then return false end
        if a:IsAdmin() and not b:IsAdmin() then return true end
        if b:IsAdmin() and not a:IsAdmin() then return false end
        return string.lower(a:Nick()) < string.lower(b:Nick())
    end)

    for _, ply in ipairs(players) do
        if string.find(string.lower(ply:Nick()), filter, 1, true) or
            string.find(string.lower(ply:SteamID()), filter, 1, true) then
            self:AddPlayerButton(ply)
        end
    end
end

function PANEL:AddPlayerButton(ply)
    local button = vgui.Create("DButton", self.playerScroll)
    button:SetText("")
    button:Dock(TOP)
    button:DockMargin(0, 0, 0, 5)
    button:SetTall(50)

    button.player = ply
    button.steamid = ply:SteamID()
    button.isSelected = false
    button.hoverFrac = 0
    button.selectFrac = 0
    button.animTime = 0

    local avatar = vgui.Create("AvatarImage", button)
    avatar:SetSize(40, 40)
    avatar:SetPos(5, 5)
    avatar:SetPlayer(ply, 64)

    local avatarBorder = vgui.Create("DPanel", button)
    avatarBorder:SetSize(44, 44)
    avatarBorder:SetPos(3, 3)
    avatarBorder:MoveToBack()
    avatarBorder.Paint = function(pnl, w, h)
        local statusColor = THEME.player
        if ply:IsSuperAdmin() then
            statusColor = THEME.superadmin
        elseif ply:IsAdmin() then
            statusColor = THEME.admin
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
            baseColor = LerpColor(self.hoverFrac, THEME.panel, THEME.panelHover)
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

        draw.SimpleText(ply:Nick(), "DermaDefault", 55, 15, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local statusText, statusColor
        if ply:IsSuperAdmin() then
            statusText = "SuperAdmin"
            statusColor = THEME.superadmin
        elseif ply:IsAdmin() then
            statusText = "Admin"
            statusColor = THEME.admin
        else
            statusText = "Player"
            statusColor = THEME.player
        end

        draw.SimpleText(statusText, "DermaDefaultBold", 55, 30, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        if self.hoverFrac > 0 or self.isSelected then
            draw.SimpleText(ply:SteamID(), "DermaDefault", w - 10, 25,
                Color(THEME.textSecondary.r, THEME.textSecondary.g, THEME.textSecondary.b,
                    THEME.textSecondary.a * math.max(self.hoverFrac, self.selectFrac)),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    button.DoClick = function()
        if button.isSelected then return end

        surface.PlaySound("ui/buttonclick.wav")

        self:SelectPlayer(button.steamid)

        for _, child in pairs(self.playerScroll:GetCanvas():GetChildren()) do
            child.isSelected = (child.steamid == button.steamid)
        end
    end

    button.OnCursorEntered = function(self)
        surface.PlaySound("ui/buttonrollover.wav")
    end

    return button
end

function PANEL:SelectPlayer(steamID)
    self.selectedPlayer = steamID

    local targetPly = nil
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == steamID then
            targetPly = ply
            break
        end
    end

    if not targetPly then
        self.noPlayerSelectedLabel:SetVisible(true)
        self.permContainer:SetVisible(false)
        self.noPlayerSelectedLabel.Paint = function(pnl, w, h)
            local boxW, boxH = w * 0.8, h * 0.6
            local boxX, boxY = (w - boxW) / 2, (h - boxH) / 2
            DrawRoundedBoxEx(0, boxX, boxY, boxW, boxH, THEME.panelLight, true, true, true, true)

            surface.SetDrawColor(THEME.warning)
            surface.SetMaterial(Material("icon16/error.png"))
            surface.DrawTexturedRect(w / 2 - 16, boxY + boxH * 0.3 - 16, 32, 32)

            draw.SimpleText("Player not found on server", "DermaLarge", w / 2, boxY + boxH * 0.6,
                THEME.warning, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            draw.SimpleText("The player may have disconnected", "DermaDefault", w / 2, boxY + boxH * 0.6 + 30,
                THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    self.permContainer:SetVisible(true)

    self.noPlayerSelectedLabel:SetVisible(false)

    self.playerInfo:SetAlpha(0)
    self.playerInfo:AlphaTo(255, 0.3, 0)

    self.playerAvatar:SetPlayer(targetPly, 64)

    self.playerName:SetText(targetPly:Nick())
    self.playerName:SizeToContents()

    self.playerSteamID:SetText(targetPly:SteamID())
    self.playerSteamID:SizeToContents()

    local adminStatus = ""
    if targetPly:IsSuperAdmin() then
        adminStatus = "SuperAdmin (All permissions granted automatically)"
        self.playerAdminStatus:SetTextColor(THEME.superadmin)
    elseif targetPly:IsAdmin() then
        adminStatus = "Admin"
        self.playerAdminStatus:SetTextColor(THEME.admin)
    else
        adminStatus = "Player"
        self.playerAdminStatus:SetTextColor(THEME.player)
    end
    self.playerAdminStatus:SetText(adminStatus)
    self.playerAdminStatus:SizeToContents()

    self.permList:Clear()
    self.checkboxes = {}

    if not RARELOAD.Permissions.DEFS then
        local errorPanel = vgui.Create("DPanel", self.permList)
        errorPanel:Dock(FILL)
        errorPanel:DockMargin(10, 10, 10, 10)
        errorPanel.Paint = function(pnl, w, h)
            DrawRoundedBoxEx(0, 0, 0, w, h, THEME.panelLight, true, true, true, true)

            surface.SetDrawColor(THEME.warning)
            surface.SetMaterial(Material("icon16/error.png"))
            surface.DrawTexturedRect(w / 2 - 16, h / 2 - 40, 32, 32)

            draw.SimpleText("Error: Permission definitions not loaded!", "DermaLarge", w / 2, h / 2,
                THEME.warning, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            draw.SimpleText("Attempting to load permissions from server...", "DermaDefault", w / 2, h / 2 + 30,
                THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        net.Start("RareloadRequestPermissions")
        net.SendToServer()
        return
    end

    local permCategories = {
        ["ADMIN"] = {},
        ["TOOL"] = {},
        ["SAVE"] = {},
        ["OTHER"] = {}
        -- TODO : Add more categories for better organization
    }

    for permName, permData in pairs(RARELOAD.Permissions.DEFS) do
        local category = "OTHER"

        if string.find(permName, "^ADMIN") then
            category = "ADMIN"
        elseif string.find(permName, "TOOL") then
            category = "TOOL"
        elseif string.find(permName, "SAVE") or string.find(permName, "RETAIN") then
            category = "SAVE"
        end

        permCategories[category][permName] = permData
    end

    for catName, perms in pairs(permCategories) do
        if table.Count(perms) > 0 then
            local catDisplayName = catName == "ADMIN" and "Administration" or
                catName == "TOOL" and "Tool Permissions" or
                catName == "SAVE" and "Save Features" or "Other Permissions"

            local catColor = catName == "ADMIN" and THEME.danger or
                catName == "TOOL" and THEME.success or
                catName == "SAVE" and THEME.accent or THEME.warning

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
                self:AddPermissionRow(permName, permData, targetPly, steamID)
            end
        end
    end
end

function PANEL:AddPermissionRow(permName, permData, targetPly, steamID)
    local permPanel = vgui.Create("DPanel", self.permList)
    permPanel:Dock(TOP)
    permPanel:DockMargin(5, 5, 5, 5)
    permPanel:SetTall(50)

    permPanel.hoverFrac = 0
    permPanel.Paint = function(pnl, w, h)
        pnl.hoverFrac = Lerp(FrameTime() * 8, pnl.hoverFrac, pnl:IsHovered() and 1 or 0)

        local baseColor = THEME.panelLight
        if pnl.hoverFrac > 0 then
            baseColor = LerpColor(pnl.hoverFrac, baseColor, THEME.panelHover)
        end

        DrawRoundedBoxEx(0, 0, 0, w, h, baseColor, true, true, true, true)
    end

    local permTitle = vgui.Create("DLabel", permPanel)
    permTitle:SetText(permData.name)
    permTitle:SetFont("DermaDefaultBold")
    permTitle:SetTextColor(THEME.text)
    permTitle:SetPos(10, 8)
    permTitle:SizeToContents()

    local permDesc = vgui.Create("DLabel", permPanel)
    permDesc:SetText(permData.desc)
    permDesc:SetFont("DermaDefault")
    permDesc:SetTextColor(THEME.textSecondary)
    permDesc:SetPos(10, 27)
    permDesc:SizeToContents()

    local toggleSwitch = vgui.Create("DButton", permPanel)
    toggleSwitch:SetSize(50, 26)
    toggleSwitch:SetText("")
    toggleSwitch:SetPos(permPanel:GetWide() - 70, 12)

    local isEnabled = self:GetPermissionValue(steamID, permName)
    toggleSwitch.switched = isEnabled
    toggleSwitch.switchFrac = isEnabled and 1 or 0

    toggleSwitch.Paint = function(pnl, w, h)
        local disabled = targetPly:IsSuperAdmin()

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
        if targetPly:IsSuperAdmin() then return end

        pnl.switched = not pnl.switched
        surface.PlaySound(pnl.switched and "ui/buttonclick.wav" or "ui/buttonclickrelease.wav")
    end

    self.checkboxes[permName] = toggleSwitch

    if targetPly:IsSuperAdmin() then
        toggleSwitch:SetEnabled(false)
        toggleSwitch.switched = true

        local lockIcon = vgui.Create("DImage", permPanel)
        lockIcon:SetSize(16, 16)
        lockIcon:SetPos(permPanel:GetWide() - 95, 18)
        lockIcon:SetImage("icon16/lock.png")

        local superAdminHint = vgui.Create("DLabel", permPanel)
        superAdminHint:SetPos(10, permDesc:GetTall() + 26)
        superAdminHint:SetText("SuperAdmin: Always granted")
        superAdminHint:SetTextColor(THEME.superadmin)
        superAdminHint:SetFont("DermaDefaultBold")
        superAdminHint:SizeToContents()
    end

    permPanel.PerformLayout = function(pnl, w, h)
        toggleSwitch:SetPos(w - 60, 12)
    end

    return permPanel
end

function PANEL:GetPermissionValue(steamID, permName)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == steamID and ply:IsSuperAdmin() then
            return true
        end
    end

    local perms = RARELOAD.Permissions.PlayerPerms[steamID]
    if perms and perms[permName] ~= nil then
        return perms[permName]
    end

    return RARELOAD.Permissions.DEFS[permName].default
end

function PANEL:SavePermissions()
    if not self.selectedPlayer or not self.checkboxes then return end

    local changedCount = 0
    local totalCount = 0

    for permName, toggleBtn in pairs(self.checkboxes) do
        totalCount = totalCount + 1
        local currentValue = self:GetPermissionValue(self.selectedPlayer, permName)
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

function LerpColor(frac, from, to)
    return Color(
        Lerp(frac, from.r, to.r),
        Lerp(frac, from.g, to.g),
        Lerp(frac, from.b, to.b),
        Lerp(frac, from.a or 255, to.a or 255)
    )
end

function PANEL:OnRemove()
    -- TODO : Add things here
end

vgui.Register("RareloadAdminPanel", PANEL, "DFrame")

function RARELOAD.AdminPanel.Open()
    if IsValid(RARELOAD.AdminPanel.Frame) then
        RARELOAD.AdminPanel.Frame:Remove()
    end

    RARELOAD.AdminPanel.Frame = vgui.Create("RareloadAdminPanel")
    return RARELOAD.AdminPanel.Frame
end

net.Receive("RareloadOpenAdminPanel", function()
    RARELOAD.AdminPanel.Open()
end)

net.Receive("RareloadNoPermission", function()
    chat.AddText(Color(255, 50, 50), "You don't have permission to open the Rareload admin panel.")
end)

net.Receive("RareloadAdminPanelAvailable", function()
    local version = net.ReadString()
    RARELOAD.version = version
    chat.AddText(Color(50, 255, 50),
        "Rareload Admin Panel available. Type !rareloadadmin or use the console command rareload_admin to open it.")
end)

hook.Add("OnPlayerChat", "RareloadAdminPanelChatCommand", function(ply, text)
    if text:lower() == "!rareloadadmin" and ply == LocalPlayer() then
        RunConsoleCommand("rareload_admin")
        return true
    end
end)

print("Rareload admin panel module loaded")
