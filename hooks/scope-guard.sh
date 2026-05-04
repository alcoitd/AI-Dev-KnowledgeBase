#!/bin/bash
# PreToolUse scope guard — warns when tool targets path outside active scope

SCOPE_FILE="$(pwd)/.claude/scope.json"
[ ! -f "$SCOPE_FILE" ] && exit 0

SCOPE_ROOT=$(python3 -c "
import json
try:
    d = json.load(open('$SCOPE_FILE'))
    r = d.get('root', '')
    print(r if r not in ('all', '') else '')
except:
    print('')
" 2>/dev/null)

[ -z "$SCOPE_ROOT" ] && exit 0

# Read stdin to temp file for reliable parsing
TMPFILE=$(mktemp)
cat > "$TMPFILE"

TOOL_NAME=$(python3 -c "
import json
try:
    d = json.load(open('$TMPFILE'))
    print(d.get('tool_name', ''))
except:
    print('')
" 2>/dev/null)

check_path() {
    local p="$1"
    local label="$2"
    [ -z "$p" ] || [ "$p" = "None" ] || [ "$p" = "." ] && return
    # Always allow .claude/ and root config files
    [[ "$p" == *".claude"* ]] || [[ "$p" == *"CLAUDE.md"* ]] && return
    if [[ "$p" != *"$SCOPE_ROOT"* ]]; then
        SCOPE_NAME=$(python3 -c "import json; print(json.load(open('$SCOPE_FILE')).get('scope',''))" 2>/dev/null)
        echo "SCOPE[$SCOPE_NAME]: $label '$p' outside active scope '$SCOPE_ROOT'. Run /scope clear to search all dirs."
    fi
}

case "$TOOL_NAME" in
  Glob)
    PATH_ARG=$(python3 -c "
import json
try:
    d = json.load(open('$TMPFILE'))
    print(d.get('tool_input', {}).get('path') or '')
except:
    print('')
" 2>/dev/null)
    check_path "$PATH_ARG" "Glob path"
    ;;
  Grep)
    GREP_PATH=$(python3 -c "
import json
try:
    d = json.load(open('$TMPFILE'))
    print(d.get('tool_input', {}).get('path') or '')
except:
    print('')
" 2>/dev/null)
    check_path "$GREP_PATH" "Grep path"
    ;;
  Read)
    FILE_PATH=$(python3 -c "
import json
try:
    d = json.load(open('$TMPFILE'))
    print(d.get('tool_input', {}).get('file_path') or '')
except:
    print('')
" 2>/dev/null)
    check_path "$FILE_PATH" "Read path"
    ;;
esac

rm -f "$TMPFILE"
exit 0
