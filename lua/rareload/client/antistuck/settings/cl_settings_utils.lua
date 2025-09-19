-- Utilities for settings load/save, clipboard import/export, and UI helpers
---@diagnostic disable: inject-field, undefined-field, param-type-mismatch, assign-type-mismatch

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

local Descriptions = RARELOAD.AntiStuckSettings.Descriptions
local Ranges = RARELOAD.AntiStuckSettings.Ranges

-- Show a modal to paste clipboard text (used for import)
function RARELOAD.AntiStuckSettings.GetClipboardText(callback)
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Paste Settings from Clipboard")
    frame:SetSize(500, 180)
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(false)
    frame:ShowCloseButton(true)
    frame:SetBackgroundBlur(true)

    local label = vgui.Create("DLabel", frame)
    label:SetText("Press Ctrl+V to paste your exported settings below, then click OK.")
    label:SetFont("DermaDefaultBold")
    label:SizeToContents()
    label:SetPos(20, 40)

    local textEntry = vgui.Create("DTextEntry", frame)
    textEntry:SetPos(20, 70)
    textEntry:SetSize(460, 40)
    textEntry:SetMultiline(true)
    textEntry:SetUpdateOnType(true)
    textEntry:RequestFocus()

    if input and input.GetClipboardText then
        local clip = input.GetClipboardText()
        if clip and clip ~= "" then textEntry:SetValue(clip) end
    end

    local okBtn = vgui.Create("DButton", frame)
    okBtn:SetText("OK")
    okBtn:SetSize(100, 30)
    okBtn:SetPos(390, 130)
    okBtn.DoClick = function()
        local text = textEntry:GetValue()
        frame:Close()
        if callback then callback(text) end
    end

    local cancelBtn = vgui.Create("DButton", frame)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetSize(100, 30)
    cancelBtn:SetPos(280, 130)
    cancelBtn.DoClick = function()
        frame:Close()
        if callback then callback(nil) end
    end
end

function RARELOAD.AntiStuckSettings.LoadSettings()
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileSettings then
        local settings = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileSettings()
        if settings then
            for key, defaultValue in pairs(Default_Anti_Stuck_Settings) do
                if settings[key] == nil then settings[key] = defaultValue end
            end
            return settings
        end
    end

    local settings = {}
    for k, v in pairs(Default_Anti_Stuck_Settings) do
        settings[k] = (type(v) == "table") and table.Copy(v) or v
    end
    return settings
end

function RARELOAD.AntiStuckSettings.SaveSettings(settings)
    if not settings or type(settings) ~= "table" then
        print("[RARELOAD] Error: Invalid settings table")
        return false
    end

    local function validateSettingsData(data)
        for k, v in pairs(data) do
            if type(k) == "number" and type(v) == "table" and v.func and v.name then
                return false, "Data contains methods structure instead of settings"
            end
            if type(k) ~= "string" then
                return false, "Settings keys must be strings, found: " .. type(k)
            end
            if Default_Anti_Stuck_Settings[k] == nil and Descriptions and not Descriptions[k] then
                print("[RARELOAD] Warning: Unknown setting key: " .. tostring(k))
            end
        end
        return true, "Valid settings data"
    end

    local isValid, err = validateSettingsData(settings)
    if not isValid then
        print("[RARELOAD] Error: Invalid settings data - " .. err)
        notification.AddLegacy("Settings validation failed: " .. err, NOTIFY_ERROR, 5)
        return false
    end

    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile then
        local currentProfileName = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
        print("[RARELOAD] Saving settings to profile: " .. (currentProfileName or "unknown"))
        local success = RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(settings, nil)
        if success then
            net.Start("RareloadAntiStuckSettings")
            net.WriteTable(settings)
            net.SendToServer()
            print("[RARELOAD] Settings saved successfully to profile: " .. (currentProfileName or "unknown"))
            return true
        else
            print("[RARELOAD] Failed to update profile: " .. (currentProfileName or "unknown"))
            return false
        end
    end

    print("[RARELOAD] Error: Profile system not available")
    return false
end

-- Export settings to clipboard
function RARELOAD.AntiStuckSettings.ExportSettings()
    local settings = RARELOAD.AntiStuckSettings.LoadSettings()
    local exported = { version = "2.0", timestamp = os.time(), settings = settings }
    local jsonData = util.TableToJSON(exported, true)
    SetClipboardText(jsonData)
    return true
end

-- Import settings from clipboard
function RARELOAD.AntiStuckSettings.ImportSettings(callback)
    RARELOAD.AntiStuckSettings.GetClipboardText(function(clipboardText)
        if not clipboardText or clipboardText == "" then
            notification.AddLegacy("No data pasted. Please copy your exported settings and paste them here.",
                NOTIFY_ERROR, 3)
            if callback then callback(false, "No data pasted") end
            return
        end
        local importedData = util.JSONToTable(clipboardText)
        if not importedData or type(importedData) ~= "table" or not importedData.settings then
            notification.AddLegacy("Invalid settings format. Please ensure you pasted the correct exported data.",
                NOTIFY_ERROR, 3)
            if callback then callback(false, "Invalid format") end
            return
        end
        if importedData.version ~= "2.0" then
            notification.AddLegacy("Unsupported settings version: " .. tostring(importedData.version), NOTIFY_ERROR, 3)
            if callback then callback(false, "Unsupported version") end
            return
        end
        local saveSuccess = RARELOAD.AntiStuckSettings.SaveSettings(importedData.settings)
        if saveSuccess then
            notification.AddLegacy("Settings imported successfully!", NOTIFY_GENERIC, 2)
            if callback then callback(true) end
        else
            notification.AddLegacy("Failed to save imported settings", NOTIFY_ERROR, 3)
            if callback then callback(false, "Save failed") end
        end
    end)
end

-- Override LoadSettings to use loaded settings if available
local originalLoadSettings = RARELOAD.AntiStuckSettings.LoadSettings
function RARELOAD.AntiStuckSettings.LoadSettings()
    if RARELOAD.AntiStuckSettings._loadedSettings then
        local settings = table.Copy(RARELOAD.AntiStuckSettings._loadedSettings)
        RARELOAD.AntiStuckSettings._loadedSettings = nil
        return settings
    end
    return originalLoadSettings()
end
