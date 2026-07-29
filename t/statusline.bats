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

@test "abbreviate_model_id: sonnet-5 flat versioning -> sonnet5 (no false .5 minor)" {
    result=$(abbreviate_model_id "claude-sonnet-5")
    [ "$result" = "sonnet5" ]
}

@test "abbreviate_model_id: fable-5 -> fabl5 (4-char family + version)" {
    result=$(abbreviate_model_id "claude-fable-5")
    [ "$result" = "fabl5" ]
}

@test "abbreviate_model_id: fable-5 with date suffix -> fabl5" {
    result=$(abbreviate_model_id "claude-fable-5-20260115")
    [ "$result" = "fabl5" ]
}

@test "abbreviate_model_id: unknown model passes through" {
    result=$(abbreviate_model_id "gpt-4o-mini")
    [ "$result" = "gpt-4o-mini" ]
}

@test "abbreviate_model_id: short alias passes through" {
    result=$(abbreviate_model_id "opus")
    [ "$result" = "opus" ]
}

# --- get_runtime_model ---

@test "get_runtime_model: fable family detected" {
    result=$(get_runtime_model "claude-fable-5[1m]")
    [ "$result" = "fable" ]
}

@test "get_runtime_model: opus family detected" {
    result=$(get_runtime_model "claude-opus-4-8")
    [ "$result" = "opus" ]
}

@test "get_runtime_model: unknown falls through" {
    result=$(get_runtime_model "gpt-5.4")
    [ "$result" = "unknown" ]
}

# --- rotate_debug_log ---

@test "rotate_debug_log: rotates when over cap" {
    tmpdir=$(mktemp -d)
    log="$tmpdir/statusline.log"
    DEBUG_LOG_MAX_BYTES=100
    head -c 200 /dev/zero | tr '\0' 'x' > "$log"
    rotate_debug_log "$log"
    [ ! -f "$log" ]
    [ -f "$log.1" ]
    rm -rf "$tmpdir"
}

@test "rotate_debug_log: keeps file under cap" {
    tmpdir=$(mktemp -d)
    log="$tmpdir/statusline.log"
    DEBUG_LOG_MAX_BYTES=1048576
    echo "small" > "$log"
    rotate_debug_log "$log"
    [ -f "$log" ]
    [ ! -f "$log.1" ]
    rm -rf "$tmpdir"
}

@test "rotate_debug_log: no-op on missing file" {
    tmpdir=$(mktemp -d)
    run rotate_debug_log "$tmpdir/nope.log"
    [ "$status" -eq 0 ]
    rm -rf "$tmpdir"
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

@test "build_usage_display: 5h at 87% includes wall-clock reset time" {
    reset_time=$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":87,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[87%@[0-9]{2}:[0-9]{2}\] ]]
}

@test "build_usage_display: 7d at 75% under pace pressure shows reset" {
    # 75% with ~2.2d left = ~4.8d elapsed: runway falls short of the deadline,
    # so the badge surfaces the absolute reset (verdict carried by color).
    reset_time=$(date -u -d '+2 days 5 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_time\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 7d\[75%@ ]]
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

@test "build_scoped_quota_display: scoped weekly limit shows for matching model" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":64,"resets_at":"2099-01-05T00:00:00Z","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}'
    result=$(build_scoped_quota_display "$usage" "claude-fable-5")
    plain=$(strip_ansi "$result")
    [[ "$plain" == "fb[64%]" ]]
}

@test "build_scoped_quota_display: scoped weekly limit hidden for non-matching model" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":64,"resets_at":"2099-01-05T00:00:00Z","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}'
    result=$(build_scoped_quota_display "$usage" "claude-opus-4-8")
    [ -z "$result" ]
}

@test "build_usage_display: scoped limits suppress legacy per-model fields" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"seven_day_opus":{"utilization":20},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":64,"resets_at":"2099-01-05T00:00:00Z","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}'
    result=$(build_usage_display "$usage" "MAX")
    plain=$(strip_ansi "$result")
    [[ "$plain" != *"op["* ]]
}

@test "build_scoped_quota_display: opus scope renders op badge on opus session" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":33,"resets_at":"2099-01-05T00:00:00Z","scope":{"model":{"id":null,"display_name":"Opus"},"surface":null},"is_active":false}]}'
    result=$(build_scoped_quota_display "$usage" "claude-opus-4-8")
    plain=$(strip_ansi "$result")
    [[ "$plain" == "op[33%]" ]]
}

@test "build_scoped_quota_display: unknown scoped model falls back to two-letter abbrev" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":42,"resets_at":"2099-01-05T00:00:00Z","scope":{"model":{"id":null,"display_name":"Zephyr"},"surface":null},"is_active":false}]}'
    result=$(build_scoped_quota_display "$usage" "claude-zephyr-1")
    plain=$(strip_ansi "$result")
    [[ "$plain" == "ze[42%]" ]]
}

@test "build_scoped_quota_display: zero-percent scoped limit is hidden" {
    usage='{"five_hour":{"utilization":10},"seven_day":{"utilization":5},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":0,"resets_at":"2099-01-05T00:00:00Z","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}'
    result=$(build_scoped_quota_display "$usage" "claude-fable-5")
    [ -z "$result" ]
}

@test "build_scoped_quota_display: empty model or usage yields nothing" {
    usage='{"limits":[{"kind":"weekly_scoped","percent":64,"scope":{"model":{"display_name":"Fable"}}}]}'
    [ -z "$(build_scoped_quota_display "$usage" "")" ]
    [ -z "$(build_scoped_quota_display "" "claude-fable-5")" ]
}

@test "build_usage_display: on-pace 7d hides runway and reset suffix" {
    # 7d 40% late in the window (reset in ~1d => ~6d elapsed) is well under
    # pace, so no runway hint, no @reset. The 5h reset time is always visible
    # (a live window always shows its wall-clock @HH:MM), so 5h carries @ here.
    reset_time=$(date -u -d '+3 hours 30 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_time_7d=$(date -u -d '+1 day' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":50,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":40,\"resets_at\":\"$reset_time_7d\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[50%@[0-9]{2}:[0-9]{2}\] ]]
    [[ "$plain" == *"7d[40%]"* ]]
    [[ "$plain" != *"d!"* ]]
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
    echo '{"account":{"display_name":"examplename"}}' > "$tmpdir/profile.cache"
    result=$(build_user_info "MAX")
    plain=$(strip_ansi "$result")
    [ "$plain" = "[MAX|example.]" ]
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

@test "build_user_info: account tag beats profile display name" {
    tmpdir=$(mktemp -d)
    CLAUDE_CACHE_DIR="$tmpdir"
    echo '{"account":{"display_name":"examplename"}}' > "$tmpdir/profile.cache"
    ACCOUNT_TAG="work"
    result=$(build_user_info "MAX")
    plain=$(strip_ansi "$result")
    [ "$plain" = "[MAX|@work]" ]
    rm -rf "$tmpdir"
}

@test "build_user_info: tag-only chip when no tier" {
    tmpdir=$(mktemp -d)
    CLAUDE_CACHE_DIR="$tmpdir"
    ACCOUNT_TAG="work"
    result=$(build_user_info "")
    plain=$(strip_ansi "$result")
    [ "$plain" = "[@work]" ]
    rm -rf "$tmpdir"
}

@test "build_user_info: long tag truncated at 12" {
    tmpdir=$(mktemp -d)
    CLAUDE_CACHE_DIR="$tmpdir"
    ACCOUNT_TAG="api-key-1a2b3c4d"
    result=$(build_user_info "")
    plain=$(strip_ansi "$result")
    [ "$plain" = "[@api-key-1a2.]" ]
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
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export STATUSLINE_TEST_NOW_MS
    export CLAUDE_CACHE_DIR

    result=$(refresh_oauth_credentials_file "$cred_file")

    # refresh must not leave its lock behind (blocks the next refresh 30s)
    [ ! -f "$tmpdir/oauth_refresh.lock" ]

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

# --- seven_day pace (burndown) ---
# Window is 7d=604800s; elapsed = 604800 - seconds_left.

@test "seven_day_elapsed: no verdict without a deadline" {
    [ -z "$(seven_day_elapsed '')" ]
}

@test "seven_day_elapsed: no verdict in the noisy first ~8h" {
    # 1h elapsed (seconds_left = 604800-3600) is below the 1/20 window floor.
    [ -z "$(seven_day_elapsed 601200)" ]
}

@test "seven_day_elapsed: reports elapsed once past the early window" {
    [ "$(seven_day_elapsed 518400)" = "86400" ]  # day 1
}

@test "seven_day_pace: heavy early burn is red and at risk" {
    # 40% one day into the window projects to ~280% — you'll run dry by day ~3.
    [ "$(seven_day_pace 40 518400 518400)" = "red 1 1" ]
}

@test "seven_day_pace: light early use is calm" {
    [ "$(seven_day_pace 10 518400 518400)" = "green 9 0" ]
}

@test "seven_day_pace: exactly on pace at the midpoint is green" {
    [ "$(seven_day_pace 50 302400 302400)" = "green 3 0" ]
}

@test "seven_day_pace: overshooting at the midpoint is red" {
    [ "$(seven_day_pace 70 302400 302400)" = "red 1 1" ]
}

@test "seven_day_pace: high but late is NOT a false alarm (was the bug)" {
    # 70% on day 6 projects to ~82% — you'll comfortably make it.
    [ "$(seven_day_pace 70 86400 86400)" = "green 2 0" ]
}

@test "seven_day_pace: near the cap is red regardless of timing" {
    [ "$(seven_day_pace 95 43200 43200)" = "red 0 1" ]
}

@test "seven_day_pace: no deadline falls back to level thresholds" {
    [ "$(seven_day_pace 75 '' '')" = "yellow -1 0" ]
    [ "$(seven_day_pace 90 '' '')" = "red -1 0" ]
    [ "$(seven_day_pace 30 '' '')" = "green -1 0" ]
}

@test "seven_day_pace: a shorter (weekend-skipped) deadline relieves the risk" {
    # 75% on day 5 (runway ~1.6d) is at risk against a 2d calendar deadline...
    [ "$(seven_day_pace 75 172800 172800 | cut -d' ' -f3)" = "1" ]
    # ...but not once the weekend (deadline -> 0) is removed.
    [ "$(seven_day_pace 75 172800 0 | cut -d' ' -f3)" = "0" ]
}

@test "weekend_secs_ahead: never exceeds the deadline, multiples of a day" {
    result=$(weekend_secs_ahead 172800)  # 2 days out
    [ "$result" -le 172800 ]
    [ $(( result % 86400 )) -eq 0 ]
}

# --- 7d learned forecast (weekday profile from usage.jsonl) ----------------

# Synthetic history: every local day burns +20% for account A (10 -> 30, then
# back to 10 next day: the negative midnight delta is a window reset and must
# be ignored). Account B burns +60/day and must be filtered out entirely.
_write_forecast_fixture() {
    local dir="$1" now days="$2"
    now=$(date +%s)
    echo '{"account":{"uuid":"acct-A"}}' > "$dir/profile.cache"
    : > "$dir/usage.jsonl"
    local d ts
    # acct-A also carries five_hour samples inside one shared window per day
    # (same resets_at) so the ratio learner sees 60 five-points buying 20
    # seven-points daily: pct_per_window = 20/60*100 = 33.33.
    for (( d = days; d >= 1; d-- )); do
        ts=$(( now - d * 86400 ))
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":10},"five_hour":{"utilization":10,"resets_at":"R%s"}}\n' "$ts" "$d"
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":22},"five_hour":{"utilization":40,"resets_at":"R%s"}}\n' "$(( ts + 14400 ))" "$d"
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":30},"five_hour":{"utilization":70,"resets_at":"R%s"}}\n' "$(( ts + 28800 ))" "$d"
        printf '{"timestamp":%s,"user":{"uuid":"acct-B"},"seven_day":{"utilization":20}}\n' "$(( ts + 1000 ))"
        printf '{"timestamp":%s,"user":{"uuid":"acct-B"},"seven_day":{"utilization":80}}\n' "$(( ts + 30000 ))"
    done >> "$dir/usage.jsonl"
}

@test "build_seven_day_profile: learns per-weekday burn, filters by account" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_forecast_fixture "$tmpdir" 21
    build_seven_day_profile
    [ -f "$tmpdir/forecast.cache" ]
    days=$(jq -r '.days_history' "$tmpdir/forecast.cache")
    [ "$days" -ge 14 ]
    # Account A burns 20/day; B's 60/day must not leak in. Allow EWMA rounding.
    mon=$(jq -r '.weekday_profile["1"]' "$tmpdir/forecast.cache")
    awk -v p="$mon" 'BEGIN{exit !(p >= 19 && p <= 21)}'
    # Ratio learner: 60 five-points buy 20 seven-points => ppw ~33.3
    ppw=$(jq -r '.pct_per_window' "$tmpdir/forecast.cache")
    awk -v p="$ppw" 'BEGIN{exit !(p >= 32 && p <= 35)}'
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: no paired 5h samples leaves the ratio unlearned" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    now=$(date +%s)
    : > "$tmpdir/usage.jsonl"
    for (( d = 16; d >= 1; d-- )); do
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":10}}\n' "$(( now - d * 86400 ))"
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":25}}\n' "$(( now - d * 86400 + 14400 ))"
    done >> "$tmpdir/usage.jsonl"
    build_seven_day_profile
    [ "$(jq -r '.pct_per_window' "$tmpdir/forecast.cache")" = "-1.00" ]
    [ -z "$(CLAUDE_ACCOUNT_DIR="$tmpdir" forecast_pct_per_window)" ]
    rm -rf "$tmpdir"
}

@test "forecast_pct_per_window: echoes the learned ratio" {
    tmpdir=$(mktemp -d)
    printf '{"pct_per_window":11.83}' > "$tmpdir/forecast.cache"
    [ "$(CLAUDE_ACCOUNT_DIR="$tmpdir" forecast_pct_per_window)" = "11.83" ]
    rm -rf "$tmpdir"
}

@test "_seven_day_walk: projects the end-of-week and the dry gap" {
    tmpdir=$(mktemp -d)
    # Flat 10%/day profile, 43% used, 4 days left: no dry, ends at 83.
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":10,"1":10,"2":10,"3":10,"4":10,"5":10,"6":10}}' > "$tmpdir/forecast.cache"
    read -r gap end <<<"$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 43 345600)"
    [ "$gap" = "-1" ]
    [ "$end" = "83" ]
    # Flat 20%/day, 50% used, 5 days left: dries mid-window, ~60h margin.
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":20,"1":20,"2":20,"3":20,"4":20,"5":20,"6":20}}' > "$tmpdir/forecast.cache"
    read -r gap end <<<"$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 50 432000)"
    [ "$gap" -ge 59 ] && [ "$gap" -le 60 ]
    [ "$end" = "100" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: hourly gate skips rebuild" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_forecast_fixture "$tmpdir" 16
    build_seven_day_profile
    first=$(jq -r '.computed_at' "$tmpdir/forecast.cache")
    sleep 1
    build_seven_day_profile
    [ "$(jq -r '.computed_at' "$tmpdir/forecast.cache")" = "$first" ]
    rm -rf "$tmpdir"
}

# --- widened snapshots + the waste ledger ----------------------------------

@test "log_usage_snapshot: records limits, model, null prediction while unlearned" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    model_id="claude-fable-5"
    usage='{"five_hour":{"utilization":50},"seven_day":{"utilization":40},"limits":[{"kind":"weekly_scoped","percent":97,"scope":{"model":{"display_name":"Fable"}}}]}'
    log_usage_snapshot "sess-1" "$usage" ""
    line=$(grep '"type":"usage"' "$tmpdir/usage.jsonl" | tail -1)
    [ "$(echo "$line" | jq -r '.model')" = "claude-fable-5" ]
    [ "$(echo "$line" | jq -r '.limits[0].kind')" = "weekly_scoped" ]
    [ "$(echo "$line" | jq -r '.predicted_end')" = "null" ]
    rm -rf "$tmpdir"
}

@test "log_usage_snapshot: stamps the learned end-of-week projection" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    model_id=""
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":10,"1":10,"2":10,"3":10,"4":10,"5":10,"6":10}}' > "$tmpdir/forecast.cache"
    reset=$(date -u -d '+4 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"five_hour":{"utilization":50},"seven_day":{"utilization":43,"resets_at":"%s"}}' "$reset")
    log_usage_snapshot "sess-1" "$usage" ""
    line=$(grep '"type":"usage"' "$tmpdir/usage.jsonl" | tail -1)
    pe=$(echo "$line" | jq -r '.predicted_end')
    # 43% used + 4 days x 10%/day = ~83 (walk rounding may land 82)
    [ "$pe" -ge 82 ] && [ "$pe" -le 83 ]
    [ "$(echo "$line" | jq -r '.model')" = "null" ]
    rm -rf "$tmpdir"
}

# Two 7d windows (W1 closes at 62%), three 5h windows (F1 closes at 80,
# F2 at 99.5 = capped; F3 still open). Timestamps relative to now so the
# default cutoff keeps everything.
_write_ledger_fixture() { # dir
    local dir="$1" now w1 w2 f1 f2 f3
    now=$(date +%s)
    echo '{"account":{"uuid":"acct-A"}}' > "$dir/profile.cache"
    w1=$(date -u -d "@$(( now - 3 * 86400 ))" '+%Y-%m-%dT%H:%M:%SZ')
    w2=$(date -u -d "@$(( now + 4 * 86400 ))" '+%Y-%m-%dT%H:%M:%SZ')
    f1=$(date -u -d "@$(( now - 4 * 86400 + 10800 ))" '+%Y-%m-%dT%H:%M:%SZ')
    f2=$(date -u -d "@$(( now - 2 * 86400 + 10800 ))" '+%Y-%m-%dT%H:%M:%SZ')
    f3=$(date -u -d "@$(( now - 86400 + 10800 ))" '+%Y-%m-%dT%H:%M:%SZ')
    : > "$dir/usage.jsonl"
    _lg() { # ts five five_reset seven seven_reset
        printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"five_hour":{"utilization":%s,"resets_at":"%s"},"seven_day":{"utilization":%s,"resets_at":"%s"}}\n' \
            "$1" "$2" "$3" "$4" "$5" >> "$dir/usage.jsonl"
    }
    _lg "$(( now - 4 * 86400 ))"        30   "$f1" 55 "$w1"
    _lg "$(( now - 4 * 86400 + 3600 ))" 80   "$f1" 62 "$w1"
    _lg "$(( now - 2 * 86400 ))"        20   "$f2" 5  "$w2"
    _lg "$(( now - 2 * 86400 + 3600 ))" 99.5 "$f2" 12 "$w2"
    _lg "$(( now - 86400 ))"            10   "$f3" 20 "$w2"
}

@test "run_usage_report: ledgers closed windows and expired capacity" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_ledger_fixture "$tmpdir"
    run run_usage_report 28
    [ "$status" -eq 0 ]
    [[ "$output" == *"7d windows closed: 1"* ]]
    [[ "$output" == *"used 62%  expired 38%"* ]]
    [[ "$output" == *"5h windows closed: 2   avg 90% at close   1 hit the cap"* ]]
    [[ "$output" == *"still learning"* ]]
    rm -rf "$tmpdir"
}

@test "run_usage_report: converts waste to windows once the ratio is learned" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_ledger_fixture "$tmpdir"
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"pct_per_window":10,"weekday_profile":{"0":10,"1":10,"2":10,"3":10,"4":10,"5":10,"6":10}}' > "$tmpdir/forecast.cache"
    reset=$(date -u -d '+4 days' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"seven_day":{"utilization":44,"resets_at":"%s"}}' "$reset" > "$tmpdir/usage.cache"
    run run_usage_report 28
    [ "$status" -eq 0 ]
    # 38% expired / 10 ppw = 3.8 windows' worth
    [[ "$output" == *"(~3.8 x 5h windows unused)"* ]]
    [[ "$output" == *"one full 5h window = ~10.00% of the week"* ]]
    [[ "$output" == *"week in progress: 44% used"* ]]
    # 44% + 4d x 10%/day: heading ~83-84%
    [[ "$output" == *"heading ~8"* ]]
    rm -rf "$tmpdir"
}

@test "run_usage_report: --days cutoff hides older closes; no history exits 1" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_ledger_fixture "$tmpdir"
    run run_usage_report 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"7d windows closed: 0"* ]]
    empty=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$empty"
    run run_usage_report 28
    [ "$status" -eq 1 ]
    [[ "$output" == *"no usage history yet"* ]]
    rm -rf "$tmpdir" "$empty"
}

@test "integration: statusline.sh report renders the ledger end-to-end" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/data"
    _write_ledger_fixture "$tmpdir/data"
    run env HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/data" bash "$SCRIPT_DIR/statusline.sh" report --days 14
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage report - default"* ]]
    [[ "$output" == *"7d windows closed: 1"* ]]
    rm -rf "$tmpdir"
}

# --- check + session-summary subcommands -----------------------------------

@test "run_check: calm cache prints calm and exits 0" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":20,"resets_at":"%s"},"seven_day":{"utilization":20,"resets_at":"%s"}}' \
        "$(date +%s)" "$reset_5h" "$reset_7d" > "$tmpdir/usage.cache"
    run run_check
    [ "$status" -eq 0 ]
    [ "$output" = "calm" ]
    rm -rf "$tmpdir"
}

@test "run_check: pressure exits 2 with the plain advisor text" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 85% only 2h into the window: hot pace, caps before reset (pressure)
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":85,"resets_at":"%s"},"seven_day":{"utilization":10}}' \
        "$(date +%s)" "$reset_5h" > "$tmpdir/usage.cache"
    run run_check
    [ "$status" -eq 2 ]
    [[ "$output" == "! 5h caps"* ]]
    rm -rf "$tmpdir"
}

@test "run_check: expiring surplus exits 1 (opportunity)" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 5h on pace (40% at 60% elapsed), 7d resets in 10h with 56% unused
    reset_5h=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+10 hours' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":40,"resets_at":"%s"},"seven_day":{"utilization":44,"resets_at":"%s"}}' \
        "$(date +%s)" "$reset_5h" "$reset_7d" > "$tmpdir/usage.cache"
    run run_check
    [ "$status" -eq 1 ]
    [[ "$output" == "+ 7d resets"* ]]
    rm -rf "$tmpdir"
}

@test "run_check: missing or stale cache exits 3" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    run run_check
    [ "$status" -eq 3 ]
    [[ "$output" == "unknown: no usage.cache"* ]]
    printf '{"fetched_at":%s,"five_hour":{"utilization":85}}' "$(( $(date +%s) - 7200 ))" > "$tmpdir/usage.cache"
    run run_check
    [ "$status" -eq 3 ]
    [[ "$output" == *"stale"* ]]
    rm -rf "$tmpdir"
}

_write_session_fixture() { # dir
    local dir="$1" now
    now=$(date +%s)
    : > "$dir/usage.jsonl"
    printf '{"type":"usage","session_id":"S1","timestamp":%s,"five_hour":{"utilization":10},"seven_day":{"utilization":5}}\n' "$(( now - 4000 ))" >> "$dir/usage.jsonl"
    printf '{"type":"usage","session_id":"S1","timestamp":%s,"five_hour":{"utilization":40},"seven_day":{"utilization":7}}\n' "$(( now - 2000 ))" >> "$dir/usage.jsonl"
    printf '{"type":"usage","session_id":"S1","timestamp":%s,"five_hour":{"utilization":70},"seven_day":{"utilization":9},"model":"claude-fable-5"}\n' "$(( now - 300 ))" >> "$dir/usage.jsonl"
}

@test "run_session_summary: summarizes the piped hook session" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_session_fixture "$tmpdir"
    out=$(printf '{"session_id":"S1"}' | run_session_summary)
    # 3700s span, +60 five-points, +4 seven-points, model from the last sample
    [ "$out" = "session S1: 1h1m, 5h +60pts, 7d +4pts, claude-fable-5" ]
    rm -rf "$tmpdir"
}

@test "run_session_summary: falls back to the last logged session; unknown exits 1" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_session_fixture "$tmpdir"
    out=$(run_session_summary < /dev/null)
    [[ "$out" == "session S1:"* ]]
    if printf '{"session_id":"nope"}' | run_session_summary > /dev/null; then
        false
    fi
    rm -rf "$tmpdir"
}

@test "integration: check and session-summary run end-to-end" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/data"
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":20,"resets_at":"%s"},"seven_day":{"utilization":20,"resets_at":"%s"}}' \
        "$(date +%s)" "$reset_5h" "$reset_7d" > "$tmpdir/data/usage.cache"
    _write_session_fixture "$tmpdir/data"
    run env HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/data" bash "$SCRIPT_DIR/statusline.sh" check
    [ "$status" -eq 0 ]
    [ "$output" = "calm" ]
    run bash -c "printf '{\"session_id\":\"S1\"}' | env HOME='$tmpdir' CLAUDE_DATA_DIR='$tmpdir/data' bash '$SCRIPT_DIR/statusline.sh' session-summary"
    [ "$status" -eq 0 ]
    [[ "$output" == "session S1:"* ]]
    rm -rf "$tmpdir"
}

_write_profile_cache() { # $1=dir $2=days_history $3=rate_all_days $4=recent24
    cat > "$1/forecast.cache" <<EOF
{"computed_at":$(date +%s),"days_history":$2,"recent_24h":$4,"recent_48h":0,
 "weekday_profile":{"0":$3,"1":$3,"2":$3,"3":$3,"4":$3,"5":$3,"6":$3}}
EOF
}

@test "seven_day_forecast: warns when learned burn dries quota before reset" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 20%/day uniform, 43% used, reset in 4d: remaining 57% lasts ~2.9d -> dry
    # ~1.1d before reset (gap < 48h) -> yellow.
    _write_profile_cache "$tmpdir" 21 20 0
    read -r level gap <<<"$(seven_day_forecast 43 345600)"
    [ "$level" = "yellow" ]
    rm -rf "$tmpdir"
}

@test "seven_day_forecast: red when dry days before reset" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 30%/day, 50% used, reset in 5d: dry in ~1.7d, gap ~3.3d (>= 48h) -> red.
    _write_profile_cache "$tmpdir" 21 30 0
    read -r level gap <<<"$(seven_day_forecast 50 432000)"
    [ "$level" = "red" ]
    [ "$gap" -ge 48 ]
    rm -rf "$tmpdir"
}

@test "seven_day_forecast: silent when the quota outlasts the window" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 5%/day, 43% used, 5d left: burns ~25% more, never dries.
    _write_profile_cache "$tmpdir" 21 5 0
    [ -z "$(seven_day_forecast 43 432000)" ]
    rm -rf "$tmpdir"
}

@test "seven_day_forecast: silent on cold start (<14 days history)" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_profile_cache "$tmpdir" 5 30 0
    [ -z "$(seven_day_forecast 50 432000)" ]
    rm -rf "$tmpdir"
}

@test "seven_day_forecast: recent 24h burn escalates over a calm profile (L1)" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # Profile says 5%/day (calm) but the last 24h burned 40%: 70% used with 3d
    # left dries within the first day at the hot rate -> warns.
    _write_profile_cache "$tmpdir" 21 5 40
    read -r level gap <<<"$(seven_day_forecast 70 259200)"
    [ "$level" = "red" ]
    rm -rf "$tmpdir"
}

@test "seven_day_forecast: no cache file means no verdict" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    [ -z "$(seven_day_forecast 50 432000)" ]
    rm -rf "$tmpdir"
}

# --- is_1m_model ------------------------------------------------------------

@test "is_1m_model: ctx_size > 200k is sufficient regardless of exceeds_200k" {
    model_id="claude-opus-4-8" ctx_size=1000000 exceeds_200k=false
    run is_1m_model
    [ "$status" -eq 0 ]
}

@test "is_1m_model: exceeds_200k_tokens=true does NOT imply a 1M window" {
    # The real bug: claude-opus-4-6 with a genuine 200k window reports
    # exceeds_200k_tokens=true once cumulative session usage passes 200k
    # tokens. That must not be read as "this is a 1M-context model."
    model_id="claude-opus-4-6" ctx_size=200000 exceeds_200k=true
    run is_1m_model
    [ "$status" -eq 1 ]
}

@test "is_1m_model: falls back to [1m] suffix when ctx_size is absent" {
    model_id="claude-opus-4-6[1m]" ctx_size="" exceeds_200k=false
    run is_1m_model
    [ "$status" -eq 0 ]
}

@test "is_1m_model: falls back to default-1M family when ctx_size is absent" {
    model_id="claude-fable-5" ctx_size="" exceeds_200k=false
    run is_1m_model
    [ "$status" -eq 0 ]
}

@test "is_1m_model: plain 200k model with no signals is not 1M" {
    model_id="claude-sonnet-4-6" ctx_size=200000 exceeds_200k=false
    run is_1m_model
    [ "$status" -eq 1 ]
}

# --- premium band -> bar color ---------------------------------------------

@test "premium_band_level: yellow band over 200k, red past 800k" {
    ctx_size=1000000 exceeds_200k=false
    context_pct=15; [ "$(premium_band_level)" = "0" ]
    context_pct=30; [ "$(premium_band_level)" = "1" ]
    context_pct=82; [ "$(premium_band_level)" = "2" ]
}

@test "premium_band_level: exceeds_200k_tokens is ignored (cumulative-usage flag, not a window-size signal)" {
    # Real logs: a genuine 200k-window opus-4-6 session reports
    # exceeds_200k_tokens=true once cumulative usage passes 200k tokens — the
    # flag tracks session-total usage, not window capacity. Band must follow
    # ctx_size x context_pct only.
    ctx_size=1000000 context_pct=15 exceeds_200k=true
    [ "$(premium_band_level)" = "0" ]
}

@test "premium_band_level: 200k window never enters the band, even with exceeds_200k=true" {
    ctx_size=200000 context_pct=90 exceeds_200k=false
    [ "$(premium_band_level)" = "0" ]
    exceeds_200k=true
    [ "$(premium_band_level)" = "0" ]
}

@test "build_usage_display: pace pressure shows explicit @Nd remaining" {
    # 75% used, reset in ~5d (=> ~2d elapsed, way over pace): the reset
    # distance appears as days-remaining even though reset is far away.
    reset_time=$(date -u -d '+5 days 2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_time\"}}"
    plain=$(strip_ansi "$(build_usage_display "$usage" "")")
    [[ "$plain" == *"7d[75%@5d]"* ]]
}

@test "build_usage_display: pressure inside the last day shows wall-clock reset" {
    # < 24h to reset: the old @Nh/@<1h countdown decayed by the hour in a
    # frozen frame — the badge now uses the 5h idiom, absolute @HH:MM.
    reset_time=$(date -u -d '+6 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":90,\"resets_at\":\"$reset_time\"}}"
    plain=$(strip_ansi "$(build_usage_display "$usage" "")")
    expected=$(_fmt_epoch "$(_epoch_from_ts "$reset_time")" '%H:%M')
    [[ "$plain" == *"7d[90%@${expected}]"* ]]
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

# --- is_default_1m_family ---

@test "is_default_1m_family: fable is a default-1M family" {
    run is_default_1m_family "claude-fable-5"
    [ "$status" -eq 0 ]
}

@test "is_default_1m_family: fable with date suffix still matches" {
    run is_default_1m_family "claude-fable-5-20260115"
    [ "$status" -eq 0 ]
}

@test "is_default_1m_family: opus is not a default-1M family" {
    run is_default_1m_family "claude-opus-4-6"
    [ "$status" -eq 1 ]
}

@test "is_default_1m_family: sonnet-4-6 is not a default-1M family" {
    run is_default_1m_family "claude-sonnet-4-6"
    [ "$status" -eq 1 ]
}

@test "is_default_1m_family: sonnet-5 is a default-1M family (2.1.197+)" {
    run is_default_1m_family "claude-sonnet-5"
    [ "$status" -eq 0 ]
}

@test "is_default_1m_family: sonnet-5 with date suffix still matches" {
    run is_default_1m_family "claude-sonnet-5-20260601"
    [ "$status" -eq 0 ]
}

# --- get_context_limit ---

@test "get_context_limit: 1m model" {
    result=$(get_context_limit "claude-opus-4-6[1m]")
    [ "$result" = "1000000" ]
}

@test "get_context_limit: fable defaults to 1M without a [1m] suffix (2.1.173+)" {
    result=$(get_context_limit "claude-fable-5")
    [ "$result" = "1000000" ]
}

@test "get_context_limit: sonnet-5 defaults to 1M without a [1m] suffix (2.1.197+)" {
    result=$(get_context_limit "claude-sonnet-5")
    [ "$result" = "1000000" ]
}

@test "get_context_limit: sonnet-4-6 stays 200k (1M is still opt-in for it)" {
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
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.139"}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.6[1m]"* ]]
    rm -rf "$tmpdir"
}

@test "integration: stdin model.id wins over settings.json .model (regression)" {
    # The session is running opus-4-6 at a 200k window; settings.json defaults to
    # claude-fable-5[1m]. The badge MUST show the running model (opus4.6), not the
    # static default — and at 200k, not 1M. Regression for the fabl5-on-opus bug
    # where the name (settings) and context (stdin) came from different sources.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"model":"claude-fable-5[1m]"}' > "$tmpdir/.claude/settings.json"
    result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","context_window":{"used_percentage":86,"context_window_size":200000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.6"* ]]
    [[ "$plain" != *"fabl"* ]]
    [[ "$plain" != *"[1m"* ]]   # 200k window -> no 1M tag
    rm -rf "$tmpdir"
}

@test "integration: settings.json .model is the fallback when stdin has no id" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"model":"opus"}' > "$tmpdir/.claude/settings.json"
    result=$(echo '{"model":{"display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174"}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus"* ]]
    rm -rf "$tmpdir"
}

@test "integration: --test renders fabl5[1m] under 200k context" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    result=$(echo '{"model":{"id":"claude-fable-5[1m]","display_name":"Fable 5 (1M context)"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.170","context_window":{"used_percentage":15,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"fabl5[1m]"* ]]
    [[ "$plain" != *"[1m:"* ]]
    # Fable identity = bright red (0;91), matching the Claude Code TUI.
    [[ "$result" == *$'\033[0;91m'* ]]
    rm -rf "$tmpdir"
}

@test "integration: premium band colors the context bar yellow (no :NNNk text)" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # 30% of a 1M window = 300k tokens, past the 200k premium boundary. The
    # band is the BAR's color now; the tag stays a constant [1m] (the absolute
    # NNNk was redundant with the bar percentage).
    result=$(echo '{"model":{"id":"claude-fable-5[1m]","display_name":"Fable 5 (1M context)"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.170","context_window":{"used_percentage":30,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"fabl5[1m]"* ]]
    [[ "$plain" != *"[1m:"* ]]
    # Bar (30% would be green) escalated to warning yellow by the band.
    [[ "$result" == *$'\033[0;33m'*"30%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: deep premium band (>800k) colors the context bar red" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","exceeds_200k_tokens":true,"context_window":{"used_percentage":82,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    # 82% of 1M = 820k: deep band forces red even though pct < 85 threshold.
    [[ "$result" == *$'\033[0;31m'*"82%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: fable WITHOUT [1m] suffix (2.1.173+) still renders fabl5[1m]" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # 2.1.173+ strips the [1m] suffix from Fable 5 (1M is its default), so the
    # tag must come from the family, not the suffix.
    result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","context_window":{"used_percentage":15,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"fabl5[1m]"* ]]
    [[ "$plain" != *"[1m:"* ]]
    rm -rf "$tmpdir"
}

@test "integration: sonnet-5 WITHOUT [1m] suffix (2.1.197+) renders sonnet5[1m], not sonnet5.5" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # 2.1.197+ strips the [1m] suffix from Sonnet 5 (1M is its default), same as
    # fable. Observed in real logs: id="claude-sonnet-5", exceeds_200k=true,
    # context_window_size=1000000, no suffix.
    result=$(echo '{"model":{"id":"claude-sonnet-5","display_name":"Sonnet 5"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.197","exceeds_200k_tokens":true,"context_window":{"used_percentage":29,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"sonnet5[1m]"* ]]
    [[ "$plain" != *"sonnet5.5"* ]]
    rm -rf "$tmpdir"
}

@test "integration: suffix-less fable flags the premium band over 200k" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # 30% of the (family-detected) 1M window = 300k, past the 200k boundary.
    result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","context_window":{"used_percentage":30,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"fabl5[1m]"* ]]
    [[ "$plain" != *"[1m:"* ]]
    [[ "$result" == *$'\033[0;33m'*"30%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: exceeds_200k_tokens does not force the premium band at low pct" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # exceeds_200k_tokens tracks cumulative session usage crossing 200k, not
    # window size — real logs show it true on genuine 200k-window sessions
    # too. The 1M tag still comes from context_window_size (ctx_size), but the
    # premium band must reflect the real computed 150k (15% of 1M), not the
    # flag: no yellow band here.
    result=$(echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","exceeds_200k_tokens":true,"context_window":{"used_percentage":15,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"fabl5[1m]"* ]]
    [[ "$result" != *$'\033[0;33m'*"15%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: exceeds_200k_tokens on a real 200k window does not add a false 1M tag" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # Real bug, real logs: claude-opus-4-6 (no [1m] suffix) with a genuine
    # 200k context_window_size reports exceeds_200k_tokens=true once session
    # cumulative usage passes 200k tokens. That flag must not be read as "this
    # window is 1M" — ctx_size=200000 is the ground truth here.
    result=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.197","exceeds_200k_tokens":true,"context_window":{"used_percentage":100,"context_window_size":200000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.6"* ]]
    [[ "$plain" != *"[1m"* ]]
    rm -rf "$tmpdir"
}

@test "integration: opus4.6[1m] opt-in suffix still drives the 1M tag (compat)" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","context_window":{"used_percentage":50,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.6[1m]"* ]]
    [[ "$result" == *$'\033[0;33m'*"50%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: suffix-less model on a 1M window (ctx_size) gets the 1M tag" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # Observed in real logs: opus-4-8 with NO [1m] suffix and a reported 1M
    # context_window_size. That field alone (not exceeds_200k_tokens, which
    # only tracks cumulative usage — see is_1m_model) is authoritative, so the
    # tag must follow it.
    result=$(echo '{"model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","exceeds_200k_tokens":true,"context_window":{"used_percentage":24,"context_window_size":1000000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.8[1m]"* ]]
    [[ "$result" == *$'\033[0;33m'*"24%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: suffix-less 200k model stays plain (no false 1M tag)" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # A genuine 200k window must NOT pick up a [1m] tag from the new ctx_size path.
    result=$(echo '{"model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.174","context_window":{"used_percentage":40,"context_window_size":200000}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.8"* ]]
    [[ "$plain" != *"[1m"* ]]
    rm -rf "$tmpdir"
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

@test "integration: --test shows effort max as max badge" {
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

@test "integration: post-compact zero context renders an empty bar, not nothing" {
    # After /compact the CLI reports used_percentage=0 for the reset window
    # (observed live, 2026-07-02). Hiding the bar at 0 read as "statusline
    # didn't refresh" — a real stdin zero must render a visibly empty bar.
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.197","context_window":{"used_percentage":0,"context_window_size":1000000}}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"opus4.6[1m][░░░░░░0%]"* ]]
}

@test "integration: absent context data still renders no bar" {
    # No context_window and no readable transcript: 0% would be a fabricated
    # number, so the bar stays hidden (distinct from a real stdin zero).
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    result=$(echo '{"session_id":"sess-noctx","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.197"}' \
        | HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/.claude/statusline" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh")
    plain=$(strip_ansi "$result")
    [[ "$plain" != *"0%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: account usage.cache is read regardless of session_id" {
    # The shared account cache (not a per-session file) drives the quota
    # display. Two different session_ids hitting the same account dir must
    # both render the same cached quota.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    echo '{"claudeAiOauth":{"accessToken":"fake"}}' > "$tmpdir/.claude/.credentials.json"
    cat > "$tmpdir/.claude/statusline/usage.cache" <<JSON
{"fetched_at":$(date +%s),"five_hour":{"utilization":42},"seven_day":{"utilization":17}}
JSON
    result=$(echo '{"session_id":"sess-A","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.170","context_window":{"used_percentage":10,"context_window_size":200000}}' \
        | HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/.claude/statusline" CLAUDE_CACHE_DIR="$tmpdir/.claude/statusline/sessions" bash "$SCRIPT_DIR/statusline.sh")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[42%]"* ]]
    [[ "$plain" == *"7d[17%]"* ]]
    # No per-session cache file should have been created.
    [ ! -f "$tmpdir/.claude/statusline/sessions/sess-A.cache" ]
    rm -rf "$tmpdir"
}

@test "integration: migrates legacy SCRIPT_DIR usage.jsonl into shared dir" {
    # Simulate the old layout where the usage log lived next to the script.
    # On first run the script should migrate it into ~/.claude/statusline.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    workdir=$(mktemp -d)
    cp "$SCRIPT_DIR/statusline.sh" "$workdir/statusline.sh"
    echo '{"type":"usage","session_id":"legacy"}' > "$workdir/usage.jsonl"
    echo '{"organization":{"organization_type":"claude_max"}}' > "$workdir/profile.cache"

    # Unset the data/cache dir overrides so the default ~/.claude/statusline
    # layout is used and migration from SCRIPT_DIR ($workdir) can trigger.
    echo '{"session_id":"sess-X","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.170"}' \
        | env -u CLAUDE_DATA_DIR -u CLAUDE_CACHE_DIR HOME="$tmpdir" bash "$workdir/statusline.sh" >/dev/null

    [ -f "$tmpdir/.claude/statusline/usage.jsonl" ]
    [ -f "$tmpdir/.claude/statusline/profile.cache" ]
    [ ! -f "$workdir/usage.jsonl" ]
    rm -rf "$tmpdir" "$workdir"
}

@test "integration: stdin rate_limits fallback without OAuth cache" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"claudeAiOauth":{"accessToken":"fake"}}' > "$tmpdir/.claude/.credentials.json"
    five_reset=$(date -d '+4 hours' +%s)
    seven_reset=$(date -d '+5 days' +%s)
    result=$(echo "{\"model\":{\"id\":\"claude-opus-4-6[1m]\",\"display_name\":\"Opus\"},\"cwd\":\"/tmp/test\",\"workspace\":{\"current_dir\":\"/tmp/test\"},\"cost\":{\"total_cost_usd\":0,\"total_lines_added\":0,\"total_lines_removed\":0,\"total_api_duration_ms\":0},\"version\":\"2.1.141\",\"context_window\":{\"used_percentage\":10,\"context_window_size\":1000000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":55,\"resets_at\":$five_reset},\"seven_day\":{\"used_percentage\":12,\"resets_at\":$seven_reset}}}" \
        | HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/.claude/statusline" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[55%@"* ]]
    [[ "$plain" == *"7d[12%]"* ]]
    rm -rf "$tmpdir"
}

@test "integration: 5h utilization climb flashes +N on the next render" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"claudeAiOauth":{"accessToken":"fake"}}' > "$tmpdir/.claude/.credentials.json"
    five_reset=$(date -d '+3 hours 30 minutes' +%s)
    seven_reset=$(date -d '+5 days' +%s)
    payload() {
        echo "{\"session_id\":\"sess-bump\",\"model\":{\"id\":\"claude-opus-4-8\",\"display_name\":\"Opus\"},\"cwd\":\"/tmp/test\",\"workspace\":{\"current_dir\":\"/tmp/test\"},\"cost\":{\"total_cost_usd\":0,\"total_lines_added\":0,\"total_lines_removed\":0,\"total_api_duration_ms\":0},\"version\":\"2.1.197\",\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":$1,\"resets_at\":$five_reset},\"seven_day\":{\"used_percentage\":12,\"resets_at\":$seven_reset}}}"
    }
    payload 40 | HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/.claude/statusline" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" >/dev/null
    result=$(payload 43 | HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/.claude/statusline" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh")
    plain=$(strip_ansi "$result")
    # +N binds tight to its badge, outside the brackets: 5h[43%@HH:MM]+3
    [[ "$plain" =~ 5h\[43%@[0-9]{2}:[0-9]{2}\]\+3 ]]
    # State is per-session and lives beside the cache-health files.
    [ -f "$tmpdir/sessions/sess-bump_quota_seen" ]
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

# --- 5h reset time (always visible, wall-clock) ---
# Wall-clock, not a countdown: the statusline only re-renders on activity,
# so a relative "@1h38m" decays into a lie during idle gaps. @HH:MM stays
# true in a frozen frame (v0.7.0 rationale, restored in v0.14.0).

@test "format_reset_absolute: future timestamp renders local HH:MM" {
    ts=$(date -u -d '+2 hours 30 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_absolute "$ts")
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_reset_absolute: bare epoch works" {
    ts=$(date -d '+2 hours' +%s)
    result=$(format_reset_absolute "$ts")
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}$ ]]
}

@test "format_reset_absolute: past timestamp returns now" {
    ts=$(date -d '-1 hour' +%s)
    result=$(format_reset_absolute "$ts")
    [ "$result" = "now" ]
}

@test "format_reset_absolute: empty and null return empty" {
    [ -z "$(format_reset_absolute "")" ]
    [ -z "$(format_reset_absolute "null")" ]
}

@test "build_usage_display: 5h at 40% shows wall-clock reset time" {
    reset_time=$(date -u -d '+1 hour 30 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":40,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[40%@[0-9]{2}:[0-9]{2}\] ]]
}

@test "build_usage_display: 5h at 30% shows reset time even far from reset" {
    # Low usage, distant reset — the old gating hid this; the reset time is
    # unconditional while a window is live.
    reset_time=$(date -u -d '+3 hours 30 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":30,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[30%@[0-9]{2}:[0-9]{2}\] ]]
}

@test "build_usage_display: 5h without resets_at stays a bare badge" {
    usage='{"five_hour":{"utilization":30},"seven_day":{"utilization":10}}'
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[30%]"* ]]
}

# --- quota bump notice (+N flash when utilization climbs between renders) ---

# --- delta_flash (unified per-component +X/-X change flash) ---

@test "delta_flash: first sighting is quiet" {
    tmpdir=$(mktemp -d)
    [ "$(delta_flash cost 753 "$tmpdir/flash")" = "0" ]
    rm -rf "$tmpdir"
}

@test "delta_flash: increase emits +delta, decrease emits -delta" {
    tmpdir=$(mktemp -d)
    delta_flash ctx 12 "$tmpdir/flash" >/dev/null
    [ "$(delta_flash ctx 15 "$tmpdir/flash")" = "3" ]
    delta_flash ctx 70 "$tmpdir/flash" >/dev/null
    [ "$(delta_flash ctx 12 "$tmpdir/flash")" = "-58" ]
    rm -rf "$tmpdir"
}

@test "delta_flash: unchanged value keeps a fresh flash, expiry clears it" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 delta_flash ctx 12 "$tmpdir/flash" >/dev/null
    STATUSLINE_TEST_NOW_EPOCH=1010 delta_flash ctx 15 "$tmpdir/flash" >/dev/null
    [ "$(STATUSLINE_TEST_NOW_EPOCH=1030 delta_flash ctx 15 "$tmpdir/flash")" = "3" ]
    [ "$(STATUSLINE_TEST_NOW_EPOCH=1071 delta_flash ctx 15 "$tmpdir/flash")" = "0" ]
    rm -rf "$tmpdir"
}

@test "delta_flash: components are independent in one state file" {
    tmpdir=$(mktemp -d)
    delta_flash cost 753 "$tmpdir/flash" >/dev/null
    delta_flash ctx 12 "$tmpdir/flash" >/dev/null
    [ "$(delta_flash cost 765 "$tmpdir/flash")" = "12" ]
    [ "$(delta_flash ctx 12 "$tmpdir/flash")" = "0" ]
    rm -rf "$tmpdir"
}

@test "delta_flash: garbage input or missing state file stays quiet" {
    tmpdir=$(mktemp -d)
    [ "$(delta_flash ctx "" "$tmpdir/flash")" = "0" ]
    [ "$(delta_flash ctx "12.5" "$tmpdir/flash")" = "0" ]
    [ "$(delta_flash ctx 12 "")" = "0" ]
    rm -rf "$tmpdir"
}

@test "delta_flash_part: renders reverse-video sign, quiet on zero" {
    plain=$(strip_ansi "$(delta_flash_part 3 "$GREEN")")
    [ "$plain" = "+3" ]
    plain=$(strip_ansi "$(delta_flash_part -58 "$GREEN")")
    [ "$plain" = "-58" ]
    [ -z "$(delta_flash_part 0 "$GREEN")" ]
}

@test "build_scoped_quota_display: flash on scoped pct change" {
    tmpdir=$(mktemp -d)
    usage='{"limits":[{"kind":"weekly_scoped","percent":67,"scope":{"model":{"display_name":"Fable"}}}]}'
    plain=$(strip_ansi "$(build_scoped_quota_display "$usage" "claude-fable-5" "$tmpdir/flash")")
    [ "$plain" = "fb[67%]" ]
    usage='{"limits":[{"kind":"weekly_scoped","percent":69,"scope":{"model":{"display_name":"Fable"}}}]}'
    plain=$(strip_ansi "$(build_scoped_quota_display "$usage" "claude-fable-5" "$tmpdir/flash")")
    [ "$plain" = "fb[69%]+2" ]
    rm -rf "$tmpdir"
}

@test "quota_bump_notice: first sighting is quiet" {
    tmpdir=$(mktemp -d)
    result=$(quota_bump_notice 42 10 "$tmpdir/state")
    [ "$result" = "0 0" ]
    rm -rf "$tmpdir"
}

@test "quota_bump_notice: climb emits the increment per window" {
    tmpdir=$(mktemp -d)
    quota_bump_notice 42 10 "$tmpdir/state" >/dev/null
    result=$(quota_bump_notice 45 11 "$tmpdir/state")
    [ "$result" = "3 1" ]
    rm -rf "$tmpdir"
}

@test "quota_bump_notice: unchanged value keeps a fresh notice alive" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 quota_bump_notice 42 10 "$tmpdir/state" >/dev/null
    STATUSLINE_TEST_NOW_EPOCH=1010 quota_bump_notice 44 10 "$tmpdir/state" >/dev/null
    result=$(STATUSLINE_TEST_NOW_EPOCH=1030 quota_bump_notice 44 10 "$tmpdir/state")
    [ "$result" = "2 0" ]
    rm -rf "$tmpdir"
}

@test "quota_bump_notice: notice expires after QUOTA_BUMP_NOTICE_SECS" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 quota_bump_notice 42 10 "$tmpdir/state" >/dev/null
    STATUSLINE_TEST_NOW_EPOCH=1010 quota_bump_notice 44 10 "$tmpdir/state" >/dev/null
    result=$(STATUSLINE_TEST_NOW_EPOCH=1071 quota_bump_notice 44 10 "$tmpdir/state")
    [ "$result" = "0 0" ]
    rm -rf "$tmpdir"
}

@test "quota_bump_notice: window reset (drop) clears silently" {
    tmpdir=$(mktemp -d)
    quota_bump_notice 80 10 "$tmpdir/state" >/dev/null
    quota_bump_notice 85 10 "$tmpdir/state" >/dev/null
    result=$(quota_bump_notice 3 10 "$tmpdir/state")
    [ "$result" = "0 0" ]
    rm -rf "$tmpdir"
}

@test "quota_bump_notice: no state file disables the machinery" {
    result=$(quota_bump_notice 42 10 "")
    [ "$result" = "0 0" ]
}

@test "build_usage_display: bump renders +N bound tight outside the badge" {
    tmpdir=$(mktemp -d)
    usage1='{"five_hour":{"utilization":42},"seven_day":{"utilization":10}}'
    usage2='{"five_hour":{"utilization":45},"seven_day":{"utilization":12}}'
    build_usage_display "$usage1" "" "$tmpdir/state" >/dev/null
    result=$(build_usage_display "$usage2" "" "$tmpdir/state")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[45%]+3"* ]]
    [[ "$plain" == *"7d[12%]+2"* ]]
    rm -rf "$tmpdir"
}

@test "build_usage_display: bump composes with the 5h countdown suffix" {
    tmpdir=$(mktemp -d)
    reset_time=$(date -u -d '+2 hours 30 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    usage1="{\"five_hour\":{\"utilization\":42,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    usage2="{\"five_hour\":{\"utilization\":45,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    build_usage_display "$usage1" "" "$tmpdir/state" >/dev/null
    result=$(build_usage_display "$usage2" "" "$tmpdir/state")
    plain=$(strip_ansi "$result")
    # +N outside, tight: 5h[45%@HH:MM]+3
    [[ "$plain" =~ 5h\[45%@[0-9]{2}:[0-9]{2}\]\+3 ]]
    rm -rf "$tmpdir"
}

# --- fetch error state (escalating cooldown + categorized indicator) ---

@test "record_fetch_error: first failure = 120s cooldown, count 1" {
    tmpdir=$(mktemp -d)
    record_fetch_error "$tmpdir/usage.err" 429 ""
    [ "$(jq -r '.count' "$tmpdir/usage.err")" = "1" ]
    [ "$(jq -r '.cooldown' "$tmpdir/usage.err")" = "120" ]
    [ "$(jq -r '.code' "$tmpdir/usage.err")" = "429" ]
    rm -rf "$tmpdir"
}

@test "record_fetch_error: consecutive failures escalate 120-240-480-600 cap" {
    tmpdir=$(mktemp -d)
    record_fetch_error "$tmpdir/usage.err" 429 ""
    record_fetch_error "$tmpdir/usage.err" 429 ""
    [ "$(jq -r '.cooldown' "$tmpdir/usage.err")" = "240" ]
    record_fetch_error "$tmpdir/usage.err" 429 ""
    [ "$(jq -r '.cooldown' "$tmpdir/usage.err")" = "480" ]
    record_fetch_error "$tmpdir/usage.err" 429 ""
    [ "$(jq -r '.cooldown' "$tmpdir/usage.err")" = "600" ]
    record_fetch_error "$tmpdir/usage.err" 429 ""
    [ "$(jq -r '.cooldown' "$tmpdir/usage.err")" = "600" ]
    [ "$(jq -r '.count' "$tmpdir/usage.err")" = "5" ]
    rm -rf "$tmpdir"
}

@test "record_fetch_error: longer Retry-After extends the cooldown" {
    tmpdir=$(mktemp -d)
    record_fetch_error "$tmpdir/usage.err" 429 300
    [ "$(jq -r '.cooldown' "$tmpdir/usage.err")" = "300" ]
    rm -rf "$tmpdir"
}

@test "record_fetch_error: shorter or garbage Retry-After is ignored" {
    tmpdir=$(mktemp -d)
    record_fetch_error "$tmpdir/a.err" 429 30
    [ "$(jq -r '.cooldown' "$tmpdir/a.err")" = "120" ]
    # Old curl (< 7.83) passes the -w format string through literally.
    record_fetch_error "$tmpdir/b.err" 429 '%header{retry-after}'
    [ "$(jq -r '.cooldown' "$tmpdir/b.err")" = "120" ]
    rm -rf "$tmpdir"
}

@test "fetch_error_remaining: fresh error blocks, expired or missing clears" {
    tmpdir=$(mktemp -d)
    jq -n --argjson at "$(date +%s)" '{at:$at,code:"429",count:1,cooldown:120}' >"$tmpdir/usage.err"
    [ "$(fetch_error_remaining "$tmpdir/usage.err")" -gt 0 ]
    jq -n --argjson at "$(($(date +%s) - 121))" '{at:$at,code:"429",count:1,cooldown:120}' >"$tmpdir/usage.err"
    [ "$(fetch_error_remaining "$tmpdir/usage.err")" = "0" ]
    [ "$(fetch_error_remaining "$tmpdir/missing.err")" = "0" ]
    rm -rf "$tmpdir"
}

@test "fetch_error_remaining: legacy epoch err file gets the old 120s window" {
    tmpdir=$(mktemp -d)
    date +%s >"$tmpdir/usage.err"
    [ "$(fetch_error_remaining "$tmpdir/usage.err")" -gt 0 ]
    echo $(($(date +%s) - 121)) >"$tmpdir/usage.err"
    [ "$(fetch_error_remaining "$tmpdir/usage.err")" = "0" ]
    rm -rf "$tmpdir"
}

@test "fetch_error_badge: maps codes to !429 / !auth / !5xx / !net / !" {
    tmpdir=$(mktemp -d)
    record_fetch_error "$tmpdir/a" 429 "";  [ "$(fetch_error_badge "$tmpdir/a")" = "!429" ]
    record_fetch_error "$tmpdir/b" 401 "";  [ "$(fetch_error_badge "$tmpdir/b")" = "!auth" ]
    record_fetch_error "$tmpdir/c" 403 "";  [ "$(fetch_error_badge "$tmpdir/c")" = "!auth" ]
    record_fetch_error "$tmpdir/d" 503 "";  [ "$(fetch_error_badge "$tmpdir/d")" = "!5xx" ]
    record_fetch_error "$tmpdir/e" 000 "";  [ "$(fetch_error_badge "$tmpdir/e")" = "!net" ]
    # Legacy bare-epoch err file carries no code: bare !
    date +%s >"$tmpdir/f";                  [ "$(fetch_error_badge "$tmpdir/f")" = "!" ]
    rm -rf "$tmpdir"
}

@test "record_fetch_error: keeps curl's error message for diagnosis" {
    tmpdir=$(mktemp -d)
    record_fetch_error "$tmpdir/usage.err" 000 "" "SSL certificate problem: unable to get local issuer certificate"
    [ "$(jq -r '.msg' "$tmpdir/usage.err")" = "SSL certificate problem: unable to get local issuer certificate" ]
    # No message -> no msg field (old file shape preserved)
    record_fetch_error "$tmpdir/b.err" 429 ""
    [ "$(jq -r 'has("msg")' "$tmpdir/b.err")" = "false" ]
    rm -rf "$tmpdir"
}

# --- curl CA bundle (mitm proxy trust via NODE_EXTRA_CA_CERTS) ---

@test "curl_ca_bundle: empty when NODE_EXTRA_CA_CERTS unset or unreadable" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    NODE_EXTRA_CA_CERTS=""
    [ -z "$(curl_ca_bundle)" ]
    NODE_EXTRA_CA_CERTS="$tmpdir/nonexistent.pem"
    [ -z "$(curl_ca_bundle)" ]
    rm -rf "$tmpdir"
}

@test "curl_ca_bundle: combined bundle contains the extra cert" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir/acct"
    NODE_EXTRA_CA_CERTS="$tmpdir/mitm-ca.pem"
    echo "FAKE-MITM-CA" >"$NODE_EXTRA_CA_CERTS"
    bundle=$(curl_ca_bundle)
    [ -n "$bundle" ]
    [ -f "$bundle" ]
    grep -q "FAKE-MITM-CA" "$bundle"
    rm -rf "$tmpdir"
}

@test "curl_ca_bundle: rebuilds when the extra cert changes" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir/acct"
    NODE_EXTRA_CA_CERTS="$tmpdir/mitm-ca.pem"
    echo "OLD-CA" >"$NODE_EXTRA_CA_CERTS"
    bundle=$(curl_ca_bundle)
    grep -q "OLD-CA" "$bundle"
    # Backdate the bundle so the -nt mtime comparison sees a newer cert
    # regardless of filesystem timestamp resolution.
    touch -t 200001010000 "$bundle"
    echo "NEW-CA" >"$NODE_EXTRA_CA_CERTS"
    bundle=$(curl_ca_bundle)
    grep -q "NEW-CA" "$bundle"
    ! grep -q "OLD-CA" "$bundle"
    rm -rf "$tmpdir"
}

@test "integration: rate-limited fetch shows !429 after quota, not bare !" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    echo '{"claudeAiOauth":{"accessToken":"fake"}}' > "$tmpdir/.claude/.credentials.json"
    now=$(date +%s)
    jq -n --argjson ts "$now" '{five_hour:{utilization:47},seven_day:{utilization:12},fetched_at:$ts}' >"$tmpdir/.claude/statusline/usage.cache"
    jq -n --argjson at "$now" '{at:$at,code:"429",count:2,cooldown:240}' >"$tmpdir/.claude/statusline/usage.err"
    result=$(echo '{"session_id":"sess-err","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.199"}' \
        | HOME="$tmpdir" CLAUDE_DATA_DIR="$tmpdir/.claude/statusline" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh")
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"5h[47%"* ]]
    [[ "$plain" == *"!429"* ]]
    rm -rf "$tmpdir"
}

@test "build_usage_display: 5h at 85% with reset in 20min uses recovery color" {
    reset_time=$(date -u -d '+20 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":85,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    [[ "$result" == *"$DIM_GREEN"* ]]
}

@test "build_usage_display: 5h at 85% with reset in 2h shows @ and warning color" {
    reset_time=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":85,\"resets_at\":\"$reset_time\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 5h\[85%@ ]]
    [[ "$result" != *"$DIM_GREEN"* ]]
}

# --- smart 7d reset time (absolute, day-of-week) ---

@test "build_usage_display: 7d at 30% hides reset even when imminent (gated on usage)" {
    reset_time=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+2d '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":30,\"resets_at\":\"$reset_time\"}}"
    plain=$(strip_ansi "$(build_usage_display "$usage" "")")
    [[ "$plain" == *"7d[30%]"* ]]
    [[ "$plain" != *"7d[30%@"* ]]
}

@test "build_usage_display: 7d at 30% with reset in 5d hides reset" {
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
    # ~4d elapsed at 75% => runway < deadline: a real warning, not recovery.
    reset_time=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_time\"}}"
    result=$(build_usage_display "$usage" "")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 7d\[75%@ ]]
    [[ "$result" != *"$DIM_GREEN"* ]]
}

# --- should_show_extra: auto mode ---

# --- should_show_extra: auto mode (recovery-aware) ---

@test "should_show_extra: auto shows when 5h >= 80 and reset distant" {
    run should_show_extra "auto" 85 50 0 7200 ""
    [ "$status" -eq 0 ]
}

@test "should_show_extra: auto shows when 5h >= 80 and no reset data" {
    run should_show_extra "auto" 85 50 0 "" ""
    [ "$status" -eq 0 ]
}

@test "should_show_extra: auto hides when 5h >= 80 but in recovery" {
    run should_show_extra "auto" 85 50 0 900 ""
    [ "$status" -eq 1 ]
}

@test "should_show_extra: auto shows when 7d >= 70 and reset distant" {
    run should_show_extra "auto" 10 75 0 "" 86400
    [ "$status" -eq 0 ]
}

@test "should_show_extra: auto hides when 7d >= 70 but in recovery" {
    run should_show_extra "auto" 10 75 0 "" 3600
    [ "$status" -eq 1 ]
}

@test "should_show_extra: auto shows when extra utilization >= 50%" {
    run should_show_extra "auto" 10 10 50 "" ""
    [ "$status" -eq 0 ]
}

@test "should_show_extra: auto hides when all below threshold" {
    run should_show_extra "auto" 50 40 49 "" ""
    [ "$status" -eq 1 ]
}

@test "should_show_extra: on-limit ignores recovery state" {
    run should_show_extra "on-limit" 85 10 80 900 ""
    [ "$status" -eq 0 ]
}

# --- get_cache_health ---

@test "get_cache_health: healthy session returns ok" {
    tmpdir=$(mktemp -d)
    echo "200000" > "$tmpdir/cache_health"
    result=$(get_cache_health 210000 173 1 "$tmpdir/cache_health")
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: cache break detected on large drop" {
    tmpdir=$(mktemp -d)
    echo "200000" > "$tmpdir/cache_health"
    result=$(get_cache_health 0 200100 1 "$tmpdir/cache_health")
    [[ "$result" == break\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: small drop is not a break" {
    tmpdir=$(mktemp -d)
    echo "200000" > "$tmpdir/cache_health"
    result=$(get_cache_health 199000 500 1 "$tmpdir/cache_health")
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: first turn with no state file returns ok" {
    tmpdir=$(mktemp -d)
    result=$(get_cache_health 50000 173 1 "$tmpdir/cache_health")
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: first turn with zero cache_read is building" {
    tmpdir=$(mktemp -d)
    result=$(get_cache_health 0 50000 1 "$tmpdir/cache_health")
    [[ "$result" == building\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: no tokens at all returns none" {
    result=$(get_cache_health 0 0 0 "")
    [ "$result" = "none" ]
}

@test "get_cache_health: empty strings treated as zero" {
    result=$(get_cache_health "" "" "" "")
    [ "$result" = "none" ]
}

@test "get_cache_health: previous zero baseline does not false-positive" {
    tmpdir=$(mktemp -d)
    echo "0" > "$tmpdir/cache_health"
    result=$(get_cache_health 50000 200 1 "$tmpdir/cache_health")
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: state file is updated after check" {
    tmpdir=$(mktemp -d)
    echo "100000" > "$tmpdir/cache_health"
    get_cache_health 150000 200 1 "$tmpdir/cache_health" >/dev/null
    stored=$(jq -r '.cache_read' "$tmpdir/cache_health")
    [ "$stored" = "150000" ]
    rm -rf "$tmpdir"
}

@test "get_cache_health: corrupt legacy state does not break arithmetic" {
    tmpdir=$(mktemp -d)
    echo "not-a-number" > "$tmpdir/cache_health"
    result=$(get_cache_health 0 50000 1 "$tmpdir/cache_health")
    [[ "$result" == building\|* ]]
    [ "$(jq -r '.cache_read' "$tmpdir/cache_health")" = "0" ]
    rm -rf "$tmpdir"
}

@test "get_cache_health: rebuilding after break (creation high, read zero)" {
    tmpdir=$(mktemp -d)
    echo "0" > "$tmpdir/cache_health"
    result=$(get_cache_health 0 50000 1 "$tmpdir/cache_health")
    [[ "$result" == building\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: drop below MIN_TOKENS threshold is not break" {
    tmpdir=$(mktemp -d)
    echo "3000" > "$tmpdir/cache_health"
    result=$(get_cache_health 1500 500 1 "$tmpdir/cache_health")
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: no state file path still works" {
    result=$(get_cache_health 50000 200 1 "")
    [[ "$result" == ok\|* ]]
}

@test "get_cache_health: creates parent directory for state file" {
    tmpdir=$(mktemp -d)
    nonexist="$tmpdir/no-such-dir/cache_health"
    result=$(get_cache_health 200000 200 1 "$nonexist")
    [[ "$result" == ok\|* ]]
    [ -f "$nonexist" ]
    result=$(get_cache_health 0 200100 1 "$nonexist")
    [[ "$result" == break\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: preserves ttl class and last active time" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1778728000
    export STATUSLINE_TEST_NOW_EPOCH
    result=$(get_cache_health 200000 0 1 "$tmpdir/cache_health" "1h")
    [[ "$result" == "ok|1h|1778728000|0" ]]
    [ "$(jq -r '.ttl_class' "$tmpdir/cache_health")" = "1h" ]
    [ "$(jq -r '.last_active_at' "$tmpdir/cache_health")" = "1778728000" ]
    unset STATUSLINE_TEST_NOW_EPOCH
    rm -rf "$tmpdir"
}

@test "get_cache_health: unchanged usage does not slide the expiry anchor" {
    # Renders also fire on vim/permission/model changes carrying the SAME
    # usage; re-stamping there would let a frozen frame claim a warm cache
    # after it already died (see the anchor comment in get_cache_health).
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health 200000 500 1 "$tmpdir/ch" >/dev/null
    result=$(STATUSLINE_TEST_NOW_EPOCH=4000 get_cache_health 200000 500 1 "$tmpdir/ch")
    [ "$result" = "ok||1000|0" ]
    [ "$(jq -r '.last_active_at' "$tmpdir/ch")" = "1000" ]
    rm -rf "$tmpdir"
}

@test "get_cache_health: changed usage re-stamps the expiry anchor" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health 200000 500 1 "$tmpdir/ch" >/dev/null
    STATUSLINE_TEST_NOW_EPOCH=1500 get_cache_health 200500 800 1 "$tmpdir/ch" >/dev/null
    [ "$(jq -r '.last_active_at' "$tmpdir/ch")" = "1500" ]
    rm -rf "$tmpdir"
}

@test "get_cache_health: activity after a gap past the TTL is a break (idle expiry)" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health 200000 500 1 "$tmpdir/ch" >/dev/null
    # 2h later the 1h cache is long dead. The read=0 rewrite frame was
    # skipped (300ms debounce) — the changed numbers + stale anchor alone
    # must flag the rewrite, sized at the re-cached prefix.
    result=$(STATUSLINE_TEST_NOW_EPOCH=8200 get_cache_health 201000 800 1 "$tmpdir/ch")
    [ "$result" = "break||8200|201800" ]
    rm -rf "$tmpdir"
}

@test "get_cache_health: activity within the TTL window is not a break" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health 200000 500 1 "$tmpdir/ch" >/dev/null
    result=$(STATUSLINE_TEST_NOW_EPOCH=3000 get_cache_health 201000 800 1 "$tmpdir/ch")
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: break is held for the notice window, then clears" {
    tmpdir=$(mktemp -d)
    echo "200000" > "$tmpdir/ch"
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health 0 200100 1 "$tmpdir/ch" >/dev/null
    # 30s later the cache is warm again, but the break notice must survive
    # the render that replaced the one-frame rewrite signal.
    result=$(STATUSLINE_TEST_NOW_EPOCH=1030 get_cache_health 200100 900 1 "$tmpdir/ch")
    [[ "$result" == break\|* ]]
    [[ "$result" == *"|200100" ]]
    result=$(STATUSLINE_TEST_NOW_EPOCH=1090 get_cache_health 200100 900 1 "$tmpdir/ch")
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: creation breakdown overrides ttl class" {
    tmpdir=$(mktemp -d)
    result=$(get_cache_health 0 50000 1 "$tmpdir/cache_health" "" 50000 0)
    [[ "$result" == building\|1h\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health: keeps last active time when current turn has no cache activity" {
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/cache_health" <<'JSON'
{"cache_read":200000,"ttl_class":"5m","last_active_at":1000}
JSON
    STATUSLINE_TEST_NOW_EPOCH=1740
    export STATUSLINE_TEST_NOW_EPOCH
    result=$(get_cache_health 0 0 1 "$tmpdir/cache_health")
    [[ "$result" == "break|5m|1000|0" ]]
    unset STATUSLINE_TEST_NOW_EPOCH
    rm -rf "$tmpdir"
}

@test "infer_cache_ttl_class: creation breakdown reports 1h" {
    result=$(infer_cache_ttl_class 100 0)
    [ "$result" = "1h" ]
}

@test "infer_cache_ttl_class: env vars alone are not proof" {
    FORCE_PROMPT_CACHING_5M=1 ENABLE_PROMPT_CACHING_1H=1 result=$(infer_cache_ttl_class 0 0)
    [ -z "$result" ]
}

@test "get_cache_health: partial cache-read drop is still a break signal" {
    tmpdir=$(mktemp -d)
    echo "200000" > "$tmpdir/cache_health"
    result=$(get_cache_health 180000 5000 1 "$tmpdir/cache_health")
    [[ "$result" == break\|* ]]
    rm -rf "$tmpdir"
}

@test "build_cache_indicator: auto stays silent while healthy (any size)" {
    # "quiet until it bites": the deadline is always ~1 TTL out mid-session,
    # so auto spends no width on it. Silent regardless of prefix size.
    [ -z "$(build_cache_indicator "ok|1h|1778728000|0" "auto")" ]
    [ -z "$(build_cache_indicator "ok||1778728000|0" "auto")" ]
}

@test "build_cache_indicator: always shows expiry deadline (anchor + observed ttl)" {
    result=$(TZ=UTC build_cache_indicator "ok|1h|1778728000|0" "always")
    plain=$(strip_ansi "$result")
    expected=$(TZ=UTC _fmt_epoch $((1778728000 + 3600)) '%H:%M')
    [ "$plain" = "${CACHE_GLYPH}:1h@${expected}" ]
}

@test "build_cache_indicator: unobserved ttl assumes the default, no class shown" {
    # bare @HH:MM = assumed TTL; the :1h/:5m provenance appears only when
    # the usage breakdown actually reported the class.
    result=$(TZ=UTC build_cache_indicator "ok||1778728000|0" "always")
    plain=$(strip_ansi "$result")
    expected=$(TZ=UTC _fmt_epoch $((1778728000 + 3600)) '%H:%M')
    [ "$plain" = "${CACHE_GLYPH}@${expected}" ]
}

@test "build_cache_indicator: building is a bare cache~ in auto" {
    result=$(build_cache_indicator "building|5m|1778728000|0" "auto")
    plain=$(strip_ansi "$result")
    [ "$plain" = "${CACHE_GLYPH}~" ]
}

@test "build_cache_indicator: building carries the deadline under --cache always" {
    result=$(TZ=UTC build_cache_indicator "building|5m|1778728000|0" "always")
    plain=$(strip_ansi "$result")
    expected=$(TZ=UTC _fmt_epoch $((1778728000 + 300)) '%H:%M')
    [ "$plain" = "${CACHE_GLYPH}:5m@${expected}~" ]
}

@test "build_cache_indicator: break shows the rewrite size" {
    result=$(build_cache_indicator "break|1h|1778728000|195000" "auto")
    plain=$(strip_ansi "$result")
    [ "$plain" = "${CACHE_GLYPH}!195k" ]
}

@test "build_cache_indicator: sub-1k break renders bare cache!" {
    result=$(build_cache_indicator "break|1h|1778728000|900" "auto")
    plain=$(strip_ansi "$result")
    [ "$plain" = "${CACHE_GLYPH}!" ]
}

@test "build_cache_indicator: a heavy (>200k) rewrite renders bold red" {
    # the >200k premium-band miss the user asked to highlight
    result=$(build_cache_indicator "break|1h|1778728000|419000" "auto")
    [ "$(strip_ansi "$result")" = "${CACHE_GLYPH}!419k" ]
    [[ "$result" == *'\033[1;31m'* ]]
}

@test "build_cache_indicator: a sub-200k rewrite stays plain red, not bold" {
    result=$(build_cache_indicator "break|1h|1778728000|150000" "auto")
    [[ "$result" != *'\033[1;31m'* ]]
    [[ "$result" == *'\033[0;31m'* ]]
}

# --- integration: cache health indicator ---

@test "integration: cache break shows cache! indicator" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo "200000" > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":200100,"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"${CACHE_GLYPH}!"* ]]
    rm -rf "$tmpdir"
}

@test "integration: healthy long-context cache stays silent in auto mode" {
    # "quiet until it bites": a warm 209k cache spends zero width. The
    # freeze-safe deadline is available on demand via --cache always
    # (asserted separately); auto shows nothing until the rewrite happens.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    # Fresh anchor: a stale one would (correctly) fire idle-expiry. This
    # asserts the warm, actively-worked case shows nothing.
    echo "{\"cache_read\":200000,\"last_active_at\":$(date +%s)}" > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":173,"cache_read_input_tokens":209703}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" != *"${CACHE_GLYPH}"* ]]
    rm -rf "$tmpdir"
}

@test "integration: --cache always surfaces the deadline on a warm cache" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo "{\"cache_read\":200000,\"ttl_class\":\"1h\",\"last_active_at\":$(date +%s)}" > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":173,"cache_read_input_tokens":209703}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test --cache always)
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ${CACHE_GLYPH}:1h@[0-9]{2}:[0-9]{2} ]]
    rm -rf "$tmpdir"
}

@test "integration: first turn building shows cache~" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":5,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":10,"cache_creation_input_tokens":50000,"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    # auto building is a bare marker (the deadline is --cache always only)
    [[ "$plain" == *"${CACHE_GLYPH}~"* ]]
    [[ "$plain" != *"@"* ]]
    rm -rf "$tmpdir"
}

@test "integration: first turn building with 1h breakdown shows ttl class" {
    # The ttl-class provenance rides on the deadline, which only --cache
    # always renders; auto building is a bare cache~.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":5,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":10,"cache_creation_input_tokens":50000,"cache_creation":{"ephemeral_1h_input_tokens":50000,"ephemeral_5m_input_tokens":0},"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test --cache always)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"${CACHE_GLYPH}:1h@"* ]]
    [[ "$plain" == *"~"* ]]
    rm -rf "$tmpdir"
}

@test "integration: --cache always shows healthy ttl metadata" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    # Anchor must be fresh: a stale anchor + new usage is (correctly) an
    # idle-expiry break now, which is not what this test is about.
    cat > "$tmpdir/sessions/test-session-id_cache_health" <<JSON
{"cache_read":200000,"ttl_class":"1h","last_active_at":$(date +%s)}
JSON
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":173,"cache_read_input_tokens":209703}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test --cache always)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"${CACHE_GLYPH}:1h@"* ]]
    rm -rf "$tmpdir"
}

@test "integration: --cache off hides cache break" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo "200000" > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":200100,"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test --cache off)
    plain=$(strip_ansi "$result")
    [[ "$plain" != *"${CACHE_GLYPH}!"* ]]
    [ "$(cat "$tmpdir/sessions/test-session-id_cache_health")" = "200000" ]
    rm -rf "$tmpdir"
}

# --- fresh-stdin-preferred quota + stale-lock reaping ----------------------

@test "merge_stdin_rate_limits: fresh stdin overrides stale cached 5h/7d" {
    stale='{"five_hour":{"utilization":100,"resets_at":"2026-06-10T11:00:00+00:00"},"seven_day":{"utilization":21}}'
    merged=$(merge_stdin_rate_limits "$stale" 4 1781097000 1 1781107200)
    [ "$(echo "$merged" | jq -r '.five_hour.utilization')" = "4" ]
    [ "$(echo "$merged" | jq -r '.seven_day.utilization')" = "1" ]
    [ "$(echo "$merged" | jq -r '.five_hour.resets_at')" = "1781097000" ]
}

@test "merge_stdin_rate_limits: expired stdin window does not clobber fresher cache" {
    # Observed live: an idle session's stdin still carried 33% on a 5h window
    # that reset 3h earlier, while the shared cache (fed by an active session)
    # had 47% on the CURRENT window. The cache's later resets_at must win.
    cache='{"five_hour":{"utilization":47,"resets_at":"2026-06-12T11:00:00+00:00"},"seven_day":{"utilization":39,"resets_at":"2026-06-17T16:00:01+00:00"}}'
    merged=$(merge_stdin_rate_limits "$cache" 33 1781244000 28 1781712000)
    [ "$(echo "$merged" | jq -r '.five_hour.utilization')" = "47" ]
    [ "$(echo "$merged" | jq -r '.five_hour.resets_at')" = "2026-06-12T11:00:00+00:00" ]
}

@test "merge_stdin_rate_limits: same window takes the max utilization" {
    # Within one window usage only increases, so the larger reading is the
    # fresher one regardless of which source it came from.
    cache='{"five_hour":{"utilization":46,"resets_at":1781262000},"seven_day":{"utilization":38,"resets_at":1781712000}}'
    merged=$(merge_stdin_rate_limits "$cache" 43 1781262000 39 1781712000)
    [ "$(echo "$merged" | jq -r '.five_hour.utilization')" = "46" ]  # cache fresher
    [ "$(echo "$merged" | jq -r '.seven_day.utilization')" = "39" ]  # stdin fresher
}

@test "merge_stdin_rate_limits: stdin with a newer window wins (reset rolled)" {
    cache='{"five_hour":{"utilization":98,"resets_at":1781244000},"seven_day":{"utilization":21,"resets_at":1781712000}}'
    merged=$(merge_stdin_rate_limits "$cache" 2 1781262000 21 1781712000)
    [ "$(echo "$merged" | jq -r '.five_hour.utilization')" = "2" ]
    [ "$(echo "$merged" | jq -r '.five_hour.resets_at')" = "1781262000" ]
}

@test "merge_stdin_rate_limits: preserves cache-only fields (extra_usage, opus)" {
    stale='{"five_hour":{"utilization":100},"seven_day":{"utilization":21},"extra_usage":{"is_enabled":true,"utilization":12},"seven_day_opus":{"utilization":9}}'
    merged=$(merge_stdin_rate_limits "$stale" 4 "" 1 "")
    [ "$(echo "$merged" | jq -r '.extra_usage.utilization')" = "12" ]
    [ "$(echo "$merged" | jq -r '.seven_day_opus.utilization')" = "9" ]
}

@test "merge_stdin_rate_limits: missing stdin value leaves that window untouched" {
    stale='{"five_hour":{"utilization":100},"seven_day":{"utilization":21}}'
    # only 5h provided; 7d should keep the cached value
    merged=$(merge_stdin_rate_limits "$stale" 4 1781097000 "" "")
    [ "$(echo "$merged" | jq -r '.five_hour.utilization')" = "4" ]
    [ "$(echo "$merged" | jq -r '.seven_day.utilization')" = "21" ]
}

@test "reap_stale_lock: removes a lock older than max age" {
    tmpdir=$(mktemp -d)
    lock="$tmpdir/usage.lock"
    touch "$lock"
    touch -d '@1' "$lock" 2>/dev/null || touch -t 200001010000 "$lock"
    reap_stale_lock "$lock" 15
    [ ! -f "$lock" ]
    rm -rf "$tmpdir"
}

@test "reap_stale_lock: keeps a fresh lock (fetch genuinely in flight)" {
    tmpdir=$(mktemp -d)
    lock="$tmpdir/usage.lock"
    touch "$lock"
    reap_stale_lock "$lock" 15
    [ -f "$lock" ]
    rm -rf "$tmpdir"
}

# --- acquire_lock: atomic fetch gate (multi-instance 429 stampede) ----------

@test "acquire_lock: acquires when no lock exists" {
    tmpdir=$(mktemp -d)
    acquire_lock "$tmpdir/usage.lock" 10
    [ -f "$tmpdir/usage.lock" ]
    rm -rf "$tmpdir"
}

@test "acquire_lock: fails while a fresh lock is held" {
    tmpdir=$(mktemp -d)
    touch "$tmpdir/usage.lock"
    ! acquire_lock "$tmpdir/usage.lock" 10
    rm -rf "$tmpdir"
}

@test "acquire_lock: reaps and takes over a stale lock" {
    tmpdir=$(mktemp -d)
    lock="$tmpdir/usage.lock"
    touch "$lock"
    touch -d '@1' "$lock" 2>/dev/null || touch -t 200001010000 "$lock"
    acquire_lock "$lock" 10
    [ -f "$lock" ]
    rm -rf "$tmpdir"
}

@test "acquire_lock: exactly one winner under concurrent contention" {
    tmpdir=$(mktemp -d)
    lock="$tmpdir/usage.lock"
    winners="$tmpdir/winners"
    for i in $(seq 1 20); do
        ( acquire_lock "$lock" 60 && echo "$i" >> "$winners" ) 3>&- &
    done
    wait
    [ -f "$winners" ]
    [ "$(wc -l < "$winners")" -eq 1 ]
    rm -rf "$tmpdir"
}

@test "fetch_usage_for_session: concurrent renders make exactly one API call" {
    # Recreates the multi-instance launch stampede: the slow token read is
    # the window where the old check-then-touch let every instance through.
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    CURL_CALLS="$tmpdir/curl_calls"
    get_oauth_token() { sleep 0.1; echo "test-token"; }
    log_usage_snapshot() { :; }
    build_seven_day_profile() { :; }
    curl() {
        sleep 0.5
        echo x >> "$CURL_CALLS"
        printf '{"five_hour":{"utilization":10},"seven_day":{"utilization":5}}\n200 '
    }
    for i in $(seq 1 8); do
        fetch_usage_for_session "s$i" >/dev/null 2>&1 3>&- &
    done
    wait
    [ "$(wc -l < "$CURL_CALLS")" -eq 1 ]
    [ -f "$tmpdir/usage.cache" ]
    [ "$(jq -r '.five_hour.utilization' "$tmpdir/usage.cache")" = "10" ]
    [ ! -f "$tmpdir/usage.lock" ]
    rm -rf "$tmpdir"
}

# --- effort badge ----------------------------------------------------------

@test "abbrev_effort: levels map to compact badges" {
    [ "$(abbrev_effort low)" = "lo" ]
    [ "$(abbrev_effort medium)" = "md" ]
    [ "$(abbrev_effort xhigh)" = "xh" ]
    [ "$(abbrev_effort max)" = "max" ]
    [ "$(abbrev_effort ultracode)" = "ultra" ]
    [ "$(abbrev_effort auto)" = "auto" ]
}

@test "effort_color: expensive modes warn, others dim" {
    [ "$(effort_color max)" = "$YELLOW" ]
    [ "$(effort_color ultracode)" = "$YELLOW" ]
    [ "$(effort_color xhigh)" = "$DIM" ]
    [ "$(effort_color low)" = "$DIM" ]
}

@test "integration: --test renders effort badge xh, hides default high" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    xh=$(echo '{"model":{"id":"claude-fable-5","display_name":"F"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.170","effort":{"level":"xhigh"}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    # fable now carries [1m] (family default), so the bracket is the separator
    # and the badge attaches without a space: fabl5[1m]xh.
    [[ "$(strip_ansi "$xh")" == *"fabl5[1m]xh"* ]]
    hi=$(echo '{"model":{"id":"claude-fable-5","display_name":"F"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.170","effort":{"level":"high"}}' \
        | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    [[ "$(strip_ansi "$hi")" != *"hi"* ]]
    rm -rf "$tmpdir"
}

# --- portable date helpers (GNU + BSD fallback) ----------------------------

@test "_epoch_from_ts: passes through a bare epoch" {
    [ "$(_epoch_from_ts 1781097000)" = "1781097000" ]
}

@test "_epoch_from_ts: parses an ISO-8601 timestamp to epoch" {
    result=$(_epoch_from_ts "2026-06-10T13:10:01+00:00")
    [[ "$result" =~ ^[0-9]+$ ]]
    [ "$result" -gt 1700000000 ]
}

@test "_epoch_from_ts: empty/null yields empty" {
    [ -z "$(_epoch_from_ts "")" ]
    [ -z "$(_epoch_from_ts null)" ]
}

@test "_fmt_epoch: formats an epoch with a strftime pattern" {
    result=$(_fmt_epoch 1781097000 '%H:%M')
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}$ ]]
}

# --- 7d reset gating -------------------------------------------------------

@test "build_usage_display: 7d reset hidden at low usage (no @time noise)" {
    reset_time=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+2d '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":1,\"resets_at\":\"$reset_time\"}}"
    plain=$(strip_ansi "$(build_usage_display "$usage" "")")
    [[ "$plain" == *"7d[1%]"* ]]
    [[ "$plain" != *"7d[1%@"* ]]
}

# --- malformed-stdin degrades cleanly --------------------------------------

@test "integration: empty stdin does not fabricate +/- 0m \$0" {
    tmpdir=$(mktemp -d)
    out=$(printf '' | HOME="$tmpdir" CLAUDE_CACHE_DIR="$tmpdir/s" bash "$SCRIPT_DIR/statusline.sh" 2>/dev/null)
    plain=$(strip_ansi "$out")
    [[ "$plain" != *'$0'* ]]
    [[ "$plain" != *'0m'* ]]
    [[ "$plain" != *'+/-'* ]]
    rm -rf "$tmpdir"
}

@test "integration: sub-cent cost is not shown as \$0" {
    out=$(echo '{"model":{"id":"claude-fable-5","display_name":"F"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.170","cost":{"total_cost_usd":0.004}}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    [[ "$(strip_ansi "$out")" != *'$0'* ]]
}

# --- account scoping (multi-account credential overlays) --------------------

@test "integration: DEVA_AUTH_TAG renders account chip" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" DEVA_AUTH_TAG="auth-file-work" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" == *"[@work]"* ]]
    rm -rf "$tmpdir"
}

@test "integration: auth-default tag renders no chip" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" DEVA_AUTH_TAG="auth-default" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" != *"@"* ]]
    rm -rf "$tmpdir"
}

@test "integration: STATUSLINE_ACCOUNT beats DEVA_AUTH_TAG" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" STATUSLINE_ACCOUNT="self" DEVA_AUTH_TAG="auth-file-work" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" == *"[@self]"* ]]
    [[ "$plain" != *"@work"* ]]
    rm -rf "$tmpdir"
}

@test "integration: hostile tag is neutralized, no chip, no scoping" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" DEVA_AUTH_TAG="../../evil" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" != *"@"* ]]
    [ ! -e "$tmpdir/.claude/statusline/accounts" ]
    rm -rf "$tmpdir"
}

@test "integration: tagged session reads quota from its scoped cache, not the shared one" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline/accounts/work"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    now=$(date +%s)
    # Decoy in the legacy shared location: a fresh cache for the OTHER account.
    printf '{"five_hour":{"utilization":77},"seven_day":{"utilization":77},"fetched_at":%s}' "$now" \
        > "$tmpdir/.claude/statusline/usage.cache"
    printf '{"five_hour":{"utilization":42},"seven_day":{"utilization":41},"fetched_at":%s}' "$now" \
        > "$tmpdir/.claude/statusline/accounts/work/usage.cache"
    out=$(echo '{"session_id":"acct-test","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" DEVA_AUTH_TAG="auth-file-work" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" == *"5h[42%]"* ]]
    [[ "$plain" != *"77%"* ]]
    rm -rf "$tmpdir"
}

@test "integration: untagged session still reads the shared cache (back-compat)" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    printf '{"five_hour":{"utilization":33},"seven_day":{"utilization":31},"fetched_at":%s}' "$(date +%s)" \
        > "$tmpdir/.claude/statusline/usage.cache"
    out=$(echo '{"session_id":"acct-test2","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" == *"5h[33%]"* ]]
    rm -rf "$tmpdir"
}

# --- advisor line (second row) ---

@test "build_advisor_line: calm windows stay silent in auto" {
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":20,\"resets_at\":\"$reset_7d\"}}"
    [ -z "$(build_advisor_line "$usage" auto)" ]
}

@test "build_advisor_line: calm windows show weekly budget in always" {
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":20,\"resets_at\":\"$reset_7d\"}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" always)")
    [[ "$plain" =~ ^-\ ~24x5h\ left,\ even\ pace\ 3\.3%/win,\ heading\ ~70%$ ]]
}

@test "build_advisor_line: hot 5h pace projects the cap wall-clock" {
    # 85% only 2h into the window (3h left): pace ~2.1x, caps well before reset
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":85,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^!\ 5h\ caps\ ~[0-9]{2}:[0-9]{2},\ .*\ before\ reset$ ]]
    [[ "$result" == *'\033[0;33m'* ]]
}

@test "build_advisor_line: 5h at 92% escalates the row to red" {
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":92,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_advisor_line "$usage" auto)
    [[ "$result" == *'\033[0;31m'* ]]
}

@test "build_advisor_line: on-pace 5h stays silent even at 85%" {
    # 85% with 45m left = 85% elapsed: pace ~1.0, window outlasts the burn
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":85,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":10}}"
    [ -z "$(build_advisor_line "$usage" auto)" ]
}

@test "build_advisor_line: imminent 5h reset suppresses the projection (recovery)" {
    reset_5h=$(date -u -d '+20 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":95,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":10}}"
    [ -z "$(build_advisor_line "$usage" auto)" ]
}

@test "build_advisor_line: capped 5h adds no clause (line 1 already says it)" {
    reset_5h=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":100,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":10}}"
    [ -z "$(build_advisor_line "$usage" auto)" ]
}

@test "build_advisor_line: pace-hot 7d projects dry point with hard-stop tail" {
    # 75% burned with 2.2d left (~4.8d elapsed): seven_day_pace warns
    reset_7d=$(date -u -d '+2 days 5 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_7d\"}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" auto)")
    [[ "$plain" =~ ^!\ 7d\ caps\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2},\ .*\ before\ reset ]]
    [[ "$plain" == *"then hard stop"* ]]
}

@test "build_advisor_line: extra-usage billing changes the 7d tail" {
    reset_7d=$(date -u -d '+2 days 5 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_7d\"},\"extra_usage\":{\"is_enabled\":true}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" auto)")
    [[ "$plain" == *"then extra billing"* ]]
}

@test "build_advisor_line: off mode is silent under any pressure" {
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":95,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":95}}"
    [ -z "$(build_advisor_line "$usage" off)" ]
}

@test "build_advisor_fleet_hint: picks idlest fresh sibling, skips self and stale" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/accounts/work" "$tmpdir/accounts/alt" "$tmpdir/accounts/idle-but-stale"
    now=$(date +%s)
    printf '{"fetched_at":%s,"five_hour":{"utilization":95}}' "$now" > "$tmpdir/accounts/work/usage.cache"
    printf '{"fetched_at":%s,"five_hour":{"utilization":8}}' "$now" > "$tmpdir/accounts/alt/usage.cache"
    printf '{"fetched_at":%s,"five_hour":{"utilization":2}}' "$((now - 7200))" > "$tmpdir/accounts/idle-but-stale/usage.cache"
    result=$(build_advisor_fleet_hint "$tmpdir/accounts" "work")
    [ "$result" = "alt 5h[8%] free" ]
    rm -rf "$tmpdir"
}

@test "build_advisor_fleet_hint: no free sibling means no hint" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/accounts/alt"
    printf '{"fetched_at":%s,"five_hour":{"utilization":88}}' "$(date +%s)" > "$tmpdir/accounts/alt/usage.cache"
    [ -z "$(build_advisor_fleet_hint "$tmpdir/accounts" "work")" ]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: capped account with tagged fleet points at the free sibling (cyan)" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/accounts/alt"
    printf '{"fetched_at":%s,"five_hour":{"utilization":8}}' "$(date +%s)" > "$tmpdir/accounts/alt/usage.cache"
    reset_5h=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":100,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":10}}"
    result=$(STATUSLINE_HOME="$tmpdir" ACCOUNT_TAG="work" build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    [[ "$plain" == "+ alt 5h[8%] free" ]]
    [[ "$result" == *'\033[0;36m'* ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: expiring surplus states the bare fact while the ratio is unlearned" {
    # No forecast.cache => no pct_per_window => no advice tail. "spend it"
    # without a feasibility model would be a guess, not advice.
    reset_5h=$(date -u -d '+4 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":44,\"resets_at\":\"$reset_7d\"}}"
    result=$(build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^\+\ 7d\ resets\ @[0-9]{2}:[0-9]{2},\ 56%\ unused$ ]]
    [[ "$result" == *'\033[0;36m'* ]]
}

_write_ppw_fixture() { # dir ppw
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"pct_per_window":%s,"weekday_profile":{"0":-1,"1":-1,"2":-1,"3":-1,"4":-1,"5":-1,"6":-1}}' "$2" > "$1/forecast.cache"
}

@test "build_advisor_line: reachable surplus advises spend-it once the ratio is learned" {
    tmpdir=$(mktemp -d)
    _write_ppw_fixture "$tmpdir" 30
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+20 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":65,\"resets_at\":\"$reset_7d\"}}"
    plain=$(CLAUDE_ACCOUNT_DIR="$tmpdir" strip_ansi "$(CLAUDE_ACCOUNT_DIR="$tmpdir" build_advisor_line "$usage" auto)")
    [[ "$plain" =~ ^\+\ 7d\ resets\ @[0-9]{2}:[0-9]{2},\ 35%\ unused\ —\ spend\ it$ ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: unreachable surplus states what expires even at full burn" {
    # The impossible-advice failure: ~1 window left cannot spend half a
    # week. ppw=12, 5h at 95% with 55m left, 7d resets in 2h: reachable
    # ~= min(2.2, 0.6) + 2.6 ~= 3 points, so ~53 of the 56 are already gone.
    tmpdir=$(mktemp -d)
    _write_ppw_fixture "$tmpdir" 12
    reset_5h=$(date -u -d '+55 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":95,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":44,\"resets_at\":\"$reset_7d\"}}"
    result=$(CLAUDE_ACCOUNT_DIR="$tmpdir" build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ 7d\ resets\ @[0-9]{2}:[0-9]{2},\ 56%\ unused\ —\ ~53%\ expires\ even\ at\ full\ burn ]]
    [[ "$plain" != *"spend it"* ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: hot 5h + expiring surplus pair into one coherent story" {
    # The utilization-gap failure: 5h nearly spent, 7d resets an hour later
    # with half the week unused. Both facts, one row, pressure color.
    reset_5h=$(date -u -d '+55 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":95,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":44,\"resets_at\":\"$reset_7d\"}}"
    result=$(build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^!\ 5h\ caps\ ~[0-9]{2}:[0-9]{2},\ .*\ before\ reset\;\ 7d\ resets\ @[0-9]{2}:[0-9]{2},\ 56%\ unused$ ]]
    [[ "$plain" != *"spend it"* ]]
    [[ "$result" == *'\033[0;31m'* ]]
}

@test "build_advisor_line: small surplus near reset stays quiet" {
    reset_7d=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20},\"seven_day\":{\"utilization\":80,\"resets_at\":\"$reset_7d\"}}"
    [ -z "$(build_advisor_line "$usage" auto)" ]
}

@test "build_advisor_line: mid-week underuse advises going heavier in an engaged session" {
    reset_7d=$(date -u -d '+2 days 12 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":40},\"seven_day\":{\"utilization\":25,\"resets_at\":\"$reset_7d\"}}"
    result=$(build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^\+\ 7d\ on\ pace\ to\ leave\ ~62%\ unused\ —\ go\ heavier$ ]]
    [[ "$result" == *'\033[0;36m'* ]]
}

@test "build_advisor_line: underuse stays quiet in an idle session" {
    reset_7d=$(date -u -d '+2 days 12 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":25,\"resets_at\":\"$reset_7d\"}}"
    [ -z "$(build_advisor_line "$usage" auto)" ]
}

@test "build_advisor_line: underuse stays quiet in the first half of the week (cold)" {
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":40},\"seven_day\":{\"utilization\":10,\"resets_at\":\"$reset_7d\"}}"
    [ -z "$(build_advisor_line "$usage" auto)" ]
}

@test "build_advisor_line: learned profile warns of underuse before linear pace can" {
    # Day 2.5 of the week — linear pace needs half the window, but a trained
    # profile (2%/day) already knows the remaining 4.5 days only burn ~9
    # more points: heading ~29%, so ~71% would be stranded.
    tmpdir=$(mktemp -d)
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"pct_per_window":-1,"weekday_profile":{"0":2,"1":2,"2":2,"3":2,"4":2,"5":2,"6":2}}' > "$tmpdir/forecast.cache"
    reset_7d=$(date -u -d '+4 days 12 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":40},\"seven_day\":{\"utilization\":20,\"resets_at\":\"$reset_7d\"}}"
    plain=$(CLAUDE_ACCOUNT_DIR="$tmpdir" strip_ansi "$(CLAUDE_ACCOUNT_DIR="$tmpdir" build_advisor_line "$usage" auto)")
    [[ "$plain" =~ ^\+\ 7d\ on\ pace\ to\ leave\ ~7[01]%\ unused\ —\ go\ heavier$ ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: capped scoped limit names the model and its return time" {
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    reset_sc=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20},\"seven_day\":{\"utilization\":20,\"resets_at\":\"$reset_7d\"},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":100,\"resets_at\":\"$reset_sc\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    result=$(build_advisor_line "$usage" auto "claude-fable-5")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^!\ fb\ capped\ —\ back\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2}$ ]]
    [[ "$result" == *'\033[0;31m'* ]]
}

@test "build_advisor_line: scoped-limit pace projects the model cap before its reset" {
    reset_sc=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20},\"seven_day\":{\"utilization\":20},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":92,\"resets_at\":\"$reset_sc\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    result=$(build_advisor_line "$usage" auto "claude-fable-5")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^!\ fb\ caps\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2},\ .*\ before\ reset$ ]]
    [[ "$result" == *'\033[0;31m'* ]]
}

@test "build_advisor_line: scoped limit for another model stays out of this session" {
    reset_sc=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20},\"seven_day\":{\"utilization\":20},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":100,\"resets_at\":\"$reset_sc\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    [ -z "$(build_advisor_line "$usage" auto "claude-opus-4-8")" ]
}

@test "integration: advisor row appears under hot 5h pace and collapses when calm" {
    tmpdir=$(mktemp -d)
    # Anchor CLAUDE_HOME inside the sandbox: without $tmpdir/.claude the
    # script's getent fallback resolves to the REAL home and the advisor
    # reads live account data.
    mkdir -p "$tmpdir/.claude"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    _mk_input() {
        printf '{"session_id":"adv","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"context_window":{"used_percentage":10,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":"%s"},"seven_day":{"used_percentage":10,"resets_at":"%s"}}}' "$1" "$reset_5h" "$reset_7d"
    }
    hot=$(_mk_input 85 | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh")
    [ "$(printf '%s\n' "$hot" | wc -l)" -eq 2 ]
    [[ "$(strip_ansi "$hot")" == *"5h caps ~"* ]]
    calm=$(_mk_input 20 | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh")
    [ "$(printf '%s\n' "$calm" | wc -l)" -eq 1 ]
    rm -rf "$tmpdir"
}

@test "integration: --advisor off keeps a single row under pressure" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    out=$(printf '{"session_id":"adv2","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":"%s"}}}' "$reset_5h" \
        | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh" --advisor off)
    [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ]
    rm -rf "$tmpdir"
}

@test "integration: advisor row right-aligns to the stats anchor" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    # TERM=dumb forces the tput fallback (term_width=80): line 2 must end at
    # the stats anchor, column 75 (term_width - 5), padded from the left.
    out=$(printf '{"session_id":"adv3","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":"%s"}}}' "$reset_5h" \
        | HOME="$tmpdir" TERM=dumb bash "$SCRIPT_DIR/statusline.sh")
    line2=$(printf '%s\n' "$out" | sed -n '2p')
    plain=$(strip_ansi "$line2")
    [ "${#plain}" -eq 75 ]
    [[ "$plain" =~ ^\ +!\ 5h\ caps\ ~ ]]
    rm -rf "$tmpdir"
}

@test "integration: pre-v0.18-deva env (DETAILS, no TAG) still resolves the account" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" DEVA_AUTH_METHOD="credentials-file" \
          DEVA_AUTH_DETAILS="credentials-file (/cfg/work.credentials.json)" \
          bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" == *"[@work]"* ]]
    rm -rf "$tmpdir"
}

@test "integration: provisioning-variant DEVA_AUTH_DETAILS resolves the stem" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" DEVA_AUTH_METHOD="credentials-file" \
          DEVA_AUTH_DETAILS="credentials-file (provisioning: /cfg/work.credentials.json)" \
          bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" == *"[@work]"* ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_fleet_hint: corrupt sibling cache does not inherit the previous sibling's numbers" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/a" "$tmpdir/b"
    now=$(date +%s)
    printf '{"five_hour":{"utilization":8},"fetched_at":%s}' "$now" > "$tmpdir/a/usage.cache"
    printf 'not json' > "$tmpdir/b/usage.cache"
    result=$(build_advisor_fleet_hint "$tmpdir" "self")
    [ "$result" = "a 5h[8%] free" ]
    rm -rf "$tmpdir"
}
