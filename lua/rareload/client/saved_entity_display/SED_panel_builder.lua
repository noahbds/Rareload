-- SED panel data builder entry point.

if SED then
    SED.EntityPanelCache = {}
    SED.NPCPanelCache = {}
end

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

include("rareload/client/saved_entity_display/SED_panel_builder_utils.lua")
include("rareload/client/saved_entity_display/SED_panel_builder_collectors.lua")

local PB = SED and SED.PanelBuilder
if not PB then
    ErrorNoHalt("[Rareload] Missing panel builder module in SED_panel_builder.lua\n")
    return
end

if not PB.populateCategories then
    ErrorNoHalt("[Rareload] Missing PB.populateCategories in SED_panel_builder.lua\n")
    return
end

function SED.BuildPanelData(saved, ent, isNPC)
    if not saved then return nil end

    SED.EntityPanelCache = SED.EntityPanelCache or {}
    SED.NPCPanelCache = SED.NPCPanelCache or {}

    local panelCache = isNPC and SED.NPCPanelCache or SED.EntityPanelCache
    local fallbackClass = PB.firstValue(saved, "class", "Class", "ClassName", "NPCName", "npcName") or "unknown"
    local fallbackSpawnTime = PB.firstValue(saved, "spawnTime", "savedAt", "SavedAt") or 0
    local id = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID or
        (fallbackClass .. "#" .. tostring(fallbackSpawnTime))
    local now = CurTime()
    local entry = panelCache[id]

    if entry and entry.expires > now then
        if IsValid(ent) and entry.data then
            local liveData = entry.data.position
            if liveData then
                local pos = ent:GetPos()
                local ang = ent:GetAngles()
                local vel = ent:GetVelocity()
                local maxHP = PB.firstValue(saved, "MaxHealth", "maxHealth", "StartHealth") or 0

                for _, line in ipairs(liveData) do
                    if line[1] == "Live Pos" then
                        line[2] = string.format("%.0f %.0f %.0f", pos.x, pos.y, pos.z)
                    elseif line[1] == "Live Ang" then
                        line[2] = string.format("%.0f %.0f %.0f", ang.p, ang.y, ang.r)
                    elseif line[1] == "Live Vel" then
                        line[2] = string.format("%.0f %.0f %.0f", vel.x, vel.y, vel.z)
                    elseif line[1] == "Live HP" and ent.Health then
                        line[2] = maxHP > 0 and (ent:Health() .. " / " .. maxHP) or tostring(ent:Health())
                    end
                end
            end
        end
        return entry
    end

    local cats

    -- NEW: If it's a phantom, directly use its built data instead of re-parsing
    if saved and saved._isPhantom and saved._phantomData then
        cats = saved._phantomData
    else
        cats = PB.newCategories()

        local addOrder = 0
        local seenByCategory = {}

        local function add(cat, label, value, col, opts)
            if value == nil or value == "" or not cats[cat] then return end

            local textValue = tostring(value)
            local rowColor = PB.resolveTextColor(col)
            seenByCategory[cat] = seenByCategory[cat] or {}

            local dedupeKey = tostring(label) .. "\31" .. textValue
            if seenByCategory[cat][dedupeKey] then return end
            seenByCategory[cat][dedupeKey] = true

            addOrder = addOrder + 1
            table.insert(cats[cat], { label, textValue, rowColor, opts, addOrder })
        end

        PB.populateCategories({
            saved = saved,
            ent = ent,
            isNPC = isNPC,
            cats = cats,
            add = add
        })
    end

    local function clampCategory(catId)
        local list = cats[catId]
        if not list then return end
        local maxLines = 200
        if #list > maxLines then
            local extra = #list - maxLines
            while #list > maxLines do table.remove(list) end
            list[#list + 1] = { "+more", ("%d more..."):format(extra), PB.resolveTextColor(nil) }
        end
    end

    for catId, list in pairs(cats) do
        PB.sortCategoryLines(list, PB.CATEGORY_LABEL_ORDER[catId])
        clampCategory(catId)
    end

    local categoryCounts = {}
    for catId, list in pairs(cats) do
        categoryCounts[catId] = #list
    end

    local oldEntry = panelCache[id]
    local oldActiveCat = (oldEntry and oldEntry.activeCat) or "basic"
    local oldAnimTabY = oldEntry and oldEntry.animTabY
    local oldSidebarScroll = oldEntry and oldEntry.sidebarScroll
    local oldCurWidth = oldEntry and oldEntry.curWidth
    local oldCurHeight = oldEntry and oldEntry.curHeight
    local oldMaxLabelWidths = oldEntry and oldEntry.maxLabelWidths
    local oldLod = oldEntry and oldEntry.lod
    local oldWrap = oldEntry and oldEntry._wrap
    local oldWidths = (oldEntry and oldEntry.widths) or {}

    entry = {
        data = cats,
        counts = categoryCounts,
        expires = now + SED.INFO_CACHE_LIFETIME * 2,
        activeCat = oldActiveCat,
        animTabY = oldAnimTabY,
        sidebarScroll = oldSidebarScroll,
        curWidth = oldCurWidth,
        curHeight = oldCurHeight,
        maxLabelWidths = oldMaxLabelWidths,
        lod = oldLod,
        _wrap = oldWrap,
        widths = oldWidths
    }
    panelCache[id] = entry
    return entry
end
