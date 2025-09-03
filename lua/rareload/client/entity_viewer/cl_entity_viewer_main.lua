include("rareload/client/entity_viewer/cl_entity_viewer_theme.lua")
include("rareload/client/entity_viewer/cl_entity_viewer_utils.lua")
include("rareload/client/entity_viewer/cl_entity_viewer_create_category.lua")

local entityViewerFrame
local lastShortcutTime = 0
local ANIMATION_SPEED = 0.3

local VIEWER_SETTINGS = {
    autoRefresh = false,
    refreshInterval = 5,
    showAdvancedInfo = true
}

local function LoadViewerSettings()
    if file.Exists("rareload/entity_viewer_settings.json", "DATA") then
        local json = file.Read("rareload/entity_viewer_settings.json", "DATA")
        local success, t = pcall(util.JSONToTable, json)
        if success and istable(t) then
            for k, v in pairs(t) do
                VIEWER_SETTINGS[k] = v
            end
        end
    end
end

local function SaveViewerSettings()
    file.Write("rareload/entity_viewer_settings.json", util.TableToJSON(VIEWER_SETTINGS, true))
end

LoadViewerSettings()

function OpenEntityViewer(ply)
    if not THEME or not ShowNotification or not util or not file then
        notification.AddLegacy("Rareload Entity Viewer: Missing dependencies!", NOTIFY_ERROR, 5)
        return
    end

    if entityViewerFrame and IsValid(entityViewerFrame) then
        entityViewerFrame:MakePopup()
        entityViewerFrame:MoveToFront()
        if LoadData then
            LoadData()
        end
        return
    end

    if not IsValid(ply) or not ply:IsAdmin() then
        ShowNotification("You must be an admin to use this command.", NOTIFY_ERROR)
        return
    end

    ---@class DFrame
    local frame = vgui.Create("DFrame")
    entityViewerFrame = frame
    local w, h = math.Clamp(ScrW() * 0.8, 900, ScrW() - 40), math.Clamp(ScrH() * 0.85, 700, ScrH() - 40)
    frame:SetSize(w, h)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:SetSizable(false)
    frame:SetMinWidth(800)
    frame:SetMinHeight(600)
    frame:SetBackgroundBlur(true)
    frame:SetAlpha(0)
    frame:AlphaTo(255, ANIMATION_SPEED, 0)
    frame:SetDeleteOnClose(true)
    frame:ShowCloseButton(true)

    frame.Paint = function(self, fw, fh)
        draw.RoundedBox(12, 0, 0, fw, fh, THEME.background)
        draw.RoundedBoxEx(12, 0, 0, fw, 64, THEME.backgroundDark, true, true, false, false)
        draw.SimpleText("Entity & NPC Viewer", "RareloadHeading", 28, 20, THEME.textPrimary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(game.GetMap(), "RareloadBody", 28, 44, THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(THEME.border)
        draw.RoundedBox(12, 0, 0, fw, fh, Color(0, 0, 0, 0))
        surface.DrawOutlinedRect(0, 0, fw, fh, 1)
    end

    local oldClose = frame.Close
    frame.Close = function(self)
        self:AlphaTo(0, ANIMATION_SPEED, 0, function()
            oldClose(self)
        end)
    end

    frame.Think = function(self)
        if input.IsKeyDown(KEY_ESCAPE) then
            self:Close()
        end
    end

    frame.OnRemove = function()
        entityViewerFrame = nil
    end

    local headerContainer = vgui.Create("DPanel", frame)
    headerContainer:Dock(TOP)
    headerContainer:SetTall(140)
    headerContainer:DockMargin(0, 64, 0, 8)
    headerContainer.Paint = function() end

    local statsContainer = vgui.Create("DPanel", headerContainer)
    statsContainer:Dock(TOP)
    statsContainer:SetTall(70)
    statsContainer:DockPadding(20, 10, 20, 10)
    statsContainer.Paint = function() end

    local searchContainer = vgui.Create("DPanel", headerContainer)
    searchContainer:Dock(BOTTOM)
    searchContainer:SetTall(40)
    searchContainer:DockMargin(20, 8, 20, 0)
    searchContainer.Paint = function() end


    local searchPanel, searchBar = CreateModernSearchBar(searchContainer)
    searchPanel:Dock(LEFT)
    searchPanel:SetWide(350)
    searchPanel:DockMargin(0, 0, 12, 0)

    local actionsPanel = vgui.Create("DPanel", searchContainer)
    actionsPanel:Dock(FILL)
    actionsPanel.Paint = function() end

    local refreshButton = CreateActionButton(actionsPanel, "Refresh", "icon16/arrow_refresh.png", THEME.info,
        "Refresh entity data")
    refreshButton:Dock(RIGHT)
    refreshButton:DockMargin(4, 4, 4, 4)
    refreshButton.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        ShowNotification("Refreshing data...", NOTIFY_GENERIC)
        LoadData(searchBar:GetValue())
    end

    local resetButton = CreateActionButton(actionsPanel, "Reset", "icon16/delete.png", THEME.error,
        "Reset all saved data")
    resetButton:Dock(RIGHT)
    resetButton:DockMargin(4, 4, 4, 4)
    resetButton.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        local confirm = vgui.Create("DFrame")
        confirm:SetSize(380, 160)
        confirm:SetTitle("")
        confirm:Center()
        confirm:MakePopup()
        confirm:SetBackgroundBlur(true)
        confirm.Paint = function(self, w, h)
            draw.RoundedBox(12, 0, 0, w, h, THEME.background)
            draw.RoundedBoxEx(12, 0, 0, w, 50, THEME.error, true, true, false, false)
            draw.SimpleText("Reset All Data", "RareloadHeading", w / 2, 25, THEME.textPrimary, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end

        local msg = vgui.Create("DLabel", confirm)
        msg:SetText("Are you sure you want to delete all saved entities and NPCs for this map?")
        msg:SetFont("RareloadText")
        msg:SetTextColor(THEME.textPrimary)
        msg:SetContentAlignment(5)
        msg:Dock(TOP)
        msg:DockMargin(10, 60, 10, 10)

        local btnPanel = vgui.Create("DPanel", confirm)
        btnPanel:Dock(BOTTOM)
        btnPanel:SetTall(40)
        btnPanel:DockMargin(10, 0, 10, 10)
        btnPanel.Paint = function() end

        local btnWidth = (380 - 40) / 2

        local yes = vgui.Create("DButton", btnPanel)
        yes:SetText("Delete All")
        yes:SetTextColor(THEME.textPrimary)
        yes:SetFont("RareloadText")
        yes:Dock(LEFT)
        yes:SetWide(btnWidth)
        yes.Paint = function(self, w, h)
            local color = self:IsHovered() and Color(255, 80, 80) or THEME.error
            draw.RoundedBox(6, 0, 0, w, h, color)
        end
        yes.DoClick = function()
            ResetData()
            confirm:Close()
        end

        local no = vgui.Create("DButton", btnPanel)
        no:SetText("Cancel")
        no:SetTextColor(THEME.textPrimary)
        no:SetFont("RareloadText")
        no:Dock(RIGHT)
        no:SetWide(btnWidth)
        no.Paint = function(self, w, h)
            local color = self:IsHovered() and THEME.surfaceVariant or THEME.surface
            draw.RoundedBox(6, 0, 0, w, h, color)
        end
        no.DoClick = function() confirm:Close() end
    end

    local settingsButton = CreateActionButton(actionsPanel, "Settings", "icon16/cog.png", THEME.textSecondary,
        "View settings")
    settingsButton:Dock(RIGHT)
    settingsButton:DockMargin(4, 4, 4, 4)
    settingsButton.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        OpenSettingsPanel()
    end

    ---@class DPropertySheet
    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL)
    tabs:DockMargin(20, 0, 20, 20)
    tabs.Paint = function(self, tw, th)
        draw.RoundedBox(8, 0, 0, tw, th, THEME.surface)
    end

    local function CreateModernTab(title, icon, isNPCTab)
        local container = vgui.Create("DPanel")
        container.Paint = function() end

        ---@class DScrollPanel
        local scroll = vgui.Create("DScrollPanel", container)
        scroll:Dock(FILL)
        scroll:DockMargin(5, 5, 5, 5)
        local tabColor = isNPCTab and THEME.secondary or THEME.primary
        local scrollbar = scroll:GetVBar()
        scrollbar:SetWide(12)
        scrollbar.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, ColorAlpha(THEME.backgroundDark, 180))
        end
        scrollbar.btnUp.hoverFraction = 0
        scrollbar.btnDown.hoverFraction = 0
        scrollbar.btnGrip.hoverFraction = 0
        scrollbar.btnUp.Paint = function(self, w, h)
            self.hoverFraction = Lerp(FrameTime() * 8, self.hoverFraction, self:IsHovered() and 1 or 0)
            local color = THEME:LerpColor(self.hoverFraction, tabColor, THEME.primaryLight)
            draw.RoundedBox(6, 2, 0, w - 4, h - 2, color)
        end
        scrollbar.btnDown.Paint = function(self, w, h)
            self.hoverFraction = Lerp(FrameTime() * 8, self.hoverFraction, self:IsHovered() and 1 or 0)
            local color = THEME:LerpColor(self.hoverFraction, tabColor, THEME.primaryLight)
            draw.RoundedBox(6, 2, 2, w - 4, h - 2, color)
        end
        scrollbar.btnGrip.Paint = function(self, w, h)
            self.hoverFraction = Lerp(FrameTime() * 8, self.hoverFraction, self:IsHovered() and 1 or 0)
            local color = THEME:LerpColor(self.hoverFraction, tabColor, THEME.primaryLight)
            draw.RoundedBox(6, 2, 0, w - 4, h, color)
            if h > 30 then
                surface.SetDrawColor(255, 255, 255, 80 + 60 * self.hoverFraction)
                local center = h / 2
                surface.DrawLine(w / 2, center - 5, w / 2, center + 5)
                if h > 50 then
                    surface.DrawLine(w / 2, center - 10, w / 2, center - 5)
                    surface.DrawLine(w / 2, center + 5, w / 2, center + 10)
                end
            end
        end
        local sheet = tabs:AddSheet(title, container, icon)
        if sheet.Tab then
            sheet.Tab.hoverFraction = 0
            sheet.Tab.accentColor = tabColor
            sheet.Tab.Paint = function(self, w, h)
                local isActive = self:IsActive()
                self.hoverFraction = Lerp(FrameTime() * 8, self.hoverFraction, (self:IsHovered() or isActive) and 1 or 0)
                local bgColor = isActive and tabColor or
                    THEME:LerpColor(self.hoverFraction, THEME.surface, THEME.surfaceVariant)
                draw.RoundedBoxEx(8, 0, 0, w, h, bgColor, true, true, false, false)
                if isActive then
                    surface.SetDrawColor(255, 255, 255, 100)
                    surface.DrawRect(4, h - 3, w - 8, 3)
                end
                surface.SetDrawColor(255, 255, 255, isActive and 30 or (15 * self.hoverFraction))
                surface.DrawRect(1, 1, w - 2, h / 3)
            end
            if sheet.Tab.Text then
                sheet.Tab.Text:SetFont("RareloadText")
            end
        end

        local loadingPanel = vgui.Create("DPanel", container)
        loadingPanel:SetSize(300, 200)
        loadingPanel:SetVisible(false)
        loadingPanel:SetZPos(100)
        local loadingRotation = 0
        loadingPanel.Paint = function(self, w, h)
            loadingRotation = (loadingRotation or 0) + FrameTime() * 360
            if loadingRotation > 360 then loadingRotation = loadingRotation - 360 end
            local centerX, centerY = w / 2, h / 2
            local radius = 24
            for i = 0, 7 do
                local angle = math.rad(loadingRotation + (i * 45))
                local dotSize = 8 - i
                if dotSize < 3 then dotSize = 3 end
                local x = centerX + math.cos(angle) * radius
                local y = centerY + math.sin(angle) * radius
                draw.RoundedBox(dotSize / 2, x - dotSize / 2, y - dotSize / 2, dotSize, dotSize,
                    ColorAlpha(tabColor, 255 - (i * 30)))
            end
            draw.SimpleText("Loading...", "RareloadText", w / 2, h / 2 + 50,
                THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        local emptyPanel = vgui.Create("DPanel", container)
        emptyPanel:SetSize(300, 200)
        emptyPanel:SetVisible(false)
        emptyPanel:SetZPos(99)
        emptyPanel.Paint = function(self, w, h)
            local iconSize = 64
            surface.SetDrawColor(THEME.textSecondary)
            surface.SetMaterial(Material(isNPCTab and "icon16/user_delete.png" or "icon16/brick_delete.png"))
            surface.DrawTexturedRect(w / 2 - iconSize / 2, h / 2 - iconSize - 10, iconSize, iconSize)
            draw.SimpleText("No " .. title .. " Found", "RareloadSubheading", w / 2, h / 2 + 10,
                THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("Try adjusting your search criteria", "RareloadBody", w / 2, h / 2 + 40,
                THEME.textTertiary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        container.PerformLayout = function(self, w, h)
            loadingPanel:SetPos(w / 2 - loadingPanel:GetWide() / 2, h / 2 - loadingPanel:GetTall() / 2)
            emptyPanel:SetPos(w / 2 - emptyPanel:GetWide() / 2, h / 2 - emptyPanel:GetTall() / 2)
        end

        function scroll:ShowLoading(show)
            loadingPanel:SetVisible(show)
            emptyPanel:SetVisible(false)
        end

        function scroll:ShowEmpty(show)
            emptyPanel:SetVisible(show)
            loadingPanel:SetVisible(false)
        end

        function scroll:Refresh()
            self:Clear()
            self:InvalidateLayout(true)
        end

        return scroll, sheet
    end

    local entityScroll, entitySheet = CreateModernTab("Entities", "icon16/bricks.png", false)
    local npcScroll, npcSheet = CreateModernTab("NPCs", "icon16/user.png", true)

    local loadingOverlay

    local function HideModernLoading()
        if loadingOverlay and IsValid(loadingOverlay) then
            loadingOverlay:AlphaTo(0, 0.2, 0, function()
                if IsValid(loadingOverlay) then loadingOverlay:Remove() end
            end)
        end
    end

    function LoadData(filter)
        entityScroll:ShowLoading(true)
        npcScroll:ShowLoading(true)
        local totalHealth, countedEntities = 0, 0
        timer.Simple(0.1, function()
            if not IsValid(frame) then return end
            entityScroll:Clear()
            npcScroll:Clear()
            local mapName = game.GetMap()
            local filePath = "rareload/player_positions_" .. mapName .. ".json"
            if not file.Exists(filePath, "DATA") then
                entityScroll:ShowLoading(false)
                npcScroll:ShowLoading(false)
                entityScroll:ShowEmpty(true)
                npcScroll:ShowEmpty(true)
                HideModernLoading()
                return
            end
            local jsonData = file.Read(filePath, "DATA")
            local success, rawData = pcall(util.JSONToTable, jsonData)
            if not success or not rawData or not rawData[mapName] then
                entityScroll:ShowLoading(false)
                npcScroll:ShowLoading(false)
                entityScroll:ShowEmpty(true)
                npcScroll:ShowEmpty(true)
                HideModernLoading()
                return
            end
            local entityCount, npcCount = 0, 0
            local entityCategories, npcCategories = 0, 0
            local totalPlayers = 0
            for steamID, playerData in pairs(rawData[mapName]) do
                totalPlayers = totalPlayers + 1
                if playerData.entities and #playerData.entities > 0 then
                    for _, entData in ipairs(playerData.entities) do
                        if entData.health then
                            totalHealth = (totalHealth + tonumber(entData.health)) or 0
                            countedEntities = countedEntities + 1
                        end
                    end
                    local category = CreateCategory(entityScroll, "Player: " .. steamID, playerData.entities, false,
                        filter)
                    if category then
                        entityCategories = entityCategories + 1
                        entityCount = entityCount + #playerData.entities
                    end
                end
                if playerData.npcs and #playerData.npcs > 0 then
                    local category = CreateCategory(npcScroll, "Player: " .. steamID, playerData.npcs, true, filter)
                    if category then
                        npcCategories = npcCategories + 1
                        npcCount = npcCount + #playerData.npcs
                    end
                end
            end
            statsContainer:Clear()
            local totalCard = CreateStatsCard(statsContainer, "TOTAL", entityCount + npcCount, "items")
            totalCard:Dock(LEFT)
            totalCard:DockMargin(0, 0, 12, 0)
            local entityCard = CreateStatsCard(statsContainer, "ENTITIES", entityCount, entityCategories .. " groups")
            entityCard:Dock(LEFT)
            entityCard:DockMargin(0, 0, 12, 0)
            local npcCard = CreateStatsCard(statsContainer, "NPCS", npcCount, npcCategories .. " groups")
            npcCard:Dock(LEFT)
            npcCard:DockMargin(0, 0, 12, 0)
            local playerCard = CreateStatsCard(statsContainer, "PLAYERS", totalPlayers, "with data")
            playerCard:Dock(LEFT)
            playerCard:DockMargin(0, 0, 12, 0)
            if entitySheet and entitySheet.Tab and entitySheet.Tab.Text then
                entitySheet.Tab.Text:SetText("Entities (" .. entityCount .. ")")
            end
            if npcSheet and npcSheet.Tab and npcSheet.Tab.Text then
                npcSheet.Tab.Text:SetText("NPCs (" .. npcCount .. ")")
            end
            entityScroll:ShowLoading(false)
            npcScroll:ShowLoading(false)
            if entityCount == 0 then
                entityScroll:ShowEmpty(true)
            end
            if npcCount == 0 then
                npcScroll:ShowEmpty(true)
            end
            HideModernLoading()
        end)
    end

    function ResetData()
        local mapName = game.GetMap()
        local filePath = "rareload/player_positions_" .. mapName .. ".json"
        if file.Exists(filePath, "DATA") then
            file.Delete(filePath)
            net.Start("RareloadReloadData")
            net.SendToServer()
            LoadData()
            ShowNotification("All data deleted for " .. mapName, NOTIFY_GENERIC)
        else
            ShowNotification("No data file exists for " .. mapName, NOTIFY_ERROR)
        end
    end

    searchBar.OnChange = function()
        local searchText = searchBar:GetValue()
        if timer.Exists("RareloadSearch") then
            timer.Remove("RareloadSearch")
        end
        timer.Create("RareloadSearch", 0.4, 1, function()
            if IsValid(frame) then
                LoadData(searchText)
            end
        end)
    end

    local function UpdateAutoRefresh()
        timer.Remove("RareloadViewerAutoRefresh")
        if VIEWER_SETTINGS.autoRefresh and IsValid(frame) then
            timer.Create("RareloadViewerAutoRefresh", VIEWER_SETTINGS.refreshInterval, 0, function()
                if IsValid(frame) then
                    LoadData(searchBar:GetValue())
                end
            end)
        end
    end

    UpdateAutoRefresh()

    frame.OnSizeChanged = function(self, w, h)
        local maxW, maxH = ScrW() - 40, ScrH() - 40
        if w > maxW or h > maxH then
            self:SetSize(math.min(w, maxW), math.min(h, maxH))
            self:Center()
        end
        local availableWidth = searchContainer:GetWide() - actionsPanel:GetWide() - 20
        searchPanel:SetWide(math.max(250, math.min(400, availableWidth)))
        headerContainer:InvalidateLayout(true)
        statsContainer:InvalidateLayout(true)
        searchContainer:InvalidateLayout(true)
        tabs:InvalidateLayout(true)
    end

    if not ConVarExists("rareload_teleport_to") then
        concommand.Add("rareload_teleport_to", function(ply, cmd, args)
            if not IsValid(ply) or not ply:IsPlayer() then return end
            local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
            if not x or not y or not z then return end
            local pos = Vector(x, y, z)
            net.Start("RareloadTeleportTo")
            net.WriteVector(pos)
            net.SendToServer()
        end)
    end

    hook.Add("Think", "RareloadEntityViewerShortcut", function()
        if input.IsKeyDown(KEY_F7) and not gui.IsGameUIVisible() then
            if CurTime() - lastShortcutTime > 0.5 then
                lastShortcutTime = CurTime()
                if not entityViewerFrame or not IsValid(entityViewerFrame) then
                    RunConsoleCommand("entity_viewer_open")
                end
            end
        end
    end)

    timer.Simple(0.1, function()
        if IsValid(frame) then
            LoadData()
        end
    end)
end

function OpenSettingsPanel()
    local settingsFrame = vgui.Create("DFrame")
    settingsFrame:SetSize(450, 320)
    settingsFrame:SetTitle("")
    settingsFrame:Center()
    settingsFrame:MakePopup()
    settingsFrame:SetBackgroundBlur(true)
    settingsFrame.Paint = function(self, w, h)
        draw.RoundedBox(12, 0, 0, w, h, THEME.background)
        draw.RoundedBoxEx(12, 0, 0, w, 60, THEME.backgroundDark, true, true, false, false)
        draw.SimpleText("Entity Viewer Settings", "RareloadHeading", w / 2, 30, THEME.textPrimary, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    local content = vgui.Create("DPanel", settingsFrame)
    content:Dock(FILL)
    content:DockMargin(20, 70, 20, 20)
    content.Paint = function() end

    ---@class DCheckBoxLabel
    local autoRefreshCheck = vgui.Create("DCheckBoxLabel", content)
    autoRefreshCheck:SetText("Auto-refresh data")
    autoRefreshCheck:SetTextColor(THEME.textPrimary)
    autoRefreshCheck:SetFont("RareloadText")
    autoRefreshCheck:Dock(TOP)
    autoRefreshCheck:DockMargin(0, 0, 0, 10)
    autoRefreshCheck:SetValue(VIEWER_SETTINGS.autoRefresh)
    autoRefreshCheck.OnChange = function(self, val)
        VIEWER_SETTINGS.autoRefresh = val
        SaveViewerSettings()
        timer.Remove("RareloadViewerAutoRefresh")
        if val and entityViewerFrame and IsValid(entityViewerFrame) then
            timer.Create("RareloadViewerAutoRefresh", VIEWER_SETTINGS.refreshInterval, 0, function()
                if IsValid(entityViewerFrame) and LoadData then
                    LoadData()
                end
            end)
        end
    end
    local intervalLabel = vgui.Create("DLabel", content)
    intervalLabel:SetText("Refresh interval (seconds):")
    intervalLabel:SetFont("RareloadText")
    intervalLabel:SetTextColor(THEME.textPrimary)
    intervalLabel:Dock(TOP)
    intervalLabel:DockMargin(0, 0, 0, 5)

    ---@class DNumSlider
    local intervalSlider = vgui.Create("DNumSlider", content)
    intervalSlider:SetText("")
    intervalSlider:Dock(TOP)
    intervalSlider:SetTall(25)
    intervalSlider:DockMargin(0, 0, 0, 15)
    intervalSlider:SetMin(1)
    intervalSlider:SetMax(30)
    intervalSlider:SetDecimals(0)
    intervalSlider:SetValue(VIEWER_SETTINGS.refreshInterval)
    intervalSlider.OnValueChanged = function(self, val)
        VIEWER_SETTINGS.refreshInterval = math.Round(val)
        SaveViewerSettings()
    end

    local advancedInfoCheck = vgui.Create("DCheckBoxLabel", content)
    advancedInfoCheck:SetText("Show advanced entity information")
    advancedInfoCheck:SetTextColor(THEME.textPrimary)
    advancedInfoCheck:SetFont("RareloadText")
    advancedInfoCheck:Dock(TOP)
    advancedInfoCheck:DockMargin(0, 0, 0, 20)
    advancedInfoCheck:SetValue(VIEWER_SETTINGS.showAdvancedInfo)
    advancedInfoCheck.OnChange = function(self, val)
        VIEWER_SETTINGS.showAdvancedInfo = val
        SaveViewerSettings()
    end
    local closeBtn = vgui.Create("DButton", content)
    closeBtn:SetText("Close")
    closeBtn:SetFont("RareloadText")
    closeBtn:Dock(BOTTOM)
    closeBtn:SetTall(36)
    closeBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.primaryLight or THEME.primary
        draw.RoundedBox(6, 0, 0, w, h, color)
        draw.SimpleText("Close", "RareloadText", w / 2, h / 2, THEME.textPrimary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()

    end
    settingsFrame:Close()
    SaveViewerSettings()
end

concommand.Add("entity_viewer_open", OpenEntityViewer)
