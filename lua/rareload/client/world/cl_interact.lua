-- Interacting with world display panels (REWRITE_PLAN.md §21.7, F30, F33). Shift+Use on the focused
-- panel locks onto it: the view freezes and the viewmodel hides. While locked:
--   ↑/↓ switch tabs, the mouse wheel scrolls, ←/→ flip a pile (or scroll a lone panel),
--   H highlights the saved spot (a player: their respawn point), L links a moved object to its spot.
-- Shift+Use again, walking out of range or the panel disappearing unlocks.

local Panels = RARELOAD.Panels
local lockAng, unlockedAt = nil, 0
local held = {}

local function lp() return LocalPlayer() end

local function unlock()
    Panels.lock, lockAng, unlockedAt = nil, nil, RealTime()
    if IsValid(lp()) then lp():DrawViewModel(true) end
end

local function lockedRec()
    local lock = Panels.lock
    for _, rec in ipairs(RARELOAD.World.records) do
        if lock and rec.key == lock.rec then return rec end
    end
end

-- True once when `key` goes down, then again every 0.25 s while held.
local function pressed(key)
    if not input.IsKeyDown(key) then
        held[key] = nil
        return false
    end
    local now = RealTime()
    if held[key] and now - held[key] < 0.25 then return false end
    held[key] = now
    return true
end

local function switchTab(rec, dir)
    local view, tabs = Panels.View(rec), rec.tabs or {}
    if #tabs == 0 then return end
    view.tab = (view.tab - 1 + dir) % #tabs + 1
    view.scroll = 0
end

local function scroll(rec, delta)
    local view = Panels.View(rec)
    view.scroll = math.max(view.scroll + delta, 0)
end

hook.Add("PlayerBindPress", "Rareload.Interact", function(_, bind, down)
    if not down then return end
    local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
    if string.find(bind, "+use", 1, true) and shift then
        if Panels.lock then
            unlock()
            return true
        end
        local g = Panels.focus
        if g and not (IsValid(lp():GetActiveWeapon()) and lp():GetActiveWeapon():GetClass() == "weapon_physgun" and lp():KeyDown(IN_ATTACK)) then
            Panels.lock, lockAng = { pile = g.key, rec = g.active.key }, lp():EyeAngles()
            lp():DrawViewModel(false)
            return true
        end
        return
    end
    if not Panels.lock then return end
    local rec = lockedRec()
    if rec and (bind == "invprev" or bind == "invnext") then
        scroll(rec, bind == "invnext" and 1 or -1)
        return true
    end
end)

hook.Add("Think", "Rareload.Interact", function()
    if not Panels.lock then return end
    local rec = lockedRec()
    local tooFar = rec and EyePos():Distance(rec.pos) > RARELOAD.Get(nil, "wdDrawDistance") + 100
    if not rec or tooFar or not RARELOAD.World.Active() or not Panels.focus then return unlock() end
    if gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus()) then return end -- typing in chat or a menu

    if pressed(KEY_UP) then switchTab(rec, -1) end
    if pressed(KEY_DOWN) then switchTab(rec, 1) end
    local flip = (pressed(KEY_RIGHT) and 1 or 0) - (pressed(KEY_LEFT) and 1 or 0)
    if flip ~= 0 and not Panels.Flip(flip) then scroll(rec, flip) end
    if pressed(KEY_H) then RARELOAD.Highlight.ToggleRecord(rec, rec.kind == "player" and "player" or "saved") end
    if pressed(KEY_L) and rec.kind == "object" then RARELOAD.Highlight.ToggleRecord(rec, "link") end
end)

-- While locked the player stands still and looks at the panel; Use stays blocked briefly after
-- unlocking so the same key press doesn't open a door behind the panel.
hook.Add("CreateMove", "Rareload.Interact", function(cmd)
    if not Panels.lock then
        if RealTime() - unlockedAt < 0.5 then cmd:RemoveKey(IN_USE) end
        return
    end
    cmd:ClearMovement()
    cmd:ClearButtons()
    if lockAng then cmd:SetViewAngles(lockAng) end
end)

hook.Add("InputMouseApply", "Rareload.Interact", function(cmd)
    if not Panels.lock then return end
    cmd:SetMouseX(0)
    cmd:SetMouseY(0)
    return true
end)
