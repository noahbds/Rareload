-- Rareload: Client-side player phantom system
-- Manages player ghosts/phantoms for position reference

RARELOAD = RARELOAD or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.settings = RARELOAD.settings or { debugEnabled = false }
RARELOAD.Phantom = RARELOAD.Phantom or {}
RARELOAD.Debug = RARELOAD.Debug or {}

-- Debug log helper
function RARELOAD.Debug:Log(message)
    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD] " .. tostring(message))
    end
end

-- Safely handle network messages with error protection
function RARELOAD:HandleNetReceive(event, callback)
    net.Receive(event, function(len)
        local success, error = pcall(callback)
        if not success then
            RARELOAD.Debug:Log("Error in " .. event .. ": " .. tostring(error))
        end
    end)
end

-- Create a phantom model for a player
function RARELOAD:CreatePhantom(ply, pos, ang)
    if not IsValid(ply) then
        self.Debug:Log("Cannot create phantom: Invalid player")
        return nil
    end

    if not pos or pos:IsZero() then
        self.Debug:Log("Cannot create phantom: Invalid position")
        return nil
    end

    local phantom = ClientsideModel(ply:GetModel())
    if not IsValid(phantom) then
        self.Debug:Log("Failed to create clientside model")
        return nil
    end

    phantom:SetPos(pos)

    -- Normalize angle to just use yaw
    local correctedAng = Angle(0, (ang and ang.y) or ply:GetAngles().y, 0)
    phantom:SetAngles(correctedAng)

    -- Configure phantom properties
    phantom.isPhantom = true
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetSolid(SOLID_NONE)

    -- Apply visibility based on debug settings
    self:ApplyPhantomVisibility(phantom, self.settings.debugEnabled)

    return phantom
end

-- Control phantom visibility
function RARELOAD:ApplyPhantomVisibility(phantom, isVisible, customColor)
    if not IsValid(phantom) then return false end

    if isVisible then
        local debugColor = customColor or Color(255, 255, 255, 150)
        phantom:SetColor(debugColor)
        phantom:SetNoDraw(false)
    else
        phantom:SetColor(Color(0, 0, 0, 0))
        phantom:SetNoDraw(true)
    end

    return true
end

-- Update phantom visibility state based on debug setting
function RARELOAD:UpdatePhantomVisibility(specificSteamID)
    local isDebugEnabled = self.settings and self.settings.debugEnabled or false
    local updatedCount = 0

    if specificSteamID and self.Phantom[specificSteamID] then
        local phantom = self.Phantom[specificSteamID].phantom
        if self:ApplyPhantomVisibility(phantom, isDebugEnabled) then
            updatedCount = 1
        end
        return updatedCount
    end

    for steamID, phantomData in pairs(self.Phantom or {}) do
        if self:ApplyPhantomVisibility(phantomData.phantom, isDebugEnabled) then
            updatedCount = updatedCount + 1
        end
    end

    return updatedCount
end

-- Remove phantom entity and cleanup data
function RARELOAD:RemovePhantom(steamID)
    if not steamID then return end

    local phantomData = self.Phantom[steamID]
    if phantomData then
        if IsValid(phantomData.phantom) then
            self.Debug:Log("Removing phantom for player " .. steamID)
            SafeRemoveEntity(phantomData.phantom)
        end
        self.Phantom[steamID] = nil
    end
end

-- Update phantom position and angle
function RARELOAD:UpdatePhantomPosition(steamID, pos, ang)
    if not steamID or not pos then return end

    local phantomData = self.Phantom[steamID]
    if phantomData and IsValid(phantomData.phantom) then
        phantomData.phantom:SetPos(pos)
        phantomData.phantom:SetAngles(Angle(0, ang and ang.y or 0, 0))
    end
end

-- Visualize phantom information in debug mode
function RARELOAD:DrawPhantomInfo(phantomData, playerPos, mapName)
    if not phantomData or not IsValid(phantomData.phantom) then return end

    local phantom = phantomData.phantom
    local phantomPos = phantom:GetPos()
    local distance = playerPos:Distance(phantomPos)

    -- Draw 3D text above phantom
    local textPos = phantomPos + Vector(0, 0, 80)
    local text = (IsValid(phantomData.ply) and phantomData.ply:Nick() or "Unknown")
        .. "\nDistance: " .. math.Round(distance) .. " units"

    local angle = LocalPlayer():EyeAngles()
    angle:RotateAroundAxis(angle:Up(), -90)
    angle:RotateAroundAxis(angle:Forward(), 90)

    cam.Start3D2D(textPos, angle, 0.1)
    draw.SimpleText(text, "DermaLarge", 0, 0, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

-- Load saved player positions from file
function RARELOAD:LoadSavedData()
    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"

    if not file.Exists(filePath, "DATA") then
        return false
    end

    local data = file.Read(filePath, "DATA")
    if not data or data == "" then
        self.Debug:Log("File is empty: " .. filePath)
        return false
    end

    local status, result = pcall(util.JSONToTable, data)
    if status and result then
        self.playerPositions = result
        return true
    else
        self.Debug:Log("Error parsing JSON: " .. tostring(result))
        return false
    end
end

-- Refresh all phantoms based on saved positions
function RARELOAD:RefreshPhantoms()
    local mapName = game.GetMap()

    if not self.playerPositions or not self.playerPositions[mapName] then
        return 0
    end

    local createdCount = 0
    local playerLookup = {}

    -- Create lookup table for faster player access
    for _, ply in ipairs(player.GetAll()) do
        playerLookup[ply:SteamID()] = ply
    end

    for steamID, playerData in pairs(self.playerPositions[mapName]) do
        if not self.Phantom[steamID] or not IsValid(self.Phantom[steamID].phantom) then
            local ply = playerLookup[steamID]

            if IsValid(ply) and playerData.pos then
                local ang = Angle(0, 0, 0)
                if playerData.ang then
                    if type(playerData.ang) == "table" then
                        ang = Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3])
                    else
                        ang = playerData.ang
                    end
                end

                local phantom = self:CreatePhantom(ply, playerData.pos, ang)
                if phantom then
                    self.Phantom[steamID] = {
                        phantom = phantom,
                        ply = ply
                    }
                    createdCount = createdCount + 1

                    self.Debug:Log("Created phantom for " .. ply:Nick())
                end
            end
        end
    end

    return createdCount
end

-- Network handlers
RARELOAD:HandleNetReceive("UpdatePhantomPosition", function()
    local steamID = net.ReadString()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    RARELOAD:UpdatePhantomPosition(steamID, pos, ang)
end)

RARELOAD:HandleNetReceive("SyncData", function()
    local data = net.ReadTable()
    if not data or type(data) ~= "table" then return end

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = data.playerPositions or {}

    local oldDebugEnabled = RARELOAD.settings.debugEnabled
    RARELOAD.settings = data.settings or {}

    if RARELOAD.settings.debugEnabled ~= oldDebugEnabled then
        RARELOAD:UpdatePhantomVisibility()
    end
end)

RARELOAD:HandleNetReceive("CreatePlayerPhantom", function()
    local ply = net.ReadEntity()
    local pos, ang = net.ReadVector(), net.ReadAngle()

    if not IsValid(ply) then
        RARELOAD.Debug:Log("Invalid player entity received.")
        return
    end

    local steamID = ply:SteamID()
    if not steamID then return end

    RARELOAD:RemovePhantom(steamID)

    local phantom = RARELOAD:CreatePhantom(ply, pos, ang)
    if phantom then
        RARELOAD.Phantom[steamID] = {
            phantom = phantom,
            ply = ply
        }
    end
end)

RARELOAD:HandleNetReceive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    if IsValid(ply) then
        RARELOAD:RemovePhantom(ply:SteamID())
    end
end)

-- Hook for rendering phantom info and refreshing phantom models
hook.Add("PostDrawOpaqueRenderables", "RARELOAD_DrawPhantomInfo", function()
    -- Load saved data periodically
    if not RARELOAD.nextDataLoad or RARELOAD.nextDataLoad < CurTime() then
        RARELOAD:LoadSavedData()
        RARELOAD.nextDataLoad = CurTime() + 10 -- Check every 10 seconds
    end

    local playerPos = LocalPlayer():GetPos()
    local mapName = game.GetMap()

    -- Check if phantoms need refreshing
    local needsRefresh = false
    if RARELOAD.playerPositions and RARELOAD.playerPositions[mapName] then
        for steamID, _ in pairs(RARELOAD.playerPositions[mapName]) do
            if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
                needsRefresh = true
                break
            end
        end
    end

    if needsRefresh then
        RARELOAD:RefreshPhantoms()
    end

    -- Draw debug info if enabled
    if RARELOAD.settings.debugEnabled then
        for _, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) then
                RARELOAD:DrawPhantomInfo(data, playerPos, mapName)
            end
        end
    end
end)

-- Update phantom visibility when debug state changes
hook.Add("Think", "RARELOAD_CheckDebugChanges", function()
    local currentDebugState = RARELOAD.settings.debugEnabled

    if RARELOAD.lastDebugState ~= currentDebugState then
        RARELOAD:UpdatePhantomVisibility()
        RARELOAD.lastDebugState = currentDebugState
    end

    -- Periodic phantom check (less frequent than rendering hook)
    if not RARELOAD.nextPhantomCheck or RARELOAD.nextPhantomCheck < CurTime() then
        local mapName = game.GetMap()

        -- Clean up invalid phantoms
        for steamID, data in pairs(RARELOAD.Phantom) do
            if not IsValid(data.phantom) or not IsValid(data.ply) then
                RARELOAD:RemovePhantom(steamID)
            end
        end

        RARELOAD.nextPhantomCheck = CurTime() + 5
    end
end)

-- Clean up phantoms when players disconnect
hook.Add("PlayerDisconnected", "RARELOAD_RemovePhantomOnDisconnect", function(ply)
    if IsValid(ply) then
        RARELOAD:RemovePhantom(ply:SteamID())
    end
end)

-- Clean up all phantoms when game shuts down
hook.Add("ShutDown", "RARELOAD_CleanupOnShutdown", function()
    for steamID, _ in pairs(RARELOAD.Phantom) do
        RARELOAD:RemovePhantom(steamID)
    end
end)
