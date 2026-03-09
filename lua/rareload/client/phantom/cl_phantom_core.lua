RARELOAD                        = RARELOAD or {}
RARELOAD.playerPositions        = RARELOAD.playerPositions or {}
RARELOAD.settings               = RARELOAD.settings or {}
RARELOAD.Phantom                = RARELOAD.Phantom or {}
RARELOAD.nextDataReload         = RARELOAD.nextDataReload or 0
RARELOAD.nextPhantomRefresh     = RARELOAD.nextPhantomRefresh or 0

local PHANTOM_UPDATE_INTERVAL   = 1.0
local DATA_RELOAD_INTERVAL      = 10.0
local PHANTOM_MAX_DISTANCE      = 10000
local PHANTOM_CULL_DISTANCE     = 10000
local PHANTOM_MAX_DISTANCE_SQR  = PHANTOM_MAX_DISTANCE * PHANTOM_MAX_DISTANCE
local PHANTOM_CULL_DISTANCE_SQR = PHANTOM_CULL_DISTANCE * PHANTOM_CULL_DISTANCE
local PHANTOM_HEAD_OFFSET       = Vector(0, 0, 80)
local PIXEL_VIS_HANDLE          = util.GetPixelVisibleHandle and util.GetPixelVisibleHandle() or nil

local function HandleNetReceive(event, callback)
    net.Receive(event, function(len)
        callback()
    end)
end

local function CreatePhantom(ply, pos, ang)
    if not IsValid(ply) then return end

    local modelToUse = "models/player/kleiner.mdl"
    local mapName = game.GetMap()
    local steamID = ply:SteamID()

    if RARELOAD.playerPositions[mapName] and
        RARELOAD.playerPositions[mapName][steamID] and
        RARELOAD.playerPositions[mapName][steamID].playermodel then
        modelToUse = RARELOAD.playerPositions[mapName][steamID].playermodel
    else
        modelToUse = ply:GetModel()
    end

    if type(pos) == "table" and not isvector(pos) and pos.x and pos.y and pos.z then
        pos = Vector(pos.x, pos.y, pos.z)
    end

    local phantom = ClientsideModel(modelToUse)
    if not IsValid(phantom) then return nil end

    if not pos then
        pos = ply:GetPos()
    end

    phantom:SetPos(pos)
    phantom:SetAngles(ang and Angle(0, ang.y, 0) or Angle(0, ply:GetAngles().y, 0))
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetSolid(SOLID_NONE)
    phantom:SetNoDraw(true)
    phantom:SetColor(Color(0, 0, 0, 0))

    return phantom
end

local function UpdatePhantomVisibility()
    local debugOn = RARELOAD.settings.debugEnabled
    local hasViewPhantomPerm = true
    local lp = LocalPlayer()
    if IsValid(lp) and RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        hasViewPhantomPerm = RARELOAD.Permissions.HasPermission(lp, "VIEW_PHANTOM")
    end
    local playerPos = LocalPlayer():GetPos()

    for steamID, phantomData in pairs(RARELOAD.Phantom) do
        local phantom = phantomData.phantom
        if IsValid(phantom) then
            local distance = playerPos:DistToSqr(phantom:GetPos())

            if distance > PHANTOM_CULL_DISTANCE_SQR then
                phantom:SetNoDraw(true)
                phantom:SetColor(Color(0, 0, 0, 0))
            elseif debugOn and hasViewPhantomPerm and distance <= PHANTOM_MAX_DISTANCE_SQR then
                phantom:SetColor(Color(255, 255, 255, 150))
                phantom:SetNoDraw(false)
            else
                phantom:SetColor(Color(0, 0, 0, 0))
                phantom:SetNoDraw(true)
            end
        end
    end
end

local function RemovePhantom(steamID)
    if not steamID then return end
    local phantomData = RARELOAD.Phantom[steamID]
    if phantomData then
        if IsValid(phantomData.phantom) then
            print("[RARELOAD DEBUG] Removing phantom for player " .. steamID)
            phantomData.phantom:Remove()
            SafeRemoveEntity(phantomData.phantom)
        end
        RARELOAD.Phantom[steamID] = nil
    end
end

local function UpdatePhantomPosition(steamID, pos, ang, model)
    if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
        local ply
        for _, p in ipairs(player.GetAll()) do
            if p:SteamID() == steamID then
                ply = p
                break
            end
        end
        if IsValid(ply) then
            RARELOAD.Phantom[steamID] = {
                phantom = CreatePhantom(ply, pos, ang),
                ply     = ply,
                steamID = steamID
            }
        end
    end

    local phantomData = RARELOAD.Phantom[steamID]
    if not (phantomData and IsValid(phantomData.phantom)) then return end

    phantomData.phantom:SetPos(pos)
    phantomData.phantom:SetAngles(Angle(0, ang.y, 0))

    if model and phantomData.phantom:GetModel() ~= model then
        phantomData.phantom:SetModel(model)
        phantomData.phantom:InvalidateBoneCache()
        UpdatePhantomVisibility()
    end
end

net.Receive("UpdatePhantomPosition", function()
    local steamID = net.ReadString()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    local hasModel = net.ReadBool()
    local model = hasModel and net.ReadString() or nil
    UpdatePhantomPosition(steamID, pos, ang, model)
end)

HandleNetReceive("SyncData", function()
    local data = net.ReadTable()
    if not data or type(data) ~= "table" then return end

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = data.playerPositions or {}

    -- Only update RARELOAD.settings from SyncData if per-player settings
    -- haven't been received yet (MySettings is empty). Otherwise per-player
    -- settings take priority over server globals.
    if not RARELOAD.MySettings or not next(RARELOAD.MySettings) then
        local oldDebugEnabled = RARELOAD.settings.debugEnabled
        RARELOAD.settings = data.settings or {}

        if oldDebugEnabled ~= RARELOAD.settings.debugEnabled then
            UpdatePhantomVisibility()
        end
    end

    -- Do NOT overwrite RARELOAD.Phantom from server data.
    -- The server's Phantom table has no valid ClientsideModel references;
    -- overwriting would destroy existing client-side phantom entities.
end)

HandleNetReceive("CreatePlayerPhantom", function()
    local ply = net.ReadEntity()
    if not IsValid(ply) then
        print("[RARELOAD DEBUG] Invalid player entity received.")
        return
    end

    local pos, ang = net.ReadVector(), net.ReadAngle()
    if not pos or pos:IsZero() then
        print("[RARELOAD DEBUG] Invalid position for phantom creation.")
        return
    end

    local steamID = IsValid(ply) and ply:SteamID() or nil
    if not steamID then return end

    RemovePhantom(steamID)

    RARELOAD.Phantom[steamID] = {
        phantom = CreatePhantom(ply, pos, ang),
        ply = ply,
        steamID = steamID
    }
end)

HandleNetReceive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    if IsValid(ply) then
        local steamID = ply:SteamID()
        if steamID and steamID ~= "" then
            RemovePhantom(steamID)
        end
    end
end)

function RARELOAD.RefreshPhantoms()
    local mapName = game.GetMap()
    if not RARELOAD.playerPositions or not RARELOAD.playerPositions[mapName] then return end
    if not RARELOAD.Phantom then RARELOAD.Phantom = {} end

    local playerPos = LocalPlayer():GetPos()
    local created = 0

    for steamID, playerData in pairs(RARELOAD.playerPositions[mapName]) do
        if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
            local pos = playerData.pos
            if type(pos) == "table" and not isvector(pos) and pos.x and pos.y and pos.z then
                pos = Vector(pos.x, pos.y, pos.z)
            end
            if pos and playerPos:DistToSqr(pos) <= PHANTOM_CULL_DISTANCE_SQR then
                local ply
                for _, p in ipairs(player.GetAll()) do
                    if p:SteamID() == steamID then
                        ply = p
                        break
                    end
                end

                if IsValid(ply) then
                    local ang = Angle(0, 0, 0)
                    if playerData.ang then
                        if type(playerData.ang) == "table" then
                            ang = Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3])
                        else
                            ang = playerData.ang
                        end
                    end

                    local phantom = CreatePhantom(ply, pos, ang)
                    if phantom then
                        RARELOAD.Phantom[steamID] = {
                            phantom = phantom,
                            ply = ply,
                            steamID = steamID,
                            lastUpdate = CurTime()
                        }
                        created = created + 1
                    end
                end
            end
        end
    end

    if created > 0 then
        UpdatePhantomVisibility()
    end
end

local function BufferPhantom()
    -- Keep as a no-op: client should not reload authoritative player position data from local disk.
    -- Data is synced from server via SyncData/SyncPlayerPositions for consistent multiplayer behavior.
end

HandleNetReceive("SyncPlayerPositions", function()
    local mapName = game.GetMap()
    local positions = net.ReadTable() or {}
    RARELOAD.playerPositions[mapName] = positions
end)

local nextPhantomCheck = 0
local nextVisibilityUpdate = 0
local lastMapName = game.GetMap()
local cachedMapPositions = nil
local lastMapCacheTime = 0

hook.Add("PostDrawOpaqueRenderables", "RARELOAD_QueuePhantomInfo", function()
    if not RARELOAD.settings.debugEnabled then return end

    BufferPhantom()

    local now = CurTime()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local hasViewPhantomPerm = true
    local lp = LocalPlayer()
    if IsValid(lp) and RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        hasViewPhantomPerm = RARELOAD.Permissions.HasPermission(lp, "VIEW_PHANTOM")
    end
    local hasValidPhantoms = false
    if RARELOAD.Phantom then
        for _, data in pairs(RARELOAD.Phantom) do
            if data and IsValid(data.phantom) then
                hasValidPhantoms = true
                break
            end
        end
    end

    local currentMap = game.GetMap()
    if currentMap ~= lastMapName then
        lastMapName = currentMap
        cachedMapPositions = nil
    end

    if now >= nextPhantomCheck then
        if not cachedMapPositions or (now - lastMapCacheTime) > 5.0 then
            cachedMapPositions = RARELOAD.playerPositions[currentMap] or {}
            lastMapCacheTime = now
        end

        if next(cachedMapPositions) then
            local needsRefresh = false
            for steamID in pairs(cachedMapPositions) do
                if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
                    needsRefresh = true
                    break
                end
            end

            if needsRefresh then
                RARELOAD.RefreshPhantoms()
            end
        end

        nextPhantomCheck = now + PHANTOM_UPDATE_INTERVAL
    end

    if now >= nextVisibilityUpdate then
        UpdatePhantomVisibility()
        nextVisibilityUpdate = now + 0.75
    end

    if type(QueuePhantomPanelsForRendering) == "function" then
        QueuePhantomPanelsForRendering()
    end
end)

hook.Add("Think", "CheckDebugModeChanges", function()
    local debugOn = RARELOAD.settings.debugEnabled
    local hasViewPhantomPerm = true
    local lp = LocalPlayer()
    if IsValid(lp) and RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        hasViewPhantomPerm = RARELOAD.Permissions.HasPermission(lp, "VIEW_PHANTOM")
    end

    if RARELOAD.lastPhantomPermState ~= hasViewPhantomPerm or RARELOAD.lastDebugState ~= debugOn then
        UpdatePhantomVisibility()
        RARELOAD.lastPhantomPermState = hasViewPhantomPerm
        RARELOAD.lastDebugState = debugOn
    end
end)

hook.Add("PlayerDisconnected", "RemovePhantomOnDisconnect", function(ply)
    if IsValid(ply) then
        RemovePhantom(ply:SteamID())
    end
end)
