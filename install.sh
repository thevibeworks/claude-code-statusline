#!/bin/bash
set -eu

REPO="thevibeworks/claude-code-statusline"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

RED='\033[31m'; GREEN='\033[32m'; DIM='\033[2m'; RESET='\033[0m'
info() { printf "${GREEN}>>>${RESET} %s\n" "$*"; }
warn() { printf "${RED}>>>${RESET} %s\n" "$*" >&2; }
die() { warn "$@"; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required: brew install jq / apt install jq"
command -v curl >/dev/null 2>&1 || die "curl is required"

info "Downloading statusline.sh"
curl -fsSL "${RAW}/statusline.sh" -o "$DEST"
chmod +x "$DEST"
info "Installed to $DEST"

# claude-watch.sh retired in v0.19.0 (superseded by the advisor line and
# claudex's claude.py --watch-usage). Clean up a copy left by old installs.
OLD_WATCH="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claude-watch.sh"
if [ -f "$OLD_WATCH" ]; then
    rm -f "$OLD_WATCH"
    info "Removed retired $OLD_WATCH"
fi

_tilde='~'
STATUSLINE_CMD="bash ${DEST/#$HOME/$_tilde}"

if [ ! -f "$SETTINGS" ]; then
    info "Creating $SETTINGS"
    mkdir -p "$(dirname "$SETTINGS")"
    cat > "$SETTINGS" << SETTINGSEOF
{
  "statusLine": {
    "type": "command",
    "command": "$STATUSLINE_CMD",
    "padding": 0
  }
}
SETTINGSEOF
else
    if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
        info "statusLine already configured in $SETTINGS — updating command"
        tmp="${SETTINGS}.tmp.$$"
        jq --arg cmd "$STATUSLINE_CMD" '.statusLine.type = "command" | .statusLine.command = $cmd | .statusLine.padding = (.statusLine.padding // 0)' "$SETTINGS" > "$tmp"
        mv -f "$tmp" "$SETTINGS"
    else
        info "Adding statusLine to $SETTINGS"
        tmp="${SETTINGS}.tmp.$$"
        jq --arg cmd "$STATUSLINE_CMD" '. + {"statusLine": {"type": "command", "command": $cmd, "padding": 0}}' "$SETTINGS" > "$tmp"
        mv -f "$tmp" "$SETTINGS"
    fi
fi

info "Done. Restart Claude Code or send a message to see the statusline."
printf "${DIM}  Docs: https://github.com/${REPO}${RESET}\n"
printf "${DIM}  Official: https://code.claude.com/docs/en/statusline${RESET}\n"
