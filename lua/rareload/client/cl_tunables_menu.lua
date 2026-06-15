if not CLIENT then return end

RARELOAD = RARELOAD or {}

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

function RARELOAD.OpenTunablesMenu()
    if IsValid(RARELOAD._tunablesFrame) then
        RARELOAD._tunablesFrame:Remove()
    end

    local frame = vgui.Create("DFrame")
    frame:SetSize(520, 580)
    frame:Center()
    frame:SetTitle("Rareload - Parameters")
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
    note:SetText("Changes apply server-wide and persist. Admin only.")
    note:SetTextColor(Color(150, 150, 150))

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(8, 8, 8, 4)

    local cats, order = groupByCategory()
    for _, catName in ipairs(order) do
        local header = vgui.Create("DLabel", scroll)
        header:Dock(TOP)
        header:DockMargin(2, 12, 2, 4)
        header:SetText(catName)
        header:SetFont("DermaDefaultBold")
        header:SetTextColor(Color(120, 180, 240))

        for _, def in ipairs(cats[catName]) do
            local slider = vgui.Create("DNumSlider", scroll)
            slider:Dock(TOP)
            slider:DockMargin(2, 2, 2, 2)
            slider:SetText(def.label)
            slider:SetMin(def.min or 0)
            slider:SetMax(def.max or 100)
            slider:SetDecimals(def.type == "int" and 0 or (def.decimals or 1))
            slider:SetValue(RARELOAD.GetTunable(def.key))
            if def.desc then slider:SetTooltip(def.desc) end

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
