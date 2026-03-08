-- Rareload Data Cleanup Utility
-- Automatically manages and cleans up old data files to prevent clutter

if not RARELOAD then RARELOAD = {} end
RARELOAD.DataCleanup = RARELOAD.DataCleanup or {}

local DataCleanup = RARELOAD.DataCleanup

-- Configuration
local CONFIG = {
    -- Keep only the last N permission backups
    MAX_PERMISSION_BACKUPS = 3,
    
    -- Keep logs from the last N days
    LOG_RETENTION_DAYS = 7,
    
    -- Auto-cleanup interval (in seconds)
    CLEANUP_INTERVAL = 600, -- 10 minutes
    
    -- Enable debug output
    DEBUG = false
}

-- Helper function to print debug messages
local function DebugPrint(...)
    if CONFIG.DEBUG or (RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled) then
        print("[RARELOAD DataCleanup]", ...)
    end
end

-- Clean up old permission backups, keeping only the most recent ones
function DataCleanup.CleanupPermissionBackups()
    local backupFiles, _ = file.Find("rareload/permissions_backup_*.json", "DATA")
    
    if not backupFiles or #backupFiles == 0 then
        DebugPrint("No permission backup files to clean up")
        return 0
    end
    
    -- Sort files by timestamp (newest first)
    table.sort(backupFiles, function(a, b)
        local timeA = tonumber(string.match(a, "permissions_backup_(%d+)%.json"))
        local timeB = tonumber(string.match(b, "permissions_backup_(%d+)%.json"))
        return (timeA or 0) > (timeB or 0)
    end)
    
    local deleted = 0
    
    -- Keep only the most recent backups
    for i = CONFIG.MAX_PERMISSION_BACKUPS + 1, #backupFiles do
        local filepath = "rareload/" .. backupFiles[i]
        file.Delete(filepath)
        DebugPrint("Deleted old permission backup:", backupFiles[i])
        deleted = deleted + 1
    end
    
    if deleted > 0 then
        print("[RARELOAD] Cleaned up " .. deleted .. " old permission backup(s), keeping " .. math.min(#backupFiles, CONFIG.MAX_PERMISSION_BACKUPS) .. " most recent")
    end
    
    return deleted
end

-- Clean up old log files, keeping only recent ones
function DataCleanup.CleanupLogFiles()
    local logFiles, _ = file.Find("rareload/logs/*.txt", "DATA")
    
    if not logFiles or #logFiles == 0 then
        DebugPrint("No log files to clean up")
        return 0
    end
    
    local cutoffTime = os.time() - (CONFIG.LOG_RETENTION_DAYS * 24 * 60 * 60)
    local deleted = 0
    
    for _, logFile in ipairs(logFiles) do
        -- Extract date from filename: rareload_YYYY-MM-DD_HH-MM.txt
        local year, month, day = string.match(logFile, "rareload_(%d+)-(%d+)-(%d+)_")
        
        if year and month and day then
            -- Create timestamp for the log file date
            local logTime = os.time({
                year = tonumber(year),
                month = tonumber(month),
                day = tonumber(day),
                hour = 0,
                min = 0,
                sec = 0
            })
            
            -- Delete if older than retention period
            if logTime < cutoffTime then
                local filepath = "rareload/logs/" .. logFile
                file.Delete(filepath)
                DebugPrint("Deleted old log file:", logFile)
                deleted = deleted + 1
            end
        end
    end
    
    if deleted > 0 then
        print("[RARELOAD] Cleaned up " .. deleted .. " old log file(s), keeping logs from last " .. CONFIG.LOG_RETENTION_DAYS .. " days")
    end
    
    return deleted
end

-- Check for and remove potentially redundant files
function DataCleanup.CheckRedundantFiles()
    local removed = 0
    local map = game.GetMap()
    
    -- Check if we have both the old format and new format player position files
    local oldFormat = "rareload/player_positions_" .. map .. ".json"
    local playerFolder = "rareload/player_positions/" .. map .. "/"
    
    -- Only warn about redundancy, don't auto-delete without verification
    if file.Exists(oldFormat, "DATA") then
        local hasPlayerFiles = false
        local files, _ = file.Find("rareload/player_positions/" .. map .. "/*.json", "DATA")
        if files and #files > 0 then
            hasPlayerFiles = true
        end
        
        if hasPlayerFiles then
            DebugPrint("Note: Found both old-format (" .. oldFormat .. ") and new per-player position files.")
            DebugPrint("Consider migrating to per-player format only.")
        end
    end
    
    return removed
end

-- Verify data integrity and report issues
function DataCleanup.VerifyDataIntegrity()
    local issues = {}
    
    -- Check main data folder exists
    if not file.Exists("rareload", "DATA") then
        file.CreateDir("rareload")
        table.insert(issues, "Created missing rareload data folder")
    end
    
    -- Check logs folder exists
    if not file.Exists("rareload/logs", "DATA") then
        file.CreateDir("rareload/logs")
        table.insert(issues, "Created missing logs folder")
    end
    
    -- Check player_positions folder exists
    if not file.Exists("rareload/player_positions", "DATA") then
        file.CreateDir("rareload/player_positions")
        table.insert(issues, "Created missing player_positions folder")
    end
    
    -- Check anti_stuck_profiles folder exists
    if not file.Exists("rareload/anti_stuck_profiles", "DATA") then
        file.CreateDir("rareload/anti_stuck_profiles")
        table.insert(issues, "Created missing anti_stuck_profiles folder")
    end
    
    -- Check player_settings folder exists
    if not file.Exists("rareload/player_settings", "DATA") then
        file.CreateDir("rareload/player_settings")
        table.insert(issues, "Created missing player_settings folder")
    end
    
    return issues
end

-- Full cleanup routine
function DataCleanup.PerformFullCleanup()
    print("[RARELOAD] Starting data cleanup...")
    
    local totalCleaned = 0
    
    -- Verify folder structure
    local issues = DataCleanup.VerifyDataIntegrity()
    if #issues > 0 then
        for _, issue in ipairs(issues) do
            print("[RARELOAD]", issue)
        end
    end
    
    -- Clean up old backups
    totalCleaned = totalCleaned + DataCleanup.CleanupPermissionBackups()
    
    -- Clean up old logs
    totalCleaned = totalCleaned + DataCleanup.CleanupLogFiles()
    
    -- Check redundant files (informational only)
    DataCleanup.CheckRedundantFiles()
    
    if totalCleaned > 0 then
        print("[RARELOAD] Data cleanup complete: removed " .. totalCleaned .. " file(s)")
    else
        DebugPrint("Data cleanup complete: no files needed removal")
    end
    
    return totalCleaned
end

-- Console command for manual cleanup
concommand.Add("rareload_cleanup_data", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You need admin privileges to run data cleanup")
        return
    end
    
    local cleaned = DataCleanup.PerformFullCleanup()
    
    if IsValid(ply) then
        ply:ChatPrint("[RARELOAD] Data cleanup complete: " .. cleaned .. " file(s) removed")
    end
end)

-- Auto-cleanup timer (runs periodically)
if SERVER then
    timer.Create("RARELOAD_AutoDataCleanup", CONFIG.CLEANUP_INTERVAL, 0, function()
        DataCleanup.PerformFullCleanup()
    end)
    
    -- Run initial cleanup on server start
    timer.Simple(60, function()
        DataCleanup.PerformFullCleanup()
    end)
end

print("[RARELOAD] Data cleanup utility loaded (retention: " .. CONFIG.MAX_PERMISSION_BACKUPS .. " backups, " .. CONFIG.LOG_RETENTION_DAYS .. " days logs)")

return DataCleanup
