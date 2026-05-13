#!/usr/bin/env bats
# Unit tests for install.sh
# Each test runs in an isolated temp directory with a mock curl.

setup() {
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    export TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    export CLAUDE_CONFIG_DIR="$TEST_HOME/.claude"
    mkdir -p "$CLAUDE_CONFIG_DIR"

    # Mock curl: copies the real statusline.sh instead of downloading
    mkdir -p "$TEST_HOME/bin"
    cat > "$TEST_HOME/bin/curl" << MOCKCURL
#!/bin/bash
for i in "\$@"; do
    if [ "\$prev" = "-o" ]; then
        cp "$SCRIPT_DIR/statusline.sh" "\$i"
        exit 0
    fi
    prev="\$i"
done
cat "$SCRIPT_DIR/statusline.sh"
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
