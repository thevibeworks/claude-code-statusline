#!/bin/bash
# claude-watch — live usage/cost watcher for Claude Code sessions.
#
# Companion to statusline.sh. Where the statusline shows a single line in
# the prompt, claude-watch is a full-screen "top"-style view of one session:
# per-turn cost, token breakdown (input / output / cache read / cache
# creation), running session totals, and account-level 5h / 7d quota read
# from the shared usage cache that statusline.sh maintains.
#
# It reads three things, all read-only:
#   1. The session transcript (assistant message usage blocks)        <- per-turn tokens + cost
#   2. The account usage cache (~/.claude/statusline/usage.cache)      <- 5h / 7d quota
#   3. The account usage log    (~/.claude/statusline/usage.jsonl)     <- session/account history
#
# Cost is computed locally from per-million list pricing (mirrors ccx's
# internal/parser/pricing.go). It is an ESTIMATE: it uses public list
# pricing and does not model fast-mode surcharges. Treat it as a guide,
# not a bill.
#
# Usage:
#   claude-watch.sh [--session ID] [--transcript PATH] [--once] [--interval N] [--no-color]
#
# Run --help for full flag docs.

set -u

# --- Resolve claude home (shared with statusline.sh) ----------------------
# OrbStack sets $HOME to the macOS host path while credentials/state live
# in the Linux user's actual home. Mirror statusline.sh's resolution.
CLAUDE_HOME="$HOME"
if [ ! -d "$CLAUDE_HOME/.claude" ]; then
    _real_home=$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f6)
    [ -n "$_real_home" ] && [ -d "$_real_home/.claude" ] && CLAUDE_HOME="$_real_home"
fi

STATUSLINE_HOME="$CLAUDE_HOME/.claude/statusline"
CLAUDE_DATA_DIR="${CLAUDE_DATA_DIR:-$STATUSLINE_HOME}"
CLAUDE_ACCOUNT_DIR="$CLAUDE_DATA_DIR"
PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$CLAUDE_HOME/.claude}/projects"

# --- Defaults / flags -----------------------------------------------------
session_id=""
transcript_path=""
interval=3
run_once=false
use_color=true

usage() {
    cat <<'EOF'
claude-watch — live usage/cost watcher for Claude Code

USAGE:
  claude-watch.sh [OPTIONS]

OPTIONS:
  --session ID         Watch a specific session by id. Default: most
                       recently modified transcript for the current dir's
                       project (falls back to the newest transcript overall).
  --transcript PATH    Watch a specific transcript .jsonl file directly.
  --interval N         Refresh interval in seconds (default: 3).
  --once               Render a single snapshot and exit (no watch loop).
  --no-color           Disable ANSI colors.
  -h, --help           Show this help.

WHAT IT SHOWS:
  Model           Active model for the latest assistant turn.
  Last turn       Cost + input / output / cache-read / cache-create tokens
                  for the most recent assistant message.
  Session totals  Cumulative tokens and estimated cost across the transcript.
  Quota           5h / 7d account quota from the shared statusline cache.

NOTES:
  Cost is an ESTIMATE from public per-million list pricing (mirrors ccx).
  Fast-mode surcharges are not modeled. Read-only: never writes to your
  Claude Code state. Quota requires statusline.sh to have populated
  ~/.claude/statusline/usage.cache.

EXAMPLES:
  claude-watch.sh
  claude-watch.sh --session 45e79c47-5981-410c-baf9-c39c9de0d807
  claude-watch.sh --transcript ~/.claude/projects/-foo/abc.jsonl --interval 5
  claude-watch.sh --once --no-color
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --session)    session_id="$2"; shift 2 ;;
    --transcript) transcript_path="$2"; shift 2 ;;
    --interval)   interval="$2"; shift 2 ;;
    --once)       run_once=true; shift ;;
    --no-color)   use_color=false; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "claude-watch: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "claude-watch: jq required" >&2; exit 1; }

case "$interval" in
    ''|*[!0-9]*) echo "claude-watch: --interval must be a positive integer" >&2; exit 2 ;;
esac
[ "$interval" -lt 1 ] && interval=1

# --- Colors ---------------------------------------------------------------
if [ "$use_color" = true ] && [ -t 1 ]; then
    YELLOW='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'
    DIM='\033[2m'; CYAN='\033[0;36m'; MAGENTA='\033[0;95m'; PURPLE='\033[0;35m'
    BOLD='\033[1m'; RESET='\033[0m'
else
    YELLOW=''; GREEN=''; RED=''; DIM=''; CYAN=''; MAGENTA=''; PURPLE=''; BOLD=''; RESET=''
fi

# --- Pricing (mirrors ccx internal/parser/pricing.go) ---------------------
# USD per 1,000,000 tokens: input output cache_read cache_create.
# Cache reads bill at ~10% of input; 5m cache writes at ~125% of input.
# These are PUBLIC LIST rates; fast-mode surcharges are not modeled.
lookup_pricing() {
    # Echoes: "input output cache_read cache_create" or "" if unknown.
    local m="$1"
    m=$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')
    case "$m" in
    *claude-fable-5*)
        # Fable 5: own tier above Opus, $10/$50 (verified, public list rate).
        echo "10.00 50.00 1.00 12.50" ;;
    *claude-opus-4-8*|*claude-opus-4-7*|*claude-opus-4-6*|*claude-opus-4-5*)
        # Opus 4.5+ capability group: tier 5/25.
        echo "5.00 25.00 0.50 6.25" ;;
    *claude-opus-4-1*|*claude-opus-4*)
        echo "15.00 75.00 1.50 18.75" ;;
    *claude-sonnet-4*|*claude-3-7-sonnet*|*claude-3-5-sonnet*)
        echo "3.00 15.00 0.30 3.75" ;;
    *claude-haiku-4-5*)
        echo "1.00 5.00 0.10 1.25" ;;
    *claude-3-5-haiku*)
        echo "0.80 4.00 0.08 1.00" ;;
    *)
        echo "" ;;
    esac
}

# NOTE: per-turn cost is computed in a single awk pass inside render() (the
# pricing tiers are mirrored there). lookup_pricing above is the shell-side
# source of truth used to decide whether a model has known list pricing.

# --- Locate transcript ----------------------------------------------------
resolve_transcript() {
    # Priority: explicit --transcript, then --session lookup, then newest
    # transcript in the current dir's project, then newest overall.
    if [ -n "$transcript_path" ]; then
        echo "$transcript_path"; return
    fi

    if [ -n "$session_id" ]; then
        local hit
        hit=$(find "$PROJECTS_DIR" -name "${session_id}.jsonl" -type f 2>/dev/null | head -1)
        [ -n "$hit" ] && { echo "$hit"; return; }
    fi

    # Current dir -> encoded project folder name (Claude Code replaces
    # path separators and dots with dashes).
    local enc
    enc=$(pwd | sed 's/[/.]/-/g')
    local proj_dir="$PROJECTS_DIR/$enc"
    if [ -d "$proj_dir" ]; then
        local newest
        newest=$(find "$proj_dir" -maxdepth 1 -name '*.jsonl' -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -1 | cut -d' ' -f2-)
        [ -n "$newest" ] && { echo "$newest"; return; }
    fi

    # Fall back to newest transcript anywhere.
    find "$PROJECTS_DIR" -name '*.jsonl' -type f -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-
}

fmt_int() {
    # Group thousands with commas; portable (no locale dependency).
    printf '%s' "$1" | awk '{
        n=$0; s=""; neg=0
        if (substr(n,1,1)=="-") { neg=1; n=substr(n,2) }
        while (length(n)>3) { s=","substr(n,length(n)-2)s; n=substr(n,1,length(n)-3) }
        s=n s; if (neg) s="-"s; print s
    }'
}

fmt_usd() {
    local v="$1"
    [ -z "$v" ] && { printf '%s' "n/a"; return; }
    awk -v v="$v" 'BEGIN { printf "$%.2f", v }'
}

usage_color() {
    local p="$1"
    p=$(printf '%.0f' "$p" 2>/dev/null || echo 0)
    if [ "$p" -ge 90 ]; then printf '%b' "$RED"
    elif [ "$p" -ge 80 ]; then printf '%b' "$YELLOW"
    else printf '%b' "$GREEN"; fi
}

# --- Render quota line from shared account cache --------------------------
render_quota() {
    local cache="$CLAUDE_ACCOUNT_DIR/usage.cache"
    if [ ! -f "$cache" ]; then
        printf '%bquota:%b no cache yet (run statusline.sh to populate)\n' "$DIM" "$RESET"
        return
    fi
    local five seven extra_used extra_limit extra_util age fetched_at
    eval "$(jq -r '
        @sh "five=\(.five_hour.utilization // "")",
        @sh "seven=\(.seven_day.utilization // "")",
        @sh "extra_used=\(.extra_usage.used_credits // "")",
        @sh "extra_limit=\(.extra_usage.monthly_limit // "")",
        @sh "extra_util=\(.extra_usage.utilization // "")",
        @sh "fetched_at=\(.fetched_at // 0)"
    ' "$cache" 2>/dev/null)"

    local out="${BOLD}quota${RESET}  "
    if [ -n "$five" ]; then
        local fi; fi=$(printf '%.0f' "$five" 2>/dev/null || echo 0)
        out+="$(usage_color "$fi")5h ${fi}%${RESET}  "
    fi
    if [ -n "$seven" ]; then
        local si; si=$(printf '%.0f' "$seven" 2>/dev/null || echo 0)
        out+="$(usage_color "$si")7d ${si}%${RESET}  "
    fi
    if [ -n "$extra_util" ] && [ "$extra_util" != "null" ]; then
        local ei; ei=$(printf '%.0f' "$extra_util" 2>/dev/null || echo 0)
        local ex_part=""
        if [ -n "$extra_used" ] && [ -n "$extra_limit" ] && [ "$extra_limit" != "null" ]; then
            local ud ld
            ud=$(awk -v c="$extra_used" 'BEGIN{printf "$%.2f", c/100}')
            ld=$(awk -v c="$extra_limit" 'BEGIN{printf "$%.0f", c/100}')
            ex_part="${ud}/${ld} "
        fi
        out+="$(usage_color "$ei")extra ${ex_part}${ei}%${RESET}  "
    fi
    age=$(( $(date +%s) - fetched_at ))
    [ "$fetched_at" -gt 0 ] 2>/dev/null && out+="${DIM}(${age}s ago)${RESET}"
    printf '%b\n' "$out"
}

# --- Render one snapshot --------------------------------------------------
render() {
    local tp="$1"
    if [ -z "$tp" ] || [ ! -f "$tp" ]; then
        printf '%bclaude-watch%b: no transcript found.\n' "$RED" "$RESET"
        printf '%b  Looked under: %s%b\n' "$DIM" "$PROJECTS_DIR" "$RESET"
        printf '%b  Pass --transcript PATH or --session ID, or cd into a project dir.%b\n' "$DIM" "$RESET"
        return
    fi

    # Stream assistant usage blocks line-by-line. `fromjson?` tolerates
    # malformed / oversized lines that appear in real transcripts (tool
    # results, truncated writes) instead of aborting the whole parse, and
    # avoids slurping multi-MB files into memory. Emits one TSV row per
    # turn: model<TAB>in<TAB>out<TAB>cread<TAB>ccreate<TAB>ts.
    local rows
    rows=$(jq -Rr '
        fromjson? // empty
        | select(.type=="assistant" and .message.usage)
        | [ (.message.model // ""),
            (.message.usage.input_tokens // 0),
            (.message.usage.output_tokens // 0),
            (.message.usage.cache_read_input_tokens // 0),
            (.message.usage.cache_creation_input_tokens // 0),
            (.timestamp // "") ]
        | @tsv
    ' "$tp" 2>/dev/null)

    if [ -z "$rows" ]; then
        printf '%bclaude-watch%b: transcript has no assistant usage yet.\n' "$YELLOW" "$RESET"
        printf '%b  %s%b\n' "$DIM" "$tp" "$RESET"
        return
    fi

    # Single awk pass over all rows: session totals + per-turn cost (each
    # turn priced at its own model's rate) + last-turn breakdown. Pricing
    # tiers are inlined here to keep this to one awk invocation regardless
    # of transcript length (a per-turn shell loop was O(n) subprocesses and
    # far too slow on multi-thousand-turn transcripts).
    local summary
    summary=$(printf '%s\n' "$rows" | awk -F'\t' '
        function rate(m,   lm) {
            lm = tolower(m)
            # returns "in out cread ccreate" via globals pi/po/pcr/pcc; 1 if known
            if (lm ~ /claude-fable-5/) {
                pi=10.0; po=50.0; pcr=1.00; pcc=12.50; return 1 }
            if (lm ~ /claude-opus-4-8|claude-opus-4-7|claude-opus-4-6|claude-opus-4-5/) {
                pi=5.0; po=25.0; pcr=0.50; pcc=6.25; return 1 }
            if (lm ~ /claude-opus-4-1|claude-opus-4/) {
                pi=15.0; po=75.0; pcr=1.50; pcc=18.75; return 1 }
            if (lm ~ /claude-sonnet-4|claude-3-7-sonnet|claude-3-5-sonnet/) {
                pi=3.0; po=15.0; pcr=0.30; pcc=3.75; return 1 }
            if (lm ~ /claude-haiku-4-5/) {
                pi=1.0; po=5.0; pcr=0.10; pcc=1.25; return 1 }
            if (lm ~ /claude-3-5-haiku/) {
                pi=0.80; po=4.0; pcr=0.08; pcc=1.0; return 1 }
            return 0
        }
        {
            m=$1; i=$2; o=$3; cr=$4; cc=$5; ts=$6
            count++
            ti+=i; to+=o; tcr+=cr; tcc+=cc
            if (rate(m)) {
                turn_cost = (i*pi + o*po + cr*pcr + cc*pcc)/1000000.0
                total += turn_cost
                lknown=1
            } else { lknown=0 }
            lm=m; li=i; lo=o; lcr=cr; lcc=cc; lts=ts; lturncost=turn_cost
        }
        END {
            printf "%d\t%d\t%d\t%d\t%d\t%.4f\t%s\t%d\t%d\t%d\t%d\t%s\t%.4f\t%d\n",
                count, ti, to, tcr, tcc, total, lm, li, lo, lcr, lcc, lts,
                (lknown? lturncost : -1), lknown
        }
    ')

    local count tot_i tot_o tot_cr tot_cc total_cost model l_i l_o l_cr l_cc l_ts last_cost l_known
    IFS=$'\t' read -r count tot_i tot_o tot_cr tot_cc total_cost model l_i l_o l_cr l_cc l_ts last_cost l_known <<<"$summary"
    [ "$l_known" = "0" ] && last_cost=""

    local abbrev="$model"
    case "$model" in
    claude-*-*-*) abbrev=$(echo "$model" | sed -E 's/claude-([a-z]+)-([0-9]+)-([0-9]+).*/\1\2.\3/') ;;
    claude-fable-*) abbrev=$(echo "$model" | sed -E 's/claude-fable-([0-9]+).*/fabl\1/') ;;
    esac

    # Match statusline's hue split: opus=purple (0;35), fable=bright magenta (0;95).
    local mcolor="$DIM"
    case "$model" in
    *opus*)   mcolor="$PURPLE" ;;
    *fable*)  mcolor="$MAGENTA" ;;
    *sonnet*) mcolor="$CYAN" ;;
    *haiku*)  mcolor="$YELLOW" ;;
    esac

    printf '%b━━ claude-watch ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$DIM" "$RESET"
    printf '%bmodel%b  %b%s%b  %bturns %s%b  %b%s%b\n' \
        "$BOLD" "$RESET" "$mcolor" "$abbrev" "$RESET" \
        "$DIM" "$count" "$RESET" "$DIM" "${l_ts}" "$RESET"
    echo
    printf '%blast turn%b  %s%b  ' "$BOLD" "$RESET" "$(fmt_usd "$last_cost")" "$RESET"
    printf '%bin%b %s  %bout%b %s  %bc-read%b %s  %bc-make%b %s\n' \
        "$DIM" "$RESET" "$(fmt_int "$l_i")" \
        "$DIM" "$RESET" "$(fmt_int "$l_o")" \
        "$DIM" "$RESET" "$(fmt_int "$l_cr")" \
        "$DIM" "$RESET" "$(fmt_int "$l_cc")"
    printf '%bsession  %b %s%b  ' "$BOLD" "$RESET" "$(fmt_usd "$total_cost")" "$RESET"
    printf '%bin%b %s  %bout%b %s  %bc-read%b %s  %bc-make%b %s\n' \
        "$DIM" "$RESET" "$(fmt_int "$tot_i")" \
        "$DIM" "$RESET" "$(fmt_int "$tot_o")" \
        "$DIM" "$RESET" "$(fmt_int "$tot_cr")" \
        "$DIM" "$RESET" "$(fmt_int "$tot_cc")"
    echo
    render_quota
    printf '%b%s%b\n' "$DIM" "$tp" "$RESET"
    if [ -z "$(lookup_pricing "$model")" ]; then
        printf '%b! cost n/a: no list price for "%s"%b\n' "$YELLOW" "$model" "$RESET"
    fi
}

# --- Main -----------------------------------------------------------------
tp=$(resolve_transcript)

if [ "$run_once" = true ]; then
    render "$tp"
    exit 0
fi

# Restore cursor on exit.
trap 'printf "\033[?25h"; exit 0' INT TERM
printf '\033[?25l'  # hide cursor during watch
while true; do
    # Re-resolve each loop so a newly-started session is picked up when no
    # explicit transcript/session was pinned.
    [ -z "$transcript_path" ] && [ -z "$session_id" ] && tp=$(resolve_transcript)
    printf '\033[2J\033[H'  # clear + home
    render "$tp"
    printf '\n%brefresh %ss · Ctrl-C to quit%b\n' "$DIM" "$interval" "$RESET"
    sleep "$interval"
done
