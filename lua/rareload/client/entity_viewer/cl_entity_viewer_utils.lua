local notificationQueue = {}
local notificationActive = false

function DrawShadowedPanel(x, y, w, h, radius, color, shadow)
    radius = radius or 8
    shadow = shadow or Color(0, 0, 0, 180)
    draw.RoundedBox(radius, x + 3, y + 3, w, h, shadow)
    draw.RoundedBox(radius, x, y, w, h, color)
end

function ShowNotification(message, type, duration, onDismiss)
    type = type or NOTIFY_GENERIC
    duration = duration or 4

    table.insert(notificationQueue, { message = message, type = type, duration = duration, onDismiss = onDismiss })
    if not notificationActive then
        ShowNextNotification()
    end
end

function ShowNextNotification()
    if #notificationQueue == 0 then
        notificationActive = false
        return
    end
    notificationActive = true
    local notif = table.remove(notificationQueue, 1)

    local notifPanel = vgui.Create("DPanel")
    notifPanel:SetSize(420, 60)
    notifPanel:SetPos(ScrW() / 2 - 210, 80)
    notifPanel:SetAlpha(0)
    notifPanel:AlphaTo(255, 0.2, 0)
    notifPanel.Paint = function(self, w, h)
        local col = notif.type == NOTIFY_ERROR and Color(255, 60, 60, 230)
            or notif.type == NOTIFY_HINT and Color(90, 180, 255, 230)
            or Color(60, 180, 120, 230)
        DrawShadowedPanel(0, 0, w, h, 12, col, Color(0, 0, 0, 120))
        draw.SimpleText(notif.message, "RareloadText", 18, h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    surface.PlaySound(notif.type == NOTIFY_ERROR and "buttons/button10.wav" or "buttons/button15.wav")

    timer.Simple(notif.duration, function()
        if not IsValid(notifPanel) then return end
        notifPanel:AlphaTo(0, 0.2, 0, function()
            if IsValid(notifPanel) then notifPanel:Remove() end
            if notif.onDismiss then notif.onDismiss() end
            ShowNextNotification()
        end)
    end)
end

function CreateModernSearchBar(parent)
    local container = vgui.Create("DPanel", parent)
    container:SetTall(40)
    container.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.surface)
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local searchIcon = vgui.Create("DPanel", container)
    searchIcon:SetSize(16, 16)
    searchIcon:SetPos(12, 12)
    searchIcon.Paint = function(self, w, h)
        surface.SetDrawColor(THEME.textSecondary)
        surface.SetMaterial(Material("icon16/magnifier.png"))
        surface.DrawTexturedRect(0, 0, 16, 16)
    end

    local searchBar = vgui.Create("DTextEntry", container)
    searchBar:SetPos(36, 8)
    searchBar:SetSize(200, 24)
    searchBar:SetPlaceholderText("Search entities and NPCs...")
    searchBar:SetFont("RareloadBody")
    searchBar:SetTextColor(THEME.textPrimary)
    searchBar.Paint = function(self, w, h)
        surface.SetDrawColor(THEME.backgroundDark)
        surface.DrawRect(0, 0, w, h)

        if self:GetPlaceholderText() and self:GetValue() == "" then
            draw.SimpleText(self:GetPlaceholderText(), self:GetFont(), 4, h / 2,
                THEME.textTertiary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        self:DrawTextEntryText(THEME.textPrimary, THEME.primary, THEME.textPrimary)

        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    container.PerformLayout = function(self, w, h)
        searchBar:SetSize(w - 48, 24)
    end

    return container, searchBar
end

function CreateActionButton(parent, text, icon, color, tooltip)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetSize(32, 32)
    btn:SetTooltip(tooltip or text)

    local hoverFraction = 0
    local pressFraction = 0

    btn.Paint = function(self, w, h)
        hoverFraction = Lerp(FrameTime() * 8, hoverFraction, self:IsHovered() and 1 or 0)
        pressFraction = Lerp(FrameTime() * 12, pressFraction, self:IsDown() and 1 or 0)

        local bgColor = THEME:LerpColor(hoverFraction * 0.1, color, Color(255, 255, 255))
        bgColor = THEME:LerpColor(pressFraction * 0.1, bgColor, Color(0, 0, 0))

        draw.RoundedBox(6, 0, 0, w, h, bgColor)

        if hoverFraction > 0 then
            draw.RoundedBox(6, 0, 0, w, h, Color(255, 255, 255, 20 * hoverFraction))
        end

        surface.SetDrawColor(255, 255, 255, 255 - pressFraction * 50)
        surface.SetMaterial(Material(icon))
        surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
    end

    return btn
end

function CreateStatsCard(parent, title, value, subtitle)
    local card = vgui.Create("DPanel", parent)
    card:SetSize(100, 60)

    card.Paint = function(self, w, h)
        THEME:DrawCard(0, 0, w, h, 2)

        draw.SimpleText(title, "RareloadCaption", w / 2, 8,
            THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        draw.SimpleText(tostring(math.Round(value or 0)), "RareloadSubheading", w / 2, h / 2 - 2,
            THEME.primary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if subtitle then
            draw.SimpleText(subtitle, "RareloadCaption", w / 2, h - 8,
                THEME.textTertiary, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        end
    end

    return card
end
