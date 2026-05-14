#!/usr/bin/env bats
# Unit tests for statusline.sh functions

setup() {
    load helpers.bash
}

# --- abbreviate_model_id ---

@test "abbreviate_model_id: opus full ID" {
    result=$(abbreviate_model_id "claude-opus-4-6")
    [ "$result" = "opus4.6" ]
}

@test "abbreviate_model_id: opus 4.7" {
    result=$(abbreviate_model_id "claude-opus-4-7")
    [ "$result" = "opus4.7" ]
}

@test "abbreviate_model_id: sonnet full ID" {
    result=$(abbreviate_model_id "claude-sonnet-4-6")
    [ "$result" = "sonnet4.6" ]
}

@test "abbreviate_model_id: haiku with date suffix" {
    result=$(abbreviate_model_id "claude-haiku-4-5-20251001")
    [ "$result" = "haiku4.5" ]
}

@test "abbreviate_model_id: unknown model passes through" {
    result=$(abbreviate_model_id "gpt-4o-mini")
    [ "$result" = "gpt-4o-mini" ]
}

@test "abbreviate_model_id: short alias passes through" {
    result=$(abbreviate_model_id "opus")
    [ "$result" = "opus" ]
}

# --- format_reset_clock ---

@test "format_reset_clock: converts UTC to local HH:MM" {
    ts=$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_clock "$ts")
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_reset_clock: empty input returns empty" {
    result=$(format_reset_clock "")
    [ -z "$result" ]
}

@test "format_reset_clock: null input returns empty" {
    result=$(format_reset_clock "null")
    [ -z "$result" ]
}

# --- format_reset_relative ---

@test "format_reset_relative: days and hours" {
    ts=$(date -u -d '+2 days 5 hours' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_relative "$ts")
    [ "$result" = "2d5h" ]
}

@test "format_reset_relative: hours and minutes" {
    ts=$(date -u -d '+3 hours 30 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_relative "$ts")
    [ "$result" = "3h30m" ]
}

@test "format_reset_relative: minutes only" {
    ts=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_relative "$ts")
    [ "$result" = "45m" ]
}

@test "format_reset_relative: exact days" {
    ts=$(date -u -d '+3 days 1 minute' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_relative "$ts")
    [ "$result" = "3d" ]
}

@test "format_reset_relative: past timestamp returns now" {
    ts=$(date -u -d '-1 hour' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_relative "$ts")
    [ "$result" = "now" ]
}

@test "format_reset_relative: empty returns empty" {
    result=$(format_reset_relative "")
    [ -z "$result" ]
}

# --- OAuth token refresh ---

@test "oauth_token_expired: uses five minute buffer for millisecond timestamps" {
    STATUSLINE_TEST_NOW_MS=1778728000000
    export STATUSLINE_TEST_NOW_MS

    run oauth_token_expired 1778728299000
    [ "$status" -eq 0 ]

    run oauth_token_expired 1778728301000
    [ "$status" -eq 1 ]

    unset STATUSLINE_TEST_NOW_MS
}

@test "refresh_oauth_credentials_file: refreshes expired token and updates credentials" {
    tmpdir=$(mktemp -d)
    cred_file="$tmpdir/.credentials.json"
    cat >"$cred_file" <<'JSON'
{"claudeAiOauth":{"accessToken":"old-access","refreshToken":"old-refresh","expiresAt":1000,"scopes":["user:profile","user:inference"],"subscriptionType":"max","rateLimitTier":"tier"}}
JSON
    chmod 600 "$cred_file"

    curl() {
        printf '%s\n200\n' '{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"scope":"user:profile user:inference"}'
    }

    STATUSLINE_TEST_NOW_MS=1000000
    CLAUDE_CACHE_DIR="$tmpdir"
    export STATUSLINE_TEST_NOW_MS
    export CLAUDE_CACHE_DIR

    result=$(refresh_oauth_credentials_file "$cred_file")

    [ "$result" = "new-access" ]
    [ "$(jq -r '.claudeAiOauth.accessToken' "$cred_file")" = "new-access" ]
    [ "$(jq -r '.claudeAiOauth.refreshToken' "$cred_file")" = "new-refresh" ]
    [ "$(jq -r '.claudeAiOauth.expiresAt' "$cred_file")" = "4600000" ]
    [ "$(jq -r '.claudeAiOauth.scopes | join(" ")' "$cred_file")" = "user:profile user:inference" ]
    [ "$(stat -c '%a' "$cred_file")" = "600" ]

    unset STATUSLINE_TEST_NOW_MS
    unset CLAUDE_CACHE_DIR
    rm -rf "$tmpdir"
}

# --- get_usage_color ---

@test "get_usage_color: green below 80" {
    result=$(get_usage_color 50)
    [ "$result" = "$GREEN" ]
}

@test "get_usage_color: yellow at 80" {
    result=$(get_usage_color 80)
    [ "$result" = "$YELLOW" ]
}

@test "get_usage_color: red at 90" {
    result=$(get_usage_color 90)
    [ "$result" = "$RED" ]
}

@test "get_usage_color: red at 100" {
    result=$(get_usage_color 100)
    [ "$result" = "$RED" ]
}

# --- get_seven_day_color ---

@test "get_seven_day_color: green below 70" {
    result=$(get_seven_day_color 50)
    [ "$result" = "$GREEN" ]
}

@test "get_seven_day_color: yellow at 70" {
    result=$(get_seven_day_color 70)
    [ "$result" = "$YELLOW" ]
}

@test "get_seven_day_color: red at 85" {
    result=$(get_seven_day_color 85)
    [ "$result" = "$RED" ]
}

# --- get_adaptive_ttl ---

@test "get_adaptive_ttl: low usage = 5 min" {
    result=$(get_adaptive_ttl 10)
    [ "$result" = "300" ]
}

@test "get_adaptive_ttl: medium usage = 2 min" {
    result=$(get_adaptive_ttl 30)
    [ "$result" = "120" ]
}

@test "get_adaptive_ttl: high usage = 1 min" {
    result=$(get_adaptive_ttl 60)
    [ "$result" = "60" ]
}

@test "get_adaptive_ttl: critical usage = 30 sec" {
    result=$(get_adaptive_ttl 85)
    [ "$result" = "30" ]
}

@test "get_adaptive_ttl: zero = 5 min" {
    result=$(get_adaptive_ttl 0)
    [ "$result" = "300" ]
}

# --- render_bar ---

@test "render_bar: 50% fills half" {
    result=$(render_bar 50 6 "#" ".")
    [ "$result" = "###..." ]
}

@test "render_bar: 0% shows empty" {
    result=$(render_bar 0 6 "#" ".")
    [ "$result" = "......" ]
}

@test "render_bar: 100% fills all" {
    result=$(render_bar 100 6 "#" ".")
    [ "$result" = "######" ]
}

@test "render_bar: 1% shows minimum 1 filled" {
    result=$(render_bar 1 6 "#" ".")
    [ "$result" = "#....." ]
}

# --- extra usage ---

@test "format_money_minor: USD cents use compact dollars" {
    result=$(format_money_minor 1629 USD)
    [ "$result" = '$16.29' ]

    result=$(format_money_minor 20000 USD whole)
    [ "$result" = '$200' ]

    result=$(format_money_minor 466 usd)
    [ "$result" = '$4.66' ]
}

@test "build_extra_usage_display: shows spend limit percent and balance" {
    usage='{"extra_usage":{"is_enabled":true,"monthly_limit":20000,"used_credits":1629,"utilization":8.145,"currency":"USD"}}'
    balance='{"amount":466,"currency":"USD","auto_reload_settings":{"enabled":false}}'

    result=$(build_extra_usage_display "$usage" "$balance")
    plain=$(strip_ansi "$result")

    [ "$plain" = 'ex[$16.29/$200 8% bal$4.66]' ]
}

@test "build_extra_usage_display: marks auto reload when enabled" {
    usage='{"extra_usage":{"is_enabled":true,"monthly_limit":20000,"used_credits":1629,"utilization":8.145,"currency":"USD"}}'
    balance='{"amount":466,"currency":"USD","auto_reload_settings":{"enabled":true}}'

    result=$(build_extra_usage_display "$usage" "$balance")
    plain=$(strip_ansi "$result")

    [ "$plain" = 'ex[$16.29/$200 8% bal$4.66 ar]' ]
}

@test "build_extra_usage_display: shows unlimited extra usage" {
    usage='{"extra_usage":{"is_enabled":true,"monthly_limit":null,"used_credits":1629,"utilization":null,"currency":"USD"}}'
    balance='{"amount":466,"currency":"USD","auto_reload_settings":{"enabled":false}}'

    result=$(build_extra_usage_display "$usage" "$balance")
    plain=$(strip_ansi "$result")

    [ "$plain" = 'ex[unlimited bal$4.66]' ]
}

@test "build_extra_usage_display: shows disabled extra usage" {
    usage='{"extra_usage":{"is_enabled":false,"monthly_limit":20000,"used_credits":0,"utilization":0,"currency":"USD"}}'

    result=$(build_extra_usage_display "$usage" "")
    plain=$(strip_ansi "$result")

    [ "$plain" = 'ex[off]' ]
}

@test "build_extra_usage_display: hides when usage payload has no extra usage object" {
    usage='{"five_hour":{"utilization":20}}'

    result=$(build_extra_usage_display "$usage" "")

    [ -z "$result" ]
}

# --- get_context_limit ---

@test "get_context_limit: 1m model" {
    result=$(get_context_limit "claude-opus-4-6[1m]")
    [ "$result" = "1000000" ]
}

@test "get_context_limit: standard model" {
    result=$(get_context_limit "claude-sonnet-4-6")
    [ "$result" = "200000" ]
}

@test "get_context_limit: empty string" {
    result=$(get_context_limit "")
    [ "$result" = "200000" ]
}

# --- integration: full script with --test ---

@test "integration: --test produces output" {
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":1.23,"total_lines_added":10,"total_lines_removed":2,"total_api_duration_ms":60000},"version":"2.1.139"}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    [ -n "$result" ]
}

@test "integration: --test shows model" {
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.139"}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.6[1m]"* ]]
}

@test "integration: --test shows cost" {
    result=$(echo '{"model":{"id":"claude-sonnet-4-6","display_name":"Sonnet"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":5.67,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":120000},"version":"2.1.139"}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *'$5.67'* ]]
}

@test "integration: --test shows directory basename" {
    result=$(echo '{"model":{"id":"claude-sonnet-4-6","display_name":"Sonnet"},"cwd":"/home/user/my-project","workspace":{"current_dir":"/home/user/my-project"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.139"}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"my-project"* ]]
}
