local notificationQueue = {}
local notificationActive = false

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
    notification.AddLegacy(notif.message, notif.type, notif.duration)
    surface.PlaySound(notif.type == NOTIFY_ERROR and "buttons/button10.wav" or "buttons/button15.wav")
    timer.Simple(notif.duration, function()
        if notif.onDismiss then notif.onDismiss() end
        ShowNextNotification()
    end)
end
