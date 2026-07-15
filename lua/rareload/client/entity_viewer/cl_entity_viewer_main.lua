local draw, surface, util, vgui, hook = draw, surface, util, vgui, hook
local math, string = math, string
local Color, Vector, Angle = Color, Vector, Angle
local IsValid, FrameTime, Lerp = IsValid, FrameTime, Lerp
local TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT = TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT

include("cl_entity_viewer_theme.lua")
include("cl_entity_viewer_utils.lua")
local SnapshotUtils       = include("rareload/shared/rareload_snapshot_utils.lua")

EV_THEME                  = THEME
local function L(key, ...)
    if RARELOAD and RARELOAD.L then return RARELOAD.L(key, ...) end
    return key
end
local EntityViewer        = {}
EntityViewer.Frame        = nil
EntityViewer.Data         = {}
EntityViewer.FilteredData = {}
EntityViewer.SearchText   = ""
EntityViewer.Category     = "All"
EntityViewer.SortMode     = "Name"
EntityViewer.PendingDeleteBatch = nil

local function ResolveDeleteEntityID(entityData)
    if not (entityData and entityData.rawData) then return "" end
    local raw = entityData.rawData
    return raw.id or raw.RareloadNPCID or raw.RareloadEntityID or raw.RareloadID or raw.UniqueID or ""
end

local function SendDeleteRequest(entityData, options)
    options = options or {}
    local entityId = ResolveDeleteEntityID(entityData)

    net.Start("RareloadEntityViewer_Delete")
    net.WriteString(tostring(entityId))
    net.WriteString(entityData.class or "Unknown")

    local posX, posY, posZ = 0, 0, 0
    if entityData.pos then
        posX = entityData.pos.x or 0
        posY = entityData.pos.y or 0
        posZ = entityData.pos.z or 0
    end
    net.WriteFloat(posX)
    net.WriteFloat(posY)
    net.WriteFloat(posZ)
    net.SendToServer()

    return true
end

local function SendDeleteManyRequest(items)
    if not istable(items) or #items == 0 then return false end

    net.Start("RareloadEntityViewer_DeleteMany")
    net.WriteUInt(#items, 16)

    for _, entityData in ipairs(items) do
        local entityId = ResolveDeleteEntityID(entityData)
        net.WriteString(tostring(entityId))
        net.WriteString(tostring(entityData.class or "Unknown"))

        local posX, posY, posZ = 0, 0, 0
        if entityData.pos then
            posX = entityData.pos.x or 0
            posY = entityData.pos.y or 0
            posZ = entityData.pos.z or 0
        end

        net.WriteFloat(posX)
        net.WriteFloat(posY)
        net.WriteFloat(posZ)
    end

    net.SendToServer()
    return true
end

local function SendRespawnRequest(entityData, options)
    options = options or {}
    if not entityData or not entityData.class or entityData.class == "" then return end

    local pos = entityData.pos
    if istable(pos) and not (isvector and isvector(pos)) then
        pos = Vector(pos.x or 0, pos.y or 0, pos.z or 0)
    end
    if not pos then return end

    -- NPCs and entities live in separate server snapshots with separate handlers.
    net.Start(entityData.isNPC and "RareloadRespawnNPC" or "RareloadRespawnEntity")
    net.WriteString(entityData.class)
    net.WriteString(tostring(entityData.id or ResolveDeleteEntityID(entityData) or ""))
    net.WriteVector(pos)
    net.SendToServer()

    timer.Simple(0.25, function()
        if SED and SED.RescanLate then
            SED.RescanLate()
        elseif SED and SED.RebuildSavedLookup then
            SED.RebuildSavedLookup()
        end
    end)

    return true
end

local function ExtractEntities(tbl, result, isNPC)
    result = result or {}
    if not tbl then return result end

    if (tbl.Class or tbl.class) and (tbl.Pos or tbl.pos) then
        local posData    = tbl.Pos or tbl.pos
        local fallbackID = nil

        if istable(posData) and posData.x and posData.y and posData.z then
            fallbackID = string.format("%s_%0.3f_%0.3f_%0.3f",
                tostring(tbl.Class or tbl.class or "ent"),
                tonumber(posData.x) or 0,
                tonumber(posData.y) or 0,
                tonumber(posData.z) or 0)
        end

        local ent = {
            id        = tbl.id or tbl.RareloadNPCID or tbl.RareloadEntityID
                or tbl.RareloadID or tbl.UniqueID or fallbackID
                or tostring(math.random(100000, 999999)),
            class     = tbl.Class or tbl.class,
            model     = tbl.Model or tbl.model,
            pos       = tbl.Pos or tbl.pos,
            ang       = tbl.Angle or tbl.ang or tbl.angle,
            health    = tbl.CurHealth or tbl.health,
            maxHealth = tbl.MaxHealth or tbl.maxHealth,
            skin      = tbl.Skin or tbl.skin,
            isNPC     = isNPC or false,
            rawData   = tbl,
        }

        if istable(ent.pos) then
            if ent.pos.__rareload_type == "Vector" then
                ent.pos = Vector(ent.pos.x, ent.pos.y, ent.pos.z)
            else
                ent.pos = Vector(ent.pos.x or 0, ent.pos.y or 0, ent.pos.z or 0)
            end
        end

        if istable(ent.ang) then
            if ent.ang.__rareload_type == "Angle" then
                ent.ang = Angle(ent.ang.p, ent.ang.y, ent.ang.r)
            else
                ent.ang = Angle(ent.ang.p or 0, ent.ang.y or 0, ent.ang.r or 0)
            end
        end

        table.insert(result, ent)
        return result
    end

    for _, v in pairs(tbl) do
        if type(v) == "table" then
            ExtractEntities(v, result, isNPC)
        end
    end

    return result
end

function EntityViewer:LoadData()
    local mapName = game.GetMap()
    local mapData = RARELOAD and RARELOAD.playerPositions and RARELOAD.playerPositions[mapName]
    if not istable(mapData) then return {} end

    local localPly = LocalPlayer()
    if not IsValid(localPly) then return {} end

    local localSteamID = localPly:SteamID()
    if not localSteamID or localSteamID == "" then return {} end

    local playerData = mapData[localSteamID]
    if not istable(playerData) then return {} end

    local entityList = SnapshotUtils and SnapshotUtils.GetSummary and
        SnapshotUtils.GetSummary(playerData.entities, { category = "entity", idPrefix = "entity" }) or {}
    local npcList = SnapshotUtils and SnapshotUtils.GetSummary and
        SnapshotUtils.GetSummary(playerData.npcs, { category = "npc", idPrefix = "npc" }) or {}

    local loaded = {}
    ExtractEntities(entityList, loaded, false)
    ExtractEntities(npcList, loaded, true)
    return loaded
end

function EntityViewer:FilterAndSort()
    self.FilteredData = {}
    local search      = string.lower(self.SearchText)
    local cat         = self.Category

    for _, ent in ipairs(self.Data) do
        local class = string.lower(ent.class or "")
        local model = string.lower(ent.model or "")

        local matchCat =
            cat == "All" or
            (cat == "NPCs" and string.find(class, "npc")) or
            (cat == "Weapons" and string.find(class, "weapon")) or
            (cat == "Vehicles" and (string.find(class, "vehicle") or
                string.find(class, "jeep") or
                string.find(class, "airboat"))) or
            (cat == "Props" and string.find(class, "prop"))

        local matchSearch = (search == "") or string.find(class, search) or string.find(model, search)

        if matchCat and matchSearch then
            table.insert(self.FilteredData, ent)
        end
    end

    table.sort(self.FilteredData, function(a, b)
        if self.SortMode == "Name" then
            return (a.class or "") < (b.class or "")
        elseif self.SortMode == "Distance" and IsValid(LocalPlayer()) then
            local dA = a.pos and LocalPlayer():GetPos():DistToSqr(a.pos) or math.huge
            local dB = b.pos and LocalPlayer():GetPos():DistToSqr(b.pos) or math.huge
            return dA < dB
        elseif self.SortMode == "Health" then
            return (tonumber(a.health) or 0) > (tonumber(b.health) or 0)
        end
        return false
    end)
end

function EntityViewer:ReloadDataAndRefresh()
    self.Data = self:LoadData()
    self:RefreshList()
end

local function ShowBulkConfirmation(title, message, onConfirm)
    Derma_Query(message, title, L("common.proceed"), function()
        if onConfirm then
            onConfirm()
        end
    end, L("common.cancel"))
end

-- category is the internal token ("All", "NPCs", ...); displayText is localized.
local function CreateSidebarButton(parent, category, displayText, yPos, onClick, viewer)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetPos(12, yPos)
    btn:SetSize(196, 44)
    btn.Category  = category
    btn.HoverAnim = 0

    btn.Paint     = function(self, w, h)
        local isSelected = viewer.Category == self.Category
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim,
            (self:IsHovered() or isSelected) and 1 or 0)

        if isSelected then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(EV_THEME.primary, 40))
            draw.RoundedBox(3, 0, 8, 4, h - 16, EV_THEME.primary)
        elseif self.HoverAnim > 0 then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(EV_THEME.surface, self.HoverAnim * 80))
        end

        local textCol = isSelected and EV_THEME.primary
            or THEME:LerpColor(self.HoverAnim, EV_THEME.textSecondary, EV_THEME.textPrimary)
        draw.SimpleText(displayText, "RareloadBody", 20, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    btn.DoClick   = onClick
    return btn
end

local function CreateEntityCard(parent, data, onTeleport, onDelete, onDetails, onRespawn)
    local card = vgui.Create("DButton", parent)
    card:SetText("")
    card:SetSize(185, 235)

    local typeColor = EV_THEME:GetEntityTypeColor(data.class)
    local hoverAnim = 0

    card.Paint = function(self, w, h)
        hoverAnim = Lerp(FrameTime() * 10, hoverAnim, self:IsHovered() and 1 or 0)

        if hoverAnim > 0.01 then
            draw.RoundedBox(12, 3, 3, w, h, ColorAlpha(Color(0, 0, 0), 50 * hoverAnim))
        end

        draw.RoundedBox(12, 0, 0, w, h, EV_THEME.surface)

        if hoverAnim > 0.01 then
            draw.RoundedBox(12, 0, 0, w, h, ColorAlpha(EV_THEME.primary, 12 * hoverAnim))
            surface.SetDrawColor(ColorAlpha(EV_THEME.primary, 80 * hoverAnim))
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end

        draw.RoundedBoxEx(8, 0, h - 4, w, 4, typeColor, false, false, true, true)
    end

    local previewBg = vgui.Create("DPanel", card)
    previewBg:SetPos(8, 8)
    previewBg:SetSize(169, 120)
    previewBg.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.backgroundDark)
    end

    if data.model and util.IsValidModel(data.model) then
        local modelPanel = vgui.Create("DModelPanel", previewBg)
        modelPanel:SetPos(0, 0)
        modelPanel:SetSize(169, 120)
        modelPanel:SetModel(data.model)
        modelPanel:SetMouseInputEnabled(false)

        local ent = modelPanel:GetEntity()
        if IsValid(ent) then
            local mn, mx = ent:GetRenderBounds()
            local center = (mn + mx) * 0.5
            local size   = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
            local fov    = 45
            local dist   = (size * 1.2) / math.tan(math.rad(fov / 2))

            modelPanel:SetLookAt(center)
            modelPanel:SetCamPos(center + Vector(dist * 0.6, dist * 0.5, dist * 0.4))
            modelPanel:SetFOV(fov)
            modelPanel.LayoutEntity = function(self, e)
                e:SetAngles(Angle(0, RealTime() * 30, 0))
            end
        end
    else
        previewBg.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, EV_THEME.backgroundDark)
            draw.SimpleText("?", "RareloadDisplay", w / 2, h / 2,
                EV_THEME.textDisabled, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local name = data.class or L("common.unknown")
    if #name > 20 then name = string.sub(name, 1, 18) .. "..." end

    local lblName = vgui.Create("DLabel", card)
    lblName:SetText(name)
    lblName:SetFont("RareloadBody")
    lblName:SetTextColor(EV_THEME.textPrimary)
    lblName:SetPos(8, 132)
    lblName:SetSize(169, 20)
    lblName:SetContentAlignment(5)

    local yOffset = 155
    if data.health and data.maxHealth then
        local hp    = tonumber(data.health) or 0
        local maxHp = tonumber(data.maxHealth) or hp
        if maxHp > 0 then
            local hpBar = vgui.Create("DPanel", card)
            hpBar:SetPos(16, yOffset)
            hpBar:SetSize(153, 5)
            hpBar.Paint = function(self, w, h)
                draw.RoundedBox(3, 0, 0, w, h, EV_THEME.backgroundDark)
                local frac      = math.Clamp(hp / maxHp, 0, 1)
                local healthCol = EV_THEME:GetHealthColor(hp, maxHp)
                draw.RoundedBox(3, 0, 0, w * frac, h, healthCol)
            end
            yOffset = yOffset + 10
        end
    end

    if data.pos and IsValid(LocalPlayer()) then
        local dist      = math.Round(LocalPlayer():GetPos():Distance(data.pos))
        local distLabel = vgui.Create("DLabel", card)
        distLabel:SetText(L("ev.units", dist))
        distLabel:SetFont("RareloadCaption")
        distLabel:SetTextColor(EV_THEME.textSecondary)
        distLabel:SetPos(8, yOffset)
        distLabel:SetSize(169, 16)
        distLabel:SetContentAlignment(5)
    end

    local btnContainer = vgui.Create("DPanel", card)
    btnContainer:SetPos(8, 195)
    btnContainer:SetSize(169, 32)
    btnContainer.Paint = function() end

    local function CreateSmallButton(x, w, icon, tooltip, hoverColor, onClick)
        local btn = vgui.Create("DButton", btnContainer)
        btn:SetText("")
        btn:SetPos(x, 0)
        btn:SetSize(w, 28)
        btn:SetTooltip(tooltip)
        btn.HoverAnim = 0
        btn.Paint = function(self, bw, bh)
            self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
            local col = THEME:LerpColor(self.HoverAnim, EV_THEME.surfaceVariant, hoverColor)
            draw.RoundedBox(6, 0, 0, bw, bh, col)
            surface.SetDrawColor(255, 255, 255, 180 + 75 * self.HoverAnim)
            surface.SetMaterial(Material(icon))
            surface.DrawTexturedRect(bw / 2 - 8, bh / 2 - 8, 16, 16)
        end
        btn.DoClick = onClick
        return btn
    end

    CreateSmallButton(0, 40, "icon16/arrow_right.png", L("ev.card.teleport"), EV_THEME.success,
        function() if onTeleport then onTeleport(data) end end)
    CreateSmallButton(43, 40, "icon16/arrow_refresh.png", L("ev.card.respawn"), EV_THEME.info,
        function() if onRespawn then onRespawn(data) end end)
    CreateSmallButton(86, 40, "icon16/cross.png", L("ev.card.delete"), EV_THEME.error,
        function() if onDelete then onDelete(data) end end)
    CreateSmallButton(129, 40, "icon16/information.png", L("ev.card.details"), EV_THEME.info,
        function() if onDetails then onDetails(data) end end)

    card.DoClick = function()
        if onDetails then onDetails(data) end
    end

    return card
end

function EntityViewer:Open()
    if IsValid(self.Frame) then self.Frame:Close() end

    self.Data = self:LoadData()
    self:FilterAndSort()

    local frame = vgui.Create("DFrame")
    frame:SetSize(920, 620)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:SetSizable(false)
    self.Frame = frame

    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 0, 0, w, h, EV_THEME.background)
        draw.RoundedBoxEx(12, 0, 0, 200, h, EV_THEME.backgroundDark, true, false, true, false)
        surface.SetDrawColor(EV_THEME.divider)
        surface.DrawLine(200, 0, 200, h)
        surface.DrawLine(200, 55, w, 55)
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetText("")
    closeBtn:SetSize(36, 36)
    closeBtn:SetPos(920 - 48, 10)
    closeBtn.HoverAnim = 0
    closeBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.surface)
        if self.HoverAnim > 0 then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(EV_THEME.error, 200 * self.HoverAnim))
        end
        draw.SimpleText("✕", "RareloadSubheading", w / 2, h / 2,
            THEME:LerpColor(self.HoverAnim, EV_THEME.textSecondary, EV_THEME.textPrimary),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Close() end
    self.CloseBtn = closeBtn

    local sidebarHeader = vgui.Create("DPanel", frame)
    sidebarHeader:SetPos(0, 0)
    sidebarHeader:SetSize(200, 70)
    sidebarHeader.Paint = function(self, w, h)
        draw.SimpleText("Rareload", "RareloadHeading", 16, 18, EV_THEME.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(L("ev.title"), "RareloadCaption", 16, 42, EV_THEME.textSecondary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
    end

    -- First element is the internal filter token, second the localization key.
    local categories = {
        { "All",      "ev.cat.all" },
        { "NPCs",     "ev.cat.npcs" },
        { "Weapons",  "ev.cat.weapons" },
        { "Vehicles", "ev.cat.vehicles" },
        { "Props",    "ev.cat.props" },
    }
    for i, cat in ipairs(categories) do
        CreateSidebarButton(frame, cat[1], L(cat[2]), 70 + (i - 1) * 48, function()
            EntityViewer.Category = cat[1]
            EntityViewer:RefreshList()
        end, self)
    end

    local statsPanel = vgui.Create("DPanel", frame)
    statsPanel:SetPos(10, 520)
    statsPanel:SetSize(180, 85)
    statsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.surface)
        local total    = #EntityViewer.Data
        local filtered = #EntityViewer.FilteredData
        draw.SimpleText(L("ev.stats"), "RareloadLabel", 12, 10, EV_THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(L("ev.stats.total", total), "RareloadCaption", 12, 32, EV_THEME.textPrimary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(L("ev.stats.showing", filtered), "RareloadCaption", 12, 50, EV_THEME.primary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(L("ev.stats.map", game.GetMap()), "RareloadCaption", 12, 68, EV_THEME.textTertiary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
    end

    local topBar = vgui.Create("DPanel", frame)
    topBar:SetPos(210, 0)
    topBar:SetSize(700, 55)
    topBar.Paint = function() end

    local searchContainer = vgui.Create("DPanel", topBar)
    searchContainer:SetPos(8, 10)
    searchContainer:SetSize(260, 36)
    searchContainer.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.surface)
    end

    local searchIcon = vgui.Create("DPanel", searchContainer)
    searchIcon:SetPos(10, 10)
    searchIcon:SetSize(16, 16)
    searchIcon.Paint = function(self, w, h)
        surface.SetDrawColor(EV_THEME.textSecondary)
        surface.SetMaterial(Material("icon16/magnifier.png"))
        surface.DrawTexturedRect(0, 0, 16, 16)
    end

    local searchEntry = vgui.Create("DTextEntry", searchContainer)
    searchEntry:SetPos(32, 6)
    searchEntry:SetSize(216, 24)
    searchEntry:SetFont("RareloadBody")
    searchEntry:SetTextColor(EV_THEME.textPrimary)
    searchEntry:SetDrawBackground(false)
    searchEntry:SetPlaceholderText(L("ev.search_placeholder"))
    searchEntry.Paint = function(self, w, h)
        self:DrawTextEntryText(EV_THEME.textPrimary, EV_THEME.primary, EV_THEME.textPrimary)
        if self:GetValue() == "" then
            draw.SimpleText(L("ev.search_placeholder"), "RareloadBody", 0, h / 2,
                EV_THEME.textTertiary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    searchEntry.OnChange = function(self)
        EntityViewer.SearchText = self:GetValue()
        EntityViewer:RefreshList()
    end

    local sortBtn = vgui.Create("DButton", topBar)
    sortBtn:SetPos(278, 10)
    sortBtn:SetSize(110, 36)
    sortBtn:SetText("")
    sortBtn.HoverAnim = 0
    sortBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 10, self.HoverAnim, self:IsHovered() and 1 or 0)
        local bgCol = THEME:LerpColor(self.HoverAnim * 0.3, EV_THEME.surface, EV_THEME.primary)
        draw.RoundedBox(8, 0, 0, w, h, bgCol)
        draw.SimpleText(L("ev.sort", L("ev.sort." .. string.lower(EntityViewer.SortMode))), "RareloadBody", w / 2, h / 2,
            EV_THEME.textPrimary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    sortBtn.DoClick = function()
        if EntityViewer.SortMode == "Name" then
            EntityViewer.SortMode = "Distance"
        elseif EntityViewer.SortMode == "Distance" then
            EntityViewer.SortMode = "Health"
        else
            EntityViewer.SortMode = "Name"
        end
        EntityViewer:RefreshList()
    end

    local refreshBtn = vgui.Create("DButton", topBar)
    refreshBtn:SetPos(660, 10)
    refreshBtn:SetSize(36, 36)
    refreshBtn:SetText("")
    refreshBtn:SetTooltip(L("ev.refresh_tip"))
    refreshBtn.HoverAnim = 0
    refreshBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 10, self.HoverAnim, self:IsHovered() and 1 or 0)
        local bgCol = THEME:LerpColor(self.HoverAnim, EV_THEME.surface, EV_THEME.primary)
        draw.RoundedBox(8, 0, 0, w, h, bgCol)
        surface.SetDrawColor(255, 255, 255, 180 + 75 * self.HoverAnim)
        surface.SetMaterial(Material("icon16/arrow_refresh.png"))
        surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
    end
    refreshBtn.DoClick = function()
        EntityViewer:ReloadDataAndRefresh()
        ShowNotification(L("ev.data_refreshed"), NOTIFY_GENERIC)
    end

    local respawnAllBtn = vgui.Create("DButton", topBar)
    respawnAllBtn:SetPos(396, 10)
    respawnAllBtn:SetSize(116, 36)
    respawnAllBtn:SetText("")
    respawnAllBtn:SetTooltip(L("ev.respawn_all_tip"))
    respawnAllBtn.HoverAnim = 0
    respawnAllBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 10, self.HoverAnim, self:IsHovered() and 1 or 0)
        local bgCol = THEME:LerpColor(self.HoverAnim * 0.4, EV_THEME.surface, EV_THEME.info)
        draw.RoundedBox(8, 0, 0, w, h, bgCol)
        draw.SimpleText(L("ev.respawn_all"), "RareloadBody", w / 2, h / 2,
            EV_THEME.textPrimary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    respawnAllBtn.DoClick = function()
        local items = EntityViewer.FilteredData or {}
        local total = #items
        if total == 0 then
            ShowNotification(L("ev.no_match_filters"), NOTIFY_ERROR)
            return
        end

        ShowBulkConfirmation(L("ev.respawn_all"), L("ev.respawn_confirm", total), function()
            local respawned = 0
            for _, data in ipairs(items) do
                if SendRespawnRequest(data) then
                    respawned = respawned + 1
                end
            end

            ShowNotification(L("ev.respawned_n", respawned),
                respawned > 0 and NOTIFY_GENERIC or NOTIFY_ERROR)
        end)
    end

    local deleteAllBtn = vgui.Create("DButton", topBar)
    deleteAllBtn:SetPos(520, 10)
    deleteAllBtn:SetSize(116, 36)
    deleteAllBtn:SetText("")
    deleteAllBtn:SetTooltip(L("ev.delete_all_tip"))
    deleteAllBtn.HoverAnim = 0
    deleteAllBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 10, self.HoverAnim, self:IsHovered() and 1 or 0)
        local bgCol = THEME:LerpColor(self.HoverAnim * 0.4, EV_THEME.surface, EV_THEME.error)
        draw.RoundedBox(8, 0, 0, w, h, bgCol)
        draw.SimpleText(L("ev.delete_all"), "RareloadBody", w / 2, h / 2,
            EV_THEME.textPrimary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    deleteAllBtn.DoClick = function()
        local items = EntityViewer.FilteredData or {}
        local total = #items
        if total == 0 then
            ShowNotification(L("ev.no_match_filters"), NOTIFY_ERROR)
            return
        end

        ShowBulkConfirmation(L("ev.delete_all"), L("ev.delete_confirm", total), function()
            if SendDeleteManyRequest(items) then
                ShowNotification(L("ev.deleting_n", total), NOTIFY_GENERIC)
            end
        end)
    end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(208, 63)
    scroll:SetSize(704, 550)

    local sbar = scroll:GetVBar()
    sbar:SetWide(6)
    sbar.Paint         = function(self, w, h) draw.RoundedBox(3, 0, 0, w, h, EV_THEME.backgroundDark) end
    sbar.btnUp.Paint   = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(self, w, h) draw.RoundedBox(3, 0, 0, w, h, EV_THEME.primary) end

    local grid         = vgui.Create("DIconLayout", scroll)
    grid:SetPos(12, 12)
    grid:SetWide(scroll:GetWide() - 24)
    grid:SetSpaceX(12)
    grid:SetSpaceY(12)
    self.Grid = grid

    if IsValid(self.CloseBtn) then self.CloseBtn:MoveToFront() end

    self:RefreshList()
end

function EntityViewer:RefreshList()
    if not IsValid(self.Grid) then return end

    self:FilterAndSort()
    self.Grid:Clear()

    if #self.FilteredData == 0 then
        local emptyLabel = vgui.Create("DPanel", self.Grid)
        emptyLabel:SetSize(660, 180)
        emptyLabel.Paint = function(self, w, h)
            draw.SimpleText(L("ev.no_entities"), "RareloadSubheading", w / 2, h / 2 - 12,
                EV_THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(L("ev.no_entities_hint"), "RareloadCaption",
                w / 2, h / 2 + 12, EV_THEME.textTertiary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    local viewer = self
    local count  = 0

    for _, entData in ipairs(self.FilteredData) do
        CreateEntityCard(self.Grid, entData,
            function(data)
                if data.pos then
                    RunConsoleCommand("rareload_teleport_to", data.pos.x, data.pos.y, data.pos.z)
                    ShowNotification(L("ev.teleporting"), NOTIFY_GENERIC)
                end
            end,
            function(data)
                SendDeleteRequest(data)
            end,
            function(data)
                CreateDetailsPanel(data, false, function(d)
                    SendDeleteRequest(d)
                end, nil)
            end,
            function(data)
                if SendRespawnRequest(data) then
                    ShowNotification(L("ev.respawning", data.class or L("ev.entity_fallback")), NOTIFY_GENERIC)
                end
            end
        )
        count = count + 1
        if count > 150 then break end
    end

    self.Grid:InvalidateLayout(true)
end

net.Receive("RareloadEntityViewer_DeleteResult", function()
    local success = net.ReadBool()
    local message = net.ReadString()

    if success then
        ShowNotification(message, NOTIFY_GENERIC)
        timer.Simple(0.2, function()
            if EntityViewer.Frame and IsValid(EntityViewer.Frame) then
                EntityViewer:ReloadDataAndRefresh()
            end
        end)
    else
        ShowNotification(message, NOTIFY_ERROR)
    end
end)

concommand.Add("rareload_entity_viewer", function() EntityViewer:Open() end)
concommand.Add("entity_viewer_open", function() EntityViewer:Open() end)

function OpenEntityViewer()
    EntityViewer:Open()
end

hook.Add("RareloadPlayerPositionsUpdated", "RARELOAD_EntityViewer_AutoRefresh", function(mapName)
    if mapName ~= game.GetMap() then return end
    if not (EntityViewer.Frame and IsValid(EntityViewer.Frame)) then return end
    EntityViewer:ReloadDataAndRefresh()
end)
