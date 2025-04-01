THEME = {
    background = Color(35, 35, 40),
    header = Color(45, 45, 55),
    panel = Color(55, 55, 65),
    panelHighlight = Color(65, 65, 80),
    accent = Color(80, 140, 240),
    dangerAccent = Color(240, 80, 80),
    text = Color(235, 235, 245),
    textDark = Color(50, 50, 60),
    border = Color(75, 75, 85)
}

surface.CreateFont("RareloadHeader", {
    font = "Roboto",
    size = 22,
    weight = 600,
    antialias = true
})

surface.CreateFont("RareloadText", {
    font = "Roboto",
    size = 16,
    weight = 500,
    antialias = true
})

surface.CreateFont("RareloadSmall", {
    font = "Roboto",
    size = 14,
    weight = 400,
    antialias = true
})

function ShowNotification(message, type)
    type = type or NOTIFY_GENERIC
    notification.AddLegacy(message, type, 4)
    surface.PlaySound(type == NOTIFY_ERROR and "buttons/button10.wav" or "buttons/button15.wav")
end

function OpenEntityViewer(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        ShowNotification("You must be an admin to use this command.", NOTIFY_ERROR)
        return
    end
    ---@class DFrame
    local frame = vgui.Create("DFrame")
    frame:SetSize(ScrW() * 0.7, ScrH() * 0.8)
    frame:SetTitle("Rareload Entity & NPC Viewer - " .. game.GetMap())
    frame:SetIcon("icon16/database_connect.png")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:SetSizable(true)
    frame:SetMinWidth(800)
    frame:SetMinHeight(500)
    frame:SetBackgroundBlur(true)
    frame:SetAlpha(0)
    frame:AlphaTo(255, 0.3, 0)

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.background)
        draw.RoundedBox(4, 0, 0, w, 24, THEME.header)
    end

    local oldClose = frame.Close
    frame.Close = function(self)
        self:AlphaTo(0, 0.3, 0, function()
            oldClose(self)
        end)
    end

    local headerPanel = vgui.Create("DPanel", frame)
    headerPanel:Dock(TOP)
    headerPanel:SetTall(40)
    headerPanel:DockMargin(5, 5, 5, 0) -- Reduced bottom margin from 5 to 0
    headerPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.panel)
    end

    local infoLabel = vgui.Create("DLabel", headerPanel)
    infoLabel:SetText("Browse, teleport to, or delete saved entities and NPCs")
    infoLabel:SetFont("RareloadText")
    infoLabel:SetTextColor(THEME.text)
    infoLabel:Dock(LEFT)
    infoLabel:DockMargin(10, 0, 10, 0)
    infoLabel:SizeToContents()

    ---@class DTextEntry
    local searchBar = vgui.Create("DTextEntry", headerPanel)
    searchBar:SetPlaceholderText("Search by class name...")
    searchBar:Dock(RIGHT)
    searchBar:SetWide(250)
    searchBar:DockMargin(5, 5, 10, 5)

    ---@class DPropertySheet
    local tabs = vgui.Create("DPropertySheet", frame)
    tabs:Dock(FILL)
    tabs:DockMargin(5, 0, 5, 5) -- Reduced top margin from 5 to 0

    tabs.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.panel)
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

        scrollbar.btnUp.Paint = function(self, w, h)
            local btnColor = self:IsHovered() and colors.hover or colors.accent
            draw.RoundedBox(4, 2, 0, w - 4, h - 2, btnColor)
        end

        scrollbar.btnDown.Paint = function(self, w, h)
            local btnColor = self:IsHovered() and colors.hover or colors.accent
            draw.RoundedBox(4, 2, 2, w - 4, h - 2, btnColor)
        end

        scrollbar.btnGrip.Paint = function(self, w, h)
            local gripColor = self:IsHovered() and colors.hover or colors.accent
            draw.RoundedBox(4, 2, 0, w - 4, h, gripColor)
        end

        local sheet = tabs:AddSheet(title, scroll, icon)

        -- Style the tab button
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

    local function LoadData(filter)
        entityScroll:Clear()
        npcScroll:Clear()

        local mapName = game.GetMap()
        local filePath = "rareload/player_positions_" .. mapName .. ".json"

        local errorIcon = Material("icon16/exclamation.png")
        local warningIcon = Material("icon16/error.png")

        if not file.Exists(filePath, "DATA") then
            CreateErrorPanel(entityScroll, "No Data Found", "No saved entities or NPCs found for " .. mapName,
                errorIcon)
            CreateErrorPanel(npcScroll, "No Data Found", "No saved entities or NPCs found for " .. mapName,
                errorIcon)
            return
        end

        local jsonData = file.Read(filePath, "DATA")
        local success, rawData = pcall(util.JSONToTable, jsonData)

        if not success or not rawData or not rawData[mapName] then
            local errorMessage = not success and "Error parsing JSON data" or "Invalid data format"
            CreateErrorPanel(entityScroll, "Data Error", errorMessage, warningIcon)
            CreateErrorPanel(npcScroll, "Data Error", errorMessage, warningIcon)
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

        for k, tab in pairs(tabs.Items) do
            if tab.Name == "Entities" then
                tab.Name = "Entities (" .. entityCount .. ")"
            elseif tab.Name == "NPCs" then
                tab.Name = "NPCs (" .. npcCount .. ")"
            end
        end

        infoLabel:SetText(string.format("Found %d entities in %d categories and %d NPCs in %d categories",
            entityCount, entityCategories, npcCount, npcCategories))
    end

    LoadData()

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

    local refreshButton = vgui.Create("DButton", headerPanel)
    refreshButton:SetText("")
    refreshButton:SetSize(30, 30)
    refreshButton:SetPos(headerPanel:GetWide() - 300, 5)
    refreshButton:DockMargin(0, 0, 10, 0)
    refreshButton.Paint = function(self, w, h)
        local color = self:IsHovered() and
            Color(THEME.accent.r * 1.2, THEME.accent.g * 1.2, THEME.accent.b * 1.2) or THEME.accent
        draw.RoundedBox(4, 0, 0, w, h, color)

        surface.SetDrawColor(255, 255, 255)
        surface.SetMaterial(Material("icon16/arrow_refresh.png"))
        surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
    end
    refreshButton.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        ShowNotification("Refreshing data...", NOTIFY_GENERIC)
        LoadData(searchBar:GetValue())
    end

    frame.OnSizeChanged = function(self, w, h)
        headerPanel:SetWide(w - 10)
        refreshButton:SetPos(searchBar:GetX() - 40, 5)

        tabs:InvalidateLayout(true)

        if tabs and tabs.Items then
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
end

net.Receive("RareloadTeleportTo", function()
    local pos = net.ReadVector()
end)


concommand.Add("entity_viewer_open", OpenEntityViewer)
