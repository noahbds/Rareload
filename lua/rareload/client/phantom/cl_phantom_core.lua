RARELOAD                        = RARELOAD or {}
RARELOAD.playerPositions        = RARELOAD.playerPositions or {}
RARELOAD.settings               = RARELOAD.settings or {}
RARELOAD.Phantom                = RARELOAD.Phantom or {}
RARELOAD.nextDataReload         = RARELOAD.nextDataReload or 0
RARELOAD.nextPhantomRefresh     = RARELOAD.nextPhantomRefresh or 0

local PHANTOM_UPDATE_INTERVAL   = 1.0
local DATA_RELOAD_INTERVAL      = 10.0
local PHANTOM_MAX_DISTANCE      = 2000
local PHANTOM_CULL_DISTANCE     = 3000
local PHANTOM_MAX_DISTANCE_SQR  = PHANTOM_MAX_DISTANCE * PHANTOM_MAX_DISTANCE
local PHANTOM_CULL_DISTANCE_SQR = PHANTOM_CULL_DISTANCE * PHANTOM_CULL_DISTANCE
local PHANTOM_HEAD_OFFSET       = Vector(0, 0, 80)
local PIXEL_VIS_HANDLE          = util.GetPixelVisibleHandle and util.GetPixelVisibleHandle() or nil

local function HandleNetReceive(event, callback)
    net.Receive(event, function(len, ply)
        if not IsValid(ply) then return end
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
    local isDebugEnabled = RARELOAD.settings.debugEnabled
    local playerPos = LocalPlayer():GetPos()

    for steamID, phantomData in pairs(RARELOAD.Phantom) do
        local phantom = phantomData.phantom
        if IsValid(phantom) then
            local distance = playerPos:DistToSqr(phantom:GetPos())

            if distance > PHANTOM_CULL_DISTANCE_SQR then
                phantom:SetNoDraw(true)
                phantom:SetColor(Color(0, 0, 0, 0))
            elseif isDebugEnabled and distance <= PHANTOM_MAX_DISTANCE_SQR then
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
                ply     = ply
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

    local oldDebugEnabled = RARELOAD.settings.debugEnabled
    RARELOAD.settings = data.settings or {}
    RARELOAD.Phantom = data.Phantom or {}

    if oldDebugEnabled ~= RARELOAD.settings.debugEnabled then
        UpdatePhantomVisibility()
    end
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

    local steamID = ply:SteamID()
    if not steamID then return end

    RemovePhantom(steamID)

    RARELOAD.Phantom[steamID] = {
        phantom = CreatePhantom(ply, pos, ang),
        ply = ply
    }
end)

HandleNetReceive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    if IsValid(ply) then
        RemovePhantom(ply:SteamID())
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
    if CurTime() < RARELOAD.nextDataReload then return end
    RARELOAD.nextDataReload = CurTime() + DATA_RELOAD_INTERVAL

    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"
    if not file.Exists(filePath, "DATA") then return end

    local data = file.Read(filePath, "DATA")
    if not data or data == "" then return end
    local ok, tbl = pcall(util.JSONToTable, data)
    if ok and type(tbl) == "table" then
        RARELOAD.playerPositions = tbl
    end
end

local nextPhantomCheck = 0
local nextVisibilityUpdate = 0
local lastMapName = game.GetMap()
local eyeForwardCache = Vector(1, 0, 0)

hook.Add("PostDrawOpaqueRenderables", "DrawPlayerPhantomInfo", function()
    BufferPhantom()

    local now = CurTime()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local playerPos = lp:GetPos()
    local eyePos = EyePos()
    local eyeAng = EyeAngles()
    eyeForwardCache = eyeAng:Forward()

    if now >= nextPhantomCheck then
        local map = game.GetMap()
        if map ~= lastMapName then
            lastMapName = map
        end
        local posTbl = RARELOAD.playerPositions[map] or {}
        local needsRefresh = false

        for steamID in pairs(posTbl) do
            if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
                needsRefresh = true
                break
            end
        end

        if needsRefresh then
            RARELOAD.RefreshPhantoms()
        end

        nextPhantomCheck = now + PHANTOM_UPDATE_INTERVAL
    end

    if now >= nextVisibilityUpdate then
        UpdatePhantomVisibility()
        nextVisibilityUpdate = now + 0.5
    end

    if RARELOAD.settings.debugEnabled and next(RARELOAD.Phantom) then
        local mapName = lastMapName
        local drawnCount = 0

        local ft = FrameTime()
        local drawBudget = math.max(3, math.min(10, math.floor(0.006 / math.max(ft, 0.001))))

        for _, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) and drawnCount < drawBudget then
                local ph = data.phantom
                local phPos = ph:GetPos()
                local distance = playerPos:DistToSqr(phPos)
                if distance <= PHANTOM_MAX_DISTANCE_SQR then
                    local toPhantom = phPos + PHANTOM_HEAD_OFFSET - eyePos
                    if eyeForwardCache:Dot(toPhantom) > 0 then
                        if not PIXEL_VIS_HANDLE or util.PixelVisible(phPos + PHANTOM_HEAD_OFFSET, 4, PIXEL_VIS_HANDLE) > 0.05 then
                            DrawPhantomInfo(data, playerPos, mapName)
                            drawnCount = drawnCount + 1
                        end
                    end
                end
            end
        end
    end
end)

hook.Add("Think", "CheckDebugModeChanges", function()
    local currentDebugState = RARELOAD.settings.debugEnabled

    if RARELOAD.lastDebugState ~= currentDebugState then
        UpdatePhantomVisibility()
        RARELOAD.lastDebugState = currentDebugState
    end
end)

hook.Add("PlayerDisconnected", "RemovePhantomOnDisconnect", function(ply)
    if IsValid(ply) then
        RemovePhantom(ply:SteamID())
    end
end)
