---@class RARELOAD
local RARELOAD              = RARELOAD or {}
RARELOAD.settings           = RARELOAD.settings or {}
RARELOAD.playerPositions    = RARELOAD.playerPositions or {}
RARELOAD.serverLastSaveTime = 0

UI                          = include("rareload/rareload_ui.lua")
RareloadUI                  = include("rareload/rareload_ui.lua")


---@class TOOL
local TOOL       = TOOL or {}
TOOL.Category    = "Rareload"
TOOL.Name        = "Position Saver Tool"
TOOL.Command     = nil
TOOL.Information = {
    { name = "left",   stage = 0, "Click to save a respawn position at target location" },
    { name = "right",  stage = 0, "Click to save a respawn position at your location" },
    { name = "reload", stage = 0, "Reload with the Rareload tool in hand to restore your previous saved position" },
    { name = "info",   stage = 0, "By Noahbds" }

}
TOOL.ConfigName  = ""

if SERVER then
    AddCSLuaFile("rareload/rareload_ui.lua")
    AddCSLuaFile("rareload/rareload_toolscreen.lua")
    util.AddNetworkString("RareloadToolReloadState")
end

if CLIENT then
    UI.RegisterFonts()
    UI.RegisterLanguage()
    net.Receive("RareloadSyncAutoSaveTime", function()
        RARELOAD.serverLastSaveTime = net.ReadFloat()
    end)

    net.Receive("RareloadPlayerMoved", function()
        RARELOAD.lastMoveTime = net.ReadFloat()
        RARELOAD.showAutoSaveMessage = false
    end)

    net.Receive("RareloadAutoSaveTriggered", function()
        local triggerTime = net.ReadFloat()
        RARELOAD.newAutoSaveTrigger = triggerTime
        RARELOAD.showAutoSaveMessage = true
        RARELOAD.autoSaveMessageTime = CurTime()
    end)

    net.Receive("RareloadToolReloadState", function()
        local hasData = net.ReadBool()
        RARELOAD.reloadImageState = {
            hasData = hasData,
            showTime = CurTime(),
            duration = 3 -- Show for 3 seconds
        }
    end)
end

if CLIENT then
    net.Receive("RareloadSettingsSync", function()
        local json = net.ReadString()
        local settings = util.JSONToTable(json)
        if settings then
            RARELOAD.settings = settings
            if IsValid(RareloadUI.LastPanel) then
                RareloadUI.LastPanel:InvalidateChildren(true)
            end
        end
    end)
end

local function loadAddonSettings()
    local addonStateFilePath = "rareload/addon_state.json"

    if not file.Exists(addonStateFilePath, "DATA") then
        return false, "Settings file does not exist"
    end

    local json = file.Read(addonStateFilePath, "DATA")
    if not json or json == "" then
        return false, "Settings file is empty"
    end

    local settings = util.JSONToTable(json)
    if not settings then
        return false, "Failed to parse settings JSON"
    end

    RARELOAD.settings = settings
    return true, nil
end

local save_inventory = include("rareload/server/save_helpers/rareload_save_inventory.lua")
local save_vehicles = include("rareload/server/save_helpers/rareload_save_vehicles.lua")
local save_entities = include("rareload/server/save_helpers/rareload_save_entities.lua")
local save_npcs = include("rareload/server/save_helpers/rareload_save_npcs.lua")
local save_ammo = include("rareload/server/save_helpers/rareload_save_ammo.lua")
local save_vehicle_state = include("rareload/server/save_helpers/rareload_save_vehicle_state.lua")
local position_history = include("rareload/server/save_helpers/rareload_position_history.lua")


function TOOL:LeftClick(trace, ply)
    local ply = self:GetOwner()

    if CLIENT then return true end

    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return
    end

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = trace.HitPos
    local newAng = ply:EyeAngles()
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = save_inventory(ply)

    if RARELOAD.settings.retainGlobalInventory then
        local globalInventory = {}
        for _, weapon in ipairs(ply:GetWeapons()) do
            table.insert(globalInventory, weapon:GetClass())
        end

        RARELOAD.globalInventory[ply:SteamID()] = {
            weapons = globalInventory,
            activeWeapon = newActiveWeapon
        }

        SaveGlobalInventory()

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " ..
                #globalInventory .. " weapons to global inventory for player " .. ply:Nick() ..
                " (Active weapon: " .. newActiveWeapon .. ")")
        end
    end

    local function tablesAreEqual(t1, t2)
        if #t1 ~= #t2 then return false end

        local lookup = {}
        for _, v in ipairs(t1) do
            lookup[v] = true
        end

        for _, v in ipairs(t2) do
            if not lookup[v] then return false end
        end

        return true
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldData and not RARELOAD.settings.autoSaveEnabled then
        local inventoryUnchanged = not RARELOAD.settings.retainInventory or
            tablesAreEqual(oldData.inventory or {}, newInventory)
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and inventoryUnchanged then
            return
        else
            local message = "[RARELOAD] Overwriting previous save: Position, Camera"
            if RARELOAD.settings.retainInventory then
                message = message .. ", Inventory"
            end
            print(message .. " updated.")
        end
    else
        local message = "[RARELOAD] Player position and camera"
        if RARELOAD.settings.retainInventory then
            message = message .. " and inventory"
        end
        print(message .. " saved.")
    end

    local playerData = {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        playermodel = ply:GetModel(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory,
    }

    if RARELOAD.settings.retainHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.settings.retainAmmo then
        playerData.ammo = save_ammo(ply, newInventory)
    end

    if RARELOAD.settings.retainVehicles then
        playerData.vehicles = save_vehicles(ply)
    end

    if RARELOAD.settings.retainVehicleState and ply:InVehicle() then
        playerData.vehicleState = save_vehicle_state(ply)
    end

    if RARELOAD.settings.retainMapEntities then
        playerData.entities = save_entities(ply)
    end

    if RARELOAD.settings.retainMapNPCs then
        playerData.npcs = save_npcs(ply)
    end

    RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)


    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData
    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    else
        print("[RARELOAD] Player position successfully saved.")
    end

    ply:ChatPrint("[Rareload] Saved respawn position at targeted location")

    if RARELOAD.settings.debugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(playerData.pos)
        local savedAng = Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3])
        net.WriteAngle(savedAng)
        net.Broadcast()
    end

    RARELOAD.UpdateClientPhantoms(ply, playerData.pos, Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3]))
    return true
end

function TOOL:RightClick()
    local ply = self:GetOwner()

    if CLIENT then return true end

    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return
    end

    RunConsoleCommand("save_position")

    local ply = self:GetOwner()

    ply:ChatPrint("[Rareload] Saved respawn position at your location")
    ply:EmitSound("buttons/button15.wav")
end

function TOOL:Reload()
    local ply = self:GetOwner()

    if CLIENT then return true end

    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return false
    end

    local steamID = ply:SteamID()
    local mapName = game.GetMap()

    local historySize = RARELOAD.GetPositionHistorySize(steamID, mapName)

    if historySize > 0 then
        local previousData = RARELOAD.GetPreviousPositionData(steamID, mapName)

        if previousData then
            RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
            RARELOAD.playerPositions[mapName][steamID] = previousData

            local success, err = pcall(function()
                file.Write("rareload/player_positions_" .. mapName .. ".json",
                    util.TableToJSON(RARELOAD.playerPositions, true))
            end)

            if success then
                local remaining = RARELOAD.GetPositionHistorySize(steamID, mapName)
                ply:ChatPrint("[RARELOAD] Restored previous position data. (" .. remaining .. " positions in history)")

                if RARELOAD.settings.debugEnabled then
                    net.Start("CreatePlayerPhantom")
                    net.WriteEntity(ply)
                    net.WriteVector(previousData.pos)
                    local savedAng = Angle(previousData.ang[1], previousData.ang[2], previousData.ang[3])
                    net.WriteAngle(savedAng)
                    net.Broadcast()

                    net.Start("UpdatePhantomPosition")
                    net.WriteString(steamID)
                    net.WriteVector(previousData.pos)
                    net.WriteAngle(Angle(previousData.ang[1], previousData.ang[2], previousData.ang[3]))
                    net.Send(ply)
                end

                net.Start("RareloadToolReloadState")
                net.WriteBool(true)
                net.Send(ply)

                ply:EmitSound("buttons/button14.wav")
                --  return true (commented - we don't want laser pew pew)
            else
                ply:ChatPrint("[RARELOAD] Failed to restore previous position data.")
                ply:EmitSound("buttons/button10.wav")
                print("[RARELOAD] Error: " .. err)
                return false
            end
        end
    else
        net.Start("RareloadToolReloadState")
        net.WriteBool(false)
        net.Send(ply)

        ply:ChatPrint("[RARELOAD] No previous position data found to restore.")
        ply:EmitSound("buttons/button8.wav")
        return false
    end
end

function TOOL.BuildCPanel(panel)
    local success, err = pcall(loadAddonSettings)
    if not success then
        ErrorNoHalt("Failed to load addon settings: " .. (err or "unknown error"))

        ---@diagnostic disable-next-line: param-type-mismatch
        local errorLabel = vgui.Create("DLabel", panel)
        errorLabel:SetText("Error loading settings! Please check console.")
        errorLabel:SetTextColor(RareloadUI.COLORS.DISABLED)
        errorLabel:Dock(TOP)
        errorLabel:DockMargin(10, 10, 10, 10)
        errorLabel:SetWrap(true)
        errorLabel:SetTall(40)

        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    RareloadUI.CreateButton(panel, "Toggle Rareload", "rareload_rareload",
        "Enable or disable Rareload", "addonEnabled")

    RareloadUI.CreateButton(panel, "Toggle Move Type", "rareload_spawn_mode",
        "Switch between different spawn modes", "spawnModeEnabled")

    RareloadUI.CreateButton(panel, "Toggle Auto Save", "rareload_auto_save",
        "Enable or disable auto saving position", "autoSaveEnabled")

    RareloadUI.CreateButton(panel, "Toggle Keep Inventory", "rareload_retain_inventory",
        "Enable or disable retaining inventory", "retainInventory")

    RareloadUI.CreateButton(panel, "Toggle Keep Health and Armor", "rareload_retain_health_armor",
        "Enable or disable retaining health and armor", "retainHealthArmor")

    RareloadUI.CreateButton(panel, "Toggle Keep Ammo", "rareload_retain_ammo",
        "Enable or disable retaining ammo", "retainAmmo")

    -- RareloadUI.CreateButton(panel, "Toggle Keep Vehicles", "rareload_retain_vehicles",
    --      "Enable or disable retaining vehicles", "retainVehicle")

    -- RareloadUI.CreateButton(panel, "Toggle Keep Vehicle State", "rareload_retain_vehicle_state",
    --     "Enable or disable retaining vehicle state", "retainVehicleState")

    RareloadUI.CreateButton(panel, "Toggle Keep Map Entities", "rareload_retain_map_entities",
        "Enable or disable retaining map entities", "retainMapEntities")

    RareloadUI.CreateButton(panel, "Toggle Keep Map NPCs", "rareload_retain_map_npcs",
        "Enable or disable retaining map NPCs", "retainMapNPCs")

    RareloadUI.CreateButton(panel, "Toggle No Custom Death at spawn", "rareload_nocustomrespawnatdeath",
        "Enable or disable custom respawn at death", "nocustomrespawnatdeath")

    RareloadUI.CreateButton(panel, "Toggle Debug", "rareload_debug",
        "Enable or disable debug mode", "debugEnabled")

    RareloadUI.CreateButton(panel, "Toggle Global Inventory", "rareload_retain_global_inventory",
        "Enable or disable global inventory", "retainGlobalInventory")

    RareloadUI.CreateActionButton(
        panel,
        "Save Position",
        "save_position",
        "Manually save your current position now"
    )


    RareloadUI.CreateSlider(
        panel,
        "Auto Save Interval",
        "Number of seconds between each automatic position save",
        "set_auto_save_interval",
        1, 60, 0,
        RARELOAD.settings.autoSaveInterval or 2,
        "s"
    )

    --  RareloadUI.CreateSlider(
    --      panel,
    --      "Max Distance",
    --      "Maximum distance (in units) at which saved entities will be restored",
    --      "set_max_distance",
    --      1, 1000, 0,
    --      RARELOAD.settings.maxDistance or 50,
    --      "u"
    --  )

    RareloadUI.CreateSlider(
        panel,
        "Auto Save Angle Tolerance",
        "Angle tolerance (in degrees) for entity restoration",
        "set_angle_tolerance",
        1, 360, 1,
        RARELOAD.settings.angleTolerance or 100.0,
        "°"
    )

    RareloadUI.CreateSlider(
        panel,
        "History Size",
        "Maximum number of position history cache entries",
        "set_history_size",
        1, 150, 0,
        RARELOAD.settings.maxHistorySize or 10
    )

    RareloadUI.CreateSeparator(panel)

    ---@diagnostic disable-next-line: undefined-field
    panel:Button("Open Entity Viewer", "entity_viewer_open")
end

local screenTool = include("rareload/rareload_toolscreen.lua")

function TOOL:DrawToolScreen()
    screenTool:Draw(256, 256, RARELOAD, loadAddonSettings)
    screenTool.EndDraw()
end
