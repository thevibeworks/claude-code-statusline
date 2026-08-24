#!/usr/bin/env bats
# Unit tests for install.sh
# Each test runs in an isolated temp directory with a mock curl.

setup() {
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    export TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export CLAUDE_CONFIG_DIR="$TEST_HOME/.claude"
    mkdir -p "$CLAUDE_CONFIG_DIR"

    # Mock curl: serves the repo instead of GitHub. It resolves the URL to a
    # repo path so a request for the skill does not silently hand back
    # statusline.sh — a mock that answers everything with the same file cannot
    # catch an installer that fetches the wrong thing.
    mkdir -p "$TEST_HOME/bin"
    cat > "$TEST_HOME/bin/curl" << MOCKCURL
#!/bin/bash
url=""; out=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -o) out="\$2"; shift 2 ;;
        -*) shift ;;
        *) url="\$1"; shift ;;
    esac
done
path="\${url#*/main/}"
[ -f "$SCRIPT_DIR/\$path" ] || exit 22
if [ -n "\$out" ]; then cp "$SCRIPT_DIR/\$path" "\$out"; else cat "$SCRIPT_DIR/\$path"; fi
MOCKCURL
    chmod +x "$TEST_HOME/bin/curl"
    export PATH="$TEST_HOME/bin:$PATH"
}

teardown() {
    rm -rf "$TEST_HOME"
}

run_install() {
    bash "$SCRIPT_DIR/install.sh" 2>&1
}

# --- file creation ---

@test "install: creates statusline.sh" {
    run_install
    [ -f "$CLAUDE_CONFIG_DIR/statusline.sh" ]
}

@test "install: statusline.sh is executable" {
    run_install
    [ -x "$CLAUDE_CONFIG_DIR/statusline.sh" ]
}

# --- settings.json creation ---

@test "install: creates settings.json when missing" {
    run_install
    [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
}

@test "install: settings.json has statusLine.type = command" {
    run_install
    result=$(jq -r '.statusLine.type' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$result" = "command" ]
}

@test "install: settings.json command references statusline.sh" {
    run_install
    result=$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")
    [[ "$result" == *"statusline.sh"* ]]
}

@test "install: settings.json has padding field" {
    run_install
    result=$(jq -r '.statusLine.padding' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$result" = "0" ]
}

# --- merge into existing settings ---

@test "install: preserves existing settings fields" {
    cat > "$CLAUDE_CONFIG_DIR/settings.json" << 'JSON'
{
  "model": "opus",
  "permissions": {"allow": ["Bash(npm *)"]}
}
JSON
    run_install
    [ "$(jq -r '.model' "$CLAUDE_CONFIG_DIR/settings.json")" = "opus" ]
    jq -e '.permissions.allow' "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null
    jq -e '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null
}

@test "install: adds statusLine to settings without clobbering" {
    cat > "$CLAUDE_CONFIG_DIR/settings.json" << 'JSON'
{
  "model": "sonnet",
  "env": {"MY_VAR": "value"}
}
JSON
    run_install
    [ "$(jq -r '.model' "$CLAUDE_CONFIG_DIR/settings.json")" = "sonnet" ]
    [ "$(jq -r '.env.MY_VAR' "$CLAUDE_CONFIG_DIR/settings.json")" = "value" ]
    [ "$(jq -r '.statusLine.type' "$CLAUDE_CONFIG_DIR/settings.json")" = "command" ]
}

# --- update existing statusLine ---

@test "install: updates existing statusLine command" {
    cat > "$CLAUDE_CONFIG_DIR/settings.json" << 'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "echo old-statusline",
    "padding": 2
  }
}
JSON
    run_install
    result=$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")
    [[ "$result" == *"statusline.sh"* ]]
    [[ "$result" != *"old-statusline"* ]]
}

@test "install: preserves existing padding when updating" {
    cat > "$CLAUDE_CONFIG_DIR/settings.json" << 'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "echo old",
    "padding": 3
  }
}
JSON
    run_install
    [ "$(jq -r '.statusLine.padding' "$CLAUDE_CONFIG_DIR/settings.json")" = "3" ]
}

# --- output ---

@test "install: output mentions Done" {
    result=$(run_install)
    [[ "$result" == *"Done"* ]]
}

@test "install: output mentions install path" {
    result=$(run_install)
    [[ "$result" == *"statusline.sh"* ]]
}

# --- the flags are the user's, not the installer's ---

@test "install: keeps the flags already on the statusLine command" {
    # A configured statusline carries --order/--debug/a width. An installer
    # that rewrites the whole command reverts the user's setup on every
    # update, silently, and they find out by looking at a row that changed.
    cat > "$CLAUDE_CONFIG_DIR/settings.json" << 'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh --debug --order activity,cost,model,quota,user",
    "padding": 0
  }
}
JSON
    run_install
    result=$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")
    [[ "$result" == *"statusline.sh --debug --order activity,cost,model,quota,user" ]]
}

@test "install: a command that is not ours keeps no flags" {
    cat > "$CLAUDE_CONFIG_DIR/settings.json" << 'JSON'
{"statusLine": {"type": "command", "command": "echo hi --not-our-flag"}}
JSON
    run_install
    result=$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")
    [[ "$result" != *"--not-our-flag"* ]]
}

# --- the skill ships with the script ---

@test "install: installs the usage-insight skill" {
    run_install
    [ -f "$CLAUDE_CONFIG_DIR/skills/usage-insight/SKILL.md" ]
    grep -q 'name: usage-insight' "$CLAUDE_CONFIG_DIR/skills/usage-insight/SKILL.md"
}

@test "install: STATUSLINE_SKILL=0 skips the skill" {
    STATUSLINE_SKILL=0 run_install
    [ -f "$CLAUDE_CONFIG_DIR/statusline.sh" ]
    [ ! -e "$CLAUDE_CONFIG_DIR/skills/usage-insight" ]
}

# --- local source (what `make install` runs) ---

@test "install: STATUSLINE_SRC installs from a checkout, no network" {
    # the mock curl is removed: a local install that reaches the network at
    # all is a local install in name only
    rm -f "$TEST_HOME/bin/curl"
    STATUSLINE_SRC="$SCRIPT_DIR" run_install
    cmp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_CONFIG_DIR/statusline.sh"
    cmp "$SCRIPT_DIR/skills/usage-insight/SKILL.md" "$CLAUDE_CONFIG_DIR/skills/usage-insight/SKILL.md"
    [ -x "$CLAUDE_CONFIG_DIR/statusline.sh" ]
}

@test "install: a source tree that does not parse is not installed" {
    # `make install` ships whatever is in the tree, half-finished edit and
    # all. A broken statusline is not a worse render, it is no statusline.
    src=$(mktemp -d)
    mkdir -p "$src/skills/usage-insight"
    printf 'if [\n' > "$src/statusline.sh"
    : > "$src/skills/usage-insight/SKILL.md"
    run env STATUSLINE_SRC="$src" bash "$SCRIPT_DIR/install.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not parse"* ]]
    [ ! -e "$CLAUDE_CONFIG_DIR/statusline.sh" ]
    rm -rf "$src"
}
