include("autorun/client/cl_entity_viewer_theme.lua")
include("autorun/client/cl_entity_viewer_utils.lua")

local entityViewerFrame
local lastShortcutTime = 0

function OpenEntityViewer(ply)
    if not THEME or not ShowNotification or not util or not file then
        notification.AddLegacy("Rareload Entity Viewer: Missing dependencies!", NOTIFY_ERROR, 5)
        return
    end

    if entityViewerFrame and IsValid(entityViewerFrame) then
        entityViewerFrame:MakePopup()
        entityViewerFrame:MoveToFront()
        return
    end

    if not IsValid(ply) or not ply:IsAdmin() then
        ShowNotification("You must be an admin to use this command.", NOTIFY_ERROR)
        return
    end

    ---@class DFrame
    local frame = vgui.Create("DFrame")
    entityViewerFrame = frame
    local w, h = math.Clamp(ScrW() * 0.6, 600, ScrW() - 40), math.Clamp(ScrH() * 0.7, 400, ScrH() - 40)
    frame:SetSize(w, h)
    frame:SetTitle("Rareload Entity & NPC Viewer - " .. game.GetMap())
    frame:SetIcon("icon16/database_connect.png")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:SetSizable(true)
    frame:SetMinWidth(480)
    frame:SetMinHeight(320)
    frame:SetBackgroundBlur(true)
    frame:SetAlpha(0)
    frame:AlphaTo(255, 0.3, 0)
    frame:SetDeleteOnClose(true)

    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 0, 0, w, h, THEME.background)

        local headerColor = THEME.header
        draw.RoundedBoxEx(8, 0, 0, w, 32, headerColor, true, true, false, false)

        surface.SetDrawColor(ColorAlpha(THEME.accent, 40))
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        local shadowAlpha = 60
        for i = 1, 8 do
            surface.SetDrawColor(0, 0, 0, shadowAlpha * (1 - i / 8))
            surface.DrawRect(i, h - 9 + i, w - i * 2, 1)
        end
    end

    local oldClose = frame.Close
    frame.Close = function(self)
        self:AlphaTo(0, 0.3, 0, function()
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

    local headerPanel = vgui.Create("DPanel", frame)
    headerPanel:Dock(TOP)
    headerPanel:SetTall(48)
    headerPanel:DockMargin(8, 8, 8, 0)
    headerPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel)
    end

    local infoLabel = vgui.Create("DLabel", headerPanel)
    infoLabel:SetText("Browse, teleport to, or delete saved entities and NPCs")
    infoLabel:SetFont("RareloadText")
    infoLabel:SetTextColor(THEME.text)
    infoLabel:Dock(LEFT)
    infoLabel:DockMargin(12, 0, 12, 0)
    infoLabel:SetWide(320)
    infoLabel:SetContentAlignment(4)

    ---@class DTextEntry
    local searchBar = vgui.Create("DTextEntry", headerPanel)
    searchBar:SetPlaceholderText("Search by class name...")
    searchBar:Dock(RIGHT)
    searchBar:SetWide(220)
    searchBar:DockMargin(8, 8, 8, 8)

    local refreshButton = vgui.Create("DButton", headerPanel)
    refreshButton:SetText("")
    refreshButton:SetWide(36)
    refreshButton:Dock(RIGHT)
    refreshButton:DockMargin(0, 8, 8, 8)
    refreshButton:SetTooltip("Refresh entity/NPC data")
    refreshButton.Paint = function(self, w, h)
        local color = self:IsHovered() and
            Color(THEME.accent.r * 1.2, THEME.accent.g * 1.2, THEME.accent.b * 1.2) or THEME.accent
        draw.RoundedBox(6, 0, 0, w, h, color)
        surface.SetDrawColor(255, 255, 255)
        surface.SetMaterial(Material("icon16/arrow_refresh.png"))
        surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
    end
    refreshButton.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        ShowNotification("Refreshing data...", NOTIFY_GENERIC)
        LoadData(searchBar:GetValue())
    end

    if LocalPlayer():IsAdmin() then
        local resetButton = vgui.Create("DButton", headerPanel)
        resetButton:SetText("")
        resetButton:SetWide(36)
        resetButton:Dock(RIGHT)
        resetButton:DockMargin(0, 8, 8, 8)
        resetButton:SetTooltip("Reset all saved entities/NPCs for this map")
        local resetIcon = Material("icon16/delete.png")
        resetButton.Paint = function(self, w, h)
            local color = self:IsHovered() and Color(220, 60, 60) or Color(180, 40, 40)
            draw.RoundedBox(6, 0, 0, w, h, color)
            surface.SetDrawColor(255, 255, 255)
            surface.SetMaterial(resetIcon)
            surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
        end
        resetButton.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            local confirm = vgui.Create("DFrame")
            confirm:SetSize(390, 180)
            confirm:SetTitle("Confirm Reset")
            confirm:SetBackgroundBlur(true)
            confirm:Center()
            confirm:MakePopup()
            confirm.Paint = function(self, w, h)
                draw.RoundedBox(10, 0, 0, w, h, THEME.background)
                draw.RoundedBox(6, 0, 0, w, 28, THEME.header)
            end
            local msg = vgui.Create("DLabel", confirm)
            msg:SetText("Are you sure you want to reset all saved data for this map?")
            msg:SetFont("RareloadText")
            msg:SetTextColor(THEME.text)
            msg:Dock(TOP)
            msg:DockMargin(10, 32, 10, 10)
            local btnPanel = vgui.Create("DPanel", confirm)
            btnPanel:Dock(BOTTOM)
            btnPanel:SetTall(40)
            btnPanel:DockMargin(10, 0, 10, 10)
            btnPanel.Paint = function() end
            local yes = vgui.Create("DButton", btnPanel)
            yes:SetText("Reset")
            yes:Dock(LEFT)
            yes:SetWide(120)
            yes.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(220, 60, 60))
            end
            yes.DoClick = function()
                ResetData()
                confirm:Close()
            end
            local no = vgui.Create("DButton", btnPanel)
            no:SetText("Cancel")
            no:Dock(RIGHT)
            no:SetWide(120)
            no.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(60, 60, 70))
            end
            no.DoClick = function()
                confirm:Close()
            end
        end
    end

    ---@class DPropertySheet
    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL)
    tabs:DockMargin(8, 8, 8, 8)
    tabs.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel)
    end

    local function CreateTab(title, icon, isNPCTab)
        local colors = {
            bg = THEME.background,
            accent = isNPCTab and Color(240, 160, 80) or THEME.accent,
            hover = isNPCTab and Color(255, 180, 100) or Color(100, 160, 255)
        }

        ---@class DScrollPanel
        local scroll = vgui.Create("DScrollPanel")

        ---@class DVScrollBar
        local scrollbar = scroll:GetVBar()
        scrollbar:SetWide(8)

        scrollbar.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, colors.bg)
        end

        ---@diagnostic disable-next-line: undefined-field
        scrollbar.btnUp.Paint = function(self, w, h)
            local btnColor = self:IsHovered() and colors.hover or colors.accent
            draw.RoundedBox(4, 2, 0, w - 4, h - 2, btnColor)
        end

        ---@diagnostic disable-next-line: undefined-field
        scrollbar.btnDown.Paint = function(self, w, h)
            local btnColor = self:IsHovered() and colors.hover or colors.accent
            draw.RoundedBox(4, 2, 2, w - 4, h - 2, btnColor)
        end

        ---@diagnostic disable-next-line: undefined-field
        scrollbar.btnGrip.Paint = function(self, w, h)
            local gripColor = self:IsHovered() and colors.hover or colors.accent
            draw.RoundedBox(4, 2, 0, w - 4, h, gripColor)
        end

        local sheet = tabs:AddSheet(title, scroll, icon)

        if sheet.Tab then
            sheet.Tab.Paint = function(self, w, h)
                local isSelected = self:IsActive()
                local bgColor = isSelected and colors.accent or Color(45, 45, 55)
                draw.RoundedBox(4, 0, 0, w, h - (isSelected and 0 or 1), bgColor)
            end
        end

        function scroll:Refresh()
            self:Clear()
            self:InvalidateLayout(true)
        end

        return scroll
    end

    local entityScroll = CreateTab("Entities", "icon16/bricks.png", false)
    local npcScroll = CreateTab("NPCs", "icon16/user.png", true)

    local function CreateErrorPanel(parent, title, message, icon)
        ---@class DPanel
        local panel = vgui.Create("DPanel", parent)
        panel:Dock(FILL)
        panel:DockMargin(20, 20, 20, 20)
        panel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.panel)

            if icon then
                surface.SetDrawColor(THEME.dangerAccent)
                surface.SetMaterial(icon)
                surface.DrawTexturedRect(w / 2 - 32, h / 2 - 60, 64, 64)
            end

            draw.SimpleText(title, "RareloadHeader", w / 2, h / 2, THEME.dangerAccent, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
            draw.SimpleText(message, "RareloadText", w / 2, h / 2 + 30, THEME.text, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end

        return panel
    end

    local loadingPanel
    local function ShowLoading()
        if loadingPanel and IsValid(loadingPanel) then loadingPanel:Remove() end
        loadingPanel = vgui.Create("DPanel", frame)
        loadingPanel:SetSize(120, 60)
        loadingPanel:Center()
        loadingPanel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(30, 30, 30, 220))
            draw.SimpleText("Loading...", "DermaLarge", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        loadingPanel:SetZPos(1000)
    end

    local function HideLoading()
        if loadingPanel and IsValid(loadingPanel) then loadingPanel:Remove() end
    end

    function LoadData(filter)
        ShowLoading()
        timer.Simple(0.1, function()
            entityScroll:Clear()
            npcScroll:Clear()

            local mapName = game.GetMap()
            local filePath = "rareload/player_positions_" .. mapName .. ".json"

            local errorIcon = Material("icon16/exclamation.png")
            local warningIcon = Material("icon16/error.png")

            if not file.Exists(filePath, "DATA") then
                CreateErrorPanel(entityScroll, "No Data Found", "No saved entities or NPCs found for " .. mapName,
                    errorIcon)
                CreateErrorPanel(npcScroll, "No Data Found", "No saved entities or NPCs found for " .. mapName, errorIcon)
                HideLoading()
                return
            end

            local jsonData = file.Read(filePath, "DATA")
            local success, rawData = pcall(util.JSONToTable, jsonData)

            if not success or not rawData or not rawData[mapName] then
                local errorMessage = not success and "Error parsing JSON data" or "Invalid data format"
                CreateErrorPanel(entityScroll, "Data Error", errorMessage, warningIcon)
                CreateErrorPanel(npcScroll, "Data Error", errorMessage, warningIcon)
                HideLoading()
                return
            end

            local entityCount, npcCount = 0, 0
            local entityCategories, npcCategories = 0, 0

            for steamID, playerData in pairs(rawData[mapName]) do
                if playerData.entities and #playerData.entities > 0 then
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

            if entityCount == 0 then
                CreateErrorPanel(entityScroll, "No Entities Found",
                    filter and "No entities match your search criteria" or "No saved entities found for this map",
                    errorIcon)
            end

            if npcCount == 0 then
                CreateErrorPanel(npcScroll, "No NPCs Found",
                    filter and "No NPCs match your search criteria" or "No saved NPCs found for this map", errorIcon)
            end

            ---@diagnostic disable-next-line: undefined-field
            for _, tab in pairs(tabs.Items) do
                if tab.Name == "Entities" then
                    tab.Name = "Entities (" .. entityCount .. ")"
                elseif tab.Name == "NPCs" then
                    tab.Name = "NPCs (" .. npcCount .. ")"
                end
            end

            infoLabel:SetText(string.format("Found %d entities in %d categories and %d NPCs in %d categories",
                entityCount, entityCategories, npcCount, npcCategories))
            HideLoading()
        end)
    end

    LoadData()

    -- Function to reset all data for the current map
    function ResetData()
        local mapName = game.GetMap()
        local filePath = "rareload/player_positions_" .. mapName .. ".json"

        if file.Exists(filePath, "DATA") then
            local emptyData = {}
            emptyData[mapName] = {}

            file.Write(filePath, util.TableToJSON(emptyData, true))

            net.Start("RareloadReloadData")
            net.SendToServer()

            if entityViewerFrame and IsValid(entityViewerFrame) then
                LoadData()
            end

            ShowNotification("All entity and NPC data has been reset for " .. mapName, NOTIFY_GENERIC)
        else
            ShowNotification("No data file exists for " .. mapName, NOTIFY_ERROR)
        end
    end

    local searchDelay = 0
    searchBar.OnChange = function()
        local searchText = searchBar:GetValue()

        if searchDelay then
            timer.Remove("RareloadSearch")
        end

        timer.Create("RareloadSearch", 0.3, 1, function()
            LoadData(searchText)
        end)
    end

    frame.OnSizeChanged = function(self, w, h)
        local maxW, maxH = ScrW() - 40, ScrH() - 40
        if w > maxW or h > maxH then
            self:SetSize(math.min(w, maxW), math.min(h, maxH))
            self:Center()
        end
        headerPanel:SetWide(w - 16)
        tabs:InvalidateLayout(true)
        ---@diagnostic disable-next-line: undefined-field
        if tabs and tabs.Items then
            ---@diagnostic disable-next-line: undefined-field
            for _, tab in pairs(tabs.Items) do
                if IsValid(tab.Panel) then
                    tab.Panel:InvalidateLayout(true)
                end
            end
        end
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
end

net.Receive("RareloadTeleportTo", function()
    local pos = net.ReadVector()
end)

concommand.Add("entity_viewer_open", OpenEntityViewer)
