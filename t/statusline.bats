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
    [[ "$result" =~ ^4[45]m$ ]]
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

@test "format_reset_relative: unix epoch produces relative time" {
    epoch=$(date -d '+2 hours 30 minutes' +%s)
    result=$(format_reset_relative "$epoch")
    [ "$result" = "2h30m" ]
}

@test "format_reset_relative: empty returns empty" {
    result=$(format_reset_relative "")
    [ -z "$result" ]
}

# --- format_duration ---

@test "format_duration: zero returns 0m" {
    result=$(format_duration 0)
    [ "$result" = "0m" ]
}

@test "format_duration: sub-minute rounds up to 1m" {
    result=$(format_duration 30000)
    [ "$result" = "1m" ]
}

@test "format_duration: exact minutes" {
    result=$(format_duration 120000)
    [ "$result" = "2m" ]
}

@test "format_duration: 59 minutes stays as minutes" {
    result=$(format_duration 3540000)
    [ "$result" = "59m" ]
}

@test "format_duration: 60 minutes becomes 1h" {
    result=$(format_duration 3600000)
    [ "$result" = "1h" ]
}

@test "format_duration: 90 minutes becomes 1h30m" {
    result=$(format_duration 5400000)
    [ "$result" = "1h30m" ]
}

@test "format_duration: 3 hours exact" {
    result=$(format_duration 10800000)
    [ "$result" = "3h" ]
}

# --- build_usage_display integer percentages ---

@test "build_usage_display: rounds float percentages to integers" {
    usage='{"five_hour":{"utilization":12.345,"resets_at":""},"seven_day":{"utilization":67.8,"resets_at":""}}'
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[12%]"* ]]
    [[ "$plain" == *"7d[68%]"* ]]
}

@test "build_usage_display: zero utilization is hidden" {
    usage='{"five_hour":{"utilization":0},"seven_day":{"utilization":0}}'
    result=$(build_usage_display "$usage" "")
    [ -z "$result" ]
}

@test "build_usage_display: 5h at 87% includes relative reset suffix" {
    reset_time=$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":87,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[87%\~ ]]
}

@test "build_usage_display: 7d at 75% includes relative reset suffix" {
    reset_time=$(date -u -d '+2 days 5 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_time\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 7d\[75%\~ ]]
}

@test "build_usage_display: MAX tier shows opus model quota" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"seven_day_opus":{"utilization":20},"seven_day_sonnet":{"utilization":15}}'
    result=$(build_usage_display "$usage" "MAX")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"op[20%]"* ]]
    [[ "$plain" != *"sn["* ]]
}

@test "build_usage_display: non-MAX tier shows sonnet model quota" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"seven_day_opus":{"utilization":20},"seven_day_sonnet":{"utilization":15}}'
    result=$(build_usage_display "$usage" "PRO")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"sn[15%]"* ]]
    [[ "$plain" != *"op["* ]]
}

@test "build_usage_display: below threshold with distant reset hides suffix" {
    reset_time=$(date -u -d '+4 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_time_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":50,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":40,\"resets_at\":\"$reset_time_7d\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[50%]"* ]]
    [[ "$plain" == *"7d[40%]"* ]]
    [[ "$plain" != *"~"* ]]
}

# --- should_show_extra ---

@test "should_show_extra: always mode shows regardless of quota" {
    run should_show_extra "always" 10 5
    [ "$status" -eq 0 ]
}

@test "should_show_extra: off mode hides regardless of quota" {
    run should_show_extra "off" 95 90
    [ "$status" -eq 1 ]
}

@test "should_show_extra: on-limit shows when 5h >= 80" {
    run should_show_extra "on-limit" 85 50
    [ "$status" -eq 0 ]
}

@test "should_show_extra: on-limit shows when 7d >= 70" {
    run should_show_extra "on-limit" 10 75
    [ "$status" -eq 0 ]
}

@test "should_show_extra: on-limit hides when both under threshold" {
    run should_show_extra "on-limit" 50 40
    [ "$status" -eq 1 ]
}

# --- build_user_info ---

@test "build_user_info: MAX with name shows tier and truncated name" {
    tmpdir=$(mktemp -d)
    CLAUDE_CACHE_DIR="$tmpdir"
    echo '{"account":{"display_name":"feast.tablet"}}' > "$tmpdir/profile.cache"
    result=$(build_user_info "MAX")
    plain=$(strip_ansi "$result")
    [ "$plain" = "[MAX|feast.t.]" ]
    rm -rf "$tmpdir"
}

@test "build_user_info: tier only without profile" {
    tmpdir=$(mktemp -d)
    CLAUDE_CACHE_DIR="$tmpdir"
    result=$(build_user_info "PRO")
    plain=$(strip_ansi "$result")
    [ "$plain" = "[PRO]" ]
    rm -rf "$tmpdir"
}

@test "build_user_info: short name preserved" {
    tmpdir=$(mktemp -d)
    CLAUDE_CACHE_DIR="$tmpdir"
    echo '{"account":{"display_name":"eric"}}' > "$tmpdir/profile.cache"
    result=$(build_user_info "MAX")
    plain=$(strip_ansi "$result")
    [ "$plain" = "[MAX|eric]" ]
    rm -rf "$tmpdir"
}

@test "build_user_info: empty tier and no profile returns empty" {
    tmpdir=$(mktemp -d)
    CLAUDE_CACHE_DIR="$tmpdir"
    result=$(build_user_info "")
    [ -z "$result" ]
    rm -rf "$tmpdir"
}

# --- format_money_minor currencies ---

@test "format_money_minor: EUR uses euro symbol" {
    result=$(format_money_minor 1500 EUR)
    [ "$result" = '€15' ]
}

@test "format_money_minor: JPY uses yen with no decimals" {
    result=$(format_money_minor 1500 JPY)
    [ "$result" = '¥1500' ]
}

@test "format_money_minor: null returns empty" {
    result=$(format_money_minor "" USD)
    [ -z "$result" ]
}

@test "format_money_minor: GBP uses pound symbol" {
    result=$(format_money_minor 2550 GBP)
    [ "$result" = '£25.50' ]
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

@test "integration: --test uses stdin context_window percentage" {
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.141","context_window":{"used_percentage":42,"context_window_size":1000000}}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"42%"* ]]
}

@test "integration: --test shows effort max" {
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.141","effort":{"level":"max"}}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"max"* ]]
}

@test "integration: --test hides default effort high" {
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.141","effort":{"level":"high"}}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" != *" high"* ]]
}

@test "integration: --test shows fast mode" {
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.141","fast_mode":true}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"fast"* ]]
}

@test "integration: --test falls back to transcript when used_percentage is null" {
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.141","context_window":{"used_percentage":null,"context_window_size":200000}}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"78%"* ]]
}

@test "integration: stdin rate_limits fallback without OAuth cache" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"claudeAiOauth":{"accessToken":"fake"}}' > "$tmpdir/.claude/.credentials.json"
    five_reset=$(date -d '+4 hours' +%s)
    seven_reset=$(date -d '+5 days' +%s)
    result=$(echo "{\"model\":{\"id\":\"claude-opus-4-6[1m]\",\"display_name\":\"Opus\"},\"cwd\":\"/tmp/test\",\"workspace\":{\"current_dir\":\"/tmp/test\"},\"cost\":{\"total_cost_usd\":0,\"total_lines_added\":0,\"total_lines_removed\":0,\"total_api_duration_ms\":0},\"version\":\"2.1.141\",\"context_window\":{\"used_percentage\":10,\"context_window_size\":1000000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":55,\"resets_at\":$five_reset},\"seven_day\":{\"used_percentage\":12,\"resets_at\":$seven_reset}}}" \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[55%]"* ]]
    [[ "$plain" == *"7d[12%]"* ]]
    rm -rf "$tmpdir"
}

# --- get_reset_seconds ---

@test "get_reset_seconds: future timestamp returns positive seconds" {
    ts=$(date -d '+90 minutes' +%s)
    result=$(get_reset_seconds "$ts")
    [ "$result" -ge 5300 ] && [ "$result" -le 5500 ]
}

@test "get_reset_seconds: past timestamp returns 0" {
    ts=$(date -d '-1 hour' +%s)
    result=$(get_reset_seconds "$ts")
    [ "$result" = "0" ]
}

@test "get_reset_seconds: ISO timestamp works" {
    ts=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(get_reset_seconds "$ts")
    [ "$result" -ge 7100 ] && [ "$result" -le 7300 ]
}

@test "get_reset_seconds: empty returns empty" {
    result=$(get_reset_seconds "")
    [ -z "$result" ]
}

@test "get_reset_seconds: null returns empty" {
    result=$(get_reset_seconds "null")
    [ -z "$result" ]
}

# --- smart 5h countdown (opportunity signal) ---

@test "build_usage_display: 5h at 40% with reset in 1h shows countdown" {
    reset_time=$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":40,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[40%\~1h ]]
}

@test "build_usage_display: 5h at 30% with reset in 3h hides countdown" {
    reset_time=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":30,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[30%]"* ]]
    [[ "$plain" != *"~"* ]] || [[ "$plain" != *"5h[30%~"* ]]
}

@test "build_usage_display: 5h at 85% with reset in 20min uses recovery color" {
    reset_time=$(date -u -d '+20 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":85,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    [[ "$result" == *"$DIM_GREEN"* ]]
}

@test "build_usage_display: 5h at 85% with reset in 2h keeps warning color" {
    reset_time=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":85,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[85%\~ ]]
    [[ "$result" != *"$DIM_GREEN"* ]]
}

# --- smart 7d countdown (planning signal) ---

@test "build_usage_display: 7d at 30% with reset in 2d shows countdown" {
    reset_time=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":30,\"resets_at\":\"$reset_time\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 7d\[30%\~2d ]]
}

@test "build_usage_display: 7d at 30% with reset in 5d hides countdown" {
    reset_time=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":30,\"resets_at\":\"$reset_time\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"7d[30%]"* ]]
}

@test "build_usage_display: 7d at 75% with reset in 10h uses recovery color" {
    reset_time=$(date -u -d '+10 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_time\"}}"
    result=$(build_usage_display "$usage" "")
    [[ "$result" == *"$DIM_GREEN"* ]]
}

@test "build_usage_display: 7d at 75% with reset in 3d keeps warning color" {
    reset_time=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_time\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 7d\[75%\~ ]]
    [[ "$result" != *"$DIM_GREEN"* ]]
}

# --- should_show_extra: auto mode ---

# --- should_show_extra: auto mode (percentage only) ---

@test "should_show_extra: auto shows when 5h >= 80" {
    run should_show_extra "auto" 85 50 0
    [ "$status" -eq 0 ]
}

@test "should_show_extra: auto shows when 7d >= 70" {
    run should_show_extra "auto" 10 75 0
    [ "$status" -eq 0 ]
}

@test "should_show_extra: auto shows when extra utilization >= 50%" {
    run should_show_extra "auto" 10 10 50
    [ "$status" -eq 0 ]
}

@test "should_show_extra: auto hides when all below threshold" {
    run should_show_extra "auto" 50 40 49
    [ "$status" -eq 1 ]
}

@test "should_show_extra: on-limit ignores extra_util" {
    run should_show_extra "on-limit" 10 10 80
    [ "$status" -eq 1 ]
}
