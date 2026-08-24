#!/bin/bash
# Install claude-code-statusline into ~/.claude.
#
# Two entry points, one installer:
#   curl -fsSL .../install.sh | bash     # end users: fetch from GitHub
#   make install                        # this checkout: STATUSLINE_SRC=$PWD
#
# Env:
#   STATUSLINE_SRC     install from this directory instead of downloading
#   CLAUDE_CONFIG_DIR  target config dir (default ~/.claude)
#   STATUSLINE_SKILL   0 to skip the usage-insight skill
#   BRANCH             branch to download from (default main)
set -eu

REPO="thevibeworks/claude-code-statusline"
BRANCH="${BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
SRC="${STATUSLINE_SRC:-}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CONFIG_DIR/statusline.sh"
SETTINGS="$CONFIG_DIR/settings.json"
SKILL_DIR="$CONFIG_DIR/skills/usage-insight"
WITH_SKILL="${STATUSLINE_SKILL:-1}"

RED='\033[31m'; GREEN='\033[32m'; DIM='\033[2m'; RESET='\033[0m'
info() { printf "${GREEN}>>>${RESET} %s\n" "$*"; }
warn() { printf "${RED}>>>${RESET} %s\n" "$*" >&2; }
die() { warn "$@"; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required: brew install jq / apt install jq"
[ -n "$SRC" ] || command -v curl >/dev/null 2>&1 || die "curl is required"

# One file lands at a time and it lands whole: the statusline runs on every
# render, and a half-written script is a broken prompt for whoever is mid-
# session. Write beside the target, then rename — atomic inside one dir.
fetch() { # fetch <repo-relative-path> <dest>
    local tmp="$2.tmp.$$"
    if [ -n "$SRC" ]; then
        [ -f "$SRC/$1" ] || die "not in $SRC: $1"
        cp -f "$SRC/$1" "$tmp"
    else
        curl -fsSL "${RAW}/$1" -o "$tmp"
    fi
    mv -f "$tmp" "$2"
}

mkdir -p "$CONFIG_DIR"

# A local install ships whatever is in the tree, including a half-finished
# edit. `bash -n` costs nothing and is the difference between a bad render
# and no statusline at all.
if [ -n "$SRC" ]; then
    bash -n "$SRC/statusline.sh" || die "$SRC/statusline.sh does not parse — not installing"
    info "Installing from $SRC"
else
    info "Downloading statusline.sh"
fi
fetch "statusline.sh" "$DEST"
chmod +x "$DEST"
info "Installed $DEST"

if [ "$WITH_SKILL" = 1 ]; then
    mkdir -p "$SKILL_DIR"
    fetch "skills/usage-insight/SKILL.md" "$SKILL_DIR/SKILL.md"
    info "Installed skill $SKILL_DIR/SKILL.md"
fi

# claude-watch.sh retired in v0.19.0 (superseded by the advisor line and
# claudex's claude.py --watch-usage). Clean up a copy left by old installs.
OLD_WATCH="$CONFIG_DIR/claude-watch.sh"
if [ -f "$OLD_WATCH" ]; then
    rm -f "$OLD_WATCH"
    info "Removed retired $OLD_WATCH"
fi

_tilde='~'
DEST_DISPLAY="${DEST/#$HOME/$_tilde}"

# Keep the flags. A configured statusline usually carries them — `--order`,
# `--debug`, a width — and an installer that rewrites the whole command
# silently reverts the user's setup every time they update.
ARGS=""
if [ -f "$SETTINGS" ]; then
    PREV=$(jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null || echo "")
    case "$PREV" in
        *statusline.sh*) ARGS="${PREV#*statusline.sh}" ;;
    esac
fi
STATUSLINE_CMD="bash ${DEST_DISPLAY}${ARGS}"

if [ ! -f "$SETTINGS" ]; then
    info "Creating $SETTINGS"
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
        info "statusLine already configured — updating command"
    else
        info "Adding statusLine to $SETTINGS"
    fi
    tmp="${SETTINGS}.tmp.$$"
    jq --arg cmd "$STATUSLINE_CMD" \
       '.statusLine = ((.statusLine // {})
          | .type = "command" | .command = $cmd | .padding = (.padding // 0))' \
       "$SETTINGS" > "$tmp" || die "could not update $SETTINGS (invalid JSON?)"
    mv -f "$tmp" "$SETTINGS"
fi
info "  statusLine.command = $STATUSLINE_CMD"

info "Done. Restart Claude Code or send a message to see the statusline."
printf "${DIM}  Docs: https://github.com/${REPO}${RESET}\n"
printf "${DIM}  Official: https://code.claude.com/docs/en/statusline${RESET}\n"
