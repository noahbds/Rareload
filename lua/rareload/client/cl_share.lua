-- Export, import and share saves on the client (5.4 plan, A2): writing exports to this game's
-- data/rareload/exports folder, the import window that uploads one of them, the player picker for
-- sharing, and the prompt when another player offers a save.

local L, UI = RARELOAD.L, RARELOAD.UI
local C, sc = UI.C, UI.sc

RARELOAD.Share = RARELOAD.Share or {}
local Share = RARELOAD.Share

local DIR = "rareload/exports/"

local function request(op, args) RARELOAD.Net.Request(op, args) end

-- Export --------------------------------------------------------------------------------------------

function Share.Export(id)
    request("export.get", { id = id })
    UI.Notify(L("share.exporting"))
end

RARELOAD.Net.On("export.file", function(payload)
    if not isstring(payload.name) or not istable(payload.doc) then return end
    file.CreateDir("rareload/exports")
    local path = DIR .. string.gsub(string.lower(payload.name), "[^a-z0-9_%-]", "_") .. ".json"
    file.Write(path, util.TableToJSON(payload.doc, true))
    UI.Notify(L("share.exported", "data/" .. path))
    MsgC(C.accent, "[Rareload] ", color_white, "Exported to garrysmod/data/" .. path .. "\n")
end)

-- Import --------------------------------------------------------------------------------------------

local sizeText = RARELOAD.Util.FormatBytes

local function upload(name, status)
    local text = file.Read(DIR .. name, "DATA")
    if not text or text == "" then return UI.Notify(L("share.unreadable"), "error") end
    local max = RARELOAD.Get(nil, "importMaxKB") * 1024
    local ok, size = RARELOAD.Net.Upload("import", text, function(sent, total)
        status(sent < total and L("share.uploading", sent, total) or "") -- the server's toast tells the rest
    end, max)
    if not ok then
        status("")
        UI.Notify(L("share.too_big", sizeText(size), sizeText(max)), "error")
    end
end

-- The files in this game's data/rareload/exports folder, newest first; picking one uploads it.
function Share.OpenImport()
    if IsValid(Share.importFrame) then Share.importFrame:Remove() end
    local frame = UI.Window({ title = L("share.import_title"), subtitle = L("share.import_hint"), w = 620, h = 560 })
    Share.importFrame = frame

    local status = UI.Label(frame, "", "Rareload.Small", C.text3)
    status:Dock(BOTTOM)
    status:SetTall(sc(22))
    local function setStatus(text) if IsValid(status) then status:SetText(text) end end

    local files = file.Find(DIR .. "*.json", "DATA", "datedesc") or {}
    if #files == 0 then
        local empty = UI.Empty(frame, "page_white_get", L("share.no_files"), L("share.import_hint"))
        empty:Dock(FILL)
        return frame
    end

    local scroll = UI.Scroll(frame)
    scroll:Dock(FILL)
    for _, name in ipairs(files) do
        local row = vgui.Create("DButton", scroll)
        row:SetText("")
        row:Dock(TOP)
        row:SetTall(sc(46))
        row:DockMargin(0, 0, sc(4), sc(6))
        local when = os.date("%Y-%m-%d %H:%M", file.Time(DIR .. name, "DATA"))
        local size = sizeText(file.Size(DIR .. name, "DATA") or 0)
        row.Paint = function(self, w, h)
            draw.RoundedBox(sc(8), 0, 0, w, h, self:IsHovered() and C.surfaceHi or C.surface)
            UI.DrawIcon("page_white_get", sc(12), (h - sc(16)) / 2, sc(16))
            draw.SimpleText(UI.Clip(string.StripExtension(name), "Rareload.BodyB", w - sc(200)), "Rareload.BodyB",
                sc(38), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(when .. "  ·  " .. size, "Rareload.Small", w - sc(12), h / 2, C.text3,
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        row.DoClick = function()
            UI.Confirm(L("share.import_title"), L("share.import_confirm", string.StripExtension(name)), function()
                upload(name, setStatus)
            end, L("share.import"))
        end
    end
    return frame
end

-- Share ---------------------------------------------------------------------------------------------

-- A list of the other players; picking one offers them a copy of save `id`.
function Share.Pick(id)
    local others = {}
    for _, other in player.Iterator() do
        if other ~= LocalPlayer() and not other:IsBot() then others[#others + 1] = other end
    end
    if #others == 0 then return UI.Notify(L("share.nobody"), "error") end

    local frame = UI.Window({ title = L("share.pick_title", id), w = 420, h = 480, overlay = true })
    local scroll = UI.Scroll(frame)
    scroll:Dock(FILL)
    for _, other in ipairs(others) do
        local b = UI.Button(scroll, other:Nick(), function()
            if IsValid(other) then request("share.send", { id = id, sid = other:SteamID64() }) end
            frame:Close()
        end, { style = "info", icon = "user" })
        b:Dock(TOP)
        b:DockMargin(0, 0, sc(4), sc(6))
    end
end

-- Another player offers a copy of one of their saves. Closing the prompt declines it.
RARELOAD.Net.On("share.offer", function(payload)
    if not isstring(payload.token) then return end
    local parts = {}
    if (tonumber(payload.objects) or 0) > 0 then parts[#parts + 1] = L("share.objects", payload.objects) end
    if (tonumber(payload.weapons) or 0) > 0 then parts[#parts + 1] = L("share.weapons", payload.weapons) end
    if isstring(payload.note) and payload.note ~= "" then parts[#parts + 1] = "\"" .. payload.note .. "\"" end
    local body = L("share.offer_body", tostring(payload.nick), tonumber(payload.id) or 0)
        .. (#parts > 0 and "\n" .. table.concat(parts, " · ") or "")

    local answered = false
    local dialog = UI.Confirm(L("share.offer_title"), body, function()
        answered = true
        request("share.answer", { token = payload.token, accept = true })
    end, L("share.accept"))
    local remove = dialog.OnRemove
    dialog.OnRemove = function(self)
        if remove then remove(self) end
        -- A tick later: the prompt closes itself before running its accept button.
        timer.Simple(0, function()
            if not answered then request("share.answer", { token = payload.token, accept = false }) end
        end)
    end
    surface.PlaySound("garrysmod/content_downloaded.wav")
end)
