#!/bin/bash
# Claude Code statusline
# Usage: statusline.sh [report|check|session-summary|week] [--style STYLE] [--order ORDER] [--theme THEME] [--path-display TYPE] [--alignment TYPE] [--extra MODE] [--cache MODE] [--advisor MODE] [--week MODE] [--notice MODE] [--deadman MODE] [--test JSON] [--debug]
# Themes: minimal, compact, detailed, developer, manager
# Styles: single-block, unicode-blocks, bracketed-bars, filled-dots, square-blocks, line-segments, ascii-bars, percent-only, fraction-display
# Extra modes: auto (default, shows when quota runs out or extra >= 50%), always, on-limit, off
# Advisor modes: auto (default, second line under quota pressure or expiring surplus), always (adds weekly budget when calm), off

# Every width below is a `${#var}` count. Under a C/POSIX locale bash counts
# BYTES, so `█░░░░░` is 18 wide, `≡` 3, `—` 3 — line 1 gets padded short and
# every anchored row lands off its edge. Claude Code passes the user's env,
# which is UTF-8 on most machines but not all (launchd-spawned terminals,
# minimal containers). Pin a UTF-8 locale for the run when the ambient one
# does not count characters.
_probe="█"
if [ "${#_probe}" -ne 1 ]; then
    for _loc in C.UTF-8 en_US.UTF-8; do
        if LC_ALL="$_loc" bash -c '[ "${#1}" -eq 1 ]' _ "$_probe" 2>/dev/null; then
            export LC_ALL="$_loc"
            break
        fi
    done
fi
unset _probe _loc

progress_bar_style="unicode-blocks"
stat_order="activity,time,cost,model,user,quota,extra"
path_display="project" # project, cwd, full, relative
alignment="left-right" # left-right, right-left, center
theme=""
advisor_display_mode="auto" # auto, always, off
notice_display_mode="${STATUSLINE_NOTICE:-auto}" # auto, off — the fading row 3
week_display_mode="auto"    # auto, always, off — the 7d window ledger row
# Context limit: auto-detected from model.id. 1M when the family ships 1M by
# default (e.g. fable — CLI strips its [1m] suffix since 2.1.173) OR when the id
# carries an explicit [1m] opt-in suffix (e.g. opus/sonnet); otherwise 200k.
# CLAUDE_CONTEXT_LIMIT env override still honored for manual tuning
context_limit_override="${CLAUDE_CONTEXT_LIMIT:-}"
extra_display_mode="auto" # auto, always, on-limit, off
cache_display_mode="auto" # auto, always, off
deadman_display_mode="${STATUSLINE_DEADMAN:-auto}" # auto, off — dead man's switch chip
test_mode=false
test_data=""
debug_mode=false
subcommand=""               # report (see run_usage_report); dispatched late,
                            # after every function it needs is defined
report_days=""

# Auto-display thresholds. The 5h countdown itself is always visible (see
# build_usage_display); these gate the recovery color and extra visibility.
FIVE_HOUR_RECOVERY_SECS=1800     # recovery color when reset <= 30min
SEVEN_DAY_RECOVERY_SECS=43200    # recovery color when reset <= 12h
QUOTA_BUMP_NOTICE_SECS=60        # how long a quota "+N" bump flash stays up
SEVEN_DAY_WINDOW_SECS=604800     # weekly quota window (fixed 7d) for pace math
SEVEN_DAY_YOUNG_SECS=86400       # a 7d projection needs a day of THIS window's
                                 # own evidence. Learned or linear, every pace
                                 # read before that is last week's story told
                                 # about a window that has barely started —
                                 # and the trailing-24h blend is measuring a
                                 # day that lies outside the window entirely
EXTRA_AUTO_UTIL_PCT=50           # show extra when its own utilization >= 50%
CACHE_BREAK_MIN_TOKENS=2000      # ignore cache drops below this (noise)
CACHE_BREAK_DROP_PCT=5           # cache read must drop >5% to count as break
CACHE_HEAVY_TOKENS=200000        # break badge turns bold-red past this: the
                                 # >200k premium-band prefix, an expensive rewrite
ADVISOR_FLEET_FRESH_SECS=3600    # sibling account cache older than this is unknown
ADVISOR_FLEET_FREE_PCT=40        # sibling counts as "free" at or under this 5h%
ADVISOR_EXPIRY_HORIZON_SECS=86400 # 7d surplus clause: inside the last day of the week
ADVISOR_SURPLUS_MIN_PCT=30       # unused weekly % that counts as expiring waste
ADVISOR_UNDERUSE_END_PCT=60      # projected end-of-week <= this => underuse advice
NOTICE_FLASH_SECS=90             # a new notice explains itself on row 3 this long
NOTICE_FLASH_MIN_CHARS=16        # ...and only if truncation left a sentence, not a stub
NOTICE_REBASE_SECS=1800          # an out-of-band 7d reset stays newsworthy this long
NOTICE_REBASE_DROP_PCT=10        # 7d falling this much inside one window = re-based
NOTICE_TAIL_SECS=3600            # "this 5h window is closing" horizon
NOTICE_TAIL_MIN_UNUSED=20        # ...and only with this much of it still unspent
NOTICE_SCOPE_MIN_PCT=70          # model-scoped weekly this deep is worth steering around
NOTICE_SCOPE_LEAD_PCT=20         # ...once it leads the account 7d by this much
ADVISOR_UNDERUSE_MIN_5H=25       # underuse advice only in an engaged session (5h >= this)
# Cache-badge marker. Triple bar (U+2261 IDENTICAL TO): three stacked
# horizontal lines read as layered cache tiers. Single-column text glyph, so
# the padding math is unaffected. Swap for ☰ (U+2630) or Ξ (U+039E) if a
# font tofus it.
CACHE_GLYPH="${CACHE_GLYPH:-≡}"

# Multiplication sign for the ledger rows' two factors: the folded-future
# count (`...▯(✕12)`) and the pace (`0.6✕`). NOT × (U+00D7) — that glyph is
# already a strip cell, the one the pool will not cover, so reusing it would
# print `...×(×12)` and make an operator look like a reading. U+2715 is the
# lighter mark of the pair by design: cells are the ink, the operator is
# punctuation. eaw=N and not an emoji, so it stays one column and the padding
# math holds — ╳ (U+2573) is ambiguous-width (double under a CJK locale) and
# ✖ (U+2716) is Emoji=Yes (colour-font fallback); either would overhang row 2.
MULT_GLYPH="${MULT_GLYPH:-✕}"

# The ledger strips' baseline: a cell that ran and cost nothing. ▁ (U+2581
# LOWER ONE EIGHTH BLOCK) is the shortest bar in the same Block Elements run
# as ▂▃▄▅▆▇█, so the zero line and the bars share one font, one advance width
# and one baseline. The old baseline was ˍ (U+02CD MODIFIER LETTER LOW
# MACRON): a spacing modifier LETTER, resolved through the text font while
# the bars fall back to the box-drawing face — visibly a different height and
# width mid-strip. Burn therefore starts one rung up, at ▂; the ladder above
# ▅ is untouched, so a fully burned window still reads the same.
LEDGER_BASE_GLYPH="${LEDGER_BASE_GLYPH:-▁}"

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
    report | check | session-summary | week)
        subcommand="$1"
        shift
        ;;
    --days)
        report_days="$2"
        shift 2
        ;;
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
    --week)
        week_display_mode="$2"
        shift 2
        ;;
    --notice)
        notice_display_mode="$2"
        shift 2
        ;;
    --deadman)
        deadman_display_mode="$2"
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
        week_display_mode="off"
        notice_display_mode="off"
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

if [ -n "$subcommand" ]; then
    # Subcommands take no stdin; the shared parse below still runs, so give
    # it an empty object and let the late dispatch (after all function
    # definitions) do the real work.
    input='{}'
elif [ "$test_mode" = true ]; then
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
    @sh "ctx_total_in=\(.context_window.total_input_tokens // "")",
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

# Terminal width, best signal first. The statusline runs with stdout on a
# pipe, where bare `tput cols` answers a flat 80 no matter how wide the real
# terminal is — the controlling tty (when we still have one) and an inherited
# COLUMNS both beat it. The advisor row additionally anchors on line 1's
# actual rendered width (see format_output), so a wrong width degrades the
# gap, never the alignment between the two rows.
term_width=""
term_width_trusted=1  # tty or COLUMNS (Claude Code sets it): a real edge
if [ -e /dev/tty ]; then
    term_width=$({ stty size </dev/tty; } 2>/dev/null | awk '{print $2}')
fi
if ! [ "$term_width" -gt 0 ] 2>/dev/null; then
    term_width="${COLUMNS:-}"
fi
if ! [ "$term_width" -gt 0 ] 2>/dev/null; then
    term_width=$(tput cols 2>/dev/null || echo 80)
    term_width_trusted=0  # a guess (a pipe answers 80): never clamp to it
fi
debug_log "TERM WIDTH: $term_width"

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
BOLD='\033[1m'
NO_BOLD='\033[22m'      # clears bold AND faint: re-state the voice colour after it
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

# Claude Code hands 5h/7d (`rate_limits`) to the statusline on every render.
# Those are free observations — the same numbers the API fetch logs, at the
# session's own cadence, with no request behind them. Log one whenever the
# pair changes (account-wide dedupe, >= STDIN_LOG_MIN_SECS apart), shaped
# like a fetched sample (`source: "stdin"`) so the ledger, the forecast and
# ccpace read them as history without knowing the difference. Never rebuilds
# the weekday profile: that stays on the fetch path.
STDIN_LOG_MIN_SECS=60
session_telemetry_json() {
    [ -n "${cost_usd:-}" ] || [ -n "${ctx_total_in:-}" ] || return 0
    # The project is the one dimension a breakdown by session cannot recover
    # later: the transcript knows tokens, the quota log knows percent, and
    # neither knows which repo the week went to. Basename only — the log is
    # owner-readable but a full path is a machine fingerprint the store has
    # no use for.
    local proj="${project_dir:-${cwd:-}}"
    proj="${proj%/}"; proj="${proj##*/}"
    jq -nc --arg cost "${cost_usd:-}" --arg dur "${duration_ms:-}" \
        --arg api "${api_duration_ms:-}" --arg la "${lines_added:-}" \
        --arg ld "${lines_removed:-}" --arg cin "${ctx_total_in:-}" \
        --arg csz "${ctx_size:-}" --arg eff "${effort_level:-}" \
        --arg fast "${fast_mode:-}" --arg cli "${cli_version:-}" \
        --arg proj "$proj" '
        def num: tonumber? // null;
        {cost_usd: ($cost|num), dur_ms: ($dur|num), api_ms: ($api|num),
         lines_add: ($la|num), lines_del: ($ld|num),
         ctx_in: ($cin|num), ctx_size: ($csz|num),
         effort: (if $eff == "" then null else $eff end),
         fast: ($fast == "true"),
         cli: (if $cli == "" then null else $cli end),
         project: (if $proj == "" then null else $proj end)}' 2>/dev/null
}

log_stdin_snapshot() {
    local session_id="$1" fp="$2" fr="$3" sp="$4" sr="$5"
    [ -n "$fp" ] && [ -n "$fr" ] && [ -n "$sp" ] || return 0
    local now seen_file last_pair last_at
    now=$(date +%s)
    seen_file="$CLAUDE_ACCOUNT_DIR/stdin_seen"
    last_pair=""; last_at=0
    [ -f "$seen_file" ] && read -r last_pair last_at <"$seen_file" 2>/dev/null
    local pair
    pair=$(printf '%.0f|%.0f' "$fp" "$sp" 2>/dev/null) || return 0
    [ "$pair" = "$last_pair" ] && return 0
    # rate_limits are per SESSION: an idle session keeps reporting the numbers
    # it last saw, so a stdin pair can sit behind the account's real state
    # (8% between 21% and 23%). Inside a window utilization only climbs;
    # log a stdin pair only when it would win the display merge — same
    # window and not below the cache, or a newer window.
    # An EXPIRED window is never news. A session that sat idle across a
    # boundary — or a hand-piped fixture — reports the window it last saw;
    # logged, that pair reads as a 49-point drop and the next real sample
    # re-climbs it, so every learner counts the same burn twice. This guard
    # needs no cache: a window whose reset is already behind us cannot be
    # the current one. 300 s of slack covers clock skew at the boundary.
    local fe_now se_now
    fe_now=$(_epoch_from_ts "$fr")
    [ -n "$fe_now" ] && [ $(( fe_now - now )) -gt -300 ] 2>/dev/null || return 0
    if [ -n "$sr" ]; then
        se_now=$(_epoch_from_ts "$sr")
        [ -n "$se_now" ] && [ $(( se_now - now )) -gt -300 ] 2>/dev/null || return 0
    fi

    local uc="$CLAUDE_ACCOUNT_DIR/usage.cache"
    if [ -f "$uc" ]; then
        local c5p c5r c7p c7r fe0 ce0
        eval "$(jq -r '@sh "c5p=\(.five_hour.utilization // "")", @sh "c5r=\(.five_hour.resets_at // "")",
                       @sh "c7p=\(.seven_day.utilization // "")", @sh "c7r=\(.seven_day.resets_at // "")"' "$uc" 2>/dev/null)"
        fe0=$(_epoch_from_ts "$fr"); ce0=$(_epoch_from_ts "$c5r")
        if [ -n "$c5p" ] && [ -n "$fe0" ] && [ -n "$ce0" ]; then
            # older window than the cache: stale by construction, drop it
            [ $(( ce0 - fe0 )) -ge 300 ] 2>/dev/null && return 0
            if [ $(( fe0 - ce0 )) -lt 300 ] 2>/dev/null \
                && awk -v a="$fp" -v b="$c5p" 'BEGIN{exit !((a+0) < (b+0))}'; then
                return 0
            fi
        fi
        if [ -n "$c7p" ] && [ -n "$sr" ] && [ -n "$c7r" ]; then
            local se0 ce7
            se0=$(_epoch_from_ts "$sr"); ce7=$(_epoch_from_ts "$c7r")
            if [ -n "$se0" ] && [ -n "$ce7" ]; then
                [ $(( ce7 - se0 )) -ge 300 ] 2>/dev/null && return 0
                if [ $(( se0 - ce7 )) -lt 300 ] 2>/dev/null \
                    && awk -v a="$sp" -v b="$c7p" 'BEGIN{exit !((a+0) < (b+0))}'; then
                    return 0
                fi
            fi
        fi
    fi
    [ $((now - ${last_at:-0})) -lt "$STDIN_LOG_MIN_SECS" ] 2>/dev/null && return 0
    local fe se fiso siso
    fe=$(_epoch_from_ts "$fr"); [ -n "$fe" ] || return 0
    fiso=$(TZ=UTC _fmt_epoch "$fe" '%Y-%m-%dT%H:%M:%SZ')
    siso=""
    if [ -n "$sr" ]; then
        se=$(_epoch_from_ts "$sr"); [ -n "$se" ] && siso=$(TZ=UTC _fmt_epoch "$se" '%Y-%m-%dT%H:%M:%SZ')
    fi
    local uuid="" email=""
    if [ -f "$CLAUDE_ACCOUNT_DIR/profile.cache" ]; then
        eval "$(jq -r '@sh "uuid=\(.account.uuid // "")", @sh "email=\(.account.email // "")"' \
            "$CLAUDE_ACCOUNT_DIR/profile.cache" 2>/dev/null)"
    fi
    mkdir -p "$CLAUDE_ACCOUNT_DIR"
    local usage_log="$CLAUDE_ACCOUNT_DIR/usage.jsonl"
    rotate_usage_log "$usage_log"
    local sess=""
    sess=$(session_telemetry_json) || true; [ -n "$sess" ] || sess=null
    jq -nc --arg sid "$session_id" --argjson ts "$now" --arg model "${model_id:-}" \
        --argjson fp "$fp" --arg fr "$fiso" --argjson sp "$sp" --arg sr "$siso" \
        --arg uuid "$uuid" --arg email "$email" --argjson sess "$sess" \
        '{type:"usage", source:"stdin", session_id:$sid, timestamp:$ts,
          user:{email:$email, uuid:$uuid},
          five_hour:{utilization:$fp, resets_at:$fr},
          seven_day:{utilization:$sp, resets_at:(if $sr == "" then null else $sr end)},
          model:(if $model == "" then null else $model end),
          session:$sess}' >>"$usage_log" 2>/dev/null \
        && printf '%s %s\n' "$pair" "$now" >"$seen_file.tmp.$$" && mv -f "$seen_file.tmp.$$" "$seen_file"
    debug_log "log_stdin_snapshot: logged 5h=$fp 7d=$sp"
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

    # Calibration seed: the learned walk's end-of-week projection AT SAMPLE
    # TIME. When this window later closes, `report` can compare what we
    # predicted against what actually happened — the forecast's accuracy
    # becomes measurable instead of assumed. Empty until the profile is warm.
    local predicted_end="" _s_util _s_secs
    _s_util=$(echo "$usage_data" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
    if [ -n "$_s_util" ]; then
        _s_secs=$(get_reset_seconds "$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)")
        [ -n "$_s_secs" ] && read -r _ predicted_end <<<"$(_seven_day_walk "$_s_util" "$_s_secs")"
    fi

    local sess=""
    sess=$(session_telemetry_json) || true; [ -n "$sess" ] || sess=null

    echo "$usage_data" | jq -c \
        --arg sid "$session_id" \
        --arg ts "$(date +%s)" \
        --arg model "${model_id:-}" \
        --arg pend "${predicted_end:-}" \
        --argjson sess "$sess" \
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
            extra_usage:.extra_usage,
            limits:(.limits // []),
            model:($model | if . == "" then null else . end),
            predicted_end:($pend | if . == "" then null else tonumber end),
            session:$sess
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

    # The newest record that actually carries a window, not just the newest
    # line: session_start/session_end markers have no .five_hour, and a
    # bounded tail keeps this off the whole-log path.
    local last_entry
    last_entry=$(tail -n 200 "$usage_log" 2>/dev/null \
        | jq -c 'select((.five_hour.resets_at // .data.five_hour.resets_at // "") != "")' 2>/dev/null | tail -1)
    if [ -z "$last_entry" ]; then
        _emit_session_start
        return 0
    fi

    local last_five_hour_reset last_session_id
    last_five_hour_reset=$(echo "$last_entry" | jq -r '.five_hour.resets_at // .data.five_hour.resets_at // empty' 2>/dev/null)
    last_session_id=$(echo "$last_entry" | jq -r '.session_id // empty' 2>/dev/null)

    # Compare WINDOWS, not strings. resets_at carries microseconds and
    # wobbles per fetch (06:00:00.515434 vs 06:00:00.087190 — one window,
    # two strings), and 05:59:59/06:00:00 straddle the same boundary. The
    # raw-string compare this replaced fired on nearly every fetch and wrote
    # a session_end/session_start pair each time: 26% of the log was markers
    # for windows that never rolled. A boundary is a window that is NEWER
    # by more than the jitter — a stale sample never opens one.
    local cur_e last_e
    cur_e=$(_epoch_from_ts "$current_five_hour_reset")
    last_e=$(_epoch_from_ts "$last_five_hour_reset")
    [ -n "$cur_e" ] && [ -n "$last_e" ] || return 0
    [ $(( cur_e - last_e )) -ge 300 ] 2>/dev/null || return 0

    if [ -n "$last_session_id" ] && [ "$last_session_id" != "$session_id" ]; then
        jq -n -c --arg sid "$last_session_id" --arg ts "$(date +%s)" \
            '{type:"session_end",session_id:$sid,timestamp:($ts|tonumber)}' \
            >>"$usage_log" 2>/dev/null
    fi
    _emit_session_start
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

# API fetch floor while stdin carries rate_limits (5h/7d come free then)
STDIN_RL_FETCH_TTL=120

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
# (no deadline, the noisy first ~8h, or a window younger than
# SEVEN_DAY_YOUNG_SECS — two hours into a fresh week, 2% used extrapolates to
# a 98h runway and calls the week at risk on nothing). A genuinely burned
# young window still goes red on its own percentage; only the pace math waits.
# $2 drives elapsed; $3 the deadline.
#   $1 used%   $2 seconds_left   $3 effective deadline secs (optional)
seven_day_pace() {
    local used; used=$(printf '%.0f' "$1" 2>/dev/null || echo 0)
    local secs_left="${2:-}" deadline="${3:-}"
    [ -z "$deadline" ] && deadline="$secs_left"
    local elapsed; elapsed=$(seven_day_elapsed "$secs_left")
    if [ -n "$elapsed" ] && [ "$elapsed" -lt "$SEVEN_DAY_YOUNG_SECS" ] 2>/dev/null; then
        elapsed=""
    fi
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

# Every store this account may have been written to. A directory is where a
# sample LANDED, not who it belongs to: the same uuid reaches the root when
# an untagged statusline fetched, accounts/<tag>/ when a deva-tagged
# container did — and a fresh tag starts an EMPTY directory for an account
# with ten months of history one level up, so it renders "still learning"
# for two weeks. Measured on one machine: 301 days at the root, 28 in the
# tagged dir, same uuid. Aggregating readers (forecast, ledger, report)
# therefore read the union — root + every accounts/*/ — and partition by
# user.uuid (state-dir contract v2, "never trust placement"); the
# per-directory scope was the thing that fragmented history to begin with.
# The union is safe for THIS data because every quantity is envelope-based:
# the same window seen from two containers takes a max, never a sum.
# Without a data root (function-level tests) it is just the account dir.
# Prints paths, `.1` backups first, one per line.
usage_corpus_files() {
    local base f seen=" "
    for base in "${CLAUDE_DATA_DIR:-}" "${CLAUDE_DATA_DIR:+$CLAUDE_DATA_DIR/accounts/}"*/ "$CLAUDE_ACCOUNT_DIR"; do
        base="${base%/}"
        [ -n "$base" ] && [ -d "$base" ] || continue
        case "$seen" in *" $base "*) continue ;; esac
        seen="$seen$base "
        for f in "$base/usage.jsonl.1" "$base/usage.jsonl"; do
            [ -f "$f" ] && printf '%s\n' "$f"
        done
    done
    return 0
}
cat_usage_corpus() {
    local f
    usage_corpus_files | while IFS= read -r f; do cat "$f" 2>/dev/null; done
    return 0
}
# mtime:size of every corpus file, one token — the cache key a derived file
# (week.cache) uses to notice a sample landing in ANY store.
usage_corpus_sig() {
    local f sig=""
    while IFS= read -r f; do
        sig="$sig$(stat -c %Y:%s "$f" 2>/dev/null || stat -f %m:%z "$f" 2>/dev/null || echo 0),"
    done <<<"$(usage_corpus_files)"
    printf '%s' "${sig:-0}"
}

# forecast.cache contract version. Bump when the MODEL changes (how burn is
# counted, what a profile value means) — not when a field is added, which
# readers already tolerate via `// -1`.
#   2  envelope burn + the full key set (pct_per_window, scoped_*, cost)
#   -  absent/lower: an unversioned or partial cache. Rebuild on sight.
# `~/.claude/statusline/` is a shared store (docs/api/state-dir.md) and this
# file is the one derived cache more than one tool wants to write. The
# version is what lets a reader tell "computed an hour ago by a writer that
# counts burn the way I do" from "recently overwritten by one that does
# not", without either tool having to know the other exists.
FORECAST_SCHEMA=2

# An hour whose learned burn multiplier sits below this is a REST hour: week
# after week, this account has burned a tenth of a uniform hour in it. Part of
# the cache contract (docs/api/state-dir.md) rather than a local threshold —
# ccpace divides the same surplus by the same awake windows, and two tools
# that disagree about which hours are spendable disagree about the ration.
REST_MULT_MAX=0.25

# The account 7d pool and the model-scoped weekly pool drain at different
# speeds toward the SAME wall. Both counters are cumulative from one reset
# instant, so their live ratio IS this week's mix — `scope / seven` is
# scoped points per account point — and what the account cannot reach before
# the wall arrives strands in the scoped pool. These are READING RULES, not
# cache fields: nothing is stored, the numbers are computed from usage.cache
# on every frame. They live here beside the cache contract because ccpace
# says the same thing from the same numbers (docs/api/state-dir.md), and two
# tools that disagree about what strands disagree about the week.
SCOPE_STRAND_MIN_PCT=10          # scoped points the mix strands before it is worth a row
SCOPE_MIX_MIN_7D=60              # ...and only once the account's own end is in sight
SCOPE_MIX_MIN_SCOPE=5            # a model untouched this week is the underuse voice's job
SCOPE_SAME_WALL_SEC=120          # resets this close are one wall; further apart, no ratio
# A 5h ledger slot is a NIGHT when under half of it is waking time (awake
# seconds < 9000, hours with mult >= REST_MULT_MAX). Half is the break-even a
# reader can hold in their head: more asleep than awake and the slot is
# capacity you will not reach. Shared with ccpace (docs/api/state-dir.md) so
# both ledgers dim the same cells; the strip applies the same half-the-cell
# rule to its 1h cells, where the threshold is 1800.
REST_SLOT_AWAKE_MIN_SECS=9000

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
#   { schema, computed_at, days_history, recent_24h, recent_48h,
#     pct_per_window, weekday_profile: {"0":sun.. "6":sat, unknown = -1},
#     hour_profile: {"0".."23" burn multipliers, mean 1; absent = unlearned},
#     scoped_name, scoped_recent_24h, scoped_profile, cost }
# Daily burn is the rise of a MONOTONE ENVELOPE, never the sum of raw
# positive deltas (see seven_env below and docs/api/state-dir.md).
build_seven_day_profile() {
    local out="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    local corpus_files
    corpus_files=$(usage_corpus_files)
    [ -n "$corpus_files" ] || return 0
    local nfiles
    nfiles=$(printf '%s\n' "$corpus_files" | grep -c .)
    local acct
    acct=$(jq -r '.account.uuid // empty' "$CLAUDE_ACCOUNT_DIR/profile.cache" 2>/dev/null)
    [ -n "$acct" ] || return 0
    # Freshness is not enough: this cache is SHARED, and an hour of trusting
    # a foreign shape is an hour of forecasting from it. A cooperating writer
    # that keeps the contract stamps its own FORECAST_SCHEMA and preserves
    # keys it does not compute; anything else — an older statusline, a tool
    # that rebuilt only the fields it knew, a truncated write — is a cache
    # this build must replace NOW, not in 59 minutes. Measured: a co-writer
    # summing raw deltas published a profile with 149%/day in it and dropped
    # pct_per_window, scoped_* and cost on the way past. The walk's
    # corrupt-profile guard caught the 149 and went silent, which is the
    # right reflex and the wrong resting state — the account had a good
    # profile ten minutes earlier and no way back to it until the hour
    # turned.
    if [ -f "$out" ]; then
        local computed schema age
        IFS=$'\t' read -r computed schema <<<"$(jq -r '[(.computed_at // 0), (.schema // 0)] | @tsv' "$out" 2>/dev/null)"
        age=$(( $(date +%s) - ${computed:-0} ))
        [ "${schema:-0}" = "$FORECAST_SCHEMA" ] && [ "$age" -lt 3600 ] 2>/dev/null && return 0
    fi
    local now tzoff_s
    now=$(date +%s)
    # ±HHMM -> signed seconds (portable; date +%z works on GNU and BSD)
    tzoff_s=$(date +%z | awk '{ s=substr($0,1,1)=="-"?-1:1; h=substr($0,2,2)+0; m=substr($0,4,2)+0; print s*(h*3600+m*60) }')
    local data
    data=$( cat_usage_corpus | jq -r --arg a "$acct" '
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
            select((.type // "usage") == "usage" and (.timestamp // null) != null)
            # Rows of other accounts and rows with no uuid are dropped —
            # and COUNTED, as X-lines the reducer tallies into the corpus
            # stamp. A uuid-less row is refused, never guessed (some carry an
            # email that would identify them; guessing identity on a log
            # that interleaves accounts is how a 9000%/day burn rate gets
            # manufactured), but a reader that discards identifiable
            # observations silently will discard more just as quietly.
            | if (.user.uuid // "") == $a then
                ([.limits[]? | select(.kind == "weekly_scoped")] | first) as $sc
                | [.timestamp, (.seven_day.utilization // ""),
                   (.five_hour.utilization // ""),
                   ((.five_hour.resets_at // "") | norm),
                   ((.seven_day.resets_at // "") | norm),
                   ($sc.percent // ""), ($sc.scope.model.display_name // ""),
                   (.session.cost_usd // ""), (.session_id // "")] | @tsv
              elif (.user.uuid // "") == "" then "X\tnouuid"
              else "X\tother" end' 2>/dev/null \
        | sort -n | awk -F'\t' -v now="$now" -v tz="$tzoff_s" -v schema="$FORECAST_SCHEMA" \
                       -v acct="$acct" -v nfiles="$nfiles" '
        # Burn is the rise of a MONOTONE ENVELOPE, not the rise of the last
        # sample. Summing raw positive deltas counts every stale dip twice:
        # measured, that read 146 points of "burn" against a real 50-point
        # week, and the walk then forecast a dry-out that was never coming.
        #
        # Two things pull a sample below the envelope, and they need
        # opposite answers:
        #   stale  a session that sat idle reports the numbers it last saw.
        #          One sample, small step back. Hold the envelope.
        #   reset  the account s counter actually went back to zero. Sticks,
        #          and it is a long fall. Re-baseline, credit nothing.
        # resets_at cannot tell them apart: an observed 7d reset (100 -> 0,
        # 2026-08-17) left resets_at untouched, so the window key is only
        # ever a one-way hint — a NEWER key is certainly a reset; an
        # unchanged one proves nothing. Hence the two-signal test below:
        # sustained (>= RESET_CONFIRM samples) AND deep (>= RESET_DROP
        # points). Both cheap, both independent, and the failure mode is a
        # bounded UNDER-count — which costs a missed warning, where the
        # over-count cost a false alarm on every render.
        # Functions, not bare rules: the ratio learner below is a separate
        # pass over the same line, and a `next` in an envelope rule would
        # silently starve it.
        function key_ok(k) { return (k != "" && k ~ /^[0-9]+$/) }
        function seven_env(ts, v, key,    d, day) {
            if (key_ok(key)) {
                if (key + 0 < swin) return                 # stale window
                if (key + 0 > swin) { swin = key + 0; env = v; lo_n = 0; env_set = 1; return }
            }
            # The first sample is a BASELINE, not burn: we are seeing where
            # the account already stood, not watching it climb there.
            if (!env_set) { env = v; env_set = 1; return }
            if (v < env) {
                lo_n++; if (lo_n == 1 || v < lo_min) lo_min = v
                if (lo_n < RESET_CONFIRM || env - lo_min < RESET_DROP) return
                env = lo_min; lo_n = 0                     # confirmed reset
            }
            lo_n = 0
            if (v <= env) return
            d = v - env; env = v; day = int((ts + tz) / 86400)
            burn[day] += d; credited = d
            # The same delta on a second axis: the LOCAL HOUR it landed in.
            # Claude Code can work at 03:00 and the human cannot, so a walk
            # that burns flat through the night puts a dry-out in the middle
            # of sleep — a false alarm at 23:00 and a missed warning at 09:00.
            hburn[day SUBSEP int(((ts + tz) % 86400) / 3600)] += d
            if (now - ts <= 86400)  r24 += d
            if (now - ts <= 172800) r48 += d
        }
        # Same envelope, same reset test, for the model-scoped weekly cap
        # (limits[] kind=weekly_scoped — Fable today). Kept per scope name so
        # a change in WHICH model is capped cannot blend two series into one
        # profile, and so a reader can tell what the profile is ABOUT.
        function scoped_env(ts, v, nm, key,    d, day) {
            sc_last = nm
            if (key_ok(key)) {
                if (key + 0 < cwin[nm]) return
                if (key + 0 > cwin[nm]) { cwin[nm] = key + 0; cenv[nm] = v; cn[nm] = 0; sset[nm] = 1; return }
            }
            if (!sset[nm]) { cenv[nm] = v; sset[nm] = 1; return }
            if (v < cenv[nm]) {
                cn[nm]++; if (cn[nm] == 1 || v < cmin[nm]) cmin[nm] = v
                if (cn[nm] < RESET_CONFIRM || cenv[nm] - cmin[nm] < RESET_DROP) return
                cenv[nm] = cmin[nm]; cn[nm] = 0
            }
            cn[nm] = 0
            if (v <= cenv[nm]) return
            d = v - cenv[nm]; cenv[nm] = v; day = int((ts + tz) / 86400)
            cburn[nm SUBSEP day] += d
            if (now - ts <= 86400) cr24[nm] += d
        }
        # Dollars. cost_usd is cumulative PER SESSION, and consecutive
        # samples come from different sessions, so the column is not a series
        # — it is many interleaved ones. Per session it only climbs, which
        # makes it the same envelope shape as a quota window with one
        # difference: a session opening at $0 has no reset to distinguish, so
        # a drop is simply a different session and the per-key envelope
        # handles it. The first sample of a session is a baseline, not spend.
        #
        # This is the join the quota API cannot make and Claude Code does not:
        # the API knows percent and no dollars (limit_dollars is null on
        # subscription), the transcripts know dollars and no percent. Only a
        # sample carrying both can price a percentage point.
        function cost_env(ts, v, sid,    d, day) {
            if (!(sid in cset)) { cost_env_v[sid] = v; cset[sid] = 1; return }
            if (v <= cost_env_v[sid]) return
            d = v - cost_env_v[sid]; cost_env_v[sid] = v
            day = int((ts + tz) / 86400)
            usd[day] += d; usd_all += d
            if (now - ts <= 86400)  u24 += d
            if (now - ts <= 604800) u7d += d
        }
        BEGIN { RESET_CONFIRM = 2; RESET_DROP = 15; swin = -1 }
        $1 == "X" { if ($2 == "nouuid") drop_nu++; else drop_other++; next }
        # The union can hold the same observation twice (a fetch logged by
        # two writers before the pool existed); sorted, repeats are adjacent.
        $0 == prev_line { next }
        {
            prev_line = $0
            nsamp++; if (oldest == "") oldest = $1
            credited = 0
            if ($2 != "") seven_env($1, $2 + 0, $5)
            if ($6 != "" && $7 != "") scoped_env($1, $6 + 0, $7, $5)
            # The price denominator must be PAIRED: only points watched by a
            # sample that also carried a dollar figure. The log predates the
            # session block by months, so dividing recent dollars by all of
            # history would price a whole week at pennies.
            if ($8 != "" && $9 != "") { burn_paired += credited; cost_env($1, $8 + 0, $9) }
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
            # Scoped weekday profile, newest capped model only, same EWMA.
            # -1 on a weekday never observed — exactly like the all-model
            # profile, so a reader cannot mistake 0 for "quiet" when it
            # means "unknown".
            for (k in cburn) {
                split(k, kp, SUBSEP)
                if (kp[1] != sc_last) continue
                age = today - kp[2]; if (age < 0) age = 0
                w = exp(-0.0495 * age)
                dw = (kp[2] + 4) % 7
                cnum[dw] += cburn[k] * w; cden[dw] += w
            }
            # The hour shape: burn SHARE per local hour, weighted by the same
            # 14-day half-life. Today is excluded — a day that has only
            # reached noon reports every evening hour as rest, and the shape
            # is exactly the thing that must not learn that.
            for (k in hburn) {
                split(k, kp, SUBSEP)
                if (kp[1] + 0 == today) continue
                age = today - kp[1]; if (age < 0) age = 0
                w = exp(-0.0495 * age)
                hnum[kp[2] + 0] += hburn[k] * w; hden += hburn[k] * w
            }
            printf "{\"schema\":%d,\"computed_at\":%d,\"days_history\":%d,", schema, now, ndays
            printf "\"recent_24h\":%.2f,\"recent_48h\":%.2f,", r24, r48
            printf "\"pct_per_window\":%.2f,", ppw
            printf "\"weekday_profile\":{"
            sep = ""
            for (i = 0; i <= 6; i++) {
                p = (den[i] > 0) ? num[i] / den[i] : -1
                printf "%s\"%d\":%.2f", sep, i, p; sep = ","
            }
            printf "},"
            # Published floored AND renormalized, so every reader sees the
            # same numbers rather than each applying the hedge its own way:
            # a rest hour projects a tenth of a uniform hour, never zero,
            # which is what the occasional overnight autonomous run costs.
            # Omitted entirely when nothing has been credited — a reader with
            # no shape walks flat, which is the behavior that predates this
            # field.
            if (hden > 0) {
                hsum = 0
                for (i = 0; i < 24; i++) {
                    hm[i] = hnum[i] / hden * 24
                    if (hm[i] < 0.1) hm[i] = 0.1
                    hsum += hm[i]
                }
                printf "\"hour_profile\":{"
                sep = ""
                for (i = 0; i < 24; i++) {
                    printf "%s\"%d\":%.2f", sep, i, hm[i] * 24 / hsum; sep = ","
                }
                printf "},"
            }
            printf "\"scoped_name\":%s,", (sc_last == "" ? "null" : "\"" sc_last "\"")
            printf "\"scoped_recent_24h\":%.2f,", (sc_last == "" ? -1 : cr24[sc_last])
            printf "\"scoped_profile\":{"
            sep = ""
            for (i = 0; i <= 6; i++) {
                p = (cden[i] > 0) ? cnum[i] / cden[i] : -1
                printf "%s\"%d\":%.2f", sep, i, p; sep = ","
            }
            printf "},"
            # What a 7d point costs, over the samples that carried both. -1
            # until a real window of paired observation exists: a price
            # mined from two samples is a rumour, not a rate.
            upp = -1
            if (usd_all > 0 && burn_paired >= 5) upp = usd_all / burn_paired
            printf "\"cost\":{\"usd_24h\":%.2f,\"usd_7d\":%.2f,\"usd_per_pct\":%.4f,\"paired_pct\":%.1f},", \
                u24, u7d, upp, burn_paired
            # Which samples this model was run over. `schema` versions the
            # model and cannot say: two writers that agree on envelope burn
            # and read different stores both pass the gate.
            printf "\"corpus\":{\"uuid\":\"%s\",\"files\":%d,\"samples\":%d,\"dropped_no_uuid\":%d,\"oldest\":%d}", \
                acct, nfiles, nsamp, drop_nu, (oldest == "" ? 0 : oldest)
            printf "}\n"
        }')
    if [ -n "$data" ]; then
        printf '%s\n' "$data" >"${out}.tmp.$$" 2>/dev/null && mv -f "${out}.tmp.$$" "$out"
        debug_log "build_seven_day_profile: rebuilt ($(echo "$data" | jq -r '"\(.days_history) days, \(.corpus.samples) samples in \(.corpus.files) files, \(.corpus.dropped_no_uuid) no-uuid dropped"'), acct=${acct:0:8})"
    fi
}

# Project the remaining window hour-by-hour against the learned profile and
# echo "<level> <dry_gap_hours>" when the quota dries up BEFORE the reset
# ("you will be out of usage while days still remain"). Empty output = no
# verdict (no cache, cold start < 14 days of history, or quota outlasts the
# window). The first 24h of the walk burns at max(profile, recent_24h) so a
# hot streak escalates before the weekday average catches up (L1 blend).
# Shared learned-profile walker: simulate burn from now to the reset using
# the weekday profile (recent-24h blended over the first day, exactly the
# seven_day_forecast behavior), shaped by the learned hour profile — the
# weekday says how much a Tuesday costs, the hour says WHEN in it. Echoes
# "gap_h projected_end":
#   gap_h          hours between drying up and the reset, -1 if the quota
#                  outlasts the window
#   projected_end  final utilization at the reset, capped at 100
# Silent on cold start (<14 days history) or missing/empty inputs. `now` is
# injectable because the hour shape makes the answer depend on when the walk
# runs, and a test that cannot pin the hour cannot assert where a dry-out
# lands.
_profile_walk() {
    local used="$1" secs_left="$2" prof_key="${3:-weekday_profile}" recent_key="${4:-recent_24h}" now="${5:-}"
    local fc="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    [ -f "$fc" ] || return 0
    [ -n "$secs_left" ] && [ "$secs_left" -gt 0 ] 2>/dev/null || return 0
    # A young window has no evidence of its own. The profile is learned from
    # the windows BEFORE this one, so minutes after a rollover the walk
    # projects last week's Tuesday onto a pool that is 2% spent and calls it
    # dry — and the L1 recent-24h blend it opens with describes a trailing day
    # that sits on the far side of the reset. Silence until the window can
    # speak for itself; the same silence a cold start earns.
    local since_reset=$(( SEVEN_DAY_WINDOW_SECS - secs_left ))
    [ "$since_reset" -ge "$SEVEN_DAY_YOUNG_SECS" ] 2>/dev/null || return 0
    local used_int
    used_int=$(printf '%.0f' "$used" 2>/dev/null || echo 0)
    [ "$used_int" -gt 0 ] 2>/dev/null || return 0
    local tzoff_s
    [ -n "$now" ] || now=$(date +%s)
    tzoff_s=$(date +%z | awk '{ s=substr($0,1,1)=="-"?-1:1; h=substr($0,2,2)+0; m=substr($0,4,2)+0; print s*(h*3600+m*60) }')
    # The 24 hour multipliers ride the same TSV. Anything that is not a
    # number lands as -1 and fails the read validation below: @tsv refuses an
    # object or an array outright, and a walk that goes silent because a
    # foreign writer put a nested value in hour_profile would be a bad shape
    # silencing a good forecast.
    jq -r --arg p "$prof_key" --arg r "$recent_key" '
        (.[$p] // {}) as $wp
        | (if ((.hour_profile // null) | type) == "object" then .hour_profile else {} end) as $hp
        | [.days_history, (.[$r] // -1),
           ($wp["0"] // -1), ($wp["1"] // -1), ($wp["2"] // -1), ($wp["3"] // -1),
           ($wp["4"] // -1), ($wp["5"] // -1), ($wp["6"] // -1)]
          + [range(0; 24) | ($hp[tostring] // -1)
             | if type == "number" then . else -1 end] | @tsv' "$fc" 2>/dev/null \
    | awk -F'\t' -v used="$used_int" -v left="$secs_left" -v now="$now" -v tz="$tzoff_s" '
    {
        ndays = $1 + 0; r24 = $2 + 0
        if (r24 < 0) r24 = 0               # unlearned recent: no blend, no lie
        if (r24 > 100) r24 = 100           # a reset can double the envelope in
                                           # 24h; THIS window still cannot lose
                                           # more than everything in a day
        for (i = 0; i <= 6; i++) prof[i] = $(i + 3) + 0
        if (ndays < 14) exit               # cold start: not enough history
        # No weekday can AVERAGE above the whole pool per day. A profile that
        # claims one came from a broken accountant (measured: a pre-envelope
        # writer sharing this home put 145 in Thursday and the walk called a
        # 2%-used fresh window dry in 30h). Corrupt input earns silence.
        for (i = 0; i <= 6; i++) if (prof[i] > 100) exit
        # fallback rate for never-seen weekdays: mean of known ones
        known = 0; sum = 0
        for (i = 0; i <= 6; i++) if (prof[i] >= 0) { sum += prof[i]; known++ }
        if (known == 0) exit
        fb = sum / known
        # The hour shape, validated exactly as the cache contract states it:
        # 24 keys, each numeric in [0, 24], mean in [0.9, 1.1]. Absent or
        # broken reads as FLAT, which is this walk before the field existed —
        # a bad hour shape narrows nothing and silences nothing. Only the
        # weekday guards above can silence the walk.
        hp_ok = 1; hsum = 0
        for (i = 0; i < 24; i++) {
            hm[i] = $(i + 10) + 0
            if (hm[i] < 0 || hm[i] > 24) hp_ok = 0
            hsum += hm[i]
        }
        if (hsum / 24 < 0.9 || hsum / 24 > 1.1) hp_ok = 0
        if (!hp_ok) for (i = 0; i < 24; i++) hm[i] = 1
        remaining = 100 - used
        t = now; end = now + left; burned = 0; gap_h = -1
        # Local-hour steps (<= 169 of them), because a rate that changes at
        # 08:00 cannot be integrated a day at a time.
        while (t < end) {
            lt = t + tz
            day = int(lt / 86400)
            seg = t + 3600 - (lt % 3600)
            if (seg > end) seg = end
            step = seg - t
            rate = prof[(day + 4) % 7]; if (rate < 0) rate = fb
            # L1 blend, tested at the segment start as it always was — which
            # on hour steps means it now ends at exactly 24h out. Day steps
            # let a blend that began mid-day run to the end of the day
            # holding t+24h, so a hot rate could be projected through 47
            # hours; the 24h horizon is what the field says and what ccpace
            # walks, and two surfaces reading one cache may not disagree.
            if (t - now < 86400 && r24 > rate) rate = r24   # L1 blend
            rate *= hm[int((lt % 86400) / 3600)]
            add = rate * step / 86400.0
            if (gap_h < 0 && burned + add >= remaining && rate > 0) {
                dry = t + (remaining - burned) / rate * 86400.0
                gap_h = int((end - dry) / 3600.0)
            }
            burned += add; t = seg
        }
        total = used + burned
        if (total > 100) total = 100
        printf "%d %d\n", gap_h, int(total + 0.5)
    }'
}

# The account 7d and the model-scoped cap, each by name. Callers say which
# question they are asking; neither has to know how a profile is stored.
_seven_day_walk() { _profile_walk "$1" "$2" weekday_profile recent_24h "${3:-}"; }
_scoped_walk()    { _profile_walk "$1" "$2" scoped_profile scoped_recent_24h "${3:-}"; }

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

# The scoped cap's learned forecast, same shape and contract as
# seven_day_forecast. This is the one that can say on Thursday that Fable
# runs out on Monday: linear pace only ever measures the week so far, and a
# week whose Tuesday is 39%/day and whose Sunday is 6%/day is not a line.
scoped_forecast() {
    local used="$1" secs_left="$2"
    local used_int
    used_int=$(printf '%.0f' "$used" 2>/dev/null || echo 0)
    local gap_h proj_end
    read -r gap_h proj_end <<<"$(_scoped_walk "$used_int" "$secs_left")"
    [ -n "$gap_h" ] && [ "$gap_h" != "-1" ] || return 0
    local level="yellow"
    { [ "$gap_h" -ge 48 ] || [ "$used_int" -ge 90 ]; } 2>/dev/null && level="red"
    echo "$level $gap_h"
}

# The scope the learned profile describes, or nothing while unlearned. A
# caller must not attribute a forecast to a model the profile is not about.
scoped_profile_name() {
    local fc="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    [ -f "$fc" ] || return 0
    jq -r '.scoped_name // empty' "$fc" 2>/dev/null
}

# What a 7d percentage point costs this account, in dollars, or nothing while
# unlearned. The join no single source can make: the quota API reports percent
# and never dollars on a subscription plan, the transcripts report dollars and
# never percent.
forecast_usd_per_pct() {
    local fc="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    [ -f "$fc" ] || return 0
    local v
    v=$(jq -r '.cost.usd_per_pct // -1' "$fc" 2>/dev/null) || return 0
    awk -v p="${v:--1}" 'BEGIN{ if (p > 0) printf "%.4f", p }'
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

# The learned hour shape as 24 space-separated multipliers, or nothing while
# it is unlearned. The read validation is the cache contract
# (docs/api/state-dir.md): 24 keys, every value numeric in [0, 24], mean in
# [0.9, 1.1], plus the same >= 14 days of history every other learned surface
# waits for. Anything else reads as flat — no clause narrows, nothing goes
# quiet. `|| true`: jq exits nonzero on a truncated cache, and under `set -e`
# a bare `x=$(cmd)` aborts AT the assignment.
hour_profile_mults() {
    local fc="$CLAUDE_ACCOUNT_DIR/forecast.cache"
    [ -f "$fc" ] || return 0
    jq -r 'if (.days_history // 0) < 14 then empty else
             (if ((.hour_profile // null) | type) == "object" then .hour_profile else {} end) as $h
             | [range(0; 24) | ($h[tostring] // -1) | if type == "number" then . else -1 end]
             | if (map(select(. >= 0 and . <= 24)) | length) == 24
                  and (add / 24) >= 0.9 and (add / 24) <= 1.1
               then map(tostring) | join(" ") else empty end
           end' "$fc" 2>/dev/null || true
}

# Seconds of the span [now + from, now + to] that fall in AWAKE local hours —
# the ones whose learned multiplier clears REST_MULT_MAX. Nothing (not zero)
# while the shape is unlearned: a caller must be able to tell "you sleep
# through all of it" from "I have no idea when you sleep". `now` is
# injectable for the same reason the walk's is.
awake_secs() {
    local mults="$1" from="${2:-0}" to="${3:-0}" now="${4:-}"
    [ -n "$mults" ] || return 0
    local tzoff_s
    [ -n "$now" ] || now=$(date +%s)
    tzoff_s=$(date +%z | awk '{ s=substr($0,1,1)=="-"?-1:1; h=substr($0,2,2)+0; m=substr($0,4,2)+0; print s*(h*3600+m*60) }')
    awk -v now="$now" -v tz="$tzoff_s" -v from="$from" -v to="$to" \
        -v rest="$REST_MULT_MAX" -v mults="$mults" 'BEGIN{
        if (split(mults, m, " ") != 24) { print 0; exit }
        t = now + from; hi = now + to; awake = 0
        while (t < hi) {
            lt = t + tz
            seg = t + 3600 - (lt % 3600)
            if (seg > hi) seg = hi
            if (m[int((lt % 86400) / 3600) + 1] + 0 >= rest) awake += seg - t
            t = seg
        }
        printf "%d\n", awake
    }'
}

# ---------------------------------------------------------------------------
# The waste ledger: `statusline.sh report [--days N]`. Mines usage.jsonl for
# closed windows and says, in percent and in windows, what expired unused.
# The advisor prevents waste prospectively; this proves it retroactively.
#
# A window "closes" when consecutive samples disagree on resets_at (normalized
# to the minute — the same identity rule the ratio learner uses): the last
# sample before the flip is that window's final utilization. Honest limits:
# usage from other clients after the last local render is invisible, and a
# window that was never sampled never existed as far as the log knows.
# ---------------------------------------------------------------------------
run_usage_report() {
    local days="${1:-28}"
    case "$days" in '' | *[!0-9]*) days=28 ;; esac
    [ "$days" -ge 1 ] 2>/dev/null || days=28
    local jsonl="$CLAUDE_ACCOUNT_DIR/usage.jsonl"
    if [ -z "$(usage_corpus_files)" ]; then
        echo "no usage history yet ($jsonl)"
        echo "the statusline logs every quota fetch; come back after a session or two."
        return 1
    fi
    local acct
    acct=$(jq -r '.account.uuid // empty' "$CLAUDE_ACCOUNT_DIR/profile.cache" 2>/dev/null)
    # profile.cache can postdate the log (fresh install): fall back to the
    # last snapshot's identity rather than reporting nothing.
    [ -n "$acct" ] || acct=$(tail -1 "$jsonl" 2>/dev/null | jq -r '.user.uuid // empty' 2>/dev/null)
    local now cutoff
    now=$(date +%s)
    cutoff=$(( now - days * 86400 ))
    # Mined stream: "S <7d-close-key> <final%>" per closed 7d window,
    # then "F <closed> <avg%> <capped>" for 5h windows, "N <samples>".
    local mined
    mined=$( cat_usage_corpus | jq -r --arg a "$acct" --argjson cut "$cutoff" '
        def norm: tostring | . as $raw
            | if $raw == "" then "" else
                (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")
                      | fromdateiso8601 | (. + 30) / 60 | floor) catch $raw)
              end;
        select((.type // "usage") == "usage" and (.user.uuid // "") == $a
               and (.timestamp // 0) >= $cut)
        | [.timestamp, (.five_hour.utilization // ""), (.seven_day.utilization // ""),
           ((.five_hour.resets_at // "") | norm), ((.seven_day.resets_at // "") | norm)]
        | @tsv' 2>/dev/null \
        | sort -n | awk -F'\t' '
        {
            n++
            if ($4 != "" && pfk != "" && $4 != pfk && pfu != "") {
                fcl++; fsum += pfu; if (pfu >= 99) fcap++
            }
            if ($5 != "" && psk != "" && $5 != psk && psu != "") {
                print "S", psk, psu
            }
            if ($4 != "") { pfk = $4; if ($2 != "") pfu = $2 }
            if ($5 != "") { psk = $5; if ($3 != "") psu = $3 }
        }
        END {
            printf "F %d %.0f %d\n", fcl, (fcl ? fsum / fcl : 0), fcap
            printf "N %d\n", n
        }')

    local ppw
    ppw=$(forecast_pct_per_window)
    local f_closed=0 f_avg=0 f_cap=0 samples=0
    read -r _ f_closed f_avg f_cap <<<"$(printf '%s\n' "$mined" | grep '^F ' | head -1)"
    read -r _ samples <<<"$(printf '%s\n' "$mined" | grep '^N ' | head -1)"

    printf 'usage report - %s (last %sd, %s samples)\n\n' "${ACCOUNT_TAG:-default}" "$days" "${samples:-0}"

    local s_count
    s_count=$(printf '%s\n' "$mined" | grep -c '^S ')
    printf '7d windows closed: %s\n' "$s_count"
    if [ "$s_count" -gt 0 ] 2>/dev/null; then
        local key final used_i waste wins when sum_final=0
        while read -r _ key final; do
            used_i=$(printf '%.0f' "$final" 2>/dev/null || echo 0)
            waste=$(( 100 - used_i )); [ "$waste" -lt 0 ] && waste=0
            sum_final=$(( sum_final + used_i ))
            case "$key" in
            *[!0-9]*) when="$key" ;;
            *) when=$(_fmt_epoch "$(( key * 60 ))" '%a %m-%d %H:%M') ;;
            esac
            if [ -n "$ppw" ]; then
                wins=$(awk -v w="$waste" -v p="$ppw" 'BEGIN{printf "%.1f", w / p}')
                printf '  %s  used %s%%  expired %s%% (~%s '"$MULT_GLYPH"' 5h windows unused)\n' \
                    "$when" "$used_i" "$waste" "$wins"
            else
                printf '  %s  used %s%%  expired %s%%\n' "$when" "$used_i" "$waste"
            fi
        done <<<"$(printf '%s\n' "$mined" | grep '^S ')"
        if [ "$s_count" -gt 1 ] 2>/dev/null; then
            local avg_used=$(( sum_final / s_count ))
            printf '  avg at close: %s%% used / %s%% expired\n' "$avg_used" "$(( 100 - avg_used ))"
        fi
    fi

    if [ "${f_closed:-0}" -gt 0 ] 2>/dev/null; then
        printf '\n5h windows closed: %s   avg %s%% at close   %s hit the cap\n' \
            "$f_closed" "$f_avg" "$f_cap"
    else
        printf '\n5h windows closed: 0\n'
    fi

    if [ -n "$ppw" ]; then
        local wpw
        wpw=$(awk -v p="$ppw" 'BEGIN{printf "%.1f", 100 / p}')
        printf 'exchange rate: one full 5h window = ~%s%% of the week (~%s windows/week, learned)\n' \
            "$ppw" "$wpw"
    else
        printf 'exchange rate: still learning (needs ~half a window of paired burn)\n'
    fi

    # Price. A percentage is not a quantity you can reason about; a dollar is.
    local upp usd24 usd7d paired
    upp=$(forecast_usd_per_pct)
    eval "$(jq -r '@sh "usd24=\(.cost.usd_24h // 0)", @sh "usd7d=\(.cost.usd_7d // 0)",
                   @sh "paired=\(.cost.paired_pct // 0)"' \
        "$CLAUDE_ACCOUNT_DIR/forecast.cache" 2>/dev/null)" 2>/dev/null || true
    if [ -n "$upp" ]; then
        printf 'price: ~$%s per 7d point%s · one 5h window ~$%s · a full week ~$%s\n' \
            "$(awk -v p="$upp" 'BEGIN{printf "%.2f", p}')" \
            "${paired:+ (learned from ${paired} paired points)}" \
            "$(awk -v p="$upp" -v w="${ppw:-0}" 'BEGIN{printf "%.0f", p * w}')" \
            "$(awk -v p="$upp" 'BEGIN{printf "%.0f", p * 100}')"
    else
        printf 'price: still learning (samples carrying both dollars and percent)\n'
    fi
    awk -v a="${usd24:-0}" -v b="${usd7d:-0}" \
        'BEGIN{ if (a > 0 || b > 0) printf "spent: $%.2f in 24h · $%.2f in 7d\n", a, b }'

    # What a 7d point buys in the pool beside it. The account pool and the
    # model-scoped pool are cumulative from one reset instant, so their live
    # ratio is this week's mix rate, and the account reaching its wall first
    # is what strands the rest of the model's pool. No history is needed and
    # nothing is cached — the reading rules are the SCOPE_* constants, shared
    # with ccpace (docs/api/state-dir.md). No session runs here, so there is
    # no model to match: the binding scoped limit speaks, else the deepest.
    local mix_cache="$CLAUDE_ACCOUNT_DIR/usage.cache" mix_tsv=""
    if [ -f "$mix_cache" ]; then
        mix_tsv=$(jq -r '. as $u
            | [$u.limits[]? | select(.kind == "weekly_scoped"
                                     and (.scope.model.display_name // "") != "")]
            | ((map(select(.is_active == true)) | first) // (sort_by(.percent // 0) | last) // empty)
            | [(.scope.model.display_name | ascii_downcase), (.percent // 0), (.resets_at // ""),
               ($u.seven_day.utilization // 0), ($u.seven_day.resets_at // "")] | @tsv' \
            "$mix_cache" 2>/dev/null) || true
    fi
    if [ -n "$mix_tsv" ]; then
        local mx_name mx_pct mx_reset mx_su mx_sreset
        IFS=$'\t' read -r mx_name mx_pct mx_reset mx_su mx_sreset <<<"$mix_tsv"
        local mx_int mx_seven mx_secs mx_ssecs
        mx_int=$(printf '%.0f' "$mx_pct" 2>/dev/null || echo 0)
        mx_seven=$(printf '%.0f' "$mx_su" 2>/dev/null || echo 0)
        mx_secs=$(get_reset_seconds "$mx_reset")
        mx_ssecs=$(get_reset_seconds "$mx_sreset")
        if [ -n "$mx_secs" ] && [ -n "$mx_ssecs" ] && [ "$mx_ssecs" -gt 0 ] 2>/dev/null \
           && [ "$mx_int" -ge "$SCOPE_MIX_MIN_SCOPE" ] && [ "$mx_int" -lt 100 ] 2>/dev/null \
           && [ "$mx_seven" -ge "$SCOPE_MIX_MIN_7D" ] && [ "$mx_seven" -lt 100 ] 2>/dev/null \
           && [ $((SEVEN_DAY_WINDOW_SECS - mx_ssecs)) -ge "$SEVEN_DAY_YOUNG_SECS" ] 2>/dev/null; then
            local mx_wall=$((mx_secs - mx_ssecs))
            [ "$mx_wall" -lt 0 ] && mx_wall=$((-mx_wall))
            local mx_reach=$(( ((100 - mx_seven) * mx_int + mx_seven / 2) / mx_seven ))
            local mx_strand=$((100 - mx_int - mx_reach))
            if [ "$mx_wall" -le "$SCOPE_SAME_WALL_SEC" ] \
               && [ "$mx_strand" -ge "$SCOPE_STRAND_MIN_PCT" ]; then
                local mx_ab
                mx_ab=$(model_scope_abbrev "$mx_name")
                printf "%s mix: ~%s %s-pt per 7d-pt this week · 7d's %s%% left carries ~%s%% of %s's %s%%\n" \
                    "$mx_ab" \
                    "$(awk -v s="$mx_int" -v v="$mx_seven" 'BEGIN{printf "%.2f", s / v}')" \
                    "$mx_ab" "$((100 - mx_seven))" "$mx_reach" "$mx_ab" "$((100 - mx_int))"
            fi
        fi
    fi

    # The rhythm the walk below is now shaped by. Stated because it changes
    # every projection in this report and is the one learned fact the reader
    # can check against their own week.
    local hour_mults
    hour_mults=$(hour_profile_mults)
    if [ -n "$hour_mults" ]; then
        awk -v m="$hour_mults" -v rest="$REST_MULT_MAX" 'BEGIN{
            split(m, mult, " ")
            awake = 0
            for (i = 0; i < 24; i++) if (mult[i + 1] + 0 >= rest) awake++
            # Longest CIRCULAR run of rest hours: sleep wraps 23 -> 0, and a
            # run cut at midnight reads as two short ones. Two passes over
            # the ring find it; the mean is 1, so some hour is always awake
            # and the run can never swallow the ring.
            best = 0; bs = -1; run = 0; start = 0
            for (i = 0; i < 48; i++) {
                h = i % 24
                if (mult[h + 1] + 0 < rest) {
                    if (run == 0) start = h
                    run++
                    if (run > best) { best = run; bs = start }
                } else run = 0
            }
            if (best >= 3)
                printf "rhythm: rest ~%02d:00-%02d:00 · %dh awake/day (learned)\n", \
                    bs, (bs + best) % 24, awake
            else
                printf "rhythm: no rest learned — burns around the clock\n"
        }'
    fi

    # Week in progress, from the freshest source (usage.cache), projected with
    # the same learned walk the advisor uses — the surfaces must not disagree.
    local uc="$CLAUDE_ACCOUNT_DIR/usage.cache"
    if [ -f "$uc" ]; then
        local cur_su cur_reset secs repoch when gap end
        cur_su=$(jq -r '.seven_day.utilization // empty' "$uc" 2>/dev/null)
        cur_reset=$(jq -r '.seven_day.resets_at // empty' "$uc" 2>/dev/null)
        if [ -n "$cur_su" ] && [ -n "$cur_reset" ]; then
            secs=$(get_reset_seconds "$cur_reset")
            repoch=$(_epoch_from_ts "$cur_reset")
            when=$(_fmt_epoch "${repoch:-0}" '%a %m-%d %H:%M')
            read -r gap end <<<"$(_seven_day_walk "$cur_su" "${secs:-0}")"
            if [ -n "$end" ]; then
                printf '\nweek in progress: %.0f%% used, resets %s - lands ~%s%%\n' \
                    "$cur_su" "$when" "$end"
            else
                printf '\nweek in progress: %.0f%% used, resets %s\n' "$cur_su" "$when"
            fi
        fi
    fi
    return 0
}

# Model context from the log: the newest record that actually carries a
# model. `tail -1` alone is wrong twice over — the newest line may be a
# session_start/session_end marker (no .model), or a cooperating
# writer's sample (ccpace logs model:null by contract). Bounded scan:
# 200 records is hours of history, and the answer is almost always in
# the last few.
last_logged_model() {
    local jsonl="$CLAUDE_ACCOUNT_DIR/usage.jsonl"
    [ -f "$jsonl" ] || return 0
    tail -n 200 "$jsonl" 2>/dev/null \
        | jq -r '.model // empty' 2>/dev/null \
        | awk 'NF { m = $0 } END { if (m != "") print m }'
}

# `statusline.sh check` — the advisor as an exit code, for tmux segments,
# cron notifiers, and scripts (`check || notify`). Prints the plain-text
# advisor verdict (or "calm"/"unknown: ...") and exits:
#   0 calm    1 opportunity (+)    2 pressure (!)    3 unknown/stale
# We provide the judgment; the host provides the plumbing — no daemon.
# Model context comes from the last logged snapshot, so scoped clauses
# know which model this account was last running.
run_check() {
    local uc="$CLAUDE_ACCOUNT_DIR/usage.cache"
    if [ ! -f "$uc" ]; then
        echo "unknown: no usage.cache under $CLAUDE_ACCOUNT_DIR"
        return 3
    fi
    local fetched age
    fetched=$(jq -r '.fetched_at // 0' "$uc" 2>/dev/null)
    age=$(( $(date +%s) - ${fetched:-0} ))
    if [ "$age" -gt 3600 ] 2>/dev/null; then
        # The state-dir contract's staleness rule: >1h old means no active
        # session feeds this account — the numbers describe the past.
        echo "unknown: usage.cache ${age}s stale (no active session feeding this account)"
        return 3
    fi
    local last_model
    last_model=$(last_logged_model)
    local line plain
    line=$(notice_long_line "$(notice_collect "$(cat "$uc")" auto "$last_model")")
    if [ -z "$line" ]; then
        echo "calm"
        return 0
    fi
    plain=$(printf '%b' "$line" | sed 's/\x1b\[[0-9;]*m//g')
    printf '%s\n' "$plain"
    case "$plain" in
    "! "*) return 2 ;;
    "+ "*) return 1 ;;
    esac
    return 0
}

# `statusline.sh session-summary` — one-line session retrospective, designed
# as a SessionEnd hook (pipe the hook JSON in; only session_id is read).
# Falls back to the last session in the log for manual runs. Window deltas
# are positive-delta sums (resets ignored), the profile builder's rule, so
# a session that straddles a 5h reset still reports what it consumed.
run_session_summary() {
    local sid=""
    [ ! -t 0 ] && sid=$(cat 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null)
    local jsonl="$CLAUDE_ACCOUNT_DIR/usage.jsonl"
    if [ -z "$sid" ] && [ -f "$jsonl" ]; then
        sid=$(jq -r 'select((.type // "") == "usage") | .session_id // empty' "$jsonl" 2>/dev/null | tail -1)
    fi
    if [ -z "$sid" ]; then
        echo "session-summary: no session id (pipe hook JSON, or log some usage first)"
        return 1
    fi
    if [ ! -f "$jsonl" ] && [ ! -f "${jsonl}.1" ]; then
        echo "session-summary: no usage log at $jsonl"
        return 1
    fi
    local out
    out=$( { cat "${jsonl}.1" 2>/dev/null; cat "$jsonl" 2>/dev/null; } | jq -r --arg s "$sid" '
            select((.type // "") == "usage" and (.session_id // "") == $s)
            | [.timestamp, (.five_hour.utilization // ""),
               (.seven_day.utilization // ""), (.model // "")]
            | @tsv' 2>/dev/null \
        | sort -n | awk -F'\t' -v sid="${sid:0:8}" '
        {
            n++
            if (first == "") first = $1
            last = $1
            if ($2 != "") { if (pf != "" && $2 > pf) df += $2 - pf; pf = $2 }
            if ($3 != "") { if (ps != "" && $3 > ps) ds += $3 - ps; ps = $3 }
            if ($4 != "") model = $4
        }
        END {
            if (n == 0) exit 0
            secs = last - first
            h = int(secs / 3600); m = int((secs % 3600) / 60)
            dur = (h > 0 ? h "h" m "m" : m "m")
            printf "session %s: %s, 5h +%.0fpts, 7d +%.0fpts%s\n", \
                sid, dur, df, ds, (model != "" ? ", " model : "")
        }')
    if [ -z "$out" ]; then
        echo "session-summary: no samples for session ${sid:0:8}"
        return 1
    fi
    printf '%s\n' "$out"
    return 0
}

# `statusline.sh week` — the 7d period as its 5h windows, one cell each:
#   ▂▃▄▅▆▇█   a window that ran; height = 7d points it burned
#   ▁         ran, burned under a point — the baseline
#   ░         unknown: no samples on record for that window
#   ▮         the window you are in now
#   ▯         a window still ahead of you (dim: one you likely sleep through)
# The report draws every slot, so what follows ▮ IS the budget line's
# "~N✕5h left" laid out cell by cell — ▮ itself is where you are, not a
# window you have left. The live row folds that same tail and prints the
# count instead. Past cells come from usage.jsonl; unknown and idle stay
# different glyphs because drawing a gap in the record as an idle session
# is the one lie this row must not tell. The prospective glance beside report's
# retrospective ledger; the same strip claude.py renders, so both
# surfaces tell one story. Reads usage.cache; stale data renders but says so.
# --- week row (the two windows as ledgers) ------------------------------------
# One grammar at two scales. The 7d strip: one cell per 5h slot of the 7d
# period (34; the last a 3h stub) on a fixed grid from the period start, a
# thin gap at each local midnight so days read as clusters without a ruler.
# The 5h strip: one cell per hour of the CURRENT 5h window (5 cells).
#   ▂▃▄▅▆▇█   a cell that ran, height ∝ points it burned (7d points per
#             5h window; 5h points per hour)
#   ▁         ran, burned under a point, or idle inside the log's coverage —
#             the shortest bar in the same block, dim: the baseline. One
#             Unicode run for the whole ladder (LEDGER_BASE_GLYPH); a
#             modifier letter used to sit here and broke the row's metrics.
#   ░         unknown — outside the sample log's coverage
#   ▮         the cell you are in now
#   ▯         a cell still ahead of you (the hollow of ▮: an empty slot);
#             DIM when the learned rhythm says you sleep through most of it —
#             capacity on the grid that is not really available. The one
#             refinement this row carries by tint alone, and the one place
#             that is honest: a dim ▯ is still a window ahead, so a reader
#             who cannot see the tint loses nothing actionable. The dim
#             count may sit one off the budget's "~N awake": these are grid
#             slots, the sentence is clocks, the same one-cell tolerance
#             the fold count documents below.
#   ...▯(✕11) the folded future: 11 more 5h windows AFTER the one you are in
#             (× in place of ▯ when the tail projects dry — the one place
#             the dry mark still draws) — live 7d strip only, and only
#             while the tail is wider than this token. The count is
#             windows ahead, the same number the budget
#             line prices as "~11✕5h left" — one line, one arithmetic. (It is
#             NOT the hidden-cell count: the 34-cell grid spans 170h against a
#             168h period, and a row that says 10 beside a budget that says 11
#             makes the reader arbitrate between its own halves.)
#             ✕ is the operator, × is a cell: the two never mean the same.
# Unknown and idle are deliberately different glyphs: drawing a gap in the
# record as an idle session is the one lie this row must not tell.
# Both strips draw their whole grid, so a strip is an axis, not a growing bar:
# it holds its width for the life of the window and ▮ walks it. On the 5h
# strip that makes the hollow run the answer to "how long have I got" — five
# slots, one per hour, `▃▃▮▯▯` is two whole hours left after this one, no
# arithmetic and no second glance at the clock.
# What NEITHER strip draws in a cell is a FORECAST. An empty cell is a fact
# (that span has not happened); a × is a guess, and the guess is already
# owned — the badge states the end, a notice names the wall with its own
# gates and an exact time (`5h caps ~14:20`, `7d dry ~Tue 22:00`). v0.33
# established this for the 5h strip; the 7d strip kept its × cells only
# because the fold hid them, and the unfold called the question: a run of
# ××× was read live as deleted windows. Cells carry the shape, badges carry
# state, notices do the warning; the folded token alone keeps the dry mark.
# Shared by the live `--week` row and the `week` subcommand, so the two
# surfaces cannot disagree.

WEEK_CELLS=34
FIVE_CELLS=5
FIVE_CELL_SECS=3600
WEEK_CACHE_TTL_SECS=300
# The live row compresses the 7d strip's future run: after the now-marker it
# keeps WEEK_FUTURE_KEEP hollow cells, then folds the rest into `...▯(✕11)`
# (count = windows_ahead, the 5h windows after this one; × red when the tail
# projects dry).
# "History is information; the future is one fact" was this fold's original
# argument, and the rest tint SUPERSEDED it: future cells now carry which
# windows the reader is awake for, so the future is a shape, not one fact.
# What remains of the fold is column economy. The token `...×(✕11)` is nine
# columns; hiding fewer cells than that pays nothing, so a future of
# WEEK_FUTURE_UNFOLD_MAX cells or fewer draws in full — the last ~2 days of
# every week — and only the long early-week run still folds. The old
# measurement stands where it was made: 30 hollow cells DO read as "too much
# future", and the count is still the part that has to survive mid-week,
# when a pressure notice owns the pin and this row is the only place the
# remaining windows appear.
WEEK_FUTURE_KEEP=2
WEEK_FUTURE_MIN_HIDE=2
WEEK_FUTURE_UNFOLD_MAX=10

# The period start on the same 5-min grid the window keys are rounded to.
# resets_at is jittered by the API (15:59:59.76 one fetch, 16:00:00.47 the
# next); a raw `reset - 7d` can land a hair past slot 0's true start and
# push that window to slot -1 — the first cell of the week silently lost.
week_period_start() {
    local now="$1" seven_secs="$2"
    echo $(( ( (now + seven_secs - SEVEN_DAY_WINDOW_SECS + 150) / 300 ) * 300 ))
}

# How many 5h windows are still AHEAD of the one you are in. The current
# window is where you are, not what you have left: the row already draws it as
# ▮ and the badge already prices it, so counting it again makes `▮ + 11` read
# as twelve. What remains once it closes is (7d left - 5h left), and a partial
# window at the end of the week is still a window you can spend, so that
# divides up. Two properties fall out and both matter: the number is stable
# inside a window (both clocks tick down together, the difference does not
# move) and it steps down by exactly one at each 5h rollover — a countdown you
# can trust rather than a reading that drifts mid-window. With no live 5h
# window in the payload there is nothing to exclude and the whole 7d
# remainder is ahead.
windows_ahead() {
    local seven_secs="${1:-0}" five_secs="${2:-0}"
    local rest=$(( seven_secs - five_secs ))
    [ "$rest" -gt 0 ] 2>/dev/null || { echo 0; return 0; }
    echo $(( (rest + 17999) / 18000 ))
}

# One pass over usage.jsonl(.1) for both strips, cached in week.cache keyed
# by the two period starts and the log's mtime:size — the scan is a whole-log
# jq pass, far too heavy for a per-render path, and the cells only move when
# a sample lands. Prints two lines, each "span_lo span_hi slot:cost,...", or
# empty when the log holds nothing for that period:
#   1. the 7d strip: a window instance is keyed by its 5h resets_at rounded
#      to 5 min (the API jitters it, and 05:59:59/06:00:00 are one window),
#      cost = the 7d delta observed inside it;
#   2. the 5h strip: samples of the current 5h window (same key), sorted,
#      walked as a monotone envelope (running max — utilization only climbs
#      inside a window; a dip is a stale reading, never a refund), each
#      step credited to the hour cell the sample fell in.
week_scan() {
    local period_start="$1" five_start="${2:-0}"
    local wc="$CLAUDE_ACCOUNT_DIR/week.cache"
    [ -n "$(usage_corpus_files)" ] || return 0
    local sig
    sig="$(usage_corpus_sig)"
    if [ -f "$wc" ]; then
        local c_ps c_fs c_sig c_at c_week c_five
        eval "$(jq -r '@sh "c_ps=\(.period_start // 0)", @sh "c_fs=\(.five_start // 0)",
                       @sh "c_sig=\(.log_sig // "")", @sh "c_at=\(.at // 0)",
                       @sh "c_week=\(.week // .hist // "")", @sh "c_five=\(.five // "")"' "$wc" 2>/dev/null)"
        if [ "$c_ps" = "$period_start" ] && [ "$c_fs" = "$five_start" ] && [ "$c_sig" = "$sig" ] \
            && [ $(( $(date +%s) - ${c_at:-0} )) -lt "$WEEK_CACHE_TTL_SECS" ] 2>/dev/null; then
            printf '%s\n%s\n' "$c_week" "$c_five"
            return 0
        fi
    fi
    # Aggregating readers partition by account uuid, never by directory
    # placement (state-dir contract v2). The default dir is the untagged
    # account s, but ten months of it predate account scoping — this log
    # holds twelve uuids, and without the filter the ledger draws all of
    # them as one account s week.
    # `|| true`: under `set -e` a bare `x=$(cmd)` aborts AT the assignment,
    # and jq exits nonzero on a missing profile.cache — which is the normal
    # state before the first fetch.
    local acct=""
    acct=$(jq -r '.account.uuid // empty' "$CLAUDE_ACCOUNT_DIR/profile.cache" 2>/dev/null) || true
    local scan week five
    scan=$( cat_usage_corpus \
        | jq -sr --argjson ps "$period_start" --argjson w "$WEEK_CELLS" \
                 --arg acct "$acct" \
                 --argjson fs "$five_start" --argjson fw "$FIVE_CELLS" --argjson fc "$FIVE_CELL_SECS" '
            def wkey: .five_hour.resets_at | sub("\\.[0-9]+";"") | sub("\\+00:00";"Z")
                      | fromdateiso8601 | . / 300 | round * 300;
            def span: (map(.t) | min | tostring) + " " + (map(.t) | max | tostring);
            [ .[] | select(.five_hour.resets_at)
                  | select($acct == "" or (.user.uuid // "") == $acct) ] as $all
            | ( $all
                | map(select(.seven_day.utilization != null and .timestamp >= $ps)
                      | { k: (wkey - 18000), t: .timestamp, s: .seven_day.utilization })
                | if length == 0 then "" else
                    span + " " +
                    (group_by(.k) | map({ slot: ((.[0].k - $ps) / 18000 | floor),
                                          cost: ((map(.s) | max) - (map(.s) | min)) })
                     | map(select(.slot >= 0 and .slot < $w))
                     | map("\(.slot):\(.cost)") | join(","))
                  end ) as $week
            | ( if $fs == 0 then "" else
                  $all
                  | map(select(.five_hour.utilization != null and .timestamp >= $fs)
                        | { k: (wkey - 18000), t: .timestamp, u: .five_hour.utilization })
                  | map(select(.k == $fs)) | sort_by(.t)
                  | if length == 0 then "" else
                      . as $a
                      | span + " " +
                        ( [ foreach range(0; length) as $i ({m: 0};
                              .prev = .m | .m = ([.m, $a[$i].u] | max)
                              | .b = ((($a[$i].t - $fs) / $fc) | floor) | .d = (.m - .prev);
                              {b: .b, d: .d}) ]
                          | map(select(.d > 0 and .b >= 0 and .b < $fw))
                          | group_by(.b) | map({ b: .[0].b, c: (map(.d) | add) })
                          | map("\(.b):\(.c)") | join(",") )
                    end
                end ) as $five
            | $week, $five' 2>/dev/null)
    week=$(printf '%s\n' "$scan" | sed -n 1p)
    five=$(printf '%s\n' "$scan" | sed -n 2p)
    local tmp="${wc}.tmp.$$"
    if jq -nc --argjson ps "$period_start" --argjson fs "$five_start" --arg sig "$sig" \
          --argjson at "$(date +%s)" --arg week "$week" --arg five "$five" \
          '{period_start:$ps,five_start:$fs,log_sig:$sig,at:$at,week:$week,five:$five}' >"$tmp" 2>/dev/null; then
        mv -f "$tmp" "$wc" 2>/dev/null || rm -f "$tmp"
    else
        rm -f "$tmp"
    fi
    printf '%s\n%s\n' "$week" "$five"
}

week_history_cells() { week_scan "$1" "${2:-0}" | sed -n 1p; }
five_history_cells() { week_scan "$1" "$2" | sed -n 2p; }

# The slot where burn exhausts the pool before reset (-1 = none). The learned
# walk speaks first (gap in HOURS before reset); with no trained forecast fall
# back to the linear projection claude.py's cap_eta uses, so a wall visible on
# one surface is visible on the other. Both wait out SEVEN_DAY_YOUNG_SECS —
# a guess drawn across a window that opened an hour ago comes from last
# week's burn, and this surface does not draw what it cannot see. Since the
# future cells stopped taking the × overwrite, this slot only decides the
# folded token's glyph (`...×` vs `...▯`) — kept, because the early-week
# fold is exactly where no per-cell shape exists to say it.
week_dry_slot() {
    local seven_int="$1" seven_secs="$2" now="$3" period_start="$4"
    local dry_epoch="" walk_gap walk_end elapsed7
    read -r walk_gap walk_end <<<"$(_seven_day_walk "$seven_int" "$seven_secs")"
    elapsed7=$(( SEVEN_DAY_WINDOW_SECS - seven_secs ))
    if [ -n "$walk_gap" ] && [ "$walk_gap" != "-1" ] && [ "$walk_gap" -gt 0 ] 2>/dev/null; then
        dry_epoch=$(( now + seven_secs - walk_gap * 3600 ))
    elif [ "$seven_int" -gt 0 ] 2>/dev/null \
         && [ "$elapsed7" -ge "$SEVEN_DAY_YOUNG_SECS" ] 2>/dev/null; then
        dry_epoch=$(( now + elapsed7 * (100 - seven_int) / seven_int ))
    fi
    if [ -n "$dry_epoch" ] && [ "$dry_epoch" -lt $(( now + seven_secs )) ] 2>/dev/null; then
        echo $(( (dry_epoch - period_start) / 18000 ))
    else
        echo -1
    fi
}

# The colored strip. Args: fill percent (for the pressure tint), now,
# period start, dry cell (-1 none), history line ("lo hi slot:cost,..."),
# cell count, cell seconds, day-gaps flag, how much future to draw (0 all;
# N keep N hollow cells then fold), the number the fold token prints —
# windows AHEAD of the current one, counted from real clocks by the caller;
# the strip must not re-derive it, since a 34-cell grid spans 170h against a
# 168h period and a count read off the drawing disagrees with the budget
# sentence beside it — an optional now-cell (-1: derive it from
# the period start, which is what a grid-aligned strip wants), and finally
# the learned hour multipliers ("" unlearned): with them, a future ▯ whose
# cell is mostly rest hours draws dim (see REST_SLOT_AWAKE_MIN_SECS).
# Cells and gaps come out of one awk so the row is one string with a color
# run per role.
build_ledger_strip() {
    local pct="$1" now="$2" ps="$3" dry="$4" hist="$5" cells_n="$6" cell_secs="$7" gaps="${8:-0}" fut="${9:-0}"
    local nleft="${10:-0}" nowslot_in="${11:--1}" mults="${12:-}"
    local span_lo="" span_hi="" cells=""
    [ -n "$hist" ] && read -r span_lo span_hi cells <<<"$hist"
    local fill_color tzoff_s
    fill_color=$(get_usage_color "$pct")
    tzoff_s=$(date +%z | awk '{ s=substr($0,1,1)=="-"?-1:1; h=substr($0,2,2)+0; m=substr($0,4,2)+0; print s*(h*3600+m*60) }')
    awk -v w="$cells_n" -v cs="$cell_secs" -v ps="$ps" -v now="$now" -v dry="$dry" \
        -v gaps="$gaps" -v tz="$tzoff_s" -v fut="$fut" \
        -v minhide="$WEEK_FUTURE_MIN_HIDE" -v unfoldmax="$WEEK_FUTURE_UNFOLD_MAX" \
        -v nleft="$nleft" -v mult="$MULT_GLYPH" \
        -v nsin="$nowslot_in" -v mults="$mults" -v restmult="$REST_MULT_MAX" \
        -v lo="${span_lo:--1}" -v hi="${span_hi:--1}" -v cells="$cells" \
        -v C_FILL="$fill_color" -v C_DIM="$DIM" -v C_NOW="$BOLD" \
        -v C_DRY="$RED" -v C_OFF="$RESET" -v BASE="$LEDGER_BASE_GLYPH" '
        # One ladder, one Unicode block: BASE (▁) is the zero line and real
        # burn starts at ▂ — see LEDGER_BASE_GLYPH for why the baseline may
        # not come from a different block. Buckets above ▅ are unchanged, so
        # a fully burned 5h window (~11 7d points) still reads ▆.
        function glyph(c) {
            if (c < 1)  return BASE
            if (c <= 2) return "▂"; if (c <= 4)  return "▃"; if (c <= 7)  return "▄"
            if (c <= 11) return "▅"; if (c <= 15) return "▆"
            if (c <= 20) return "▇"; return "█"
        }
        # Awake seconds of the cell starting at t0: the same hour arithmetic
        # awake_secs walks, inlined because a fork per cell is 34 forks per
        # render. hm[] is 1-based (split); an empty mults string leaves
        # have_rest 0 and no cell ever asks.
        function cell_awake(t0,    t2, end2, lt2, seg2, aw2) {
            end2 = t0 + cs; aw2 = 0; t2 = t0
            while (t2 < end2) {
                lt2 = t2 + tz
                seg2 = t2 + 3600 - (lt2 % 3600)
                if (seg2 > end2) seg2 = end2
                if (hm[int((lt2 % 86400) / 3600) + 1] + 0 >= restmult) aw2 += seg2 - t2
                t2 = seg2
            }
            return aw2
        }
        BEGIN {
            n = split(cells, a, ",")
            for (i = 1; i <= n; i++) { split(a[i], kv, ":"); cost[kv[1]] = kv[2] }
            have_rest = (split(mults, hm, " ") == 24)
            nowslot = (nsin >= 0 ? nsin : int((now - ps) / cs))
            # fold the future tail — but only when folding pays: the token is
            # nine columns, and a future of unfoldmax cells or fewer costs no
            # more drawn in full while carrying the rest shape the token
            # cannot (see WEEK_FUTURE_UNFOLD_MAX)
            lim = w
            if (fut > 0 && nleft > 0 && w - (nowslot + 1) > unfoldmax \
                && w - (nowslot + 1 + fut) >= minhide)
                lim = nowslot + 1 + fut
            s = ""; prev = ""; pday = -1
            for (i = 0; i < lim; i++) {
                start = ps + i * cs
                # a thin gap where a local calendar day begins, in HISTORY only:
                # days read as clusters (a day with 5 windows shows it) without
                # a ruler; the run from ▮ onward stays contiguous — a gap right
                # after the now-marker read as a phantom cell
                if (gaps && i <= nowslot) {
                    day = int((start + tz) / 86400)
                    if (i > 0 && i < nowslot && day != pday) { s = s C_OFF " "; prev = "" }
                    pday = day
                }
                if (i < nowslot) {
                    # a sampled sub-1% cell and an idle one both mean "cost
                    # nothing": one glyph, one tint, no colour-only meaning
                    if (i in cost)                              { g = glyph(cost[i]); c = (g == BASE ? C_DIM : C_FILL) }
                    else if (lo >= 0 && lo <= start + cs && start <= hi) { g = BASE; c = C_DIM }
                    else                                        { g = "░"; c = C_DIM }
                } else if (i == nowslot)                        { g = "▮"; c = C_NOW }
                else {
                    # a window still ahead — dim when the learned rhythm says
                    # the reader sleeps through most of it (under half the
                    # cell awake). Unlearned, every ▯ stays plain. A dry
                    # projection used to overwrite these as red × — v0.33
                    # made the 5h strip a record, not a forecast, and the
                    # unfold put the same question to this one: a run of ×
                    # was read as three DELETED windows (measured, live,
                    # 2026-09-01), while the guess it drew was already owned
                    # by the pinned notice with an exact time. Same answer
                    # here now: a future cell is a slot, never a verdict;
                    # only the fold token below still carries the dry mark.
                    g = "▯"; c = ""
                    if (have_rest && 2 * cell_awake(start) < cs) c = C_DIM
                }
                if (c != prev) { s = s C_OFF c; prev = c }
                s = s g
            }
            if (lim < w) {
                # the fold: glyph = how the tail ends (× red when the pool
                # dries before the reset), count = the 5h windows ahead of the
                # one you are in — the same number the budget line prices, not
                # the number of cells this fold happens to hide.
                # No apostrophes in here: this comment lives inside a
                # single-quoted awk program.
                if (dry >= 0 && dry < w) { tg = "×"; tc = C_DRY }
                else                     { tg = "▯"; tc = C_DIM }
                s = s C_OFF tc "..." tg "(" mult nleft ")"
            }
            print s C_OFF
        }'
}

# 7d strip: 34 ✕ 5h cells from the period start, day-gapped. $5 is
# week_history_cells' line; $6 folds the future tail after that many kept
# cells (the live row passes WEEK_FUTURE_KEEP; the `week` report draws all and
# never folds); $7 is windows_ahead, the number the fold token prints. $8 is
# a test seam: the hour multipliers, read from the learned profile when the
# caller does not say (an UNSET $8, not an empty one — "" is how a test
# states "unlearned" against a fixture that would otherwise speak).
build_week_strip() {
    local mults="${8-$(hour_profile_mults)}"
    build_ledger_strip "$1" "$2" "$3" "$4" "$5" "$WEEK_CELLS" 18000 1 "${6:-0}" "${7:-0}" -1 "$mults"
}

# 5h strip: the five hours of the current window, always all five. $4 is
# five_history_cells' line, $5 the seconds still on the window.
#
# The hollow run after ▮ is the hours left — the reason the grid is fixed —
# but there is no dry cell in it: a × here would be a forecast, and the badge
# (`5h[38%@23:00]`) plus the "5h caps ~14:20" notice already own that warning
# with better gates and an exact time. Fixed width also means the row does not
# reflow every hour, which is the difference between an axis and a bar that
# grows at you.
#
# A dim hollow hour is NOT a forecast of the pool — it is the reader's own
# learned rhythm (an hour they are usually asleep for), the same rule the 7d
# cells apply at half-the-cell: for a 1h cell that is 1800 awake seconds.
# `▃▮▯▯▯` with the last two dim says the window outlives the evening.
#
# ▮ rides the real clock, not the grid. five_period_start rounds to 5 minutes
# so week_scan's cache key holds still across renders (a resets_at that jitters
# by a second would re-run a whole-log jq pass every render), and that rounding
# offsets every hour boundary by up to 2½ minutes. Invisible in a bar height;
# wrong exactly where this strip is read. With the marker at 4 - floor(left/1h)
# the hollow count IS the whole hours remaining, to the second: three hours and
# one minute left never draws as two.
build_five_strip() {
    local nowslot=$(( 4 - ${5:-0} / 3600 ))
    [ "$nowslot" -lt 0 ] && nowslot=0
    [ "$nowslot" -gt $((FIVE_CELLS - 1)) ] && nowslot=$((FIVE_CELLS - 1))
    local mults="${6-$(hour_profile_mults)}"
    build_ledger_strip "$1" "$2" "$3" -1 "$4" "$FIVE_CELLS" "$FIVE_CELL_SECS" 0 0 0 "$nowslot" "$mults"
}

# Does a history line carry at least one cell BEFORE the now-cell? A single
# sample in the current cell (every render logs one now) draws nothing but
# ░░░▮ — auto mode stays quiet until there is a past to show.
ledger_has_past() {
    local hist="$1" now="$2" ps="$3" cell_secs="$4"
    [ -n "$hist" ] || return 1
    local lo hi cells nowslot slot pair
    read -r lo hi cells <<<"$hist"
    nowslot=$(( (now - ps) / cell_secs ))
    # coverage that started before this cell means an earlier cell ran (idle or not)
    [ -n "$lo" ] && [ "$lo" -lt $(( ps + nowslot * cell_secs )) ] 2>/dev/null && return 0
    IFS=, read -ra pairs <<<"$cells"
    for pair in "${pairs[@]}"; do
        slot="${pair%%:*}"
        [ "$slot" -lt "$nowslot" ] 2>/dev/null && return 0
    done
    return 1
}

# How much of a window must have run before its own numbers may project:
# 5% of its length (5h -> 15m, 7d -> ~8.4h, the fraction seven_day_elapsed
# has always called the noise floor). One rule with one caller-supplied
# length, because the alternative is a constant per surface and surfaces
# that disagree about the same window — which is exactly how a 10-minute-old
# 5h window came to draw `▮▯×××` while the pace suffix on the same row
# judged itself too young to speak.
window_evidence_floor() {
    echo $(( $1 / 20 ))
}

# The current 5h window's start on the 5-min grid (its resets_at - 5h).
five_period_start() {
    local now="$1" five_secs="$2"
    echo $(( ( (now + five_secs - 18000 + 150) / 300 ) * 300 ))
}

# Tail of a strip: pace and the axis label of its right end (the reset).
# pace = used / elapsed-fraction; >1✕ means the pool caps before the reset.
# Dim below 1✕, pressure-tinted from 1✕ (status lane), hidden while the
# window is too young to judge — window_evidence_floor, the one rule the 5h
# dry cells and the caps notice also wait on: 5% of the window's own length,
# so 5h waits 15m and 7d waits ~8.4h (the fraction seven_day_elapsed calls
# noisy). A flat 15m was right for 5h and nonsense for a week: an hour into a
# fresh window, 2% of the pool divided by 0.6% of the time printed 3✕ in red.
# Reset is wall
# clock: `@04:00` inside 24h, `@Wed 09:00` beyond — an axis label for a
# timeline that ends there. $5 = "hide" drops it: when the badge above
# already carries that reset, printing it again spends columns to say
# nothing (one badge per fact, in both directions).
strip_tail() {
    local pct="$1" secs_left="$2" length="$3" now="$4" reset_mode="${5:-show}"
    local out="" elapsed=$(( length - secs_left )) min_elapsed
    min_elapsed=$(window_evidence_floor "$length")
    if [ "$elapsed" -ge "$min_elapsed" ] && [ "$pct" -gt 0 ] 2>/dev/null; then
        local pace tint band
        pace=$(awk -v u="$pct" -v e="$elapsed" -v l="$length" 'BEGIN{ printf "%.1f", (u/100)/(e/l) }')
        band=$(awk -v p="$pace" 'BEGIN{ print (p>=1.5?2:(p>=1.0?1:0)) }')
        case "$band" in 2) tint="$RED" ;; 1) tint="$YELLOW" ;; *) tint="$DIM" ;; esac
        out=" ${tint}${pace}${MULT_GLYPH}${RESET}"
    fi
    if [ "$reset_mode" = "hide" ]; then
        printf '%s' "$out"
        return 0
    fi
    local when
    if [ "$secs_left" -lt 86400 ]; then
        when=$(_fmt_epoch $(( now + secs_left )) '%H:%M')
    else
        when=$(_fmt_epoch $(( now + secs_left )) '%a %H:%M')
    fi
    printf '%s %s@%s%s' "$out" "$DIM" "$when" "$RESET"
}

# The live row: `5h ▂▅█▮▯ 0.6✕ @04:00  7d ▅▁▂▃▅ ▁▃▅▃▃ …▮▯▯...▯(✕11) 0.7✕ @Wed 09:00` under the badges — this
# sitting at the left, the week at the right, one grammar. Prints nothing
# when there is no live window, or — in auto mode — when the log holds no
# sample for either period yet (a row of ░░░▮▯▯ says nothing the badges do
# not already say; the row earns its height only once it carries where the
# points went). Freeze-safe by construction: ▮ moves at cell boundaries,
# every other cell is history.
build_week_row() {
    local usage_data="$1" mode="${2:-auto}" five_reset_mode="${3:-show}" seven_reset_mode="${4:-show}"
    [ "$mode" != "off" ] || return 0
    [ -n "$usage_data" ] || return 0
    local five_util five_reset seven_util seven_reset
    eval "$(echo "$usage_data" | jq -r '
        @sh "five_util=\(.five_hour.utilization // 0)",
        @sh "five_reset=\(.five_hour.resets_at // "")",
        @sh "seven_util=\(.seven_day.utilization // 0)",
        @sh "seven_reset=\(.seven_day.resets_at // "")"
    ' 2>/dev/null)"
    local five_int seven_int five_secs seven_secs now
    five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
    seven_int=$(printf '%.0f' "$seven_util" 2>/dev/null || echo 0)
    five_secs=$(get_reset_seconds "$five_reset")
    seven_secs=$(get_reset_seconds "$seven_reset")
    now=$(date +%s)
    local have_seven=0 have_five=0 period_start=0 five_start=0
    [ -n "$seven_secs" ] && [ "$seven_secs" -gt 0 ] 2>/dev/null && have_seven=1
    [ -n "$five_secs" ] && [ "$five_secs" -gt 0 ] 2>/dev/null && have_five=1
    [ "$have_seven" = 1 ] || [ "$have_five" = 1 ] || return 0
    [ "$have_seven" = 1 ] && period_start=$(week_period_start "$now" "$seven_secs")
    [ "$have_five" = 1 ] && five_start=$(five_period_start "$now" "$five_secs")
    local week_hist="" five_hist=""
    if [ "$have_seven" = 1 ]; then
        mapfile -t _scan < <(week_scan "$period_start" "$five_start")
        week_hist="${_scan[0]:-}"; five_hist="${_scan[1]:-}"
    else
        five_hist=$(five_history_cells 0 "$five_start")
    fi
    if [ "$mode" != "always" ]; then
        ledger_has_past "$week_hist" "$now" "$period_start" 18000 \
            || ledger_has_past "$five_hist" "$now" "$five_start" "$FIVE_CELL_SECS" \
            || return 0
    fi
    local parts=""
    if [ "$have_five" = 1 ]; then
        parts="${DIM}5h ${RESET}$(build_five_strip "$five_int" "$now" "$five_start" "$five_hist" "$five_secs")$(strip_tail "$five_int" "$five_secs" 18000 "$now" "$five_reset_mode")"
    fi
    if [ "$have_seven" = 1 ]; then
        local dry
        dry=$(week_dry_slot "$seven_int" "$seven_secs" "$now" "$period_start")
        [ -n "$parts" ] && parts="$parts  "
        parts="${parts}${DIM}7d ${RESET}$(build_week_strip "$seven_int" "$now" "$period_start" "$dry" "$week_hist" "$WEEK_FUTURE_KEEP" "$(windows_ahead "$seven_secs" "${five_secs:-0}")")$(strip_tail "$seven_int" "$seven_secs" "$SEVEN_DAY_WINDOW_SECS" "$now" "$seven_reset_mode")"
    fi
    printf '%b' "$parts"
}

run_week() {
    local uc="$CLAUDE_ACCOUNT_DIR/usage.cache"
    if [ ! -f "$uc" ]; then
        echo "week: no usage.cache under $CLAUDE_ACCOUNT_DIR"
        return 3
    fi
    local usage seven_util seven_reset fetched
    usage=$(cat "$uc")
    eval "$(echo "$usage" | jq -r '
        @sh "seven_util=\(.seven_day.utilization // 0)",
        @sh "seven_reset=\(.seven_day.resets_at // "")",
        @sh "fetched=\(.fetched_at // 0)"
    ' 2>/dev/null)"
    local seven_int seven_secs
    seven_int=$(printf '%.0f' "$seven_util" 2>/dev/null || echo 0)
    seven_secs=$(get_reset_seconds "$seven_reset")
    if [ -z "$seven_secs" ] || [ "$seven_secs" -le 0 ] 2>/dev/null; then
        echo "week: no active 7d window in usage.cache"
        return 3
    fi
    local now age stale=""
    now=$(date +%s)
    age=$((now - ${fetched:-0}))
    [ "$age" -gt 3600 ] 2>/dev/null && stale=" (stale $(format_duration $((age * 1000))))"

    local period_start hist dry strip
    period_start=$(week_period_start "$now" "$seven_secs")
    hist=$(week_history_cells "$period_start")
    dry=$(week_dry_slot "$seven_int" "$seven_secs" "$now" "$period_start")
    strip=$(build_week_strip "$seven_int" "$now" "$period_start" "$dry" "$hist")

    # the row carries its own remaining/reset, like every other window row:
    # a wider bar, not a separate surface (no ruler, no day labels)
    local label tail
    label=$(printf '7d %3d%% ' "$seven_int")
    tail=$(printf '  %-8s @%s' \
        "$(format_duration $((seven_secs * 1000)))" \
        "$(_fmt_epoch $((now + seven_secs)) '%a %H:%M')")
    # the strip carries its own per-role colors (burn / idle / unknown / dry)
    printf '%s%b\n' "$label" "${strip}${DIM}${tail}${RESET}${stale}"

    local indent="        " # 8 = width of the "7d NNN% " label column

    # the budget line under the strip: the advisor, always-mode, so calm
    # weeks still show runway/ration/landing; pressure clauses show as-is
    local last_model
    last_model=$(last_logged_model)
    local advisor
    advisor=$(notice_long_line "$(notice_collect "$usage" always "$last_model")")
    [ -n "$advisor" ] && printf '%s%b\n' "$indent" "$advisor"
    return 0
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
#   budget       no sigil, dim       the week's resting reading; it interrupts
#                                    nothing, so it wears no mark
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
#   fb capped · back ~Thu 07:00           running model's weekly_scoped limit
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
#   7d on pace to leave ~62% unused · go heavier
#                                         mid-week underuse, engaged sessions
#                                         only — reaches exactly the users
#                                         who can act on it
#   budget ~19✕5h left · ~13 awake · even 1.6%/win · lands ~52%
#                                         always-mode calm line (shared
#                                         budget frame with claude.py's
#                                         watch advisor); the awake clause
#                                         appears only once the hour shape
#                                         is learned and only when it cuts
#                                         the count, and it names the
#                                         denominator `even` divides by; in
#                                         the last window: budget last window ·
#                                         N% left · lands ~M%
# ---------------------------------------------------------------------------
# The notice engine. Readers below turn the account's live numbers into
# NOTICES: one record per thing worth saying, each carrying both a short
# form (pinned beside the ledgers on row 2) and a long one (row 3, which
# fades). A record is
#
#   rank  voice  scope  key  hl  short  long
#
#   rank   value order; the top surviving record owns row 2
#   voice  !red / !yellow pressure · + opportunity · - budget (dim, no sigil)
#   scope  5h / 7d / fb / acct — one voice per scope per frame, so two
#          clauses about the same window can never disagree
#   key    identity of the CONDITION, not of the text: row 3 shows a notice
#          only while its key is new to this session (NOTICE_FLASH_SECS),
#          so a long explanation arrives once and then gets out of the way
#   hl     the substring worth bolding — the number the reader acts on
#
# Every notice derives from a badge line 1 already shows, and never repeats
# a number the row it sits on carries (the strips print their own resets).
# ---------------------------------------------------------------------------
# Fields are separated by US (0x1f), never by a tab: tab is IFS whitespace,
# so bash collapses runs of it and ONE empty field silently shifts every
# field after it (a notice with no highlight token lost its long form).
NOTICE_FS=$'\037'
NOTICE_RECS=()
notice_add() {
    NOTICE_RECS+=("$1$NOTICE_FS$2$NOTICE_FS$3$NOTICE_FS$4$NOTICE_FS$5$NOTICE_FS$6$NOTICE_FS$7")
}

notice_voice_color() {
    case "$1" in
    '!red') printf '%s' "$RED" ;;
    '!yellow') printf '%s' "$YELLOW" ;;
    '+') printf '%s' "$CYAN" ;;
    *) printf '%s' "$DIM" ;;
    esac
}

# Bold the number the reader acts on, then restore the voice colour — \033[22m
# clears bold AND faint, so the dim budget voice must be re-stated after it.
notice_highlight() {
    local text="$1" tok="$2" color="$3"
    if [ -z "$tok" ] || [[ "$text" != *"$tok"* ]]; then
        printf '%s' "$text"
        return 0
    fi
    printf '%s%s%s%s%s%s' "${text%%"$tok"*}" "$BOLD" "$tok" "$NO_BOLD" "$color" "${text#*"$tok"}"
}

# A sigil marks a voice that INTERRUPTS: `!` you are about to hit something,
# `+` there is capacity to take. The budget voice interrupts nothing — it is
# the week's resting reading — and a leading `-` on a dim line reads as a
# bullet, which turned the pin into the first item of a list that had no
# second item. Dim is the mark; the sentence carries itself.
notice_render() {
    local voice="$1" hl="$2" text="$3" color sigil=''
    color=$(notice_voice_color "$voice")
    case "$voice" in '!'*) sigil='! ' ;; '+') sigil='+ ' ;; esac
    printf '%s%s%s%s' "$color" "$sigil" "$(notice_highlight "$text" "$hl" "$color")" "$RESET"
}

# First time THIS session saw a condition (stamping it if new). Wall-clock
# epochs, so a frozen frame ages honestly instead of replaying the flash.
notice_first_seen() {
    local key="$1" state="$2" now="$3" ts=""
    if [ -f "$state" ]; then
        ts=$(awk -F'\t' -v k="$key" '$1 == k { print $2; exit }' "$state" 2>/dev/null)
    fi
    if [ -z "$ts" ]; then
        ts="$now"
        # the group's exit status is its LAST command: a bare `[ -f ] && tail`
        # made every first-ever stamp look like a failed write, so nothing was
        # ever remembered and the flash never faded
        {
            printf '%s\t%s\n' "$key" "$now"
            if [ -f "$state" ]; then tail -12 "$state"; fi
        } >"${state}.tmp.$$" 2>/dev/null \
            && mv -f "${state}.tmp.$$" "$state" 2>/dev/null || rm -f "${state}.tmp.$$"
    fi
    printf '%s' "$ts"
}

# Sorted, deduped by scope: the highest-ranked record for each window wins.
notice_ranked() {
    [ "${#NOTICE_RECS[@]}" -gt 0 ] || return 0
    printf '%s\n' "${NOTICE_RECS[@]}" | sort -t"$NOTICE_FS" -k1,1nr | awk -F"$NOTICE_FS" '!seen[$3]++'
}

# Row 2's pinned voice: the top record's short form. Stays as long as the
# condition holds — a pin, not a flash.
notice_pin_line() {
    local records="$1" rank voice scope key hl short long
    [ -n "$records" ] || return 0
    IFS="$NOTICE_FS" read -r rank voice scope key hl short long <<<"$(printf '%s\n' "$records" | sed -n 1p)"
    [ -n "$short" ] || return 0
    notice_render "$voice" "$hl" "$short"
}

# The full sentence. The status row rations columns; a terminal command
# (`--check`, `--week`) has a line to spend, so it gets the long form.
notice_long_line() {
    local records="$1" rank voice scope key hl short long
    [ -n "$records" ] || return 0
    IFS="$NOTICE_FS" read -r rank voice scope key hl short long <<<"$(printf '%s\n' "$records" | sed -n 1p)"
    [ -n "$long" ] || return 0
    notice_render "$voice" "$hl" "$long"
}

# Row 3: the same engine's long form, but only while the condition is new to
# this session. It says the part that does not fit beside the ledgers, then
# disappears and leaves the pin. Never echoes the pin's own sentence: record
# one IS the pin, so the flash starts at record two. A calm start has one
# thing to say and says it once — two rows, not the same sentence twice at
# two lengths.
notice_flash_line() {
    local records="$1" state="$2" now="${3:-$(date +%s)}"
    [ -n "$records" ] || return 0
    local pin_key="" first=1
    while IFS="$NOTICE_FS" read -r rank voice scope key hl short long; do
        [ -n "$key" ] || continue
        if [ "$first" = 1 ]; then pin_key="$key"; first=0; fi
        [ "$key" = "$pin_key" ] && continue
        [ -n "$long" ] || continue
        local seen age
        seen=$(notice_first_seen "$key" "$state" "$now")
        age=$((now - seen))
        [ "$age" -le "$NOTICE_FLASH_SECS" ] 2>/dev/null || continue
        notice_render "$voice" "$hl" "$long"
        return 0
    done <<<"$records"
    return 0
}

# Is the flash still worth a row after the width took its bite? The old rule
# asked whether it beat the PIN by NOTICE_FLASH_MIN_GAIN columns, which made
# sense only while row 3 restated row 2 — once the flash became a different
# notice, that subtraction compared two unrelated sentences and dropped a
# short one whenever the pin happened to be long. The question is absolute:
# `7d dry ~Wed` has spent a row to say nothing you can act on, `7d dry ~Wed
# 19:50` still carries the number.
notice_flash_worth_row() {
    [ "${#1}" -ge "$NOTICE_FLASH_MIN_CHARS" ]
}

# Read the account's live numbers and emit every notice they justify.
# Order below is the order the old advisor spoke in — pressure first, so the
# `pressure` gate still mutes the "go heavier" family; rank decides what the
# reader actually sees.
notice_collect() {
    local usage_data="$1" mode="${2:-auto}" current_model="${3:-}"
    NOTICE_RECS=()
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

    local five_int seven_int five_secs seven_secs now
    five_int=$(printf '%.0f' "$five_util" 2>/dev/null || echo 0)
    seven_int=$(printf '%.0f' "$seven_util" 2>/dev/null || echo 0)
    five_secs=$(get_reset_seconds "$five_reset")
    seven_secs=$(get_reset_seconds "$seven_reset")
    now=$(date +%s)
    local surplus=$((100 - seven_int))

    local pressure=0 week_slack=0

    # Weekly limit scoped to the model THIS session runs (limits[]
    # kind=weekly_scoped, same substring match as the fb[N%] badge), plus the
    # roomiest OTHER scoped model — the one worth switching to.
    local scope_name="" scope_int="" scope_secs="" alt_name="" alt_int=""
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
            local alt_tsv
            alt_tsv=$(echo "$usage_data" | jq -r --arg m "$scope_name" '
                [.limits[]? | select(.kind == "weekly_scoped" and (.scope.model.display_name // "") != "")
                 | {n: (.scope.model.display_name | ascii_downcase), p: (.percent // 0)}]
                | map(select(.n != $m)) | sort_by(.p) | first // empty
                | [.n, (.p | floor)] | @tsv' 2>/dev/null)
            [ -n "$alt_tsv" ] && IFS=$'\t' read -r alt_name alt_int <<<"$alt_tsv"
        fi
    fi
    local scope_ab="" alt_ab=""
    [ -n "$scope_name" ] && scope_ab=$(model_scope_abbrev "$scope_name")
    [ -n "$alt_name" ] && alt_ab=$(model_scope_abbrev "$alt_name")

    # An out-of-band 7d move: utilization falling INSIDE one window instance
    # (same resets_at) is not burn running backwards — it is a plan upgrade
    # or a support-side reset re-basing the denominator. Worth saying,
    # because every projection below (and the ledger's history) still
    # describes the old period. Tracked per account, stamped once, and
    # newsworthy for NOTICE_REBASE_SECS.
    local rebase_from="" rebase_to="" rebase_at=""
    if [ -n "$seven_secs" ] && [ "$seven_secs" -gt 0 ] 2>/dev/null && [ -d "${CLAUDE_ACCOUNT_DIR:-}" ]; then
        local seen_file="$CLAUDE_ACCOUNT_DIR/seven_seen"
        local cur_reset=$(( ((now + seven_secs) + 150) / 300 * 300 ))
        local p_reset="" p_util="" p_at="" p_from="" p_to=""
        [ -f "$seen_file" ] && IFS=$'\t' read -r p_reset p_util p_at p_from p_to <"$seen_file"
        if [ "$p_reset" = "$cur_reset" ] && [ -n "$p_util" ] \
           && [ "$seven_int" -le $((p_util - NOTICE_REBASE_DROP_PCT)) ] 2>/dev/null; then
            rebase_from="$p_util" rebase_to="$seven_int" rebase_at="$now"
        elif [ -n "$p_at" ] && [ "$p_reset" = "$cur_reset" ] \
             && [ $((now - p_at)) -le "$NOTICE_REBASE_SECS" ] 2>/dev/null; then
            rebase_from="$p_from" rebase_to="$p_to" rebase_at="$p_at"
        fi
        if [ "$p_reset" != "$cur_reset" ] || [ "$p_util" != "$seven_int" ]; then
            printf '%s\t%s\t%s\t%s\t%s\n' "$cur_reset" "$seven_int" "${rebase_at:-}" \
                "${rebase_from:-}" "${rebase_to:-}" >"$seen_file.tmp.$$" 2>/dev/null \
                && mv -f "$seen_file.tmp.$$" "$seen_file" 2>/dev/null || rm -f "$seen_file.tmp.$$"
        fi
    fi

    # --- pressure: a wall between here and a reset -------------------------

    # The running model's weekly limit is spent: that model is gone until it
    # comes back, and the one number that matters is when. No recovery
    # suppression — an imminent return makes the time MORE useful.
    if [ -n "$scope_int" ] && [ "$scope_int" -ge 100 ] 2>/dev/null \
       && [ -n "$scope_secs" ] && [ "$scope_secs" -gt 0 ] 2>/dev/null; then
        local back_str
        back_str=$(_fmt_epoch $((now + scope_secs)) '%a %H:%M')
        if [ -n "$back_str" ]; then
            local alt_part=""
            [ -n "$alt_ab" ] && [ -n "$alt_int" ] && alt_part=" · ${alt_ab} ${alt_int}% still open"
            notice_add 100 '!red' fb "fb.capped.${scope_ab}" "~${back_str}" \
                "${scope_ab} capped ~${back_str}" \
                "${scope_ab} capped · back ~${back_str}${alt_part}"
            pressure=1
        fi
    fi

    # 5h cap projection. Gate = the 5h badge's own pressure gate (>= 80),
    # recovery-suppressed exactly like its colour. At 100% line 1 already
    # says capped; only the fleet hint still helps there.
    if [ "$five_int" -ge 80 ] && [ "$five_int" -lt 100 ] \
       && [ -n "$five_secs" ] && [ "$five_secs" -gt "$FIVE_HOUR_RECOVERY_SECS" ] 2>/dev/null; then
        local elapsed=$((18000 - five_secs)) floor
        floor=$(window_evidence_floor 18000)
        if [ "$elapsed" -ge "$floor" ]; then
            local cap_secs=$(( (100 - five_int) * elapsed / five_int ))
            if [ "$cap_secs" -lt "$five_secs" ]; then
                local cap_hhmm gap voice='!yellow'
                cap_hhmm=$(_fmt_epoch $((now + cap_secs)) '%H:%M')
                gap=$(format_duration $(( (five_secs - cap_secs) * 1000 )))
                [ "$five_int" -ge 90 ] && voice='!red'
                if [ -n "$cap_hhmm" ]; then
                    notice_add 90 "$voice" 5h "5h.caps.${cap_hhmm}" "~${cap_hhmm}" \
                        "5h caps ~${cap_hhmm}" \
                        "5h caps ~${cap_hhmm}, ${gap} before reset"
                    pressure=1
                fi
            fi
        fi
    fi

    # Where the running model's weekly quota runs out, if it does before its
    # own reset. Held as a fact, not a sentence: the steering reader below
    # wants to carry it.
    #
    # The LEARNED scoped walk speaks first, exactly as it does for the account
    # 7d. Linear pace can only measure the week so far, and a week whose
    # Tuesday burns 39%/day and whose Sunday burns 6%/day is not a line. That
    # is the difference between "you are at 84%" on a quiet Thursday and
    # "Fable runs out Monday, two days before it comes back" — one is a
    # number, the other is a decision. It only ever speaks for the scope its
    # profile was built from: which model carries the weekly cap is
    # Anthropic's choice and has changed before, and one model's weekday shape
    # is not another's. Cold, it falls back to the old linear math behind the
    # badge's own >= 80 gate.
    local sc_str="" sc_gap="" sc_voice='!yellow'
    if [ -n "$scope_int" ] && [ "$scope_int" -gt 0 ] && [ "$scope_int" -lt 100 ] 2>/dev/null \
       && [ -n "$scope_secs" ] && [ "$scope_secs" -gt "$SEVEN_DAY_RECOVERY_SECS" ] 2>/dev/null; then
        local sc_cap="" sc_prof_lc
        sc_prof_lc=$(scoped_profile_name | tr '[:upper:]' '[:lower:]')
        if [ -n "$sc_prof_lc" ] && [ "$sc_prof_lc" = "$scope_name" ]; then
            local sw_level sw_gap
            read -r sw_level sw_gap <<<"$(scoped_forecast "$scope_int" "$scope_secs")"
            if [ -n "$sw_level" ] && [ "${sw_gap:-0}" -gt 0 ] 2>/dev/null; then
                sc_cap=$((scope_secs - sw_gap * 3600))
                [ "$sw_level" = "red" ] && sc_voice='!red'
            fi
        fi
        if [ -z "$sc_cap" ] && [ "$scope_int" -ge 80 ] 2>/dev/null; then
            local sc_elapsed=$((SEVEN_DAY_WINDOW_SECS - scope_secs))
            [ "$sc_elapsed" -gt 0 ] && sc_cap=$(( (100 - scope_int) * sc_elapsed / scope_int ))
            [ "$scope_int" -ge 90 ] && sc_voice='!red'
        fi
        if [ -n "$sc_cap" ] && [ "$sc_cap" -ge 0 ] 2>/dev/null \
           && [ "$sc_cap" -lt "$scope_secs" ] 2>/dev/null; then
            local sc_gap_secs=$((scope_secs - sc_cap))
            sc_str=$(_fmt_epoch $((now + sc_cap)) '%a %H:%M')
            if [ "$sc_gap_secs" -ge 172800 ]; then
                sc_gap="$((sc_gap_secs / 86400))d"
            else
                sc_gap=$(format_duration $((sc_gap_secs * 1000)))
            fi
        fi
    fi

    # 7d dry projection. The learned weekday forecast speaks first (it can
    # warn on a calm Friday about your heavy Tuesday); cold start falls back
    # to linear pace, and only when seven_day_pace already warns. Recovery
    # (<= 12h out) stays quiet — the surplus notice owns that zone.
    if [ "$seven_int" -gt 0 ] && [ "$seven_int" -lt 100 ] \
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
            local dry_str gap_str tail voice='!yellow'
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
            [ "$sev_level" = "red" ] && voice='!red'
            if [ -n "$dry_str" ]; then
                notice_add 85 "$voice" 7d "7d.${sev_verb}.${dry_str}" "~${dry_str}" \
                    "7d ${sev_verb} ~${dry_str} · ${tail#then }" \
                    "7d ${sev_verb} ~${dry_str}, ${gap_str} before reset · ${tail}"
                pressure=1
            fi
        fi
    fi

    # --- the week's mechanism: what the numbers MEAN together --------------

    # The denominator moved under us.
    if [ -n "$rebase_at" ] && [ -n "$rebase_from" ] && [ -n "$rebase_to" ]; then
        notice_add 80 '+' 7d "7d.rebase.${rebase_at}" "${rebase_from}%→${rebase_to}%" \
            "7d rebased ${rebase_from}%→${rebase_to}%" \
            "7d fell ${rebase_from}%→${rebase_to}% inside one window · plan change or an out-of-band reset; the ledger still draws the old period"
    fi

    # The model caps before the account does. Line 1 shows both numbers but
    # not their relation, and the relation is the whole decision: switching
    # models buys the week's remaining capacity back.
    local fb_spoken=0
    if [ -n "$scope_int" ] && [ "$scope_int" -lt 100 ] 2>/dev/null \
       && [ "$scope_int" -ge "$NOTICE_SCOPE_MIN_PCT" ] \
       && [ $((scope_int - seven_int)) -ge "$NOTICE_SCOPE_LEAD_PCT" ] 2>/dev/null; then
        local steer_short steer_long steer_voice='+'
        steer_short="${scope_ab} ${scope_int}% vs 7d ${seven_int}%"
        steer_long="${scope_ab} weekly ${scope_int}% against 7d ${seven_int}%"
        # a projected wall makes this pressure, not an invitation
        if [ -n "$sc_str" ]; then
            steer_voice="$sc_voice"
            steer_long="${steer_long}, dry ~${sc_str}"
            pressure=1
        fi
        steer_long="${steer_long} · the model caps first, not the account"
        if [ -n "$alt_ab" ] && [ -n "$alt_int" ] && [ "$alt_int" -lt "$scope_int" ] 2>/dev/null; then
            steer_short="${steer_short} · go ${alt_ab}"
            steer_long="${steer_long}; ${alt_ab} sits at ${alt_int}%, so run it for the bulk and keep ${scope_ab} for what needs it"
        else
            steer_short="${steer_short} · spread the load"
            steer_long="${steer_long}, so spread the bulk while the week still has room"
        fi
        notice_add 78 "$steer_voice" fb "fb.steer.$((scope_int / 5))" "${scope_ab} ${scope_int}%" \
            "$steer_short" "$steer_long"
        fb_spoken=1
    fi

    # No steering to do (the account is just as deep), so the deadline stands
    # on its own.
    if [ "$fb_spoken" = 0 ] && [ -n "$sc_str" ]; then
        notice_add 72 "$sc_voice" fb "fb.caps.${sc_str}" "~${sc_str}" \
            "${scope_ab} caps ~${sc_str}" \
            "${scope_ab} caps ~${sc_str}, ${sc_gap} before reset"
        pressure=1
    fi

    # The other way round: the ACCOUNT caps first, and the model's remaining
    # points expire in a pool nothing can reach them from. Both counters run
    # from the same reset instant, so their live ratio is this week's mix
    # rate — no history, no cache field, just the two numbers line 1 already
    # shows. Measured at 81/63: mix 0.78 against 0.77 mined from the corpus.
    # It is the mirror of the steering notice above and cannot coexist with
    # it — that one needs the model ahead of the account, this one needs the
    # account ahead of the model.
    #
    # Rank 58: above the 5h tail, below the fleet hint, and never above the
    # 7d pressure that CAUSES it. The pairing this is built for is the dry
    # warning pinned on row 2 with the strand flashing on row 3.
    if [ -z "$sc_str" ] && [ -z "$rebase_at" ] \
       && [ -n "$scope_int" ] && [ "$scope_int" -ge "$SCOPE_MIX_MIN_SCOPE" ] 2>/dev/null \
       && [ "$scope_int" -lt 100 ] 2>/dev/null \
       && [ "$seven_int" -ge "$SCOPE_MIX_MIN_7D" ] && [ "$seven_int" -lt 100 ] \
       && [ -n "$scope_secs" ] && [ -n "$seven_secs" ] && [ "$seven_secs" -gt 0 ] 2>/dev/null \
       && [ $((SEVEN_DAY_WINDOW_SECS - seven_secs)) -ge "$SEVEN_DAY_YOUNG_SECS" ] 2>/dev/null; then
        # One wall, or no ratio: the two pools have always reset together to
        # the microsecond, but Anthropic could split them someday, and a mix
        # taken across two different weeks is a fluent lie.
        local wall_gap=$((scope_secs - seven_secs))
        [ "$wall_gap" -lt 0 ] && wall_gap=$((-wall_gap))
        if [ "$wall_gap" -le "$SCOPE_SAME_WALL_SEC" ]; then
            # One division, not two. Both numbers land on one line beside the
            # total they must add to, so the strand is the REMAINDER of what
            # the mix reaches, never its own rounding.
            local mix_left=$((100 - scope_int))
            local mix_reach=$(( ((100 - seven_int) * scope_int + seven_int / 2) / seven_int ))
            local mix_strand=$((mix_left - mix_reach))
            if [ "$mix_strand" -ge "$SCOPE_STRAND_MIN_PCT" ] 2>/dev/null; then
                notice_add 58 '+' fb "fb.strand.$((mix_strand / 5))" "~${mix_strand}%" \
                    "${scope_ab} ~${mix_strand}% expires at this mix" \
                    "7d caps before ${scope_ab}: this mix reaches ~${mix_reach}% of its ${mix_left}% left · run ${scope_ab} heavier to extract more"
            fi
        fi
    fi

    # Expiring surplus — use it or lose it. Inside the last day of the 7d
    # window a big green remainder is forfeiture, not headroom. The tail is
    # feasibility-checked against the learned pct_per_window ratio: burning
    # is rate-capped by the 5h mechanism, so "spend it" appears only when
    # full-tilt burn can actually consume the surplus.
    if [ "$seven_int" -gt 0 ] && [ -n "$seven_secs" ] && [ "$seven_secs" -gt 0 ] 2>/dev/null \
       && [ "$seven_secs" -le "$ADVISOR_EXPIRY_HORIZON_SECS" ] 2>/dev/null \
       && [ "$surplus" -ge "$ADVISOR_SURPLUS_MIN_PCT" ]; then
        local when tail="" ppw reachable=""
        when=$(format_reset_absolute "$seven_reset")
        ppw=$(forecast_pct_per_window)
        if [ -n "$ppw" ]; then
            # Two legs: the window you are in (time-limited by its own reset,
            # rate-limited by its own headroom) and everything after it. The
            # TIME terms are awake seconds once the rhythm is learned —
            # "spend it" at 23:00 was advice to burn a week of surplus
            # through eight hours of sleep. Unlearned, the legs are wall
            # seconds and the arithmetic is exactly what it was.
            local leg_secs="$seven_secs" rest_secs=0 hour_mults
            if [ "${five_secs:-0}" -gt 0 ] 2>/dev/null \
               && [ "$five_secs" -lt "$seven_secs" ] 2>/dev/null; then
                leg_secs="$five_secs"; rest_secs=$(( seven_secs - five_secs ))
            fi
            hour_mults=$(hour_profile_mults)
            if [ -n "$hour_mults" ]; then
                local awake_leg awake_rest=0
                awake_leg=$(awake_secs "$hour_mults" 0 "$leg_secs")
                [ "$rest_secs" -gt 0 ] && awake_rest=$(awake_secs "$hour_mults" "$leg_secs" "$seven_secs")
                leg_secs="$awake_leg"; rest_secs="$awake_rest"
            fi
            reachable=$(awk -v ppw="$ppw" -v leg="$leg_secs" -v rest="$rest_secs" -v fu="$five_int" 'BEGIN{
                cap = ppw * (100 - fu) / 100          # current window headroom
                l = ppw * leg / 18000                 # time-limited until 5h reset
                r = (l < cap ? l : cap) + ppw * rest / 18000
                printf "%d", int(r + 0.5)
            }')
        fi
        if [ -n "$reachable" ]; then
            if [ "$reachable" -ge "$surplus" ] 2>/dev/null; then
                tail=" · spend it"
            else
                tail=" · ~$((surplus - reachable))% expires even at full burn"
            fi
        fi
        if [ -n "$when" ]; then
            week_slack=1
            # Inside the FINAL 5h window the mechanism itself is the story:
            # no later window exists to spend the remainder through, so the
            # feasibility tail lands on a harder fact and outranks the plain
            # last-day form.
            if [ "$seven_secs" -le 18000 ] 2>/dev/null; then
                local left7
                left7=$(format_duration $((seven_secs * 1000)))
                notice_add 75 '+' 7d "7d.lastwin.$((surplus / 5))" "${surplus}%" \
                    "last 5h of the week · ${surplus}% unused${tail}" \
                    "7d resets in ${left7}: the last 5h window of the period · ${surplus}% of the week is unused and expires with it${tail}"
            else
                notice_add 65 '+' 7d "7d.surplus.$((surplus / 5))" "${surplus}%" \
                    "${surplus}% unused${tail}" \
                    "7d resets @${when}, ${surplus}% unused${tail}"
            fi
        fi
    fi

    # Fleet relief: once this account's 5h is spent, the useful fact is which
    # sibling isn't.
    if [ "$five_int" -ge 90 ] && [ -n "${ACCOUNT_TAG:-}" ]; then
        local hint
        hint=$(build_advisor_fleet_hint "${STATUSLINE_HOME}/accounts" "$ACCOUNT_TAG")
        if [ -n "$hint" ]; then
            notice_add 60 '+' acct "acct.fleet.${hint%% *}" "${hint%% *}" \
                "$hint" "this account's 5h is spent · ${hint}"
        fi
    fi

    # Underuse: on pace to strand a large chunk of the subscription. Speaks
    # only in an engaged, unsqueezed session — it reaches exactly the person
    # who can act on it and never nags an idle one. Muted right after a
    # rebase: the learned walk still describes the old denominator.
    if [ "$pressure" = 0 ] && [ -z "$rebase_at" ] && [ "$seven_int" -gt 0 ] \
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
            local waste=$((100 - heading))
            week_slack=1
            notice_add 50 '+' 7d "7d.underuse.$((waste / 5))" "~${waste}%" \
                "~${waste}% will expire · go heavier" \
                "7d on pace to leave ~${waste}% unused · go heavier"
        fi
    fi

    # This 5h window is closing with room still on it. On its own that is
    # not waste — the 5h window is a rate limit, not a budget, and unused
    # room costs nothing. It matters only when the WEEK is heading to strand
    # capacity: the weekly pool can only be spent through 5h windows, so a
    # half-used window is throughput you cannot get back. Hence the gate on
    # week_slack, set by the surplus / last-window / underuse readers above.
    if [ "$week_slack" = 1 ] && [ "$pressure" = 0 ] \
       && [ -n "$five_secs" ] && [ "$five_secs" -gt 0 ] 2>/dev/null \
       && [ "$five_secs" -le "$NOTICE_TAIL_SECS" ] 2>/dev/null \
       && [ "$five_int" -gt 0 ] && [ $((100 - five_int)) -ge "$NOTICE_TAIL_MIN_UNUSED" ]; then
        local left5 next5
        left5=$(format_duration $((five_secs * 1000)))
        next5=$(_fmt_epoch $((now + five_secs)) '%H:%M')
        notice_add 55 '+' 5h "5h.tail.$((five_secs / 600))" "~${left5}" \
            "5h ~${left5} left · $((100 - five_int))% unused" \
            "this 5h window closes in ${left5} with $((100 - five_int))% unused · the week's surplus can only be spent through windows like it"
    fi

    # Calm budget: the week in one breath — runway, what even looks like,
    # where you land. Shared frame with ccpace's watch advisor.
    if [ "$mode" = "always" ] && [ "$seven_int" -gt 0 ] && [ "$seven_int" -lt 100 ] \
       && [ -n "$seven_secs" ] && [ "$seven_secs" -gt 0 ] 2>/dev/null; then
        # windows AHEAD, not including the one you are in — the same number
        # the 7d row folds into `...▯(✕N)`, so the two halves of one row never
        # need arbitrating. "left" means still to come.
        local windows elapsed7=$((SEVEN_DAY_WINDOW_SECS - seven_secs))
        windows=$(windows_ahead "$seven_secs" "${five_secs:-0}")
        # Where the week actually ends up. The learned walk answers it from
        # YOUR weekday shape; linear pace is the fallback once a day has run,
        # and it can only ever restate the week so far. Two different
        # questions share this line and the grammar has to keep them apart:
        # `even N%/win` is the RATION (spend this per window and the pool
        # lands exactly on 100), `lands ~N%` is the PREDICTION (spend like
        # you have been and you land here). "heading" said neither — a
        # direction is not a destination, and the reader was left deciding
        # which of the two numbers beside it was the forecast.
        local lands="" lands_part="" walk_gap walk_end
        read -r walk_gap walk_end <<<"$(_seven_day_walk "$seven_int" "$seven_secs")"
        if [ -n "$walk_end" ]; then
            lands="$walk_end"
        elif [ "$elapsed7" -ge 86400 ]; then
            lands=$((seven_int * SEVEN_DAY_WINDOW_SECS / elapsed7))
            [ "$lands" -gt 100 ] && lands=100
        fi
        [ -n "$lands" ] && lands_part=" · lands ~${lands}%"
        # Row 2 gets the runway and the LANDING, not the runway and the
        # ration. Of the three clauses the long form carries, the landing is
        # the only one the reader cannot derive from the badges above: the
        # count is on the strip beside it (`...▯(✕9)`) and the ration is
        # surplus ÷ that count. It is also the one that answers the question
        # a calm week actually asks — not "how do I ration this" but "am I
        # going to strand it". Cold, with no landing to state, the ration is
        # the best short form there is and the line falls back to it.
        local short_tail=""
        if [ "$windows" -le 0 ]; then
            notice_add 10 '-' acct "acct.budget.last" "${surplus}%" \
                "last window · ${surplus}% left" \
                "budget last window · ${surplus}% left${lands_part}"
        else
            # How many of those windows you are actually awake for. A window
            # you sleep through is not capacity you can spend, and a ration
            # that divides by it is a number nobody can hit. Clamped to the
            # calendar count — the two describe the same future and must
            # never disagree about it — and spoken only when it REFINES it:
            # equal counts would spend a clause to say nothing.
            local awake_n="" awake_part="" den="$windows" hour_mults asecs
            hour_mults=$(hour_profile_mults)
            asecs=$(awake_secs "$hour_mults" "${five_secs:-0}" "$seven_secs")
            if [ -n "$asecs" ]; then
                awake_n=$(( (asecs + 17999) / 18000 ))
                [ "$awake_n" -gt "$windows" ] && awake_n="$windows"
                if [ "$awake_n" -lt "$windows" ]; then
                    den="$awake_n"
                    # At zero the awake clause and the ration both go: there
                    # is no denominator, and "~0 awake" is a sentence about
                    # the next eight hours pretending to be one about the
                    # week. The landing still speaks.
                    [ "$awake_n" -gt 0 ] && awake_part=" · ~${awake_n} awake"
                else
                    awake_n=""
                fi
            fi
            local even="" even_part=""
            if [ "$den" -gt 0 ] 2>/dev/null; then
                even=$(awk -v h="$surplus" -v w="$den" 'BEGIN{printf "%.1f", h/w}')
                even_part=" · even ${even}%/win"
            fi
            # 0 ahead is the only "last window": the week ends inside the one
            # you are in, and there is nothing to divide the surplus across.
            # At 1 the line keeps the count and the grammar — `1✕5h left ·
            # 25.0%/win` says the same thing the N-window form says, and
            # calling two windows the last one to save a redundant clause is
            # the wrong trade.
            if [ -n "$lands" ]; then short_tail="lands ~${lands}%"
            elif [ -n "$even" ]; then short_tail="${even}%/win"; fi
            local short_line="${windows}${MULT_GLYPH}5h left"
            [ -n "$short_tail" ] && short_line="${short_line} · ${short_tail}"
            notice_add 10 '-' acct "acct.budget.${windows}" "${windows}${MULT_GLYPH}5h" \
                "$short_line" \
                "budget ~${windows}${MULT_GLYPH}5h left${awake_part}${even_part}${lands_part}"
        fi
    fi

    notice_ranked
}

# The pinned row-2 voice. Kept as the advisor's public name: same signature,
# same "echo a line or nothing" contract, now backed by the notice engine.
build_advisor_line() {
    local usage_data="$1" mode="${2:-auto}" current_model="${3:-}"
    notice_pin_line "$(notice_collect "$usage_data" "$mode" "$current_model")"
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

# Deadman chip: surfaces thevibeworks/deadman — a dead man's switch that
# hands the session off when you stop responding. `deadman chip <sid>` is a
# single fast file read printing `armed 42m` (counting down to the handoff),
# `warned 3m` (phone warning sent), `due` (fire imminent/overdue), or nothing
# when no switch is armed. The tool may not be installed at all, and absence
# must cost nothing: the builtin `command -v` gate is the only spend before
# bailing — no subshell, no render. Keyed on stdin_session_id (the session the
# CLI reports for THIS render), never a cached/derived id. Armed is calm
# bookkeeping (DIM, neutral); warned/due mean the handoff is close — STATUS-
# lane yellow. The ☠ glyph (U+2620) is a single-column text-presentation
# character — same rationale as CACHE_GLYPH — so the padding math holds; do
# not add U+FE0F, which would flip it to a double-width emoji.
build_deadman_component() {
    if [ "$deadman_display_mode" = "off" ] || [ -z "$stdin_session_id" ]; then
        return 0
    fi
    command -v deadman >/dev/null 2>&1 || return 0
    local chip
    chip=$(deadman chip "$stdin_session_id" 2>/dev/null) || return 0
    [ -n "$chip" ] || return 0
    case "$chip" in
    armed*) echo " ${DIM}[☠ ${chip}]${RESET}" ;;
    *)      echo " ${YELLOW}[☠ ${chip}]${RESET}" ;;
    esac
}

deadman_info=$(build_deadman_component)

# cctrace trace chip: is this session's wire being captured, and where does
# the live UI serve? Session identity, so it lives on the LEFT with path and
# branch (structure lane, dim — red stays reserved for pressure). Detection,
# strongest signal first:
#   CCTRACE_SERVER_PORT / CCTRACE_TRACE_FILE   cctrace >= 0.29 exports trace
#                                              identity into the child env
#   NODE_EXTRA_CA_CERTS under a cctrace dir    older mitm captures leave only
#                                              proxy plumbing behind
#   DEVA_TRACE=1                               deva --trace says so outright
# Without the port env (old cctrace), the live-instance registry
# (<data-dir>/instances/*.json, a documented contract) is matched by this
# session's id, then by project path, then by being the only live capture.
# The registry stores session ids REDACTED past the first 8 hex
# ("c3a6e0f3-****-…" — capture-time redaction, ids never land on disk in
# full), so the sid8 prefix is the join key — the same convention cctrace's
# own UI uses. The id match trusts any non-tombstone entry (if OUR capture
# died, this session's proxy died with it); the path/only-live fallbacks
# trust only heartbeat-fresh files (<2min, heartbeat is 30s) — crashed runs
# leave "live" entries behind for up to a day, and a stale port is worse
# than no port. No match still shows the bare chip: "recorded" matters
# even portless.
build_trace_url() {
    local port="${CCTRACE_SERVER_PORT:-}"
    local traced=""
    [ -n "$port" ] && traced=1
    [ -n "${CCTRACE_TRACE_FILE:-}" ] && traced=1
    case "${NODE_EXTRA_CA_CERTS:-}" in
    */cctrace/*) traced=1 ;;
    esac
    [ "${DEVA_TRACE:-}" = "1" ] && traced=1
    [ -n "$traced" ] || return 0

    if [ -z "$port" ]; then
        local reg="${CCTRACE_DATA_DIR:-}"
        if [ -z "$reg" ]; then
            case "${NODE_EXTRA_CA_CERTS:-}" in
            */cctrace/*) reg=$(dirname "$(dirname "$NODE_EXTRA_CA_CERTS")") ;;
            *) reg="$CLAUDE_HOME/.local/share/cctrace" ;;
            esac
        fi
        reg="$reg/instances"
        if [ -d "$reg" ]; then
            port=$(cat "$reg"/*.json 2>/dev/null | jq -rs --arg sid "${stdin_session_id:-}" '
                [ .[] | select(type == "object" and .endedAt == null) ]
                | map(select(($sid | length) >= 8 and
                             ((.sessionId // "")[0:8] == $sid[0:8])))
                | first.port // empty' 2>/dev/null)
            if [ -z "$port" ]; then
                port=$(find "$reg" -name '*.json' -newermt '-120 seconds' 2>/dev/null \
                    | xargs cat 2>/dev/null | jq -rs --arg cwd "${current_dir:-}" '
                    [ .[] | select(type == "object" and .endedAt == null) ] as $fresh |
                    (($fresh | map(select(.projectPath == $cwd and $cwd != ""))) +
                     (if ($fresh | length) == 1 then $fresh else [] end))
                    | first.port // empty' 2>/dev/null)
            fi
        fi
    fi

    # Full URL so terminals linkify it. DEVA_TRACE_UI_URL is the
    # host-reachable URL deva exports on create/reattach (deva#547) —
    # the container-side port is not what the host browser can reach,
    # so it wins over anything derived locally.
    #
    # Path: /s/<sid8> (cctrace >= 0.40) jumps straight to THIS session's
    # conversation, scrolled to the newest turn — the sid8 prefix is the
    # same join key the registry match above uses, and it keeps the link
    # exact even when the server also carries other sessions (a resume,
    # a deadman -p run). Without a session id there is no session to name,
    # so fall back to the plain live page.
    local upath="/trace"
    [ -n "${stdin_session_id:-}" ] && upath="/s/${stdin_session_id:0:8}"
    if [ -n "${DEVA_TRACE_UI_URL:-}" ]; then
        echo "${DEVA_TRACE_UI_URL%/}${upath}"
    elif [ -n "$port" ]; then
        echo "http://localhost:${port}${upath}"
    else
        echo "cctrace"
    fi
}

# The chip: the URL itself when there is one (terminals linkify a bare
# URL; the widest-supported form), the bare word when the port is unknown.
build_trace_component() {
    local u
    u=$(build_trace_url)
    [ -n "$u" ] || return 0
    echo " ${DIM}[${u}]${RESET}"
}

# trace_url is kept for the degrade path in format_output: when line 1 will
# not fit the terminal, the URL text collapses to `[cctrace]` carrying the
# same target as an OSC 8 hyperlink — 9 columns instead of ~35, still one
# click where the terminal supports it (iTerm2, kitty, WezTerm, ...).
trace_url=$(build_trace_url)
trace_info=""
trace_info_short=""
if [ -n "$trace_url" ]; then
    trace_info=" ${DIM}[${trace_url}]${RESET}"
    case "$trace_url" in
    http*) trace_info_short=" ${DIM}[$(printf '\033]8;;%s\a%s\033]8;;\a' "$trace_url" cctrace)]${RESET}" ;;
    *)     trace_info_short="$trace_info" ;;
    esac
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
    # A reported window is authoritative in both directions: 200k from the
    # CLI on a default-1M family means the user turned 1M off
    # (CLAUDE_CODE_DISABLE_1M_CONTEXT) and the bar is already re-based to
    # 200k — the tag must not contradict it. The name only decides when
    # the CLI sent no window at all.
    if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
        [ "$ctx_size" -gt 200000 ]
        return
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

# Subcommand dispatch. Sits here on purpose: every function a subcommand
# needs is defined above, and none of the per-session render work (fetches,
# state writes, component building) has started below. Subcommands are
# read-only against the state dir.
if [ -n "$subcommand" ]; then
    case "$subcommand" in
    report) run_usage_report "${report_days:-28}"; exit $? ;;
    check) run_check; exit $? ;;
    session-summary) run_session_summary; exit $? ;;
    week) run_week; exit $? ;;
    esac
    exit 0
fi

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
        # Fable abbreviates to a 4-char family + version: fabl5. It started
        # single-component (claude-fable-5) and grew a minor with Fable 5.1
        # (claude-fable-5-1 -> fabl5.1). A minor is one or two digits; a
        # longer component is a date suffix and must not become ".20260115".
        local rest="${m#claude-fable-}"
        local major="${rest%%-*}"
        local minor=""
        if [[ "$rest" == *-* ]]; then
            minor="${rest#*-}"
            minor="${minor%%-*}"
        fi
        case "$minor" in
        [0-9]|[0-9][0-9]) echo "fabl${major}.${minor}" ;;
        *)                echo "fabl${major}" ;;
        esac
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
        # Claude Code hands 5h/7d on stdin every render (merged below), so
        # the API is only asked for what stdin lacks — the model-scoped
        # weekly limit and extra usage — which move at the week's pace,
        # not the sitting's: no need for the 30 s hot-window cadence.
        if [ -n "$rl_five_pct" ] || [ -n "$rl_seven_pct" ]; then
            [ "$ttl" -lt "$STDIN_RL_FETCH_TTL" ] && ttl=$STDIN_RL_FETCH_TTL
        fi
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
            [ "$test_mode" = true ] || log_stdin_snapshot "${stdin_session_id:-}" "$rl_five_pct" "$rl_five_reset" "$rl_seven_pct" "$rl_seven_reset"
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
        [ "$test_mode" = true ] || log_stdin_snapshot "${stdin_session_id:-}" "$rl_five_pct" "$rl_five_reset" "$rl_seven_pct" "$rl_seven_reset"
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

# Renders line 1 and records its actual width in line1_cols: the advisor row
# right-aligns to THAT edge, not to term_width — when the width guess is
# wrong (tput's flat 80 under a pipe) line 1 overflows its phantom edge, and
# anchoring line 2 on the same phantom left it dangling mid-line.
line1_cols=0

# Visible text of a rendered fragment: SGR color codes and OSC 8 hyperlink
# wrappers stripped (both are zero-width on screen).
plain_text() {
    printf '%b' "$1" | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b]8;;[^\x07\x1b]*\(\x07\|\x1b\\\)//g'
}

# Line 1 must FIT: Claude Code truncates or wraps a row wider than the
# terminal (COLUMNS is handed to the script for exactly this), and a wrapped
# line 1 leaves every anchored row beneath the wrong edge. Degrade in value
# order before overflowing: the trace URL text collapses to a short linked
# chip (when even a 1-column gap would not fit the full URL), then the
# path/stats gap goes to 1. LINE1_MARGIN is what the status area keeps for
# itself beside COLUMNS.
LINE1_MARGIN=5
format_output() {
    local path_part="${DIM}${display_path}${RESET}${git_info}${trace_info}${deadman_info}"
    local stats_part="${right_parts}"

    local path_plain stats_plain
    path_plain=$(plain_text "$path_part")
    stats_plain=$(plain_text "$stats_part")

    if [ -n "$trace_info_short" ] && [ "$trace_info_short" != "$trace_info" ] \
        && [ $((${#path_plain} + ${#stats_plain} + 1 + LINE1_MARGIN)) -gt "$term_width" ] 2>/dev/null; then
        path_part="${DIM}${display_path}${RESET}${git_info}${trace_info_short}${deadman_info}"
        path_plain=$(plain_text "$path_part")
        debug_log "LINE1: trace chip collapsed to fit ${term_width} cols"
    fi

    case "$alignment" in
    "left-right")
        local padding=$((term_width - ${#path_plain} - ${#stats_plain} - LINE1_MARGIN))
        [ $padding -lt 1 ] && padding=1
        line1_cols=$((${#path_plain} + padding + ${#stats_plain}))
        printf "%b%*s%b\n" "$path_part" $padding "" "$stats_part"
        ;;
    "right-left")
        local padding=$((term_width - ${#path_plain} - ${#stats_plain} - LINE1_MARGIN))
        [ $padding -lt 1 ] && padding=1
        line1_cols=$((${#stats_plain} + padding + ${#path_plain}))
        printf "%b%*s%b\n" "$stats_part" $padding "" "$path_part"
        ;;
    "center")
        local total_len=$((${#path_plain} + ${#stats_plain}))
        if [ $total_len -lt $((term_width - 10)) ]; then
            local left_padding=$(((term_width - ${#path_plain}) / 2))
            local right_padding=$((term_width - left_padding - ${#path_plain} - ${#stats_plain}))
            [ $right_padding -lt 2 ] && right_padding=2
            line1_cols=$((left_padding + ${#path_plain} + right_padding + ${#stats_plain}))
            # leading pad survives Claude Code's per-row trim only behind a
            # zero-width code (see print_row_block)
            printf "%b%*s%b%*s%b\n" "$RESET" $left_padding "" "$path_part" $right_padding "" "$stats_part"
        else
            local padding=$((term_width - ${#path_plain} - ${#stats_plain} - LINE1_MARGIN))
            [ $padding -lt 1 ] && padding=1
            line1_cols=$((${#path_plain} + padding + ${#stats_plain}))
            printf "%b%*s%b\n" "$path_part" $padding "" "$stats_part"
        fi
        ;;
    *)
        local padding=$((term_width - ${#path_plain} - ${#stats_plain} - LINE1_MARGIN))
        [ $padding -lt 1 ] && padding=1
        line1_cols=$((${#path_plain} + padding + ${#stats_plain}))
        printf "%b%*s%b\n" "$path_part" $padding "" "$stats_part"
        ;;
    esac
}

format_output

# Extra rows: each further stdout line renders as its own row in Claude
# Code's status area, and printing nothing produces no row — so a quiet row
# costs zero height. The rows hang as ONE block under the badges: the block's
# right edge meets line 1's ACTUAL rendered edge (line1_cols, recorded by
# format_output — not term_width, which lies under a pipe), and every row in
# the block shares one left edge, so the widest row touches the badges and
# the others read flush-left beside it (ragged right, the way text reads;
# a ragged LEFT edge under a fixed right one is a staircase). A lone row is
# the block, so it right-anchors as before. When the stats sit left
# (right-left alignment) the block stays left with them.
#
# Claude Code trims each stdout line before rendering (`.trim()` per row,
# 2.1.234) — bare leading spaces never reach the screen, which is why the
# rows sat flush-left for a while. A zero-width SGR reset ahead of the
# padding is not whitespace, so the padding survives the trim and the
# renderer (Ink, wrap=truncate) keeps it. Nerd-hacky, verified live.
# Shorten a sentence to fit `avail` columns by dropping its LAST segment,
# cutting at the RIGHTMOST joint of any weight — `; ` (a second voice),
# ` · ` (a tail clause), `, ` (a sub-fact) — so each pass gives up as little
# as possible and the leading fact is the last thing to go:
# "! 5h caps ~05:18, 52m before reset; 7d dry ~Thu 09:00 · then hard stop"
# -> "... 7d dry ~Thu 09:00" -> "... 52m before reset" -> "! 5h caps ~05:18".
# Width is what the terminal SHOWS: cutting a rendered sentence at a joint
# keeps its colour runs (and the bolded number) intact, and a joint never
# occurs inside an escape sequence. A hard cut with `…` only when no joint
# is left; fails (rc 1) under 16 columns, where nothing honest fits.
ADVISOR_MERGE_MIN_COLS=16
compact_text() {
    local text="$1" avail="$2" sep vis head best
    [ "$avail" -ge "$ADVISOR_MERGE_MIN_COLS" ] 2>/dev/null || return 1
    vis=$(plain_text "$text")
    while [ "${#vis}" -gt "$avail" ]; do
        best=""
        for sep in '; ' ' · ' ', '; do
            [[ "$text" == *"$sep"* ]] || continue
            head="${text%"$sep"*}"
            [ "${#head}" -gt "${#best}" ] && best="$head"
        done
        [ -n "$best" ] || break
        text="$best"
        vis=$(plain_text "$text")
    done
    if [ "${#vis}" -gt "$avail" ]; then
        text="${vis:0:$((avail - 1))}…"
    fi
    printf '%s' "$text"
}

extra_rows=()
queue_row() {
    local row="$1" tag="$2"
    [ -n "$row" ] || return 0
    debug_log "$tag: $(plain_text "$row")"
    extra_rows+=("$row")
}
print_row_block() {
    [ "${#extra_rows[@]}" -gt 0 ] || return 0
    local anchor max block_w=0 left=0 i plain color
    anchor=$((line1_cols > 0 ? line1_cols : term_width - LINE1_MARGIN))
    # a line 1 wider than a KNOWN terminal edge is cut there by Claude Code;
    # meet it at the edge. A guessed width (pipe, tput's flat 80) may be low
    # — there line 1's own edge stays the anchor, as before.
    if [ "$term_width_trusted" = 1 ] && [ "$anchor" -gt $((term_width - LINE1_MARGIN)) ]; then
        anchor=$((term_width - LINE1_MARGIN))
    fi
    max=$((anchor > term_width - 1 ? anchor : term_width - 1))
    # single-hue-per-row truncation keeps a cut tail honest
    for i in "${!extra_rows[@]}"; do
        plain=$(plain_text "${extra_rows[$i]}")
        if [ "${#plain}" -gt "$max" ] 2>/dev/null && [ "$max" -gt 1 ]; then
            color=$(printf '%s' "${extra_rows[$i]}" | grep -o '^\\033\[[0-9;]*m' | head -1)
            plain="${plain:0:$((max - 1))}…"
            extra_rows[$i]="${color}${plain}${RESET}"
        fi
        [ "${#plain}" -gt "$block_w" ] && block_w=${#plain}
    done
    if [ "$alignment" != "right-left" ]; then
        left=$((anchor - block_w))
        [ "$left" -gt 0 ] 2>/dev/null || left=0
    fi
    for i in "${!extra_rows[@]}"; do
        if [ "$left" -gt 0 ]; then
            printf '%b%*s%b\n' "$RESET" "$left" "" "${extra_rows[$i]}"
        else
            printf '%b\n' "${extra_rows[$i]}"
        fi
    done
}

# Row order under the badges: evidence, then interpretation. The week row
# is where the 7d points went (one cell per 5h window); the notice engine
# says what to do about it. Reading down one column: 7d[44%@2d] -> the strip
# that spent those 44% -> the clause that projects the rest.
#
# A number line 1 already prints is not printed again below: the 5h badge
# always carries its reset while a window is live, the 7d badge carries one
# under pressure — so the matching strip drops its own `@HH:MM` and spends
# those columns on the message instead. The evidence is what line 1 actually
# rendered, not a re-derivation of the badges' own gates.
week_row=""
if [ "$week_display_mode" != "off" ] && [ -n "${usage_data:-}" ]; then
    line1_plain=$(plain_text "$right_parts")
    five_reset_mode="show" seven_reset_mode="show"
    [[ "$line1_plain" =~ 5h\[[0-9]+%@ ]] && five_reset_mode="hide"
    [[ "$line1_plain" =~ 7d\[[0-9]+%@ ]] && seven_reset_mode="hide"
    week_row=$(build_week_row "$usage_data" "$week_display_mode" "$five_reset_mode" "$seven_reset_mode")
    queue_row "$week_row" "WEEK"
fi

# The notice engine speaks under pressure or opportunity in auto mode; when
# the week row is showing, the calm budget voice joins it — the strips and
# the numbers derived from them are one unit. Collected once: the pin (row 2)
# and the flash (row 3) are two views of the same records.
advisor_line=""
notice_flash=""
if [ "$advisor_display_mode" != "off" ] && [ -n "${usage_data:-}" ]; then
    advisor_mode_now="$advisor_display_mode"
    [ "$advisor_mode_now" = "auto" ] && [ -n "$week_row" ] && advisor_mode_now="always"
    notice_records=$(notice_collect "$usage_data" "$advisor_mode_now" "${model_id:-$model_display}")
    advisor_line=$(notice_pin_line "$notice_records")
    [ "$notice_display_mode" != "off" ] && notice_flash=$(notice_flash_line "$notice_records" \
        "$CLAUDE_CACHE_DIR/${stdin_session_id:-global}_notice_seen")
fi

# Row 2 mirrors line 1 when it can: advice on the left, evidence on the
# right, the gap between them absorbing the width (exactly line 1's
# path/stats shape). The pinned sentence is compacted to the room line 1
# leaves beside the ledgers — rightmost joint first — so a calm frame is two
# rows, not three. No honest room (< 16 cols, narrow terminals) keeps the
# block: ledgers, then the full sentence beneath.
if [ -n "$advisor_line" ]; then
    merged=""
    if [ -n "$week_row" ]; then
        week_anchor=$((line1_cols > 0 ? line1_cols : term_width - LINE1_MARGIN))
        if [ "$term_width_trusted" = 1 ] && [ "$week_anchor" -gt $((term_width - LINE1_MARGIN)) ]; then
            week_anchor=$((term_width - LINE1_MARGIN))
        fi
        week_plain=$(plain_text "$week_row")
        avail=$((week_anchor - ${#week_plain} - 2))
        if [ "$alignment" != "right-left" ] \
           && advisor_short=$(compact_text "$advisor_line" "$avail"); then
            advisor_short_plain=$(plain_text "$advisor_short")
            merged="${advisor_short}${RESET}"
            merged+=$(printf '%*s' $((week_anchor - ${#week_plain} - ${#advisor_short_plain})) "")
            merged+="$week_row"
            extra_rows[0]="$merged"
            debug_log "PIN (merged): $advisor_short_plain"
        fi
    fi
    [ -z "$merged" ] && queue_row "$advisor_line" "PIN"
fi

# Row 3: the long form of whatever just became true, and only while it is
# new to this session (NOTICE_FLASH_SECS). It says the part that does not
# fit beside the ledgers, then gets out of the way — the pin above stays.
if [ -n "$notice_flash" ]; then
    flash_anchor=$((line1_cols > 0 ? line1_cols : term_width - LINE1_MARGIN))
    [ "$flash_anchor" -gt "$term_width" ] 2>/dev/null && flash_anchor=$term_width
    notice_flash=$(compact_text "$notice_flash" $((flash_anchor - 1)) || printf '%s' "$notice_flash")
    flash_plain=$(plain_text "$notice_flash")
    # a stub is not an explanation; see notice_flash_worth_row
    if notice_flash_worth_row "$flash_plain"; then
        queue_row "${notice_flash}${RESET}" "FLASH"
    fi
fi
print_row_block

if [ "$test_mode" = true ] && [ -n "$temp_transcript" ] && [ -f "$temp_transcript" ]; then
    rm -f "$temp_transcript"
fi
