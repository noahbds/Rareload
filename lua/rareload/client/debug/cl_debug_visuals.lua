RARELOAD = RARELOAD or {}
RARELOAD.Debug = RARELOAD.Debug or {}
RARELOAD.Debug.Visuals = RARELOAD.Debug.Visuals or {}
RARELOAD.Debug.Logs = {} -- Store logs for on-screen display

local debugItems = {} -- 3D world items

net.Receive("RareloadDebugLog", function()
    if not RARELOAD.Debug.IsEnabled() then return end

    local levelVal = net.ReadUInt(4)
    local header = net.ReadString()
    local len = net.ReadUInt(32)
    local data = net.ReadData(len)
    local message = util.Decompress(data)
    
    local hasEnt = net.ReadBool()
    local ent = hasEnt and net.ReadEntity() or nil

    local col = Color(200, 200, 200)
    for k, v in pairs(RARELOAD.Debug.LEVELS) do
        if v.value == levelVal then col = v.color break end
    end

    MsgC(col, "[RL-NET] " .. header .. ": ")
    MsgC(Color(255, 255, 255), message .. "\n")

    table.insert(RARELOAD.Debug.Logs, 1, {
        time = CurTime(),
        text = header .. ": " .. (string.len(message) > 50 and string.sub(message, 1, 50).."..." or message),
        color = col
    })

    if #RARELOAD.Debug.Logs > 10 then table.remove(RARELOAD.Debug.Logs) end
end)

-- 2. Receive 3D World Events
net.Receive("RareloadDebugWorldEvent", function()
    local pos = net.ReadVector()
    local type = net.ReadString()
    local col = net.ReadColor()
    local dur = net.ReadFloat()
    local extra = net.ReadFloat()

    table.insert(debugItems, {
        pos = pos,
        type = type,
        col = col,
        dieTime = CurTime() + dur,
        extra = extra
    })
end)

-- 3. Render 3D Elements (The "ESP" like view)
hook.Add("PostDrawTranslucentRenderables", "RareloadDebug3D", function()
    if not RARELOAD.Debug.IsEnabled() then return end

    -- Draw Networked Events
    for i = #debugItems, 1, -1 do
        local item = debugItems[i]
        if CurTime() > item.dieTime then
            table.remove(debugItems, i)
        else
            render.SetColorMaterial()
            if item.type == "sphere" then
                render.DrawSphere(item.pos, item.extra, 10, 10, Color(item.col.r, item.col.g, item.col.b, 50))
                render.DrawWireframeSphere(item.pos, item.extra, 10, 10, item.col, true)
            elseif item.type == "box" then
                render.DrawWireframeBox(item.pos, Angle(0,0,0), Vector(-item.extra, -item.extra, 0), Vector(item.extra, item.extra, item.extra*2), item.col, true)
            elseif item.type == "cross" then
                render.DrawLine(item.pos + Vector(10,0,0), item.pos - Vector(10,0,0), item.col)
                render.DrawLine(item.pos + Vector(0,10,0), item.pos - Vector(0,10,0), item.col)
                render.DrawLine(item.pos + Vector(0,0,10), item.pos - Vector(0,0,10), item.col)
            end
        end
    end

    -- Draw Saved Entity Positions (Visualizing the JSON data in real time)
    local mapName = game.GetMap()
    if RARELOAD.playerPositions and RARELOAD.playerPositions[mapName] then
        for steamID, pdata in pairs(RARELOAD.playerPositions[mapName]) do
            -- Draw saved entities
            if pdata.entities then
                for _, entInfo in ipairs(pdata.entities) do
                    local pos = entInfo.pos
                    if type(pos) == "table" then pos = Vector(pos.x, pos.y, pos.z) end
                    
                    if pos and LocalPlayer():GetPos():DistToSqr(pos) < 1000000 then -- 1000 units
                        local ang = Angle(0, CurTime() * 50, 0)
                        local alpha = 100 + math.sin(CurTime() * 5) * 50
                        
                        render.DrawWireframeBox(pos, angle_zero, Vector(-5,-5,-5), Vector(5,5,5), Color(0, 255, 0, 255), true)
                        
                        cam.Start3D2D(pos + Vector(0,0,10), Angle(0, LocalPlayer():EyeAngles().y - 90, 90), 0.1)
                            draw.SimpleText(entInfo.class, "Default", 0, 0, Color(0, 255, 0, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        cam.End3D2D()
                    end
                end
            end
        end
    end
end)

hook.Add("HUDPaint", "RareloadDebugHUD", function()
    if not RARELOAD.Debug.IsEnabled() then return end
    
    local x, y = ScrW() - 320, 50
    
    -- Background
    draw.RoundedBox(4, x, y, 300, 30 + (#RARELOAD.Debug.Logs * 20), Color(0, 0, 0, 200))
    
    -- Title
    draw.SimpleText("RARELOAD DEBUGGER", "DermaDefaultBold", x + 150, y + 5, Color(255, 255, 255), TEXT_ALIGN_CENTER)
    
    -- System Stats
    local entCount = #ents.GetAll()
    local savedMap = game.GetMap()
    local savedCount = 0
    if RARELOAD.playerPositions and RARELOAD.playerPositions[savedMap] then
        savedCount = table.Count(RARELOAD.playerPositions[savedMap])
    end
    
    y = y + 25
    draw.SimpleText(string.format("Ents: %d | Saved Profiles: %d", entCount, savedCount), "DermaDefault", x + 150, y, Color(200, 200, 200), TEXT_ALIGN_CENTER)
    
    -- Logs
    y = y + 20
    for _, log in ipairs(RARELOAD.Debug.Logs) do
        local alpha = math.Clamp(255 - (CurTime() - log.time) * 25, 50, 255)
        draw.SimpleText(log.text, "DermaDefault", x + 10, y, ColorAlpha(log.color, alpha))
        y = y + 20
    end
end)