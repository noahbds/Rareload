-- Quick save and quick load keys (5.4 plan, D3). The keys are client convars the server can read; the
-- server handles the key press (sv_history.lua), so it works without the tool out. The binders are
-- in the tool panel. 0 = no key.

RARELOAD.Keys = {
    { convar = "cl_rareload_key_save", label = "menu.key_quicksave" },
    { convar = "cl_rareload_key_load", label = "menu.key_quickload" },
}

for _, k in ipairs(RARELOAD.Keys) do
    CreateClientConVar(k.convar, "0", true, true, "Rareload: key code for " .. k.convar .. " (0 = none)", 0,
        BUTTON_CODE_LAST)
end
