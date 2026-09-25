-- The Rareload tool: left click saves at the aimed spot, right click saves where you stand, reload
-- runs the chosen reload-key mode.

TOOL.Category = "Rareload"
TOOL.Name = "#tool.rareload_tool.name"
TOOL.Information = {
    { name = "left" },
    { name = "right" },
    { name = "reload" },
}

local function denied(ply)
    RARELOAD.Toast(ply, "toast.tool_denied", nil, "error")
    return false
end

local function save(tool, at)
    if CLIENT then return true end
    local ply = tool:GetOwner()
    if not RARELOAD.Can(ply, "rareload_use_tool") then return denied(ply) end
    RARELOAD.Pipeline.Save(ply, { at = at, reason = "tool" })
    return true
end

function TOOL:LeftClick(trace)
    if not trace.Hit or trace.HitSky then
        if SERVER then RARELOAD.Toast(self:GetOwner(), "toast.aim_ground", nil, "error") end
        return false
    end
    return save(self, trace.HitPos)
end

function TOOL:RightClick()
    save(self, nil)
    return false
end

function TOOL:Reload()
    if CLIENT then return false end
    local ply = self:GetOwner()
    if not RARELOAD.Can(ply, "rareload_use_tool") or not RARELOAD.Can(ply, "rareload_restore") then return denied(ply) end
    local key, id = RARELOAD.History.ReloadKey(ply)
    RARELOAD.Toast(ply, key, id and { id })
    return false
end

if CLIENT then
    function TOOL:DrawToolScreen(w, h)
        RARELOAD.ToolScreen.Draw(w, h)
    end

    function TOOL.BuildCPanel(panel)
        RARELOAD.Menu.BuildToolPanel(panel)
    end
end
