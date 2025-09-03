-- Remove old phantom interaction system
hook.Remove("GUIMousePressed", "PhantomPanelInteraction")
hook.Remove("Think", "PhantomKeyboardNavigation")
hook.Remove("StartCommand", "PhantomBlockMovement")
hook.Remove("PlayerBindPress", "PhantomBlockBindings")
hook.Remove("CalcView", "PhantomInteractionView")
hook.Remove("KeyPress", "PhantomInteractionToggle")

-- The phantom interaction is now handled by the new system in cl_phantom_info.lua
-- This matches the entity viewer system with Shift+E interaction
