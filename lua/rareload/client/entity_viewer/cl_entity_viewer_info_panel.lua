local UI_COLORS = {
    bg = Color(24, 25, 29),
    sidebar = Color(18, 19, 22),
    row = Color(32, 34, 40),
    accent = Color(80, 140, 255),
    text = Color(220, 220, 225),
    muted = Color(130, 130, 140)
}

-- Formats SteamID for filesystem (STEAM_0:0:123 -> steam_0_0_123)
local function GetCleanSteamID(sid)
    return string.lower(string.Replace(sid, ":", "_"))
end

function CreateDetailsPanel(data, isNPC, onDeleted, onAction)
    local frame = vgui.Create("DFrame")
    frame:SetSize(850, 600)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:SetBackgroundBlur(true)

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, UI_COLORS.bg)
        draw.RoundedBoxEx(8, 0, 0, 200, h, UI_COLORS.sidebar, false, false, true, false)
        draw.SimpleText("Entity Inspector", "RareloadHeading", 220, 30, UI_COLORS.text)
    end

    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetSize(200, 600)
    sidebar.Paint = function() end

    local content = vgui.Create("DPanel", frame)
    content:SetPos(200, 60)
    content:SetSize(650, 540)
    content.Paint = function() end

    local activeTab = ""
    local function SwitchTab(id)
        if activeTab == id then return end
        activeTab = id
        content:Clear()

        if id == "info" then
            local scroll = vgui.Create("DScrollPanel", content)
            scroll:Dock(FILL)
            scroll:DockMargin(20, 0, 20, 20)

            local function AddRow(label, val)
                local p = vgui.Create("DPanel", scroll)
                p:Dock(TOP)
                p:SetTall(40)
                p:DockMargin(0, 0, 0, 8)
                p.Paint = function(self, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, UI_COLORS.row)
                    draw.SimpleText(label, "RareloadBody", 15, h / 2, UI_COLORS.muted, 0, 1)
                    draw.SimpleText(tostring(val), "RareloadBody", 150, h / 2, UI_COLORS.text, 0, 1)
                end
            end

            AddRow("Class", data.class)
            AddRow("Model", data.model)
            AddRow("Health", (data.health or "?") .. " / " .. (data.maxHealth or "?"))
            if data.pos then AddRow("Pos", string.format("%.1f, %.1f, %.1f", data.pos.x, data.pos.y, data.pos.z)) end
            -- Find the id == "json" section in your CreateDetailsPanel
        elseif id == "json" then
            RARELOAD.JSONEditor.Create(content, data, isNPC, function(newData)
                -- Get the unique ID of the entity we are editing
                local targetId = newData.RareloadNPCID or (data.rawData and data.rawData.RareloadNPCID) or data.id

                -- Send the new data to the Server to be saved to the file
                net.Start("RareloadEntityViewer_UpdateData")
                net.WriteString(tostring(targetId))
                net.WriteBool(isNPC)
                net.WriteTable(newData)
                net.SendToServer()

                ShowNotification("Update request sent to server...", NOTIFY_GENERIC)
                frame:Close()

                -- Optional: Refresh the main viewer after a short delay
                timer.Simple(0.5, function()
                    if OpenEntityViewer then OpenEntityViewer() end
                end)
            end)
        end
    end

    local function Tab(name, id, y)
        local b = vgui.Create("DButton", sidebar)
        b:SetSize(200, 50)
        b:SetPos(0, y)
        b:SetText(name)
        b:SetFont("RareloadBody")
        b:SetTextColor(UI_COLORS.text)
        b.Paint = function(self, w, h)
            if activeTab == id then
                draw.RoundedBox(0, 0, 0, 4, h, UI_COLORS.accent)
                surface.SetDrawColor(80, 140, 255, 20)
                surface.DrawRect(0, 0, w, h)
            end
        end
        b.DoClick = function() SwitchTab(id) end
    end

    Tab("Information", "info", 60)
    Tab("Data Editor", "json", 110)
    SwitchTab("info")
end
