-- The Rareload tool: left click saves at the aimed spot, right click saves where you stand, reload
-- runs the chosen reload-key mode (REWRITE_PLAN.md F1, F28). The screen and panel live in client/.

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
    return save(self, trace.HitPos)
end

-- Saving where you stand aims at nothing, so no tool beam: returning false skips the shoot effect.
function TOOL:RightClick()
    save(self, nil)
    return false
end

function TOOL:Reload()
    if CLIENT then return false end
    local ply = self:GetOwner()
    if not RARELOAD.Can(ply, "rareload_use_tool") or not RARELOAD.Can(ply, "rareload_restore") then return denied(ply) end
    RARELOAD.Toast(ply, RARELOAD.History.ReloadKey(ply))
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
