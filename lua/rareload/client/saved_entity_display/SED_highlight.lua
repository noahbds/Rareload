SED = (RARELOAD and RARELOAD.SavedEntityDisplay) or SED
if not SED then return end

local SS = SED.Require("Shared", "rareload/client/saved_entity_display/SED_shared.lua")

local Highlight = SED.Highlight or {}
SED.Highlight   = Highlight
SED.Highlights  = SED.Highlights or {}

local BEAM_MAT  = Material("trails/laser")
local GLOW_MAT  = Material("sprites/light_glow02_add")
local MAX_LABELS = 16

local KIND_SAVED = "saved"
local KIND_L2P   = "live2phantom"
local KIND_P2P   = "player2phantom"

local COLORS = {
    [KIND_SAVED] = Color(255, 210, 60),
    [KIND_L2P]   = Color(90, 200, 255),
    [KIND_P2P]   = Color(120, 255, 140),
}

local math_floor, math_sqrt, math_Clamp = math.floor, math.sqrt, math.Clamp
local IsValid = IsValid

local _beamCol = Color(255, 255, 255, 255)
local _orbCol  = Color(255, 255, 255, 255)
local _orbPos  = Vector(0, 0, 0)

local HALO_CAP = 24
local function ByDistAsc(a, b) return a.dist < b.dist end

local function Key(kind, id) return kind .. "\1" .. tostring(id) end
local function SavedRecord(id, isNPC)
    local lookup = isNPC and SED.SAVED_NPCS_BY_ID or SED.SAVED_ENTITIES_BY_ID
    return lookup and lookup[id] or nil
end

function Highlight.IsActive(kind, id)
    return SED.Highlights[Key(kind, id)] ~= nil
end

local function Set(kind, id, data)
    SED.Highlights[Key(kind, id)] = data
end

function Highlight.Toggle(kind, id, data)
    local k = Key(kind, id)
    if SED.Highlights[k] then
        SED.Highlights[k] = nil
        return false
    end
    SED.Highlights[k] = data or { kind = kind, id = id }
    return true
end

function Highlight.ToggleSaved(id, isNPC)
    return Highlight.Toggle(KIND_SAVED, id, { kind = KIND_SAVED, id = id, isNPC = isNPC })
end

function Highlight.ToggleLiveToPhantom(id, isNPC)
    return Highlight.Toggle(KIND_L2P, id, { kind = KIND_L2P, id = id, isNPC = isNPC })
end

function Highlight.TogglePlayerToPhantom(steamID)
    return Highlight.Toggle(KIND_P2P, steamID, { kind = KIND_P2P, id = steamID })
end

function Highlight.HighlightAllSaved()
    for id in pairs(SED.SAVED_ENTITIES_BY_ID or {}) do
        Set(KIND_SAVED, id, { kind = KIND_SAVED, id = id, isNPC = false })
    end
    for id in pairs(SED.SAVED_NPCS_BY_ID or {}) do
        Set(KIND_SAVED, id, { kind = KIND_SAVED, id = id, isNPC = true })
    end
end

function Highlight.LinkAllLiveToPhantom()
    local liveByID = SS.BuildLiveByID()
    for id in pairs(liveByID) do
        local isNPC = (SED.SAVED_NPCS_BY_ID or {})[id] ~= nil
        if SavedRecord(id, isNPC) then
            Set(KIND_L2P, id, { kind = KIND_L2P, id = id, isNPC = isNPC })
        end
    end
end

function Highlight.HighlightAllPlayers()
    local byMap = RARELOAD.playerPositions and RARELOAD.playerPositions[game.GetMap()]
    for steamID in pairs(byMap or {}) do
        Set(KIND_P2P, steamID, { kind = KIND_P2P, id = steamID })
    end
end

function Highlight.ClearAll()
    SED.Highlights = {}
end

function Highlight.Count()
    local n = 0
    for _ in pairs(SED.Highlights) do n = n + 1 end
    return n
end

local resolved   = {}
local resolvedN  = 0
local frameNum   = -1
local frameEyePos

local function FillResolved(s, e, liveByID, eyePos, byMap)
    if e.kind == KIND_SAVED then
        local rec = SavedRecord(e.id, e.isNPC)
        local toPos = rec and SS.ToVector(rec.pos)
        if not toPos then return false end
        local live = liveByID[e.id]
        local pd = (SED.ObjectPhantoms or {})[e.id]
        s.color   = COLORS[KIND_SAVED]
        s.fromPos = eyePos
        s.toPos   = toPos
        s.outline = (IsValid(live) and live) or (pd and IsValid(pd.phantom) and pd.phantom) or nil
        s.label   = (rec.class or rec.Class or RARELOAD.L("sed.highlight.saved"))
            .. (e.isNPC and RARELOAD.L("sed.highlight.npc_suffix") or "")
        s.dual    = false
        return true
    elseif e.kind == KIND_L2P then
        local rec = SavedRecord(e.id, e.isNPC)
        local toPos = rec and SS.ToVector(rec.pos)
        local live = liveByID[e.id]
        if not (toPos and IsValid(live)) then return false end
        local from = live:GetPos()
        s.color   = COLORS[KIND_L2P]
        s.fromPos = from
        s.toPos   = toPos
        s.outline = live
        s.label   = RARELOAD.L("sed.highlight.drift", math_floor(from:Distance(toPos)))
        s.dual    = true
        return true
    elseif e.kind == KIND_P2P then
        local pdata = byMap and byMap[e.id]
        local toPos = pdata and SS.ToVector(pdata.pos)
        if not toPos then return false end
        local ply = player.GetBySteamID(e.id)
        local from = (IsValid(ply) and ply:EyePos()) or eyePos
        s.color   = COLORS[KIND_P2P]
        s.fromPos = from
        s.toPos   = toPos
        s.outline = IsValid(ply) and ply or nil
        s.label   = IsValid(ply) and ply:Nick() or RARELOAD.L("sed.highlight.player")
        s.dual    = IsValid(ply)
        return true
    end
    return false
end

local function GetResolved()
    local fn = FrameNumber()
    if fn == frameNum then return resolved, resolvedN end
    frameNum = fn

    resolvedN = 0
    if not next(SED.Highlights) then return resolved, 0 end

    SED.lpCache = (IsValid(SED.lpCache) and SED.lpCache) or LocalPlayer()
    frameEyePos = IsValid(SED.lpCache) and SED.lpCache:EyePos() or nil
    if not frameEyePos then return resolved, 0 end

    local liveByID = SS.BuildLiveByID()
    local byMap    = RARELOAD.playerPositions and RARELOAD.playerPositions[game.GetMap()]

    for _, e in pairs(SED.Highlights) do
        local slot = resolved[resolvedN + 1]
        if not slot then
            slot = {}
            resolved[resolvedN + 1] = slot
        end
        if FillResolved(slot, e, liveByID, frameEyePos, byMap) then
            slot.dist = frameEyePos:Distance(slot.toPos)
            resolvedN = resolvedN + 1
        end
    end

    return resolved, resolvedN
end

hook.Add("RareloadPlayerPositionsUpdated", "RARELOAD_Highlight_Prune", function(mapName)
    if mapName ~= game.GetMap() then return end
    for k, e in pairs(SED.Highlights) do
        local keep
        if e.kind == KIND_P2P then
            local byMap = RARELOAD.playerPositions and RARELOAD.playerPositions[game.GetMap()]
            keep = byMap and byMap[e.id] ~= nil
        else
            keep = SavedRecord(e.id, e.isNPC) ~= nil
        end
        if not keep then SED.Highlights[k] = nil end
    end
end)

hook.Add("PreDrawHalos", "RARELOAD_Highlight_Halos", function()
    local list, n = GetResolved()
    if n == 0 then return end

    local src = list
    if n > HALO_CAP then
        src = {}
        for i = 1, n do src[i] = list[i] end
        table.sort(src, ByDistAsc)
        n = HALO_CAP
    end

    local byColor = {}
    for i = 1, n do
        local r = src[i]
        if IsValid(r.outline) then
            local g = byColor[r.color]
            if not g then g = {}; byColor[r.color] = g end
            g[#g + 1] = r.outline
        end
    end
    for col, ents in pairs(byColor) do
        halo.Add(ents, col, 3, 3, 2, true, true)
    end
end)

hook.Add("PostDrawTranslucentRenderables", "RARELOAD_Highlight_Beams", function(bDepth, bSky)
    if bDepth or bSky then return end
    if render.GetRenderTarget() ~= nil then return end
    local list, n = GetResolved()
    if n == 0 then return end

    local pulse = 0.65 + math.sin(CurTime() * 4) * 0.35

    render.OverrideDepthEnable(true, false)

    local beamA = 220 * pulse
    render.SetMaterial(BEAM_MAT)
    for i = 1, n do
        local r = list[i]
        local c = r.color
        _beamCol.r, _beamCol.g, _beamCol.b, _beamCol.a = c.r, c.g, c.b, beamA
        render.DrawBeam(r.fromPos, r.toPos, 6, 0, r.toPos:Distance(r.fromPos) / 64, _beamCol)
    end

    render.SetMaterial(GLOW_MAT)
    local orbSize = 34 * pulse
    for i = 1, n do
        local r = list[i]
        local c = r.color
        local t = r.toPos
        _orbCol.r, _orbCol.g, _orbCol.b = c.r, c.g, c.b
        _orbPos.x, _orbPos.y, _orbPos.z = t.x, t.y, t.z + 8
        render.DrawSprite(_orbPos, orbSize, orbSize, _orbCol)
        if r.dual then
            render.DrawSprite(r.fromPos, orbSize * 0.7, orbSize * 0.7, _orbCol)
        end
    end

    render.OverrideDepthEnable(false, false)
end)

surface.CreateFont("RareloadHighlightLabel", { font = "Roboto", size = 19, weight = 700, antialias = true })

local function DrawLabel(text, x, y, col)
    surface.SetFont("RareloadHighlightLabel")
    local tw, th = surface.GetTextSize(text)
    local pad = 6
    surface.SetDrawColor(15, 18, 24, 220)
    surface.DrawRect(x - tw * 0.5 - pad, y - th * 0.5 - 2, tw + pad * 2, th + 4)
    surface.SetDrawColor(col.r, col.g, col.b, 255)
    surface.DrawOutlinedRect(x - tw * 0.5 - pad, y - th * 0.5 - 2, tw + pad * 2, th + 4, 1)
    draw.SimpleText(text, "RareloadHighlightLabel", x, y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

hook.Add("HUDPaint", "RARELOAD_Highlight_HUD", function()
    local list, n = GetResolved()
    if n == 0 then return end

    local sw, sh = ScrW(), ScrH()
    local cx, cy = sw * 0.5, sh * 0.5

    local labelList = list
    if n > MAX_LABELS then
        labelList = {}
        for i = 1, n do labelList[i] = list[i] end
        table.sort(labelList, ByDistAsc)
    end
    local labelCount = math.min(n, MAX_LABELS)

    for i = 1, labelCount do
        local r = labelList[i]
        local col = r.color
        local scr = r.toPos:ToScreen()
        local text = RARELOAD.L("sed.highlight.label_fmt", r.label or "", math_floor(r.dist))

        if scr.visible and scr.x >= 0 and scr.x <= sw and scr.y >= 0 and scr.y <= sh then
            DrawLabel(text, scr.x, scr.y - 24, col)
        else
            local dx, dy = scr.x - cx, scr.y - cy
            if not scr.visible then dx, dy = -dx, -dy end
            local len = math.max(1, math_sqrt(dx * dx + dy * dy))
            local margin = 60
            local mx = math_Clamp(cx + dx / len * (cx - margin), margin, sw - margin)
            local my = math_Clamp(cy + dy / len * (cy - margin), margin, sh - margin)
            local ang = math.atan2(dy, dx)
            local s = 12
            surface.SetDrawColor(col.r, col.g, col.b, 230)
            draw.NoTexture()
            surface.DrawPoly({
                { x = mx + math.cos(ang) * s,       y = my + math.sin(ang) * s },
                { x = mx + math.cos(ang + 2.5) * s, y = my + math.sin(ang + 2.5) * s },
                { x = mx + math.cos(ang - 2.5) * s, y = my + math.sin(ang - 2.5) * s },
            })
            DrawLabel(text, mx, my - 18, col)
        end
    end

    if n > 0 then
        DrawLabel(n .. (n == 1 and " tracer" or " tracers"), cx, 26, COLORS[KIND_SAVED])
    end
end)

concommand.Add("rareload_highlight_all", function() Highlight.HighlightAllSaved() end)
concommand.Add("rareload_highlight_link_all", function() Highlight.LinkAllLiveToPhantom() end)
concommand.Add("rareload_highlight_players", function() Highlight.HighlightAllPlayers() end)
concommand.Add("rareload_highlight_clear", function() Highlight.ClearAll() end)

Highlight._initialized = true
return Highlight
