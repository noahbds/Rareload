-- lua/entities/ent_rareload_spawnpoint.lua

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Rareload Spawn Point"
ENT.Author = "Noahbds"
ENT.Spawnable = false

function ENT:Initialize()
    local playerModel = player_manager.TranslatePlayerModel("kleiner") -- Default model if player model is not set
    self:SetModel(playerModel)
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 100)) -- Set transparency
    self:SetSolid(SOLID_NONE)
    self:DrawShadow(false)
end

function ENT:Think()
    if RARELOAD.settings.debugEnabled then
        self:SetNoDraw(false)
    else
        self:SetNoDraw(true)
    end
end

function ENT:OnTakeDamage(dmginfo)
    return false -- Make the entity not killable
end