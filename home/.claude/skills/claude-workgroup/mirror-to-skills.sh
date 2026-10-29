#!/bin/bash
# PostToolUse hook: mirror edits to tools/claude-workgroup/* into ~/.claude/skills/claude-workgroup/
# Reads tool JSON from stdin, extracts file path, and if it matches, cp-overwrites the skill file.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path','') or d.get('tool_response',{}).get('filePath',''))" 2>/dev/null)

[ -z "$FILE_PATH" ] && exit 0

# Only mirror files inside tools/claude-workgroup/
case "$FILE_PATH" in
    */tools/claude-workgroup/*)
        FILENAME=$(basename "$FILE_PATH")
        DEST="$HOME/.claude/skills/claude-workgroup/$FILENAME"
        if [ -f "$FILE_PATH" ]; then
            cp "$FILE_PATH" "$DEST" 2>/dev/null
            [ "${FILENAME##*.}" = "sh" ] && chmod +x "$DEST" 2>/dev/null
            # Re-establish hardlink so future list shows same inode
            ln -f "$FILE_PATH" "$DEST" 2>/dev/null
        fi
        ;;
esac

exit 0
