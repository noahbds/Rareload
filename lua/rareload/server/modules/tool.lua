-- The selected tool and its settings (5.4 plan, B3). The tool gun's mode and each tool's settings
-- are the player's own client convars, so the server reads them and the client sets them back.
-- Only the selected tool's settings are kept.

local MAX_CONVARS = 64
local MAX_VALUE = 256

RARELOAD.Module({
    id = "toolState",
    phase = "finalize",
    after = { "activeWeapon" },
    setting = { "keepInventory", "keepTool" },
    privSave = "rareload_save_inventory",
    privRestore = "rareload_restore_inventory",

    save = function(ply)
        local gun = ply:GetWeapon("gmod_tool")
        local mode = ply:GetInfo("gmod_toolmode")
        local tool = IsValid(gun) and istable(gun.Tool) and gun.Tool[mode]
        if not tool then return nil end
        local convars, n = {}, 0
        local names = table.GetKeys(istable(tool.ClientConVar) and tool.ClientConVar or {})
        table.sort(names)
        for _, name in ipairs(names) do
            local value = ply:GetInfo(mode .. "_" .. name)
            if n < MAX_CONVARS and isstring(value) and #value <= MAX_VALUE then
                convars[name] = value
                n = n + 1
            end
        end
        return { mode = mode, convars = convars }
    end,

    restore = function(ply, saved)
        if not isstring(saved.mode) then return end
        local convars = istable(saved.convars) and saved.convars or {}
        RARELOAD.Net.Push(ply, "tool.apply", { mode = saved.mode, convars = convars })
    end,

    summary = function(saved)
        return tostring(saved.mode) .. ", " .. table.Count(saved.convars or {}) .. " settings"
    end,
})
