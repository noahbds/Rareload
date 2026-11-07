-- Checkpoints (5.4 plan, D7): the window to set, go to and delete them, and their markers in the world.

local L, UI = RARELOAD.L, RARELOAD.UI
local C, sc = UI.C, UI.sc

RARELOAD.CheckpointsUI = RARELOAD.CheckpointsUI or {}
local CP = RARELOAD.CheckpointsUI
CP.list = CP.list or {}

local function request(op, args) RARELOAD.Net.Request(op, args) end

RARELOAD.Net.On("checkpoints", function(p)
    CP.list = istable(p.list) and p.list or {}
    for _, c in ipairs(CP.list) do c.vec = RARELOAD.Util.ToVector(c.pos) end
    hook.Run("RareloadStateChanged", "checkpoints")
end)

function CP.Open()
    if IsValid(CP.frame) then CP.frame:Remove() end
    local frame = UI.Window({ title = L("checkpoint.title"), subtitle = L("checkpoint.help"), w = 680, h = 560 })
    CP.frame = frame

    local bar = vgui.Create("DPanel", frame)
    bar:Dock(TOP)
    bar:SetTall(sc(36))
    bar:DockMargin(0, 0, 0, sc(10))
    bar:SetPaintBackground(false)
    local name = UI.TextEntry(bar, L("checkpoint.name"))
    name:Dock(FILL)
    name:DockMargin(0, 0, sc(8), 0)
    local add = UI.Button(bar, L("checkpoint.add"), function()
        request("checkpoint.add", { name = string.sub(name:GetValue(), 1, 64) })
        name:SetValue("")
    end, { style = "success", icon = "flag_green" })
    add:Dock(RIGHT)
    add:SetWide(sc(160))
    name.OnEnter = function() add:DoClick() end

    local scroll = UI.Scroll(frame)
    scroll:Dock(FILL)

    local function fill()
        if not IsValid(scroll) then return end
        scroll:Clear()
        if #CP.list == 0 then
            local e = UI.Empty(scroll, "flag_blue", L("checkpoint.none"), L("checkpoint.help"))
            e:Dock(TOP)
            e:SetTall(sc(200))
            return
        end
        for i, c in ipairs(CP.list) do
            local off = c.disabled == true
            local row = vgui.Create("DPanel", scroll)
            row:Dock(TOP)
            row:SetTall(sc(46))
            row:DockMargin(0, 0, sc(4), sc(6))
            row.Paint = function(_, w, h)
                draw.RoundedBox(sc(8), 0, 0, w, h, C.surface)
                UI.DrawIcon("flag_blue", sc(12), (h - sc(16)) / 2, sc(16),
                    off and ColorAlpha(color_white, 90) or color_white)
                draw.SimpleText(UI.Clip(i .. ". " .. c.name, "Rareload.BodyB", w - sc(310)), "Rareload.BodyB", sc(38),
                    h / 2, off and C.textOff or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if c.vec then
                    draw.SimpleText(L("inspector.units", math.Round(LocalPlayer():GetPos():Distance(c.vec))),
                        "Rareload.Small", w - sc(260), h / 2, C.text3, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
            local del = UI.Button(row, "", function() request("checkpoint.remove", { i = i }) end,
                { style = "danger", icon = "bin" })
            del:Dock(RIGHT)
            del:SetWide(sc(40))
            del:DockMargin(sc(6), sc(6), sc(6), sc(6))
            del:SetTooltip(L("checkpoint.remove"))
            local go = UI.Button(row, L("checkpoint.go"), function() request("checkpoint.go", { i = i }) end,
                { style = "info", icon = "arrow_right" })
            go:Dock(RIGHT)
            go:SetWide(sc(120))
            go:DockMargin(sc(6), sc(6), 0, sc(6))
            local sw = UI.Switch(row, "", not off, function() request("checkpoint.toggle", { i = i }) end,
                { tooltip = L(off and "screen.disabled" or "screen.enabled") })
            sw:Dock(RIGHT)
            sw:SetWide(sc(50))
            sw:DockMargin(0, sc(8), 0, sc(8))
        end
    end
    fill()
    hook.Add("RareloadStateChanged", frame, function(_, what) if what == "checkpoints" then fill() end end)
    request("checkpoint.get")
    return frame
end

RARELOAD.UI.Command("checkpoints", function() CP.Open() end)
concommand.Add("rareload_checkpoints", function() CP.Open() end, nil, "Open your Rareload checkpoints")

-- Markers: a beam on each checkpoint, and its name and distance on screen above it, fading out with
-- distance.
local RANGE = 3000

local function shown()
    return #CP.list > 0 and RARELOAD.Get(nil, "showCheckpoints") and RARELOAD.World.Active()
end

local function alphaAt(d) return math.Clamp((RANGE - d) / 600, 0, 1) * 255 end

hook.Add("PostDrawTranslucentRenderables", "Rareload.Checkpoints", function(depth, sky)
    if depth or sky or not shown() then return end
    local eye = EyePos()
    render.SetColorMaterial()
    for _, c in ipairs(CP.list) do
        local d = not c.disabled and c.vec and eye:Distance(c.vec)
        if d and d < RANGE and d > 40 then
            render.DrawBeam(c.vec, c.vec + Vector(0, 0, 80), 4, 0, 1, ColorAlpha(C.accent, alphaAt(d) * 0.7))
        end
    end
end)

hook.Add("HUDPaint", "Rareload.Checkpoints", function()
    if not shown() then return end
    local eye = EyePos()
    for i, c in ipairs(CP.list) do
        local d = not c.disabled and c.vec and eye:Distance(c.vec)
        if d and d < RANGE and d > 40 then
            local p = (c.vec + Vector(0, 0, 88)):ToScreen()
            if p.visible then
                local a = alphaAt(d)
                local text = i .. ". " .. c.name
                surface.SetFont("Rareload.BodyB")
                local tw, th = surface.GetTextSize(text)
                local w, h = tw + sc(34), th + sc(10)
                local x, y = math.floor(p.x - w / 2), math.floor(p.y - h)
                draw.RoundedBox(sc(6), x, y, w, h, ColorAlpha(C.surface, a * 0.85))
                UI.DrawIcon("flag_blue", x + sc(6), y + (h - sc(16)) / 2, sc(16), ColorAlpha(color_white, a))
                draw.SimpleText(text, "Rareload.BodyB", x + sc(28), y + h / 2, ColorAlpha(C.text, a), TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)
                draw.SimpleText(L("inspector.units", math.Round(d)), "Rareload.Small", p.x, y + h + sc(2),
                    ColorAlpha(C.text3, a), TEXT_ALIGN_CENTER)
            end
        end
    end
end)
