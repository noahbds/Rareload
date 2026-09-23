-- Client UI foundation (REWRITE_PLAN.md §21.2, §25): translations, fonts and scale, the Rareload Derma
-- skin, toasts, the client side of the `rareload` command, and small shared widgets.

RARELOAD.UI = RARELOAD.UI or {}
local UI = RARELOAD.UI

-- Translations come from resource/localization/<lang>/rareload.properties (D16, G74).
function RARELOAD.L(key, ...)
    local phrase = language.GetPhrase("rareload." .. key)
    if select("#", ...) == 0 then return phrase end
    -- Translators write the format string, so a mismatched placeholder must not break the UI.
    local ok, text = pcall(string.format, phrase, ...)
    return ok and text or phrase
end
local L = RARELOAD.L

-- GMod reloads the .properties files itself; panels built with the old language rebuild on this hook.
cvars.AddChangeCallback("gmod_language", function()
    timer.Simple(0.1, function() hook.Run("RareloadLanguageChanged") end)
end, "Rareload.UI")

-- Palette (from v4's dark theme) --------------------------------------------------------------------

UI.C = {
    bg = Color(30, 30, 35, 245), panel = Color(40, 40, 45), panelAlt = Color(50, 50, 56), line = Color(60, 60, 70),
    text = Color(245, 245, 245), text2 = Color(180, 180, 190), textOff = Color(120, 120, 130),
    accent = Color(65, 145, 255), ok = Color(70, 200, 120), warn = Color(255, 195, 85), bad = Color(255, 70, 70),
    button = Color(60, 60, 70), buttonHover = Color(70, 70, 80), buttonDown = Color(50, 50, 60),
}
local C = UI.C

-- Scale and fonts: a fixed set, recreated only when the screen size changes (G37) --------------------

function UI.sc(v) return math.floor(v * UI.S + 0.5) end

local function createFonts()
    UI.S = math.Clamp(ScrH() / 1080, 0.85, 2)
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Roboto", size = math.floor(size * UI.S + 0.5), weight = weight, extended = true })
    end
    font("Rareload.Title", 24, 800)
    font("Rareload.Heading", 17, 700)
    font("Rareload.Body", 15, 500)
    font("Rareload.Small", 13, 500)
end
createFonts()
hook.Add("OnScreenSizeChanged", "Rareload.UI.Fonts", createFonts)

-- Fixed-size fonts for the tool screen and the world display, which don't depend on the screen.
surface.CreateFont("Rareload.Screen", { font = "Roboto", size = 22, weight = 600, extended = true })
surface.CreateFont("Rareload.ScreenTitle", { font = "Roboto", size = 38, weight = 900, extended = true })
surface.CreateFont("Rareload.Panel", { font = "Roboto", size = 26, weight = 500, extended = true })
surface.CreateFont("Rareload.PanelTitle", { font = "Roboto", size = 34, weight = 800, extended = true })
surface.CreateFont("Rareload.PanelSmall", { font = "Roboto", size = 20, weight = 500, extended = true })

-- Derma skin: every stock control inside a Rareload window is painted here (D18, G78) ----------------

local SKIN = { PrintName = "Rareload", Author = "Rareload", DermaVersion = 1 }

local function box(r, w, h, col) draw.RoundedBox(r, 0, 0, w, h, col) end

function SKIN:PaintFrame(_, w, h)
    box(8, w, h, C.bg)
    draw.RoundedBoxEx(8, 0, 0, w, 24, C.panel, true, true, false, false)
    surface.SetDrawColor(C.accent)
    surface.DrawRect(0, 24, w, 1)
end

function SKIN:PaintPanel(panel, w, h)
    if panel.m_bBackground then box(6, w, h, panel.m_bgColor or C.panel) end
end

function SKIN:PaintButton(panel, w, h)
    if not panel.m_bBackground then return end
    local col = C.button
    if not panel:IsEnabled() then col = C.buttonDown
    elseif panel.Depressed or panel:IsSelected() or panel:GetToggle() then col = C.accent
    elseif panel.Hovered then col = C.buttonHover end
    box(6, w, h, col)
end

function SKIN:PaintWindowCloseButton(panel, w, h)
    if panel.Hovered then draw.RoundedBox(4, 4, 2, w - 8, h - 4, C.bad) end
    local s, x, y = 4, w / 2, h / 2
    surface.SetDrawColor(C.text)
    surface.DrawLine(x - s, y - s, x + s, y + s)
    surface.DrawLine(x - s, y + s, x + s, y - s)
end

function SKIN:PaintTextEntry(panel, w, h)
    if panel.m_bBackground then
        box(4, w, h, panel:HasFocus() and C.accent or C.line)
        draw.RoundedBox(4, 1, 1, w - 2, h - 2, panel:IsEnabled() and C.panelAlt or C.panel)
    end
    local placeholder = panel:GetPlaceholderText()
    if placeholder and placeholder ~= "" and panel:GetText() == "" then
        local text = panel:GetText()
        panel:SetText(language.GetPhrase((placeholder:gsub("^#", ""))))
        panel:DrawTextEntryText(panel:GetPlaceholderColor(), panel:GetHighlightColor(), panel:GetCursorColor())
        panel:SetText(text)
        return
    end
    panel:DrawTextEntryText(panel:GetTextColor(), panel:GetHighlightColor(), panel:GetCursorColor())
end

function SKIN:PaintCheckBox(panel, w, h)
    box(4, w, h, panel:IsEnabled() and C.line or C.panel)
    if panel:GetChecked() then
        draw.RoundedBox(3, 2, 2, w - 4, h - 4, panel:IsEnabled() and C.accent or C.textOff)
    end
end

function SKIN:PaintListView(panel, w, h)
    if panel.m_bBackground then box(6, w, h, C.panel) end
end

function SKIN:PaintListViewLine(panel, w, h)
    if panel:IsSelected() then box(0, w, h, ColorAlpha(C.accent, 120))
    elseif panel.Hovered then box(0, w, h, C.panelAlt)
    elseif panel.m_bAlt then box(0, w, h, Color(255, 255, 255, 6)) end
end

function SKIN:PaintVScrollBar(_, w, h) box(4, w, h, Color(0, 0, 0, 60)) end
function SKIN:PaintScrollBarGrip(panel, w, h) box(4, w, h, panel.Hovered and C.text2 or C.textOff) end
function SKIN:PaintButtonUp() end
function SKIN:PaintButtonDown() end

function SKIN:PaintComboBox(panel, w, h)
    box(4, w, h, (panel.Hovered or panel:IsMenuOpen()) and C.buttonHover or C.button)
end

function SKIN:PaintComboDownArrow(_, w, h)
    surface.SetDrawColor(C.text2)
    draw.NoTexture()
    surface.DrawPoly({ { x = w * 0.3, y = h * 0.4 }, { x = w * 0.7, y = h * 0.4 }, { x = w * 0.5, y = h * 0.65 } })
end

function SKIN:PaintMenu(_, w, h) box(0, w, h, C.panel) end
function SKIN:PaintMenuSpacer(_, w, h) box(0, w, h, C.line) end

function SKIN:PaintMenuOption(panel, w, h)
    if panel.Hovered or panel.Highlight then box(0, w, h, C.accent) end
    if panel:GetChecked() then draw.RoundedBox(2, 8, h / 2 - 3, 6, 6, C.text) end
end

function SKIN:PaintTooltip(_, w, h) box(4, w, h, C.panelAlt) end

function SKIN:PaintNumSlider(_, w, h)
    surface.SetDrawColor(C.line)
    surface.DrawRect(8, h / 2 - 1, w - 16, 2)
end

function SKIN:PaintSliderKnob(panel, w, h)
    draw.RoundedBox(h / 2, 1, 1, w - 2, h - 2, panel.Hovered and C.text or C.accent)
end

-- Colours Rareload sets itself; any other group (tabs, trees…) is read from the Default skin when a
-- panel asks for it. The engine loads the Default skin after autorun files run, so nothing is copied here.
SKIN.Colours = setmetatable({
    Window = { TitleActive = C.text, TitleInactive = C.text2 },
    Label = { Default = C.text, Bright = C.text, Dark = C.text, Highlight = C.accent },
    Button = { Normal = C.text, Hover = C.text, Down = C.text2, Disabled = C.textOff },
    TooltipText = C.text,
}, { __index = function(_, k)
    local default = derma.GetNamedSkin("Default")
    return default and default.Colours[k]
end })
SKIN.colTextEntryText, SKIN.colTextEntryTextHighlight = C.text, C.accent
SKIN.colTextEntryTextCursor, SKIN.colTextEntryTextPlaceholder = C.text, C.textOff
SKIN.colNumSliderNotch = C.line

derma.DefineSkin("Rareload", "Rareload's dark skin", SKIN)

-- Widgets -----------------------------------------------------------------------------------------

-- A skinned, centered popup window. Sizes are at 1080p and scaled.
function UI.Frame(title, w, h)
    local frame = vgui.Create("DFrame")
    frame:SetSkin("Rareload")
    frame:SetTitle(title)
    frame:SetSize(math.min(UI.sc(w), ScrW() - 40), math.min(UI.sc(h), ScrH() - 40))
    frame:SetSizable(true)
    frame:SetMinWidth(UI.sc(w * 0.6))
    frame:SetMinHeight(UI.sc(h * 0.6))
    frame.btnMaxim:SetVisible(false)
    frame.btnMinim:SetVisible(false)
    frame:Center()
    frame:MakePopup()
    return frame
end

function UI.Button(parent, text, onClick)
    local b = vgui.Create("DButton", parent)
    b:SetText(text)
    b:SetFont("Rareload.Body")
    b:SetTall(UI.sc(30))
    b.DoClick = onClick
    return b
end

-- Stock dialog for confirmations (G85).
function UI.Confirm(title, text, onYes)
    Derma_Query(text, title, L("ui.yes"), onYes, L("ui.no"))
end

-- Formatting --------------------------------------------------------------------------------------

function UI.Pos(t)
    local v = RARELOAD.Util.ToVector(t)
    return v and string.format("%.0f  %.0f  %.0f", v.x, v.y, v.z) or "-"
end

function UI.Date(t)
    if not t then return "-" end
    return os.date(os.date("%x", t) == os.date("%x") and "%H:%M:%S" or "%x %H:%M", t)   -- G80
end

-- Translated names of the states that are on.
local STATES = { "god", "notarget", "frozen", "noclip", "flashlight" }
function UI.States(states)
    local on = {}
    for _, k in ipairs(STATES) do
        if istable(states) and states[k] then on[#on + 1] = L("state." .. k) end
    end
    return #on > 0 and table.concat(on, ", ") or L("ui.none")
end

-- Toasts ------------------------------------------------------------------------------------------

local KINDS = { info = NOTIFY_GENERIC, ok = NOTIFY_GENERIC, error = NOTIFY_ERROR, hint = NOTIFY_HINT }

RARELOAD.Net.On("toast", function(t)
    notification.AddLegacy(L(t.key, unpack(t.args or {})), KINDS[t.kind] or NOTIFY_GENERIC, 4)   -- G79
    surface.PlaySound(t.kind == "error" and "buttons/button10.wav" or "buttons/button14.wav")
    hook.Run("RareloadToast", t)
end)

RARELOAD.Net.On("dev.reload", function()
    include("autorun/rareload.lua")
end)

-- Client subcommands of `rareload` (timeline, menu…): the server owns the command and sends them here.
UI.commands = UI.commands or {}   -- name -> fn(args)

function UI.Command(name, fn)
    UI.commands[name] = fn
end

RARELOAD.Net.On("cmd", function(p)
    local fn = UI.commands[p.name]
    if fn then fn(p.args or {}) end
end)
