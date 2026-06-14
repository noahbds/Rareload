local notificationQueue  = {}
local notificationActive = false
local lastNotificationSignature = nil
local lastNotificationTime = 0

function ShowNotification(message, type, duration, onDismiss)
    type     = type or NOTIFY_GENERIC
    duration = duration or 4

    local signature = tostring(message) .. "|" .. tostring(type) .. "|" .. tostring(duration)
    local now = CurTime()
    if signature == lastNotificationSignature and (now - lastNotificationTime) < 0.35 then
        return
    end

    lastNotificationSignature = signature
    lastNotificationTime = now

    table.insert(notificationQueue, {
        message   = message,
        type      = type,
        duration  = duration,
        onDismiss = onDismiss,
    })

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
        THEME:DrawBlur(self, 2)

        local accent = THEME.primary
        if notif.type == NOTIFY_ERROR then
            accent = THEME.error
        elseif notif.type == NOTIFY_HINT then
            accent = THEME.info
        elseif notif.type == NOTIFY_GENERIC then
            accent = THEME.success
        end

        draw.RoundedBox(12, 0, 0, w, h, THEME.surface)
        draw.RoundedBox(12, 0, 0, w, h, Color(0, 0, 0, 100))

        -- Left accent stripe
        draw.RoundedBoxEx(12, 0, 0, 6, h, accent, true, false, true, false)

        draw.SimpleText(notif.message, "RareloadBody", 24, h / 2,
            THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
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
