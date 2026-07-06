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
    for (( d = days; d >= 1; d-- )); do
        ts=$(( now - d * 86400 ))
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":10}}\n' "$ts"
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":22}}\n' "$(( ts + 14400 ))"
        printf '{"timestamp":%s,"user":{"uuid":"acct-A"},"seven_day":{"utilization":30}}\n' "$(( ts + 28800 ))"
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
    [[ "$result" == "ok|1h|1778728000" ]]
    [ "$(jq -r '.ttl_class' "$tmpdir/cache_health")" = "1h" ]
    [ "$(jq -r '.last_active_at' "$tmpdir/cache_health")" = "1778728000" ]
    unset STATUSLINE_TEST_NOW_EPOCH
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
    [[ "$result" == "break|5m|1000" ]]
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

@test "build_cache_indicator: auto hides healthy ttl metadata" {
    result=$(build_cache_indicator "ok|1h|1778728000" "auto")
    [ -z "$result" ]
}

@test "build_cache_indicator: always shows ttl and observed time" {
    result=$(build_cache_indicator "ok|1h|1778728000" "always")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^cache:1h@[0-9]{2}:[0-9]{2}$ ]]
}

@test "build_cache_indicator: building shows ttl metadata" {
    result=$(build_cache_indicator "building|5m|1778728000" "auto")
    plain=$(strip_ansi "$result")
    [[ "$plain" =~ ^cache:5m@[0-9]{2}:[0-9]{2}~$ ]]
}

# --- integration: cache health indicator ---

@test "integration: cache break shows cache! indicator" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo "200000" > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":200100,"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"cache!"* ]]
    rm -rf "$tmpdir"
}

@test "integration: healthy cache shows no indicator" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo "200000" > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":173,"cache_read_input_tokens":209703}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" != *"cache!"* ]]
    [[ "$plain" != *"cache~"* ]]
    rm -rf "$tmpdir"
}

@test "integration: first turn building shows cache~" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":5,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":10,"cache_creation_input_tokens":50000,"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"cache~"* ]]
    rm -rf "$tmpdir"
}

@test "integration: first turn building with 1h breakdown shows ttl class" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":5,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":10,"cache_creation_input_tokens":50000,"cache_creation":{"ephemeral_1h_input_tokens":50000,"ephemeral_5m_input_tokens":0},"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"cache:1h@"* ]]
    [[ "$plain" == *"~"* ]]
    rm -rf "$tmpdir"
}

@test "integration: --cache always shows healthy ttl metadata" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    cat > "$tmpdir/sessions/test-session-id_cache_health" <<'JSON'
{"cache_read":200000,"ttl_class":"1h","last_active_at":1778728000}
JSON
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":173,"cache_read_input_tokens":209703}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test --cache always)
    plain=$(strip_ansi "$result")
    [[ "$plain" == *"cache:1h@"* ]]
    rm -rf "$tmpdir"
}

@test "integration: --cache off hides cache break" {
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/sessions"
    echo "200000" > "$tmpdir/sessions/test-session-id_cache_health"
    result=$(echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/test","workspace":{"current_dir":"/tmp/test"},"cost":{"total_cost_usd":0,"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0},"version":"2.1.150","context_window":{"used_percentage":21,"context_window_size":1000000,"current_usage":{"input_tokens":1,"output_tokens":58,"cache_creation_input_tokens":200100,"cache_read_input_tokens":0}}}' \
        | CLAUDE_CACHE_DIR="$tmpdir/sessions" bash "$SCRIPT_DIR/statusline.sh" --test --cache off)
    plain=$(strip_ansi "$result")
    [[ "$plain" != *"cache!"* ]]
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
