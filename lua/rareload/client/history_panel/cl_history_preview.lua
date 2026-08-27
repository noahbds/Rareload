-- ─────────────────────────────────────────────────────────────────────────────
-- Save Timeline — in-world preview (4.0 · Phase 4)
--
-- A "Preview in World" toggle drops phantoms of a saved snapshot into the map:
-- the player model AND every saved entity/NPC, each at its saved position. Each
-- phantom glows GREEN when its spot is clear or RED when a player-sized hull
-- would spawn inside a solid, and carries a small in-world info card (class +
-- clear/blocked). Restoring a red spot still lands safely (server anti-stuck
-- relocates), so red is a heads-up, not a block.
--
-- Fully client-side and self-contained; owns its phantoms and hooks. Entity
-- geometry is fetched on demand from the server (RareloadHistory_Preview).
-- ─────────────────────────────────────────────────────────────────────────────

if not CLIENT then return end
RARELOAD = RARELOAD or {}

local Preview = RARELOAD.HistoryPreview or {}
RARELOAD.HistoryPreview = Preview

local COL_CLEAR = Color(64, 224, 110)
local COL_BLOCK = Color(240, 72, 60)
local GLOW_MAT  = Material("sprites/light_glow02_add")
local LABEL_DIST_SQR = 2200 * 2200
local LABEL_CAP = 24

Preview.items  = Preview.items or {}
Preview.active = Preview.active or false
Preview.showId = Preview.showId or nil

surface.CreateFont("RareloadHistPreview", { font = "Roboto", size = 15, weight = 600, antialias = true })
surface.CreateFont("RareloadHistPreviewSmall", { font = "Roboto", size = 13, weight = 500, antialias = true })

-- Would a standing player be stuck here? Lift the box a few units so simply
-- standing on the ground doesn't read as "starting in solid".
local function HullClear(pos)
    local tr = util.TraceHull({
        start  = pos,
        endpos = pos,
        mins   = Vector(-16, -16, 4),
        maxs   = Vector(16, 16, 72),
        mask   = MASK_PLAYERSOLID,
        filter = LocalPlayer(),
    })
    return not (tr.StartSolid or tr.AllSolid)
end
Preview.TestClear = HullClear

local function ToVec(t)
    return istable(t) and Vector(tonumber(t.x) or 0, tonumber(t.y) or 0, tonumber(t.z) or 0) or nil
end
local function ToAng(t)
    return istable(t) and Angle(tonumber(t.p) or 0, tonumber(t.y) or 0, tonumber(t.r) or 0) or Angle(0, 0, 0)
end

local function RemoveAll()
    for _, it in ipairs(Preview.items) do
        if IsValid(it.phantom) then it.phantom:Remove() end
    end
    Preview.items = {}
end

function Preview.Clear()
    Preview.active = false
    Preview.showId = nil
    RemoveAll()
end

function Preview.IsShowing(id)
    return Preview.active and Preview.showId == id
end

local function AddPhantom(model, pos, ang, title)
    if not (pos and model and model ~= "" and util.IsValidModel(model)) then return end
    local clear = HullClear(pos)
    local it = {
        pos   = pos,
        clear = clear,
        color = clear and COL_CLEAR or COL_BLOCK,
        title = title or "?",
    }
    local p = ClientsideModel(model)
    if IsValid(p) then
        p:SetPos(pos)
        p:SetAngles(ang)
        p:SetMoveType(MOVETYPE_NONE)
        p:SetSolid(SOLID_NONE)
        p:SetRenderMode(RENDERMODE_TRANSALPHA)
        p:SetColor(Color(255, 255, 255, 150))
        it.phantom = p
    end
    Preview.items[#Preview.items + 1] = it
end

-- `entry` is the summary row (has id, mdl, pos, ang). The player phantom is spawned
-- immediately from it; entity/NPC phantoms are fetched from the server and added when
-- they arrive, so the preview never depends on a round-trip to show anything.
function Preview.Request(entry)
    if not istable(entry) then return end
    Preview.active = true
    Preview.showId = entry.id
    RemoveAll()
    -- Fall back to the local player's model when the save has no usable model, so the
    -- player phantom always appears (otherwise the preview would sit empty forever).
    local model = entry.mdl
    if not (isstring(model) and util.IsValidModel(model)) then
        local lp = LocalPlayer()
        model = (IsValid(lp) and lp:GetModel()) or "models/player/kleiner.mdl"
    end
    AddPhantom(model, ToVec(entry.pos), ToAng(entry.ang), "Player")
    net.Start("RareloadHistory_Preview")
    net.WriteString(entry.id or "")
    net.SendToServer()
end

function Preview.Toggle(entry)
    if not istable(entry) then return end
    if Preview.IsShowing(entry.id) then
        Preview.Clear()
    else
        Preview.Request(entry)
    end
end

net.Receive("RareloadHistory_Preview", function()
    local id  = net.ReadString()
    local len = net.ReadUInt(32)
    local raw = len > 0 and net.ReadData(len) or ""
    -- ignore stale responses for a preview we've since turned off / changed
    if not Preview.active or Preview.showId ~= id then return end
    local json = util.Decompress(raw)
    if not json then return end
    local ok, data = pcall(util.JSONToTable, json)
    if ok and istable(data) and istable(data.objects) then
        for _, o in ipairs(data.objects) do
            AddPhantom(o.m, ToVec(o.p), ToAng(o.a), tostring(o.c or "?"))
        end
    end
end)

-- coloured outline glow
hook.Add("PreDrawHalos", "RARELOAD_HistoryPreview_Halo", function()
    if not Preview.active then return end
    local green, red = {}, {}
    for _, it in ipairs(Preview.items) do
        if IsValid(it.phantom) then
            local t = it.clear and green or red
            t[#t + 1] = it.phantom
        end
    end
    if #green > 0 then halo.Add(green, COL_CLEAR, 5, 5, 2, true, true) end
    if #red > 0 then halo.Add(red, COL_BLOCK, 5, 5, 2, true, true) end
end)

-- glow orbs + in-world info cards (SED-style), drawn in the 3D scene so they show
-- around the panel.
local function FaceAngle(pos, eye)
    local n = eye - pos
    n.z = 0
    if n:LengthSqr() < 1 then n = Vector(1, 0, 0) end
    n:Normalize()
    local a = n:Angle()
    a.y = a.y - 90
    a.p = 0
    a.r = 90
    return a
end

hook.Add("PostDrawTranslucentRenderables", "RARELOAD_HistoryPreview_World", function(bDepth, bSky)
    if bDepth or bSky or not Preview.active then return end
    if render.GetRenderTarget() ~= nil then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local eye = lp:EyePos()
    local pulse = 0.55 + math.sin(CurTime() * 4) * 0.35

    render.SetMaterial(GLOW_MAT)
    for _, it in ipairs(Preview.items) do
        render.DrawSprite(it.pos + Vector(0, 0, 20), 32 * pulse, 32 * pulse, it.color)
    end

    -- info cards for the nearest few phantoms
    local shown = 0
    for _, it in ipairs(Preview.items) do
        if shown >= LABEL_CAP then break end
        if eye:DistToSqr(it.pos) <= LABEL_DIST_SQR then
            shown = shown + 1
            local top = it.pos + Vector(0, 0, 82)
            local ang = FaceAngle(top, eye)
            local w, h = 190, 42
            cam.Start3D2D(top, ang, 0.11)
            draw.RoundedBox(6, -w / 2, -h, w, h, Color(14, 17, 22, 225))
            surface.SetDrawColor(it.color.r, it.color.g, it.color.b, 255)
            surface.DrawOutlinedRect(-w / 2, -h, w, h, 2)
            draw.SimpleText(it.title, "RareloadHistPreview", 0, -h + 6, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(it.clear and "CLEAR" or "BLOCKED", "RareloadHistPreviewSmall", 0, -h + 24, it.color,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            cam.End3D2D()
        end
    end
end)

-- top-screen confirmation (the panel can sit in front of the phantom)
hook.Add("HUDPaint", "RARELOAD_HistoryPreview_Hint", function()
    if not Preview.active then return end
    local n = #Preview.items
    local txt = n > 0
        and ("●  Previewing " .. n .. (n == 1 and " object" or " objects") ..
            " — reopen the Save Timeline to hide, or type rareload_preview_off")
        or "●  Loading preview…"
    surface.SetFont("RareloadHistPreview")
    local tw = surface.GetTextSize(txt)
    local cx, y = ScrW() * 0.5, 22
    draw.RoundedBox(6, cx - tw / 2 - 12, y, tw + 24, 26, Color(14, 17, 22, 225))
    surface.SetDrawColor(64, 224, 110, 220)
    surface.DrawOutlinedRect(cx - tw / 2 - 12, y, tw + 24, 26, 1)
    draw.SimpleText(txt, "RareloadHistPreview", cx, y + 13, Color(150, 235, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

hook.Add("OnReloaded", "RARELOAD_HistoryPreview_Reset", Preview.Clear)

-- Hide the preview from anywhere (it now persists after the panel closes).
concommand.Add("rareload_preview_off", function() Preview.Clear() end)

return Preview
