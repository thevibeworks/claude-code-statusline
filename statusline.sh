#!/bin/bash
# Claude Code statusline
# Usage: statusline.sh [--style STYLE] [--order ORDER] [--theme THEME] [--path-display TYPE] [--alignment TYPE] [--extra MODE] [--test JSON] [--debug]
# Themes: minimal, compact, detailed, developer, manager
# Styles: single-block, unicode-blocks, bracketed-bars, filled-dots, square-blocks, line-segments, ascii-bars, percent-only, fraction-display
# Extra modes: auto (default, shows when quota runs out or extra >= 50%), always, on-limit, off

progress_bar_style="unicode-blocks"
stat_order="activity,time,cost,model,user,quota,extra"
path_display="project" # project, cwd, full, relative
alignment="left-right" # left-right, right-left, center
theme=""
# Context limit: auto-detected from model.id ([1m] suffix = 1M, default = 200k)
# CLAUDE_CONTEXT_LIMIT env override still honored for manual tuning
context_limit_override="${CLAUDE_CONTEXT_LIMIT:-}"
extra_display_mode="auto" # auto, always, on-limit, off
test_mode=false
test_data=""
debug_mode=false

# Auto-display thresholds: two signal types gate countdown and extra visibility
#   Signal 1 — percentage: how much quota is consumed
#   Signal 2 — time proximity: how close is the next reset window
FIVE_HOUR_COUNTDOWN_SECS=7200    # show countdown when reset <= 2h
FIVE_HOUR_RECOVERY_SECS=1800     # recovery color when reset <= 30min
SEVEN_DAY_COUNTDOWN_SECS=259200  # show countdown when reset <= 3d
SEVEN_DAY_RECOVERY_SECS=43200    # recovery color when reset <= 12h
EXTRA_AUTO_UTIL_PCT=50           # show extra when its own utilization >= 50%

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve claude home — OrbStack sets $HOME to macOS host path,
# but credentials/settings live in the Linux user's actual home.
CLAUDE_HOME="$HOME"
if [ ! -d "$CLAUDE_HOME/.claude" ]; then
    _real_home=$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f6)
    [ -n "$_real_home" ] && [ -d "$_real_home/.claude" ] && CLAUDE_HOME="$_real_home"
fi

CLAUDE_DATA_DIR="${CLAUDE_DATA_DIR:-$SCRIPT_DIR}"
CLAUDE_CACHE_DIR="${CLAUDE_CACHE_DIR:-$SCRIPT_DIR/sessions}"

# Debug helper
DEBUG_LOG="${DEBUG_LOG:-/tmp/claude-code-statusline.log}"
debug_log() {
    if [ "$debug_mode" = true ]; then
        local msg="[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*"
        echo "$msg" >&2
        echo "$msg" >> "$DEBUG_LOG" 2>/dev/null
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
    --style)
        progress_bar_style="$2"
        shift 2
        ;;
    --order)
        stat_order="$2"
        shift 2
        ;;
    --theme)
        theme="$2"
        shift 2
        ;;
    --path-display)
        path_display="$2"
        shift 2
        ;;
    --alignment)
        alignment="$2"
        shift 2
        ;;
    --extra)
        extra_display_mode="$2"
        shift 2
        ;;
    --test)
        test_mode=true
        if [ -n "$2" ] && [[ "$2" != --* ]]; then
            test_data="$2"
            shift 2
        else
            shift
        fi
        ;;
    --debug)
        debug_mode=true
        shift
        ;;
    *)
        shift
        ;;
    esac
done

debug_log "Script started with: style=$progress_bar_style order=$stat_order theme=$theme"
debug_log "SCRIPT_DIR=$SCRIPT_DIR CLAUDE_DATA_DIR=$CLAUDE_DATA_DIR CLAUDE_CACHE_DIR=$CLAUDE_CACHE_DIR"

command -v jq >/dev/null 2>&1 || { echo "statusline: jq required" >&2; exit 1; }

apply_theme() {
    case "$theme" in
    "minimal")
        progress_bar_style="single-block"
        stat_order="model,user"
        path_display="project"
        alignment="left-right"
        extra_display_mode="off"
        ;;
    "compact")
        progress_bar_style="unicode-blocks"
        stat_order="activity,time,cost,model,user,quota,extra"
        path_display="project"
        alignment="left-right"
        ;;
    "detailed")
        progress_bar_style="bracketed-bars"
        stat_order="model,activity,time,cost,user,quota,extra"
        path_display="cwd"
        alignment="left-right"
        ;;
    "developer")
        progress_bar_style="filled-dots"
        stat_order="activity,time,cost,model,user,quota,extra"
        path_display="full"
        alignment="right-left"
        extra_display_mode="on-limit"
        ;;
    "manager")
        progress_bar_style="percent-only"
        stat_order="cost,time,activity,model,user"
        path_display="project"
        alignment="center"
        ;;
    esac
}

if [ -n "$theme" ]; then
    apply_theme
fi

if [ "$test_mode" = true ]; then
    if [ -n "$test_data" ]; then
        input="$test_data"
    else
        input=$(cat)
    fi
    debug_log "TEST MODE ENABLED: input data: ${input:0:200}..."

    mock_context='{
        "type": "assistant",
        "message": {
            "usage": {
                "cache_read_input_tokens": 130000,
                "input_tokens": 26000
            }
        }
    }'

    temp_transcript="/tmp/statusline-test-$(date +%s).jsonl"
    echo "$mock_context" >"$temp_transcript"

    input=$(echo "$input" | jq --arg transcript "$temp_transcript" '{
        session_id: "test-session-id",
        transcript_path: $transcript,
        cwd: .cwd,
        model: .model,
        workspace: .workspace,
        version: .version,
        output_style: .output_style,
        cost: .cost,
        exceeds_200k_tokens: .exceeds_200k_tokens,
        context_window: (.context_window // {used_percentage: 15, context_window_size: 1000000}),
        effort: .effort,
        fast_mode: .fast_mode,
        rate_limits: .rate_limits
    }' 2>/dev/null)
    debug_log "TEST MODE: transformed input: ${input:0:300}..."
else
    input=$(cat)
    debug_log "RAW STDIN: $input"
fi

# Parse all fields in a single jq call for speed
eval "$(echo "$input" | jq -r '
    @sh "model_display=\(.model.display_name // "Unknown")",
    @sh "model_id=\(.model.id // "")",
    @sh "current_dir=\(.workspace.current_dir // .cwd // "/")",
    @sh "project_dir=\(.workspace.project_dir // "")",
    @sh "cwd=\(.cwd // "")",
    @sh "cost_usd=\(.cost.total_cost_usd // 0)",
    @sh "lines_added=\(.cost.total_lines_added // 0)",
    @sh "lines_removed=\(.cost.total_lines_removed // 0)",
    @sh "api_duration_ms=\(.cost.total_api_duration_ms // 0)",
    @sh "duration_ms=\(.cost.total_duration_ms // 0)",
    @sh "transcript_path=\(.transcript_path // "")",
    @sh "cli_version=\(.version // "")",
    @sh "exceeds_200k=\(.exceeds_200k_tokens // false)",
    @sh "ctx_pct=\(.context_window.used_percentage // "")",
    @sh "ctx_size=\(.context_window.context_window_size // "")",
    @sh "effort_level=\(.effort.level // "")",
    @sh "fast_mode=\(.fast_mode // false)",
    @sh "rl_five_pct=\(.rate_limits.five_hour.used_percentage // "")",
    @sh "rl_five_reset=\(.rate_limits.five_hour.resets_at // "")",
    @sh "rl_seven_pct=\(.rate_limits.seven_day.used_percentage // "")",
    @sh "rl_seven_reset=\(.rate_limits.seven_day.resets_at // "")"
' 2>/dev/null)"

# Detect context window from model ID:
#   CLI function NO(A): if A.includes("[1m]") return 1e6; else return 200000;
get_context_limit() {
    local mid="$1"
    if [[ "$mid" == *"[1m]"* ]]; then
        echo 1000000
    else
        echo 200000
    fi
}

debug_log "PARSED INPUT: model=$model_display (id=$model_id) cwd=$current_dir cost=$cost_usd ctx_pct=$ctx_pct exceeds_200k=$exceeds_200k api_duration_ms=$api_duration_ms"

term_width=$(tput cols 2>/dev/null || echo 80)

YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
DIM_GREEN='\033[2;32m'
DIM_RED='\033[2;31m'
DIM_YELLOW='\033[2;33m'
CYAN='\033[0;36m'
DIM_CYAN='\033[2;36m'
RESET='\033[0m'

# Usage quota tracking

oauth_token_expired() {
    local expires_at="${1:-}"

    if [ -z "$expires_at" ] || [ "$expires_at" = "null" ]; then
        return 1
    fi

    local expiry
    expiry=$(printf '%.0f' "$expires_at" 2>/dev/null) || return 1

    # Claude Code stores expiresAt in milliseconds. Accept seconds for older
    # notes/tools that used second precision.
    if [ "$expiry" -lt 100000000000 ] 2>/dev/null; then
        expiry=$((expiry * 1000))
    fi

    local now_ms="${STATUSLINE_TEST_NOW_MS:-$(($(date +%s) * 1000))}"
    [ $((now_ms + 300000)) -ge "$expiry" ]
}

refresh_oauth_credentials_file() {
    local cred_file="$1"
    local refresh_token scope scope_string payload response http_code body

    [ -f "$cred_file" ] || return 1

    refresh_token=$(jq -r '.claudeAiOauth.refreshToken // empty' "$cred_file" 2>/dev/null)
    [ -n "$refresh_token" ] || return 1

    mkdir -p "$CLAUDE_CACHE_DIR"
    local lock_file="$CLAUDE_CACHE_DIR/oauth_refresh.lock"
    if [ -f "$lock_file" ]; then
        local lock_age=$(($(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo 0)))
        [ "$lock_age" -lt 30 ] && return 1
        rm -f "$lock_file"
    fi
    touch "$lock_file"

    scope_string=$(jq -r '.claudeAiOauth.scopes // [] | join(" ")' "$cred_file" 2>/dev/null)
    if [ -z "$scope_string" ]; then
        scope_string="user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    fi

    payload=$(jq -n \
        --arg refresh "$refresh_token" \
        --arg scope "$scope_string" \
        '{
            grant_type:"refresh_token",
            refresh_token:$refresh,
            client_id:"9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            scope:$scope
        }')

    response=$(curl -sS -w "\n%{http_code}" -X POST \
        "https://platform.claude.com/v1/oauth/token" \
        -H "Content-Type: application/json" \
        --data "$payload" \
        --max-time 15)

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    rm -f "$lock_file"

    if [ "$http_code" != "200" ]; then
        debug_log "refresh_oauth_credentials_file: refresh failed (code: $http_code)"
        return 1
    fi

    local access_token new_refresh_token expires_in now_ms expires_at scopes_json tmp_file
    access_token=$(echo "$body" | jq -r '.access_token // empty' 2>/dev/null)
    new_refresh_token=$(echo "$body" | jq -r '.refresh_token // empty' 2>/dev/null)
    expires_in=$(echo "$body" | jq -r '.expires_in // empty' 2>/dev/null)
    scope=$(echo "$body" | jq -r '.scope // empty' 2>/dev/null)

    [ -n "$access_token" ] || return 1
    [ -n "$new_refresh_token" ] || new_refresh_token="$refresh_token"
    [ -n "$expires_in" ] || expires_in=3600
    [ -n "$scope" ] || scope="$scope_string"

    now_ms="${STATUSLINE_TEST_NOW_MS:-$(($(date +%s) * 1000))}"
    expires_at=$((now_ms + expires_in * 1000))
    scopes_json=$(printf '%s' "$scope" | jq -R 'split(" ") | map(select(length > 0))')

    tmp_file="${cred_file}.tmp.$$"
    jq \
        --arg access "$access_token" \
        --arg refresh "$new_refresh_token" \
        --argjson expires "$expires_at" \
        --argjson scopes "$scopes_json" \
        '.claudeAiOauth.accessToken = $access
         | .claudeAiOauth.refreshToken = $refresh
         | .claudeAiOauth.expiresAt = $expires
         | .claudeAiOauth.scopes = $scopes' \
        "$cred_file" >"$tmp_file" 2>/dev/null || {
            rm -f "$tmp_file"
            return 1
        }
    chmod 600 "$tmp_file" 2>/dev/null || true
    mv -f "$tmp_file" "$cred_file"

    debug_log "refresh_oauth_credentials_file: refreshed OAuth token"
    echo "$access_token"
}

get_oauth_token() {
    # 1. Credentials file (Linux, or macOS plaintext fallback)
    local cred_file="$CLAUDE_HOME/.claude/.credentials.json"
    debug_log "get_oauth_token: checking $cred_file (CLAUDE_HOME=$CLAUDE_HOME)"

    if [ -f "$cred_file" ]; then
        local token=$(jq -r '.claudeAiOauth.accessToken // .access_token // empty' "$cred_file" 2>/dev/null)
        if [ -n "$token" ]; then
            local expires_at=$(jq -r '.claudeAiOauth.expiresAt // empty' "$cred_file" 2>/dev/null)
            if oauth_token_expired "$expires_at"; then
                debug_log "get_oauth_token: credentials token expired, attempting refresh"
                local refreshed_token
                refreshed_token=$(refresh_oauth_credentials_file "$cred_file" 2>/dev/null)
                if [ -n "$refreshed_token" ]; then
                    debug_log "get_oauth_token: refreshed token from credentials file (${#refreshed_token} chars)"
                    echo "$refreshed_token"
                    return 0
                fi
                debug_log "get_oauth_token: refresh failed, using existing token"
            fi
            debug_log "get_oauth_token: token from credentials file (${#token} chars)"
            echo "$token"
            return 0
        fi
    fi

    # 2. macOS Keychain — service="Claude Code-credentials", account=$USER
    if command -v security >/dev/null 2>&1; then
        local keychain_user="${USER:-$(whoami)}"
        local service="Claude Code-credentials"
        debug_log "get_oauth_token: trying macOS Keychain (service=$service account=$keychain_user)"

        local kc_data=$(security find-generic-password -a "$keychain_user" -s "$service" -w 2>/dev/null)
        if [ -n "$kc_data" ]; then
            local token=$(echo "$kc_data" | jq -r '.claudeAiOauth.accessToken // .access_token // empty' 2>/dev/null)
            if [ -n "$token" ]; then
                debug_log "get_oauth_token: token from macOS Keychain (${#token} chars)"
                echo "$token"
                return 0
            fi
        fi
    fi

    debug_log "get_oauth_token: no token found"
    return 1
}

get_user_profile() {
    local token="$1"
    local profile_cache="$CLAUDE_CACHE_DIR/profile.cache"
    debug_log "get_user_profile: starting (cache: $profile_cache)"

    if [ -f "$profile_cache" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$profile_cache" 2>/dev/null || stat -f %m "$profile_cache" 2>/dev/null || echo 0)))
        debug_log "get_user_profile: cache exists, age=${age}s"
        if [ $age -lt 86400 ]; then
            debug_log "get_user_profile: using cached profile"
            cat "$profile_cache"
            return 0
        fi
    fi

    mkdir -p "$CLAUDE_CACHE_DIR"

    debug_log "get_user_profile: fetching from API..."

    local response=$(curl -s -w "\n%{http_code}" -X GET \
        "https://api.anthropic.com/api/oauth/profile" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        --max-time 5)

    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    debug_log "API RESPONSE: HTTP $http_code"
    debug_log "RESPONSE BODY: $body"

    if [ "$http_code" = "200" ]; then
        echo "$body" >"$profile_cache" 2>/dev/null
        debug_log "get_user_profile: profile cached successfully"
        cat "$profile_cache"
        return 0
    else
        debug_log "get_user_profile: API failed (code: $http_code), using cache if available"
        [ -f "$profile_cache" ] && cat "$profile_cache"
        return 1
    fi
}

fetch_usage_for_session() {
    local session_id="$1"
    local cache_file="$CLAUDE_CACHE_DIR/${session_id}.cache"
    local lock_file="$CLAUDE_CACHE_DIR/${session_id}.lock"
    local err_file="$CLAUDE_CACHE_DIR/${session_id}.err"

    mkdir -p "$CLAUDE_CACHE_DIR"
    debug_log "fetch_usage_for_session: session=$session_id"

    if [ -f "$cache_file" ]; then
        local fetched_at=$(jq -r '.fetched_at // 0' "$cache_file" 2>/dev/null)
        local five_util=$(jq -r '.five_hour.utilization // 0' "$cache_file" 2>/dev/null)
        local age=$(($(date +%s) - fetched_at))

        # Adaptive TTL: poll less when quota is low, more when it's hot
        local five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
        local ttl=$(get_adaptive_ttl "$five_int")

        debug_log "fetch_usage_for_session: cache age=${age}s ttl=${ttl}s (5h_util=${five_int}%)"
        if [ $age -lt $ttl ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Exponential backoff on errors
    if [ -f "$err_file" ]; then
        local err_at=$(cat "$err_file" 2>/dev/null || echo 0)
        local err_age=$(($(date +%s) - err_at))
        if [ $err_age -lt 120 ]; then
            debug_log "fetch_usage_for_session: in error backoff (${err_age}s < 120s)"
            [ -f "$cache_file" ] && cat "$cache_file"
            return 0
        fi
        rm -f "$err_file"
    fi

    if [ -f "$lock_file" ]; then
        local lock_age=$(($(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo 0)))
        if [ $lock_age -lt 10 ]; then
            debug_log "fetch_usage_for_session: lock active, skip"
            [ -f "$cache_file" ] && cat "$cache_file"
            return 0
        fi
        rm -f "$lock_file"
    fi

    local token=$(get_oauth_token)
    if [ -z "$token" ]; then
        debug_log "fetch_usage_for_session: no token available"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi

    touch "$lock_file"

    # Use CLI version from input for User-Agent, fall back to generic
    local ua="claude-code/${cli_version:-2.1.76}"

    debug_log "fetch_usage_for_session: fetching (User-Agent: $ua)..."

    local response=$(curl -s -w "\n%{http_code}" -X GET \
        "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "User-Agent: $ua" \
        --max-time 5)

    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    rm -f "$lock_file"

    debug_log "API RESPONSE: HTTP $http_code"
    debug_log "RESPONSE BODY: $body"

    if [ "$http_code" = "200" ]; then
        debug_log "fetch_usage_for_session: success"
        debug_log "USAGE DATA: five_hour=$(echo "$body" | jq -r '.five_hour.utilization // "N/A"') seven_day=$(echo "$body" | jq -r '.seven_day.utilization // "N/A"')"
        local tmp_cache="${cache_file}.tmp.$$"
        echo "$body" | jq --arg ts "$(date +%s)" '. + {fetched_at: ($ts|tonumber)}' >"$tmp_cache" 2>/dev/null
        mv -f "$tmp_cache" "$cache_file"
        rm -f "$err_file"
        cat "$cache_file"
        log_usage_snapshot "$session_id" "$body" "$token"
        return 0
    else
        debug_log "fetch_usage_for_session: API failed (code: $http_code)"
        date +%s >"$err_file" 2>/dev/null
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi
}

get_cached_org_uuid() {
    local profile_cache="$CLAUDE_CACHE_DIR/profile.cache"
    if [ -f "$profile_cache" ]; then
        jq -r '.organization.uuid // empty' "$profile_cache" 2>/dev/null
    fi
}

fetch_prepaid_balance() {
    local org_uuid="$1"
    local cache_file="$CLAUDE_CACHE_DIR/prepaid_credits.cache"
    local lock_file="$CLAUDE_CACHE_DIR/prepaid_credits.lock"
    local err_file="$CLAUDE_CACHE_DIR/prepaid_credits.err"

    [ -n "$org_uuid" ] || return 1

    mkdir -p "$CLAUDE_CACHE_DIR"
    debug_log "fetch_prepaid_balance: org=$org_uuid"

    if [ -f "$cache_file" ]; then
        local fetched_at=$(jq -r '.fetched_at // 0' "$cache_file" 2>/dev/null)
        local age=$(($(date +%s) - fetched_at))
        if [ $age -lt 300 ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    if [ -f "$err_file" ]; then
        local err_at=$(cat "$err_file" 2>/dev/null || echo 0)
        local err_age=$(($(date +%s) - err_at))
        if [ $err_age -lt 120 ]; then
            [ -f "$cache_file" ] && cat "$cache_file"
            return 0
        fi
        rm -f "$err_file"
    fi

    if [ -f "$lock_file" ]; then
        local lock_age=$(($(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo 0)))
        if [ $lock_age -lt 10 ]; then
            [ -f "$cache_file" ] && cat "$cache_file"
            return 0
        fi
        rm -f "$lock_file"
    fi

    local token=$(get_oauth_token)
    if [ -z "$token" ]; then
        debug_log "fetch_prepaid_balance: no token available"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi

    touch "$lock_file"

    local ua="claude-code/${cli_version:-2.1.76}"
    local response=$(curl -s -w "\n%{http_code}" -X GET \
        "https://api.anthropic.com/api/oauth/organizations/${org_uuid}/prepaid/credits" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "User-Agent: $ua" \
        -H "x-organization-uuid: $org_uuid" \
        --max-time 5)

    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    rm -f "$lock_file"

    debug_log "PREPAID API RESPONSE: HTTP $http_code"
    debug_log "PREPAID RESPONSE BODY: $body"

    if [ "$http_code" = "200" ]; then
        local tmp_cache="${cache_file}.tmp.$$"
        echo "$body" | jq --arg ts "$(date +%s)" '. + {fetched_at: ($ts|tonumber)}' >"$tmp_cache" 2>/dev/null
        mv -f "$tmp_cache" "$cache_file"
        rm -f "$err_file"
        cat "$cache_file"
        return 0
    else
        debug_log "fetch_prepaid_balance: API failed (code: $http_code)"
        date +%s >"$err_file" 2>/dev/null
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi
}

log_usage_snapshot() {
    local session_id="$1"
    local usage_data="$2"
    local token="$3"

    mkdir -p "$CLAUDE_DATA_DIR"
    local usage_log="$CLAUDE_DATA_DIR/usage.jsonl"
    debug_log "log_usage_snapshot: session=$session_id"

    detect_session_boundary "$session_id" "$usage_data"

    local user_email=""
    local user_name=""
    local user_uuid=""
    local user_display_name=""
    local has_claude_pro="false"
    local has_claude_max="false"
    local org_name=""
    local org_type=""
    local billing_type=""
    local rate_limit_tier=""

    if [ -n "$token" ]; then
        debug_log "log_usage_snapshot: fetching user profile..."
        local profile=$(get_user_profile "$token")
        if [ -n "$profile" ]; then
            debug_log "log_usage_snapshot: profile received: ${profile:0:100}..."
            eval "$(echo "$profile" | jq -r '
                @sh "user_email=\(.account.email // .email // "")",
                @sh "user_name=\(.account.full_name // .account.display_name // .name // "")",
                @sh "user_uuid=\(.account.uuid // "")",
                @sh "user_display_name=\(.account.display_name // "")",
                @sh "has_claude_pro=\(.account.has_claude_pro // false)",
                @sh "has_claude_max=\(.account.has_claude_max // false)",
                @sh "org_name=\(.organization.name // "")",
                @sh "org_type=\(.organization.organization_type // "")",
                @sh "billing_type=\(.organization.billing_type // "")",
                @sh "rate_limit_tier=\(.organization.rate_limit_tier // "")"
            ' 2>/dev/null)"
            debug_log "log_usage_snapshot: extracted email='$user_email' name='$user_name' uuid='$user_uuid' pro='$has_claude_pro' max='$has_claude_max'"
        else
            debug_log "log_usage_snapshot: no profile data returned"
        fi
    else
        debug_log "log_usage_snapshot: no token provided"
    fi

    echo "$usage_data" | jq -c \
        --arg sid "$session_id" \
        --arg ts "$(date +%s)" \
        --arg email "$user_email" \
        --arg name "$user_name" \
        --arg uuid "$user_uuid" \
        --arg display_name "$user_display_name" \
        --arg pro "$has_claude_pro" \
        --arg max "$has_claude_max" \
        --arg org_name "$org_name" \
        --arg org_type "$org_type" \
        --arg billing "$billing_type" \
        --arg rate_limit "$rate_limit_tier" \
        '{
            type:"usage",
            session_id:$sid,
            timestamp:($ts|tonumber),
            user: {
                email: $email,
                name: $name,
                uuid: $uuid,
                display_name: $display_name,
                subscriptions: {
                    claude_pro: ($pro == "true"),
                    claude_max: ($max == "true")
                }
            },
            organization: {
                name: $org_name,
                type: $org_type,
                billing_type: $billing,
                rate_limit_tier: $rate_limit
            },
            five_hour:.five_hour,
            seven_day:.seven_day,
            seven_day_opus:.seven_day_opus,
            extra_usage:.extra_usage
        }' \
        >>"$usage_log" 2>/dev/null
}

detect_session_boundary() {
    local session_id="$1"
    local usage_data="$2"
    local usage_log="$CLAUDE_DATA_DIR/usage.jsonl"

    local current_five_hour_reset=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    local current_seven_day_reset=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)

    _emit_session_start() {
        jq -n -c --arg sid "$session_id" --arg ts "$(date +%s)" \
            --arg fh "$current_five_hour_reset" --arg sd "$current_seven_day_reset" \
            '{type:"session_start",session_id:$sid,timestamp:($ts|tonumber),
              five_hour_window_end:$fh,seven_day_window_end:$sd}' \
            >>"$usage_log" 2>/dev/null
    }

    if [ ! -f "$usage_log" ]; then
        _emit_session_start
        return 0
    fi

    local last_entry=$(tail -1 "$usage_log" 2>/dev/null)
    if [ -z "$last_entry" ]; then
        _emit_session_start
        return 0
    fi

    local last_five_hour_reset=$(echo "$last_entry" | jq -r '.five_hour.resets_at // .data.five_hour.resets_at // empty' 2>/dev/null)
    local last_session_id=$(echo "$last_entry" | jq -r '.session_id // empty' 2>/dev/null)

    if [ "$last_five_hour_reset" != "$current_five_hour_reset" ] && [ -n "$last_five_hour_reset" ]; then
        if [ -n "$last_session_id" ] && [ "$last_session_id" != "$session_id" ]; then
            jq -n -c --arg sid "$last_session_id" --arg ts "$(date +%s)" \
                '{type:"session_end",session_id:$sid,timestamp:($ts|tonumber)}' \
                >>"$usage_log" 2>/dev/null
        fi
        _emit_session_start
    fi
}

should_show_extra() {
    local mode="$1" five_int="${2:-0}" seven_int="${3:-0}" extra_util="${4:-0}"
    local five_reset_secs="${5:-}" seven_reset_secs="${6:-}"
    case "$mode" in
        "off") return 1 ;;
        "on-limit")
            [ "$five_int" -ge 80 ] || [ "$seven_int" -ge 70 ]
            return $?
            ;;
        "auto")
            # Recovery suppresses pressure: if reset is imminent, quota isn't really "running out"
            if [ "$five_int" -ge 80 ]; then
                if [ -z "$five_reset_secs" ] || [ "$five_reset_secs" -gt $FIVE_HOUR_RECOVERY_SECS ] 2>/dev/null; then
                    return 0
                fi
            fi
            if [ "$seven_int" -ge 70 ]; then
                if [ -z "$seven_reset_secs" ] || [ "$seven_reset_secs" -gt $SEVEN_DAY_RECOVERY_SECS ] 2>/dev/null; then
                    return 0
                fi
            fi
            [ "$extra_util" -ge $EXTRA_AUTO_UTIL_PCT ] && return 0
            return 1
            ;;
        *) return 0 ;;
    esac
}

render_bar() {
    local pct=$1 width=$2 fill_char=$3 empty_char=$4
    local filled=$((pct * width / 100))
    [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
    local empty=$((width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="$fill_char"; done
    for ((i=0; i<empty; i++)); do bar+="$empty_char"; done
    printf '%s' "$bar"
}

format_money_minor() {
    local amount="${1:-}"
    local currency="${2:-USD}"
    local mode="${3:-fit}"

    if [ -z "$amount" ] || [ "$amount" = "null" ]; then
        echo ""
        return
    fi

    local minor
    minor=$(printf '%.0f' "$amount" 2>/dev/null) || {
        echo ""
        return
    }

    local upper_currency
    upper_currency=$(printf '%s' "$currency" | tr '[:lower:]' '[:upper:]')
    local symbol=""
    case "$upper_currency" in
    USD) symbol="$" ;;
    EUR) symbol="€" ;;
    GBP) symbol="£" ;;
    JPY) symbol="¥" ;;
    CAD) symbol="CA$" ;;
    AUD) symbol="A$" ;;
    NZD) symbol="NZ$" ;;
    SGD) symbol="S$" ;;
    BRL) symbol="R$" ;;
    *)   symbol="${upper_currency} " ;;
    esac

    case "$upper_currency" in
    JPY|KRW|VND)
        printf "%s%d" "$symbol" "$minor"
        return
        ;;
    esac

    if [ "$mode" = "whole" ]; then
        printf "%s%d" "$symbol" $(((minor + 50) / 100))
        return
    fi

    local whole=$((minor / 100))
    local cents=$((minor % 100))
    if [ "$cents" -eq 0 ]; then
        printf "%s%d" "$symbol" "$whole"
    else
        printf "%s%d.%02d" "$symbol" "$whole" "$cents"
    fi
}

get_adaptive_ttl() {
    local five_int=${1:-0}
    if [ "$five_int" -ge 80 ]; then echo 30
    elif [ "$five_int" -ge 50 ]; then echo 60
    elif [ "$five_int" -ge 20 ]; then echo 120
    else echo 300
    fi
}

format_duration() {
    local ms=${1:-0}
    [ "$ms" -le 0 ] 2>/dev/null && { echo "0m"; return; }
    local mins=$((ms / 60000))
    [ $mins -eq 0 ] && mins=1
    if [ $mins -ge 60 ]; then
        local h=$((mins / 60))
        local m=$((mins % 60))
        if [ $m -gt 0 ]; then
            echo "${h}h${m}m"
        else
            echo "${h}h"
        fi
    else
        echo "${mins}m"
    fi
}

format_reset_relative() {
    local ts="$1"
    [ -z "$ts" ] || [ "$ts" = "null" ] && return
    local reset_epoch now_epoch delta
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        reset_epoch="$ts"
    else
        reset_epoch=$(date -d "$ts" +%s 2>/dev/null) || return
    fi
    now_epoch=$(date +%s)
    delta=$((reset_epoch - now_epoch))
    [ "$delta" -le 0 ] && { echo "now"; return; }

    local days=$((delta / 86400))
    local hours=$(((delta % 86400) / 3600))
    local mins=$(((delta % 3600) / 60))

    if [ "$days" -gt 0 ]; then
        if [ "$hours" -gt 0 ]; then echo "${days}d${hours}h"
        else echo "${days}d"
        fi
    elif [ "$hours" -gt 0 ]; then
        if [ "$mins" -gt 0 ]; then echo "${hours}h${mins}m"
        else echo "${hours}h"
        fi
    else
        echo "${mins}m"
    fi
}

get_reset_seconds() {
    local ts="$1"
    [ -z "$ts" ] || [ "$ts" = "null" ] && { echo ""; return; }
    local reset_epoch now_epoch
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        reset_epoch="$ts"
    else
        reset_epoch=$(date -d "$ts" +%s 2>/dev/null) || { echo ""; return; }
    fi
    now_epoch=$(date +%s)
    local delta=$((reset_epoch - now_epoch))
    [ "$delta" -lt 0 ] && delta=0
    echo "$delta"
}

get_usage_color() {
    local percent=$(printf '%.0f' "$1" 2>/dev/null || echo 0)
    if [ "$percent" -ge 90 ]; then
        echo "$RED"
    elif [ "$percent" -ge 80 ]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

get_seven_day_color() {
    local percent=$(printf '%.0f' "$1" 2>/dev/null || echo 0)
    if [ "$percent" -ge 85 ]; then
        echo "$RED"
    elif [ "$percent" -ge 70 ]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

build_usage_display() {
    local usage_data="$1"
    local user_tier="${2:-}"  # MAX, PRO, ENT, TEAM, or empty

    if [ -z "$usage_data" ]; then
        echo ""
        return
    fi

    local five_util five_reset seven_util seven_reset opus_util sonnet_util
    eval "$(echo "$usage_data" | jq -r '
        @sh "five_util=\(.five_hour.utilization // 0)",
        @sh "five_reset=\(.five_hour.resets_at // "")",
        @sh "seven_util=\(.seven_day.utilization // 0)",
        @sh "seven_reset=\(.seven_day.resets_at // "")",
        @sh "opus_util=\(.seven_day_opus.utilization // 0)",
        @sh "sonnet_util=\(.seven_day_sonnet.utilization // 0)"
    ' 2>/dev/null)"

    local five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
    local seven_int=$(printf '%.0f' "$seven_util" 2>/dev/null || echo 0)
    local opus_int=$(printf '%.0f' "$opus_util" 2>/dev/null || echo 0)
    local sonnet_int=$(printf '%.0f' "$sonnet_util" 2>/dev/null || echo 0)

    local parts=()

    # 5h quota (always show if >0)
    # Countdown shown when: usage >= 80% (warning) OR reset <= 2h (opportunity)
    # Recovery color (DIM_GREEN) when high usage + reset <= 30min
    if [ "$five_int" -gt 0 ] 2>/dev/null; then
        local color=$(get_usage_color "$five_int")
        local reset_suffix=""
        local reset_secs=""
        [ -n "$five_reset" ] && reset_secs=$(get_reset_seconds "$five_reset")

        local show_reset=false
        [ "$five_int" -ge 80 ] && show_reset=true
        [ -n "$reset_secs" ] && [ "$reset_secs" -le $FIVE_HOUR_COUNTDOWN_SECS ] 2>/dev/null && show_reset=true

        if [ "$show_reset" = true ] && [ -n "$five_reset" ]; then
            if [ "$five_int" -ge 80 ] && [ -n "$reset_secs" ] && [ "$reset_secs" -le $FIVE_HOUR_RECOVERY_SECS ] 2>/dev/null; then
                color="$DIM_GREEN"
            fi
            local rel=$(format_reset_relative "$five_reset")
            [ -n "$rel" ] && reset_suffix="${DIM}~${rel}${color}"
        fi
        parts+=("${DIM}5h${color}[${five_int}%${reset_suffix}]${RESET}")
    fi

    # 7d aggregate quota (if present and >0)
    # Countdown shown when: usage >= 70% (warning) OR reset <= 3d (planning)
    # Recovery color (DIM_GREEN) when high usage + reset <= 12h
    if [ "$seven_int" -gt 0 ] 2>/dev/null; then
        local color=$(get_seven_day_color "$seven_int")
        local reset_suffix=""
        local reset_secs=""
        [ -n "$seven_reset" ] && reset_secs=$(get_reset_seconds "$seven_reset")

        local show_reset=false
        [ "$seven_int" -ge 70 ] && show_reset=true
        [ -n "$reset_secs" ] && [ "$reset_secs" -le $SEVEN_DAY_COUNTDOWN_SECS ] 2>/dev/null && show_reset=true

        if [ "$show_reset" = true ] && [ -n "$seven_reset" ]; then
            if [ "$seven_int" -ge 70 ] && [ -n "$reset_secs" ] && [ "$reset_secs" -le $SEVEN_DAY_RECOVERY_SECS ] 2>/dev/null; then
                color="$DIM_GREEN"
            fi
            local rel=$(format_reset_relative "$seven_reset")
            [ -n "$rel" ] && reset_suffix="${DIM}~${rel}${color}"
        fi
        parts+=("${DIM}7d${color}[${seven_int}%${reset_suffix}]${RESET}")
    fi

    # Model-specific 7d quotas
    # MAX users: show opus only (per your spec: "no need to show sonnet for max users")
    # Others: show sonnet
    if [ "$user_tier" = "MAX" ]; then
        if [ "$opus_int" -gt 0 ] 2>/dev/null; then
            local color=$(get_seven_day_color "$opus_int")
            parts+=("${DIM}op${color}[${opus_int}%]${RESET}")
        fi
    else
        if [ "$sonnet_int" -gt 0 ] 2>/dev/null; then
            local color=$(get_seven_day_color "$sonnet_int")
            parts+=("${DIM}sn${color}[${sonnet_int}%]${RESET}")
        fi
    fi

    local IFS=' '
    echo "${parts[*]}"
}

build_extra_usage_display() {
    local usage_data="$1"
    local balance_data="${2:-}"

    if [ -z "$usage_data" ]; then
        echo ""
        return
    fi

    local extra_present is_enabled monthly_limit used_credits utilization currency
    eval "$(echo "$usage_data" | jq -r '
        @sh "extra_present=\(.extra_usage != null)",
        @sh "is_enabled=\(.extra_usage.is_enabled // "")",
        @sh "monthly_limit=\(if .extra_usage.monthly_limit == null then "null" else (.extra_usage.monthly_limit // "" | tostring) end)",
        @sh "used_credits=\(.extra_usage.used_credits // "")",
        @sh "utilization=\(.extra_usage.utilization // "")",
        @sh "currency=\(.extra_usage.currency // "USD")"
    ' 2>/dev/null)"

    [ "$extra_present" = "true" ] || {
        echo ""
        return
    }

    if [ "$is_enabled" != "true" ]; then
        echo "${DIM}ex[off]${RESET}"
        return
    fi

    local balance_amount balance_currency auto_reload
    if [ -n "$balance_data" ]; then
        eval "$(echo "$balance_data" | jq -r '
            @sh "balance_amount=\(.amount // "")",
            @sh "balance_currency=\(.currency // "USD")",
            @sh "auto_reload=\(.auto_reload_settings.enabled // false)"
        ' 2>/dev/null)"
    fi

    local balance_part=""
    if [ -n "$balance_amount" ] && [ "$balance_amount" != "null" ]; then
        local balance_display
        balance_display=$(format_money_minor "$balance_amount" "${balance_currency:-$currency}")
        [ -n "$balance_display" ] && balance_part=" bal${balance_display}"
    fi

    local auto_reload_part=""
    [ "$auto_reload" = "true" ] && auto_reload_part=" ar"

    if [ "$monthly_limit" = "null" ]; then
        echo "${DIM}ex${GREEN}[unlimited${balance_part}${auto_reload_part}]${RESET}"
        return
    fi

    if [ -z "$used_credits" ] || [ -z "$monthly_limit" ] || [ -z "$utilization" ]; then
        echo ""
        return
    fi

    local used_display limit_display util_int color
    used_display=$(format_money_minor "$used_credits" "$currency")
    limit_display=$(format_money_minor "$monthly_limit" "$currency" whole)
    util_int=$(printf '%.0f' "$utilization" 2>/dev/null || echo 0)
    color=$(get_usage_color "$util_int")

    if [ -z "$used_display" ] || [ -z "$limit_display" ]; then
        echo ""
        return
    fi

    echo "${DIM}ex${color}[${used_display}/${limit_display} ${util_int}%${balance_part}${auto_reload_part}]${RESET}"
}

get_user_tier() {
    local tier=""
    local profile_cache="$CLAUDE_CACHE_DIR/profile.cache"
    if [ -f "$profile_cache" ]; then
        local org_type=$(jq -r '.organization.organization_type // empty' "$profile_cache" 2>/dev/null)
        case "$org_type" in
        "claude_max")        tier="MAX" ;;
        "claude_pro")        tier="PRO" ;;
        "claude_enterprise") tier="ENT" ;;
        "claude_team")       tier="TEAM" ;;
        esac
    fi
    if [ -z "$tier" ]; then
        local cred_file="$CLAUDE_HOME/.claude/.credentials.json"
        if [ -f "$cred_file" ]; then
            local sub_type=$(jq -r '.claudeAiOauth.subscriptionType // empty' "$cred_file" 2>/dev/null)
            case "$sub_type" in
            "claude_max")        tier="MAX" ;;
            "claude_pro")        tier="PRO" ;;
            "claude_enterprise") tier="ENT" ;;
            "claude_team")       tier="TEAM" ;;
            esac
        fi
    fi
    echo "$tier"
}

build_user_info() {
    local tier="$1"
    local name=""

    local profile_cache="$CLAUDE_CACHE_DIR/profile.cache"
    if [ -f "$profile_cache" ]; then
        name=$(jq -r '.account.display_name // empty' "$profile_cache" 2>/dev/null)
    fi

    if [ "${#name}" -gt 8 ]; then
        name="${name:0:7}."
    fi

    local tier_color="$DIM"
    case "$tier" in
        "MAX")       tier_color="$GREEN" ;;
        "PRO")       tier_color="$CYAN" ;;
        "ENT"|"TEAM") tier_color="$DIM_CYAN" ;;
    esac

    if [ -n "$tier" ] && [ -n "$name" ]; then
        echo "${DIM}[${tier_color}${tier}${DIM}|${name}]${RESET}"
    elif [ -n "$tier" ]; then
        echo "${DIM}[${tier_color}${tier}${DIM}]${RESET}"
    elif [ -n "$name" ]; then
        echo "${DIM}[${name}]${RESET}"
    else
        echo ""
    fi
}

build_display_path() {
    local working_dir="${current_dir:-$cwd}"
    local home_dir="${HOME:-/home/$(whoami)}"

    case "$path_display" in
    "project")
        echo "$(basename "$working_dir")"
        ;;
    "cwd")
        if [[ "$working_dir" == "$home_dir"/* ]]; then
            echo "~${working_dir#$home_dir}"
        else
            echo "$working_dir"
        fi
        ;;
    "full")
        echo "$working_dir"
        ;;
    "relative")
        if [ -n "$project_dir" ] && [[ "$working_dir" == "$project_dir"* ]]; then
            local rel_path="${working_dir#$project_dir}"
            if [ -n "$rel_path" ]; then
                echo "$(basename "$project_dir")${rel_path}"
            else
                echo "$(basename "$project_dir")"
            fi
        else
            echo "$(basename "$working_dir")"
        fi
        ;;
    *)
        echo "$(basename "$working_dir")"
        ;;
    esac
}

display_path=$(build_display_path)

git_info=""
if [ -d "$current_dir/.git" ] || git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$current_dir" branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        if ! git -C "$current_dir" diff-index --quiet HEAD -- 2>/dev/null; then
            git_info=" ${YELLOW}(${branch}*)${RESET}"
        else
            git_info=" ${DIM_YELLOW}(${branch})${RESET}"
        fi
    fi
fi

configured_model=""
claude_config_dir="${CLAUDE_CONFIG_DIR:-$CLAUDE_HOME/.claude}"
if [ -f "$claude_config_dir/settings.json" ]; then
    configured_model=$(jq -r '.model // ""' "$claude_config_dir/settings.json" 2>/dev/null || echo "")
fi

get_runtime_model() {
    local id="$1"
    # Strip [1m] suffix for family detection
    local base="${id%%\[*\]}"
    case "$base" in
    *"opus"*)  echo "opus" ;;
    *"sonnet"*) echo "sonnet" ;;
    *"haiku"*) echo "haiku" ;;
    *)         echo "unknown" ;;
    esac
}

# Detect if this is a 1M context model
is_1m_model() {
    [[ "$model_id" == *"[1m]"* ]]
}

runtime_model=$(get_runtime_model "$model_id")

abbreviate_model_id() {
    local m="$1"
    case "$m" in
    claude-opus-*|claude-sonnet-*|claude-haiku-*)
        local family="${m#claude-}"
        family="${family%%-[0-9]*}"
        local rest="${m#claude-${family}-}"
        local major="${rest%%-*}"
        rest="${rest#*-}"
        local minor="${rest%%-*}"
        echo "${family}${major}.${minor}"
        ;;
    *) echo "$m" ;;
    esac
}

if [ -n "$configured_model" ]; then
    local_cfg="${configured_model%%\[1m\]}"
    case "$local_cfg" in
    "opusplan")
        model_text="opusplan"
        model_color='\033[1;35m'
        ;;
    "opus"|claude-opus-*)
        model_color='\033[0;35m'
        if [ "$local_cfg" = "opus" ]; then
            model_text="opus"
        else
            model_text=$(abbreviate_model_id "$local_cfg")
        fi
        ;;
    "sonnet"|claude-sonnet-*)
        model_color='\033[0;36m'
        if [ "$local_cfg" = "sonnet" ]; then
            model_text="sonnet"
        else
            model_text=$(abbreviate_model_id "$local_cfg")
        fi
        ;;
    "haiku"|claude-haiku-*)
        model_color='\033[0;34m'
        if [ "$local_cfg" = "haiku" ]; then
            model_text="haiku"
        else
            model_text=$(abbreviate_model_id "$local_cfg")
        fi
        ;;
    *)
        model_text="$local_cfg"
        model_color='\033[0;37m'
        ;;
    esac
    if is_1m_model; then
        model_text="${model_text}[1m]"
    fi
else
    base_id="${model_id%%\[*\]}"
    abbreviated=$(abbreviate_model_id "$base_id")
    if [ "$abbreviated" != "$base_id" ]; then
        model_text="$abbreviated"
    else
        model_text="$runtime_model"
    fi
    if is_1m_model; then
        model_text="${model_text}[1m]"
    fi
    case "$runtime_model" in
    "opus")
        model_color='\033[2;35m'
        ;;
    "sonnet")
        model_color='\033[2;36m'
        ;;
    "haiku")
        model_color='\033[2;34m'
        ;;
    *)
        model_color='\033[2;37m'
        ;;
    esac
fi

context_info=""
context_pct=""

# Primary: use pre-calculated percentage from CLI (v2.1.132+)
if [ -n "$ctx_pct" ]; then
    context_pct=$(printf '%.0f' "$ctx_pct" 2>/dev/null || echo 0)
    debug_log "CONTEXT (stdin): pct=$context_pct size=${ctx_size:-?}"
# Fallback: parse transcript for older CLI versions
elif [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    debug_log "CONTEXT (transcript fallback): $transcript_path"
    context_limit="${context_limit_override:-${ctx_size:-$(get_context_limit "$model_id")}}"
    latest_usage=$(tail -20 "$transcript_path" 2>/dev/null | jq -r '
        select(.type=="assistant" and .message.usage) |
        .message.usage |
        "\(.cache_read_input_tokens // 0),\(.input_tokens // 0)"
    ' 2>/dev/null | tail -1)
    if [ -n "$latest_usage" ] && [ "$latest_usage" != "," ]; then
        IFS=',' read -r cache_tokens input_tokens <<<"$latest_usage"
        input_tokens_total=$(( ${cache_tokens:-0} + ${input_tokens:-0} ))
        if [ "$context_limit" -gt 0 ] 2>/dev/null && [ "$input_tokens_total" -gt 0 ]; then
            context_pct=$((input_tokens_total * 100 / context_limit))
            [ "$context_pct" -gt 100 ] && context_pct=100
        fi
    fi
fi

if [ -n "$context_pct" ] && [ "$context_pct" -gt 0 ] 2>/dev/null; then
    if [ $context_pct -ge 100 ]; then
        bar_color='\033[0;31m'
    elif [ $context_pct -ge 85 ]; then
        bar_color='\033[0;33m'
    else
        bar_color='\033[0;32m'
    fi

    case "$progress_bar_style" in
    "bracketed-bars")
        progress_bar=$(render_bar "$context_pct" 8 "█" "░")
        context_info="${DIM}[${RESET}${bar_color}${progress_bar}${RESET}${DIM}] ${context_pct}%${RESET}"
        ;;
    "unicode-blocks")
        progress_bar=$(render_bar "$context_pct" 6 "█" "░")
        context_info="${bar_color}[${progress_bar}${context_pct}%]${RESET}"
        ;;
    "filled-dots")
        progress_bar=$(render_bar "$context_pct" 6 "●" "○")
        context_info="${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
        ;;
    "square-blocks")
        progress_bar=$(render_bar "$context_pct" 6 "▰" "▱")
        context_info="${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
        ;;
    "line-segments")
        progress_bar=$(render_bar "$context_pct" 6 "━" "┅")
        context_info="${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
        ;;
    "ascii-bars")
        progress_bar=$(render_bar "$context_pct" 6 "|" "░")
        context_info="${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
        ;;
    "single-block")
        context_info="${bar_color}▓${RESET} ${DIM}${context_pct}%${RESET}"
        ;;
    "percent-only")
        context_info="${bar_color}${context_pct}%${RESET}"
        ;;
    "fraction-display")
        ratio_filled=$((context_pct * 8 / 100))
        context_info="${bar_color}${ratio_filled}/8${RESET}"
        ;;
    *)
        progress_bar=$(render_bar "$context_pct" 6 "█" "░")
        context_info="${bar_color}[${progress_bar}${context_pct}%]${RESET}"
        ;;
    esac
fi

model_suffix=""
if [ "$fast_mode" = "true" ]; then
    model_suffix=" ${DIM}fast${RESET}"
elif [ -n "$effort_level" ] && [ "$effort_level" != "high" ]; then
    model_suffix=" ${DIM}${effort_level}${RESET}"
fi
model_component="${model_color}${model_text}${RESET}${model_suffix}${context_info}"
activity_component=""
time_component=""
cost_component=""
context_component=""

if [ "$lines_added" != "0" ] && [ "$lines_removed" != "0" ]; then
    activity_component="${DIM_GREEN}+${lines_added}${RESET}${DIM}/${DIM_RED}-${lines_removed}${RESET}"
elif [ "$lines_added" != "0" ]; then
    activity_component="${DIM_GREEN}+${lines_added}${RESET}"
elif [ "$lines_removed" != "0" ]; then
    activity_component="${DIM_RED}-${lines_removed}${RESET}"
fi

if [ "$api_duration_ms" != "0" ]; then
    time_text=$(format_duration "$api_duration_ms")
    time_component="${DIM}${time_text}${RESET}"
fi

if [ "$cost_usd" != "0" ] && [ "$cost_usd" != "0.00" ]; then
    cost_formatted=$(printf "%.2f" "$cost_usd" | sed 's/\.00$//')
    cost_component="${DIM_YELLOW}\$${cost_formatted}${RESET}"
fi

add_component() {
    local component="$1"
    [ -n "$component" ] && right_parts="${right_parts:+$right_parts }$component"
}

quota_component=""
extra_component=""
user_component=""
user_tier=""

session_id=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null || echo "")

# OAuth gate: skip quota/user entirely when using API key or custom base URL
# The /api/oauth/usage endpoint only works with OAuth tokens at api.anthropic.com
_may_have_oauth=false
if [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
    debug_log "oauth_gate: API key auth detected, skipping quota/user"
    _may_have_oauth=false
elif [ -n "$ANTHROPIC_BASE_URL" ]; then
    debug_log "oauth_gate: custom base URL ($ANTHROPIC_BASE_URL), skipping quota/user"
    _may_have_oauth=false
elif [ -f "$CLAUDE_HOME/.claude/.credentials.json" ]; then
    # Only set true if the file actually contains an OAuth access token
    if jq -e '.claudeAiOauth.accessToken // empty' "$CLAUDE_HOME/.claude/.credentials.json" >/dev/null 2>&1; then
        _may_have_oauth=true
    else
        debug_log "oauth_gate: credentials file exists but no OAuth token"
    fi
elif command -v security >/dev/null 2>&1; then
    _may_have_oauth=true  # macOS Keychain might have it
fi

if [ -n "$session_id" ] && [ "$_may_have_oauth" = true ]; then
    user_tier=$(get_user_tier)

    # Quota component (needs tier to decide opus vs sonnet)
    cache_file="$CLAUDE_CACHE_DIR/${session_id}.cache"
    lock_file="$CLAUDE_CACHE_DIR/${session_id}.lock"
    err_file="$CLAUDE_CACHE_DIR/${session_id}.err"

    five_int=0
    seven_int_cache=0
    should_fetch=false
    if [ ! -f "$cache_file" ]; then
        should_fetch=true
    else
        eval "$(jq -r '
            @sh "fetched_at=\(.fetched_at // 0)",
            @sh "five_util=\(.five_hour.utilization // 0)",
            @sh "seven_util_cache=\(.seven_day.utilization // 0)"
        ' "$cache_file" 2>/dev/null)"
        age=$(($(date +%s) - fetched_at))
        five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
        seven_int_cache=$(printf '%.0f' "$seven_util_cache" 2>/dev/null || echo 0)
        ttl=$(get_adaptive_ttl "$five_int")
        [ "$age" -ge "$ttl" ] && should_fetch=true
    fi

    # Respect error backoff
    if [ "$should_fetch" = true ] && [ -f "$err_file" ]; then
        err_at=$(cat "$err_file" 2>/dev/null || echo 0)
        err_age=$(($(date +%s) - err_at))
        [ $err_age -lt 120 ] && should_fetch=false
    fi

    if [ "$should_fetch" = true ] && [ ! -f "$lock_file" ]; then
        (fetch_usage_for_session "$session_id" >/dev/null 2>&1 &)
    fi

    if [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
        quota_display=$(build_usage_display "$usage_data" "$user_tier")
        [ -n "$quota_display" ] && quota_component="$quota_display"

        if [ -n "$quota_component" ]; then
            if [ -f "$lock_file" ]; then
                quota_component="${quota_component}${DIM}~${RESET}"
            elif [ -f "$err_file" ]; then
                quota_component="${quota_component}${DIM_RED}!${RESET}"
            fi
        fi

        extra_usage_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null || echo false)
        prepaid_data=""
        if [ "$extra_usage_enabled" = "true" ]; then
            org_uuid=$(get_cached_org_uuid)
            prepaid_cache="$CLAUDE_CACHE_DIR/prepaid_credits.cache"
            prepaid_lock="$CLAUDE_CACHE_DIR/prepaid_credits.lock"
            prepaid_err="$CLAUDE_CACHE_DIR/prepaid_credits.err"
            should_fetch_prepaid=false

            if [ -n "$org_uuid" ]; then
                if [ ! -f "$prepaid_cache" ]; then
                    should_fetch_prepaid=true
                else
                    prepaid_fetched_at=$(jq -r '.fetched_at // 0' "$prepaid_cache" 2>/dev/null || echo 0)
                    prepaid_age=$(($(date +%s) - prepaid_fetched_at))
                    [ "$prepaid_age" -ge 300 ] && should_fetch_prepaid=true
                fi

                if [ "$should_fetch_prepaid" = true ] && [ -f "$prepaid_err" ]; then
                    prepaid_err_at=$(cat "$prepaid_err" 2>/dev/null || echo 0)
                    prepaid_err_age=$(($(date +%s) - prepaid_err_at))
                    [ $prepaid_err_age -lt 120 ] && should_fetch_prepaid=false
                fi

                if [ "$should_fetch_prepaid" = true ] && [ ! -f "$prepaid_lock" ]; then
                    (fetch_prepaid_balance "$org_uuid" >/dev/null 2>&1 &)
                fi

                [ -f "$prepaid_cache" ] && prepaid_data=$(cat "$prepaid_cache" 2>/dev/null)
            fi
        fi

        extra_display=$(build_extra_usage_display "$usage_data" "$prepaid_data")
        if [ -n "$extra_display" ]; then
            if [ -f "$prepaid_lock" ]; then
                extra_display="${extra_display}${DIM}~${RESET}"
            elif [ -f "$prepaid_err" ]; then
                extra_display="${extra_display}${DIM_RED}!${RESET}"
            fi
            extra_component="$extra_display"
        fi
    elif [ -n "$rl_five_pct" ] || [ -n "$rl_seven_pct" ]; then
        stdin_usage=$(jq -n \
            --argjson fp "${rl_five_pct:-null}" \
            --arg fr "${rl_five_reset}" \
            --argjson sp "${rl_seven_pct:-null}" \
            --arg sr "${rl_seven_reset}" \
            '{five_hour:{utilization:$fp,resets_at:(if $fr == "" then null else $fr end)},
              seven_day:{utilization:$sp,resets_at:(if $sr == "" then null else $sr end)}}')
        quota_display=$(build_usage_display "$stdin_usage" "$user_tier")
        [ -n "$quota_display" ] && quota_component="$quota_display"
        five_int=$(printf '%.0f' "${rl_five_pct:-0}" 2>/dev/null || echo 0)
        seven_int_cache=$(printf '%.0f' "${rl_seven_pct:-0}" 2>/dev/null || echo 0)
    fi

    extra_util_pct=0
    if [ -n "$usage_data" ]; then
        extra_util_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' 2>/dev/null)
        extra_util_pct=$(printf '%.0f' "$extra_util_pct" 2>/dev/null || echo 0)
    fi

    five_reset_secs=""
    seven_reset_secs=""
    [ -n "$rl_five_reset" ] && five_reset_secs=$(get_reset_seconds "$rl_five_reset")
    [ -n "$rl_seven_reset" ] && seven_reset_secs=$(get_reset_seconds "$rl_seven_reset")

    if ! should_show_extra "$extra_display_mode" "$five_int" "$seven_int_cache" "$extra_util_pct" "$five_reset_secs" "$seven_reset_secs"; then
        extra_component=""
    fi

    user_component=$(build_user_info "$user_tier")
fi

right_parts=""
IFS=',' read -ra order_array <<<"$stat_order"
for item in "${order_array[@]}"; do
    case "$item" in
    "model") add_component "$model_component" ;;
    "activity") add_component "$activity_component" ;;
    "time") add_component "$time_component" ;;
    "cost") add_component "$cost_component" ;;
    "context") add_component "$context_component" ;;
    "user") add_component "$user_component" ;;
    "quota") add_component "$quota_component" ;;
    "extra") add_component "$extra_component" ;;
    esac
done

format_output() {
    local path_part="${DIM_CYAN}${display_path}${RESET}${git_info}"
    local stats_part="${right_parts}"

    # Strip ANSI escapes for length calculation (portable: printf %b instead of echo -e)
    local path_plain=$(printf '%b' "$path_part" | sed 's/\x1b\[[0-9;]*m//g')
    local stats_plain=$(printf '%b' "$stats_part" | sed 's/\x1b\[[0-9;]*m//g')

    case "$alignment" in
    "left-right")
        local padding=$((term_width - ${#path_plain} - ${#stats_plain} - 5))
        [ $padding -lt 6 ] && padding=6
        printf "%b%*s%b\n" "$path_part" $padding "" "$stats_part"
        ;;
    "right-left")
        local padding=$((term_width - ${#path_plain} - ${#stats_plain} - 5))
        [ $padding -lt 6 ] && padding=6
        printf "%b%*s%b\n" "$stats_part" $padding "" "$path_part"
        ;;
    "center")
        local total_len=$((${#path_plain} + ${#stats_plain}))
        if [ $total_len -lt $((term_width - 10)) ]; then
            local left_padding=$(((term_width - ${#path_plain}) / 2))
            local right_padding=$((term_width - left_padding - ${#path_plain} - ${#stats_plain}))
            [ $right_padding -lt 2 ] && right_padding=2
            printf "%*s%b%*s%b\n" $left_padding "" "$path_part" $right_padding "" "$stats_part"
        else
            local padding=$((term_width - ${#path_plain} - ${#stats_plain} - 5))
            [ $padding -lt 6 ] && padding=6
            printf "%b%*s%b\n" "$path_part" $padding "" "$stats_part"
        fi
        ;;
    *)
        local padding=$((term_width - ${#path_plain} - ${#stats_plain} - 5))
        [ $padding -lt 6 ] && padding=6
        printf "%b%*s%b\n" "$path_part" $padding "" "$stats_part"
        ;;
    esac
}

format_output

if [ "$test_mode" = true ] && [ -n "$temp_transcript" ] && [ -f "$temp_transcript" ]; then
    rm -f "$temp_transcript"
fi
