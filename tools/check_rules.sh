#!/usr/bin/env bash
# Enforces the platform and architecture rules from REWRITE_PLAN.md §26 and §27.2.
# Usage: tools/check_rules.sh   (run from the repository root; exits non-zero on any violation)

set -u
cd "$(dirname "$0")/.." || exit 2

LUA_DIR="lua"
fail=0

report() {
    echo "✗ $1"
    echo "$2" | sed 's/^/    /'
    fail=1
}

# check <description> <extended-regex> [path-to-exclude ...]
check() {
    local desc="$1" pattern="$2"
    shift 2
    local out
    out=$(grep -rnE "$pattern" "$LUA_DIR" --include='*.lua' 2>/dev/null)
    for skip in "$@"; do
        out=$(echo "$out" | grep -v "^$skip:" || true)
    done
    out=$(echo "$out" | sed '/^$/d')
    if [ -n "$out" ]; then report "$desc" "$out"; fi
}

# Single owners (§10.1)
check "net.Start/net.Receive outside sh_net.lua (§10.1)" '\bnet\.(Start|Receive)\(' "$LUA_DIR/rareload/sh_net.lua"
check "file writes outside sv_storage.lua (§10.1)" '\bfile\.(Write|Read|Delete|Rename|Append|Open)\(' "$LUA_DIR/rareload/server/sv_storage.lua"

# Globals (§10.1): a function declared without a table or colon is a global
check "global function declaration (§10.1)" '^\s*function [A-Za-z_][A-Za-z0-9_]*\s*\('

# Platform facts (§5.2, §5.3)
check "ents.GetAll/player.GetAll: use ents.Iterator/player.Iterator (G25)" '\b(ents|player)\.GetAll\('
check "RunString/CompileString (S5)" '\b(RunString|RunStringEx|CompileString)\('
check "ConCommand built from data (S5)" 'ConCommand\([^)]*\.\.'
check "list.Get: use list.GetEntry/HasEntry (G67)" '\blist\.Get\('
check "table.Copy in server code (G68)" '\btable\.Copy\('
check "Player:SelectWeapon: use CUserCmd:SelectWeapon (G56)" '[^d]:SelectWeapon\('
check "util.Decompress without maxSize (G4)" 'util\.Decompress\([^,)]*\)'

# Pipeline and modules never use timers (§15, §26)
out=$(grep -rnE '\btimer\.(Simple|Create)\(' "$LUA_DIR/rareload/server/sv_pipeline.lua" "$LUA_DIR/rareload/server/modules" --include='*.lua' 2>/dev/null)
[ -n "$out" ] && report "timer in pipeline/modules: use ctx:nextTick/ctx:waitFor (§15.1)" "$out"

# Our data files must be decoded with ignoreLimits (G1)
if [ -f "$LUA_DIR/rareload/server/sv_storage.lua" ]; then
    out=$(grep -nE 'JSONToTable\(' "$LUA_DIR/rareload/server/sv_storage.lua" | grep -vE 'JSONToTable\([^,]+,\s*true' || true)
    [ -n "$out" ] && report "sv_storage JSONToTable without ignoreLimits (G1)" "$out"
fi

# File names: lowercase only, no empty files (G44, G45)
out=$(find "$LUA_DIR" -type f -name '*.lua' | grep -E '[A-Z]' || true)
[ -n "$out" ] && report "uppercase in Lua file path (G45)" "$out"
out=$(find "$LUA_DIR" -type f -name '*.lua' -empty)
[ -n "$out" ] && report "empty Lua file (G44)" "$out"

# Translations (G74): valid GMod language folders, first line of each file empty
VALID_LANGS=" bg cs da de el en en-PT es-ES et fi fr he hr hu it ja ko lt nl no pl pt-BR pt-PT ru sk sv-SE th tr uk vi zh-CN zh-TW "
if [ -d resource/localization ]; then
    for dir in resource/localization/*/; do
        [ -d "$dir" ] || continue
        code=$(basename "$dir")
        case "$VALID_LANGS" in
            *" $code "*) ;;
            *) report "unknown GMod language folder (G74)" "$dir" ;;
        esac
    done
    for f in resource/localization/*/*.properties; do
        [ -f "$f" ] || continue
        if [ -n "$(head -n 1 "$f")" ]; then report ".properties first line must be empty (G74)" "$f"; fi
    done
fi

if [ "$fail" -eq 0 ]; then
    echo "✓ all rules pass"
fi
exit "$fail"
