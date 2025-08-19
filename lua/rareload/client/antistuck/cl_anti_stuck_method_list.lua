-- Anti-Stuck Panel Method List Management
-- Handles the dynamic method list rendering and drag-and-drop functionality

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckDebug = RARELOAD.AntiStuckDebug or {}
RARELOAD.AntiStuckMethodList = RARELOAD.AntiStuckMethodList or {}

-- Get theme reference
local function getTheme()
    return RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.GetTheme() or {}
end

-- Method list refresh function
function RARELOAD.AntiStuckDebug.RefreshMethodList()
    -- Debounce and defer rebuild to avoid clearing during active layout
    if RARELOAD.AntiStuckDebug._refreshScheduled then return end
    RARELOAD.AntiStuckDebug._refreshScheduled = true

    timer.Simple(0, function()
        RARELOAD.AntiStuckDebug._refreshScheduled = nil

        -- Safety check for namespace
        if not RARELOAD or not RARELOAD.AntiStuckDebug then
            print("[RARELOAD] Error: AntiStuckDebug namespace not initialized")
            return
        end

        local parent = RARELOAD.AntiStuckDebug.methodContainer
        local searchBox = RARELOAD.AntiStuckDebug.searchBox

        if not parent or not IsValid(parent) then
            print("[RARELOAD] Error: Method container not valid")
            return
        end

        -- Clear once; don't Remove() each child to avoid transient NULL panels during layout
        parent:Clear()

        local methods = RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.GetMethods() or {}
        if #methods == 0 then
            print("[RARELOAD] Warning: No methods available")
            return
        end

        local search = searchBox and IsValid(searchBox) and searchBox:GetValue():lower() or ""

        -- Filter methods based on search
        local function matchesSearch(method)
            if search == "" then return true end
            local searchTerms = string.Split(search, " ")
            local content = (method.name .. " " .. (method.description or "")):lower()

            for _, term in ipairs(searchTerms) do
                if term ~= "" and not content:find(term, 1, true) then
                    return false
                end
            end
            return true
        end

        local visible = {}
        for i, method in ipairs(methods) do
            if matchesSearch(method) then
                table.insert(visible, { method = method, origIndex = i })
            end
        end

        -- Drag state for reordering
        local dragState = {
            dragging = nil,
            dragIndex = nil,
            dragOffsetY = 0,
            dropIndicator = nil,
            startTime = 0
        }

        local panels = {}

        -- Create method panels
        for visIndex, entry in ipairs(visible) do
            local method, i = entry.method, entry.origIndex

            if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateMethodPanel then
                local pnl = RARELOAD.AntiStuckComponents.CreateMethodPanel(parent, method, i, dragState)
                panels[visIndex] = pnl

                -- Add drag and drop functionality
                RARELOAD.AntiStuckMethodList.SetupDragDrop(pnl, visIndex, visible, dragState, panels, parent)
            end
        end

        -- Show "no results" message if search yielded nothing
        if #visible == 0 and search ~= "" then
            local THEME = getTheme()
            local noResults = vgui.Create("DLabel", parent)
            noResults:SetText("No methods match your search")
            noResults:SetFont("RareloadText")
            noResults:SetTextColor(THEME.textSecondary)
            noResults:SetContentAlignment(5)
            noResults:SetTall(60)
            noResults:Dock(TOP)
            noResults:DockMargin(20, 20, 20, 0)
        end
    end)
end

-- Setup drag and drop functionality for method panels
function RARELOAD.AntiStuckMethodList.SetupDragDrop(pnl, visIndex, visible, dragState, panels, parent)
    -- Mouse press handler for drag initiation
    pnl.OnMousePressed = function(self, mc)
        if mc == MOUSE_LEFT then
            local mx, my = self:CursorPos()
            if mx >= self:GetWide() - 45 and mx <= self:GetWide() - 10 and my >= 20 and my <= 65 then
                dragState.dragging = self
                dragState.dragIndex = visIndex
                dragState.dragOffsetY = my
                dragState.startTime = SysTime()
                self:MouseCapture(true)
                self:SetZPos(1000)
                surface.PlaySound("ui/buttonclickrelease.wav")
            end
        end
    end

    -- Mouse release handler for drop
    pnl.OnMouseReleased = function(self, mc)
        if dragState.dragging == self and mc == MOUSE_LEFT then
            self:MouseCapture(false)
            self:SetZPos(0)

            local mouseY = gui.MouseY()
            local parentX, parentY = parent:LocalToScreen(0, 0)
            local scrollOffset = parent:GetVBar():GetScroll()
            local relY = mouseY - parentY + scrollOffset
            local itemH = self:GetTall() + 8
            local newIndex = math.Clamp(math.floor((relY - dragState.dragOffsetY + itemH / 2) / itemH) + 1, 1, #visible)
            if newIndex ~= dragState.dragIndex and SysTime() - dragState.startTime > 0.1 then
                -- Reorder the methods
                if RARELOAD.AntiStuckData then
                    local methods = RARELOAD.AntiStuckData.GetMethods()
                    local globalOld = visible[dragState.dragIndex].origIndex
                    local globalNew = visible[newIndex].origIndex

                    local movedMethod = table.remove(methods, globalOld)
                    -- Ensure the moved method retains its enabled state
                    if movedMethod and movedMethod.enabled == nil then
                        movedMethod.enabled = true
                    end

                    if movedMethod then
                        table.insert(methods, globalNew, movedMethod)

                        -- Normalize priorities to 10,20,... based on new order
                        for idx, m in ipairs(methods) do
                            m.priority = idx * 10
                        end

                        -- Save the reordered methods to the profile
                        RARELOAD.AntiStuckData.SetMethods(methods)
                        local saveSuccess = RARELOAD.AntiStuckData.SaveMethods()

                        if saveSuccess then
                            RARELOAD.AntiStuckDebug.RefreshMethodList()
                            surface.PlaySound("ui/buttonclickrelease.wav")
                        else
                            print("[RARELOAD] Error: Failed to save method reorder")
                        end
                    else
                        print("[RARELOAD] Error: Could not move method - method was nil")
                    end
                end
            end

            -- Clean up drag state
            dragState.dragging = nil
            dragState.dragIndex = nil
            dragState.dropIndicator = nil
            dragState.startTime = 0
        end
    end

    -- Think function for drag animation
    pnl.Think = function(self)
        if dragState.dragging == self then
            local x, y = parent:ScreenToLocal(gui.MouseX(), gui.MouseY())
            local scrollOffset = parent:GetVBar():GetScroll()
            self:SetPos(20, math.max(0, y - dragState.dragOffsetY + scrollOffset))

            local itemH = self:GetTall() + 8
            local relY = y - dragState.dragOffsetY + itemH / 2 + scrollOffset
            dragState.dropIndicator = math.Clamp(math.floor(relY / itemH) + 1, 1, #visible)

            -- Animate other panels
            for k, p in ipairs(panels) do
                if p ~= self then
                    local targetY = (k - 1) * itemH
                    if dragState.dropIndicator and k >= dragState.dropIndicator and dragState.dragIndex and dragState.dropIndicator <= dragState.dragIndex then
                        targetY = targetY + itemH
                    elseif dragState.dropIndicator and k > dragState.dropIndicator and dragState.dragIndex and dragState.dropIndicator > dragState.dragIndex then
                        -- No additional offset needed
                    end
                    p:MoveTo(20, targetY, 0.15, 0, 1)
                end
            end
        end
    end
end
