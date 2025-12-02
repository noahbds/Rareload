RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Debug = RARELOAD.Debug or {}

local MapName = game.GetMap()

function RARELOAD.SavePlayerPositionOnDisconnect(ply)
    if not IsValid(ply) then return end
    
    -- Ensure the main save function is available
    if not RARELOAD.SaveRespawnPoint then
        include("rareload/core/save_helpers/rareload_save_point.lua")
    end

    if RARELOAD.SaveRespawnPoint then
        RARELOAD.SaveRespawnPoint(ply, ply:GetPos(), ply:EyeAngles(), { whereMsg = "disconnect" })
    end
end

local function loadSettings()
    local settingsFilePath = "rareload/addon_state.json"
    if file.Exists(settingsFilePath, "DATA") then
        local json = file.Read(settingsFilePath, "DATA")
        RARELOAD.settings = util.JSONToTable(json)
    end
end

function RARELOAD.UpdateClientPhantoms(ply, pos, ang)
    if not IsValid(ply) then return end

    local steamID = ply:SteamID()
    local currentModel = ply:GetModel()

    if not RARELOAD.playerPositions[MapName] then
        RARELOAD.playerPositions[MapName] = {}
    end

    if not RARELOAD.playerPositions[MapName][steamID] then
        RARELOAD.playerPositions[MapName][steamID] = {}
    end

    RARELOAD.playerPositions[MapName][steamID].playermodel = currentModel

    -- Load centralized conversion functions
    if not RARELOAD or not RARELOAD.DataUtils then
        include("rareload/utils/rareload_data_utils.lua")
    end

    local vectorPos = RARELOAD.DataUtils.ToVector(pos)
    if not vectorPos then
        vectorPos = ply:GetPos()
    end

    local angleObj = RARELOAD.DataUtils.ToAngle(ang)
    if not angleObj then
        angleObj = ply:EyeAngles()
    end

    net.Start("UpdatePhantomPosition")
    net.WriteString(steamID)
    net.WriteVector(vectorPos)
    net.WriteAngle(angleObj)
    net.WriteBool(true)
    net.WriteString(currentModel)
    net.Broadcast()

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Broadcasting phantom update for " .. steamID)
        print("[RARELOAD DEBUG] Model: " .. currentModel)
        print("[RARELOAD DEBUG] Position: " .. tostring(vectorPos))
    end
end

loadSettings()
