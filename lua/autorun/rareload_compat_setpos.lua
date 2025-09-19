-- RARELOAD compatibility shim for SetPos
-- Some addons wrap Entity:SetPos and expect a Vector strictly.
-- This wrapper coerces common formats (tables, strings) into a Vector
-- before delegating to the previously defined SetPos implementation.

if SERVER then
    local function coerceVectorArg(p)
        if not (isvector and isvector(p)) then
            if istable and istable(p) then
                local x, y, z
                if p.x and p.y and p.z then
                    x, y, z = p.x, p.y, p.z
                elseif p[1] and p[2] and p[3] then
                    x, y, z = p[1], p[2], p[3]
                end
                if x and y and z then
                    p = Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
                end
            elseif isstring and isstring(p) then
                if RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.ToVector then
                    local v = RARELOAD.DataUtils.ToVector(p)
                    if v then p = v end
                end
                if not (isvector and isvector(p)) then
                    local ok, v = pcall(util.StringToType, tostring(p), "Vector")
                    if ok and v then p = v end
                end
            end
        end
        return p
    end

    local function installWrapper()
        local ENT = FindMetaTable and FindMetaTable("Entity")
        if not ENT then return end

        -- If already wrapped by us and still present, do nothing
        if ENT.RareloadSetPosWrapped then return end

        local prev = ENT.SetPos
        ENT.RareloadOldSetPos = prev

        function ENT:SetPos(p, ...)
            p = coerceVectorArg(p)
            return self:RareloadOldSetPos(p, ...)
        end

        ENT.RareloadSetPosWrapped = true

        -- If another addon saved the original as oldSetPos, wrap that too
        if ENT.oldSetPos and not ENT.RareloadOldSetPosWrapped then
            local old = ENT.oldSetPos
            ENT.RareloadOrig_oldSetPos = old
            function ENT:oldSetPos(p, ...)
                p = coerceVectorArg(p)
                return old(self, p, ...)
            end

            ENT.RareloadOldSetPosWrapped = true
        end
    end

    -- Try early and late to win over other wrappers
    timer.Simple(0, installWrapper)
    hook.Add("InitPostEntity", "RARELOAD_Compat_SetPos", installWrapper)
    timer.Simple(1, installWrapper)
    timer.Simple(2, installWrapper)
end
