RARELOAD = RARELOAD or {}
RARELOAD.ProfileFileOps = RARELOAD.ProfileFileOps or {}

-- Constants
local PROFILE_DIR = "rareload/anti_stuck_profiles/"
local BACKUP_DIR = "rareload/anti_stuck_profiles/backups/"
local MAX_BACKUPS = 5
local FILE_OPERATION_TIMEOUT = 0.1 -- Maximum time to wait for file operations

-- Utility functions
local function SafeJSONDecode(str)
    if not str or str == "" then return nil end
    local success, result = pcall(util.JSONToTable, str)
    return success and result or nil
end

local function SafeJSONEncode(tbl)
    if not tbl then return nil end
    local success, result = pcall(util.TableToJSON, tbl, true)
    return success and result or nil
end

local function EnsureDirectories()
    file.CreateDir("rareload")
    file.CreateDir(PROFILE_DIR)
    file.CreateDir(BACKUP_DIR)
end

local function GetBackupPath(profileName, timestamp)
    return BACKUP_DIR .. profileName .. "_" .. timestamp .. ".json"
end

local function CreateBackup(profileName)
    local sourcePath = PROFILE_DIR .. profileName .. ".json"
    if not file.Exists(sourcePath, "DATA") then return false end
    
    local timestamp = os.time()
    local backupPath = GetBackupPath(profileName, timestamp)
    
    -- Read source file
    local content = file.Read(sourcePath, "DATA")
    if not content then return false end
    
    -- Write backup
    file.Write(backupPath, content)
    
    -- Clean up old backups
    local backups = file.Find(BACKUP_DIR .. profileName .. "_*.json", "DATA")
    if #backups > MAX_BACKUPS then
        table.sort(backups)
        for i = 1, #backups - MAX_BACKUPS do
            file.Delete(BACKUP_DIR .. backups[i])
        end
    end
    
    return true
end

local function RestoreBackup(profileName, timestamp)
    local backupPath = GetBackupPath(profileName, timestamp)
    if not file.Exists(backupPath, "DATA") then return false end
    
    local content = file.Read(backupPath, "DATA")
    if not content then return false end
    
    local profile = SafeJSONDecode(content)
    if not profile then return false end
    
    -- Validate restored profile
    if not RARELOAD.ProfileValidation.ValidateProfile(profile) then
        return false
    end
    
    -- Write to main profile file
    file.Write(PROFILE_DIR .. profileName .. ".json", content)
    
    return true
end

-- File operations with timeout
local function SafeFileOperation(operation, ...)
    local startTime = SysTime()
    local result = operation(...)
    
    -- Check if operation took too long
    if SysTime() - startTime > FILE_OPERATION_TIMEOUT then
        print("[RARELOAD] Warning: File operation took longer than expected")
    end
    
    return result
end

-- Export functions
function RARELOAD.ProfileFileOps.Initialize()
    EnsureDirectories()
end

function RARELOAD.ProfileFileOps.ReadProfile(profileName)
    if not profileName then return nil end
    
    local filePath = PROFILE_DIR .. profileName .. ".json"
    if not file.Exists(filePath, "DATA") then return nil end
    
    local content = SafeFileOperation(file.Read, filePath, "DATA")
    if not content then return nil end
    
    return SafeJSONDecode(content)
end

function RARELOAD.ProfileFileOps.WriteProfile(profileName, data)
    if not profileName or not data then return false end
    
    -- Create backup before writing
    CreateBackup(profileName)
    
    -- Encode and write data
    local json = SafeJSONEncode(data)
    if not json then return false end
    
    return SafeFileOperation(file.Write, PROFILE_DIR .. profileName .. ".json", json)
end

function RARELOAD.ProfileFileOps.DeleteProfile(profileName)
    if not profileName then return false end
    
    local filePath = PROFILE_DIR .. profileName .. ".json"
    if not file.Exists(filePath, "DATA") then return false end
    
    -- Create backup before deleting
    CreateBackup(profileName)
    
    return SafeFileOperation(file.Delete, filePath)
end

function RARELOAD.ProfileFileOps.ListProfiles()
    local files = file.Find(PROFILE_DIR .. "*.json", "DATA")
    local profiles = {}
    
    for _, fileName in ipairs(files) do
        local profileName = string.gsub(fileName, ".json$", "")
        table.insert(profiles, profileName)
    end
    
    return profiles
end

function RARELOAD.ProfileFileOps.GetBackups(profileName)
    if not profileName then return {} end
    
    local backups = file.Find(BACKUP_DIR .. profileName .. "_*.json", "DATA")
    local result = {}
    
    for _, fileName in ipairs(backups) do
        local timestamp = string.match(fileName, profileName .. "_(%d+)%.json$")
        if timestamp then
            table.insert(result, {
                timestamp = tonumber(timestamp),
                date = os.date("%Y-%m-%d %H:%M:%S", tonumber(timestamp))
            })
        end
    end
    
    -- Sort by timestamp (newest first)
    table.sort(result, function(a, b)
        return a.timestamp > b.timestamp
    end)
    
    return result
end

function RARELOAD.ProfileFileOps.RestoreProfile(profileName, timestamp)
    if not profileName or not timestamp then return false end
    return RestoreBackup(profileName, timestamp)
end

-- Initialize on load
RARELOAD.ProfileFileOps.Initialize()
