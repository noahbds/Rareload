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
local TINT_SAME  = Color(120, 200, 255, 170) -- this saved object still exists live (kept across saves)

Preview.items  = Preview.items or {}
Preview.active = Preview.active or false
Preview.showId = Preview.showId or nil

surface.CreateFont("RareloadHistPreview", { font = "Roboto", size = 15, weight = 600, antialias = true })

-- Would a standing player be stuck here? Lift the box off the floor so standing on
-- the ground doesn't read as "starting in solid". `ignoreEnt` is the live entity that IS this
-- saved object (kept across saves) so its own body doesn't read as an obstacle.
local function HullClear(pos, ignoreEnt)
    local filter = { LocalPlayer() }
    if IsValid(ignoreEnt) then filter[#filter + 1] = ignoreEnt end
    local tr = util.TraceHull({
        start  = pos,
        endpos = pos,
        mins   = Vector(-16, -16, 4),
        maxs   = Vector(16, 16, 72),
        mask   = MASK_PLAYERSOLID,
        filter = filter,
    })
    return not (tr.StartSolid or tr.AllSolid)
end
Preview.TestClear = HullClear

-- Same id SED derives for a record, so preview panel interaction can find it back.
local function RecID(rec)
    return rec.id or rec.RareloadNPCID or rec.RareloadEntityID or rec.RareloadID
        or ((rec.class or rec.Class or rec.ClassName or "unknown") .. "?")
end

-- The live world entity kept across saves that IS this saved record: entities broadcast their
-- saved id as the networked "RareloadID" (== rec.id), so a match means the player carried this
-- object from the previewed save into the current one. Returns the entity, or nil.
local function FindLiveByRID(rid)
    if not rid or rid == "" then return nil end
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and not e:IsPlayer() and e.GetNWString and e:GetNWString("RareloadID", "") == rid then
            return e
        end
    end
    return nil
end

-- Hand SED the phantoms that have a saved record; it draws their panels + interaction.
local function SyncSED()
    if not SED then return end
    local out, byID = {}, {}
    for _, it in ipairs(Preview.items) do
        if it.rec and IsValid(it.phantom) then
            it.rec._isHistPreview = true -- SED draws a preview badge from this flag
            out[#out + 1] = { ent = it.phantom, saved = it.rec, isNPC = it.isNPC, pos = it.pos }
            byID[RecID(it.rec)] = it.rec
        end
    end
    SED.PreviewItems = out
    SED.PreviewRecordsByID = byID
end

local function RemoveAll()
    for _, it in ipairs(Preview.items) do
        if istable(it.subs) then
            for _, s in ipairs(it.subs) do if IsValid(s) then s:Remove() end end
        end
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

-- SED phantoms spawn hidden (MakePhantomModel); reveal the phantom + its sub-models and tint them.
local function RevealPhantom(phantom, subs, col)
    if not IsValid(phantom) then return end
    phantom:SetNoDraw(false)
    phantom:SetColor(col)
    if istable(subs) then
        for _, s in ipairs(subs) do
            if IsValid(s) then s:SetNoDraw(false); s:SetColor(col) end
        end
    end
    local children = phantom:GetChildren()
    if istable(children) then
        for _, c in ipairs(children) do
            if IsValid(c) then c:SetNoDraw(false); c:SetColor(col) end
        end
    end
end

-- Spawn an entity/NPC preview phantom through the SED module (identical to the debug display),
-- then reveal + tint it. Blue when the object still exists live (kept across saves), else the
-- green/red clearance tint.
local function AddObjectPhantom(rec, title, isNPC)
    if not (istable(rec) and SED and SED.ObjectPhantom and SED.ObjectPhantom.CreateModel) then return nil end
    local phantom, subs, pos = SED.ObjectPhantom.CreateModel(rec)
    if not IsValid(phantom) then return nil end

    local selfEnt = FindLiveByRID(RecID(rec))
    rec._histPreviewSame = IsValid(selfEnt) or nil
    local clear = HullClear(pos, selfEnt)
    local col   = IsValid(selfEnt) and TINT_SAME or (clear and TINT_CLEAR or TINT_BLOCK)
    RevealPhantom(phantom, subs, col)

    local it = {
        pos = pos, clear = clear, title = title or "?", rec = rec, isNPC = isNPC and true or false,
        selfEnt = selfEnt, phantom = phantom, subs = subs,
    }
    Preview.items[#Preview.items + 1] = it
    return it
end

-- Spawn the player preview phantom through the SED module (yaw-only angle, appearance, seated pose
-- when saved in a vehicle), then reveal + tint it.
local function AddPlayerPhantom(savedInfo, fallbackModel)
    if not (SED and SED.Phantom and SED.Phantom.CreatePlayerModel) then return nil end
    local phantom = SED.Phantom.CreatePlayerModel(savedInfo, fallbackModel)
    if not IsValid(phantom) then return nil end

    local pos   = phantom:GetPos()
    local clear = HullClear(pos)
    RevealPhantom(phantom, nil, clear and TINT_CLEAR or TINT_BLOCK)

    local it = { pos = pos, clear = clear, title = "Player", isPlayerPhantom = true, phantom = phantom }
    Preview.items[#Preview.items + 1] = it
    return it
end

-- `entry` is the summary row (id). Every phantom — player and objects — is spawned from the full
-- saved records the server sends back, through the SED builders, so they match the debug display.
function Preview.Request(entry)
    if not istable(entry) then return end
    Preview.active = true
    Preview.showId = entry.id
    Preview._fallbackModel = entry.mdl
    RemoveAll()
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

    -- player phantom, built from the full saved info (yaw-only angle, appearance, seated pose)
    if istable(data.player) and istable(data.player.info) then
        local fallback = data.player.m or Preview._fallbackModel
        Preview.playerItem = AddPlayerPhantom(data.player.info, fallback)
        if Preview.playerItem and SED and SED.Phantom and SED.Phantom.BuildRecordFromInfo then
            local lp   = LocalPlayer()
            local name = (IsValid(lp) and lp:Nick()) or "Player"
            local sid  = (IsValid(lp) and lp:SteamID()) or "preview"
            local okr, rec = pcall(SED.Phantom.BuildRecordFromInfo, name, sid, data.player.info, game.GetMap())
            if okr and istable(rec) then Preview.playerItem.rec = rec end
        end
    end

    -- entity / NPC phantoms, each from its full SED record
    for _, o in ipairs(data.objects or {}) do
        if istable(o.rec) then AddObjectPhantom(o.rec, tostring(o.c or "?"), o.npc == 1) end
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

    -- One pass: map every live entity's saved id -> entity, to spot objects kept across saves.
    local byRID = {}
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and not e:IsPlayer() and e.GetNWString then
            local rid = e:GetNWString("RareloadID", "")
            if rid ~= "" then byRID[rid] = e end
        end
    end

    for _, it in ipairs(Preview.items) do
        local selfEnt = (it.rec and not it.isPlayerPhantom) and byRID[RecID(it.rec)] or nil
        it.selfEnt = IsValid(selfEnt) and selfEnt or nil
        if it.rec then it.rec._histPreviewSame = it.selfEnt and true or nil end
        it.clear = HullClear(it.pos, it.selfEnt)
        if IsValid(it.phantom) then
            local col = it.selfEnt and TINT_SAME or (it.clear and TINT_CLEAR or TINT_BLOCK)
            it.phantom:SetColor(col)
            local children = it.phantom:GetChildren()
            if istable(children) then
                for _, child in ipairs(children) do
                    if IsValid(child) then child:SetColor(col) end
                end
            end
        end
    end
end)

-- top-screen confirmation (the panel can sit in front of the phantom)
local L = RARELOAD.L or function(_, ...) return tostring(...) end
hook.Add("HUDPaint", "RARELOAD_HistoryPreview_Hint", function()
    if not Preview.active then return end
    local n = #Preview.items
    local txt = n > 0 and L("sth.preview.hud_active", n) or L("sth.preview.hud_loading")
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
