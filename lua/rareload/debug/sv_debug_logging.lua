RARELOAD = RARELOAD or {}
RARELOAD.Debug = RARELOAD.Debug or {}

util.AddNetworkString("RareloadDebugLog")
util.AddNetworkString("RareloadDebugWorldEvent")

-- Keep local references for speed
local validLevels = RARELOAD.Debug.LEVELS

local function LogToFile(header, message)
    if not RARELOAD.settings.debugLoggingToFile then return end
    
    local date = os.date("%Y-%m-%d")
    local time = os.date("%H:%M:%S")
    local path = "rareload/logs/" .. date .. ".txt"
    
    if not file.Exists("rareload/logs", "DATA") then
        file.CreateDir("rareload/logs")
    end

    local str = string.format("[%s] %s: %s\n", time, header, message)
    file.Append(path, str)
end

function RARELOAD.Debug.Log(levelName, header, data, entity)
    if not RARELOAD.Debug.IsEnabled() then return end

    local levelInfo = validLevels[levelName] or validLevels.INFO
    if levelInfo.value > RARELOAD.Debug.GetLevel() then return end

    -- 1. Format the message
    local msgString = ""
    if type(data) == "table" then
        msgString = util.TableToJSON(data, true)
    else
        msgString = tostring(data)
    end

    local entInfo = ""
    if IsValid(entity) then
        if entity:IsPlayer() then
            entInfo = string.format(" [Ply: %s]", entity:Nick())
        else
            entInfo = string.format(" [Ent: %s|%d]", entity:GetClass(), entity:EntIndex())
        end
    end

    local fullHeader = levelInfo.prefix .. " " .. header .. entInfo

    -- 2. Server Console Print
    MsgC(levelInfo.color, fullHeader .. "\n")
    if levelInfo.value <= 2 then -- Errors/Warnings get stack trace
        print(msgString)
    elseif levelName == "VERBOSE" then
        print(msgString)
    end

    -- 3. File Logging
    LogToFile(fullHeader, msgString)

    -- 4. Network to Admins (The Improvement)
    -- We compress the message if it's large to save bandwidth
    local netData = util.Compress(msgString)
    
    net.Start("RareloadDebugLog")
        net.WriteUInt(levelInfo.value, 4) -- 1 to 4
        net.WriteString(header)
        net.WriteUInt(#netData, 32)
        net.WriteData(netData, #netData)
        if IsValid(entity) then
            net.WriteBool(true)
            net.WriteEntity(entity)
        else
            net.WriteBool(false)
        end
    net.Send(RARELOAD.GetAdmins()) -- Helper function needed
end

-- Helper to get admins
function RARELOAD.GetAdmins()
    local admins = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply:IsAdmin() then table.insert(admins, ply) end
    end
    return admins
end

-- Visual Debugging: Draw a box/line in the world for clients
-- Type: "box", "line", "sphere"
function RARELOAD.Debug.WorldEvent(pos, type, color, duration, extra)
    if not RARELOAD.Debug.IsEnabled() then return end
    
    net.Start("RareloadDebugWorldEvent")
        net.WriteVector(pos)
        net.WriteString(type)
        net.WriteColor(color or Color(255, 255, 255))
        net.WriteFloat(duration or 5)
        net.WriteFloat(extra or 0) -- Radius for sphere, or size for box
    net.Send(RARELOAD.GetAdmins())
end