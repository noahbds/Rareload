-- ─────────────────────────────────────────────────────────────────────────────
-- Shared Rareload client UI primitives (RARELOAD.UI)
--
-- One home for the scaled-font / button / scrollbar / model-framing / dialog
-- helpers the Save Timeline and the (save-scoped) entity viewer both use, so the
-- two panels look like one system and the code lives in exactly one place.
--
-- Scale: every size is authored at 1080p and multiplied by UI.S (ScrH()/1080,
-- clamped). Call UI.EnsureFonts() before building a panel; it (re)creates the RH_*
-- font set for the current scale. Colors come from the global THEME at draw time.
-- ─────────────────────────────────────────────────────────────────────────────

if not CLIENT then return end

RARELOAD = RARELOAD or {}
local UI = RARELOAD.UI or {}
RARELOAD.UI = UI

local draw, surface, vgui = draw, surface, vgui
local Lerp, FrameTime, IsValid = Lerp, FrameTime, IsValid
local ALIGN_L, ALIGN_R, ALIGN_C, ALIGN_T, ALIGN_M =
    TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, TEXT_ALIGN_CENTER

-- Resolve L at call time — this module loads before the lang table on some paths.
local function L(...) return (RARELOAD.L or function(_, v) return tostring(v) end)(...) end

UI.S = UI.S or 1

-- ── scaling + fonts ─────────────────────────────────────────────────────────

function UI.Scale() return math.Clamp(ScrH() / 1080, 0.85, 2.1) end

function UI.sc(v) return math.floor(v * UI.S + 0.5) end

-- surface.CreateFont with an existing name redefines it, so this is safe to call
-- again on a resolution change. Returns the current scale.
function UI.EnsureFonts()
    local s = UI.Scale()
    if UI._fontScale == s then return UI.S end
    UI._fontScale = s
    UI.S = s
    local function f(name, size, weight)
        surface.CreateFont(name, {
            font = "Roboto", size = math.floor(size * s + 0.5), weight = weight,
            antialias = true, extended = true,
        })
    end
    f("RH_Title", 25, 800)
    f("RH_Sub", 14, 500)
    f("RH_H1", 22, 700)
    f("RH_H2", 17, 600)
    f("RH_Body", 15, 500)
    f("RH_BodyB", 15, 700)
    f("RH_Small", 13, 500)
    f("RH_Tiny", 11, 600)
    f("RH_Stat", 26, 800)
    f("RH_Btn", 15, 600)
    return UI.S
end

-- ── Derma (Silk) icons ──────────────────────────────────────────────────────

UI.icons = UI.icons or {
    ent      = Material("icon16/bricks.png"),
    npc      = Material("icon16/user.png"),
    veh      = Material("icon16/car.png"),
    pin      = Material("icon16/star.png"),
    note     = Material("icon16/note.png"),
    health   = Material("icon16/heart.png"),
    search   = Material("icon16/magnifier.png"),
    weapon   = Material("icon16/gun.png"),
    prop     = Material("icon16/brick.png"),
    respawn  = Material("icon16/arrow_refresh.png"),
    delete   = Material("icon16/cross.png"),
    inspect  = Material("icon16/magnifier.png"),
}

-- ── shared widgets ──────────────────────────────────────────────────────────

local sc = UI.sc

function UI.StyleScrollbar(scroll)
    local vb = scroll:GetVBar()
    if not IsValid(vb) then return end
    vb:SetWide(sc(7))
    vb.Paint = function() end
    vb.btnUp.Paint = function() end
    vb.btnDown.Paint = function() end
    vb.btnGrip.Paint = function(_, w, h) draw.RoundedBox(sc(4), sc(1), 0, w - sc(2), h, THEME.surfaceHigh) end
end

-- Frame a DModelPanel's camera onto its model's render bounds.
function UI.FrameModelPanel(mp)
    local ent = mp:GetEntity()
    if not IsValid(ent) then return end
    local mn, mx = ent:GetRenderBounds()
    local center = (mn + mx) * 0.5
    local size   = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
    local fov    = 42
    local dist   = (size * 1.25) / math.tan(math.rad(fov / 2))
    mp:SetLookAt(center)
    mp:SetCamPos(center + Vector(dist * 0.65, dist * 0.5, dist * 0.35))
    mp:SetFOV(fov)
end

-- Self-drawing button with hover animation. opts.solid = filled accent button.
function UI.Button(parent, text, color, onClick, opts)
    opts = opts or {}
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn.HoverAnim = 0
    btn._t = text
    btn._solid = opts.solid == true
    btn.GetText2 = function(self) return self._t end
    btn.SetText2 = function(self, t) self._t = t end
    btn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
        local r = sc(8)
        if self._solid then
            local bg = THEME:LerpColor(self.HoverAnim * 0.35, color, THEME.textPrimary)
            draw.RoundedBox(r, 0, 0, w, h, bg)
            draw.SimpleText(self:GetText2(), "RH_Btn", w / 2, h / 2, THEME.background, ALIGN_C, ALIGN_M)
        else
            -- flat tint that deepens toward the accent on hover (no sharp outline —
            -- an outlined rect over a rounded fill leaves corner-bracket artifacts)
            local base = THEME:LerpColor(0.12, THEME.surface, color)
            local bg = THEME:LerpColor(self.HoverAnim * 0.45, base, color)
            draw.RoundedBox(r, 0, 0, w, h, bg)
            local txtCol = THEME:LerpColor(self.HoverAnim, THEME.textPrimary, THEME.background)
            draw.SimpleText(self:GetText2(), "RH_Btn", w / 2, h / 2, txtCol, ALIGN_C, ALIGN_M)
        end
    end
    btn.DoClick = function(self)
        surface.PlaySound("ui/buttonclickrelease.wav")
        onClick(self)
    end
    return btn
end

-- Themed yes/no dialog matching the panels (replaces Derma_Query).
function UI.ConfirmDialog(title, body, onYes)
    local d = vgui.Create("DFrame")
    d:SetSize(sc(440), sc(180))
    d:Center()
    d:SetTitle("")
    d:ShowCloseButton(false)
    d:MakePopup()
    d.Paint = function(_, w, h)
        draw.RoundedBox(sc(12), 0, 0, w, h, THEME.background)
        draw.SimpleText(title, "RH_H2", sc(20), sc(18), THEME.textPrimary, ALIGN_L, ALIGN_T)
        draw.DrawText(body, "RH_Body", sc(20), sc(52), THEME.textSecondary, ALIGN_L)
    end
    local yes = UI.Button(d, L("common.proceed"), THEME.error, function() d:Close(); onYes() end, { solid = true })
    yes:SetSize(sc(190), sc(36)); yes:SetPos(sc(20), sc(126))
    local no = UI.Button(d, L("common.cancel"), THEME.surface, function() d:Close() end)
    no:SetSize(sc(190), sc(36)); no:SetPos(sc(230), sc(126))
    return d
end

-- Draw a small search magnifier at (cx, cy) with radius rad, using surface prims
-- (glyph fonts can't be relied on for the emoji).
function UI.DrawSearchIcon(cx, cy, rad, col)
    surface.SetDrawColor(col or THEME.textTertiary)
    for i = 0, 32 do
        local a1, a2 = math.rad(i / 32 * 360), math.rad((i + 1) / 32 * 360)
        surface.DrawLine(cx + math.cos(a1) * rad, cy + math.sin(a1) * rad,
            cx + math.cos(a2) * rad, cy + math.sin(a2) * rad)
    end
    surface.DrawLine(cx + rad * 0.7, cy + rad * 0.7, cx + rad * 1.7, cy + rad * 1.7)
end

return UI
