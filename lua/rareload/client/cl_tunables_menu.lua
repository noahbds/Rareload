if not CLIENT then return end

RARELOAD = RARELOAD or {}

local function L(key, ...)
    if RARELOAD.L then return RARELOAD.L(key, ...) end
    return key
end

-- Tunable defs keep English labels as their own fallback; the locale files
-- override them via "tunables.<key>" / "tunables.<key>.tip" entries.
local function tunableLabel(def)
    local lang = RARELOAD.Lang
    return (lang and lang.Get("tunables." .. def.key)) or def.label
end

local function tunableDesc(def)
    local lang = RARELOAD.Lang
    return (lang and lang.Get("tunables." .. def.key .. ".tip")) or def.desc
end

local function categoryLabel(catName)
    local lang = RARELOAD.Lang
    return (lang and lang.Get("tunables.category." .. catName)) or catName
end

local function groupByCategory()
    local cats, order = {}, {}
    for _, def in ipairs(RARELOAD.TunableDefs or {}) do
        if not cats[def.category] then
            cats[def.category] = {}
            order[#order + 1] = def.category
        end
        table.insert(cats[def.category], def)
    end
    return cats, order
end

local function addHeader(scroll, text)
    local header = vgui.Create("DLabel", scroll)
    header:Dock(TOP)
    header:DockMargin(2, 12, 2, 4)
    header:SetText(text)
    header:SetFont("DermaDefaultBold")
    header:SetTextColor(Color(120, 180, 240))
    return header
end

local function addLanguageSelector(scroll)
    if not (RARELOAD.Lang and RARELOAD.Lang.GetAvailable) then return end

    addHeader(scroll, L("params.cat.interface"))

    local row = vgui.Create("DPanel", scroll)
    row:Dock(TOP)
    row:DockMargin(2, 2, 2, 2)
    row:SetTall(24)
    row:SetPaintBackground(false)
    row:SetTooltip(L("params.language.tip"))

    local label = vgui.Create("DLabel", row)
    label:Dock(LEFT)
    label:SetWide(180)
    label:SetText(L("params.language"))

    local combo = vgui.Create("DComboBox", row)
    combo:Dock(FILL)
    combo:SetSortItems(false)

    local cv = GetConVar("rareload_language")
    local current = cv and string.lower(cv:GetString()) or "auto"

    combo:AddChoice(L("params.language.auto"), "auto", current == "auto" or current == "")
    for _, code in ipairs(RARELOAD.Lang.GetAvailable()) do
        combo:AddChoice(RARELOAD.Lang.GetName(code), code, current == code)
    end

    combo.OnSelect = function(_, _, _, code)
        RunConsoleCommand("rareload_language", code)
        -- Reopen so every label in this menu picks up the new language.
        timer.Simple(0, function()
            if IsValid(RARELOAD._tunablesFrame) then
                RARELOAD.OpenTunablesMenu()
            end
        end)
    end
end

function RARELOAD.OpenTunablesMenu()
    if IsValid(RARELOAD._tunablesFrame) then
        RARELOAD._tunablesFrame:Remove()
    end

    local frame = vgui.Create("DFrame")
    frame:SetSize(520, 580)
    frame:Center()
    frame:SetTitle(L("params.title"))
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        surface.SetDrawColor(28, 31, 38, 255)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(64, 152, 255, 255)
        surface.DrawRect(0, 24, w, 2)
    end
    RARELOAD._tunablesFrame = frame

    local note = vgui.Create("DLabel", frame)
    note:Dock(BOTTOM)
    note:DockMargin(10, 4, 10, 8)
    note:SetText(L("params.note"))
    note:SetTextColor(Color(150, 150, 150))

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(8, 8, 8, 4)

    addLanguageSelector(scroll)

    local cats, order = groupByCategory()
    for _, catName in ipairs(order) do
        addHeader(scroll, categoryLabel(catName))

        for _, def in ipairs(cats[catName]) do
            local slider = vgui.Create("DNumSlider", scroll)
            slider:Dock(TOP)
            slider:DockMargin(2, 2, 2, 2)
            slider:SetText(tunableLabel(def))
            slider:SetMin(def.min or 0)
            slider:SetMax(def.max or 100)
            slider:SetDecimals(def.type == "int" and 0 or (def.decimals or 1))
            slider:SetValue(RARELOAD.GetTunable(def.key))
            local desc = tunableDesc(def)
            if desc then slider:SetTooltip(desc) end

            slider.OnValueChanged = function(_, val)
                if def.type == "int" then val = math.Round(val) end
                timer.Create("RareloadTunableSend_" .. def.key, 0.35, 1, function()
                    if RARELOAD.SendTunableUpdate then
                        RARELOAD.SendTunableUpdate(def.key, val)
                    end
                end)
            end
        end
    end
end

concommand.Add("rareload_tunables", function()
    RARELOAD.OpenTunablesMenu()
end)
