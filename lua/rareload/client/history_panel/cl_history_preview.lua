-- ─────────────────────────────────────────────────────────────────────────────
-- Save Timeline — in-world preview (4.0 · Phase 4)
--
-- A "Preview in World" toggle drops phantoms of a saved snapshot into the map: the
-- player model AND every saved entity/NPC, each at its saved position. Each phantom
-- is tinted GREEN when its spot is clear or RED when a player-sized hull would spawn
-- inside a solid (re-tested live).
--
-- The info panels + interaction come straight from the SED module: we hand our
-- phantoms + their saved records to SED via SED.PreviewItems, and SED renders the
-- real panels (depth-sorted, aim-to-inspect) through its own QueueAllSavedPanels
-- pipeline. No panel rendering is reimplemented here.
-- ─────────────────────────────────────────────────────────────────────────────

if not CLIENT then return end
RARELOAD = RARELOAD or {}

local Preview = RARELOAD.HistoryPreview or {}
RARELOAD.HistoryPreview = Preview

local TINT_CLEAR = Color(140, 255, 170, 190)
local TINT_BLOCK = Color(255, 140, 130, 190)

Preview.items  = Preview.items or {}
Preview.active = Preview.active or false
Preview.showId = Preview.showId or nil

surface.CreateFont("RareloadHistPreview", { font = "Roboto", size = 15, weight = 600, antialias = true })

-- Would a standing player be stuck here? Lift the box off the floor so standing on
-- the ground doesn't read as "starting in solid".
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

-- Same id SED derives for a record, so preview panel interaction can find it back.
local function RecID(rec)
    return rec.id or rec.RareloadNPCID or rec.RareloadEntityID or rec.RareloadID
        or ((rec.class or rec.Class or rec.ClassName or "unknown") .. "?")
end

-- Hand SED the phantoms that have a saved record; it draws their panels + interaction.
local function SyncSED()
    if not SED then return end
    local out, byID = {}, {}
    for _, it in ipairs(Preview.items) do
        if it.rec and IsValid(it.phantom) then
            out[#out + 1] = { ent = it.phantom, saved = it.rec, isNPC = it.isNPC, pos = it.pos }
            byID[RecID(it.rec)] = it.rec
        end
    end
    SED.PreviewItems = out
    SED.PreviewRecordsByID = byID
end

local function RemoveAll()
    for _, it in ipairs(Preview.items) do
        if IsValid(it.phantom) then it.phantom:Remove() end
    end
    Preview.items = {}
    Preview.playerItem = nil
    if SED then
        SED.PreviewItems = {}
        SED.PreviewRecordsByID = {}
    end
end

function Preview.Clear()
    Preview.active = false
    Preview.showId = nil
    RemoveAll()
end

function Preview.IsShowing(id)
    return Preview.active and Preview.showId == id
end

local function AddPhantom(model, pos, ang, title, rec, isNPC)
    if not (pos and isstring(model) and model ~= "") then return nil end
    util.PrecacheModel(model) -- prop/NPC models may not be loaded client-side yet
    local clear = HullClear(pos)
    local it = { pos = pos, clear = clear, title = title or "?", rec = rec, isNPC = isNPC and true or false }
    local p = ClientsideModel(model)
    if IsValid(p) then
        p:SetPos(pos)
        p:SetAngles(ang)
        p:SetMoveType(MOVETYPE_NONE)
        p:SetSolid(SOLID_NONE)
        p:SetRenderMode(RENDERMODE_TRANSALPHA)
        p:SetColor(clear and TINT_CLEAR or TINT_BLOCK)
        it.phantom = p
    end
    Preview.items[#Preview.items + 1] = it
    return it
end

-- `entry` is the summary row (id, mdl, pos, ang). The player phantom is spawned
-- immediately from it; entity/NPC phantoms + all SED records arrive from the server.
function Preview.Request(entry)
    if not istable(entry) then return end
    Preview.active = true
    Preview.showId = entry.id
    RemoveAll()
    local model = entry.mdl
    if not (isstring(model) and util.IsValidModel(model)) then
        local lp = LocalPlayer()
        model = (IsValid(lp) and lp:GetModel()) or "models/player/kleiner.mdl"
    end
    Preview.playerItem = AddPhantom(model, ToVec(entry.pos), ToAng(entry.ang), "Player")
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
    if not Preview.active or Preview.showId ~= id then return end
    local json = util.Decompress(raw)
    if not json then return end
    local ok, data = pcall(util.JSONToTable, json)
    if not (ok and istable(data)) then return end

    -- attach the player's SED panel record, built from the saved player-state
    if Preview.playerItem and istable(data.player) and istable(data.player.info)
        and SED and SED.Phantom and SED.Phantom.BuildRecordFromInfo then
        local lp   = LocalPlayer()
        local name = (IsValid(lp) and lp:Nick()) or "Player"
        local sid  = (IsValid(lp) and lp:SteamID()) or "preview"
        local okr, rec = pcall(SED.Phantom.BuildRecordFromInfo, name, sid, data.player.info, game.GetMap())
        if okr and istable(rec) then Preview.playerItem.rec = rec end
    end

    -- entity / NPC phantoms, each with its full SED record
    for _, o in ipairs(data.objects or {}) do
        AddPhantom(o.m, ToVec(o.p), ToAng(o.a), tostring(o.c or "?"), o.rec, o.npc == 1)
    end

    SyncSED()
end)

-- re-test collision periodically so the tint updates live as the world changes
local _nextRecheck = 0
hook.Add("Think", "RARELOAD_HistoryPreview_Recheck", function()
    if not Preview.active then return end
    local now = CurTime()
    if now < _nextRecheck then return end
    _nextRecheck = now + 0.3
    for _, it in ipairs(Preview.items) do
        it.clear = HullClear(it.pos)
        if IsValid(it.phantom) then it.phantom:SetColor(it.clear and TINT_CLEAR or TINT_BLOCK) end
    end
end)

-- top-screen confirmation (the panel can sit in front of the phantom)
hook.Add("HUDPaint", "RARELOAD_HistoryPreview_Hint", function()
    if not Preview.active then return end
    local n = #Preview.items
    local txt = n > 0
        and ("●  Previewing " .. n .. (n == 1 and " object" or " objects") ..
            " — aim at a panel and press Shift+E to inspect  ·  reopen the timeline or rareload_preview_off to hide")
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

-- Hide the preview from anywhere (it persists after the panel closes so you can inspect it).
concommand.Add("rareload_preview_off", function() Preview.Clear() end)

return Preview
