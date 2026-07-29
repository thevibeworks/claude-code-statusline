#!/bin/bash
# Claude Code statusline
# Usage: statusline.sh [--style STYLE] [--order ORDER] [--theme THEME] [--path-display TYPE] [--alignment TYPE] [--extra MODE] [--cache MODE] [--advisor MODE] [--test JSON] [--debug]
# Themes: minimal, compact, detailed, developer, manager
# Styles: single-block, unicode-blocks, bracketed-bars, filled-dots, square-blocks, line-segments, ascii-bars, percent-only, fraction-display
# Extra modes: auto (default, shows when quota runs out or extra >= 50%), always, on-limit, off
# Advisor modes: auto (default, second line under quota pressure or expiring surplus), always (adds weekly budget when calm), off

progress_bar_style="unicode-blocks"
stat_order="activity,time,cost,model,user,quota,extra"
path_display="project" # project, cwd, full, relative
alignment="left-right" # left-right, right-left, center
theme=""
advisor_display_mode="auto" # auto, always, off
# Context limit: auto-detected from model.id. 1M when the family ships 1M by
# default (e.g. fable — CLI strips its [1m] suffix since 2.1.173) OR when the id
# carries an explicit [1m] opt-in suffix (e.g. opus/sonnet); otherwise 200k.
# CLAUDE_CONTEXT_LIMIT env override still honored for manual tuning
context_limit_override="${CLAUDE_CONTEXT_LIMIT:-}"
extra_display_mode="auto" # auto, always, on-limit, off
cache_display_mode="auto" # auto, always, off
test_mode=false
test_data=""
debug_mode=false

# Auto-display thresholds. The 5h countdown itself is always visible (see
# build_usage_display); these gate the recovery color and extra visibility.
FIVE_HOUR_RECOVERY_SECS=1800     # recovery color when reset <= 30min
SEVEN_DAY_RECOVERY_SECS=43200    # recovery color when reset <= 12h
QUOTA_BUMP_NOTICE_SECS=60        # how long a quota "+N" bump flash stays up
SEVEN_DAY_WINDOW_SECS=604800     # weekly quota window (fixed 7d) for pace math
EXTRA_AUTO_UTIL_PCT=50           # show extra when its own utilization >= 50%
CACHE_BREAK_MIN_TOKENS=2000      # ignore cache drops below this (noise)
CACHE_BREAK_DROP_PCT=5           # cache read must drop >5% to count as break
CACHE_HEAVY_TOKENS=200000        # break badge turns bold-red past this: the
                                 # >200k premium-band prefix, an expensive rewrite
ADVISOR_PACE_MIN_ELAPSED=900     # 5h cap projection needs >=15m of window aged
ADVISOR_FLEET_FRESH_SECS=3600    # sibling account cache older than this is unknown
ADVISOR_FLEET_FREE_PCT=40        # sibling counts as "free" at or under this 5h%
ADVISOR_EXPIRY_HORIZON_SECS=86400 # 7d surplus clause: inside the last day of the week
ADVISOR_SURPLUS_MIN_PCT=30       # unused weekly % that counts as expiring waste
ADVISOR_UNDERUSE_END_PCT=60      # projected end-of-week <= this => underuse advice
ADVISOR_UNDERUSE_MIN_5H=25       # underuse advice only in an engaged session (5h >= this)
# Cache-badge marker. Triple bar (U+2261 IDENTICAL TO): three stacked
# horizontal lines read as layered cache tiers. Single-column text glyph, so
# the padding math is unaffected. Swap for ☰ (U+2630) or Ξ (U+039E) if a
# font tofus it.
CACHE_GLYPH="${CACHE_GLYPH:-≡}"

# Unobserved-TTL default for the cache expiry deadline. Mirrors the CLI's own
# rule (should1hCacheTTL, CC source): claude.ai subscribers in the REPL get
# cache_control ttl:"1h" (confirmed on every breakpoint in live traces);
# API-key / custom-endpoint auth stays on the stock 5m cache. The CLI's own
# FORCE_PROMPT_CACHING_5M / ENABLE_PROMPT_CACHING_1H overrides win when set.
# An observed ephemeral_1h/5m usage breakdown always overrides this default.
# Known gap: a subscriber session that bootstrapped on overage latches 5m,
# which we cannot see — the cache!Nk break badge still reports the miss.
_env_truthy() { case "$1" in 1|true|yes|on) return 0 ;; *) return 1 ;; esac; }
if _env_truthy "${FORCE_PROMPT_CACHING_5M:-}"; then
    CACHE_TTL_DEFAULT="5m"
elif _env_truthy "${ENABLE_PROMPT_CACHING_1H:-}"; then
    CACHE_TTL_DEFAULT="1h"
elif [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
    CACHE_TTL_DEFAULT="5m"
else
    CACHE_TTL_DEFAULT="1h"
fi

# Owner-only by default: caches and the debug log hold account PII (email,
# uuid, org, paths). umask 077 keeps every file/dir we create unreadable to
# other UIDs — important when ~/.claude is a shared bind-mount across containers.
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve claude home — OrbStack sets $HOME to macOS host path,
# but credentials/settings live in the Linux user's actual home.
CLAUDE_HOME="$HOME"
if [ ! -d "$CLAUDE_HOME/.claude" ]; then
    _real_home=$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f6)
    [ -n "$_real_home" ] && [ -d "$_real_home/.claude" ] && CLAUDE_HOME="$_real_home"
fi

# Shared statusline state under the resolved claude home. Account-scoped
# data (usage/profile/prepaid + usage.jsonl) lives at the top level so a
# single fetch serves all concurrent sessions instead of one fetch per
# session. Per-session cache-health state lives under sessions/.
#
#   ~/.claude/statusline/                  <- CLAUDE_DATA_DIR  (account-scoped)
#     usage.cache, profile.cache, prepaid_credits.cache, usage.jsonl
#   ~/.claude/statusline/sessions/         <- CLAUDE_CACHE_DIR (per-session)
#     <session_id>_cache_health
#
# CLAUDE_DATA_DIR / CLAUDE_CACHE_DIR env overrides are still honored for
# back-compat. When unset, they default into ~/.claude/statusline.
STATUSLINE_HOME="$CLAUDE_HOME/.claude/statusline"
CLAUDE_DATA_DIR_OVERRIDDEN=""
_data_dir_set=""
_cache_dir_set=""
[ -n "${CLAUDE_DATA_DIR:-}" ] && { CLAUDE_DATA_DIR_OVERRIDDEN=1; _data_dir_set=1; }
[ -n "${CLAUDE_CACHE_DIR:-}" ] && { CLAUDE_DATA_DIR_OVERRIDDEN=1; _cache_dir_set=1; }
CLAUDE_DATA_DIR="${CLAUDE_DATA_DIR:-$STATUSLINE_HOME}"
CLAUDE_CACHE_DIR="${CLAUDE_CACHE_DIR:-$CLAUDE_DATA_DIR/sessions}"

# Account-scoped data (shared usage/profile/prepaid caches + usage.jsonl)
# anchors on the data dir by default. Back-compat: if the caller overrode
# only CLAUDE_CACHE_DIR (the old single-dir layout where everything lived
# together), keep account data alongside it so the override still works.
if [ -n "$_cache_dir_set" ] && [ -z "$_data_dir_set" ]; then
    CLAUDE_ACCOUNT_DIR="$CLAUDE_CACHE_DIR"
else
    CLAUDE_ACCOUNT_DIR="$CLAUDE_DATA_DIR"
fi

# Account scoping. One ~/.claude used to imply one account; credential
# overlays broke that — deva-style runners bind-mount a different
# .credentials.json per container over the SAME shared ~/.claude, so the
# "account-scoped" caches above would bleed across accounts (B renders A's
# quota whenever A fetched last; profile.cache sticks to the first account
# for 24h). The credentials file itself has no stable identity (tokens
# rotate), so the runner must say which account this session is:
#   STATUSLINE_ACCOUNT  explicit label, wins always
#   DEVA_AUTH_TAG       from deva >= 0.18 (auth-file-<stem>, api-key-<n>, env);
#                       auth-default means single-account -> no scoping
# When set, account state moves to accounts/<tag>/ under the shared dir:
# same-account sessions still share one fetch, different accounts stop
# clobbering each other. An explicit CLAUDE_DATA_DIR/CLAUDE_CACHE_DIR
# override is the caller's layout — respected verbatim, no rescoping.
ACCOUNT_TAG=""
if [ -n "${STATUSLINE_ACCOUNT:-}" ]; then
    ACCOUNT_TAG="$STATUSLINE_ACCOUNT"
elif [ -n "${DEVA_AUTH_TAG:-}" ] && [ "$DEVA_AUTH_TAG" != "auth-default" ]; then
    ACCOUNT_TAG="${DEVA_AUTH_TAG#auth-file-}"
elif [ "${DEVA_AUTH_METHOD:-}" = "credentials-file" ] && [ -n "${DEVA_AUTH_DETAILS:-}" ]; then
    # Containers created by pre-v0.18 deva overlay a credentials file but
    # export no DEVA_AUTH_TAG — only the details string:
    #   "credentials-file (/path/<stem>.credentials.json)"
    #   "credentials-file (provisioning: /path/<stem>.credentials.json)"
    # Without this fallback such sessions silently read the DEFAULT
    # account's caches — the wrong-label/wrong-quota bug this scoping
    # exists to kill. Derive the tag from the file stem, same rule deva
    # itself uses.
    _auth_path="${DEVA_AUTH_DETAILS#*(}"
    _auth_path="${_auth_path%)}"
    _auth_path="${_auth_path##* }"
    _auth_path="${_auth_path##*/}"
    _auth_path="${_auth_path%.credentials.json}"
    ACCOUNT_TAG="${_auth_path%.json}"
    unset _auth_path
fi
# Env-derived path component: filesystem-safe charset, bounded length, no
# dot-leading names (blocks "..", hidden dirs).
ACCOUNT_TAG=$(printf '%s' "$ACCOUNT_TAG" | tr -cd 'A-Za-z0-9._-' | cut -c1-24)
case "$ACCOUNT_TAG" in .*) ACCOUNT_TAG="" ;; esac
if [ -n "$ACCOUNT_TAG" ] && [ -z "$CLAUDE_DATA_DIR_OVERRIDDEN" ]; then
    CLAUDE_ACCOUNT_DIR="$CLAUDE_ACCOUNT_DIR/accounts/$ACCOUNT_TAG"
fi

# One-time graceful migration: older versions wrote account-scoped caches
# and the usage log under $SCRIPT_DIR (and per-session data under
# $SCRIPT_DIR/sessions). If that legacy layout exists and the new shared
# dir has not been populated yet, move it over so history/credentials are
# preserved. Best-effort only — failures fall through to a fresh fetch.
migrate_legacy_state() {
    local legacy_data="$SCRIPT_DIR"
    local legacy_sessions="$SCRIPT_DIR/sessions"

    # Skip when caller pinned custom dirs or legacy == new (no-op).
    [ -n "${CLAUDE_DATA_DIR_OVERRIDDEN:-}" ] && return 0
    [ "$legacy_data" = "$CLAUDE_ACCOUNT_DIR" ] && return 0
    # Legacy state predates account scoping and belongs to the default
    # account — never migrate it into whichever tagged account runs first.
    [ -n "$ACCOUNT_TAG" ] && return 0

    local moved=false
    if [ ! -d "$CLAUDE_ACCOUNT_DIR" ]; then
        local f found=false
        for f in usage.cache profile.cache prepaid_credits.cache usage.jsonl; do
            [ -e "$legacy_data/$f" ] && found=true && break
        done
        [ -d "$legacy_sessions" ] && found=true
        [ "$found" = true ] || return 0

        mkdir -p "$CLAUDE_ACCOUNT_DIR" 2>/dev/null || return 0
        for f in usage.cache profile.cache prepaid_credits.cache usage.jsonl; do
            if [ -e "$legacy_data/$f" ] && [ ! -e "$CLAUDE_ACCOUNT_DIR/$f" ]; then
                mv -f "$legacy_data/$f" "$CLAUDE_ACCOUNT_DIR/$f" 2>/dev/null && moved=true
            fi
        done
        if [ -d "$legacy_sessions" ] && [ ! -d "$CLAUDE_CACHE_DIR" ]; then
            mkdir -p "$(dirname "$CLAUDE_CACHE_DIR")" 2>/dev/null
            mv -f "$legacy_sessions" "$CLAUDE_CACHE_DIR" 2>/dev/null && moved=true
        fi
        [ "$moved" = true ] && debug_log "migrate_legacy_state: moved legacy state from $SCRIPT_DIR -> $CLAUDE_ACCOUNT_DIR"
    fi
    return 0
}

# Debug log location: under the shared statusline dir by default so logs
# don't litter /tmp. DEBUG_LOG env override still wins. Writes use append
# mode (echo >> is atomic for small lines), making it safe for many
# concurrent statusline processes — across containers — sharing one
# mounted ~/.claude. A size cap rotates the file so it can't grow forever.
DEBUG_LOG="${DEBUG_LOG:-$STATUSLINE_HOME/logs/statusline.log}"
DEBUG_LOG_MAX_BYTES="${DEBUG_LOG_MAX_BYTES:-1048576}"  # 1 MiB cap

# Rotate the debug log when it exceeds the cap. Keeps a single .1 backup.
# Uses a short-lived lock so concurrent processes don't all rotate at once.
rotate_debug_log() {
    local f="$1"
    [ -f "$f" ] || return 0
    local size
    size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)
    [ "$size" -lt "$DEBUG_LOG_MAX_BYTES" ] 2>/dev/null && return 0

    local rot_lock="${f}.rotate.lock"
    # mkdir is atomic: only one process wins the rotation.
    if mkdir "$rot_lock" 2>/dev/null; then
        mv -f "$f" "${f}.1" 2>/dev/null
        rmdir "$rot_lock" 2>/dev/null
    fi
}

debug_log() {
    if [ "$debug_mode" = true ]; then
        local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [pid:$$] DEBUG: $*"
        echo "$msg" >&2
        mkdir -p "$(dirname "$DEBUG_LOG")" 2>/dev/null
        rotate_debug_log "$DEBUG_LOG"
        # O_APPEND: each small write is atomic, so interleaving across
        # concurrent processes never corrupts a line.
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
    --cache)
        cache_display_mode="$2"
        shift 2
        ;;
    --advisor)
        advisor_display_mode="$2"
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

migrate_legacy_state

command -v jq >/dev/null 2>&1 || { echo "statusline: jq required" >&2; exit 1; }

apply_theme() {
    case "$theme" in
    "minimal")
        progress_bar_style="single-block"
        stat_order="model,user"
        path_display="project"
        alignment="left-right"
        extra_display_mode="off"
        advisor_display_mode="off"
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
        advisor_display_mode="off"
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
    @sh "rl_seven_reset=\(.rate_limits.seven_day.resets_at // "")",
    @sh "cache_read_tokens=\(.context_window.current_usage.cache_read_input_tokens // "")",
    @sh "cache_creation_tokens=\(.context_window.current_usage.cache_creation_input_tokens // "")",
    @sh "cache_creation_1h_tokens=\(.context_window.current_usage.cache_creation.ephemeral_1h_input_tokens // .context_window.current_usage.cache_creation.ephemeral_1h // "")",
    @sh "cache_creation_5m_tokens=\(.context_window.current_usage.cache_creation.ephemeral_5m_input_tokens // .context_window.current_usage.cache_creation.ephemeral_5m // "")",
    @sh "uncached_input_tokens=\(.context_window.current_usage.input_tokens // "")",
    @sh "stdin_session_id=\(.session_id // "")"
' 2>/dev/null)"

# Families that ship a 1M context window by default. Claude Code 2.1.173+ omits
# the [1m] suffix for these (1M is implied), so the suffix alone no longer
# detects them — match on the family instead. The [1m] suffix is now reserved
# for opt-in 1M on default-200k families (opus, and sonnet before 5), still
# honored below. sonnet-5 joined fable as default-1M in 2.1.197 — matched by
# exact major version so older sonnet-4-x/4-5 stay opt-in.
is_default_1m_family() {
    case "$1" in
    *fable*|*sonnet-5*) return 0 ;;
    *)                  return 1 ;;
    esac
}

# Detect context window from model ID:
#   CLI: if id.includes("[1m]") -> 1e6; else family-default (fable=1e6, else 200k)
get_context_limit() {
    local mid="$1"
    if [[ "$mid" == *"[1m]"* ]] || is_default_1m_family "$mid"; then
        echo 1000000
    else
        echo 200000
    fi
}

debug_log "PARSED INPUT: model=$model_display (id=$model_id) cwd=$current_dir cost=$cost_usd ctx_pct=$ctx_pct exceeds_200k=$exceeds_200k api_duration_ms=$api_duration_ms"

term_width=$(tput cols 2>/dev/null || echo 80)

# Palette is organized in three lanes so a glance is unambiguous:
#   STATUS  (green/yellow/red) — pressure ONLY: quota, context, cache, premium
#                                band, expensive effort. Warm = "watch a limit".
#   IDENTITY (magenta/cyan/blue; fable = bright red 0;91 to match the Claude
#                                Code TUI) — model family only. Never status.
#                                Pressure red stays 0;31; fable is 0;91.
#   NEUTRAL (grey/white by weight) — structure & you: path, branch, time, cost,
#                                tier, name, routine effort.
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
# Bold red — one notch louder than pressure red (0;31), still the STATUS lane
# (distinct from fable's identity bright-red 0;91). Used only for a heavy cache
# rewrite (>= CACHE_HEAVY_TOKENS): the expensive miss deserves extra weight.
BOLD_RED='\033[1;31m'
DIM='\033[2m'
DIM_GREEN='\033[2;32m'
DIM_RED='\033[2;31m'
DIM_YELLOW='\033[2;33m'
CYAN='\033[0;36m'
DIM_CYAN='\033[2;36m'
WHITE='\033[0;37m'
BOLD_WHITE='\033[1;37m'
# Reverse video for the quota bump flash — inverts fg/bg at whatever the
# badge's current color is, so the +N token pops without adding a new hue.
REVERSE='\033[7m'
NO_REVERSE='\033[27m'
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

# Node trusts NODE_EXTRA_CA_CERTS in ADDITION to the system store; curl has no
# additive flag. When the CLI runs behind a trusted mitm proxy (cctrace,
# corporate TLS inspection), the statusline inherits HTTPS_PROXY but curl
# rejects the proxy's certificate -> instant HTTP 000 -> persistent !net,
# while the CLI itself keeps working. Splice the extra cert onto a copy of
# the system bundle and point --cacert at it. Prints the combined bundle
# path, or nothing when no extra CA is configured.
curl_ca_bundle() {
    [ -n "$NODE_EXTRA_CA_CERTS" ] && [ -r "$NODE_EXTRA_CA_CERTS" ] || return 0
    local bundle="$CLAUDE_ACCOUNT_DIR/ca-bundle.pem"
    if [ ! -f "$bundle" ] || [ "$NODE_EXTRA_CA_CERTS" -nt "$bundle" ]; then
        mkdir -p "$CLAUDE_ACCOUNT_DIR"
        local sys="" candidate
        for candidate in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do
            [ -r "$candidate" ] && { sys="$candidate"; break; }
        done
        local tmp="${bundle}.tmp.$$"
        if [ -n "$sys" ]; then
            cat "$sys" "$NODE_EXTRA_CA_CERTS" >"$tmp" 2>/dev/null
        else
            cat "$NODE_EXTRA_CA_CERTS" >"$tmp" 2>/dev/null
        fi
        mv -f "$tmp" "$bundle" 2>/dev/null || rm -f "$tmp"
    fi
    [ -r "$bundle" ] && printf '%s\n' "$bundle"
}

refresh_oauth_credentials_file() {
    local cred_file="$1"
    local refresh_token scope scope_string payload response http_code body

    [ -f "$cred_file" ] || return 1

    refresh_token=$(jq -r '.claudeAiOauth.refreshToken // empty' "$cred_file" 2>/dev/null)
    [ -n "$refresh_token" ] || return 1

    mkdir -p "$CLAUDE_ACCOUNT_DIR"
    local lock_file="$CLAUDE_ACCOUNT_DIR/oauth_refresh.lock"
    # Atomic: two concurrent refreshes are worse than a missed one — with
    # rotating refresh tokens the loser's grant can invalidate the winner's.
    acquire_lock "$lock_file" 30 || return 1

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

    local ca_bundle
    ca_bundle=$(curl_ca_bundle)
    response=$(curl -sS -w "\n%{http_code}" -X POST \
        "https://platform.claude.com/v1/oauth/token" \
        -H "Content-Type: application/json" \
        --data "$payload" \
        ${ca_bundle:+--cacert "$ca_bundle"} \
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
    local profile_cache="$CLAUDE_ACCOUNT_DIR/profile.cache"
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

    # Synchronous fetch: honor the no-network switch (see STATUSLINE_NO_FETCH).
    if [ -n "${STATUSLINE_NO_FETCH:-}" ]; then
        [ -f "$profile_cache" ] && cat "$profile_cache"
        return 0
    fi

    mkdir -p "$CLAUDE_ACCOUNT_DIR"

    debug_log "get_user_profile: fetching from API..."

    local ca_bundle
    ca_bundle=$(curl_ca_bundle)
    local response=$(curl -s -w "\n%{http_code}|%{errormsg}" -X GET \
        "https://api.anthropic.com/api/oauth/profile" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Accept: application/json, text/plain, */*" \
        -H "Accept-Encoding: identity" \
        -H "Content-Type: application/json" \
        -H "User-Agent: claude-cli/${cli_version:-2.1.207} (external, cli)" \
        ${ca_bundle:+--cacert "$ca_bundle"} \
        --max-time 5)

    local status_line=$(echo "$response" | tail -1)
    local errmsg="${status_line#*|}"
    [ "$errmsg" = "$status_line" ] && errmsg=""
    case "$errmsg" in *'%{errormsg}'*) errmsg="" ;; esac
    local http_code="${status_line%%|*}"
    local body=$(echo "$response" | sed '$d')

    debug_log "API RESPONSE: HTTP $http_code${errmsg:+ curl: $errmsg}"
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

# --- fetch error state -------------------------------------------------------
# Failed fetches leave a JSON err file: {at, code, count, cooldown}. Consecutive
# failures escalate the cooldown (120s -> 240s -> 480s -> 600s cap) instead of
# retrying into a still-throttled window every fixed 120s — observed live: 23%
# of usage fetches 429'd in clusters exactly one backoff apart. A server
# Retry-After (429s carry one) extends the cooldown when it's longer. The err
# file survives until a fetch SUCCEEDS, so the count keeps escalating across
# expired cooldowns; success removes it.

record_fetch_error() {
    local err_file="$1" http_code="$2" retry_after="$3" errmsg="${4:-}"
    local count=1
    if [ -f "$err_file" ] && head -c1 "$err_file" 2>/dev/null | grep -q '{'; then
        local prev=$(jq -r '.count // 0' "$err_file" 2>/dev/null)
        [ "$prev" -ge 1 ] 2>/dev/null && count=$((prev + 1))
    fi
    local cooldown
    if [ "$count" -ge 4 ]; then
        cooldown=600
    else
        cooldown=$((120 * (1 << (count - 1))))
    fi
    # Sanitize Retry-After: digits only (old curl without %header{} support
    # passes the literal format string through; headers can also be dates).
    case "$retry_after" in *[!0-9]* | '') retry_after="" ;; esac
    if [ -n "$retry_after" ] && [ "$retry_after" -gt "$cooldown" ] 2>/dev/null; then
        cooldown="$retry_after"
    fi
    debug_log "fetch error: $(basename "$err_file"): code=${http_code:-?} retry_after=${retry_after:-none} consecutive=$count cooldown=${cooldown}s${errmsg:+ msg=$errmsg}"
    # msg keeps curl's own error text (SSL failure, DNS, refused connection):
    # code 000 alone is undiagnosable — `cat usage.err` should say why.
    jq -n -c --argjson at "$(date +%s)" --arg code "${http_code:-}" \
        --argjson count "$count" --argjson cooldown "$cooldown" \
        --arg msg "$errmsg" \
        '{at:$at,code:$code,count:$count,cooldown:$cooldown} + (if $msg != "" then {msg:$msg} else {} end)' >"$err_file" 2>/dev/null
}

# Seconds of cooldown remaining; 0 = clear to retry. Legacy err files (bare
# epoch from pre-v0.13.0) get the old fixed 120s window.
fetch_error_remaining() {
    local err_file="$1"
    [ -f "$err_file" ] || { echo 0; return; }
    local at=0 cooldown=120
    if head -c1 "$err_file" 2>/dev/null | grep -q '{'; then
        eval "$(jq -r '@sh "at=\(.at // 0)", @sh "cooldown=\(.cooldown // 120)"' "$err_file" 2>/dev/null)"
    else
        at=$(cat "$err_file" 2>/dev/null || echo 0)
    fi
    local remaining=$((at + cooldown - $(date +%s)))
    [ "$remaining" -gt 0 ] 2>/dev/null || remaining=0
    echo "$remaining"
}

# Short reason for the stale-data indicator: !429 (rate limited), !auth
# (401/403), !5xx (server), !net (connection failed). Bare ! when the code
# is unknown (legacy err file).
fetch_error_badge() {
    local err_file="$1"
    [ -f "$err_file" ] || return
    local code=""
    head -c1 "$err_file" 2>/dev/null | grep -q '{' && code=$(jq -r '.code // ""' "$err_file" 2>/dev/null)
    case "$code" in
        429)     echo "!429" ;;
        401|403) echo "!auth" ;;
        5??)     echo "!5xx" ;;
        000)     echo "!net" ;;
        *)       echo "!" ;;
    esac
}

# Usage quota is ACCOUNT-scoped (the /api/oauth/usage endpoint returns the
# same 5h/7d/extra data regardless of session). Cache it once in a shared
# file so N concurrent sessions share one fetch instead of issuing N
# redundant calls. session_id is still threaded through for the usage.jsonl
# snapshot and session-boundary detection.
fetch_usage_for_session() {
    local session_id="$1"
    local cache_file="$CLAUDE_ACCOUNT_DIR/usage.cache"
    local lock_file="$CLAUDE_ACCOUNT_DIR/usage.lock"
    local err_file="$CLAUDE_ACCOUNT_DIR/usage.err"

    mkdir -p "$CLAUDE_ACCOUNT_DIR"
    debug_log "fetch_usage_for_session: session=$session_id (shared usage.cache)"

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

    # Escalating cooldown on errors. The err file stays until a success so
    # consecutive failures keep escalating; only the cooldown gates retries.
    local err_remaining
    err_remaining=$(fetch_error_remaining "$err_file")
    if [ "$err_remaining" -gt 0 ] 2>/dev/null; then
        debug_log "fetch_usage_for_session: in error cooldown (${err_remaining}s remaining)"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 0
    fi

    # Acquire the lock BEFORE the token read: get_oauth_token can take
    # hundreds of ms (file reads, possibly a refresh round-trip), and N
    # instances launched together all sat in that gap under the old
    # check-then-touch, then fetched concurrently — the main source of 429
    # bursts (each CLI already fires 2 usage requests of its own on boot).
    if ! acquire_lock "$lock_file" 10; then
        debug_log "fetch_usage_for_session: lock contended, skip"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 0
    fi

    local token=$(get_oauth_token)
    if [ -z "$token" ]; then
        debug_log "fetch_usage_for_session: no token available"
        rm -f "$lock_file"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi

    # Headers mirror claude-cli exactly (verified against a cctrace capture
    # of CLI 2.1.207; see docs/api/oauth-usage.md).
    local ua="claude-cli/${cli_version:-2.1.207} (external, cli)"
    local ca_bundle
    ca_bundle=$(curl_ca_bundle)

    debug_log "fetch_usage_for_session: fetching (User-Agent: $ua)..."

    # %header{retry-after} needs curl >= 7.83, %{errormsg} >= 7.75; older
    # curl emits the literal format string, which the digit filter in
    # record_fetch_error and the errmsg sanitizer below discard.
    local response=$(curl -s -w "\n%{http_code} %header{retry-after}|%{errormsg}" -X GET \
        "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Accept: application/json, text/plain, */*" \
        -H "Accept-Encoding: identity" \
        -H "Content-Type: application/json" \
        -H "User-Agent: $ua" \
        ${ca_bundle:+--cacert "$ca_bundle"} \
        --max-time 5)

    local status_line=$(echo "$response" | tail -1)
    local errmsg="${status_line#*|}"
    [ "$errmsg" = "$status_line" ] && errmsg=""
    case "$errmsg" in *'%{errormsg}'*) errmsg="" ;; esac
    status_line="${status_line%%|*}"
    local http_code="${status_line%% *}"
    local retry_after="${status_line#* }"
    [ "$retry_after" = "$status_line" ] && retry_after=""
    local body=$(echo "$response" | sed '$d')

    rm -f "$lock_file"

    debug_log "API RESPONSE: HTTP $http_code${retry_after:+ (retry-after: $retry_after)}${errmsg:+ curl: $errmsg}"
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
        # Hourly-gated internally; piggybacks on the TTL-gated fetch path so
        # renders never pay the history scan.
        build_seven_day_profile
        return 0
    else
        record_fetch_error "$err_file" "$http_code" "$retry_after" "$errmsg"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi
}

get_cached_org_uuid() {
    local profile_cache="$CLAUDE_ACCOUNT_DIR/profile.cache"
    if [ -f "$profile_cache" ]; then
        jq -r '.organization.uuid // empty' "$profile_cache" 2>/dev/null
    fi
}

fetch_prepaid_balance() {
    local org_uuid="$1"
    local cache_file="$CLAUDE_ACCOUNT_DIR/prepaid_credits.cache"
    local lock_file="$CLAUDE_ACCOUNT_DIR/prepaid_credits.lock"
    local err_file="$CLAUDE_ACCOUNT_DIR/prepaid_credits.err"

    [ -n "$org_uuid" ] || return 1

    mkdir -p "$CLAUDE_ACCOUNT_DIR"
    debug_log "fetch_prepaid_balance: org=$org_uuid"

    if [ -f "$cache_file" ]; then
        local fetched_at=$(jq -r '.fetched_at // 0' "$cache_file" 2>/dev/null)
        local age=$(($(date +%s) - fetched_at))
        if [ $age -lt 300 ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    local err_remaining
    err_remaining=$(fetch_error_remaining "$err_file")
    if [ "$err_remaining" -gt 0 ] 2>/dev/null; then
        [ -f "$cache_file" ] && cat "$cache_file"
        return 0
    fi

    # Same atomic-acquire-before-token-read as fetch_usage_for_session.
    if ! acquire_lock "$lock_file" 10; then
        [ -f "$cache_file" ] && cat "$cache_file"
        return 0
    fi

    local token=$(get_oauth_token)
    if [ -z "$token" ]; then
        debug_log "fetch_prepaid_balance: no token available"
        rm -f "$lock_file"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi

    local ua="claude-cli/${cli_version:-2.1.207} (external, cli)"
    local ca_bundle
    ca_bundle=$(curl_ca_bundle)
    local response=$(curl -s -w "\n%{http_code} %header{retry-after}|%{errormsg}" -X GET \
        "https://api.anthropic.com/api/oauth/organizations/${org_uuid}/prepaid/credits" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Accept: application/json, text/plain, */*" \
        -H "Accept-Encoding: identity" \
        -H "Content-Type: application/json" \
        -H "User-Agent: $ua" \
        -H "x-organization-uuid: $org_uuid" \
        ${ca_bundle:+--cacert "$ca_bundle"} \
        --max-time 5)

    local status_line=$(echo "$response" | tail -1)
    local errmsg="${status_line#*|}"
    [ "$errmsg" = "$status_line" ] && errmsg=""
    case "$errmsg" in *'%{errormsg}'*) errmsg="" ;; esac
    status_line="${status_line%%|*}"
    local http_code="${status_line%% *}"
    local retry_after="${status_line#* }"
    [ "$retry_after" = "$status_line" ] && retry_after=""
    local body=$(echo "$response" | sed '$d')

    rm -f "$lock_file"

    debug_log "PREPAID API RESPONSE: HTTP $http_code${retry_after:+ (retry-after: $retry_after)}${errmsg:+ curl: $errmsg}"
    debug_log "PREPAID RESPONSE BODY: $body"

    if [ "$http_code" = "200" ]; then
        local tmp_cache="${cache_file}.tmp.$$"
        echo "$body" | jq --arg ts "$(date +%s)" '. + {fetched_at: ($ts|tonumber)}' >"$tmp_cache" 2>/dev/null
        mv -f "$tmp_cache" "$cache_file"
        rm -f "$err_file"
        cat "$cache_file"
        return 0
    else
        record_fetch_error "$err_file" "$http_code" "$retry_after" "$errmsg"
        [ -f "$cache_file" ] && cat "$cache_file"
        return 1
    fi
}

log_usage_snapshot() {
    local session_id="$1"
    local usage_data="$2"
    local token="$3"

    mkdir -p "$CLAUDE_ACCOUNT_DIR"
    local usage_log="$CLAUDE_ACCOUNT_DIR/usage.jsonl"
    debug_log "log_usage_snapshot: session=$session_id"
    rotate_usage_log "$usage_log"

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
    local usage_log="$CLAUDE_ACCOUNT_DIR/usage.jsonl"

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

# Cache health state machine. Tracks the per-session cached-prefix numbers in
# a small JSON state file and classifies each render:
#   ok        warm cache, no anomaly
#   building  first write of a fresh prefix (read = 0, creation > 0)
#   break     the cached prefix shrank hard (drop rule), OR new activity landed
#             after an idle gap longer than the TTL (the rewrite happened even
#             when the 300ms render debounce skipped the read=0 frame), OR a
#             recent break still held for QUOTA_BUMP_NOTICE_SECS
#   none      no usage numbers at all this render
# Echoes "state|ttl_class|last_active_at|break_tokens".
get_cache_health() {
    local cache_read="${1:-0}" cache_creation="${2:-0}" uncached="${3:-0}"
    local state_file="${4:-}" ttl_class="${5:-}" cache_creation_1h="${6:-0}" cache_creation_5m="${7:-0}"

    [ -z "$cache_read" ] && cache_read=0
    [ -z "$cache_creation" ] && cache_creation=0
    [ -z "$uncached" ] && uncached=0
    [ -z "$cache_creation_1h" ] && cache_creation_1h=0
    [ -z "$cache_creation_5m" ] && cache_creation_5m=0

    cache_read=$(printf '%.0f' "$cache_read" 2>/dev/null) || cache_read=0
    cache_creation=$(printf '%.0f' "$cache_creation" 2>/dev/null) || cache_creation=0
    uncached=$(printf '%.0f' "$uncached" 2>/dev/null) || uncached=0
    cache_creation_1h=$(printf '%.0f' "$cache_creation_1h" 2>/dev/null) || cache_creation_1h=0
    cache_creation_5m=$(printf '%.0f' "$cache_creation_5m" 2>/dev/null) || cache_creation_5m=0

    local total=$((cache_read + cache_creation + uncached))
    if [ "$total" -le 0 ]; then
        echo "none"
        return
    fi

    local prev_cache_read=""
    local prev_cache_creation=""
    local prev_ttl_class=""
    local last_active_at=""
    local break_at=0 break_tokens=0
    local now_epoch="${STATUSLINE_TEST_NOW_EPOCH:-$(date +%s)}"

    if [ -n "$ttl_class" ] && [ "$ttl_class" != "5m" ] && [ "$ttl_class" != "1h" ]; then
        ttl_class=""
    fi

    if [ "$cache_creation_1h" -gt 0 ]; then
        ttl_class="1h"
    elif [ "$cache_creation_5m" -gt 0 ]; then
        ttl_class="5m"
    fi

    if [ -n "$state_file" ] && [ -f "$state_file" ]; then
        if jq -e 'type == "object"' "$state_file" >/dev/null 2>&1; then
            eval "$(jq -r '
                @sh "prev_cache_read=\(.cache_read // "")",
                @sh "prev_cache_creation=\(.cache_creation // "")",
                @sh "prev_ttl_class=\(.ttl_class // "")",
                @sh "last_active_at=\(.last_active_at // "")",
                @sh "break_at=\(.break_at // 0)",
                @sh "break_tokens=\(.break_tokens // 0)"
            ' "$state_file" 2>/dev/null)"
        else
            prev_cache_read=$(cat "$state_file" 2>/dev/null)
            [[ "$prev_cache_read" =~ ^[0-9]+$ ]] || prev_cache_read=""
        fi
    fi

    [ -z "$ttl_class" ] && ttl_class="$prev_ttl_class"

    # Anchor for the expiry deadline: the last REQUEST, not the last render.
    # Renders also fire on vim/permission/model changes carrying the previous
    # message's usage unchanged; re-stamping there slides the anchor forward
    # and a frozen frame would claim a warm cache after it already died.
    # Stamp only when the usage numbers actually moved (new API activity).
    local usage_changed=""
    if [ "$cache_read" -gt 0 ] || [ "$cache_creation" -gt 0 ]; then
        if [ "$cache_read" != "${prev_cache_read:-}" ] || [ "$cache_creation" != "${prev_cache_creation:-}" ]; then
            usage_changed=1
        fi
    fi
    local prev_active="${last_active_at:-}"
    [ -n "$usage_changed" ] && last_active_at="$now_epoch"

    local ttl_secs=3600
    [ "${ttl_class:-$CACHE_TTL_DEFAULT}" = "5m" ] && ttl_secs=300

    local state="ok"
    if [ -z "$prev_cache_read" ] || [ "$prev_cache_read" -le 0 ] 2>/dev/null; then
        if [ "$cache_read" -le 0 ] && [ "$cache_creation" -gt 0 ]; then
            state="building"
        fi
    else
        local drop=$((prev_cache_read - cache_read))
        local threshold=$((prev_cache_read * (100 - CACHE_BREAK_DROP_PCT) / 100))
        if [ "$drop" -gt "$CACHE_BREAK_MIN_TOKENS" ] && [ "$cache_read" -lt "$threshold" ]; then
            state="break"
            break_at="$now_epoch"
            break_tokens="$cache_creation"
        elif [ -n "$usage_changed" ] && [ -n "$prev_active" ] \
             && [ $((now_epoch - prev_active)) -gt "$ttl_secs" ] 2>/dev/null; then
            # Idle expiry: activity after a gap longer than the TTL means the
            # whole prefix was re-written, whether or not any render caught
            # the read=0 frame. Size estimate: the prefix that got re-cached.
            state="break"
            break_at="$now_epoch"
            break_tokens=$((cache_read + cache_creation))
        elif [ "$cache_read" -le 0 ] && [ "$cache_creation" -gt "$CACHE_BREAK_MIN_TOKENS" ]; then
            state="building"
        fi
    fi

    # A break is HELD for QUOTA_BUMP_NOTICE_SECS: the single render that
    # catches the rewrite is often replaced within seconds during a busy turn.
    if [ "$state" != "break" ]; then
        if [ "${break_at:-0}" -gt 0 ] 2>/dev/null && [ $((now_epoch - break_at)) -lt "$QUOTA_BUMP_NOTICE_SECS" ] 2>/dev/null; then
            state="break"
        else
            break_at=0
            break_tokens=0
        fi
    fi

    if [ -n "$state_file" ]; then
        mkdir -p "$(dirname "$state_file")" 2>/dev/null
        local tmp_state="${state_file}.tmp.$$"
        jq -n -c \
            --argjson cache_read "$cache_read" \
            --argjson cache_creation "$cache_creation" \
            --argjson uncached "$uncached" \
            --arg ttl "$ttl_class" \
            --argjson last_active "${last_active_at:-0}" \
            --argjson break_at "${break_at:-0}" \
            --argjson break_tokens "${break_tokens:-0}" \
            --argjson updated_at "$now_epoch" \
            '{
                cache_read: $cache_read,
                cache_creation: $cache_creation,
                uncached: $uncached,
                ttl_class: (if $ttl == "" then null else $ttl end),
                last_active_at: (if $last_active > 0 then $last_active else null end),
                break_at: (if $break_at > 0 then $break_at else null end),
                break_tokens: (if $break_tokens > 0 then $break_tokens else null end),
                updated_at: $updated_at
            }' > "$tmp_state" 2>/dev/null && mv -f "$tmp_state" "$state_file" 2>/dev/null
        rm -f "$tmp_state" 2>/dev/null
    fi

    echo "${state}|${ttl_class}|${last_active_at}|${break_tokens}"
}

infer_cache_ttl_class() {
    local cache_creation_1h="${1:-0}" cache_creation_5m="${2:-0}"

    [ -z "$cache_creation_1h" ] && cache_creation_1h=0
    [ -z "$cache_creation_5m" ] && cache_creation_5m=0
    cache_creation_1h=$(printf '%.0f' "$cache_creation_1h" 2>/dev/null) || cache_creation_1h=0
    cache_creation_5m=$(printf '%.0f' "$cache_creation_5m" 2>/dev/null) || cache_creation_5m=0

    if [ "$cache_creation_1h" -gt 0 ]; then
        echo "1h"
        return
    fi
    if [ "$cache_creation_5m" -gt 0 ]; then
        echo "5m"
        return
    fi
    echo ""
}

# Portable date helpers. GNU `date -d` does not exist on BSD/macOS (a supported
# target), so every reset/countdown render must fall back to BSD syntax or it
# silently disappears. These try GNU first, then BSD, and echo "" on failure.

# ISO-8601 string or epoch -> epoch seconds.
_epoch_from_ts() {
    local ts="$1"
    [ -z "$ts" ] || [ "$ts" = "null" ] && return 0
    if [[ "$ts" =~ ^[0-9]+$ ]]; then printf '%s' "$ts"; return 0; fi
    local out
    out=$(date -d "$ts" +%s 2>/dev/null) && { printf '%s' "$out"; return 0; }
    # BSD: needs an explicit format and no fractional seconds / timezone.
    local clean="${ts%%.*}"; clean="${clean%%+*}"; clean="${clean%Z}"
    out=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$clean" +%s 2>/dev/null) && printf '%s' "$out"
    return 0
}

# epoch seconds + strftime format -> formatted string.
_fmt_epoch() {
    local epoch="$1" fmt="$2" out
    [ -z "$epoch" ] && return 0
    out=$(date -d "@$epoch" +"$fmt" 2>/dev/null) && { printf '%s' "$out"; return 0; }
    out=$(date -r "$epoch" +"$fmt" 2>/dev/null) && printf '%s' "$out"
    return 0
}

# Cache badge — "quiet until it bites". Claude Code never re-renders an idle
# session, and while active the cache is always freshly ~1 TTL from expiry, so
# a proactive "expiring soon" is not honestly observable for a 1h (subscriber)
# cache: the expiry only becomes real during an idle gap that produces no
# render to warn in. So auto mode stays SILENT while healthy — no width spent
# on a deadline that's always ~an hour out mid-session — and speaks only when
# the rewrite actually happened:
#   cache!<size>  a resume landing on a dead cache (idle-expiry break) or a
#                 mid-session prefix collapse. <size> = re-cached tokens; the
#                 miss bills at ~20x the read rate (and burns 5h/7d quota on
#                 subscriptions). BOLD red past CACHE_HEAVY_TOKENS — the >200k
#                 premium-band rewrite the user asked to highlight.
#   cache~        a large prefix is (re)building this turn.
# --cache always keeps the freeze-safe absolute deadline (cache@HH:MM = last
# request + TTL): a past time in a frozen frame reads "expired at HH:MM", the
# same wall-clock idiom as the 5h @reset. TTL: the CLI does not forward the
# ephemeral_1h/5m breakdown today (ttl_class stays null), so an unobserved TTL
# assumes CACHE_TTL_DEFAULT; an observed class renders as provenance
# (cache:5m@…) and overrides it.
build_cache_indicator() {
    local health_result="$1" mode="${2:-auto}"
    local state ttl_class last_active_at break_tokens
    IFS='|' read -r state ttl_class last_active_at break_tokens <<<"$health_result"

    case "$mode" in
        "off") return ;;
    esac

    # Absolute expiry deadline (last request + TTL) — rendered only in `always`.
    local ttl_secs=3600
    [ "${ttl_class:-$CACHE_TTL_DEFAULT}" = "5m" ] && ttl_secs=300
    local meta=""
    if [ -n "$last_active_at" ] && [ "$last_active_at" -gt 0 ] 2>/dev/null; then
        local deadline
        deadline=$(_fmt_epoch $((last_active_at + ttl_secs)) '%H:%M')
        [ -n "$deadline" ] && meta="@${deadline}"
    fi
    [ -n "$ttl_class" ] && [ -n "$meta" ] && meta=":${ttl_class}${meta}"

    case "$state" in
        "break")
            # Rewrite size quantifies the hit: ≡!195k = a 195k-token prefix
            # was re-cached at the write rate. Bold past the heavy threshold
            # — a >200k premium-band miss is the expensive one.
            local size=""
            [ "${break_tokens:-0}" -ge 1000 ] 2>/dev/null && size="$((break_tokens / 1000))k"
            local col="$RED"
            [ "${break_tokens:-0}" -ge "$CACHE_HEAVY_TOKENS" ] 2>/dev/null && col="$BOLD_RED"
            echo "${col}${CACHE_GLYPH}!${size}${RESET}"
            ;;
        "building")
            # Glyph at full weight, trailing meta dim: an all-dim badge
            # disappears next to the bright context bar (reported in real use).
            if [ "$mode" = "always" ]; then
                echo "${YELLOW}${CACHE_GLYPH}${DIM_YELLOW}${meta}~${RESET}"
            else
                echo "${YELLOW}${CACHE_GLYPH}${DIM_YELLOW}~${RESET}"
            fi
            ;;
        "ok")
            # Healthy: silent in auto (the deadline is always ~1 TTL out while
            # active — noise), shown only when explicitly requested. The glyph
            # keeps full weight so the badge stays findable; meta stays dim.
            [ "$mode" = "always" ] && [ -n "$meta" ] && echo "${WHITE}${CACHE_GLYPH}${DIM}${meta}${RESET}"
            ;;
    esac
    return 0
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

# Atomically acquire a lock file, or return 1 if another process holds a
# fresh one. noclobber (set -C) makes create-if-absent a single atomic step —
# the old check-then-touch pattern left a window (hundreds of ms when a slow
# token read sat between check and touch) where N freshly launched instances
# all passed the check and stampeded the API with concurrent fetches.
# A lock older than $2 is presumed orphaned (fetcher died), reaped, and
# re-contended once; losing that race just skips this cycle — the winner is
# fetching anyway.
acquire_lock() {
    local lock_file="$1" max_age="${2:-10}"
    if (set -C; : >"$lock_file") 2>/dev/null; then
        return 0
    fi
    local mtime age
    mtime=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo 0)
    age=$(($(date +%s) - mtime))
    if [ "$age" -ge "$max_age" ] 2>/dev/null; then
        rm -f "$lock_file"
        (set -C; : >"$lock_file") 2>/dev/null && return 0
    fi
    return 1
}

# Remove a lock left behind by a fetch that died before cleanup. Without this,
# a single orphaned *.lock permanently freezes the cache (the fetch gate skips
# launching while the lock exists, and never reaps it). $2 = max age seconds.
reap_stale_lock() {
    local lock_file="$1" max_age="${2:-15}"
    [ -f "$lock_file" ] || return 0
    local mtime now age
    mtime=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - mtime))
    [ "$age" -ge "$max_age" ] && rm -f "$lock_file"
    return 0
}

# Merge the CLI's stdin rate_limits with cached usage JSON, window-aware.
#
# Neither source is always fresher: stdin reflects THIS session's last API
# response (seconds old when active, hours old when idle — an idle session can
# carry a window that already reset), while the shared cache is fed by whichever
# concurrent session fetched last. Timestamps for stdin aren't available, but
# two structural facts decide freshness without them:
#   - across windows: the later resets_at IS the newer window
#   - within one window: utilization only ever increases
# So per window: newer resets_at wins outright; same window takes the max
# utilization (the larger number is by definition the more recent reading).
# Fields stdin lacks (extra_usage, model breakdowns) are left untouched.
# Args: <usage_json> <five_pct> <five_reset> <seven_pct> <seven_reset>
merge_stdin_rate_limits() {
    local usage="$1" fp="$2" fr="$3" sp="$4" sr="$5"

    # Cached window state (utilization + resets_at) for comparison.
    local c5p c5r c7p c7r
    c5p=$(echo "$usage" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    c5r=$(echo "$usage" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    c7p=$(echo "$usage" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
    c7r=$(echo "$usage" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)

    # Decide one window. Echoes "pct|reset" to apply, or "" to keep the cache.
    _pick_window() {
        local sp_="$1" sr_="$2" cp_="$3" cr_="$4"
        [ -z "$sp_" ] && return 0                      # no stdin -> keep cache
        if [ -z "$cp_" ] || [ -z "$cr_" ]; then        # no cache -> stdin wins
            echo "${sp_}|${sr_}"; return 0
        fi
        local se ce
        se=$(_epoch_from_ts "$sr_"); ce=$(_epoch_from_ts "$cr_")
        if [ -z "$se" ] || [ -z "$ce" ]; then          # unparseable -> stdin
            echo "${sp_}|${sr_}"; return 0
        fi
        if [ "$se" -gt "$ce" ] 2>/dev/null; then       # stdin has newer window
            echo "${sp_}|${sr_}"
        elif [ "$se" -lt "$ce" ] 2>/dev/null; then     # stdin window expired
            return 0                                   # keep fresher cache
        else                                           # same window: take max
            if awk -v a="$sp_" -v b="$cp_" 'BEGIN{exit !((a+0) > (b+0))}'; then
                echo "${sp_}|${sr_}"
            fi                                         # else cache >= stdin: keep
        fi
    }

    local pick5 pick7
    pick5=$(_pick_window "$fp" "$fr" "$c5p" "$c5r")
    pick7=$(_pick_window "$sp" "$sr" "$c7p" "$c7r")

    local f5p="" f5r="" s7p="" s7r=""
    [ -n "$pick5" ] && { f5p="${pick5%%|*}"; f5r="${pick5#*|}"; }
    [ -n "$pick7" ] && { s7p="${pick7%%|*}"; s7r="${pick7#*|}"; }

    echo "$usage" | jq \
        --argjson fp "${f5p:-null}" --arg fr "$f5r" \
        --argjson sp "${s7p:-null}" --arg sr "$s7r" \
        '(.five_hour //= {}) | (.seven_day //= {})
         | (if $fp != null then .five_hour.utilization = $fp
              | .five_hour.resets_at = (if $fr == "" then null else $fr end) else . end)
         | (if $sp != null then .seven_day.utilization = $sp
              | .seven_day.resets_at = (if $sr == "" then null else $sr end) else . end)' \
        2>/dev/null
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
    reset_epoch=$(_epoch_from_ts "$ts")
    [ -z "$reset_epoch" ] && return
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

# Wall-clock reset time (@14:30), local TZ. Claude Code only re-renders the
# statusline on activity, so any minute-scale countdown quietly decays into a
# lie during an idle gap — "@1h38m" rendered 30 minutes ago overstates the
# wait by 30 minutes, and idle is exactly when no re-render comes to fix it.
# Wall-clock stays true no matter how stale the frame is. The "as of" numbers
# in the same frame (cost, context %, usage %) don't have this problem: they
# only change with activity, and activity triggers a re-render. Restored from
# v0.7.0 (v0.11.0 reversed it and re-made the v0.6-era mistake). "now" when
# the reset is already past.
format_reset_absolute() {
    local ts="$1"
    [ -z "$ts" ] || [ "$ts" = "null" ] && return
    local reset_epoch
    reset_epoch=$(_epoch_from_ts "$ts")
    [ -z "$reset_epoch" ] && return
    if [ "$reset_epoch" -le "$(date +%s)" ] 2>/dev/null; then
        echo "now"
        return
    fi
    _fmt_epoch "$reset_epoch" '%H:%M'
}

get_reset_seconds() {
    local ts="$1"
    [ -z "$ts" ] || [ "$ts" = "null" ] && { echo ""; return; }
    local reset_epoch now_epoch
    reset_epoch=$(_epoch_from_ts "$ts")
    [ -z "$reset_epoch" ] && { echo ""; return; }
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

# Seconds elapsed into the fixed 7d quota window, or "" when pace can't be
# judged: no/invalid deadline, or the first ~8h where the projection is too
# noisy to trust (a single opening burst would otherwise read as a runaway).
seven_day_elapsed() {
    local secs_left="$1"
    [ -z "$secs_left" ] && return
    [ "$secs_left" -le 0 ] 2>/dev/null && return
    [ "$secs_left" -ge "$SEVEN_DAY_WINDOW_SECS" ] 2>/dev/null && return
    local elapsed=$(( SEVEN_DAY_WINDOW_SECS - secs_left ))
    [ "$elapsed" -lt $(( SEVEN_DAY_WINDOW_SECS / 20 )) ] && return  # < ~8.4h: noisy
    echo "$elapsed"
}

# Upcoming weekend seconds between now and reset, by 24h sampling (<=7 probes).
# Used only when CLAUDE_7D_WORKDAYS is set, to shorten the effective deadline so
# the meter doesn't alarm over weekend days the user won't spend quota on.
# Approximate (whole-day granularity) — it's an opt-in planning aid, not billing.
weekend_secs_ahead() {
    local secs_left="$1" now_epoch wsecs=0 off=0 probe dow
    now_epoch=$(date +%s)
    while [ $(( off * 86400 )) -lt "$secs_left" ] 2>/dev/null; do
        probe=$(( now_epoch + off * 86400 ))
        dow=$(_fmt_epoch "$probe" '%u')  # 1=Mon .. 7=Sun
        [ "${dow:-0}" -ge 6 ] 2>/dev/null && wsecs=$(( wsecs + 86400 ))
        off=$(( off + 1 ))
    done
    [ "$wsecs" -gt "$secs_left" ] && wsecs="$secs_left"
    echo "$wsecs"
}

# Pace verdict for the weekly quota. Compares runway (seconds of quota left at
# the current burn rate) against the deadline (seconds until reset; $3 lets the
# weekend-skip flag shorten it). Echoes: "<level> <runway_days> <hint>".
#   level: green|yellow|red   runway_days: int, -1 when unknown   hint: 0|1
# A 10% buffer keeps marginal overshoots quiet (warn only when you'll fall
# >~10% short). Falls back to level thresholds when pace can't be judged
# (no deadline, or the noisy first ~8h). $2 drives elapsed; $3 the deadline.
#   $1 used%   $2 seconds_left   $3 effective deadline secs (optional)
seven_day_pace() {
    local used; used=$(printf '%.0f' "$1" 2>/dev/null || echo 0)
    local secs_left="${2:-}" deadline="${3:-}"
    [ -z "$deadline" ] && deadline="$secs_left"
    local elapsed; elapsed=$(seven_day_elapsed "$secs_left")
    if [ -z "$elapsed" ] || [ "$used" -le 0 ] 2>/dev/null; then
        if   [ "$used" -ge 85 ] 2>/dev/null; then echo "red -1 0"
        elif [ "$used" -ge 70 ] 2>/dev/null; then echo "yellow -1 0"
        else echo "green -1 0"; fi
        return
    fi
    local runway_secs=$(( (100 - used) * elapsed / used ))
    local runway_days=$(( runway_secs / 86400 ))
    # at risk: you'll fall >10% short of the deadline (runway/deadline < 0.9).
    local atrisk=0
    [ $(( runway_secs * 10 )) -lt $(( ${deadline:-0} * 9 )) ] 2>/dev/null && atrisk=1
    # red when used up (>=95), or you'll run out in under half the time left.
    local hard=0
    { [ "$used" -ge 90 ] 2>/dev/null || [ $(( runway_secs * 2 )) -lt "${deadline:-0}" ] 2>/dev/null; } && hard=1
    local level="green"
    if   [ "$used" -ge 95 ] 2>/dev/null;            then level="red"
    elif [ "$atrisk" = 1 ] && [ "$hard" = 1 ];      then level="red"
    elif [ "$atrisk" = 1 ] || [ "$used" -ge 85 ] 2>/dev/null; then level="yellow"
    fi
    local hint=0
    { [ "$atrisk" = 1 ] || [ "$used" -ge 90 ] 2>/dev/null; } && hint=1
    echo "$level $runway_days $hint"
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

# ---------------------------------------------------------------------------
# 7d forecast: learn the user's weekday burn signature from usage.jsonl and
# project whether the remaining quota survives the remaining days. The pace
# model (above) only knows the window average; the profile knows that YOUR
# Tuesday burns 27%/day while YOUR Saturday burns 5%/day, so it can warn on a
# quiet Friday about next week — and stay quiet before a light weekend.
#
# All day math is epoch arithmetic (no awk strftime/mktime — GNU-only):
#   local_day = (epoch + tz_offset) / 86400;  dow = (local_day + 4) % 7
# with 0=Sun..6=Sat (epoch day 0 was a Thursday). Snapshots are partitioned by
# account uuid — usage.jsonl interleaves accounts and mixing them produces
# garbage burn rates (observed: 9000%/day). Plan changes rescale utilization%,
# so days are EWMA-weighted with a 14-day half-life: old scales fade away.
# ---------------------------------------------------------------------------

USAGE_LOG_MAX_BYTES="${USAGE_LOG_MAX_BYTES:-33554432}"  # 32 MiB cap

# Rotate usage.jsonl when it exceeds the cap. Single .1 backup; the profile
# builder reads .1 + current, so rotation never costs learned history.
rotate_usage_log() {
    local f="$1"
    [ -f "$f" ] || return 0
    local size
    size=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)
    [ "$size" -lt "$USAGE_LOG_MAX_BYTES" ] 2>/dev/null && return 0
    local rot_lock="${f}.rotate.lock"
    if mkdir "$rot_lock" 2>/dev/null; then
        mv -f "$f" "${f}.1" 2>/dev/null
        rmdir "$rot_lock" 2>/dev/null
    fi
}

# Rebuild forecast.cache from usage.jsonl (at most hourly; called from the
# fetch path, which is itself TTL-gated). Output: one small JSON the renders
# can read for free:
#   { computed_at, days_history, recent_24h, recent_48h,
#     weekday_profile: {"0":sun.. "6":sat, unknown days = -1} }
# Daily burn = sum of positive deltas of seven_day.utilization within a local
# calendar day (negative deltas = window reset; ignored by construction).
build_seven_day_profile() {
    local jsonl="$CLAUDE_ACCOUNT_DIR/usage.jsonl"
    local out="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    [ -f "$jsonl" ] || return 0
    local acct
    acct=$(jq -r '.account.uuid // empty' "$CLAUDE_ACCOUNT_DIR/profile.cache" 2>/dev/null)
    [ -n "$acct" ] || return 0
    if [ -f "$out" ]; then
        local computed age
        computed=$(jq -r '.computed_at // 0' "$out" 2>/dev/null)
        age=$(( $(date +%s) - ${computed:-0} ))
        [ "$age" -lt 3600 ] 2>/dev/null && return 0
    fi
    local now tzoff_s
    now=$(date +%s)
    # ±HHMM -> signed seconds (portable; date +%z works on GNU and BSD)
    tzoff_s=$(date +%z | awk '{ s=substr($0,1,1)=="-"?-1:1; h=substr($0,2,2)+0; m=substr($0,4,2)+0; print s*(h*3600+m*60) }')
    local data
    data=$( { cat "${jsonl}.1" 2>/dev/null; cat "$jsonl"; } | jq -r --arg a "$acct" '
            # Window identity for the ratio pairs: resets_at wobbles per
            # fetch (microseconds, and 06:59:59 vs 07:00:00 across the
            # boundary), so normalize to the nearest minute. Non-ISO values
            # fall back to the raw string ($raw — NOT `catch .`, which would
            # yield the error MESSAGE and give every empty/broken value one
            # shared fake identity, silently pairing across real windows).
            def norm: tostring | . as $raw
                | if $raw == "" then "" else
                    (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")
                          | fromdateiso8601 | (. + 30) / 60 | floor) catch $raw)
                  end;
            select((.user.uuid // "") == $a)
            | [.timestamp, (.seven_day.utilization // ""),
               (.five_hour.utilization // ""),
               ((.five_hour.resets_at // "") | norm)] | @tsv' 2>/dev/null \
        | sort -n | awk -F'\t' -v now="$now" -v tz="$tzoff_s" '
        $2 != "" {
            if (prev_set && $2 > prev) {
                d = $2 - prev
                day = int(($1 + tz) / 86400)
                burn[day] += d
                if (now - $1 <= 86400)  r24 += d
                if (now - $1 <= 172800) r48 += d
            }
            prev = $2; prev_set = 1
        }
        # Cross-window ratio: pair consecutive samples inside the SAME 5h
        # window (resets_at identity guards against pairing across a reset)
        # and accumulate how many 7d points each 5h point costs. This is the
        # physics that converts "windows left" into "weekly % spendable".
        $2 != "" && $3 != "" && $4 != "" {
            if (pr_set && $4 == pr_reset && $3 > pr_five && $2 >= pr_seven) {
                rf += $3 - pr_five; rs += $2 - pr_seven
            }
            pr_five = $3; pr_seven = $2; pr_reset = $4; pr_set = 1
        }
        END {
            today = int((now + tz) / 86400)
            for (day in burn) {
                age = today - day; if (age < 0) age = 0
                w = exp(-0.0495 * age)            # half-life 14 days
                dw = (day + 4) % 7                # 0=Sun .. 6=Sat
                num[dw] += burn[day] * w; den[dw] += w
                ndays++
            }
            # pct_per_window: 7d % consumed by a fully burned 5h window.
            # Trust it only after half a window of observed paired burn
            # (rf >= 50) with visible 7d movement (rs >= 3, guards integer
            # rounding); clamp to a sane band.
            ppw = -1
            if (rf >= 50 && rs >= 3) {
                ppw = rs / rf * 100
                if (ppw < 1)  ppw = 1
                if (ppw > 50) ppw = 50
            }
            printf "{\"computed_at\":%d,\"days_history\":%d,", now, ndays
            printf "\"recent_24h\":%.2f,\"recent_48h\":%.2f,", r24, r48
            printf "\"pct_per_window\":%.2f,", ppw
            printf "\"weekday_profile\":{"
            sep = ""
            for (i = 0; i <= 6; i++) {
                p = (den[i] > 0) ? num[i] / den[i] : -1
                printf "%s\"%d\":%.2f", sep, i, p; sep = ","
            }
            printf "}}\n"
        }')
    if [ -n "$data" ]; then
        printf '%s\n' "$data" >"${out}.tmp.$$" 2>/dev/null && mv -f "${out}.tmp.$$" "$out"
        debug_log "build_seven_day_profile: rebuilt ($(echo "$data" | jq -r '.days_history') days, acct=${acct:0:8})"
    fi
}

# Project the remaining window day-by-day against the learned profile and
# echo "<level> <dry_gap_hours>" when the quota dries up BEFORE the reset
# ("you will be out of usage while days still remain"). Empty output = no
# verdict (no cache, cold start < 14 days of history, or quota outlasts the
# window). The first 24h of the walk burns at max(profile, recent_24h) so a
# hot streak escalates before the weekday average catches up (L1 blend).
# Shared learned-profile walker: simulate burn from now to the reset using
# the weekday profile (recent-24h blended over the first day, exactly the
# seven_day_forecast behavior). Echoes "gap_h projected_end":
#   gap_h          hours between drying up and the reset, -1 if the quota
#                  outlasts the window
#   projected_end  final utilization at the reset, capped at 100
# Silent on cold start (<14 days history) or missing/empty inputs.
_seven_day_walk() {
    local used="$1" secs_left="$2"
    local fc="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    [ -f "$fc" ] || return 0
    [ -n "$secs_left" ] && [ "$secs_left" -gt 0 ] 2>/dev/null || return 0
    local used_int
    used_int=$(printf '%.0f' "$used" 2>/dev/null || echo 0)
    [ "$used_int" -gt 0 ] 2>/dev/null || return 0
    local now tzoff_s
    now=$(date +%s)
    tzoff_s=$(date +%z | awk '{ s=substr($0,1,1)=="-"?-1:1; h=substr($0,2,2)+0; m=substr($0,4,2)+0; print s*(h*3600+m*60) }')
    jq -r '[.days_history, .recent_24h,
            .weekday_profile["0"], .weekday_profile["1"], .weekday_profile["2"],
            .weekday_profile["3"], .weekday_profile["4"], .weekday_profile["5"],
            .weekday_profile["6"]] | @tsv' "$fc" 2>/dev/null \
    | awk -F'\t' -v used="$used_int" -v left="$secs_left" -v now="$now" -v tz="$tzoff_s" '
    {
        ndays = $1 + 0; r24 = $2 + 0
        for (i = 0; i <= 6; i++) prof[i] = $(i + 3) + 0
        if (ndays < 14) exit               # cold start: not enough history
        # fallback rate for never-seen weekdays: mean of known ones
        known = 0; sum = 0
        for (i = 0; i <= 6; i++) if (prof[i] >= 0) { sum += prof[i]; known++ }
        if (known == 0) exit
        fb = sum / known
        remaining = 100 - used
        t = now; end = now + left; burned = 0; gap_h = -1
        while (t < end) {
            day = int((t + tz) / 86400)
            day_end = (day + 1) * 86400 - tz
            step = (day_end < end ? day_end : end) - t
            rate = prof[(day + 4) % 7]; if (rate < 0) rate = fb
            if (t - now < 86400 && r24 > rate) rate = r24   # L1 blend
            add = rate * step / 86400.0
            if (gap_h < 0 && burned + add >= remaining && rate > 0) {
                dry = t + (remaining - burned) / rate * 86400.0
                gap_h = int((end - dry) / 3600.0)
            }
            burned += add; t = day_end
        }
        total = used + burned
        if (total > 100) total = 100
        printf "%d %d\n", gap_h, int(total + 0.5)
    }'
}

seven_day_forecast() {
    local used="$1" secs_left="$2"
    local used_int
    used_int=$(printf '%.0f' "$used" 2>/dev/null || echo 0)
    local gap_h proj_end
    read -r gap_h proj_end <<<"$(_seven_day_walk "$used_int" "$secs_left")"
    [ -n "$gap_h" ] && [ "$gap_h" != "-1" ] || return 0
    local level="yellow"
    { [ "$gap_h" -ge 48 ] || [ "$used_int" -ge 90 ]; } 2>/dev/null && level="red"
    echo "$level $gap_h"
}

# Learned cross-window ratio from forecast.cache: 7d percentage points a
# fully burned 5h window costs THIS account. Echoes a positive decimal, or
# nothing while unlearned — callers must not advise without it.
forecast_pct_per_window() {
    local fc="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    [ -f "$fc" ] || return 0
    local ppw
    ppw=$(jq -r '.pct_per_window // -1' "$fc" 2>/dev/null)
    awk -v p="${ppw:--1}" 'BEGIN{ if (p > 0) printf "%.2f", p }'
}

# Generalized change flash: signed delta between the current value and the
# last value THIS session rendered, held for QUOTA_BUMP_NOTICE_SECS after the
# change so the refresh right after a jump still shows it. One JSON state
# file holds every component ({key: {seen, at, delta}}); integer values only,
# callers scale floats first (cost -> cents). Unlike quota_bump_notice below
# (climb-only, the 5h/7d flash), this one also reports drops — a negative
# context delta after /compact is the whole point. Echoes the delta; 0 = quiet.
delta_flash() {
    local key="$1" cur="$2" state_file="$3"
    [ -n "$state_file" ] && [ -n "$key" ] || { echo 0; return 0; }
    case "$cur" in '' | *[!0-9-]*) echo 0; return 0 ;; esac
    local now="${STATUSLINE_TEST_NOW_EPOCH:-$(date +%s)}"

    local seen="" at=0 d=0
    if [ -f "$state_file" ]; then
        eval "$(jq -r --arg k "$key" '
            .[$k] // {} |
            @sh "seen=\(.seen // "")",
            @sh "at=\(.at // 0)",
            @sh "d=\(.delta // 0)"
        ' "$state_file" 2>/dev/null)"
    fi

    if [ -z "$seen" ]; then
        at=0 d=0 # first sighting is quiet
    elif [ "$cur" -ne "$seen" ] 2>/dev/null; then
        at=$now d=$((cur - seen))
    elif [ "$d" -ne 0 ] 2>/dev/null && [ $((now - at)) -lt "$QUOTA_BUMP_NOTICE_SECS" ] 2>/dev/null; then
        : # unchanged value keeps a still-fresh flash alive
    else
        at=0 d=0
    fi

    mkdir -p "$(dirname "$state_file")" 2>/dev/null
    local tmp="${state_file}.tmp.$$"
    if [ -f "$state_file" ]; then
        jq -c --arg k "$key" \
            --argjson v "{\"seen\":$cur,\"at\":$at,\"delta\":$d}" \
            '. + {($k): $v}' "$state_file" >"$tmp" 2>/dev/null
    else
        jq -n -c --arg k "$key" \
            --argjson v "{\"seen\":$cur,\"at\":$at,\"delta\":$d}" \
            '{($k): $v}' >"$tmp" 2>/dev/null
    fi
    if [ -s "$tmp" ]; then
        mv -f "$tmp" "$state_file" 2>/dev/null
    else
        rm -f "$tmp" 2>/dev/null
    fi
    echo "$d"
}

# Renders a delta_flash value in the shared flash idiom: reverse-video +N/-N
# bound tight to its component, same as the 5h/7d bump. Empty when quiet.
delta_flash_part() {
    local d="$1" color="$2"
    [ "$d" -ne 0 ] 2>/dev/null || return 0
    local sign="+"
    [ "$d" -lt 0 ] && { sign="-"; d=$((-d)); }
    printf '%s' "${color}${REVERSE}${sign}${d}${NO_REVERSE}${RESET}"
}

# Short-lived "+N" notice when a quota window's utilization climbs between
# renders. State is per-session ("what THIS statusline last rendered"), so
# concurrent sessions each get their own flash instead of racing over shared
# account state. Echoes "<five_delta> <seven_delta>"; 0 = quiet. Rules per
# window: first sighting is quiet; a climb records the increment and shows it
# for QUOTA_BUMP_NOTICE_SECS; an unchanged value keeps a still-fresh notice
# alive; a drop (window reset) clears silently — the fresh low number is its
# own signal. A second climb inside the window overwrites the notice (latest
# increment, not a running sum: "+N" answers "what just happened").
quota_bump_notice() {
    local five_cur="$1" seven_cur="$2" state_file="$3"
    [ -n "$state_file" ] || { echo "0 0"; return 0; }
    local now="${STATUSLINE_TEST_NOW_EPOCH:-$(date +%s)}"

    local five_seen="" five_at=0 five_d=0 seven_seen="" seven_at=0 seven_d=0
    if [ -f "$state_file" ]; then
        eval "$(jq -r '
            @sh "five_seen=\(.five.seen // "")",
            @sh "five_at=\(.five.bump_at // 0)",
            @sh "five_d=\(.five.delta // 0)",
            @sh "seven_seen=\(.seven.seen // "")",
            @sh "seven_at=\(.seven.bump_at // 0)",
            @sh "seven_d=\(.seven.delta // 0)"
        ' "$state_file" 2>/dev/null)"
    fi

    # _judge <cur> <seen> <bump_at> <delta> -> "<bump_at> <delta>" (delta 0 = quiet)
    _judge() {
        local cur="$1" seen="$2" at="${3:-0}" d="${4:-0}"
        if [ -z "$seen" ] || [ -z "$cur" ]; then echo "0 0"; return; fi
        if [ "$cur" -gt "$seen" ] 2>/dev/null; then
            echo "$now $((cur - seen))"
        elif [ "$cur" -lt "$seen" ] 2>/dev/null; then
            echo "0 0"
        elif [ "$d" -gt 0 ] 2>/dev/null && [ $((now - at)) -lt "$QUOTA_BUMP_NOTICE_SECS" ] 2>/dev/null; then
            echo "$at $d"
        else
            echo "0 0"
        fi
    }

    read -r five_at five_d <<<"$(_judge "$five_cur" "$five_seen" "$five_at" "$five_d")"
    read -r seven_at seven_d <<<"$(_judge "$seven_cur" "$seven_seen" "$seven_at" "$seven_d")"

    mkdir -p "$(dirname "$state_file")" 2>/dev/null
    local tmp="${state_file}.tmp.$$"
    jq -n -c \
        --argjson fs "${five_cur:-0}" --argjson fa "$five_at" --argjson fd "$five_d" \
        --argjson ss "${seven_cur:-0}" --argjson sa "$seven_at" --argjson sd "$seven_d" \
        --argjson up "$now" \
        '{five:{seen:$fs,bump_at:$fa,delta:$fd},
          seven:{seen:$ss,bump_at:$sa,delta:$sd},
          updated_at:$up}' >"$tmp" 2>/dev/null && mv -f "$tmp" "$state_file" 2>/dev/null
    rm -f "$tmp" 2>/dev/null

    echo "${five_d:-0} ${seven_d:-0}"
}

# Two-letter badge label for a model-scoped limit, following the op/sn
# convention. Unknown families degrade to their first two letters rather
# than hiding the quota behind a name we haven't mapped yet.
model_scope_abbrev() {
    case "$1" in
    opus*) echo "op" ;;
    sonnet*) echo "sn" ;;
    haiku*) echo "hk" ;;
    fable*) echo "fb" ;;
    *) printf '%.2s\n' "$1" ;;
    esac
}

# Model-scoped weekly quota badge (limits[] kind=weekly_scoped, the contract
# that replaced seven_day_opus/sonnet). Renders only the scope matching the
# model THIS session is burning — other models' quotas are noise. Substring
# match, so scope "Fable" hits claude-fable-5. It's a WEEKLY number (shares
# its reset with the 7d badge) but displays next to the model+context block,
# not in the 5h/7d cluster: the quota is a property of the model you're
# running, and that's where the eye looks for it.
build_scoped_quota_display() {
    local usage_data="$1"
    local current_model="$2"
    local flash_state="${3:-}" # optional: enables the +N change flash
    [ -n "$usage_data" ] || return 0
    [ -n "$current_model" ] || return 0

    local scoped_tsv
    scoped_tsv=$(echo "$usage_data" | jq -r '
        .limits[]? | select(.kind == "weekly_scoped" and (.scope.model.display_name // "") != "")
        | [(.scope.model.display_name | ascii_downcase), (.percent // 0)] | @tsv' 2>/dev/null)
    [ -n "$scoped_tsv" ] || return 0

    local model_lc
    model_lc=$(printf '%s' "$current_model" | tr '[:upper:]' '[:lower:]')
    local scope_name scope_pct
    while IFS=$'\t' read -r scope_name scope_pct; do
        [ -n "$scope_name" ] || continue
        case "$model_lc" in
        *"$scope_name"*)
            local scope_int=$(printf '%.0f' "$scope_pct" 2>/dev/null || echo 0)
            if [ "$scope_int" -gt 0 ] 2>/dev/null; then
                local color=$(get_seven_day_color "$scope_int")
                local flash=""
                if [ -n "$flash_state" ]; then
                    flash=$(delta_flash_part "$(delta_flash scoped "$scope_int" "$flash_state")" "$color")
                fi
                printf '%s' "${DIM}$(model_scope_abbrev "$scope_name")${color}[${scope_int}%]${RESET}${flash}"
                return 0
            fi
            ;;
        esac
    done <<<"$scoped_tsv"
}

build_usage_display() {
    local usage_data="$1"
    local user_tier="${2:-}"  # MAX, PRO, ENT, TEAM, or empty
    local bump_state_file="${3:-}"  # optional: enables the +N bump flash

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

    local five_bump=0 seven_bump=0
    if [ -n "$bump_state_file" ]; then
        read -r five_bump seven_bump <<<"$(quota_bump_notice "$five_int" "$seven_int" "$bump_state_file")"
    fi

    local parts=()

    # 5h quota (always show if >0)
    # The reset time is always visible while a window is live: a 5h horizon
    # is short enough that "when does it reset" is the number you plan the
    # current sitting around, so it isn't gated on pressure like the 7d
    # deadline. WALL-CLOCK (@14:30), not a countdown: the statusline only
    # re-renders on activity, so "@1h38m" decays into a lie during idle gaps
    # while "@14:30" stays true in a frozen frame (see format_reset_absolute).
    # The 7d badge is hybrid: day-relative @Nd while >= 24h out, wall-clock
    # @HH:MM inside the last day (see the 7d reset_suffix below).
    # Recovery color (DIM_GREEN) when high usage + reset <= 30min.
    if [ "$five_int" -gt 0 ] 2>/dev/null; then
        local color=$(get_usage_color "$five_int")
        local reset_suffix=""
        local reset_secs=""
        [ -n "$five_reset" ] && reset_secs=$(get_reset_seconds "$five_reset")

        if [ -n "$five_reset" ]; then
            if [ "$five_int" -ge 80 ] && [ -n "$reset_secs" ] && [ "$reset_secs" -le $FIVE_HOUR_RECOVERY_SECS ] 2>/dev/null; then
                color="$DIM_GREEN"
            fi
            local abs=$(format_reset_absolute "$five_reset")
            [ -n "$abs" ] && reset_suffix="${DIM}@${abs}${color}"
        fi
        # Bump flash: reverse-video +N right after the badge — bound tight so
        # it can't read as belonging to the next badge, unmissable without
        # adding a fourth color lane. ASCII + (a ▲ glyph rendered poorly).
        local bump_part=""
        [ "$five_bump" -gt 0 ] 2>/dev/null && bump_part="${color}${REVERSE}+${five_bump}${NO_REVERSE}"
        parts+=("${DIM}5h${color}[${five_int}%${reset_suffix}]${bump_part}${RESET}")
    fi

    # 7d aggregate quota (if present and >0). Color comes from PACE, not level:
    # the question is "will the quota outlast the window?" not "how full is it?".
    # The @reset deadline appears only under real pressure — a high % late in
    # the window is fine and stays quiet.
    if [ "$seven_int" -gt 0 ] 2>/dev/null; then
        local reset_secs=""
        [ -n "$seven_reset" ] && reset_secs=$(get_reset_seconds "$seven_reset")

        # Opt-in: skip weekends in the deadline so the meter doesn't alarm over
        # days the user won't spend quota on (the limit itself is calendar-based).
        local deadline_secs="$reset_secs"
        case "${CLAUDE_7D_WORKDAYS:-}" in
        1|true|yes|on)
            if [ -n "$reset_secs" ]; then
                local wknd; wknd=$(weekend_secs_ahead "$reset_secs")
                deadline_secs=$(( reset_secs - wknd ))
                [ "$deadline_secs" -lt 0 ] && deadline_secs=0
            fi
            ;;
        esac

        # seven_day_pace also returns runway-days and a hint flag; only the
        # level drives the display (no runway text — every compact rendering
        # of "days of quota left" was misread as days until reset).
        local sev_level sev_runway sev_hint
        read -r sev_level sev_runway sev_hint <<<"$(seven_day_pace "$seven_int" "$reset_secs" "$deadline_secs")"

        # Learned forecast (weekday profile + recent burn) can escalate the
        # verdict: it knows YOUR heavy days are still ahead when the plain
        # window-average looks calm. Worst of the two levels wins.
        local fc_level fc_gap
        read -r fc_level fc_gap <<<"$(seven_day_forecast "$seven_int" "$reset_secs")"
        if [ "$fc_level" = "red" ]; then
            sev_level="red"
        elif [ "$fc_level" = "yellow" ] && [ "$sev_level" = "green" ]; then
            sev_level="yellow"
        fi

        local color="$GREEN"
        case "$sev_level" in red) color="$RED";; yellow) color="$YELLOW";; esac

        # Recovery: high usage + imminent reset (<= 12h) — relief is basically
        # here, so dim the alarm rather than scream at a wall you won't hit.
        if [ "$seven_int" -ge 70 ] && [ -n "$reset_secs" ] && [ "$reset_secs" -le $SEVEN_DAY_RECOVERY_SECS ] 2>/dev/null; then
            color="$DIM_GREEN"
        fi

        # Under pressure, be explicit about when relief arrives. Hybrid form:
        # >= 24h out stays day-relative (@Nd — decays one day per day in a
        # frozen frame; mild, and the narrowest honest form), but inside the
        # last day it switches to the 5h badge's wall-clock idiom (@04:00).
        # The old @Nh/@<1h countdown decayed by the hour during idle — worst
        # exactly when pressure keeps this suffix visible, convincing you
        # you're still capped after relief already arrived. Under 24h a bare
        # @HH:MM is unambiguous (next occurrence), same as the 5h badge.
        # Shown whenever the verdict warns — abnormal burn 5 days out
        # included — or usage is already high. On-pace badges stay 7d[NN%].
        local reset_suffix=""
        if [ -n "$reset_secs" ] && [ "$reset_secs" -gt 0 ] 2>/dev/null \
           && { [ "$sev_level" != "green" ] || [ "$seven_int" -ge 85 ] 2>/dev/null; }; then
            local rem=""
            if [ "$reset_secs" -ge 86400 ]; then
                rem="$(( reset_secs / 86400 ))d"
            else
                rem=$(format_reset_absolute "$seven_reset")
            fi
            [ -n "$rem" ] && reset_suffix="${DIM}@${rem}${color}"
        fi
        local bump_part=""
        [ "$seven_bump" -gt 0 ] 2>/dev/null && bump_part="${color}${REVERSE}+${seven_bump}${NO_REVERSE}"
        parts+=("${DIM}7d${color}[${seven_int}%${reset_suffix}]${bump_part}${RESET}")
    fi

    # Legacy model-specific 7d quotas (pre-limits[] responses only). When the
    # response carries weekly_scoped limits the new contract supersedes these
    # fields (they arrive null anyway); the scoped badge itself renders next
    # to the model+context block via build_scoped_quota_display, not here.
    # MAX users: show opus only (per your spec: "no need to show sonnet for max users")
    # Others: show sonnet
    local has_scoped=false
    echo "$usage_data" | jq -e '[.limits[]? | select(.kind == "weekly_scoped")] | length > 0' >/dev/null 2>&1 && has_scoped=true
    if [ "$has_scoped" = false ]; then
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

# ---------------------------------------------------------------------------
# Advisor line (second statusline row). Design rule: line 2 speaks only when
# the numbers on line 1 don't mean what they appear to mean, and every clause
# derives from a badge line 1 already shows — no third alarm channel. It cuts
# both ways, with a voice per direction:
#   pressure     "! ..." yellow/red  you'll hit a wall before a reset
#   opportunity  "+ ..." cyan        paid capacity is about to expire unused,
#                                    or a sibling account is free while you're
#                                    pinned — spend, don't conserve
# Cyan is reserved for opportunity: it can never mean pressure, so the color
# alone carries the stance. Quiet = no row at all (Claude Code renders each
# stdout line as its own row; printing nothing costs nothing). All times are
# wall-clock or future-to-future gaps — both freeze-safe in an idle frame,
# same idiom as the badges above.
# ---------------------------------------------------------------------------

# Sibling-account relief hint for shared-home fleets (deva): when THIS
# account's 5h is pinned, a fresh sibling cache with a mostly-idle 5h window
# is the actionable way out. Reads accounts/*/usage.cache — no credentials,
# no fetches. Echoes "tag 5h[N%] free" for the idlest fresh sibling, or "".
build_advisor_fleet_hint() {
    local accounts_dir="$1" self_tag="$2"
    [ -n "$accounts_dir" ] && [ -d "$accounts_dir" ] || return 0
    local now best_tag="" best_util=101 dir tag fetched util age
    now=$(date +%s)
    for dir in "$accounts_dir"/*/; do
        [ -f "$dir/usage.cache" ] || continue
        tag=$(basename "$dir")
        [ "$tag" = "$self_tag" ] && continue
        # Reset before eval: a corrupt cache makes jq emit nothing, and the
        # previous sibling's numbers must not leak onto this tag.
        fetched=0 util=""
        eval "$(jq -r '
            @sh "fetched=\(.fetched_at // 0)",
            @sh "util=\(.five_hour.utilization // "")"
        ' "$dir/usage.cache" 2>/dev/null)"
        [ -n "$util" ] || continue
        age=$((now - ${fetched:-0}))
        [ "$age" -le "$ADVISOR_FLEET_FRESH_SECS" ] 2>/dev/null || continue
        util=$(printf '%.0f' "$util" 2>/dev/null) || continue
        if [ "$util" -le "$ADVISOR_FLEET_FREE_PCT" ] && [ "$util" -lt "$best_util" ]; then
            best_util="$util"
            best_tag="$tag"
        fi
    done
    [ -n "$best_tag" ] && echo "${best_tag} 5h[${best_util}%] free"
    return 0
}

# Build the advisor row. Echoes a colored line or nothing.
#   auto:   speak under pressure OR when paid capacity is going to waste
#   always: additionally show the weekly budget when calm
#   off:    nothing
# Clauses in value order (max two survive, joined "; "):
#   fb capped — back ~Thu 07:00           running model's weekly_scoped limit
#                                         hit 100: the model just went away,
#                                         the useful fact is when it returns
#   5h caps ~14:20, 52m before reset      linear projection, only while the
#                                         5h badge is already yellow/red and
#                                         relief is not imminent
#   7d resets @07:00, 56% unused — spend it | — ~40% expires even at full burn
#                                         expiring surplus: inside the last
#                                         day of the week, green on line 1
#                                         means forfeiting, not fine — the
#                                         exact zone pressure logic mutes.
#                                         Tail is feasibility-checked against
#                                         the learned pct_per_window ratio;
#                                         no ratio yet, no tail
#   alt 5h[8%] free                     fleet relief once 5h >= 90
#   fb caps ~Wed 18:00, 1d before reset   scoped-limit pace, same math and
#                                         gates as the 7d aggregate
#   7d dry ~Thu 09:00, 2d before reset — then extra billing|hard stop
#                                         learned forecast when trained, else
#                                         linear pace when seven_day_pace
#                                         already warns
#   7d on pace to leave ~62% unused — go heavier
#                                         mid-week underuse, engaged sessions
#                                         only — reaches exactly the users
#                                         who can act on it
#   ~19x5h left, even pace 1.1%/win, heading ~52%
#                                         always-mode calm line
build_advisor_line() {
    local usage_data="$1" mode="${2:-auto}" current_model="${3:-}"
    [ "$mode" = "off" ] && return 0
    [ -n "$usage_data" ] || return 0

    local five_util five_reset seven_util seven_reset extra_enabled
    eval "$(echo "$usage_data" | jq -r '
        @sh "five_util=\(.five_hour.utilization // 0)",
        @sh "five_reset=\(.five_hour.resets_at // "")",
        @sh "seven_util=\(.seven_day.utilization // 0)",
        @sh "seven_reset=\(.seven_day.resets_at // "")",
        @sh "extra_enabled=\(.extra_usage.is_enabled // false)"
    ' 2>/dev/null)"

    local five_int seven_int
    five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
    seven_int=$(printf '%.0f' "$seven_util" 2>/dev/null || echo 0)
    local five_secs seven_secs
    five_secs=$(get_reset_seconds "$five_reset")
    seven_secs=$(get_reset_seconds "$seven_reset")
    local now
    now=$(date +%s)

    # pressure: any wall-ahead clause fired (drives ! + yellow/red).
    # seven_spoken: some clause already told the 7d story — the window gets
    # one voice per render, never two that could disagree.
    local clauses=() level="yellow" pressure=0 seven_spoken=0

    # Weekly limit scoped to the model THIS session runs (limits[]
    # kind=weekly_scoped, same substring match as the fb[N%] badge). Other
    # models' quotas stay out — noise here, and invisible on line 1.
    local scope_name="" scope_int="" scope_secs=""
    if [ -n "$current_model" ]; then
        local model_lc scoped_tsv
        model_lc=$(printf '%s' "$current_model" | tr '[:upper:]' '[:lower:]')
        scoped_tsv=$(echo "$usage_data" | jq -r --arg m "$model_lc" '
            [.limits[]? | select(.kind == "weekly_scoped" and (.scope.model.display_name // "") != "")
             | (.scope.model.display_name | ascii_downcase) as $s
             | select($m | contains($s))]
            | first // empty
            | [(.scope.model.display_name | ascii_downcase), (.percent // 0), (.resets_at // "")] | @tsv' 2>/dev/null)
        if [ -n "$scoped_tsv" ]; then
            local scope_pct scope_reset
            IFS=$'\t' read -r scope_name scope_pct scope_reset <<<"$scoped_tsv"
            scope_int=$(printf '%.0f' "$scope_pct" 2>/dev/null || echo 0)
            scope_secs=$(get_reset_seconds "$scope_reset")
        fi
    fi

    # Scoped limit capped: the model this session runs just became
    # unavailable — the top story, and the one number that matters is when
    # it comes back. No recovery suppression: "back ~Thu 07:00" is exactly
    # what an imminent reset makes MORE useful.
    if [ -n "$scope_int" ] && [ "$scope_int" -ge 100 ] 2>/dev/null \
       && [ -n "$scope_secs" ] && [ "$scope_secs" -gt 0 ] 2>/dev/null; then
        local back_str
        back_str=$(_fmt_epoch $((now + scope_secs)) '%a %H:%M')
        if [ -n "$back_str" ]; then
            clauses+=("$(model_scope_abbrev "$scope_name") capped — back ~${back_str}")
            pressure=1 level="red"
        fi
    fi

    # 5h cap projection. Gate = the 5h badge's own pressure gate (>= 80),
    # recovery-suppressed exactly like its color. At 100% line 1 already
    # says capped + reset time; projecting is pointless — only the fleet
    # hint below still helps there.
    if [ "$five_int" -ge 80 ] && [ "$five_int" -lt 100 ] \
       && [ -n "$five_secs" ] && [ "$five_secs" -gt "$FIVE_HOUR_RECOVERY_SECS" ] 2>/dev/null; then
        local elapsed=$((18000 - five_secs))
        if [ "$elapsed" -ge "$ADVISOR_PACE_MIN_ELAPSED" ]; then
            local cap_secs=$(( (100 - five_int) * elapsed / five_int ))
            if [ "$cap_secs" -lt "$five_secs" ]; then
                local cap_hhmm gap
                cap_hhmm=$(_fmt_epoch $((now + cap_secs)) '%H:%M')
                gap=$(format_duration $(( (five_secs - cap_secs) * 1000 )))
                if [ -n "$cap_hhmm" ]; then
                    clauses+=("5h caps ~${cap_hhmm}, ${gap} before reset")
                    pressure=1
                    [ "$five_int" -ge 90 ] && level="red"
                fi
            fi
        fi
    fi

    # Expiring surplus — use it or lose it. Inside the last day of the 7d
    # window a big green remainder is not headroom, it's forfeiture: at
    # reset it vanishes whether spent or not. This is the zone where the
    # pressure clauses go quiet (recovery), and precisely where waste peaks.
    # The tail is feasibility-checked against the learned pct_per_window
    # ratio: burning is rate-capped by the 5h mechanism (current headroom
    # until its reset, full windows after), so "spend it" only appears when
    # full-tilt burn can actually consume the surplus; past that point the
    # honest tail is how much expires no matter what. Unlearned ratio = no
    # tail: never advise what we can't back.
    if [ "$seven_int" -gt 0 ] && [ -n "$seven_secs" ] && [ "$seven_secs" -gt 0 ] 2>/dev/null \
       && [ "$seven_secs" -le "$ADVISOR_EXPIRY_HORIZON_SECS" ] 2>/dev/null \
       && [ $((100 - seven_int)) -ge "$ADVISOR_SURPLUS_MIN_PCT" ]; then
        local when surplus tail="" ppw reachable=""
        when=$(format_reset_absolute "$seven_reset")
        surplus=$((100 - seven_int))
        ppw=$(forecast_pct_per_window)
        if [ -n "$ppw" ]; then
            reachable=$(awk -v ppw="$ppw" -v ss="$seven_secs" -v fs="${five_secs:-0}" -v fu="$five_int" 'BEGIN{
                cap = ppw * (100 - fu) / 100          # current window headroom
                if (fs > 0 && fs < ss) {
                    leg = ppw * fs / 18000            # time-limited until 5h reset
                    r = (leg < cap ? leg : cap) + ppw * (ss - fs) / 18000
                } else {
                    leg = ppw * ss / 18000            # 5h window outlasts 7d reset
                    r = (leg < cap ? leg : cap)
                }
                printf "%d", int(r + 0.5)
            }')
        fi
        if [ -n "$reachable" ]; then
            if [ "$reachable" -ge "$surplus" ] 2>/dev/null; then
                tail=" — spend it"
            else
                tail=" — ~$((surplus - reachable))% expires even at full burn"
            fi
        fi
        if [ -n "$when" ]; then
            clauses+=("7d resets @${when}, ${surplus}% unused${tail}")
            seven_spoken=1
        fi
    fi

    # Fleet relief: once this account's 5h is effectively spent, the useful
    # fact is which sibling isn't. Opportunity, not alarm — line 1 already
    # screams about the cap.
    if [ "$five_int" -ge 90 ] && [ -n "${ACCOUNT_TAG:-}" ]; then
        local hint
        hint=$(build_advisor_fleet_hint "${STATUSLINE_HOME}/accounts" "$ACCOUNT_TAG")
        [ -n "$hint" ] && clauses+=("$hint")
    fi

    # Scoped-limit pace: the running model's weekly quota caps before its
    # reset. Same linear math and recovery suppression as the 7d aggregate,
    # same >= 80 gate as its badge color.
    if [ -n "$scope_int" ] && [ "$scope_int" -ge 80 ] && [ "$scope_int" -lt 100 ] 2>/dev/null \
       && [ -n "$scope_secs" ] && [ "$scope_secs" -gt "$SEVEN_DAY_RECOVERY_SECS" ] 2>/dev/null; then
        local sc_elapsed=$((SEVEN_DAY_WINDOW_SECS - scope_secs))
        if [ "$sc_elapsed" -ge "$ADVISOR_PACE_MIN_ELAPSED" ]; then
            local sc_cap=$(( (100 - scope_int) * sc_elapsed / scope_int ))
            if [ "$sc_cap" -lt "$scope_secs" ]; then
                local sc_str sc_gap_secs sc_gap
                sc_str=$(_fmt_epoch $((now + sc_cap)) '%a %H:%M')
                sc_gap_secs=$((scope_secs - sc_cap))
                if [ "$sc_gap_secs" -ge 172800 ]; then
                    sc_gap="$((sc_gap_secs / 86400))d"
                else
                    sc_gap=$(format_duration $((sc_gap_secs * 1000)))
                fi
                if [ -n "$sc_str" ]; then
                    clauses+=("$(model_scope_abbrev "$scope_name") caps ~${sc_str}, ${sc_gap} before reset")
                    pressure=1
                    [ "$scope_int" -ge 90 ] && level="red"
                fi
            fi
        fi
    fi

    # 7d dry projection. The learned forecast speaks first (it can warn on a
    # calm Friday about your heavy Tuesday — and it already escalates line
    # 1's color, so the gate stays shared). Cold start falls back to linear
    # pace, but only when seven_day_pace already warns. Recovery (<= 12h to
    # reset) stays quiet, mirroring the badge — the surplus clause owns that
    # zone.
    if [ "$seven_spoken" = 0 ] && [ "$seven_int" -gt 0 ] && [ "$seven_int" -lt 100 ] \
       && [ -n "$seven_secs" ] && [ "$seven_secs" -gt "$SEVEN_DAY_RECOVERY_SECS" ] 2>/dev/null; then
        local dry_epoch="" gap_secs="" sev_verb="dry" sev_level=""
        local fc_level fc_gap
        read -r fc_level fc_gap <<<"$(seven_day_forecast "$seven_int" "$seven_secs")"
        if [ -n "$fc_level" ]; then
            gap_secs=$((fc_gap * 3600))
            dry_epoch=$((now + seven_secs - gap_secs))
            sev_level="$fc_level"
        else
            local p_level p_runway p_hint
            read -r p_level p_runway p_hint <<<"$(seven_day_pace "$seven_int" "$seven_secs")"
            if [ "${p_hint:-0}" = "1" ]; then
                local elapsed7=$((SEVEN_DAY_WINDOW_SECS - seven_secs))
                local cap7=$(( (100 - seven_int) * elapsed7 / seven_int ))
                if [ "$cap7" -lt "$seven_secs" ]; then
                    dry_epoch=$((now + cap7))
                    gap_secs=$((seven_secs - cap7))
                    sev_verb="caps"
                    sev_level="$p_level"
                fi
            fi
        fi
        if [ -n "$dry_epoch" ]; then
            local dry_str gap_str tail
            dry_str=$(_fmt_epoch "$dry_epoch" '%a %H:%M')
            if [ "$gap_secs" -ge 172800 ]; then
                gap_str="$((gap_secs / 86400))d"
            else
                gap_str=$(format_duration $((gap_secs * 1000)))
            fi
            if [ "$extra_enabled" = "true" ]; then
                tail="then extra billing"
            else
                tail="then hard stop"
            fi
            if [ -n "$dry_str" ]; then
                clauses+=("7d ${sev_verb} ~${dry_str}, ${gap_str} before reset — ${tail}")
                pressure=1 seven_spoken=1
                [ "$sev_level" = "red" ] && level="red"
            fi
        fi
    fi

    # Underuse: on pace to strand a large chunk of the week. The learned
    # walk speaks first — it knows YOUR remaining weekdays, so it can warn
    # from day two without waiting for linear pace to mean anything; cold
    # start falls back to linear past half the window. Speaks only in an
    # engaged, unsqueezed session (5h in [25,80), no pressure clause) — the
    # statusline renders while you work, so this reaches exactly the person
    # who can act on it, and never nags an idle or already-constrained one.
    if [ "$seven_spoken" = 0 ] && [ "$pressure" = 0 ] && [ "$seven_int" -gt 0 ] \
       && [ "$five_int" -ge "$ADVISOR_UNDERUSE_MIN_5H" ] && [ "$five_int" -lt 80 ] 2>/dev/null \
       && [ -n "$seven_secs" ] && [ "$seven_secs" -gt "$ADVISOR_EXPIRY_HORIZON_SECS" ] 2>/dev/null; then
        local elapsed7=$((SEVEN_DAY_WINDOW_SECS - seven_secs))
        local heading="" walk_gap walk_end
        read -r walk_gap walk_end <<<"$(_seven_day_walk "$seven_int" "$seven_secs")"
        if [ -n "$walk_end" ] && [ "$elapsed7" -ge 172800 ]; then
            heading="$walk_end"
        elif [ $((elapsed7 * 2)) -ge "$SEVEN_DAY_WINDOW_SECS" ]; then
            heading=$((seven_int * SEVEN_DAY_WINDOW_SECS / elapsed7))
        fi
        if [ -n "$heading" ] && [ "$heading" -le "$ADVISOR_UNDERUSE_END_PCT" ] 2>/dev/null; then
            clauses+=("7d on pace to leave ~$((100 - heading))% unused — go heavier")
        fi
    fi

    if [ "${#clauses[@]}" -gt 0 ]; then
        local text="${clauses[0]}"
        [ "${#clauses[@]}" -ge 2 ] && text="${text}; ${clauses[1]}"
        if [ "$pressure" = 1 ]; then
            local color="$YELLOW"
            [ "$level" = "red" ] && color="$RED"
            echo "${color}! ${text}${RESET}"
        else
            echo "${CYAN}+ ${text}${RESET}"
        fi
        return 0
    fi

    # Calm + always: the weekly budget in one breath. ceil'd window count so
    # a partial window still counts as spendable; "heading ~N%" is the
    # learned end-of-week projection when trained, linear once the window is
    # at least a day old.
    if [ "$mode" = "always" ] && [ "$seven_int" -gt 0 ] && [ "$seven_int" -lt 100 ] \
       && [ -n "$seven_secs" ] && [ "$seven_secs" -gt 0 ] 2>/dev/null; then
        local windows=$(( (seven_secs + 17999) / 18000 ))
        if [ "$windows" -gt 0 ]; then
            local even heading_part=""
            even=$(awk -v h=$((100 - seven_int)) -v w="$windows" 'BEGIN{printf "%.1f", h/w}')
            local elapsed7=$((SEVEN_DAY_WINDOW_SECS - seven_secs))
            local heading="" walk_gap walk_end
            read -r walk_gap walk_end <<<"$(_seven_day_walk "$seven_int" "$seven_secs")"
            if [ -n "$walk_end" ]; then
                heading="$walk_end"
            elif [ "$elapsed7" -ge 86400 ]; then
                heading=$((seven_int * SEVEN_DAY_WINDOW_SECS / elapsed7))
                [ "$heading" -gt 100 ] && heading=100
            fi
            [ -n "$heading" ] && heading_part=", heading ~${heading}%"
            echo "${DIM}- ~${windows}x5h left, even pace ${even}%/win${heading_part}${RESET}"
        fi
    fi
    return 0
}

get_user_tier() {
    local tier=""
    local profile_cache="${CLAUDE_ACCOUNT_DIR:-$CLAUDE_CACHE_DIR}/profile.cache"
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

    # Runner-provided account tag beats the profile display name: two
    # accounts can carry the same human name, the tag (@work / @self)
    # is what tells concurrent sessions apart. Slightly wider truncation
    # than names — tags like api-key-1a2b are identity, not prose.
    if [ -n "${ACCOUNT_TAG:-}" ]; then
        name="$ACCOUNT_TAG"
        [ "${#name}" -gt 12 ] && name="${name:0:11}."
        name="@$name"
    else
        local profile_cache="${CLAUDE_ACCOUNT_DIR:-$CLAUDE_CACHE_DIR}/profile.cache"
        if [ -f "$profile_cache" ]; then
            name=$(jq -r '.account.display_name // empty' "$profile_cache" 2>/dev/null)
        fi
        if [ "${#name}" -gt 8 ]; then
            name="${name:0:7}."
        fi
    fi

    # Tier is identity, not status — neutral white-weight so it never reads as
    # a quota signal (MAX used to be green, which collided with "quota healthy").
    local tier_color="$DIM"
    case "$tier" in
        "MAX")        tier_color="$BOLD_WHITE" ;;
        "PRO")        tier_color="$WHITE" ;;
        "ENT"|"TEAM") tier_color="$DIM" ;;
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
            git_info=" ${WHITE}(${branch}*)${RESET}"
        else
            git_info=" ${DIM}(${branch})${RESET}"
        fi
    fi
fi

# settings.json .model is only a fallback for the rare case stdin carries no
# model id — it's a static default a session can override, so it must not be
# read (let alone preferred) when stdin already tells us the running model.
configured_model=""
claude_config_dir="${CLAUDE_CONFIG_DIR:-$CLAUDE_HOME/.claude}"
if [ -z "$model_id" ] && [ -f "$claude_config_dir/settings.json" ]; then
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
    *"fable"*) echo "fable" ;;
    *)         echo "unknown" ;;
    esac
}

# Detect if this is a 1M context model. Prefer the CLI's authoritative window
# size over the model name — since 2.1.173 the [1m] suffix is stripped
# whenever 1M is the active default (observed on fable, opus, and sonnet-5),
# so the name alone under-detects. Order: real window size > name.
#   1. ctx_size > 200k          — the window the CLI reports (ground truth)
#   2. [1m] suffix / 1M family  — name fallback for older CLIs lacking ctx_size
#
# exceeds_200k_tokens is NOT a window-size signal and must not be used as one:
# real logs show claude-opus-4-6 (a genuine 200k-window model, no [1m] suffix)
# reporting exceeds_200k_tokens=true once cumulative session usage passes
# 200k tokens (total_input_tokens > 200000 predicts the flag in 839/840
# sampled turns; context_window_size > 200000 predicts it in only 719/840).
# The flag tracks "this session has used over 200k tokens so far", not "this
# window is bigger than 200k" — treating it as the latter mis-tagged a real
# 200k opus session as opus4.6[1m] on ~14% of observed renders.
is_1m_model() {
    if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 200000 ] 2>/dev/null; then
        return 0
    fi
    [[ "$model_id" == *"[1m]"* ]] || is_default_1m_family "$model_id"
}

# Premium pricing band for 1M-window models: above 200k tokens the input rate
# is higher. The cue lives in the CONTEXT BAR's color (not extra text — the
# absolute NNNk was redundant with the bar's own percentage): yellow past 200k,
# red past 800k. Echoes 0 (none) / 1 (yellow) / 2 (red).
# Computed from ctx_size × context_pct only — see is_1m_model for why
# exceeds_200k_tokens is not a valid signal here either.
premium_band_level() {
    local size="${ctx_size:-1000000}"
    local abs=""
    if [ -n "$context_pct" ] && [ "$size" -gt 0 ] 2>/dev/null; then
        abs=$(( context_pct * size / 100 ))
    fi
    if [ -n "$abs" ] && [ "$abs" -gt 800000 ] 2>/dev/null; then
        echo 2
    elif [ -n "$abs" ] && [ "$abs" -gt 200000 ] 2>/dev/null; then
        echo 1
    else
        echo 0
    fi
}

# The [1m] tag itself is now constant — band pressure is the bar's job.
build_1m_tag() {
    echo "[1m]"
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
        if [[ "$rest" == *-* ]]; then
            # major.minor versioning (opus-4-8, sonnet-4-6, haiku-4-5)
            local minor="${rest#*-}"
            minor="${minor%%-*}"
            echo "${family}${major}.${minor}"
        else
            # flat versioning (sonnet-5) — no minor component to append
            echo "${family}${major}"
        fi
        ;;
    claude-fable-*)
        # Fable uses single-component versioning (claude-fable-5) — no
        # major.minor split — so abbreviate to a 4-char family + version: fabl5.
        local rest="${m#claude-fable-}"
        local major="${rest%%-*}"
        echo "fabl${major}"
        ;;
    *) echo "$m" ;;
    esac
}

# PRIMARY: the model the session is actually running THIS render, from the
# stdin model.id. This is ground truth — the same source as the context window
# — so the name and the window can never disagree. A session can switch models
# mid-flight (/model, --model), and stdin tracks that; settings.json cannot.
if [ -n "$model_id" ]; then
    base_id="${model_id%%\[*\]}"
    abbreviated=$(abbreviate_model_id "$base_id")
    if [ "$abbreviated" != "$base_id" ]; then
        model_text="$abbreviated"
    else
        model_text="$runtime_model"
    fi
    # Identity lane: full-strength family color (magenta/cyan/blue).
    case "$runtime_model" in
    "opus")   model_color='\033[0;35m' ;;
    "sonnet") model_color='\033[0;36m' ;;
    "haiku")  model_color='\033[0;94m' ;;
    # Fable renders in red in the Claude Code TUI; bright red (0;91) matches
    # that identity while staying distinct from the pressure red (0;31).
    "fable")  model_color='\033[0;91m' ;;
    *)        model_color='\033[0;37m' ;;
    esac
# FALLBACK: stdin gave no model id (rare) — fall back to the configured default.
elif [ -n "$configured_model" ]; then
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
        model_color='\033[0;94m'
        if [ "$local_cfg" = "haiku" ]; then
            model_text="haiku"
        else
            model_text=$(abbreviate_model_id "$local_cfg")
        fi
        ;;
    "fable"|claude-fable-*)
        model_color='\033[0;91m'
        if [ "$local_cfg" = "fable" ]; then
            model_text="fable"
        else
            model_text=$(abbreviate_model_id "$local_cfg")
        fi
        ;;
    *)
        model_text="$local_cfg"
        model_color='\033[0;37m'
        ;;
    esac
fi

context_info=""
context_pct=""
# One state file drives every component's +X/-X change flash (see delta_flash).
flash_state_file="$CLAUDE_CACHE_DIR/${stdin_session_id:-global}_flash_seen"

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

# Append the constant 1M-context tag; premium-band pressure colors the bar.
if is_1m_model; then
    model_text="${model_text}$(build_1m_tag)"
fi

# Render at a real 0% too (empty bar), not just >0: after /compact the CLI
# reports used_percentage=0 for the reset window, and hiding the bar there
# read as "statusline didn't refresh" — the visible snap to [░░░░░░0%] is the
# refresh. Absent data (ctx_pct empty, no transcript) still renders nothing.
if [ -n "$context_pct" ] && [ "$context_pct" -ge 0 ] 2>/dev/null; then
    if [ $context_pct -ge 100 ]; then
        bar_color='\033[0;31m'
    elif [ $context_pct -ge 85 ]; then
        bar_color='\033[0;33m'
    else
        bar_color='\033[0;32m'
    fi

    # Premium pricing band (1M models, >200k tokens) escalates the bar color:
    # the bar % alone looks calm (320k = 32%) while every request in the band
    # bills at the premium input rate. Yellow in the band, red past 800k.
    if is_1m_model; then
        band=$(premium_band_level)
        if [ "$band" = "2" ]; then
            bar_color='\033[0;31m'
        elif [ "$band" = "1" ] && [ "$bar_color" = '\033[0;32m' ]; then
            bar_color='\033[0;33m'
        fi
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

    # Unified change flash: [█░░12%]+3 while filling, [░░░░0%]-58 right
    # after /compact — the drop is the interesting one.
    ctx_delta=$(delta_flash ctx "$context_pct" "$flash_state_file")
    context_info="${context_info}$(delta_flash_part "$ctx_delta" "$bar_color")"
fi

# Compact effort badge: lo / md / xh / max / ultra / auto. Lowercase keeps it
# quiet — it's secondary metadata, and (for xhigh users especially) it's on
# every render. 'high' is the default and stays hidden. Color carries the
# weight: routine levels are dim, the expensive modes (max, ultracode) render
# in the pressure color so you notice you're spending hard (see effort_color).
abbrev_effort() {
    case "$1" in
        low) echo "lo" ;;  medium) echo "md" ;;  high) echo "hi" ;;
        xhigh) echo "xh" ;;  max) echo "max" ;;
        ultracode) echo "ultra" ;;  auto) echo "auto" ;;
        *) echo "$1" ;;
    esac
}
effort_color() {
    case "$1" in
        max|ultracode) printf '%s' "$YELLOW" ;;
        *) printf '%s' "$DIM" ;;
    esac
}

model_suffix=""
# Attach the effort/fast tag directly when the model already ends in a ']'
# bracket (e.g. fabl5[1m]) — the bracket is the visual separator, so
# fabl5[1m]XH reads clean. Otherwise keep a space (opus4.8 XH).
suffix_sep=" "
[[ "$model_text" == *"]" ]] && suffix_sep=""
if [ "$fast_mode" = "true" ]; then
    model_suffix="${suffix_sep}${DIM}fast${RESET}"
elif [ -n "$effort_level" ] && [ "$effort_level" != "high" ]; then
    model_suffix="${suffix_sep}$(effort_color "$effort_level")$(abbrev_effort "$effort_level")${RESET}"
fi

cache_indicator=""
if [ "$cache_display_mode" != "off" ] && { [ -n "$cache_read_tokens" ] || [ -n "$cache_creation_tokens" ]; }; then
    cache_state_file="$CLAUDE_CACHE_DIR/${stdin_session_id:-global}_cache_health"
    cache_ttl_class=$(infer_cache_ttl_class "$cache_creation_1h_tokens" "$cache_creation_5m_tokens")
    cache_health=$(get_cache_health "$cache_read_tokens" "$cache_creation_tokens" "$uncached_input_tokens" "$cache_state_file" "$cache_ttl_class" "$cache_creation_1h_tokens" "$cache_creation_5m_tokens")
    debug_log "CACHE HEALTH: state=$cache_health read=$cache_read_tokens creation=$cache_creation_tokens uncached=$uncached_input_tokens ttl=$cache_ttl_class"
    cache_indicator_text=$(build_cache_indicator "$cache_health" "$cache_display_mode")
    [ -n "$cache_indicator_text" ] && cache_indicator=" ${cache_indicator_text}"
fi

model_component="${model_color}${model_text}${RESET}${model_suffix}${context_info}${cache_indicator}"
activity_component=""
time_component=""
cost_component=""
context_component=""

# Numeric gates (not string `!= "0"`): empty/malformed stdin leaves these unset,
# and "" != "0" is true — which printed fake +/- , 0m and $0. Default to 0 and
# compare numerically; the `2>/dev/null` swallows non-numeric input as false.
if [ "${lines_added:-0}" -gt 0 ] 2>/dev/null && [ "${lines_removed:-0}" -gt 0 ] 2>/dev/null; then
    activity_component="${DIM_GREEN}+${lines_added}${RESET}${DIM}/${DIM_RED}-${lines_removed}${RESET}"
elif [ "${lines_added:-0}" -gt 0 ] 2>/dev/null; then
    activity_component="${DIM_GREEN}+${lines_added}${RESET}"
elif [ "${lines_removed:-0}" -gt 0 ] 2>/dev/null; then
    activity_component="${DIM_RED}-${lines_removed}${RESET}"
fi

if [ "${api_duration_ms:-0}" -gt 0 ] 2>/dev/null; then
    time_text=$(format_duration "$api_duration_ms")
    time_component="${DIM}${time_text}${RESET}"
fi

# Render cost only when it rounds to >= $0.01. A string blocklist ("0"/"0.00")
# let 0.0 and sub-cent values through as "$0". `-v` keeps the (untrusted) value
# as awk data, never program text.
if awk -v c="${cost_usd:-0}" 'BEGIN{exit !((c+0)>=0.005)}' 2>/dev/null; then
    cost_formatted=$(printf "%.2f" "$cost_usd" | sed 's/\.00$//')
    cost_component="${DIM}\$${cost_formatted}${RESET}"
    # Change flash in cents: $7.53+.12 (dollars only when the jump is >= $1).
    cost_cents=$(awk -v c="${cost_usd:-0}" 'BEGIN{printf "%d", (c*100)+0.5}' 2>/dev/null)
    cost_delta=$(delta_flash cost "$cost_cents" "$flash_state_file")
    if [ "${cost_delta:-0}" -ne 0 ] 2>/dev/null; then
        cost_sign="+"
        [ "$cost_delta" -lt 0 ] && { cost_sign="-"; cost_delta=$((-cost_delta)); }
        if [ "$cost_delta" -ge 100 ]; then
            cost_delta_text=$(printf '%s%d.%02d' "$cost_sign" $((cost_delta / 100)) $((cost_delta % 100)))
        else
            cost_delta_text=$(printf '%s.%02d' "$cost_sign" "$cost_delta")
        fi
        cost_component="${cost_component}${DIM}${REVERSE}${cost_delta_text}${NO_REVERSE}${RESET}"
    fi
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
    # Account-scoped: one shared usage.cache serves all concurrent sessions.
    cache_file="$CLAUDE_ACCOUNT_DIR/usage.cache"
    lock_file="$CLAUDE_ACCOUNT_DIR/usage.lock"
    err_file="$CLAUDE_ACCOUNT_DIR/usage.err"
    # Per-session bump state: the "+N" flash compares against what THIS
    # statusline last rendered (same lifecycle as _cache_health).
    quota_state_file="$CLAUDE_CACHE_DIR/${stdin_session_id:-global}_quota_seen"

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

    # Respect the escalating error cooldown
    if [ "$should_fetch" = true ] && [ "$(fetch_error_remaining "$err_file")" -gt 0 ] 2>/dev/null; then
        should_fetch=false
    fi

    # STATUSLINE_NO_FETCH: render purely from cache/stdin, never spawn a
    # network fetch. The test harness exports it so integration tests don't
    # fire real API calls (or race teardown with a background fetch).
    [ -n "${STATUSLINE_NO_FETCH:-}" ] && should_fetch=false

    if [ "$should_fetch" = true ]; then
        reap_stale_lock "$lock_file" 15
        [ ! -f "$lock_file" ] && (fetch_usage_for_session "$session_id" >/dev/null 2>&1 &)
    fi

    if [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)

        # Prefer the CLI's fresh stdin rate_limits over the cached 5h/7d.
        # Claude Code passes current-plan, current-window numbers on every
        # render, so overlaying them self-heals plan upgrades, window resets,
        # and a frozen/stale cache. extra_usage and model breakdowns (which
        # stdin does not carry) still come from the cache.
        if [ -n "$rl_five_pct" ] || [ -n "$rl_seven_pct" ]; then
            merged=$(merge_stdin_rate_limits "$usage_data" "$rl_five_pct" "$rl_five_reset" "$rl_seven_pct" "$rl_seven_reset")
            [ -n "$merged" ] && usage_data="$merged"
            [ -n "$rl_five_pct" ] && five_int=$(printf '%.0f' "$rl_five_pct" 2>/dev/null || echo "$five_int")
            [ -n "$rl_seven_pct" ] && seven_int_cache=$(printf '%.0f' "$rl_seven_pct" 2>/dev/null || echo "$seven_int_cache")
        fi

        quota_display=$(build_usage_display "$usage_data" "$user_tier" "$quota_state_file")
        [ -n "$quota_display" ] && quota_component="$quota_display"

        # Model-scoped weekly quota hugs the model+context block (it's a
        # property of the model this session runs, not of the 5h/7d cluster).
        scoped_display=$(build_scoped_quota_display "$usage_data" "${model_id:-$model_display}" "$flash_state_file")
        [ -n "$scoped_display" ] && model_component="${model_component} ${scoped_display}"

        if [ -n "$quota_component" ]; then
            if [ -f "$lock_file" ]; then
                quota_component="${quota_component}${DIM}~${RESET}"
            elif [ -f "$err_file" ]; then
                quota_component="${quota_component}${DIM_RED}$(fetch_error_badge "$err_file")${RESET}"
            fi
        fi

        extra_usage_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null || echo false)
        prepaid_data=""
        if [ "$extra_usage_enabled" = "true" ]; then
            org_uuid=$(get_cached_org_uuid)
            prepaid_cache="$CLAUDE_ACCOUNT_DIR/prepaid_credits.cache"
            prepaid_lock="$CLAUDE_ACCOUNT_DIR/prepaid_credits.lock"
            prepaid_err="$CLAUDE_ACCOUNT_DIR/prepaid_credits.err"
            should_fetch_prepaid=false

            if [ -n "$org_uuid" ]; then
                if [ ! -f "$prepaid_cache" ]; then
                    should_fetch_prepaid=true
                else
                    prepaid_fetched_at=$(jq -r '.fetched_at // 0' "$prepaid_cache" 2>/dev/null || echo 0)
                    prepaid_age=$(($(date +%s) - prepaid_fetched_at))
                    [ "$prepaid_age" -ge 300 ] && should_fetch_prepaid=true
                fi

                if [ "$should_fetch_prepaid" = true ] && [ "$(fetch_error_remaining "$prepaid_err")" -gt 0 ] 2>/dev/null; then
                    should_fetch_prepaid=false
                fi
                [ -n "${STATUSLINE_NO_FETCH:-}" ] && should_fetch_prepaid=false

                if [ "$should_fetch_prepaid" = true ]; then
                    reap_stale_lock "$prepaid_lock" 30
                    [ ! -f "$prepaid_lock" ] && (fetch_prepaid_balance "$org_uuid" >/dev/null 2>&1 &)
                fi

                [ -f "$prepaid_cache" ] && prepaid_data=$(cat "$prepaid_cache" 2>/dev/null)
            fi
        fi

        extra_display=$(build_extra_usage_display "$usage_data" "$prepaid_data")
        if [ -n "$extra_display" ]; then
            if [ -f "$prepaid_lock" ]; then
                extra_display="${extra_display}${DIM}~${RESET}"
            elif [ -f "$prepaid_err" ]; then
                extra_display="${extra_display}${DIM_RED}$(fetch_error_badge "$prepaid_err")${RESET}"
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
        quota_display=$(build_usage_display "$stdin_usage" "$user_tier" "$quota_state_file")
        [ -n "$quota_display" ] && quota_component="$quota_display"
        five_int=$(printf '%.0f' "${rl_five_pct:-0}" 2>/dev/null || echo 0)
        seven_int_cache=$(printf '%.0f' "${rl_seven_pct:-0}" 2>/dev/null || echo 0)
        # No cache yet, but stdin still carries the windows — enough for the
        # advisor's projections.
        usage_data="$stdin_usage"
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

# API-key / custom-endpoint sessions skip the OAuth block above, but an
# account tag is exactly what tells such sessions apart — chip from the
# tag alone, no tier.
if [ -z "$user_component" ] && [ -n "$ACCOUNT_TAG" ]; then
    user_component=$(build_user_info "")
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
    local path_part="${DIM}${display_path}${RESET}${git_info}"
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

# Advisor row: a second stdout line renders as its own row in Claude Code's
# status area, and printing nothing produces no row — so a quiet advisor
# costs zero height. Single-hue by design, which keeps truncation honest.
# Right-aligned to the same anchor the stats cluster ends at in format_output
# (term_width - 5), so the advice sits directly beneath the usage badges it
# interprets, stable across widths and message lengths; when the stats sit
# left (right-left alignment) the advisor stays left with them.
if [ "$advisor_display_mode" != "off" ] && [ -n "${usage_data:-}" ]; then
    advisor_line=$(build_advisor_line "$usage_data" "$advisor_display_mode" "${model_id:-$model_display}")
    if [ -n "$advisor_line" ]; then
        advisor_plain=$(printf '%b' "$advisor_line" | sed 's/\x1b\[[0-9;]*m//g')
        advisor_max=$((term_width - 1))
        if [ "${#advisor_plain}" -gt "$advisor_max" ] 2>/dev/null && [ "$advisor_max" -gt 1 ]; then
            advisor_color=$(printf '%s' "$advisor_line" | grep -o '^\\033\[[0-9;]*m' | head -1)
            advisor_plain="${advisor_plain:0:$((advisor_max - 1))}…"
            advisor_line="${advisor_color}${advisor_plain}${RESET}"
        fi
        advisor_pad=0
        if [ "$alignment" != "right-left" ]; then
            advisor_pad=$((term_width - 5 - ${#advisor_plain}))
            [ "$advisor_pad" -gt 0 ] 2>/dev/null || advisor_pad=0
        fi
        debug_log "ADVISOR: $advisor_plain"
        printf '%*s%b\n' "$advisor_pad" "" "$advisor_line"
    fi
fi

if [ "$test_mode" = true ] && [ -n "$temp_transcript" ] && [ -f "$temp_transcript" ]; then
    rm -f "$temp_transcript"
fi
