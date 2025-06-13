RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Debug = RARELOAD.Debug or {}

local MapName = game.GetMap()

function RARELOAD.LoadPlayerPositions()
    local filePath = "rareload/player_positions_" .. MapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
            else
                print("[RARELOAD DEBUG] Error parsing JSON: " .. result)
            end
        else
            print("[RARELOAD DEBUG] File is empty: " .. filePath)
        end
    else
        print("[RARELOAD DEBUG] File does not exist: " .. filePath)
    end
end

function RARELOAD.SavePlayerPositionOnDisconnect(ply)
    RARELOAD.playerPositions[MapName] = RARELOAD.playerPositions[MapName] or {}
    RARELOAD.playerPositions[MapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType(),
    }
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

    local vectorPos
    if type(pos) == "table" and pos.x and pos.y and pos.z then
        vectorPos = Vector(pos.x, pos.y, pos.z)
    elseif type(pos) == "string" then
        local x, y, z = string.match(pos, "%[([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)%]")
        if not x then x, y, z = string.match(pos, "([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)") end
        if not x then x, y, z = string.match(pos, "^([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)$") end
        if x and y and z then
            vectorPos = Vector(tonumber(x), tonumber(y), tonumber(z))
        else
            vectorPos = ply:GetPos()
        end
    else
        vectorPos = ply:GetPos()
    end

    local angleObj
    if type(ang) == "table" and ang.p and ang.y and ang.r then
        angleObj = Angle(ang.p, ang.y, ang.r)
    elseif type(ang) == "table" and #ang == 3 then
        angleObj = Angle(ang[1], ang[2], ang[3])
    elseif type(ang) == "string" then
        local p, y, r = string.match(ang, "{([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)}")
        if not p then p, y, r = string.match(ang, "([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)") end
        if not p then p, y, r = string.match(ang, "^([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)$") end
        if p and y and r then
            angleObj = Angle(tonumber(p), tonumber(y), tonumber(r))
        else
            angleObj = ply:EyeAngles()
        end
    else
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
