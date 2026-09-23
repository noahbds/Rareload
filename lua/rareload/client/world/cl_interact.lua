-- Interacting with world display panels (REWRITE_PLAN.md §21.7, F30, F33): Shift+Use locks onto the
-- focused panel and freezes the view; while locked the mouse wheel scrolls its lines, the strafe keys
-- flip through a pile, and Shift+Use (or losing the panel) unlocks.

local Panels = RARELOAD.Panels
local lockAng

local function unlock()
    Panels.lock, lockAng = nil, nil
end

local function focusedRec()
    local g = Panels.focus
    return g and g.rec, g
end

hook.Add("PlayerBindPress", "Rareload.Interact", function(_, bind, pressed)
    if not pressed then return end
    if string.find(bind, "+use", 1, true) and input.IsKeyDown(KEY_LSHIFT) then
        if Panels.lock then
            unlock()
            return true
        end
        local _, g = focusedRec()
        if g then
            Panels.lock, lockAng = g.key, LocalPlayer():EyeAngles()
            return true
        end
        return
    end
    if not Panels.lock then return end

    local rec, g = focusedRec()
    if not rec then return end
    if bind == "invprev" or bind == "invnext" then
        Panels.scroll[rec.key] = (Panels.scroll[rec.key] or 0) + (bind == "invnext" and 1 or -1)
        return true
    end
    if string.find(bind, "+moveleft", 1, true) or string.find(bind, "+moveright", 1, true) then
        local step = string.find(bind, "+moveright", 1, true) and 1 or -1
        Panels.pile[g.key] = (g.index + step - 1) % #g.recs + 1
        return true
    end
end)

-- While locked the player stands still and looks at the panel.
hook.Add("CreateMove", "Rareload.Interact", function(cmd)
    if not Panels.lock then return end
    if not Panels.focus or not RARELOAD.World.Active() then return unlock() end
    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetViewAngles(lockAng)
end)

hook.Add("InputMouseApply", "Rareload.Interact", function(cmd)
    if not Panels.lock then return end
    cmd:SetMouseX(0)
    cmd:SetMouseY(0)
    return true
end)
