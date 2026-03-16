#!/bin/bash
# Claude Code statusline
# Usage: statusline.sh [--style STYLE] [--order ORDER] [--theme THEME] [--path-display TYPE] [--alignment TYPE] [--test JSON] [--debug]
# Themes: minimal, compact, detailed, developer, manager
# Styles: single-block, unicode-blocks, bracketed-bars, filled-dots, square-blocks, line-segments, ascii-bars, percent-only, fraction-display

progress_bar_style="unicode-blocks"
stat_order="activity,time,cost,model,context,user,quota"
path_display="project" # project, cwd, full, relative
alignment="left-right" # left-right, right-left, center
theme=""
# Context limit: auto-detected from model.id ([1m] suffix = 1M, default = 200k)
# CLAUDE_CONTEXT_LIMIT env override still honored for manual tuning
context_limit_override="${CLAUDE_CONTEXT_LIMIT:-}"
max_output_tokens=${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-32000}
test_mode=false
test_data=""
debug_mode=false

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
        stat_order="model,context,user"
        path_display="project"
        alignment="left-right"
        ;;
    "compact")
        progress_bar_style="unicode-blocks"
        stat_order="activity,time,cost,model,context,user,quota"
        path_display="project"
        alignment="left-right"
        ;;
    "detailed")
        progress_bar_style="bracketed-bars"
        stat_order="model,activity,time,cost,context,user,quota"
        path_display="cwd"
        alignment="left-right"
        ;;
    "developer")
        progress_bar_style="filled-dots"
        stat_order="activity,time,cost,model,context,user,quota"
        path_display="full"
        alignment="right-left"
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
        exceeds_200k_tokens: .exceeds_200k_tokens
    }' 2>/dev/null)
    debug_log "TEST MODE: transformed input: ${input:0:300}..."
else
    input=$(cat)
    debug_log "STDIN INPUT RECEIVED: ${input:0:300}..."
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
    @sh "exceeds_200k=\(.exceeds_200k_tokens // false)"
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

if [ -n "$context_limit_override" ]; then
    context_limit="$context_limit_override"
else
    context_limit=$(get_context_limit "$model_id")
fi

debug_log "PARSED INPUT: model=$model_display (id=$model_id) cwd=$current_dir cost=$cost_usd context_limit=$context_limit exceeds_200k=$exceeds_200k api_duration_ms=$api_duration_ms"

term_width=$(tput cols 2>/dev/null || echo 80)

# Usage quota tracking

get_oauth_token() {
    # 1. Credentials file (Linux, or macOS plaintext fallback)
    local cred_file="$CLAUDE_HOME/.claude/.credentials.json"
    debug_log "get_oauth_token: checking $cred_file (CLAUDE_HOME=$CLAUDE_HOME)"

    if [ -f "$cred_file" ]; then
        local token=$(jq -r '.claudeAiOauth.accessToken // .access_token // empty' "$cred_file" 2>/dev/null)
        if [ -n "$token" ]; then
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
        -H "anthropic-beta: oauth-2025-04-20" \
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
            seven_day_opus:.seven_day_opus
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

format_usage_bar() {
    local percent=$(printf '%.0f' "$1" 2>/dev/null || echo 0)
    local width=${2:-6}

    local filled=$((percent * width / 100))
    [ "$percent" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    echo "${bar}"
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

get_adaptive_ttl() {
    local five_int=${1:-0}
    if [ "$five_int" -ge 80 ]; then echo 30
    elif [ "$five_int" -ge 50 ]; then echo 60
    elif [ "$five_int" -ge 20 ]; then echo 120
    else echo 300
    fi
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

    local five_util=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' 2>/dev/null)
    local seven_util=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' 2>/dev/null)
    local opus_util=$(echo "$usage_data" | jq -r '.seven_day_opus.utilization // 0' 2>/dev/null)
    local sonnet_util=$(echo "$usage_data" | jq -r '.seven_day_sonnet.utilization // 0' 2>/dev/null)

    local five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
    local seven_int=$(printf '%.0f' "$seven_util" 2>/dev/null || echo 0)
    local opus_int=$(printf '%.0f' "$opus_util" 2>/dev/null || echo 0)
    local sonnet_int=$(printf '%.0f' "$sonnet_util" 2>/dev/null || echo 0)

    local parts=()

    # 5h quota (always show if >0)
    if [ "$five_int" -gt 0 ] 2>/dev/null; then
        local color=$(get_usage_color "$five_int")
        parts+=("${DIM}5h${color}[${five_util}%]${RESET}")
    fi

    # 7d aggregate quota (if present and >0)
    if [ "$seven_int" -gt 0 ] 2>/dev/null; then
        local color=$(get_seven_day_color "$seven_int")
        parts+=("${DIM}7d${color}[${seven_util}%]${RESET}")
    fi

    # Model-specific 7d quotas
    # MAX users: show opus only (per your spec: "no need to show sonnet for max users")
    # Others: show sonnet
    if [ "$user_tier" = "MAX" ]; then
        if [ "$opus_int" -gt 0 ] 2>/dev/null; then
            local color=$(get_seven_day_color "$opus_int")
            parts+=("${DIM}op${color}[${opus_util}%]${RESET}")
        fi
    else
        if [ "$sonnet_int" -gt 0 ] 2>/dev/null; then
            local color=$(get_seven_day_color "$sonnet_int")
            parts+=("${DIM}sn${color}[${sonnet_util}%]${RESET}")
        fi
    fi

    local IFS=' '
    echo "${parts[*]}"
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

    if [ -n "$tier" ] && [ -n "$name" ]; then
        echo "${DIM}[${tier}|${name}]${RESET}"
    elif [ -n "$tier" ]; then
        echo "${DIM}[${tier}]${RESET}"
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
            git_info=" (${branch}*)"
        else
            git_info=" (${branch})"
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

if [ -n "$configured_model" ]; then
    # Strip [1m] suffix from configured model for case matching
    local_cfg="${configured_model%%\[1m\]}"
    case "$local_cfg" in
    "opusplan")
        model_text="opusplan"
        model_color='\033[1;35m'
        ;;
    "opus")
        model_text="opus"
        model_color='\033[0;35m'
        ;;
    "sonnet")
        model_text="sonnet"
        model_color='\033[0;36m'
        ;;
    "haiku")
        model_text="haiku"
        model_color='\033[0;34m'
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
    model_text="$runtime_model"
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

YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
DIM_GREEN='\033[2;32m'
DIM_RED='\033[2;31m'
DIM_YELLOW='\033[2;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

context_info=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    debug_log "CONTEXT CALCULATION: transcript_path=$transcript_path context_limit=$context_limit"

    # Extract latest assistant usage: cache_read_input_tokens, input_tokens, output_tokens
    # The transcript JSONL has entries like: {"type":"assistant","message":{"usage":{...}}}
    latest_usage=$(tail -20 "$transcript_path" 2>/dev/null | jq -r '
        select(.type=="assistant" and .message.usage) |
        .message.usage |
        "\(.cache_read_input_tokens // 0),\(.input_tokens // 0),\(.output_tokens // 0)"
    ' 2>/dev/null | tail -1)
    debug_log "CONTEXT EXTRACTION: latest_usage=$latest_usage"

    if [ -n "$latest_usage" ] && [ "$latest_usage" != ",," ] && [ "$latest_usage" != "," ]; then
        IFS=',' read -r cache_tokens input_tokens output_tokens <<<"$latest_usage"
        cache_tokens=${cache_tokens:-0}
        input_tokens=${input_tokens:-0}
        output_tokens=${output_tokens:-0}
        debug_log "CONTEXT TOKENS: cache_read=$cache_tokens input=$input_tokens output=$output_tokens"

        if [ "$cache_tokens" != "0" ] || [ "$input_tokens" != "0" ]; then
            # cache_read + input = total input tokens the model saw (includes system, tools, CLAUDE.md)
            # No additional overhead needed — the API usage already accounts for everything
            input_tokens_total=$((cache_tokens + input_tokens))

            # Match CLI's /context formula: percentage = round(totalTokens / contextWindow * 100)
            # The CLI uses the FULL context window as denominator (not window - output_reserve)
            # This matches what /context displays: e.g. "104k/1000k tokens (10%)"
            context_pct=$((input_tokens_total * 100 / context_limit))

            # Sanity: if exceeds_200k_tokens is true and we computed <100%, force minimum 100%
            if [ "$exceeds_200k" = "true" ] && [ "$context_limit" -le 200000 ] && [ "$context_pct" -lt 100 ]; then
                context_pct=100
            fi

            # Cap at 100% for display (can overshoot in theory)
            [ "$context_pct" -gt 100 ] && context_pct=100

            debug_log "CONTEXT MATH: input_total=$input_tokens_total pct=$context_pct window=$context_limit"

            if [ $context_pct -gt 0 ]; then
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
                    context_info=" ${DIM}[${RESET}${bar_color}${progress_bar}${RESET}${DIM}] ${context_pct}%${RESET}"
                    ;;
                "unicode-blocks")
                    progress_bar=$(render_bar "$context_pct" 6 "█" "░")
                    context_info="${bar_color}[${progress_bar}${context_pct}%]${RESET}"
                    ;;
                "filled-dots")
                    progress_bar=$(render_bar "$context_pct" 6 "●" "○")
                    context_info=" ${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
                    ;;
                "square-blocks")
                    progress_bar=$(render_bar "$context_pct" 6 "▰" "▱")
                    context_info=" ${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
                    ;;
                "line-segments")
                    progress_bar=$(render_bar "$context_pct" 6 "━" "┅")
                    context_info=" ${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
                    ;;
                "ascii-bars")
                    progress_bar=$(render_bar "$context_pct" 6 "|" "░")
                    context_info=" ${bar_color}${progress_bar}${RESET} ${DIM}${context_pct}%${RESET}"
                    ;;
                "single-block")
                    context_info=" ${bar_color}▓${RESET} ${DIM}${context_pct}%${RESET}"
                    ;;
                "percent-only")
                    context_info=" ${bar_color}${context_pct}%${RESET}"
                    ;;
                "fraction-display")
                    ratio_filled=$((context_pct * 8 / 100))
                    context_info=" ${bar_color}${ratio_filled}/8${RESET}"
                    ;;
                *)
                    progress_bar=$(render_bar "$context_pct" 6 "█" "░")
                    context_info="${bar_color}[${progress_bar}${context_pct}%]${RESET}"
                    ;;
                esac
            fi
        fi
    fi
fi

model_component="${model_color}${model_text}${RESET}"
activity_component=""
time_component=""
cost_component=""
context_component="${context_info}"

if [ "$lines_added" != "0" ] && [ "$lines_removed" != "0" ]; then
    activity_component="${DIM_GREEN}+${lines_added}${RESET}${DIM}/${DIM_RED}-${lines_removed}${RESET}"
elif [ "$lines_added" != "0" ]; then
    activity_component="${DIM_GREEN}+${lines_added}${RESET}"
elif [ "$lines_removed" != "0" ]; then
    activity_component="${DIM_RED}-${lines_removed}${RESET}"
fi

if [ "$api_duration_ms" != "0" ]; then
    api_duration_min_calc=$((api_duration_ms / 60000))
    if [ $api_duration_min_calc -eq 0 ]; then
        api_duration_min_calc=1
    fi

    time_component="\033[2;36m${api_duration_min_calc}m${RESET}"
fi

if [ "$cost_usd" != "0" ] && [ "$cost_usd" != "0.00" ]; then
    cost_formatted=$(printf "%.2f" "$cost_usd" | sed 's/\.00$//')
    cost_component="${DIM_YELLOW}\$${cost_formatted}${RESET}"
fi

add_component() {
    local component="$1"
    [ -n "$component" ] && right_parts="${right_parts:+$right_parts }$component"
}

add_component_no_space() {
    local component="$1"
    [ -n "$component" ] && right_parts="${right_parts}$component"
}

quota_component=""
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

    should_fetch=false
    if [ ! -f "$cache_file" ]; then
        should_fetch=true
    else
        fetched_at=$(jq -r '.fetched_at // 0' "$cache_file" 2>/dev/null || echo 0)
        five_util=$(jq -r '.five_hour.utilization // 0' "$cache_file" 2>/dev/null || echo 0)
        age=$(($(date +%s) - fetched_at))

        # Adaptive TTL matching fetch_usage_for_session
        five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
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
    "context") add_component_no_space "$context_component" ;;
    "user") add_component "$user_component" ;;
    "quota") add_component "$quota_component" ;;
    esac
done

format_output() {
    local path_part="${CYAN}${display_path}${RESET}${YELLOW}${git_info}${RESET}"
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
