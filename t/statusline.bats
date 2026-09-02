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

@test "abbreviate_model_id: fable-5-1 -> fabl5.1 (the minor Fable grew on 2026-09-01)" {
    result=$(abbreviate_model_id "claude-fable-5-1")
    [ "$result" = "fabl5.1" ]
}

@test "abbreviate_model_id: fable-5-1 with date suffix -> fabl5.1" {
    result=$(abbreviate_model_id "claude-fable-5-1-20260901")
    [ "$result" = "fabl5.1" ]
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
    ts=$(date -u -d '+2 days 5 hours 30 seconds' '+%Y-%m-%dT%H:%M:%SZ')
    result=$(format_reset_relative "$ts")
    [ "$result" = "2d5h" ]
}

@test "format_reset_relative: hours and minutes" {
    ts=$(date -u -d '+3 hours 30 minutes 30 seconds' '+%Y-%m-%dT%H:%M:%SZ')
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
    epoch=$(date -d '+2 hours 30 minutes 30 seconds' +%s)
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

# A learned profile for the model-scoped weekly cap: every weekday burns
# $3 percent of it, and $4 is the last 24h. days_history is the ALL-model
# count — the scoped series rides the same scan.
_write_scoped_profile_cache() { # dir days rate recent24 scope_name
    cat > "$1/forecast.cache" <<EOF
{"schema":$FORECAST_SCHEMA,"computed_at":$(date +%s),"days_history":$2,"recent_24h":0,"recent_48h":0,
 "weekday_profile":{"0":-1,"1":-1,"2":-1,"3":-1,"4":-1,"5":-1,"6":-1},
 "scoped_name":"$5","scoped_recent_24h":$4,
 "scoped_profile":{"0":$3,"1":$3,"2":$3,"3":$3,"4":$3,"5":$3,"6":$3}}
EOF
}

@test "build_seven_day_profile: a stale dip is not a refund" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    now=$(date +%s)
    : > "$tmpdir/usage.jsonl"
    # 10 -> 30 -> 50, then ONE sample at 4 (an idle session reporting the
    # window it last saw), then 54. Real burn: 44. Summing positive deltas
    # reads 90 — the dip is refunded and then re-earned.
    i=0
    for u in 10 30 50 4 54; do
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":%s}}\n' \
            "$(( now - 3600 + i * 60 ))" "$u" >> "$tmpdir/usage.jsonl"
        i=$(( i + 1 ))
    done
    build_seven_day_profile
    [ "$(jq -r '.recent_24h' "$tmpdir/forecast.cache")" = "44.00" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: a confirmed reset re-baselines, mid-window and all" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    now=$(date +%s)
    : > "$tmpdir/usage.jsonl"
    # The counter really can go back to zero with resets_at UNCHANGED (seen
    # 2026-08-17: 100 -> 0, same reset instant). A sustained, deep drop is a
    # reset: 40 before it, 20 after, 60 total — and nothing credited for the
    # fall itself.
    i=0
    for u in 10 30 50 0 0 20; do
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":%s,"resets_at":"2026-08-19T16:00:00+00:00"}}\n' \
            "$(( now - 3600 + i * 60 ))" "$u" >> "$tmpdir/usage.jsonl"
        i=$(( i + 1 ))
    done
    build_seven_day_profile
    [ "$(jq -r '.recent_24h' "$tmpdir/forecast.cache")" = "60.00" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: learns the model-scoped weekly cap too" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    now=$(date +%s)
    : > "$tmpdir/usage.jsonl"
    i=0
    for u in 5 25 60 12 90; do
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":1},"limits":[{"kind":"weekly_scoped","percent":%s,"scope":{"model":{"display_name":"Fable"}}}]}\n' \
            "$(( now - 3600 + i * 60 ))" "$u" >> "$tmpdir/usage.jsonl"
        i=$(( i + 1 ))
    done
    build_seven_day_profile
    [ "$(jq -r '.scoped_name' "$tmpdir/forecast.cache")" = "Fable" ]
    # 5 -> 90 with one stale dip (12) held: 85, not 85+78.
    [ "$(jq -r '.scoped_recent_24h' "$tmpdir/forecast.cache")" = "85.00" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: no scoped samples leaves the scoped profile unlearned" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_forecast_fixture "$tmpdir" 16
    build_seven_day_profile
    [ "$(jq -r '.scoped_name' "$tmpdir/forecast.cache")" = "null" ]
    [ "$(jq -r '.scoped_profile["1"]' "$tmpdir/forecast.cache")" = "-1.00" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: prices a 7d point from paired samples" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    now=$(date +%s)
    # Two sessions interleaved. cost_usd is cumulative PER SESSION, so the
    # raw column goes 1, 2, 9, 12, 15 — deltas of that are nonsense. Per
    # session: s1 1->9->15 (+14), s2 2->12 (+10) = $24. 7d 10->30 with the
    # first sample a baseline = 20 paired points. $1.20 a point.
    : > "$tmpdir/usage.jsonl"
    i=0
    for spec in "10 s1 1.0" "15 s2 2.0" "20 s1 9.0" "25 s2 12.0" "30 s1 15.0"; do
        set -- $spec
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":%s},"session_id":"%s","session":{"cost_usd":%s}}\n' \
            "$(( now - 3000 + i * 300 ))" "$1" "$2" "$3" >> "$tmpdir/usage.jsonl"
        i=$(( i + 1 ))
    done
    build_seven_day_profile
    [ "$(jq -r '.cost.usd_24h' "$tmpdir/forecast.cache")" = "24.00" ]
    [ "$(jq -r '.cost.paired_pct' "$tmpdir/forecast.cache")" = "20.0" ]
    [ "$(jq -r '.cost.usd_per_pct' "$tmpdir/forecast.cache")" = "1.2000" ]
    [ "$(CLAUDE_ACCOUNT_DIR="$tmpdir" forecast_usd_per_pct)" = "1.2000" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: quota points with no dollars beside them are never priced" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    now=$(date +%s)
    # months of quota history with no session block: the denominator must not
    # borrow those points, or a week prices at pennies.
    : > "$tmpdir/usage.jsonl"
    for (( d = 40; d >= 1; d-- )); do
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":10}}\n' "$(( now - d * 86400 ))"
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":40}}\n' "$(( now - d * 86400 + 3600 ))"
    done >> "$tmpdir/usage.jsonl"
    build_seven_day_profile
    [ "$(jq -r '.cost.usd_per_pct' "$tmpdir/forecast.cache")" = "-1.0000" ]
    [ "$(jq -r '.cost.paired_pct' "$tmpdir/forecast.cache")" = "0.0" ]
    [ -z "$(CLAUDE_ACCOUNT_DIR="$tmpdir" forecast_usd_per_pct)" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: stamps the schema it wrote" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_forecast_fixture "$tmpdir" 21
    build_seven_day_profile
    [ "$(jq -r '.schema' "$tmpdir/forecast.cache")" = "$FORECAST_SCHEMA" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: a fresh cache of this schema is left alone" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_forecast_fixture "$tmpdir" 21
    build_seven_day_profile
    before=$(jq -r '.computed_at' "$tmpdir/forecast.cache")
    jq --argjson t "$(( before - 60 ))" '.computed_at = $t' "$tmpdir/forecast.cache" > "$tmpdir/f" \
        && mv "$tmpdir/f" "$tmpdir/forecast.cache"
    build_seven_day_profile
    [ "$(jq -r '.computed_at' "$tmpdir/forecast.cache")" = "$(( before - 60 ))" ]
    rm -rf "$tmpdir"
}

# The shared-store defence. A co-writer that summed raw deltas published
# 149%/day into Thursday and dropped pct_per_window on the way past; the
# walk's corrupt-profile guard caught the 149 and went silent for the rest
# of the hour. Freshness alone cannot be the gate on a file more than one
# tool writes — the shape has to match too.
@test "build_seven_day_profile: a fresh cache of a foreign shape is rebuilt on sight" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_forecast_fixture "$tmpdir" 21
    cat > "$tmpdir/forecast.cache" <<EOF
{"computed_at":$(date +%s),"days_history":251,"recent_24h":18,"recent_48h":21,
 "weekday_profile":{"0":11,"1":29,"2":59,"3":149.11,"4":17,"5":11,"6":11}}
EOF
    build_seven_day_profile
    [ "$(jq -r '.schema' "$tmpdir/forecast.cache")" = "$FORECAST_SCHEMA" ]
    [ "$(jq -r '.pct_per_window' "$tmpdir/forecast.cache")" != "null" ]
    thu=$(jq -r '.weekday_profile["3"]' "$tmpdir/forecast.cache")
    awk -v p="$thu" 'BEGIN{exit !(p >= 0 && p <= 100)}'
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: an older statusline's unversioned cache is rebuilt too" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_forecast_fixture "$tmpdir" 21
    printf '{"computed_at":%s,"days_history":21,"recent_24h":0,"recent_48h":0,"pct_per_window":9,"weekday_profile":{"0":1,"1":1,"2":1,"3":1,"4":1,"5":1,"6":1}}\n' \
        "$(date +%s)" > "$tmpdir/forecast.cache"
    build_seven_day_profile
    [ "$(jq -r '.schema' "$tmpdir/forecast.cache")" = "$FORECAST_SCHEMA" ]
    mon=$(jq -r '.weekday_profile["1"]' "$tmpdir/forecast.cache")
    awk -v p="$mon" 'BEGIN{exit !(p >= 19 && p <= 21)}'
    rm -rf "$tmpdir"
}

@test "forecast_usd_per_pct: no cache, no price, no error" {
    tmpdir=$(mktemp -d)
    [ -z "$(CLAUDE_ACCOUNT_DIR="$tmpdir" forecast_usd_per_pct)" ]
    printf '{"computed_at":0}' > "$tmpdir/forecast.cache"
    [ -z "$(CLAUDE_ACCOUNT_DIR="$tmpdir" forecast_usd_per_pct)" ]
    rm -rf "$tmpdir"
}

@test "scoped_forecast: the learned walk warns where linear pace cannot" {
    tmpdir=$(mktemp -d)
    # 45% used with 4 days left is calm to a straight line — pace says you
    # land near 79%. The profile says 20%/day, so the cap arrives on day 3.
    _write_scoped_profile_cache "$tmpdir" 20 20 0 Fable
    read -r level gap <<<"$(CLAUDE_ACCOUNT_DIR="$tmpdir" scoped_forecast 45 345600)"
    [ "$level" = "red" ] || [ "$level" = "yellow" ]
    [ "$gap" -gt 0 ]
    # and the account-7d walk is untouched by it: that profile is unlearned
    [ -z "$(CLAUDE_ACCOUNT_DIR="$tmpdir" seven_day_forecast 45 345600)" ]
    rm -rf "$tmpdir"
}

@test "scoped_forecast: an unlearned scoped profile says nothing" {
    tmpdir=$(mktemp -d)
    _write_scoped_profile_cache "$tmpdir" 20 -1 -1 Fable
    [ -z "$(CLAUDE_ACCOUNT_DIR="$tmpdir" scoped_forecast 45 345600)" ]
    # cold start: enough weekdays, not enough days
    _write_scoped_profile_cache "$tmpdir" 3 20 0 Fable
    [ -z "$(CLAUDE_ACCOUNT_DIR="$tmpdir" scoped_forecast 45 345600)" ]
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

# --- the hour shape (rest model) -------------------------------------------

# A valid hour_profile: 24 keys, mean 1, the named local hours at the 0.1
# floor and the rest sharing what is left. TZ is pinned by every test that
# uses these, so "hour" means one thing on any host.
_hour_profile_at() { # comma-separated rest hours
    awk -v rest="$1" 'BEGIN{
        n = split(rest, r, ","); rv = 0.1; av = (24 - n * rv) / (24 - n)
        printf "{"
        for (i = 0; i < 24; i++) {
            is = 0
            for (j = 1; j <= n; j++) if (r[j] + 0 == i) is = 1
            printf "%s\"%d\":%.4f", (i ? "," : ""), i, (is ? rv : av)
        }
        printf "}"
    }'
}

# The same, placed relative to the CURRENT local hour: how a test puts the
# span it asks about inside or outside sleep without owning the clock.
_hour_profile_from_now() { # offset count
    local off="$1" n="$2" h0 list="" i
    h0=$(date +%H); h0=$((10#$h0))
    for (( i = 0; i < n; i++ )); do list="$list,$(( (h0 + off + i + 48) % 24 ))"; done
    _hour_profile_at "${list#,}"
}

_add_hour_profile() { # cache-file profile-json
    jq -c --argjson h "$2" '. + {hour_profile: $h}' "$1" > "$1.t" && mv "$1.t" "$1"
}

@test "build_seven_day_profile: learns the hour shape, floored and mean 1" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    # The fixture burns twice a day, at +4h and +8h from the hour it was
    # written in, 12 points then 8. Two hot hours, twenty-two at rest.
    _write_forecast_fixture "$tmpdir" 21
    build_seven_day_profile
    [ "$(jq -r '.hour_profile | length' "$tmpdir/forecast.cache")" = "24" ]
    mean=$(jq -r '[.hour_profile[]] | add / 24' "$tmpdir/forecast.cache")
    awk -v m="$mean" 'BEGIN{exit !(m >= 0.99 && m <= 1.01)}'
    # The floor is the hedge for the occasional overnight autonomous run: a
    # rest hour projects a tenth of a uniform hour, never zero.
    [ "$(jq -r '[.hour_profile[] | select(. < 0.05)] | length' "$tmpdir/forecast.cache")" = "0" ]
    [ "$(jq -r '[.hour_profile[] | select(. > 1)] | length' "$tmpdir/forecast.cache")" = "2" ]
    # 60% of the burn in one hour is 14.4 uniform hours before the floor
    # takes its cut and the shape is scaled back to mean 1.
    top=$(jq -r '[.hour_profile[]] | max' "$tmpdir/forecast.cache")
    awk -v p="$top" 'BEGIN{exit !(p >= 12 && p <= 14)}'
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: today never trains the hour shape" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    _write_forecast_fixture "$tmpdir" 21
    # 30 points burned an hour ago, in an hour the history has never used. A
    # day that has only reached noon reports every evening hour as rest, so
    # today is evidence about burn and never about rhythm.
    printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":60}}\n' \
        "$(( $(date +%s) - 3600 ))" >> "$tmpdir/usage.jsonl"
    build_seven_day_profile
    [ "$(jq -r '[.hour_profile[] | select(. > 1)] | length' "$tmpdir/forecast.cache")" = "2" ]
    top=$(jq -r '[.hour_profile[]] | max' "$tmpdir/forecast.cache")
    awk -v p="$top" 'BEGIN{exit !(p >= 12 && p <= 14)}'
    # ...and the weekday side counted it, untouched by any of this
    awk -v r="$(jq -r '.recent_24h' "$tmpdir/forecast.cache")" 'BEGIN{exit !(r >= 30)}'
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: a first day of burn publishes no hour shape" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    now=$(date +%s)
    printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":10}}\n' \
        "$(( now - 7200 ))" > "$tmpdir/usage.jsonl"
    printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":40}}\n' \
        "$(( now - 3600 ))" >> "$tmpdir/usage.jsonl"
    build_seven_day_profile
    # The burn is real and counted; with today excluded there is nothing left
    # to shape it with, and an absent field is how a reader is told to walk
    # flat. A shape guessed from one day is worse than none.
    [ "$(jq -r '.recent_24h' "$tmpdir/forecast.cache")" = "30.00" ]
    [ "$(jq -r '.hour_profile' "$tmpdir/forecast.cache")" = "null" ]
    rm -rf "$tmpdir"
}

@test "_profile_walk: an absent or broken hour shape walks exactly as before" {
    tmpdir=$(mktemp -d)
    export TZ=UTC
    # Pinned clock: the shape makes the walk depend on the hour it runs in,
    # so a regression test that let the clock move would compare two
    # different questions.
    now=$(date -u -d '2026-01-05 22:00:00' +%s)
    base='{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":20,"1":20,"2":20,"3":20,"4":20,"5":20,"6":20}}'
    printf '%s' "$base" > "$tmpdir/forecast.cache"
    want=$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 50 432000 "$now")
    # the release's own numbers, so the baseline cannot drift with the fixture
    read -r gap end <<<"$want"
    [ "$gap" -ge 59 ] && [ "$gap" -le 60 ]
    [ "$end" = "100" ]
    # mean 3; one key of 24; a value of 30; a value that is not a number; a
    # shape that is not an object at all. Every one of them walks flat, and
    # none of them takes the walk's voice away — only the weekday guards do
    # that.
    while IFS= read -r bad; do
        printf '%s' "$base" | jq -c --argjson h "$bad" '. + {hour_profile: $h}' > "$tmpdir/forecast.cache"
        [ "$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 50 432000 "$now")" = "$want" ]
    done <<EOF
$(_hour_profile_at 0 | jq -c 'map_values(. * 3)')
{"0":1}
$(_hour_profile_at 0 | jq -c '.["3"] = 30')
$(_hour_profile_at 0 | jq -c '.["3"] = "x"')
$(_hour_profile_at 0 | jq -c '.["3"] = {"a":1}')
"nonsense"
EOF
    rm -rf "$tmpdir"
}

@test "_profile_walk: the hour shape moves the dry-out out of the night" {
    tmpdir=$(mktemp -d)
    export TZ=UTC
    # 22:00 on a Monday, 5 points left, 24%/day flat: one point an hour.
    now=$(date -u -d '2026-01-05 22:00:00' +%s)
    base='{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":24,"1":24,"2":24,"3":24,"4":24,"5":24,"6":24}}'
    printf '%s' "$base" > "$tmpdir/forecast.cache"
    read -r gap _ <<<"$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 95 259200 "$now")"
    # Flat, it dries at 03:00 — a false alarm at 23:00 and a missed warning
    # at 09:00, which is the whole complaint against a flat night.
    [ "$(date -u -d "@$(( now + 259200 - gap * 3600 ))" '+%H')" -lt 8 ]
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 0,1,2,3,4,5,6,7)"
    read -r gap _ <<<"$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 95 259200 "$now")"
    # Shaped, the same 5 points take until after wake: the night burns a
    # tenth of an hour each, so the crossing lands in the morning.
    [ "$(date -u -d "@$(( now + 259200 - gap * 3600 ))" '+%H')" -ge 8 ]
    # ...and over a whole number of days the shape is neutral by
    # construction: every hour class is covered exactly as often, so the
    # landing is the weekday total and nothing else.
    printf '%s' "$base" | jq -c '.weekday_profile |= map_values(10)' > "$tmpdir/forecast.cache"
    flat=$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 40 259200 "$now")
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 0,1,2,3,4,5,6,7)"
    [ "$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 40 259200 "$now")" = "$flat" ]
    [ "$flat" = "-1 70" ]
    rm -rf "$tmpdir"
}

@test "_profile_walk: the L1 blend ends at 24h, not at the end of that day" {
    tmpdir=$(mktemp -d)
    export TZ=UTC
    now=$(date -u -d '2026-01-05 22:00:00' +%s)
    # Calm 10%/day profile, a hot trailing day at 40%, 10% used, 3 days left.
    # 24h of blend (40) plus 48h of profile (20) lands on 70. Day steps used
    # to blend the whole day holding t+24h — 26 hours of hot rate the day
    # never earned, and 73 on this fixture. The horizon is 24h in both tools
    # that read this cache.
    printf '{"computed_at":0,"days_history":20,"recent_24h":40,"recent_48h":0,"weekday_profile":{"0":10,"1":10,"2":10,"3":10,"4":10,"5":10,"6":10}}' > "$tmpdir/forecast.cache"
    [ "$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 10 259200 "$now")" = "-1 70" ]
    # The shape is still neutral over whole days with the blend binding: it
    # redistributes the hot day, it does not add to it.
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 0,1,2,3,4,5,6,7)"
    [ "$(CLAUDE_ACCOUNT_DIR="$tmpdir" _seven_day_walk 10 259200 "$now")" = "-1 70" ]
    rm -rf "$tmpdir"
}

@test "awake_secs: counts only the hours the account is awake for" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    now=$(date -u -d '2026-01-05 22:00:00' +%s)
    printf '{"days_history":20}' > "$tmpdir/forecast.cache"
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 0,1,2,3,4,5,6,7)"
    m=$(hour_profile_mults)
    # a whole day holds 16 awake hours whatever hour it starts in
    [ "$(awake_secs "$m" 0 86400 "$now")" = "57600" ]
    # 22:00 to midnight is all awake; midnight to 08:00 is all rest
    [ "$(awake_secs "$m" 0 7200 "$now")" = "7200" ]
    [ "$(awake_secs "$m" 7200 36000 "$now")" = "0" ]
    # partial hours count as the part they are
    [ "$(awake_secs "$m" 0 1800 "$now")" = "1800" ]
    [ "$(awake_secs "$m" 5400 9000 "$now")" = "1800" ]
    # no live 5h window: the span is the whole remainder, from now
    [ "$(awake_secs "$m" 0 36000 "$now")" = "7200" ]
    # a 5h window outlasting the 7d reset leaves no span at all
    [ "$(awake_secs "$m" 36000 7200 "$now")" = "0" ]
    # unlearned is not zero: a caller must tell "you sleep through all of it"
    # from "I do not know when you sleep"
    [ -z "$(awake_secs "" 0 86400 "$now")" ]
    printf '{"days_history":13}' > "$tmpdir/forecast.cache"
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 0,1,2,3,4,5,6,7)"
    [ -z "$(hour_profile_mults)" ]
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

@test "detect_session_boundary: microsecond jitter is not a new window" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    log="$tmpdir/usage.jsonl"
    printf '{"type":"usage","session_id":"s1","timestamp":1,"five_hour":{"resets_at":"2026-07-28T06:00:00.515434+00:00"}}\n' > "$log"
    # resets_at wobbles per fetch and 05:59:59/06:00:00 straddle one
    # boundary. Compared as strings, every fetch looked like a roll and
    # wrote a marker pair: 26% of a real log was markers for windows that
    # never rolled, and the rotation cap ate that much history.
    detect_session_boundary s1 '{"five_hour":{"resets_at":"2026-07-28T06:00:00.087190+00:00"}}'
    detect_session_boundary s1 '{"five_hour":{"resets_at":"2026-07-28T05:59:59.344798+00:00"}}'
    [ "$(grep -c 'session_start\|session_end' "$log")" -eq 0 ]
    # a real roll: one end (the previous session) and one start
    detect_session_boundary s2 '{"five_hour":{"resets_at":"2026-07-28T11:00:00.123456+00:00"}}'
    [ "$(grep -c '"session_start"' "$log")" -eq 1 ]
    [ "$(grep -c '"session_end"' "$log")" -eq 1 ]
    # an OLDER window is a stale sample: it opens nothing
    detect_session_boundary s2 '{"five_hour":{"resets_at":"2026-05-20T16:00:00.000000+00:00"}}'
    [ "$(grep -c '"session_start"' "$log")" -eq 1 ]
    rm -rf "$tmpdir"
}

@test "detect_session_boundary: markers between samples do not hide the window" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    log="$tmpdir/usage.jsonl"
    printf '{"type":"usage","session_id":"s1","timestamp":1,"five_hour":{"resets_at":"2026-07-28T06:00:00.5+00:00"}}\n' > "$log"
    printf '{"type":"session_start","session_id":"s1","timestamp":2}\n' >> "$log"
    detect_session_boundary s1 '{"five_hour":{"resets_at":"2026-07-28T06:00:00.1+00:00"}}'
    [ "$(grep -c '"session_start"' "$log")" -eq 1 ]
    rm -rf "$tmpdir"
}

@test "session telemetry: what stdin knows and the quota API does not" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    model_id="claude-opus-5"
    cost_usd=2.45; duration_ms=834656; api_duration_ms=297096
    lines_added=11; lines_removed=3
    ctx_total_in=115348; ctx_size=1000000
    effort_level="xhigh"; fast_mode=false; cli_version="2.1.235"
    usage='{"five_hour":{"utilization":50},"seven_day":{"utilization":40}}'
    log_usage_snapshot "sess-1" "$usage" ""
    line=$(grep '"type":"usage"' "$tmpdir/usage.jsonl" | tail -1)
    [ "$(echo "$line" | jq -r '.session.cost_usd')" = "2.45" ]
    [ "$(echo "$line" | jq -r '.session.api_ms')" = "297096" ]
    [ "$(echo "$line" | jq -r '.session.ctx_in')" = "115348" ]
    [ "$(echo "$line" | jq -r '.session.effort')" = "xhigh" ]
    [ "$(echo "$line" | jq -r '.session.fast')" = "false" ]
    [ "$(echo "$line" | jq -r '.session.cli')" = "2.1.235" ]
    # and on the free stdin path too, so the series has no holes
    printf '{"account":{"uuid":"u-1"}}' > "$tmpdir/profile.cache"
    log_stdin_snapshot sid1 12 "$(( $(date +%s) + 3600 ))" 39 "$(( $(date +%s) + 86400 ))"
    line=$(grep '"source":"stdin"' "$tmpdir/usage.jsonl" | tail -1)
    [ "$(echo "$line" | jq -r '.session.cost_usd')" = "2.45" ]
    [ "$(echo "$line" | jq -r '.session.lines_add')" = "11" ]
    rm -rf "$tmpdir"
}

@test "session telemetry: no stdin context, no block — never a broken record" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    model_id=""; cost_usd=""; ctx_total_in=""; duration_ms=""; api_duration_ms=""
    lines_added=""; lines_removed=""; ctx_size=""; effort_level=""; fast_mode=""; cli_version=""
    log_usage_snapshot "sess-1" '{"five_hour":{"utilization":50}}' ""
    line=$(grep '"type":"usage"' "$tmpdir/usage.jsonl" | tail -1)
    echo "$line" | jq -e . >/dev/null
    [ "$(echo "$line" | jq -r '.session')" = "null" ]
    rm -rf "$tmpdir"
}

@test "week_scan: partitions by account uuid, not by directory" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _seed_week_store "$tmpdir"
    # the default dir predates account scoping — a real one holds a dozen
    # uuids. Tag the seeded rows as A and add a fat B window; only A's
    # burn may reach the strip.
    # derive the period from the seeded cache, not from a second `date` —
    # a second of drift shifts every slot index
    ps=$(( $(date -u -d "$(jq -r '.seven_day.resets_at' "$tmpdir/usage.cache")" +%s) - 604800 ))
    tmpf="$tmpdir/tagged.jsonl"
    jq -c '. + {user:{uuid:"acct-A"}}' "$tmpdir/usage.jsonl" > "$tmpf" && mv "$tmpf" "$tmpdir/usage.jsonl"
    w_end=$((ps + 8 * 18000 + 18000))
    for u in 0 99; do
        printf '{"timestamp":%s,"user":{"uuid":"acct-B"},"five_hour":{"resets_at":"%s"},"seven_day":{"utilization":%s}}\n' \
            "$((w_end - 18000))" "$(date -u -d "@$w_end" '+%Y-%m-%dT%H:%M:%SZ')" "$u" \
            >> "$tmpdir/usage.jsonl"
    done
    echo '{"account":{"uuid":"acct-A"}}' > "$tmpdir/profile.cache"
    # slot-agnostic: week_scan rounds the window key to 5 min but FLOORS the
    # slot, so an unaligned period can drop a window one cell left. The costs
    # are what this test is about.
    cells=$(week_history_cells "$ps")
    [[ ! "$cells" =~ :99(,|$) ]]      # acct-B's fat window never lands
    [[ "$cells" =~ (^|,|\ )[0-9]+:8(,|$) ]]   # acct-A's 10->18 window does
    [[ "$cells" =~ (^|,|\ )[0-9]+:7(,|$) ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: the learned scoped walk projects the model cap days early" {
    tmpdir=$(mktemp -d)
    # the env prefix must cover notice_collect too — it reads the profile
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_scoped_profile_cache "$tmpdir" 20 20 0 Fable
    reset=$(date -u -d '+4 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"five_hour":{"utilization":20},"seven_day":{"utilization":30,"resets_at":"%s"},"limits":[{"kind":"weekly_scoped","percent":45,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}]}' "$reset" "$reset")
    plain=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto claude-fable-5)")")
    [[ "$plain" =~ fb\ caps\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2},\ .*\ before\ reset ]]
    # linear pace alone is silent here: 45% with 4d left is under the 80 gate
    printf '{"computed_at":0,"days_history":0}' > "$tmpdir/forecast.cache"
    [ -z "$(notice_long_line "$(notice_collect "$usage" auto claude-fable-5)")" ]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: a scoped profile about another model is never borrowed" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # the profile was learned while OPUS carried the scoped cap; the session
    # runs Fable. Attributing opus's weekday shape to fable would invent a
    # forecast, so the clause falls back to linear (silent under 80).
    _write_scoped_profile_cache "$tmpdir" 20 20 0 Opus
    reset=$(date -u -d '+4 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"five_hour":{"utilization":20},"seven_day":{"utilization":30,"resets_at":"%s"},"limits":[{"kind":"weekly_scoped","percent":45,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}]}' "$reset" "$reset")
    [ -z "$(notice_long_line "$(notice_collect "$usage" auto claude-fable-5)")" ]
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
    [[ "$output" == *"(~3.8 ✕ 5h windows unused)"* ]]
    [[ "$output" == *"one full 5h window = ~10.00% of the week"* ]]
    [[ "$output" == *"week in progress: 44% used"* ]]
    # 44% + 4d x 10%/day: lands ~83-84%
    [[ "$output" == *"lands ~8"* ]]
    rm -rf "$tmpdir"
}

@test "run_usage_report: states the rhythm the walk is shaped by" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    _write_ledger_fixture "$tmpdir"
    base='{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":10,"1":10,"2":10,"3":10,"4":10,"5":10,"6":10}}'
    # Unlearned: the report claims no rhythm it has not measured.
    printf '%s' "$base" > "$tmpdir/forecast.cache"
    run run_usage_report 28
    [[ "$output" != *rhythm* ]]
    printf '%s' "$base" > "$tmpdir/forecast.cache"
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 0,1,2,3,4,5,6,7)"
    run run_usage_report 28
    [[ "$output" == *"rhythm: rest ~00:00-08:00 · 16h awake/day (learned)"* ]]
    # Sleep wraps midnight; a run cut there would read as two short ones.
    printf '%s' "$base" > "$tmpdir/forecast.cache"
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 22,23,0,1,2,3,4,5)"
    run run_usage_report 28
    [[ "$output" == *"rhythm: rest ~22:00-06:00 · 16h awake/day (learned)"* ]]
    # An account that never stops, and one whose quiet hours are scattered
    # rather than slept: neither has a rest block to name.
    printf '%s' "$base" > "$tmpdir/forecast.cache"
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at "")"
    run run_usage_report 28
    [[ "$output" == *"rhythm: no rest learned — burns around the clock"* ]]
    printf '%s' "$base" > "$tmpdir/forecast.cache"
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_at 3,9,15)"
    run run_usage_report 28
    [[ "$output" == *"rhythm: no rest learned — burns around the clock"* ]]
    rm -rf "$tmpdir"
}

@test "run_usage_report: what a 7d point buys in the pool beside it" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_ledger_fixture "$tmpdir"
    reset=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ')
    _uc() { # seven, then each scoped limit as pct:model:is_active
        local seven="$1" lim="" t p n a
        shift
        for t in "$@"; do
            IFS=: read -r p n a <<<"$t"
            lim="${lim:+$lim,}$(printf '{"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"display_name":"%s"}},"is_active":%s}' \
                "$p" "$reset" "$n" "$a")"
        done
        printf '{"seven_day":{"utilization":%s,"resets_at":"%s"},"limits":[%s]}' \
            "$seven" "$reset" "$lim" > "$tmpdir/usage.cache"
    }
    # nothing scoped in the payload: no second pool, no ratio
    _uc 81
    run run_usage_report 28
    [[ "$output" != *"mix:"* ]]
    # 81 against 63: 19 account points left carry 15 of the 37 the model has
    _uc 81 "63:Fable:false" "20:Opus:false"
    run run_usage_report 28
    [[ "$output" == *"fb mix: ~0.78 fb-pt per 7d-pt this week · 7d's 19% left carries ~15% of fb's 37%"* ]]
    # no session runs here, so no model to match: the binding limit wins over
    # the deeper one
    _uc 81 "63:Fable:false" "20:Opus:true"
    run run_usage_report 28
    [[ "$output" == *"op mix: ~0.25 op-pt per 7d-pt this week · 7d's 19% left carries ~5% of op's 80%"* ]]
    # the account has to be deep enough for "which cap binds" to be a question
    _uc 50 "30:Fable:false"
    run run_usage_report 28
    [[ "$output" != *"mix:"* ]]
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

@test "run_week: renders the 34-cell window ledger, remaining/reset, budget line" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":20,"resets_at":"%s"},"seven_day":{"utilization":20,"resets_at":"%s"}}' \
        "$(date +%s)" "$reset_5h" "$reset_7d" > "$tmpdir/usage.cache"
    run run_week
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    [[ "$plain" == "7d  20% "* ]]
    bar=$(echo "$plain" | head -1 | sed 's/^7d  20% //; s/  .*$//' | tr -d ' ')
    [ "$(echo "$bar" | grep -o . | wc -l)" -eq 34 ]
    # no store: the past is honestly unknown, never drawn as idle
    [[ "$bar" =~ ^░+▮▯+$ ]]
    # the row carries its own remaining/reset; no ruler, no day labels
    [[ "$plain" =~ ▯+\ +[0-9]+[dhm].*@[A-Z][a-z][a-z]\ [0-9]{2}:[0-9]{2} ]]
    [[ "$plain" != *"'-------'"* ]]
    [[ "$plain" == *"budget ~24✕5h left"* ]]
    [[ "$plain" != *"stale"* ]]
    rm -rf "$tmpdir"
}

@test "run_week: cells from the now cell count the budget line's windows" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 55% used, 31h left -> ceil(31/5) = 7 windows: 7 cells from ▮ rightward
    reset_7d=$(date -u -d '+31 hours' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":55,"resets_at":"%s"}}' \
        "$(date +%s)" "$reset_7d" > "$tmpdir/usage.cache"
    run run_week
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    bar=$(echo "$plain" | head -1 | sed 's/^7d  55% //; s/  .*$//' | tr -d ' ')
    stated=$(echo "$plain" | sed -n 's/.*budget ~\([0-9]*\)✕5h left.*/\1/p')
    counted=$(echo "$bar" | grep -o '▮.*' | grep -o . | wc -l)
    [ "$counted" -eq "$stated" ]
    rm -rf "$tmpdir"
}

@test "run_week: a sample store resolves past windows into burn heights" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    reset_7d_epoch=$((now + 31 * 3600))
    reset_7d=$(date -u -d "@$reset_7d_epoch" '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":55,"resets_at":"%s"}}' \
        "$now" "$reset_7d" > "$tmpdir/usage.cache"
    # period start + slots 3..5 sampled; slot 4 ran but burned nothing
    ps=$((reset_7d_epoch - 604800))
    : > "$tmpdir/usage.jsonl"
    for spec in "3 10 18" "4 18 18" "5 18 25"; do
        set -- $spec
        w_end=$((ps + $1 * 18000 + 18000))
        for u in "$2" "$3"; do
            printf '{"timestamp":%s,"five_hour":{"resets_at":"%s"},"seven_day":{"utilization":%s}}\n' \
                "$((w_end - 18000))" "$(date -u -d "@$w_end" '+%Y-%m-%dT%H:%M:%SZ')" "$u" \
                >> "$tmpdir/usage.jsonl"
        done
    done
    run run_week
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    bar=$(echo "$plain" | head -1 | sed 's/^7d  55% //; s/  .*$//' | tr -d ' ')
    [ "$(echo "$bar" | grep -o . | wc -l)" -eq 34 ]
    # burn heights appear, slots before coverage stay unknown
    [[ "$bar" == ░* ]]
    [[ "$bar" =~ [▂▃▄▅▆▇█] ]]
    # the zero-burn sampled window reads idle, not unknown — ▁ is the
    # baseline, so the burning neighbours must be ▂ or taller
    [[ "$bar" =~ [▂▃▄▅▆▇█]▁[▂▃▄▅▆▇█] ]]
    rm -rf "$tmpdir"
}

# --- week row (the live 7d ledger under the badges) ---------------------------

# usage.cache + a usage.jsonl with slots 3..5 sampled, reset 31h out.
_seed_week_store() {
    local dir="$1" now reset_7d_epoch reset_7d ps spec w_end u
    now=$(date +%s)
    reset_7d_epoch=$((now + 31 * 3600))
    reset_7d=$(date -u -d "@$reset_7d_epoch" '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":55,"resets_at":"%s"}}' \
        "$now" "$reset_7d" > "$dir/usage.cache"
    ps=$((reset_7d_epoch - 604800))
    : > "$dir/usage.jsonl"
    for spec in "3 10 18" "4 18 18" "5 18 25"; do
        set -- $spec
        w_end=$((ps + $1 * 18000 + 18000))
        for u in "$2" "$3"; do
            printf '{"timestamp":%s,"five_hour":{"resets_at":"%s"},"seven_day":{"utilization":%s}}\n' \
                "$((w_end - 18000))" "$(date -u -d "@$w_end" '+%Y-%m-%dT%H:%M:%SZ')" "$u" \
                >> "$dir/usage.jsonl"
        done
    done
}

@test "build_week_row: the strip under the badges, labelled 7d, on a 34-cell grid" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _seed_week_store "$tmpdir"
    row=$(build_week_row "$(cat "$tmpdir/usage.cache")" auto)
    plain=$(strip_ansi "$row")
    # no live 5h window in the fixture: the 7d strip alone
    [[ "$plain" == "7d "* ]]
    strip=$(printf '%s' "${plain#7d }" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//')
    bar=$(printf '%s' "$strip" | tr -d ' ')
    # 31h from the reset there are six cells ahead — ten or fewer draw in
    # full (WEEK_FUTURE_UNFOLD_MAX), so the whole 34-cell grid shows; the
    # mid-week fold has its own test on a five-day frame
    [[ "$bar" =~ ▮▯+$ ]]
    [ "$(printf '%s' "$bar" | grep -o . | wc -l)" -eq 34 ]
    [[ "$bar" =~ [▂▃▄▅▆▇█]▁[▂▃▄▅▆▇█] ]]
    [[ "$bar" == *▮* ]]
    # day gaps: single spaces inside the strip, several of them across a week
    [ "$(printf '%s' "$strip" | tr -cd ' ' | wc -c)" -ge 5 ]
    rm -rf "$tmpdir"
}

@test "log_stdin_snapshot: stdin rate_limits become usage samples, deduped by pair and time" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    printf '{"account":{"uuid":"u-1","email":"e@x"}}' > "$tmpdir/profile.cache"
    # windows must be LIVE, not a frozen epoch: an expired window is never
    # logged, so a hardcoded one turns this test into a time bomb.
    five=$(( $(date +%s) + 3600 )); seven=$(( $(date +%s) + 86400 ))
    log_stdin_snapshot sid1 12 "$five" 39 "$seven"
    log_stdin_snapshot sid1 12 "$five" 39 "$seven"   # same pair: no row
    log_stdin_snapshot sid2 13 "$five" 39 "$seven"   # changed, but < 60s: no row
    [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 1 ]
    row=$(cat "$tmpdir/usage.jsonl")
    [ "$(echo "$row" | jq -r .source)" = "stdin" ]
    [ "$(echo "$row" | jq -r .user.uuid)" = "u-1" ]
    [ "$(echo "$row" | jq -r .five_hour.resets_at)" = "$(date -u -d "@$five" '+%Y-%m-%dT%H:%M:%SZ')" ]
    [ "$(echo "$row" | jq -r .seven_day.utilization)" = "39" ]
    # older than the floor: the changed pair lands
    printf '12|39 %s\n' "$(( $(date +%s) - 120 ))" > "$tmpdir/stdin_seen"
    log_stdin_snapshot sid2 13 "$five" 39 "$seven"
    [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 2 ]
    # the week strip reads them like fetched samples (same window key)
    rm -rf "$tmpdir"
}

@test "strip_tail: pace from 1✕ tints, below 1✕ dims, young window hides it; reset is an axis label" {
    now=$(date +%s)
    # 50% used, 2h30 into a 5h window -> 1.0✕ (yellow); reset inside 24h -> @HH:MM
    t=$(strip_tail 50 9000 18000 "$now")
    plain=$(strip_ansi "$t")
    [[ "$plain" =~ ^\ 1\.0✕\ @[0-9]{2}:[0-9]{2}$ ]]
    [[ "$t" == *"${YELLOW}1.0✕"* ]]
    # 10% at 2h30 -> 0.2✕ dim
    t=$(strip_tail 10 9000 18000 "$now"); [[ "$t" == *"${DIM}0.2✕"* ]]
    # 80% at 2h30 -> 1.6✕ red
    t=$(strip_tail 80 9000 18000 "$now"); [[ "$t" == *"${RED}1.6✕"* ]]
    # 10 minutes in: too young for a pace, the reset still labels the edge
    plain=$(strip_ansi "$(strip_tail 10 17400 18000 "$now")")
    [[ "$plain" =~ ^\ @[0-9]{2}:[0-9]{2}$ ]]
    # 7d reset beyond 24h -> weekday + time
    plain=$(strip_ansi "$(strip_tail 40 $((3*86400)) 604800 "$now")")
    [[ "$plain" =~ @[A-Z][a-z][a-z]\ [0-9]{2}:[0-9]{2}$ ]]
}

# One Unicode block for the whole ladder. ˍ (U+02CD) is a spacing modifier
# LETTER: terminals resolve it through the text font while ▂▃▄ fall back to
# the box-drawing face, so the zero line sat at a different height and width
# than the bars beside it. ▁ is the shortest bar of the same run, which costs
# one rung — burn now starts at ▂ — and buys a strip that is one typeface.
@test "build_ledger_strip: the baseline is the shortest bar of the same block" {
    hist="0 100000 0:0,1:0.4,2:1,3:2,4:3,5:5,6:9,7:13,8:18,9:40"
    # cell 10 is `now`, so every cell above is history and draws its height
    strip=$(strip_ansi "$(build_ledger_strip 50 100000 0 -1 "$hist" 11 10000 0 0 0 10)")
    [ "$strip" = "▁▁▂▂▃▄▅▆▇█▮" ]
    # nothing from outside Block Elements, and in particular no modifier letter
    [[ "$strip" != *ˍ* ]]
    # an idle cell inside coverage draws the same baseline as a sub-point one:
    # one glyph, one tint, no colour-only meaning
    idle=$(strip_ansi "$(build_ledger_strip 50 100000 0 -1 "0 100000 0:5" 4 10000 0 0 0 3)")
    [ "$idle" = "▄▁▁▮" ]
}

@test "build_five_strip: five slots, always — the hollow run is the hours left" {
    # An axis, not a growing bar: five cells for five hours, ▮ walking them,
    # so "how long have I got" is a count of ▯ and never a second glance at
    # the clock — and the row holds its width for the life of the window.
    # What the strip still refuses to draw is a FORECAST: no × wall. The badge
    # (`5h[7%@04:20]`) states the end and the rank-90 "5h caps" notice owns
    # the warning with its own gates and its own exact time.
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    _five_of() {   # $1 = seconds still on the window, $2 = utilization
        local reset_5h; reset_5h=$(date -u -d "@$((now + $1))" '+%Y-%m-%dT%H:%M:%SZ')
        local u=$(printf '{"fetched_at":%s,"five_hour":{"utilization":%s,"resets_at":"%s"},"seven_day":{"utilization":20}}' "$now" "$2" "$reset_5h")
        local p; p=$(strip_ansi "$(build_week_row "$u" always)")
        p="${p#5h }"; p="${p%%  7d*}"
        printf '%s' "$(printf '%s' "$p" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//; s/ [0-9.]*✕$//')"
    }
    # (1) a hot young window: one prompt front-loaded 7% ten minutes in —
    # the fixture that used to draw ▮▯×××. Four hours still to come, and not
    # one of them carries a verdict.
    [ "$(_five_of $((18000 - 600)) 7)" = "▮▯▯▯▯" ]
    # (2) mid-window, burning hard enough that linear pace would have walled
    # off every remaining cell: still ▯, never ×
    mid=$(_five_of 9000 80)
    [ "$mid" = "░░▮▯▯" ]
    [[ "$mid" != *×* ]]
    # (3) the last hour: nothing ahead, same five columns — the row does not
    # reflow as the window drains
    [ "$(_five_of 600 40)" = "░░░░▮" ]
    # the hollow run IS the whole hours left, to the second — not to the
    # nearest cell boundary of a grid rounded to 5 minutes. 3h01m left draws
    # three hollow cells; the 119-minute mark used to draw two.
    for secs in 17400 12600 10860 9000 4000 600; do
        hollow=$((secs / 3600))
        slot=$((4 - hollow))
        want=""
        for ((i = 0; i < slot; i++)); do want="${want}░"; done
        want="${want}▮"
        for ((i = slot + 1; i < 5; i++)); do want="${want}▯"; done
        [ "$(_five_of "$secs" 30)" = "$want" ]
    done
    rm -rf "$tmpdir"
}

@test "windows_ahead: the window you are in is not a window you have left" {
    # 55h of week with 3h still on the current 5h window: 52h is ahead of it,
    # and a stub at the end of the week is still a window you can spend — so
    # 11 more, not the 12 that counting ▮ twice would give.
    [ "$(windows_ahead $((55 * 3600)) $((3 * 3600)))" -eq 11 ]
    # ...and it does not drift while both clocks tick down together: an hour
    # later the week is 54h and the window 2h, still 52h ahead. A count that
    # moved mid-window would be a reading; this is a countdown.
    [ "$(windows_ahead $((54 * 3600)) $((2 * 3600)))" -eq 11 ]
    [ "$(windows_ahead $((53 * 3600)) $((1 * 3600)))" -eq 11 ]
    # it steps down by exactly one, at the rollover, when 5h is on the clock again
    [ "$(windows_ahead $((52 * 3600 - 1)) 18000)" -eq 10 ]
    # a partial window at the end of the week still counts
    [ "$(windows_ahead $((8 * 3600)) $((3 * 3600)))" -eq 1 ]
    # the week ends inside this window: nothing is ahead of it
    [ "$(windows_ahead $((3 * 3600)) $((3 * 3600)))" -eq 0 ]
    [ "$(windows_ahead $((2 * 3600)) $((3 * 3600)))" -eq 0 ]
    # no live 5h window in the payload: nothing to exclude
    [ "$(windows_ahead $((55 * 3600)) 0)" -eq 11 ]
}

@test "strip_tail: young is a fraction of the window, not a clock reading" {
    now=$(date +%s)
    # 5h is unchanged: 15m is 5% of it, and the pace is legible from there
    [[ "$(strip_ansi "$(strip_tail 5 $((18000 - 900)) 18000 "$now" hide)")" == *"✕"* ]]
    [ -z "$(strip_tail 5 $((18000 - 899)) 18000 "$now" hide)" ]
    # the same 15m is 0.1% of a week: 2% of the pool over 0.1% of the time
    # printed 3.0✕ in red on an hour-old window. 7d now waits ~8.4h, the
    # fraction seven_day_elapsed already calls the noise floor.
    [ -z "$(strip_tail 2 $((604800 - 900)) 604800 "$now" hide)" ]
    [ -z "$(strip_tail 2 $((604800 - 30239)) 604800 "$now" hide)" ]
    [[ "$(strip_ansi "$(strip_tail 2 $((604800 - 30240)) 604800 "$now" hide)")" == *"✕"* ]]
}

@test "build_week_row: each strip ends with its pace and reset" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _seed_week_store "$tmpdir"
    now=$(date +%s)
    reset_5h=$(date -u -d "@$((now + 3 * 3600))" '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(jq -c --arg r "$reset_5h" '.five_hour.resets_at = $r | .five_hour.utilization = 40' "$tmpdir/usage.cache")
    plain=$(strip_ansi "$(build_week_row "$usage" auto)")
    # 5h resets inside 24h -> @HH:MM; 7d resets in 31h -> @Ddd HH:MM
    [[ "$plain" =~ ^5h\ .*▮.*\ [0-9]\.[0-9]✕\ @[0-9]{2}:[0-9]{2}\ \ 7d\ .*▮.*\ [0-9]\.[0-9]✕\ @[A-Z][a-z][a-z]\ [0-9]{2}:[0-9]{2}$ ]]
    rm -rf "$tmpdir"
}

@test "log_stdin_snapshot: an EXPIRED window is never a sample" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    printf '{"account":{"uuid":"u-1"}}' > "$tmpdir/profile.cache"
    # An idle session — or a hand-piped fixture — reports the window it last
    # saw. Logged, that pair reads as a huge drop and the next real sample
    # re-climbs it: the learner counts the same burn twice. Measured on a
    # real log, two such rows inflated a 50-point week to 146.
    old5=$(( $(date +%s) - 7200 )); old7=$(( $(date +%s) - 3600 ))
    log_stdin_snapshot stale 4 "$old5" 4 "$old7"
    [ ! -f "$tmpdir/usage.jsonl" ] || [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 0 ]
    # a live 5h window with an expired 7d one is still not a sample
    log_stdin_snapshot stale 4 "$(( $(date +%s) + 3600 ))" 4 "$old7"
    [ ! -f "$tmpdir/usage.jsonl" ] || [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 0 ]
    # both live: logged
    log_stdin_snapshot live 4 "$(( $(date +%s) + 3600 ))" 4 "$(( $(date +%s) + 86400 ))"
    [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 1 ]
    rm -rf "$tmpdir"
}

@test "log_stdin_snapshot: a stdin pair behind the cache in the same window is a stale session — not logged" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    printf '{"account":{"uuid":"u-1"}}' > "$tmpdir/profile.cache"
    five=$(( $(date +%s) + 3600 )); seven=$(( $(date +%s) + 86400 ))
    printf '{"five_hour":{"utilization":21,"resets_at":"%s"},"seven_day":{"utilization":43,"resets_at":"%s"},"fetched_at":1}' \
        "$(date -u -d "@$five" '+%Y-%m-%dT%H:%M:%S.2+00:00')" \
        "$(date -u -d "@$seven" '+%Y-%m-%dT%H:%M:%S.1+00:00')" > "$tmpdir/usage.cache"
    log_stdin_snapshot s 8 "$five" 41 "$seven"      # same windows, behind the cache
    [ ! -f "$tmpdir/usage.jsonl" ] || [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 0 ]
    log_stdin_snapshot s 23 "$five" 43 "$seven"     # ahead: logged
    [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 1 ]
    # a NEWER 5h window is logged even though its number is lower
    printf '12|39 0\n' > "$tmpdir/stdin_seen"
    log_stdin_snapshot s 2 "$seven" 43 "$seven"
    [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 2 ]
    # ... but an OLDER 5h window than the cache is a stale session, not news
    printf '12|39 0\n' > "$tmpdir/stdin_seen"
    log_stdin_snapshot s 99 "$(( five - 18000 ))" 43 "$seven"
    [ "$(wc -l < "$tmpdir/usage.jsonl")" -eq 2 ]
    rm -rf "$tmpdir"
}

@test "five strip: a dip inside the window never becomes a burst (monotone envelope)" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    reset_5h=$((now + 3 * 3600 - 400))
    fs=$(( ( (reset_5h - 18000 + 150) / 300 ) * 300 ))
    iso=$(date -u -d "@$reset_5h" '+%Y-%m-%dT%H:%M:%SZ')
    : > "$tmpdir/usage.jsonl"
    # 20 -> 21 -> (stale 8) -> 23: the envelope credits 1 + 2, never +15
    for spec in "600 20" "4200 21" "4300 8" "4400 23"; do
        set -- $spec
        printf '{"timestamp":%s,"five_hour":{"utilization":%s,"resets_at":"%s"},"seven_day":{"utilization":20}}\n' \
            "$((fs + $1))" "$2" "$iso" >> "$tmpdir/usage.jsonl"
    done
    five=$(five_history_cells 0 "$fs")
    [[ "$five" == *"0:20,1:3" ]]
    rm -rf "$tmpdir"
}

@test "week strip: day gaps live in history only — never right after ▮" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":20,"resets_at":"%s"}}' "$(date +%s)" "$reset_7d")
    plain=$(strip_ansi "$(build_week_row "$usage" always)" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//')
    # everything from ▮ to the end is one contiguous run: kept hollow cells,
    # then the folded tail (no gap ever lands right after the now-marker)
    [[ "${plain#*▮}" =~ ^▯+\.\.\.▯\(✕[0-9]+\)$ ]]
    rm -rf "$tmpdir"
}

@test "build_week_row: the folded 7d tail counts windows to the reset, not cells hidden" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    # not a whole number of 5h windows out: the grid rounds the period start
    # to 5 min, and an exact multiple would sit on the ceil boundary
    reset_epoch=$((now + 5 * 86400 + 3600))
    reset_7d=$(date -u -d "@$reset_epoch" '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":20,"resets_at":"%s"}}' "$now" "$reset_7d")
    plain=$(strip_ansi "$(build_week_row "$usage" always)" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//' | tr -d ' ')
    strip="${plain#7d}"
    [[ "$strip" =~ ^(.*)\.\.\.▯\(✕([0-9]+)\)$ ]]
    drawn=$(printf '%s' "${BASH_REMATCH[1]}" | grep -o . | wc -l)
    # exactly WEEK_FUTURE_KEEP hollow cells stay visible before the fold
    [[ "${BASH_REMATCH[1]}" == *"▮▯▯" ]]
    # the count is 5h windows before the reset — the number the budget line
    # prices — and NOT the cells the fold hid: the 34-cell grid spans 170h
    # against a 168h period, so the two disagree by design
    [ "${BASH_REMATCH[2]}" -eq $(( (reset_epoch - now + 17999) / 18000 )) ]
    [ "${BASH_REMATCH[2]}" -ne $((34 - drawn)) ]
    rm -rf "$tmpdir"
}

@test "build_week_row: the future folds only when folding pays" {
    # The fold's old rule ("as soon as it hides two cells") served "the
    # future is one fact"; the rest tint superseded that — future cells now
    # carry a shape — so what remains of the fold is column economy: a tail
    # of WEEK_FUTURE_UNFOLD_MAX cells or fewer costs no more drawn in full
    # than the nine-column token that would replace it.
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    _tail_of() {
        local reset; reset=$(date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ')
        local u; u=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":20,"resets_at":"%s"}}' "$now" "$reset")
        local p; p=$(strip_ansi "$(build_week_row "$u" always)" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//' | tr -d ' ')
        printf '%s' "${p#*▮}"
    }
    # ~6 windows left: cheaper drawn than folded, so every cell shows
    six=$(_tail_of $((now + 6 * 18000 - 3600)))
    [[ "$six" != *"..."* ]]
    [[ "$six" =~ ^▯{5,7}$ ]]
    # ~13 windows left: the tail is wider than the token, so it still folds
    # to KEEP=2 cells and the count
    mid=$(_tail_of $((now + 13 * 18000 - 3600)))
    [[ "$mid" =~ ^▯▯\.\.\.▯\(✕([0-9]+)\)$ ]]
    [ "${BASH_REMATCH[1]}" -eq 13 ]
    # the last cells of the week: nothing to fold at all
    close=$(_tail_of $((now + 18000 + 600)))
    [[ "$close" != *"..."* ]]
    [[ "$close" =~ ^▯{0,3}$ ]]
    rm -rf "$tmpdir"
}

# Mark dim runs so a test can assert WHERE the tint sits, not just that some
# escape exists: {D} opens dim, {R} is the reset that closes every run.
_mark_dim() {
    printf '%s' "$1" | sed -e $'s/\x1b\\[2m/{D}/g' -e $'s/\x1b\\[0m/{R}/g' \
        -e $'s/\x1b\\[[0-9;]*m//g'
}

@test "build_week_strip: the unfold boundary is the fold token's own width" {
    # F = cells after ▮ on the 34-cell grid. Ten or fewer draw in full;
    # eleven is the first tail wider than the token and folds.
    local ps now10 now11 t10 t11
    ps=$(( ($(date +%s) / 86400 - 6) * 86400 ))
    now10=$((ps + 23 * 18000 + 100))     # nowslot 23 -> F = 10
    now11=$((ps + 22 * 18000 + 100))     # nowslot 22 -> F = 11
    t10=$(strip_ansi "$(build_week_strip 50 "$now10" "$ps" -1 "" 2 10 "")")
    t11=$(strip_ansi "$(build_week_strip 50 "$now11" "$ps" -1 "" 2 11 "")")
    [[ "$t10" != *"..."* ]]
    [[ "$t11" == *"...▯(✕11)"* ]]
}

@test "build_week_strip: a cell you sleep through draws dim" {
    # ps at UTC midnight; rest hours 0-8 (mult 0.1), awake 9-23. nowslot 27
    # puts six cells ahead: 20:00 (4h awake, plain), 01:00 (rest, dim),
    # 06:00 (2h awake < half the cell, dim), then three daytime cells plain.
    local mults="0.1 0.1 0.1 0.1 0.1 0.1 0.1 0.1 0.1 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54"
    local ps now out
    ps=$(( ($(date +%s) / 86400 - 6) * 86400 ))
    now=$((ps + 27 * 18000 + 100))
    out=$(_mark_dim "$(TZ=UTC build_week_strip 50 "$now" "$ps" -1 "" 2 6 "$mults")")
    [[ "${out#*▮}" == "{R}▯{R}{D}▯▯{R}▯▯▯{R}" ]]
}

@test "build_week_strip: a dry guess may not delete a window" {
    # The dry projection used to overwrite future cells as red ×, and an
    # unfolded ▮▯▯▯××× was read as three DELETED windows (measured live).
    # The wall already has an owner — the pinned notice, with an exact
    # time — so the drawn cells are identical with the projection and
    # without it; only the fold token still carries the dry mark.
    local mults="0.1 0.1 0.1 0.1 0.1 0.1 0.1 0.1 0.1 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54"
    local ps now with without
    ps=$(( ($(date +%s) / 86400 - 6) * 86400 ))
    now=$((ps + 27 * 18000 + 100))
    with=$(TZ=UTC build_week_strip 50 "$now" "$ps" 31 "" 2 6 "$mults")
    without=$(TZ=UTC build_week_strip 50 "$now" "$ps" -1 "" 2 6 "$mults")
    [ "$with" = "$without" ]
    [[ "$(strip_ansi "$with")" != *×* ]]
    # and the rest cells still dim
    [[ "$(_mark_dim "$with")" == *"{D}▯▯{R}"* ]]
}

@test "build_week_strip: unlearned, every future cell stays plain" {
    local ps now raw
    ps=$(( ($(date +%s) / 86400 - 6) * 86400 ))
    now=$((ps + 27 * 18000 + 100))
    raw=$(TZ=UTC build_week_strip 50 "$now" "$ps" -1 "" 2 6 "")
    # no dim escape anywhere after the now-marker (history ░ cells are dim
    # by design and sit before it)
    [[ "${raw#*▮}" != *$'\033[2m'* ]]
}

@test "build_five_strip: hollow hours you sleep through draw dim" {
    # a 22:00-03:00 UTC window, two hours in: the hours ahead are 01:00 and
    # 02:00, both rest — the window outlives the evening and the strip says so
    local mults="0.1 0.1 0.1 0.1 0.1 0.1 0.1 0.1 0.1 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54 1.54"
    local fps fnow out
    fps=$(( ($(date +%s) / 86400 - 1) * 86400 + 22 * 3600 ))
    fnow=$((fps + 2 * 3600 + 60))
    out=$(_mark_dim "$(TZ=UTC build_five_strip 40 "$fnow" "$fps" "" 10740 "$mults")")
    [[ "${out#*▮}" == "{R}{D}▯▯{R}" ]]
}

@test "build_week_strip: the tint flows from the learned cache, gated on history" {
    # No mults argument: the builder reads hour_profile_mults, which refuses
    # a cache younger than 14 days — the same evidence gate every learned
    # surface waits behind.
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    local hp ps now
    hp='{"0":0.1,"1":0.1,"2":0.1,"3":0.1,"4":0.1,"5":0.1,"6":0.1,"7":0.1,"8":0.1,"9":1.54,"10":1.54,"11":1.54,"12":1.54,"13":1.54,"14":1.54,"15":1.54,"16":1.54,"17":1.54,"18":1.54,"19":1.54,"20":1.54,"21":1.54,"22":1.54,"23":1.54}'
    ps=$(( ($(date +%s) / 86400 - 6) * 86400 ))
    now=$((ps + 27 * 18000 + 100))
    printf '{"days_history":21,"hour_profile":%s}\n' "$hp" >"$tmpdir/forecast.cache"
    learned=$(TZ=UTC build_week_strip 50 "$now" "$ps" -1 "" 2 6)
    [[ "${learned#*▮}" == *$'\033[2m▯'* ]]
    printf '{"days_history":5,"hour_profile":%s}\n' "$hp" >"$tmpdir/forecast.cache"
    young=$(TZ=UTC build_week_strip 50 "$now" "$ps" -1 "" 2 6)
    [[ "${young#*▮}" != *$'\033[2m'* ]]
    rm -rf "$tmpdir"
}

@test "build_week_row: the fold token and the budget line count the same windows" {
    # one line, one arithmetic: the row folded `...▯(✕N)` and the budget
    # sentence beside it priced `~N✕5h left` from the same instant, and a
    # reader must never have to arbitrate between the halves of one row
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    reset_7d=$(date -u -d "@$((now + 3 * 86400 + 7000))" '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":30,"resets_at":"%s"}}' "$now" "$reset_7d")
    row=$(strip_ansi "$(build_week_row "$usage" always)")
    [[ "$row" =~ \(✕([0-9]+)\) ]]
    fold="${BASH_REMATCH[1]}"
    pin=$(strip_ansi "$(build_advisor_line "$usage" always)")
    [[ "$pin" =~ ^([0-9]+)✕5h\ left ]]
    [ "$fold" -eq "${BASH_REMATCH[1]}" ]
    rm -rf "$tmpdir"
}

@test "build_week_row: a dry tail folds as × — the wall of dry cells is one glyph" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _write_profile_cache "$tmpdir" 21 30 0     # 30%/day learned: dries days early
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":50,"resets_at":"%s"}}' "$(date +%s)" "$reset_7d")
    plain=$(strip_ansi "$(build_week_row "$usage" always)" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//' | tr -d ' ')
    [[ "$plain" =~ \.\.\.×\(✕[0-9]+\)$ ]]
    # the dry cell and the operator sit side by side in this token and must
    # never be the same mark: × is a reading, ✕ is punctuation
    [[ "$plain" == *"×(✕"* ]]
    rm -rf "$tmpdir"
}

@test "MULT_GLYPH: one column, distinct from the dry cell, overridable" {
    # row 2 right-anchors the week row by ${#week_plain}, a character count —
    # a glyph carrying a variation selector counts 1 and draws 2, overhanging
    # the edge once per pace suffix. Guard the default, not the override.
    [ "${#MULT_GLYPH}" -eq 1 ]
    [ "$MULT_GLYPH" = "✕" ]
    [ "$MULT_GLYPH" != "×" ]
    now=$(date +%s)
    t=$(MULT_GLYPH=╳; strip_ansi "$(strip_tail 50 9000 18000 "$now")")
    [[ "$t" == *"1.0╳"* ]]
}

@test "build_week_row: the 5h strip credits each hour with the points it added" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    reset_5h=$((now + 3600 - 400))    # window started 4h+ ago: we sit in cell 4
    fs=$(( ( (reset_5h - 18000 + 150) / 300 ) * 300 ))
    reset_5h_iso=$(date -u -d "@$reset_5h" '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":30,"resets_at":"%s"},"seven_day":{"utilization":20,"resets_at":"%s"}}' "$now" "$reset_5h_iso" "$reset_7d")
    : > "$tmpdir/usage.jsonl"
    # +30m 5%, +1h30 15%, +2h30 15% (idle), +3h30 40%: cells 0:5 1:10 2:0 3:25
    for spec in "1800 5" "5400 15" "9000 15" "12600 40"; do
        set -- $spec
        printf '{"timestamp":%s,"five_hour":{"utilization":%s,"resets_at":"%s"},"seven_day":{"utilization":20}}\n' \
            "$((fs + $1))" "$2" "$reset_5h_iso" >> "$tmpdir/usage.jsonl"
    done
    plain=$(strip_ansi "$(build_week_row "$usage" auto)")
    [[ "$plain" == "5h "* ]]
    five="${plain#5h }"; five="${five%%  7d*}"; five=$(printf '%s' "$five" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//')
    [ "$five" = "▄▅▁█▮" ]
    # 30% in 4h+ -> dry past the reset: holds, so no × in this window
    [[ "$five" != *×* ]]
    rm -rf "$tmpdir"
}

@test "build_week_row: auto is silent without history; always draws the unknown week; off never" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":20,"resets_at":"%s"}}' "$(date +%s)" "$reset_7d")
    [ -z "$(build_week_row "$usage" auto)" ]
    plain=$(strip_ansi "$(build_week_row "$usage" always)" | sed 's/ [0-9.]*✕ @.*$//; s/ @.*$//' | tr -d ' ')
    [[ "$plain" =~ ^7d░+▮▯+\.\.\.▯\(✕[0-9]+\)$ ]]
    [ -z "$(build_week_row "$usage" off)" ]
    # no live 7d window: nothing, even in always mode
    [ -z "$(build_week_row '{"seven_day":{"utilization":20}}' always)" ]
    rm -rf "$tmpdir"
}

@test "week_history_cells: cached per period + log signature; a new sample invalidates" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    _seed_week_store "$tmpdir"
    now=$(date +%s)
    ps=$(( ( (now + 31 * 3600 - 604800 + 150) / 300 ) * 300 ))
    first=$(week_history_cells "$ps")
    [[ "$first" == *"3:8"* ]]
    [ -f "$tmpdir/week.cache" ]
    [ "$(jq -r .period_start "$tmpdir/week.cache")" = "$ps" ]
    # served from cache: doctor the cache, the doctored value comes back
    jq -c '.week="1 2 3:99"' "$tmpdir/week.cache" > "$tmpdir/wc" && mv "$tmpdir/wc" "$tmpdir/week.cache"
    [ "$(week_history_cells "$ps")" = "1 2 3:99" ]
    # a new sample changes the log signature: real cells again
    sleep 1
    printf '{"timestamp":%s,"five_hour":{"resets_at":"%s"},"seven_day":{"utilization":30}}\n' \
        "$((ps + 5 * 18000))" "$(date -u -d "@$((ps + 6 * 18000))" '+%Y-%m-%dT%H:%M:%SZ')" >> "$tmpdir/usage.jsonl"
    again=$(week_history_cells "$ps")
    [[ "$again" == *"5:12"* ]]
    # a different period never reads a stale cache
    [[ "$(week_history_cells $((ps - 604800)))" != *"3:8"* ]]
    rm -rf "$tmpdir"
}

@test "week_period_start: snaps to the 5-min grid so slot 0 is never lost to jitter" {
    # a reset that truncates to a second past the grid still starts the week ON it
    now=1786550400
    [ "$(week_period_start "$now" $((604800 + 1)))" = "1786550400" ]
    [ "$(week_period_start "$now" $((604800 - 1)))" = "1786550400" ]
    [ "$(week_period_start "$now" $((604800 + 149)))" = "1786550400" ]
    [ "$(week_period_start "$now" $((604800 + 150)))" = "1786550700" ]
}

@test "compact_text: drops the weakest joint first, keeps the leading fact" {
    t="! 5h caps ~05:18, 52m before reset; 7d dry ~Thu 09:00, 2d before reset · then hard stop"
    [ "$(compact_text "$t" 200)" = "$t" ]
    [ "$(compact_text "$t" 40)" = "! 5h caps ~05:18, 52m before reset" ]
    [ "$(compact_text "$t" 20)" = "! 5h caps ~05:18" ]
    b="budget ~3✕5h left · even 20%/win · heading ~52%"
    [ "$(compact_text "$b" 34)" = "budget ~3✕5h left · even 20%/win" ]
    [ "$(compact_text "$b" 17)" = "budget ~3✕5h left" ]
    # no joint left: hard cut with an ellipsis, never a mid-word lie
    [ "$(compact_text "budget last window is long" 16)" = "budget last win…" ]
    # under 16 columns nothing honest fits
    run compact_text "$b" 15
    [ "$status" -eq 1 ]
}

@test "integration: advisor merges into the week row when line 1 leaves room" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    _seed_week_store "$tmpdir/.claude/statusline"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(jq -r .seven_day.resets_at "$tmpdir/.claude/statusline/usage.cache")
    input=$(printf '{"session_id":"wk","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"context_window":{"used_percentage":10,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":"%s"},"seven_day":{"used_percentage":55,"resets_at":"%s"}}}' "$reset_5h" "$reset_7d")
    out=$(printf '%s' "$input" | HOME="$tmpdir" COLUMNS=140 bash "$SCRIPT_DIR/statusline.sh" --notice off)
    # 140 cols: line 1 leaves ~45 beside the ledgers -> row 2 mirrors line 1:
    # advice left, evidence right, one edge shared with line 1. Two rows.
    [ "$(printf '%s\n' "$out" | wc -l)" -eq 2 ]
    l1=$(printf '%s\n' "$out" | sed -n 1p | sed "s/\x1b\[[0-9;]*m//g")
    l2=$(printf '%s\n' "$out" | sed -n 2p | sed "s/\x1b\[[0-9;]*m//g")
    [[ "$l2" =~ ^!\ 5h\ caps\ ~.*\ \ 5h\ .*▮.*7d\ .*▮ ]]
    [ "${#l2}" -eq "${#l1}" ]
    # the merged row starts with ink (its color), not whitespace: nothing to trim
    raw2=$(printf '%s\n' "$out" | sed -n 2p)
    [[ "$raw2" == $'\e['* ]]
    [[ "$raw2" != $'\e[0m '* ]]
    off=$(printf '%s' "$input" | HOME="$tmpdir" COLUMNS=140 bash "$SCRIPT_DIR/statusline.sh" --week off --notice off)
    [ "$(printf '%s\n' "$off" | wc -l)" -eq 2 ]
    rm -rf "$tmpdir"
}

@test "integration: no room beside the ledgers keeps the block — ledgers, then the full sentence" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    _seed_week_store "$tmpdir/.claude/statusline"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(jq -r .seven_day.resets_at "$tmpdir/.claude/statusline/usage.cache")
    input=$(printf '{"session_id":"wk","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"context_window":{"used_percentage":10,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":"%s"},"seven_day":{"used_percentage":55,"resets_at":"%s"}}}' "$reset_5h" "$reset_7d")
    # 88 cols: the merged form needs ~92 since the strips narrowed (5-cell 5h,
    # folded 7d tail), so the advisor falls back to a row of its own
    out=$(printf '%s' "$input" | HOME="$tmpdir" COLUMNS=88 setsid -w bash "$SCRIPT_DIR/statusline.sh" --notice off)
    [ "$(printf '%s\n' "$out" | wc -l)" -eq 3 ]
    l1=$(printf '%s\n' "$out" | sed -n 1p | sed "s/\x1b\[[0-9;]*m//g")
    l2=$(printf '%s\n' "$out" | sed -n 2p | sed "s/\x1b\[[0-9;]*m//g")
    l3=$(printf '%s\n' "$out" | sed -n 3p | sed "s/\x1b\[[0-9;]*m//g")
    [[ "$l2" =~ ^\ *5h\ .*▮.*7d\ .*▮ ]]
    [[ "$l3" == *"5h caps ~"* ]]
    # the rows hang as one block: the widest (the week row) ends where line 1
    # ends, and the advisor shares its LEFT edge rather than the right one
    [ "${#l2}" -eq "${#l1}" ]
    l2_left=$(printf '%s' "$l2" | sed 's/[^ ].*//' | wc -c)
    l3_left=$(printf '%s' "$l3" | sed 's/[^ ].*//' | wc -c)
    [ "$l2_left" -eq "$l3_left" ]
    [ "${#l3}" -lt "${#l1}" ]
    # leading padding rides behind a zero-width reset: Claude Code trims each
    # row before rendering, a bare-space row would land flush-left
    raw2=$(printf '%s\n' "$out" | sed -n 2p)
    [[ "$raw2" == $'\e[0m '* ]]
    rm -rf "$tmpdir"
}

@test "run_week: burning ahead of the clock walls off the windows the pool won't cover" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 80% used, 6d left: ~14% elapsed — the pool dries long before reset
    reset_7d=$(date -u -d '+6 days' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"five_hour":{"utilization":10},"seven_day":{"utilization":80,"resets_at":"%s"}}' \
        "$(date +%s)" "$reset_7d" > "$tmpdir/usage.cache"
    run run_week
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    bar=$(echo "$plain" | head -1 | sed 's/^7d  80% //; s/  .*$//' | tr -d ' ')
    # every future cell is a slot; the wall this frame projects is the
    # advisor sentence's to state, not the grid's to draw
    [[ "$bar" =~ ▮▯+$ ]]
    [[ "$bar" != *×* ]]
    rm -rf "$tmpdir"
}

@test "run_week: missing cache or no active window exits 3; stale is tagged" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    run run_week
    [ "$status" -eq 3 ]
    [[ "$output" == "week: no usage.cache"* ]]
    printf '{"fetched_at":%s,"five_hour":{"utilization":10}}' "$(date +%s)" > "$tmpdir/usage.cache"
    run run_week
    [ "$status" -eq 3 ]
    [[ "$output" == "week: no active 7d window"* ]]
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"fetched_at":%s,"seven_day":{"utilization":49,"resets_at":"%s"}}' \
        "$(( $(date +%s) - 7200 ))" "$reset_7d" > "$tmpdir/usage.cache"
    run run_week
    [ "$status" -eq 0 ]
    [[ "$(strip_ansi "$output")" == *"(stale "* ]]
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

@test "seven_day_forecast: a corrupt profile (>100%/day weekday) says nothing" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 145%/day of a 100-point pool is not a rate, it is a broken writer.
    # Measured live 2026-08-19: a pre-envelope build wrote thu=145 /
    # recent=343 into a shared home and the walk called a 2%-used fresh
    # window dry in 30h, red, on every render.
    cat > "$tmpdir/forecast.cache" <<EOF
{"computed_at":$(date +%s),"days_history":22,"recent_24h":343,"recent_48h":380,
 "weekday_profile":{"0":9,"1":15,"2":28,"3":145,"4":21,"5":16,"6":13}}
EOF
    [ -z "$(seven_day_forecast 2 518400)" ]
    rm -rf "$tmpdir"
}

@test "seven_day_forecast: recent_24h spanning a reset clamps to the pool" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    # 180 points in 24h is legitimate across a reset, but this window cannot
    # burn faster than 100/day: 50% used, 3d left dries in 12h (gap 60h),
    # not in 6.7h (gap 65h) at the unclamped rate.
    _write_profile_cache "$tmpdir" 21 5 180
    read -r level gap <<<"$(seven_day_forecast 50 259200)"
    [ "$level" = "red" ]
    [ "$gap" -ge 59 ] && [ "$gap" -le 60 ]
    rm -rf "$tmpdir"
}

# --- the young-window guard: a 7d projection needs this window's evidence ---

@test "young 7d window: nothing projects from last week onto a window hours old" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    # A heavy trained profile (30%/day, 40% in the trailing 24h) and a window
    # that opened 2.4h ago with 2% on it. Every point of that profile — and
    # every hour of that trailing day — belongs to the window BEFORE this one.
    _write_profile_cache "$tmpdir" 21 30 40
    young=$((604800 - 8640))
    [ -z "$(seven_day_forecast 2 $young)" ]
    [ -z "$(_seven_day_walk 2 $young)" ]
    ps=$(week_period_start "$now" "$young")
    [ "$(week_dry_slot 2 "$young" "$now" "$ps")" = "-1" ]
    reset_7d=$(date -u -d "@$((now + young))" '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":2,"resets_at":"%s"}}' "$now" "$reset_7d")
    row=$(strip_ansi "$(build_week_row "$usage" always)")
    [[ "$row" != *×* ]]              # no wall of dry cells drawn from history
    [[ "$row" != *"✕ @"* ]]          # and no pace on a 2.4h-old week
    records=$(notice_collect "$usage" always)
    [ -z "$(printf '%s\n' "$records" | grep -E '7d\.(dry|caps)')" ]
    long=$(strip_ansi "$(notice_long_line "$records")")
    [[ "$long" == budget* ]]
    [[ "$long" != *heading* ]]       # nowhere to head yet
    rm -rf "$tmpdir"
}

@test "young 7d window: a day in, the projections come back" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    now=$(date +%s)
    _write_profile_cache "$tmpdir" 21 30 40
    aged=$((604800 - 90000))         # 25h elapsed: the window can speak
    [ -n "$(seven_day_forecast 2 $aged)" ]
    ps=$(week_period_start "$now" "$aged")
    [ "$(week_dry_slot 2 "$aged" "$now" "$ps")" != "-1" ]
    reset_7d=$(date -u -d "@$((now + aged))" '+%Y-%m-%dT%H:%M:%SZ')
    usage=$(printf '{"fetched_at":%s,"five_hour":{"utilization":9},"seven_day":{"utilization":2,"resets_at":"%s"}}' "$now" "$reset_7d")
    row=$(strip_ansi "$(build_week_row "$usage" always)")
    [[ "$row" == *×* ]]
    records=$(notice_collect "$usage" always)
    [ -n "$(printf '%s\n' "$records" | grep -E '7d\.(dry|caps)')" ]
    [[ "$(strip_ansi "$(notice_long_line "$records")")" == *"7d dry"* ]]
    rm -rf "$tmpdir"
}

@test "seven_day_pace: a window younger than a day has no pace of its own" {
    # 8% burned 12h into a fresh week extrapolates to 16%/day and calls the
    # week at risk — on half a day of evidence, most of it one session.
    read -r level runway hint <<<"$(seven_day_pace 8 $((604800 - 43200)))"
    [ "$level" = "green" ]; [ "$hint" = "0" ]; [ "$runway" = "-1" ]
    # a day in, the same arithmetic is allowed to speak
    read -r level runway hint <<<"$(seven_day_pace 20 $((604800 - 90000)))"
    [ "$level" = "yellow" ]; [ "$hint" = "1" ]
    # ...and a young window that is genuinely spent still goes red on its own
    # percentage: the guard mutes pace, never facts
    read -r level runway hint <<<"$(seven_day_pace 88 $((604800 - 43200)))"
    [ "$level" = "red" ]
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

@test "is_1m_model: a 200k window from the CLI beats the default-1M family (1M turned off)" {
    # CLAUDE_CODE_DISABLE_1M_CONTEXT=1 on Fable: the CLI believes 200k and
    # re-bases the bar to it. The name must not paint [1m] over that.
    model_id="claude-fable-5-1" ctx_size=200000 exceeds_200k=false
    run is_1m_model
    [ "$status" -eq 1 ]
}

@test "is_1m_model: a 200k window from the CLI beats the [1m] suffix" {
    model_id="claude-opus-4-8[1m]" ctx_size=200000 exceeds_200k=false
    run is_1m_model
    [ "$status" -eq 1 ]
}

# --- premium band -> bar color ---------------------------------------------

@test "rewrite_exposure_level: yellow band over 200k, red past 800k" {
    pc_recache_if_cold="" ctx_size=1000000 exceeds_200k=false
    context_pct=15; [ "$(rewrite_exposure_level)" = "0" ]
    context_pct=30; [ "$(rewrite_exposure_level)" = "1" ]
    context_pct=82; [ "$(rewrite_exposure_level)" = "2" ]
}

@test "rewrite_exposure_level: exceeds_200k_tokens is ignored (cumulative-usage flag, not a window-size signal)" {
    # Real logs: a genuine 200k-window opus-4-6 session reports
    # exceeds_200k_tokens=true once cumulative usage passes 200k tokens — the
    # flag tracks session-total usage, not window capacity. Band must follow
    # ctx_size x context_pct only.
    pc_recache_if_cold="" ctx_size=1000000 context_pct=15 exceeds_200k=true
    [ "$(rewrite_exposure_level)" = "0" ]
}

@test "rewrite_exposure_level: 200k window never enters the band, even with exceeds_200k=true" {
    pc_recache_if_cold="" ctx_size=200000 context_pct=90 exceeds_200k=false
    [ "$(rewrite_exposure_level)" = "0" ]
    exceeds_200k=true
    [ "$(rewrite_exposure_level)" = "0" ]
}

@test "rewrite_exposure_level: the CLI's recache_tokens_if_cold sizes the exposure" {
    # 15% of 1M reads calm, but the CLI says a cold cache rewrites 250k.
    ctx_size=1000000 context_pct=15 exceeds_200k=false
    pc_recache_if_cold=250000; [ "$(rewrite_exposure_level)" = "1" ]
    pc_recache_if_cold=900000; [ "$(rewrite_exposure_level)" = "2" ]
    pc_recache_if_cold=150000; [ "$(rewrite_exposure_level)" = "0" ]
    # null right after a compaction: fall back to the live context.
    pc_recache_if_cold=""; context_pct=30; [ "$(rewrite_exposure_level)" = "1" ]
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

@test "integration: rewrite exposure colors the context bar yellow (no :NNNk text)" {
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

@test "integration: deep rewrite exposure (>800k) colors the context bar red" {
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

@test "integration: suffix-less fable flags rewrite exposure over 200k" {
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

@test "integration: exceeds_200k_tokens does not force rewrite exposure at low pct" {
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

# --- get_cache_health_cli (prompt_cache ledger, 2.1.251+) -------------------

@test "get_cache_health_cli: warm ledger with no misses is ok; ttl and anchor are the CLI's" {
    tmpdir=$(mktemp -d)
    # expires_at 5600 on a 1h TTL => the last request was at 2000, not "now".
    result=$(STATUSLINE_TEST_NOW_EPOCH=2500 get_cache_health_cli 200000 500 "$tmpdir/ch" 1h 5600 0 0 0 "")
    [ "$result" = "ok|1h|2000|0" ]
    jq -e '.pc_misses == 0 and .pc_rebuilds == 0 and .last_active_at == 2000' "$tmpdir/ch"
    rm -rf "$tmpdir"
}

@test "get_cache_health_cli: a miss the CLI counted is a break, sized at what it re-cached" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health_cli 200000 500 "$tmpdir/ch" 1h 4600 0 0 0 "" >/dev/null
    # Next render: misses 0 -> 1, miss_recache_tokens 0 -> 419000.
    result=$(STATUSLINE_TEST_NOW_EPOCH=8200 get_cache_health_cli 0 419000 "$tmpdir/ch" 1h 11800 1 0 419000 8199)
    [ "$result" = "break|1h|8200|419000" ]
    rm -rf "$tmpdir"
}

@test "get_cache_health_cli: a second miss is sized at the delta, not the session total" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health_cli 200000 500 "$tmpdir/ch" 1h 4600 1 0 300000 900 >/dev/null
    result=$(STATUSLINE_TEST_NOW_EPOCH=9000 get_cache_health_cli 0 150000 "$tmpdir/ch" 1h 12600 2 0 450000 8999)
    [[ "$result" == break\|* ]]
    [[ "$result" == *"|150000" ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health_cli: a rebuild the CLI expected (compaction) is building, not a break" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health_cli 200000 500 "$tmpdir/ch" 1h 4600 0 0 0 "" >/dev/null
    # /compact: read collapses to 0, a 60k prefix writes, expected_rebuilds 0 -> 1.
    result=$(STATUSLINE_TEST_NOW_EPOCH=1100 get_cache_health_cli 0 60000 "$tmpdir/ch" 1h 4700 0 1 0 "")
    [[ "$result" == building\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health_cli: no state yet but the CLI's last miss just happened is a break" {
    tmpdir=$(mktemp -d)
    # A resumed session's first frame: no state file, last_miss_at 10s ago,
    # this turn wrote the 300k rewrite.
    result=$(STATUSLINE_TEST_NOW_EPOCH=5000 get_cache_health_cli 0 300000 "$tmpdir/ch" 1h 8600 3 0 700000 4990)
    [ "$result" = "break|1h|5000|300000" ]
    rm -rf "$tmpdir"
}

@test "get_cache_health_cli: an old miss with no state is not a break" {
    tmpdir=$(mktemp -d)
    result=$(STATUSLINE_TEST_NOW_EPOCH=5000 get_cache_health_cli 200000 500 "$tmpdir/ch" 1h 8600 3 0 700000 1000)
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health_cli: a break is held for the notice window, then clears" {
    tmpdir=$(mktemp -d)
    STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health_cli 200000 500 "$tmpdir/ch" 1h 4600 0 0 0 "" >/dev/null
    STATUSLINE_TEST_NOW_EPOCH=8200 get_cache_health_cli 0 419000 "$tmpdir/ch" 1h 11800 1 0 419000 8199 >/dev/null
    result=$(STATUSLINE_TEST_NOW_EPOCH=8230 get_cache_health_cli 419000 900 "$tmpdir/ch" 1h 11830 1 0 419000 8199)
    [ "$result" = "break|1h|8230|419000" ]
    result=$(STATUSLINE_TEST_NOW_EPOCH=8290 get_cache_health_cli 419000 900 "$tmpdir/ch" 1h 11890 1 0 419000 8199)
    [[ "$result" == ok\|* ]]
    rm -rf "$tmpdir"
}

@test "get_cache_health_cli: a 5m TTL anchors 300s before expiry; null expiry keeps the old anchor" {
    tmpdir=$(mktemp -d)
    result=$(STATUSLINE_TEST_NOW_EPOCH=1000 get_cache_health_cli 50000 500 "$tmpdir/ch" 5m 1300 0 0 0 "")
    [ "$result" = "ok|5m|1000|0" ]
    result=$(STATUSLINE_TEST_NOW_EPOCH=1200 get_cache_health_cli 50000 500 "$tmpdir/ch" 5m "" 0 0 0 "")
    [ "$result" = "ok|5m|1000|0" ]
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

@test "integration: prompt_cache ledger — a counted miss renders ≡!419k bold red" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo '{"cache_read":200000,"cache_creation":100,"pc_misses":0,"pc_rebuilds":0,"pc_miss_recache":0,"last_active_at":1000}' > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-fable-5-1","display_name":"Fable 5.1"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.258","context_window":{"used_percentage":42,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":419000,"cache_read_input_tokens":0}},"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":1788324900,"requests":44,"misses":1,"expected_rebuilds":0,"hit_ratio":0.5,"cache_write_tokens":600000,"miss_recache_tokens":419000,"last_miss_at":1788321300,"recache_tokens_if_cold":419000}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"${CACHE_GLYPH}!419k"* ]]
    [[ "$result" == *$'\033[1;31m'"${CACHE_GLYPH}!419k"* ]]
    jq -e '.pc_misses == 1 and .pc_miss_recache == 419000' "$tmpdir/sessions/test-session-id_cache_health"
    rm -rf "$tmpdir"
}

@test "integration: prompt_cache ledger — a compaction rebuild renders ≡~, never ≡!" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo '{"cache_read":200000,"cache_creation":100,"pc_misses":0,"pc_rebuilds":0,"pc_miss_recache":0,"last_active_at":1000}' > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-fable-5-1","display_name":"Fable 5.1"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.258","context_window":{"used_percentage":6,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":60000,"cache_read_input_tokens":0}},"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":1788324900,"requests":45,"misses":0,"expected_rebuilds":1,"hit_ratio":0.9,"cache_write_tokens":260000,"miss_recache_tokens":0,"last_miss_at":null,"recache_tokens_if_cold":null}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"${CACHE_GLYPH}~"* ]]
    [[ "$plain" != *"${CACHE_GLYPH}!"* ]]
    rm -rf "$tmpdir"
}

@test "integration: prompt_cache ledger — a warm session with no misses stays silent" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    result=$(echo '{"model":{"id":"claude-fable-5-1","display_name":"Fable 5.1"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.258","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":135,"output_tokens":2,"cache_creation_input_tokens":1061,"cache_read_input_tokens":205283}},"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":1788324900,"requests":43,"misses":0,"expected_rebuilds":0,"hit_ratio":0.97,"cache_write_tokens":182487,"miss_recache_tokens":0,"last_miss_at":null,"recache_tokens_if_cold":205418}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" != *"${CACHE_GLYPH}"* ]]
    # The exposure past 200k (205k cold rewrite) tints the calm 21% bar yellow.
    [[ "$result" == *$'\033[0;33m'*"21%"* ]]
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
    # +4d22h at 21% sits inside every band with real slack: windows
    # ceil(424800/18000)=24 tolerates hours of skew, heading
    # floor(21*604800/elapsed)=70 tolerates ~24 minutes between this
    # date call and the function's own now-read. The former +5d/20%
    # fixture was a knife edge — heading=70 needed elapsed<=172800 while
    # windows=24 needed elapsed>=172800, so any second-boundary crossing
    # between the two clock reads flipped heading to 69 and failed CI.
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+4 days 22 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":21,\"resets_at\":\"$reset_7d\"}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" always)")
    # the budget voice wears no sigil: it interrupts nothing, and a leading
    # '-' on a dim line reads as a bullet in a list of one
    # row 2 carries the runway and the LANDING: the count is already drawn
    # on the strip beside it and the ration is surplus ÷ count, but where the
    # week ends up is nowhere else on screen
    [[ "$plain" =~ ^24✕5h\ left\ ·\ lands\ ~70%$ ]]
    # the whole sentence is still there for surfaces with a line to spend —
    # ration and prediction both, each named for what it is
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" always)")")
    [[ "$long" =~ ^budget\ ~24✕5h\ left\ ·\ even\ 3\.3%/win\ ·\ lands\ ~70%$ ]]
}

@test "build_advisor_line: budget degrades to plain headroom in the last window" {
    # The week ends INSIDE the current window (3h of 7d, 3h30 still on the
    # 5h): nothing is ahead of it, so there is nothing to divide the surplus
    # across and the line says the headroom straight. Surplus kept under
    # ADVISOR_SURPLUS_MIN_PCT — a bigger remainder belongs to the expiring
    # surplus clause, which owns the last-day zone.
    reset_5h=$(date -u -d '+3 hours 30 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_7d\"}}"
    # 25% unused is under ADVISOR_SURPLUS_MIN_PCT, so the end-of-week voice
    # stays quiet and the budget line owns the row
    plain=$(strip_ansi "$(build_advisor_line "$usage" always)")
    [[ "$plain" =~ ^last\ window\ ·\ 25%\ left$ ]]
    [[ "$plain" != *"/win"* ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" always)")")
    [[ "$long" =~ ^budget\ last\ window\ ·\ 25%\ left\ ·\ lands\ ~[0-9]+%$ ]]
}

@test "build_advisor_line: one window ahead keeps the count and the grammar" {
    # 3h of week with 45m on the current window: one more window follows this
    # one. Calling that "last window" to save a redundant `/win` clause states
    # something false about the week; the N-window form is true at N=1.
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_7d\"}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" always)")
    [[ "$plain" =~ ^1✕5h\ left\ · ]]
    [[ "$plain" != *"last window"* ]]
    # and the ration is still true at N=1: the long form divides by one
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" always)")")
    [[ "$long" == *"even 25.0%/win"* ]]
}

@test "build_advisor_line: the short budget states the landing, the long one both" {
    # A week with a day behind it: linear pace can speak even with no learned
    # profile, so row 2 has a destination to name. The ration and the
    # prediction answer different questions and the long form labels each —
    # `even N%/win` is what to spend, `lands ~N%` is where you end up.
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":14,\"resets_at\":\"$reset_7d\"}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" always)")
    [[ "$plain" =~ ^[0-9]+✕5h\ left\ ·\ lands\ ~[0-9]+%$ ]]
    [[ "$plain" != *"/win"* ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" always)")")
    [[ "$long" == *"even "*"%/win"* ]]
    [[ "$long" == *"lands ~"* ]]
    # one line, two futures, never the same word for both
    [[ "$long" != *heading* ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: the ration divides by the windows you are awake for" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+4 days 22 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":21,\"resets_at\":\"$reset_7d\"}}"
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":-1,"1":-1,"2":-1,"3":-1,"4":-1,"5":-1,"6":-1}}' > "$tmpdir/forecast.cache"
    # Unlearned, nothing moves: the ration is surplus over every window.
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" always)")")
    [[ "$long" =~ ^budget\ ~24✕5h\ left\ ·\ even\ 3\.3%/win\ ·\ lands\ ~[0-9]+%$ ]]
    # Eight hours of sleep a night, starting two hours from now, so the rest
    # band sits inside the span wherever the clock happens to be.
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_from_now 2 8)"
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" always)")")
    [[ "$long" =~ ^budget\ ~24✕5h\ left\ ·\ ~([0-9]+)\ awake\ ·\ even\ ([0-9.]+)%/win\ ·\ lands\ ~[0-9]+%$ ]]
    awake="${BASH_REMATCH[1]}" even="${BASH_REMATCH[2]}"
    # The clause names the denominator beside it, which is what makes the
    # line self-describing: a third of the week is asleep, so the honest
    # ration per window you will actually spend is higher.
    [ "$awake" -lt 24 ] && [ "$awake" -gt 0 ]
    [ "$even" = "$(awk -v h=79 -v w="$awake" 'BEGIN{printf "%.1f", h/w}')" ]
    # Row 2 is unchanged — the landing is still the one clause it carries.
    plain=$(strip_ansi "$(build_advisor_line "$usage" always)")
    [[ "$plain" =~ ^24✕5h\ left\ ·\ lands\ ~[0-9]+%$ ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: a window you sleep through takes the ration with it" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    # The week ends in 3 hours and every one of them is a rest hour: one
    # window ahead on the calendar, none you will be at the keyboard for.
    reset_5h=$(date -u -d '+45 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_7d\"}}"
    printf '{"computed_at":0,"days_history":20,"recent_24h":0,"recent_48h":0,"weekday_profile":{"0":-1,"1":-1,"2":-1,"3":-1,"4":-1,"5":-1,"6":-1}}' > "$tmpdir/forecast.cache"
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_from_now -1 6)"
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" always)")")
    # No `~0 awake` and no ration: zero is not a denominator, and a clause
    # about the next three hours would be pretending to be one about the
    # week. Where the week lands still speaks.
    [[ "$long" =~ ^budget\ ~1✕5h\ left\ ·\ lands\ ~[0-9]+%$ ]]
    [[ "$long" != *awake* ]]
    [[ "$long" != *"/win"* ]]
    plain=$(strip_ansi "$(build_advisor_line "$usage" always)")
    [[ "$plain" =~ ^1✕5h\ left\ ·\ lands\ ~[0-9]+%$ ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: hot 5h pace projects the cap wall-clock" {
    # 85% only 2h into the window (3h left): pace ~2.1x, caps well before reset
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":85,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":10}}"
    result=$(build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    # the pin says the wall; "42m before reset" is derivable from line 1's
    # own @HH:MM, so it rides the long form instead
    [[ "$plain" =~ ^!\ 5h\ caps\ ~[0-9]{2}:[0-9]{2}$ ]]
    [[ "$result" == *'\033[0;33m'* ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto)")")
    [[ "$long" =~ ^!\ 5h\ caps\ ~[0-9]{2}:[0-9]{2},\ .*\ before\ reset$ ]]
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
    [[ "$plain" =~ ^!\ 7d\ caps\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2}\ ·\ hard\ stop$ ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto)")")
    [[ "$long" =~ ^!\ 7d\ caps\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2},\ .*\ before\ reset ]]
    [[ "$long" == *"then hard stop"* ]]
}

@test "build_advisor_line: extra-usage billing changes the 7d tail" {
    reset_7d=$(date -u -d '+2 days 5 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10},\"seven_day\":{\"utilization\":75,\"resets_at\":\"$reset_7d\"},\"extra_usage\":{\"is_enabled\":true}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" auto)")
    [[ "$plain" == *"· extra billing"* ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto)")")
    [[ "$long" == *"then extra billing"* ]]
}

@test "build_advisor_line: off mode is silent under any pressure" {
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":95,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":95}}"
    [ -z "$(build_advisor_line "$usage" off)" ]
}

# --- the notice engine: ranking, the fading row 3, and what it knows ---

@test "notice_highlight: bolds the number and restores the voice colour" {
    out=$(notice_highlight "47% unused · spend it" "47%" "$CYAN")
    [ "$out" = "${BOLD}47%${NO_BOLD}${CYAN} unused · spend it" ]
    # a token that is not there leaves the sentence untouched
    [ "$(notice_highlight "no numbers here" "47%" "$CYAN")" = "no numbers here" ]
}

@test "notice_ranked: one voice per scope, highest rank wins" {
    NOTICE_RECS=()
    notice_add 50 '+' 7d k.low '' 'low 7d' 'low 7d long'
    notice_add 90 '!yellow' 5h k.five '' 'five' 'five long'
    notice_add 75 '+' 7d k.high '' 'high 7d' 'high 7d long'
    ranked=$(notice_ranked)
    [ "$(printf '%s\n' "$ranked" | wc -l)" -eq 2 ]
    [ "$(printf '%s\n' "$ranked" | sed -n 1p | cut -d$'\037' -f6)" = "five" ]
    [ "$(printf '%s\n' "$ranked" | sed -n 2p | cut -d$'\037' -f6)" = "high 7d" ]
    NOTICE_RECS=()
}

@test "notice_flash_line: the pin never flashes its own sentence; a second condition does" {
    state=$(mktemp -d)/notice_seen
    NOTICE_RECS=()
    notice_add 90 '!yellow' 5h '5h.caps.05:18' '~05:18' '5h caps ~05:18' '5h caps ~05:18, 42m before reset'
    records=$(notice_ranked)
    now=$(date +%s)
    # one condition, one row: row 3 would only restate row 2 at more length
    [ -z "$(notice_flash_line "$records" "$state" "$now")" ]
    [ "$(strip_ansi "$(notice_pin_line "$records")")" = "! 5h caps ~05:18" ]
    # a second, lower-ranked condition has something the pin does not say
    notice_add 65 '+' 7d '7d.surplus.9' '47%' '47% unused' '7d resets @07:00, 47% unused · spend it'
    records=$(notice_ranked)
    first=$(strip_ansi "$(notice_flash_line "$records" "$state" "$now")")
    [ "$first" = "+ 7d resets @07:00, 47% unused · spend it" ]
    # same condition a minute later: still inside the flash window
    [ -n "$(notice_flash_line "$records" "$state" $((now + 60)))" ]
    # ...and past it the row is gone; row 2 keeps the pin
    [ -z "$(notice_flash_line "$records" "$state" $((now + NOTICE_FLASH_SECS + 1)))" ]
    NOTICE_RECS=()
    rm -rf "$(dirname "$state")"
}

@test "notice_flash_worth_row: a sentence earns the row, a truncation stub does not" {
    # the floor is absolute, not relative to the pin: since row 3 became a
    # DIFFERENT notice than row 2, subtracting their lengths compared two
    # unrelated sentences
    run notice_flash_worth_row "! 7d dry ~Wed 19:50"   # 19: carries the number
    [ "$status" -eq 0 ]
    run notice_flash_worth_row "! 7d dry ~Wed"         # 13: says nothing to act on
    [ "$status" -eq 1 ]
    # the boundary itself, both sides
    run notice_flash_worth_row "$(printf '%*s' "$NOTICE_FLASH_MIN_CHARS" '')"
    [ "$status" -eq 0 ]
    run notice_flash_worth_row "$(printf '%*s' $((NOTICE_FLASH_MIN_CHARS - 1)) '')"
    [ "$status" -eq 1 ]
    run notice_flash_worth_row ""
    [ "$status" -eq 1 ]
}

@test "notice_flash_line: a NEW condition speaks even when the old one has faded" {
    state=$(mktemp -d)/notice_seen
    now=$(date +%s)
    printf '%s\t%s\n' '5h.caps.05:18' "$((now - 600))" > "$state"
    NOTICE_RECS=()
    notice_add 90 '!yellow' 5h '5h.caps.05:18' '' 'pin' 'the faded one'
    notice_add 65 '+' 7d '7d.surplus.11' '' 'pin2' 'the fresh one'
    out=$(strip_ansi "$(notice_flash_line "$(notice_ranked)" "$state" "$now")")
    [ "$out" = "+ the fresh one" ]
    NOTICE_RECS=()
    rm -rf "$(dirname "$state")"
}

@test "notice_collect: the model caps before the account, so steer to the roomier one" {
    reset_7d=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":40},\"seven_day\":{\"utilization\":53,\"resets_at\":\"$reset_7d\"},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":91,\"resets_at\":\"$reset_7d\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}},{\"kind\":\"weekly_scoped\",\"percent\":33,\"resets_at\":\"$reset_7d\",\"scope\":{\"model\":{\"display_name\":\"Opus\"}}}]}"
    short=$(notice_collect "$usage" auto "claude-fable-5" | awk -F$'\037' '$3 == "fb" { print $6 }')
    [ "$short" = "fb 91% vs 7d 53% · go op" ]
    long=$(notice_collect "$usage" auto "claude-fable-5" | awk -F$'\037' '$3 == "fb" { print $7 }')
    [[ "$long" == *"op sits at 33%"* ]]
    # no roomier sibling in the payload: no model to name, so no fake advice
    solo="{\"five_hour\":{\"utilization\":40},\"seven_day\":{\"utilization\":53,\"resets_at\":\"$reset_7d\"},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":91,\"resets_at\":\"$reset_7d\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    [[ "$(notice_collect "$solo" auto "claude-fable-5" | awk -F$'\037' '$3 == "fb" { print $6 }')" == *"spread the load" ]]
}

@test "notice_collect: a model level with the account says nothing about switching" {
    reset_7d=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    # 75% scoped vs 70% account: the model is not the binding constraint
    usage="{\"five_hour\":{\"utilization\":40},\"seven_day\":{\"utilization\":70,\"resets_at\":\"$reset_7d\"},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":75,\"resets_at\":\"$reset_7d\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    [ -z "$(notice_collect "$usage" auto "claude-fable-5" | awk -F$'\037' '$3 == "fb"')" ]
}

# One wall, two pools. Default: five days into the week, both counters
# resetting at the same instant — the shape the mix reading is only ever
# allowed to speak in.
_mix_reset() { date -u -d "${1:-+2 days}" '+%Y-%m-%dT%H:%M:%SZ'; }
_mix_usage() { # seven scope [reset-iso] [scope-wall-skew-secs]
    local seven="$1" scope="$2" r7="${3:-}" skew="${4:-0}" rfb
    [ -n "$r7" ] || r7=$(_mix_reset)
    rfb=$(date -u -d "$r7 + $skew seconds" '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"five_hour":{"utilization":40},"seven_day":{"utilization":%s,"resets_at":"%s"},"limits":[{"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"display_name":"Fable"}}}]}' \
        "$seven" "$r7" "$scope" "$rfb"
}
_strand_recs() { notice_collect "$(_mix_usage "$1" "$2" "${3:-}" "${4:-0}")" auto claude-fable-5; }
_strand_key() { _strand_recs "$@" | awk -F$'\037' '$4 ~ /strand/ { print $4 }'; }

@test "notice_collect: the account caps first, so the model's own pool strands" {
    # 81 against 63 — the live reading the model was built from. Both
    # counters run from one reset instant, so the ratio IS this week's mix
    # (0.78, against 0.77 mined from the corpus): the 19 account points left
    # carry 15 of the 37 the model still has, and 22 expire unreachable.
    recs=$(_strand_recs 81 63)
    _fb() { printf '%s\n' "$recs" | awk -F$'\037' -v n="$1" '$3 == "fb" { print $n }'; }
    [ "$(_fb 1)" = "58" ]
    [ "$(_fb 2)" = "+" ]
    [ "$(_fb 4)" = "fb.strand.4" ]
    [ "$(_fb 5)" = "~22%" ]
    [ "$(_fb 6)" = "fb ~22% expires at this mix" ]
    [ "$(_fb 7)" = "7d caps before fb: this mix reaches ~15% of its 37% left · run fb heavier to extract more" ]
    # the key re-flashes as the strand grows, like the surplus voice
    [ "$(_strand_key 81 59)" = "fb.strand.5" ]
}

@test "notice_collect: every gate the mix reading stands on" {
    # a week that has barely started: the ratio is two days of noise
    [ -z "$(_strand_key 81 63 "$(_mix_reset '+6 days 12 hours')")" ]
    # two walls 5 minutes apart would be a ratio of two different weeks;
    # the observed jitter between them is seconds
    [ -z "$(_strand_key 81 63 "" 300)" ]
    [ -n "$(_strand_key 81 63 "" 60)" ]
    # a model untouched this week belongs to the underuse voice, not here
    [ -z "$(_strand_key 81 4)" ]
    [ -n "$(_strand_key 81 5)" ]
    # ...and the question only exists once the account's own end is in sight
    [ -z "$(_strand_key 59 30)" ]
    [ -n "$(_strand_key 60 30)" ]
    # under 10 points there is nothing to act on
    [ -z "$(_strand_key 70 64)" ]
    [ -n "$(_strand_key 70 63)" ]
    # either pool at 100 is its own notice, and neither is a mix
    [ -z "$(_strand_key 81 100)" ]
    [ -z "$(_strand_key 100 63)" ]
}

@test "notice_collect: a model projected to cap first cannot also be stranding" {
    # 85 against 95 five days in: the linear scoped pace hits the model's own
    # cap a day before its reset, so the frame already says fb runs out
    r=$(_mix_reset)
    [[ "$(notice_collect "$(_mix_usage 95 85 "$r")" auto claude-fable-5 \
        | awk -F$'\037' '$3 == "fb" { print $4 }')" == fb.caps.* ]]
    [ -z "$(_strand_key 95 85 "$r")" ]
    # the same two numbers with the wall 20h out: the projection no longer
    # reaches the cap, and what the account cannot spend strands again
    [ "$(_strand_key 95 85 "$(_mix_reset '+20 hours')")" = "fb.strand.2" ]
}

@test "notice_collect: the mix stays quiet while the denominator is suspect" {
    tmpdir=$(mktemp -d)
    export CLAUDE_ACCOUNT_DIR="$tmpdir"
    r=$(_mix_reset)
    # first sight of the window, then 78 -> 65 inside it. A plan change moved
    # one of the two counters for a reason the ratio cannot see.
    notice_collect "$(_mix_usage 78 40 "$r")" auto claude-fable-5 >/dev/null
    recs=$(notice_collect "$(_mix_usage 65 40 "$r")" auto claude-fable-5)
    [ -n "$(printf '%s\n' "$recs" | awk -F$'\037' '$4 ~ /rebase/')" ]
    [ -z "$(printf '%s\n' "$recs" | awk -F$'\037' '$4 ~ /strand/')" ]
    # once the re-base is no longer newsworthy the same frame speaks
    rm -f "$tmpdir/seven_seen"
    [ "$(_strand_key 65 40 "$r")" = "fb.strand.7" ]
    unset CLAUDE_ACCOUNT_DIR
    rm -rf "$tmpdir"
}

@test "notice_collect: the wall pins the row, the strand it causes flashes" {
    state=$(mktemp -d)/notice_seen
    recs=$(_strand_recs 81 63)
    # the account wall is the pressure and owns row 2; the strand is its
    # consequence, and a consequence never outranks its cause
    [[ "$(strip_ansi "$(notice_pin_line "$recs")")" == "! 7d caps ~"* ]]
    flash=$(strip_ansi "$(notice_flash_line "$recs" "$state" "$(date +%s)")")
    [[ "$flash" == "+ 7d caps before fb: this mix reaches ~15%"* ]]
    rm -rf "$(dirname "$state")"
}

@test "notice_collect: 7d falling inside one window reads as a re-base, not as burn" {
    tmpdir=$(mktemp -d)
    export CLAUDE_ACCOUNT_DIR="$tmpdir"
    reset_7d=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    _u() { printf '{"five_hour":{"utilization":40},"seven_day":{"utilization":%s,"resets_at":"%s"}}' "$1" "$reset_7d"; }
    # first sight: nothing to compare against
    notice_collect "$(_u 53)" auto >/dev/null
    [ -z "$(notice_collect "$(_u 53)" auto | grep rebase)" ]
    # same window instance, utilization collapses: a plan change or an
    # out-of-band reset — burn never runs backwards
    short=$(notice_collect "$(_u 12)" auto | awk -F$'\037' '$4 ~ /rebase/ { print $6 }')
    [ "$short" = "7d rebased 53%→12%" ]
    # it stays newsworthy across renders, not just the one that caught it
    [ -n "$(notice_collect "$(_u 12)" auto | grep rebase)" ]
    # ...and the underuse voice stays quiet while the denominator is suspect
    [ -z "$(notice_collect "$(_u 12)" auto | grep 'go heavier')" ]
    unset CLAUDE_ACCOUNT_DIR
    rm -rf "$tmpdir"
}

@test "notice_collect: a closing 5h window only matters when the week has slack" {
    reset_5h=$(date -u -d '+40 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    # week on pace: an unspent 5h window is headroom, not waste — silence
    reset_7d=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":30,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":60,\"resets_at\":\"$reset_7d\"}}"
    [ -z "$(notice_collect "$usage" auto | awk -F$'\037' '$3 == "5h"')" ]
    # week stranding capacity: the same window is throughput you cannot bank
    reset_7d=$(date -u -d '+20 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":30,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":40,\"resets_at\":\"$reset_7d\"}}"
    short=$(notice_collect "$usage" auto | awk -F$'\037' '$3 == "5h" { print $6 }')
    [[ "$short" =~ ^5h\ ~[0-9]+m\ left\ ·\ 70%\ unused$ ]]
}

@test "strip_tail: hide drops the reset line 1 already prints, keeps the pace" {
    now=$(date +%s)
    show=$(strip_ansi "$(strip_tail 50 3600 18000 "$now" show)")
    hide=$(strip_ansi "$(strip_tail 50 3600 18000 "$now" hide)")
    [[ "$show" =~ ^\ [0-9]\.[0-9]✕\ @[0-9]{2}:[0-9]{2}$ ]]
    [[ "$hide" =~ ^\ [0-9]\.[0-9]✕$ ]]
    # default is still show: `--week` on its own has no badge above it
    [ "$(strip_ansi "$(strip_tail 50 3600 18000 "$now")")" = "$show" ]
}

@test "integration: the 5h strip drops the reset the 5h badge already carries" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    _seed_week_store "$tmpdir/.claude/statusline"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(jq -r .seven_day.resets_at "$tmpdir/.claude/statusline/usage.cache")
    input=$(printf '{"session_id":"dedup","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"context_window":{"used_percentage":10,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":"%s"},"seven_day":{"used_percentage":55,"resets_at":"%s"}}}' "$reset_5h" "$reset_7d")
    out=$(printf '%s' "$input" | HOME="$tmpdir" COLUMNS=160 bash "$SCRIPT_DIR/statusline.sh" --notice off)
    l1=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 1p)")
    l2=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 2p)")
    # line 1 carries the 5h reset, so the 5h strip does not repeat it
    re_badge='5h\[40%@[0-9]{2}:[0-9]{2}\]'
    re_strip='5h [^ ]+ [0-9]\.[0-9]✕  7d'
    re_seven='7d .*[0-9]{2}:[0-9]{2}$'
    [[ "$l1" =~ $re_badge ]]
    [[ "$l2" =~ $re_strip ]]
    # the 7d badge shows no reset here, so its strip still labels its own end
    [[ ! "$l1" =~ 7d\[[0-9]+%@ ]]
    [[ "$l2" =~ $re_seven ]]
    rm -rf "$tmpdir"
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
    # the strip beside the pin already prints @HH:MM; the pin spends its
    # columns on the number you act on
    [[ "$plain" =~ ^\+\ last\ 5h\ of\ the\ week\ ·\ 56%\ unused$ ]]
    [[ "$result" == *'\033[0;36m'* ]]
    # ...and the number is the bolded part
    [[ "$result" == *'\033[1m56%\033[22m'* ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto)")")
    [[ "$long" =~ ^\+\ 7d\ resets\ in\ .*:\ the\ last\ 5h\ window\ of\ the\ period\ ·\ 56%\ of\ the\ week\ is\ unused\ and\ expires\ with\ it$ ]]
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
    [[ "$plain" =~ ^\+\ 35%\ unused\ ·\ spend\ it$ ]]
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
    seven=$(CLAUDE_ACCOUNT_DIR="$tmpdir" notice_collect "$usage" auto | awk -F$'\037' '$3 == "7d" { print $6 }')
    [[ "$seven" =~ ^last\ 5h\ of\ the\ week\ ·\ 56%\ unused\ ·\ ~53%\ expires\ even\ at\ full\ burn$ ]]
    [[ "$seven" != *"spend it"* ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: feasibility counts awake hours, not wall hours" {
    tmpdir=$(mktemp -d)
    CLAUDE_ACCOUNT_DIR="$tmpdir"
    export TZ=UTC
    # ppw=30, a fresh 5h window and 20h of week left: on the clock alone the
    # 35% surplus is reachable and the line says spend it.
    _write_ppw_fixture "$tmpdir" 30
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+20 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":10,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":65,\"resets_at\":\"$reset_7d\"}}"
    plain=$(strip_ansi "$(build_advisor_line "$usage" auto)")
    [[ "$plain" =~ ^\+\ 35%\ unused\ ·\ spend\ it$ ]]
    # Learn that 22 of the next 24 hours are rest and the same clock buys
    # nothing: "spend it" at 23:00 was advice to burn a third of a week
    # through eight hours of sleep.
    _add_hour_profile "$tmpdir/forecast.cache" "$(_hour_profile_from_now -1 22)"
    plain=$(strip_ansi "$(build_advisor_line "$usage" auto)")
    [[ "$plain" =~ ^\+\ 35%\ unused\ ·\ ~35%\ expires\ even\ at\ full\ burn$ ]]
    rm -rf "$tmpdir"
}

@test "notice_collect: hot 5h and expiring surplus are two records, not one crammed row" {
    # The utilization-gap case: 5h nearly spent, 7d resets an hour later with
    # half the week unused. Two scopes, two stories: the wall pins row 2
    # (pressure outranks opportunity) and the surplus keeps its own record —
    # the old row crammed both into one "; " sentence nobody could scan.
    reset_5h=$(date -u -d '+55 minutes' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":95,\"resets_at\":\"$reset_5h\"},\"seven_day\":{\"utilization\":44,\"resets_at\":\"$reset_7d\"}}"
    records=$(notice_collect "$usage" auto)
    [ "$(printf '%s\n' "$records" | wc -l)" -ge 2 ]
    [ "$(printf '%s\n' "$records" | sed -n 1p | cut -d$'\037' -f3)" = "5h" ]
    [ "$(printf '%s\n' "$records" | sed -n 2p | cut -d$'\037' -f3)" = "7d" ]
    result=$(build_advisor_line "$usage" auto)
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^!\ 5h\ caps\ ~[0-9]{2}:[0-9]{2}$ ]]
    [[ "$result" == *'\033[0;31m'* ]]
    # one scope, one voice: the 7d record never doubles up on the 5h pin
    [ "$(printf '%s\n' "$records" | cut -d$'\037' -f3 | sort | uniq -d)" = "" ]
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
    [[ "$plain" =~ ^\+\ ~62%\ will\ expire\ ·\ go\ heavier$ ]]
    [[ "$result" == *'\033[0;36m'* ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto)")")
    [[ "$long" =~ ^\+\ 7d\ on\ pace\ to\ leave\ ~62%\ unused\ ·\ go\ heavier$ ]]
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
    [[ "$plain" =~ ^\+\ ~7[01]%\ will\ expire\ ·\ go\ heavier$ ]]
    rm -rf "$tmpdir"
}

@test "build_advisor_line: capped scoped limit names the model and its return time" {
    reset_7d=$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')
    reset_sc=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20},\"seven_day\":{\"utilization\":20,\"resets_at\":\"$reset_7d\"},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":100,\"resets_at\":\"$reset_sc\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    result=$(build_advisor_line "$usage" auto "claude-fable-5")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^!\ fb\ capped\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2}$ ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto "claude-fable-5")")")
    [[ "$long" =~ ^!\ fb\ capped\ ·\ back\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2} ]]
    [[ "$result" == *'\033[0;31m'* ]]
}

@test "build_advisor_line: scoped-limit pace projects the model cap before its reset" {
    reset_sc=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20},\"seven_day\":{\"utilization\":20},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":92,\"resets_at\":\"$reset_sc\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    result=$(build_advisor_line "$usage" auto "claude-fable-5")
    plain=$(strip_ansi "$result")
    # 92% on the model against 20% on the account: the wall is real, and the
    # way out (another model) is the pin. Pressure voice, because there IS a
    # wall; the deadline itself rides the long form.
    [[ "$plain" =~ ^!\ fb\ 92%\ vs\ 7d\ 20%\ ·\ spread\ the\ load$ ]]
    [[ "$result" == *'\033[0;31m'* ]]
    long=$(strip_ansi "$(notice_long_line "$(notice_collect "$usage" auto "claude-fable-5")")")
    [[ "$long" =~ dry\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2} ]]
}

@test "build_advisor_line: a model that caps with no roomier sibling states the deadline" {
    # account as deep as the model (no steering to do): the bare deadline
    reset_sc=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ')
    usage="{\"five_hour\":{\"utilization\":20},\"seven_day\":{\"utilization\":85,\"resets_at\":\"$reset_7d\"},\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":92,\"resets_at\":\"$reset_sc\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}"
    fb=$(notice_collect "$usage" auto "claude-fable-5" | awk -F$'\037' '$3 == "fb" { print $6 }')
    [[ "$fb" =~ ^fb\ caps\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2}$ ]]
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
        printf '{"session_id":"adv","model":{"id":"claude-opus-4-8","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"context_window":{"used_percentage":10,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":"%s"},"seven_day":{"used_percentage":%s,"resets_at":"%s"}}}' "$1" "$reset_5h" "${2:-10}" "$reset_7d"
    }
    hot=$(_mk_input 85 | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh" --notice off)
    [ "$(printf '%s\n' "$hot" | wc -l)" -eq 2 ]
    [[ "$(strip_ansi "$hot")" == *"5h caps ~"* ]]
    # one condition is one row: row 3 does not restate the pin above it
    lone=$(_mk_input 85 | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh")
    [ "$(printf '%s\n' "$lone" | wc -l)" -eq 2 ]
    calm=$(_mk_input 20 | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh")
    [ "$(printf '%s\n' "$calm" | wc -l)" -eq 1 ]
    # a SECOND condition this session has not seen earns row 3 with its own
    # sentence — the 7d wall the 5h pin says nothing about. Last in the
    # sequence on purpose: a later render at a lower 7d would read this
    # window as re-based and speak about that instead.
    fresh=$(_mk_input 85 95 | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh")
    [ "$(printf '%s\n' "$fresh" | wc -l)" -eq 3 ]
    [[ "$(strip_ansi "$fresh")" == *"before reset"* ]]
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
        | HOME="$tmpdir" TERM=dumb bash "$SCRIPT_DIR/statusline.sh" --notice off)
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

# --- deadman chip (dead man's switch) ---

# PATH shim standing in for the real deadman binary. Writes a marker file on
# every invocation so tests can assert the fast paths spend NO subshell at all,
# not merely that they render nothing.
make_deadman_shim() { # $1=tmpdir $2=chip output
    mkdir -p "$1/bin"
    printf '#!/bin/bash\ntouch "%s/called"\necho "%s"\n' "$1" "$2" > "$1/bin/deadman"
    chmod +x "$1/bin/deadman"
}

@test "build_deadman_component: armed renders dim countdown chip" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" "armed 42m"
    deadman_display_mode="auto"
    stdin_session_id="dm-armed"
    result=$(PATH="$tmpdir/bin:$PATH"; build_deadman_component)
    [ "$result" = " ${DIM}[☠ armed 42m]${RESET}" ]
    rm -rf "$tmpdir"
}

@test "build_deadman_component: warned escalates to warning color" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" "warned 3m"
    deadman_display_mode="auto"
    stdin_session_id="dm-warned"
    result=$(PATH="$tmpdir/bin:$PATH"; build_deadman_component)
    [ "$result" = " ${YELLOW}[☠ warned 3m]${RESET}" ]
    rm -rf "$tmpdir"
}

@test "build_deadman_component: due keeps the warning color" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" "due"
    deadman_display_mode="auto"
    stdin_session_id="dm-due"
    result=$(PATH="$tmpdir/bin:$PATH"; build_deadman_component)
    [ "$result" = " ${YELLOW}[☠ due]${RESET}" ]
    rm -rf "$tmpdir"
}

@test "build_deadman_component: empty chip output (nothing armed) renders nothing" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" ""
    deadman_display_mode="auto"
    stdin_session_id="dm-idle"
    result=$(PATH="$tmpdir/bin:$PATH"; build_deadman_component)
    [ -z "$result" ]
    rm -rf "$tmpdir"
}

@test "build_deadman_component: deadman not installed renders nothing" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/emptybin"
    deadman_display_mode="auto"
    stdin_session_id="dm-noinstall"
    # Builtins-only PATH: the function must bail at `command -v` before ever
    # needing an external binary — this is the zero-cost absence contract.
    result=$(PATH="$tmpdir/emptybin"; build_deadman_component)
    [ -z "$result" ]
    rm -rf "$tmpdir"
}

@test "build_deadman_component: off mode spends nothing even with deadman armed" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" "armed 42m"
    deadman_display_mode="off"
    stdin_session_id="dm-off"
    result=$(PATH="$tmpdir/bin:$PATH"; build_deadman_component)
    [ -z "$result" ]
    [ ! -e "$tmpdir/called" ]
    rm -rf "$tmpdir"
}

@test "build_deadman_component: empty session id never invokes the tool" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" "armed 42m"
    deadman_display_mode="auto"
    stdin_session_id=""
    result=$(PATH="$tmpdir/bin:$PATH"; build_deadman_component)
    [ -z "$result" ]
    [ ! -e "$tmpdir/called" ]
    rm -rf "$tmpdir"
}

@test "integration: deadman chip renders on line 1 next to the path" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" "armed 42m"
    out=$(echo '{"session_id":"dm-int","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | PATH="$tmpdir/bin:$PATH" bash "$SCRIPT_DIR/statusline.sh" --test)
    line1=$(strip_ansi "$out" | head -n1)
    [[ "$line1" == *"[☠ armed 42m]"* ]]
    rm -rf "$tmpdir"
}

@test "integration: no chip without a deadman shim on PATH" {
    # Hosts with a real deadman installed still pass: an unarmed/unknown
    # session prints empty by contract, and empty renders nothing.
    out=$(echo '{"session_id":"dm-int-none-e5b1","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | bash "$SCRIPT_DIR/statusline.sh" --test)
    [[ "$(strip_ansi "$out")" != *"☠"* ]]
}

@test "integration: --deadman off suppresses the chip" {
    tmpdir=$(mktemp -d)
    make_deadman_shim "$tmpdir" "armed 42m"
    out=$(echo '{"session_id":"dm-int-off","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | PATH="$tmpdir/bin:$PATH" bash "$SCRIPT_DIR/statusline.sh" --test --deadman off)
    [[ "$(strip_ansi "$out")" != *"☠"* ]]
    rm -rf "$tmpdir"
}

# --- cctrace trace chip (left cluster) ---

@test "build_trace_component: silent without any trace signal" {
    result=$(stdin_session_id="s1" current_dir="/t"; build_trace_component)
    [ -z "$result" ]
}

@test "build_trace_component: CCTRACE_SERVER_PORT renders the chip directly" {
    result=$( (CCTRACE_SERVER_PORT=9317; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:9317/trace]" ]
}

@test "build_trace_component: DEVA_TRACE_UI_URL outranks the container-side port" {
    result=$( (DEVA_TRACE_UI_URL="http://localhost:1355" CCTRACE_SERVER_PORT=9317; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:1355/trace]" ]
}

@test "build_trace_component: a known session id deep-links /s/<sid8>, not /trace" {
    # cctrace >= 0.40 serves /s/<sid8> — a rewrite to /trace#/session/<sid8>,
    # landing on THIS session's conversation scrolled to the newest turn.
    result=$( (DEVA_TRACE_UI_URL="http://localhost:1355" CCTRACE_SERVER_PORT=9317 \
        stdin_session_id="c3a6e0f3-871b-4047-a282-60ca3d2244e6"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:1355/s/c3a6e0f3]" ]
}

@test "build_trace_component: registry stores the sid REDACTED — sid8 prefix still matches" {
    # cctrace's capture-time redaction masks session ids past the first 8 hex
    # before anything lands on disk; the sid8 prefix is the join key.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/instances"
    printf '{"id":"r1","pid":1,"port":9319,"project":"p","projectPath":"/elsewhere","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z","sessionId":"c3a6e0f3-****-****-****-************"}' \
        > "$tmpdir/instances/r1.json"
    result=$( (DEVA_TRACE=1 CCTRACE_DATA_DIR="$tmpdir" stdin_session_id="c3a6e0f3-871b-4047-a282-60ca3d2244e6" current_dir="/t"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:9319/s/c3a6e0f3]" ]
    rm -rf "$tmpdir"
}

@test "build_trace_component: sid8 claims its own entry even when the heartbeat looks stale" {
    # If OUR capture died the session's proxy died with it — an identity
    # match never needs freshness.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/instances"
    printf '{"id":"r1","pid":1,"port":9319,"project":"p","projectPath":"/elsewhere","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z","sessionId":"c3a6e0f3-****-****-****-************"}' \
        > "$tmpdir/instances/r1.json"
    touch -d '10 minutes ago' "$tmpdir/instances/r1.json"
    result=$( (DEVA_TRACE=1 CCTRACE_DATA_DIR="$tmpdir" stdin_session_id="c3a6e0f3-871b-4047-a282-60ca3d2244e6" current_dir="/t"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:9319/s/c3a6e0f3]" ]
    rm -rf "$tmpdir"
}

@test "build_trace_component: a stale live entry never lends its port via fallback" {
    # Crashed captures leave non-tombstoned entries behind for up to a day;
    # the path/only-live fallbacks trust heartbeat-fresh files only.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/instances"
    printf '{"id":"r1","pid":1,"port":9319,"project":"p","projectPath":"/my/proj","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z"}' \
        > "$tmpdir/instances/r1.json"
    touch -d '10 minutes ago' "$tmpdir/instances/r1.json"
    result=$( (DEVA_TRACE=1 CCTRACE_DATA_DIR="$tmpdir" stdin_session_id="unseen-sid-123" current_dir="/my/proj"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [cctrace]" ]
    rm -rf "$tmpdir"
}

@test "build_trace_component: tombstoned runs never lend their port (bare chip)" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/instances"
    printf '{"id":"r1","pid":1,"port":9319,"project":"p","projectPath":"/t","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z","sessionId":"sid-1","endedAt":"2026-01-01T01:00:00Z"}' \
        > "$tmpdir/instances/r1.json"
    result=$( (DEVA_TRACE=1 CCTRACE_DATA_DIR="$tmpdir" stdin_session_id="sid-1" current_dir="/t"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [cctrace]" ]
    rm -rf "$tmpdir"
}

@test "build_trace_component: NODE_EXTRA_CA_CERTS marker derives the registry dir" {
    base=$(mktemp -d)
    tmpdir="$base/cctrace"
    mkdir -p "$tmpdir/mitm" "$tmpdir/instances"
    touch "$tmpdir/mitm/ca-cert.pem"
    printf '{"id":"r1","pid":1,"port":9321,"project":"p","projectPath":"/proj","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z","sessionId":"sid-x"}' \
        > "$tmpdir/instances/r1.json"
    result=$( (NODE_EXTRA_CA_CERTS="$tmpdir/mitm/ca-cert.pem" stdin_session_id="sid-x" current_dir="/t"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:9321/s/sid-x]" ]
    rm -rf "$base"
}

@test "build_trace_component: project-path fallback when the session id is not registered yet" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/instances"
    printf '{"id":"r1","pid":1,"port":9320,"project":"p","projectPath":"/my/proj","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z"}' \
        > "$tmpdir/instances/r1.json"
    printf '{"id":"r2","pid":2,"port":9325,"project":"q","projectPath":"/other","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z"}' \
        > "$tmpdir/instances/r2.json"
    result=$( (DEVA_TRACE=1 CCTRACE_DATA_DIR="$tmpdir" stdin_session_id="unseen" current_dir="/my/proj"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:9320/s/unseen]" ]
    rm -rf "$tmpdir"
}

@test "build_trace_component: two live captures with no match stay honest (bare chip)" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/instances"
    printf '{"id":"r1","pid":1,"port":9320,"project":"p","projectPath":"/a","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z"}' \
        > "$tmpdir/instances/r1.json"
    printf '{"id":"r2","pid":2,"port":9325,"project":"q","projectPath":"/b","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z"}' \
        > "$tmpdir/instances/r2.json"
    result=$( (DEVA_TRACE=1 CCTRACE_DATA_DIR="$tmpdir" stdin_session_id="unseen" current_dir="/c"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [cctrace]" ]
    rm -rf "$tmpdir"
}

@test "build_trace_component: a lone live capture is claimed without a match" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/instances"
    printf '{"id":"r1","pid":1,"port":9322,"project":"p","projectPath":"/a","logFile":"","mode":"mitm","startedAt":"2026-01-01T00:00:00Z"}' \
        > "$tmpdir/instances/r1.json"
    result=$( (DEVA_TRACE=1 CCTRACE_DATA_DIR="$tmpdir" stdin_session_id="unseen" current_dir="/c"; build_trace_component) )
    plain=$(strip_ansi "$result")
    [ "$plain" = " [http://localhost:9322/s/unseen]" ]
    rm -rf "$tmpdir"
}

@test "integration: traced session wears the chip on the left, next to path" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"session_id":"trace-int","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t/proj","workspace":{"current_dir":"/t/proj"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" CCTRACE_SERVER_PORT=9317 DEVA_TRACE_UI_URL="" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" == "proj [http://localhost:9317/s/test-ses]"* ]]
    rm -rf "$tmpdir"
}

@test "integration: untraced session has no chip" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    out=$(echo '{"session_id":"trace-int2","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t/proj","workspace":{"current_dir":"/t/proj"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$out")
    [[ "$plain" != *"cctrace"* ]]
    rm -rf "$tmpdir"
}

# --- advisor row alignment (second line meets line 1's right edge) ---

@test "integration: advisor row right-aligns to line 1's actual edge" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    # 85% only 2h into the 5h window: pace-hot, the advisor projects the cap.
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"five_hour":{"utilization":85,"resets_at":"%s"},"seven_day":{"utilization":10},"fetched_at":%s}' \
        "$reset_5h" "$(date +%s)" > "$tmpdir/.claude/statusline/usage.cache"
    out=$(echo '{"session_id":"align-test","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t/proj","workspace":{"current_dir":"/t/proj"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | HOME="$tmpdir" COLUMNS=110 bash "$SCRIPT_DIR/statusline.sh" --test --notice off)
    line1=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 1p)")
    line2=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 2p)")
    [ -n "$line2" ]
    [ "${#line1}" -eq "${#line2}" ]
    rm -rf "$tmpdir"
}

@test "integration: advisor row still meets the edge when the width guess is low" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"five_hour":{"utilization":85,"resets_at":"%s"},"seven_day":{"utilization":10},"fetched_at":%s}' \
        "$reset_5h" "$(date +%s)" > "$tmpdir/.claude/statusline/usage.cache"
    # No tty, no COLUMNS: the width is tput's guess (TERM=dumb -> 80). Line 1
    # overflows the guess; the advisor must anchor on line 1's real edge, not
    # the guessed one — a pipe's 80 says nothing about the real terminal.
    out=$(echo '{"session_id":"align-low","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t/proj","workspace":{"current_dir":"/t/proj"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | env -u COLUMNS TERM=dumb HOME="$tmpdir" setsid -w bash "$SCRIPT_DIR/statusline.sh" --test --notice off --path-display full --order activity,time,cost,model,user,quota,extra)
    line1=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 1p)")
    line2=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 2p)")
    [ -n "$line2" ]
    [ "${#line1}" -eq "${#line2}" ]
    rm -rf "$tmpdir"
}

@test "integration: a KNOWN narrow width (COLUMNS) clamps every row to the visible edge" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    reset_5h=$(date -u -d '+3 hours' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"five_hour":{"utilization":85,"resets_at":"%s"},"seven_day":{"utilization":10},"fetched_at":%s}' \
        "$reset_5h" "$(date +%s)" > "$tmpdir/.claude/statusline/usage.cache"
    # Claude Code hands COLUMNS to the script (>= 2.1.153): a 60-col terminal
    # cuts line 1 at its edge, so the advisor meets that edge, not the
    # overflowing content's.
    out=$(echo '{"session_id":"align-known","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t/a/very/long/project/path/that/keeps/going/and/going/on","workspace":{"current_dir":"/t/a/very/long/project/path/that/keeps/going/and/going/on"},"version":"2.1.174","cost":{"total_cost_usd":0}}' \
        | COLUMNS=60 HOME="$tmpdir" setsid -w bash "$SCRIPT_DIR/statusline.sh" --test --notice off --path-display full)
    line1=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 1p)")
    line2=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 2p)")
    [ -n "$line2" ]
    [ "${#line1}" -gt 55 ]
    [ "${#line2}" -eq 55 ]
    rm -rf "$tmpdir"
}

@test "integration: a narrow width keeps a short flash beside a long pin" {
    # The regression this guards: row 3's gate used to require the flash to
    # beat the PIN by 12 columns. At 30 columns the pin is `! 5h caps ~23:54`
    # (16) and the flash is cut at its first joint to `! 7d caps ~Tue 07:22`
    # (20) — a gain of 4, so the second notice lost its row for being about a
    # different window than the first. It is a sentence with a number in it;
    # it gets the row. 30 columns is deliberate: the full sentence runs ~38
    # even when the reset gap renders short (`40h` vs `39h59m`), so the joint
    # is always dropped and the lengths here do not drift with the clock.
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude/statusline"
    printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$tmpdir/.claude/.credentials.json"
    reset_5h=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ')
    reset_7d=$(date -u -d '+3 days' '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"five_hour":{"utilization":85,"resets_at":"%s"},"seven_day":{"utilization":75,"resets_at":"%s"},"fetched_at":%s}' \
        "$reset_5h" "$reset_7d" "$(date +%s)" > "$tmpdir/.claude/statusline/usage.cache"
    out=$(echo '{"session_id":"flashfloor","model":{"id":"claude-opus-4-6","display_name":"Opus"},"cwd":"/t","workspace":{"current_dir":"/t"},"cost":{"total_cost_usd":0},"context_window":{"used_percentage":10,"context_window_size":200000}}' \
        | COLUMNS=30 HOME="$tmpdir" bash "$SCRIPT_DIR/statusline.sh")
    [ "$(printf '%s\n' "$out" | wc -l)" -eq 3 ]
    pin=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 2p)" | sed 's/^ *//')
    flash=$(strip_ansi "$(printf '%s\n' "$out" | sed -n 3p)" | sed 's/^ *//')
    [[ "$pin" =~ ^!\ 5h\ caps\ ~[0-9]{2}:[0-9]{2}$ ]]
    [[ "$flash" =~ ^!\ 7d\ caps\ ~[A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2}$ ]]
    # the two rows speak about different windows, and the flash is shorter
    # than the old rule would ever have allowed
    [ $(( ${#flash} - ${#pin} )) -lt 12 ]
    [ "${#flash}" -ge "$NOTICE_FLASH_MIN_CHARS" ]
    rm -rf "$tmpdir"
}

# --- last_logged_model: model context survives markers and foreign samples ---

@test "last_logged_model: newest record with a model wins" {
    tmpdir=$(mktemp -d)
    printf '%s\n' \
        '{"type":"usage","timestamp":1,"model":"claude-opus-4-6"}' \
        '{"type":"usage","timestamp":2,"model":"claude-sonnet-5"}' \
        >"$tmpdir/usage.jsonl"
    result=$(CLAUDE_ACCOUNT_DIR="$tmpdir" last_logged_model)
    [ "$result" = "claude-sonnet-5" ]
    rm -rf "$tmpdir"
}

@test "last_logged_model: session markers do not blank the model" {
    tmpdir=$(mktemp -d)
    printf '%s\n' \
        '{"type":"usage","timestamp":1,"model":"claude-opus-4-6"}' \
        '{"type":"session_end","session_id":"s1","timestamp":2}' \
        '{"type":"session_start","session_id":"s2","timestamp":3}' \
        >"$tmpdir/usage.jsonl"
    result=$(CLAUDE_ACCOUNT_DIR="$tmpdir" last_logged_model)
    [ "$result" = "claude-opus-4-6" ]
    rm -rf "$tmpdir"
}

@test "last_logged_model: cooperating-writer samples (model null) are skipped" {
    tmpdir=$(mktemp -d)
    printf '%s\n' \
        '{"type":"usage","timestamp":1,"model":"claude-opus-4-6"}' \
        '{"type":"usage","timestamp":2,"source":"ccpace/0.1.1","model":null}' \
        >"$tmpdir/usage.jsonl"
    result=$(CLAUDE_ACCOUNT_DIR="$tmpdir" last_logged_model)
    [ "$result" = "claude-opus-4-6" ]
    rm -rf "$tmpdir"
}

@test "last_logged_model: no log, no model, no error" {
    tmpdir=$(mktemp -d)
    result=$(CLAUDE_ACCOUNT_DIR="$tmpdir" last_logged_model)
    [ -z "$result" ]
    rm -rf "$tmpdir"
}

# --- corpus: history is the ACCOUNT's, across every store it was written to

_write_corpus_fixture() {
    # root holds the account's OLD history (untagged days); the tagged dir
    # holds the recent week. Same uuid, two directories — the real layout.
    local root="$1" now d ts
    local tag="$root/accounts/work"
    now=$(date +%s)
    mkdir -p "$tag"
    echo '{"account":{"uuid":"acct-A"}}' > "$tag/profile.cache"
    for (( d = 30; d >= 8; d-- )); do
        ts=$(( now - d * 86400 ))
        printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":10},"five_hour":{"utilization":10,"resets_at":"R%s"}}\n' "$ts" "$d"
        printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":22},"five_hour":{"utilization":40,"resets_at":"R%s"}}\n' "$(( ts + 14400 ))" "$d"
        printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":30},"five_hour":{"utilization":70,"resets_at":"R%s"}}\n' "$(( ts + 28800 ))" "$d"
    done > "$root/usage.jsonl"
    # sediment: a row with no uuid, a row of someone else, a marker
    printf '{"type":"usage","timestamp":%s,"user":{"email":"x@y"},"seven_day":{"utilization":99}}\n' "$(( now - 9 * 86400 ))" >> "$root/usage.jsonl"
    printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-B"},"seven_day":{"utilization":80}}\n' "$(( now - 9 * 86400 ))" >> "$root/usage.jsonl"
    printf '{"type":"session_start","timestamp":%s,"session_id":"s"}\n' "$(( now - 9 * 86400 ))" >> "$root/usage.jsonl"
    for (( d = 7; d >= 1; d-- )); do
        ts=$(( now - d * 86400 ))
        printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":10},"five_hour":{"utilization":10,"resets_at":"R%s"}}\n' "$ts" "$d"
        printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":22},"five_hour":{"utilization":40,"resets_at":"R%s"}}\n' "$(( ts + 14400 ))" "$d"
        printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":30},"five_hour":{"utilization":70,"resets_at":"R%s"}}\n' "$(( ts + 28800 ))" "$d"
    done > "$tag/usage.jsonl"
}

@test "usage_corpus_files: root + every accounts/*/ + own dir, backups first, no repeats" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/accounts/a" "$tmpdir/accounts/b"
    : > "$tmpdir/usage.jsonl"; : > "$tmpdir/usage.jsonl.1"
    : > "$tmpdir/accounts/a/usage.jsonl"; : > "$tmpdir/accounts/b/usage.jsonl.1"
    CLAUDE_DATA_DIR="$tmpdir" CLAUDE_ACCOUNT_DIR="$tmpdir/accounts/a"
    run usage_corpus_files
    [ "$output" = "$tmpdir/usage.jsonl.1
$tmpdir/usage.jsonl
$tmpdir/accounts/a/usage.jsonl
$tmpdir/accounts/b/usage.jsonl.1" ]
    # no data root (function-level callers): the account dir alone
    CLAUDE_DATA_DIR=""
    run usage_corpus_files
    [ "$output" = "$tmpdir/accounts/a/usage.jsonl" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: a fresh tag learns from the account's history at the root" {
    tmpdir=$(mktemp -d)
    _write_corpus_fixture "$tmpdir"
    # per-directory scope: 7 days in the tagged dir, below the 14-day floor
    CLAUDE_DATA_DIR="" CLAUDE_ACCOUNT_DIR="$tmpdir/accounts/work"
    build_seven_day_profile
    [ "$(jq -r '.days_history' "$tmpdir/accounts/work/forecast.cache")" -lt 14 ]
    rm -f "$tmpdir/accounts/work/forecast.cache"
    # the union: 30 days for the same uuid, one level up
    CLAUDE_DATA_DIR="$tmpdir"
    build_seven_day_profile
    [ "$(jq -r '.days_history' "$tmpdir/accounts/work/forecast.cache")" -ge 28 ]
    # still one account: B's 80 never leaks into the profile
    mon=$(jq -r '.weekday_profile["1"]' "$tmpdir/accounts/work/forecast.cache")
    awk -v p="$mon" 'BEGIN{exit !(p >= 19 && p <= 21)}'
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: stamps the corpus it ran over, drops counted" {
    tmpdir=$(mktemp -d)
    _write_corpus_fixture "$tmpdir"
    CLAUDE_DATA_DIR="$tmpdir" CLAUDE_ACCOUNT_DIR="$tmpdir/accounts/work"
    build_seven_day_profile
    fc="$tmpdir/accounts/work/forecast.cache"
    [ "$(jq -r '.corpus.uuid' "$fc")" = "acct-A" ]
    [ "$(jq -r '.corpus.files' "$fc")" = "2" ]
    [ "$(jq -r '.corpus.samples' "$fc")" = "90" ]
    [ "$(jq -r '.corpus.dropped_no_uuid' "$fc")" = "1" ]
    [ "$(jq -r '.corpus.oldest' "$fc")" = "$(head -1 "$tmpdir/usage.jsonl" | jq -r .timestamp)" ]
    rm -rf "$tmpdir"
}

@test "build_seven_day_profile: the same observation in two stores is counted once" {
    tmpdir=$(mktemp -d)
    _write_corpus_fixture "$tmpdir"
    cp "$tmpdir/accounts/work/usage.jsonl" "$tmpdir/usage.jsonl.1"
    CLAUDE_DATA_DIR="$tmpdir" CLAUDE_ACCOUNT_DIR="$tmpdir/accounts/work"
    build_seven_day_profile
    [ "$(jq -r '.corpus.samples' "$tmpdir/accounts/work/forecast.cache")" = "90" ]
    rm -rf "$tmpdir"
}

@test "week_scan: a sample landing in another store invalidates week.cache" {
    tmpdir=$(mktemp -d)
    _write_corpus_fixture "$tmpdir"
    CLAUDE_DATA_DIR="$tmpdir" CLAUDE_ACCOUNT_DIR="$tmpdir/accounts/work"
    sig1=$(usage_corpus_sig)
    sleep 1
    printf '{"type":"usage","timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":31},"five_hour":{"utilization":71,"resets_at":"R1"}}\n' "$(date +%s)" >> "$tmpdir/usage.jsonl"
    sig2=$(usage_corpus_sig)
    [ "$sig1" != "$sig2" ]
    rm -rf "$tmpdir"
}

@test "session_telemetry_json: carries the project basename, never the path" {
    cost_usd=1.5 project_dir="/Users/x/wrk/src/repo-name/" cwd="/Users/x/wrk/src/repo-name/sub"
    run session_telemetry_json
    [ "$(echo "$output" | jq -r .project)" = "repo-name" ]
    [[ "$output" != *"/Users"* ]]
    cost_usd=1.5 project_dir="" cwd="/tmp/other"
    run session_telemetry_json
    [ "$(echo "$output" | jq -r .project)" = "other" ]
    cost_usd=1.5 project_dir="" cwd=""
    run session_telemetry_json
    [ "$(echo "$output" | jq -r .project)" = "null" ]
}
