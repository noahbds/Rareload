RARELOAD = RARELOAD or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Phantom = RARELOAD.Phantom or {}

function HandleNetReceive(event, callback)
    net.Receive(event, function(len, ply)
        if not IsValid(ply) then return end
        callback()
    end)
end

function CreatePhantom(ply, pos, ang)
    if not IsValid(ply) then return end

    local phantom = ClientsideModel(ply:GetModel())
    phantom:SetPos(pos)

    local correctedAng
    if ang then
        correctedAng = Angle(0, ang.y, 0)
    else
        correctedAng = Angle(0, ply:GetAngles().y, 0)
    end

    phantom:SetAngles(correctedAng)
    ---@diagnostic disable-next-line: inject-field
    phantom.isPhantom = true
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
    phantom:SetColor(Color(255, 255, 255, 100))

    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetSolid(SOLID_NONE)

    if RARELOAD.settings.debugEnabled then
        phantom:SetColor(Color(255, 255, 255, 150))
        phantom:SetNoDraw(false)
    else
        phantom:SetColor(Color(0, 0, 0, 0))
        phantom:SetNoDraw(true)
    end

    return phantom
end

function UpdatePhantomVisibility()
    local isDebugEnabled = RARELOAD.settings.debugEnabled

    for steamID, phantomData in pairs(RARELOAD.Phantom) do
        local phantom = phantomData.phantom
        if IsValid(phantom) then
            if isDebugEnabled then
                phantom:SetColor(Color(255, 255, 255, 150))
                phantom:SetNoDraw(false)
            else
                phantom:SetColor(Color(0, 0, 0, 0))
                phantom:SetNoDraw(true)
            end
        end
    end
end

function RemovePhantom(steamID)
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

function UpdatePhantomPosition(steamID, pos, ang)
    local phantomData = RARELOAD.Phantom[steamID]
    if phantomData and IsValid(phantomData.phantom) then
        phantomData.phantom:SetPos(pos)
        phantomData.phantom:SetAngles(Angle(0, ang.y, 0))
    end
end

net.Receive("UpdatePhantomPosition", function()
    local steamID = net.ReadString()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    UpdatePhantomPosition(steamID, pos, ang)
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

    ---@diagnostic disable-next-line: undefined-field
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
        ---@diagnostic disable-next-line: undefined-field
        RemovePhantom(ply:SteamID())
    end
end)

local fileNotExistPrinted = false


local function reloadSavedData()
    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"

    if not file.Exists(filePath, "DATA") then
        if not fileNotExistPrinted then
            print("[RARELOAD DEBUG] File does not exist: " .. filePath)
            fileNotExistPrinted = true
        end
        return
    end

    local data = file.Read(filePath, "DATA")
    if not data or data == "" then
        print("[RARELOAD DEBUG] File is empty: " .. filePath)
        return
    end

    local status, result = pcall(util.JSONToTable, data)
    if status and result then
        RARELOAD.playerPositions = result
    else
        print("[RARELOAD DEBUG] Error parsing JSON: " .. tostring(result))
    end
end



function RARELOAD.RefreshPhantoms()
    local mapName = game.GetMap()

    if not RARELOAD.playerPositions or not RARELOAD.playerPositions[mapName] then
        return
    end

    if not RARELOAD.Phantom then
        RARELOAD.Phantom = {}
    end

    for steamID, playerData in pairs(RARELOAD.playerPositions[mapName]) do
        if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
            local ply = nil
            for _, p in ipairs(player.GetAll()) do
                if p:SteamID() == steamID then
                    ply = p
                    break
                end
            end

            if IsValid(ply) and playerData.pos then
                local ang = Angle(0, 0, 0)
                if playerData.ang then
                    if type(playerData.ang) == "table" then
                        ang = Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3])
                    else
                        ang = playerData.ang
                    end
                end

                RARELOAD.Phantom[steamID] = {
                    phantom = CreatePhantom(ply, playerData.pos, ang),
                    ply = ply
                }

                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    ---@diagnostic disable-next-line: need-check-nil, undefined-field
                    print("[RARELOAD DEBUG] Created phantom for " .. ply:Nick() .. " at " .. tostring(playerData.pos))
                end
            end
        end
    end
end

hook.Add("PostDrawOpaqueRenderables", "DrawPlayerPhantomInfo", function()
    reloadSavedData()
    local playerPos = LocalPlayer():GetPos()
    local mapName = game.GetMap()

    local shouldRefresh = false
    if RARELOAD.playerPositions and RARELOAD.playerPositions[mapName] then
        for steamID, _ in pairs(RARELOAD.playerPositions[mapName]) do
            if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
                shouldRefresh = true
                break
            end
        end
    end

    if shouldRefresh then
        RARELOAD.RefreshPhantoms()
    end

    if RARELOAD.settings.debugEnabled then
        for _, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) then
                DrawPhantomInfo(data, playerPos, mapName)
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

    if RARELOAD.nextPhantomCheck and RARELOAD.nextPhantomCheck > CurTime() then return end

    local shouldRefresh = false
    for steamID, data in pairs(RARELOAD.playerPositions[game.GetMap()] or {}) do
        if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
            shouldRefresh = true
            break
        end
    end

    if shouldRefresh then
        RARELOAD.RefreshPhantoms()
    end

    RARELOAD.nextPhantomCheck = CurTime() + 2
end)

hook.Add("PlayerDisconnected", "RemovePhantomOnDisconnect", function(ply)
    if IsValid(ply) then
        RemovePhantom(ply:SteamID())
    end
end)
