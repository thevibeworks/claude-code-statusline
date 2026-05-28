# Changelog

## v0.7.0 — 2026-05-27 — Prompt Cache Health & Absolute Reset Times

Tested against Claude Code CLI v2.1.150 (MAX and PRO accounts).

### Cache Health Indicator

Detects prompt cache invalidation from per-turn token data already in
the CLI's stdin JSON. Uses the same detection logic as Claude Code's
internal `promptCacheBreakDetection.ts`: flags a break when
`cache_read_input_tokens` drops >5% and >2000 tokens from the
previous turn.

- `cache!` (red) — cache break detected, this turn was fully uncached
- `cache~` (dim yellow) — cache building, first turn or post-break rebuild
- Hidden when healthy — zero noise during normal operation

Display appears after the context bar:

```
opus4.6[1m][███░░26%]              (healthy — no indicator)
opus4.6[1m][███░░26%] cache~       (building — first turn)
opus4.6[1m][███░░26%] cache!       (break — full rebuild)
```

State tracked in `$CLAUDE_CACHE_DIR/cache_health` (one number: previous
turn's `cache_read_input_tokens`).

### Why It Matters

A single cache break on a 1M-context Opus session costs ~22x more than
a cached turn. For subscription users, that's quota burn equivalent to
20+ normal turns. The indicator makes this invisible cost visible.

### Added

- `get_cache_health()` function with four return states: `ok`, `break`,
  `building`, `none`
- `CACHE_BREAK_MIN_TOKENS` (2000) and `CACHE_BREAK_DROP_PCT` (5)
  threshold constants
- Extracts `cache_read_input_tokens`, `cache_creation_input_tokens`,
  `input_tokens` from stdin `context_window.current_usage`
- Per-session state file (`${session_id}_cache_health`) prevents false
  positives when running concurrent Claude Code sessions
- `mkdir -p` before state file write ensures detection works for API key
  users where `$CLAUDE_CACHE_DIR` may not exist yet
- 16 new tests (13 unit + 3 integration)

### Absolute Reset Times

Quota reset display changed from relative countdown to absolute time:

- **Before**: `5h[87%~1h30m]` `7d[75%~2d5h]`
- **After**: `5h[87%@14:30]` `7d[75%@Mon]`

Relative time (`~1h30m`) is only true at render time. Claude Code
controls statusline refresh, so a countdown can become stale while
still visible. Absolute time (`@14:30`, `@Mon`) stays true without
realtime refresh.

- 5h uses wall-clock time (`@HH:MM`) — answers "when can I resume?"
- 7d uses day-of-week (`@Mon`) — answers "which day does it reset?"
- Same-day 7d reset falls back to wall-clock
- `@now` when reset is past

`format_reset_absolute()` function with `short` (HH:MM) and `day`
(day-of-week, falls back to HH:MM for same day) modes.

132 total tests across both suites.

---

## v0.6.0 — 2026-05-26 — Smart Countdowns & Information Grouping

Tested against Claude Code CLI v2.1.143 (MAX and PRO accounts).

### Smart Countdown Display

Reset countdowns now respond to two independent signals:

- **Percentage pressure**: 5h >= 80% or 7d >= 70% (existing behavior)
- **Time proximity**: 5h reset <= 2h or 7d reset <= 3d (new)

Either signal triggers the countdown. A user at 40% with 90 minutes to reset
sees `5h[40%~1h30m]` — the opportunity signal: "burn freely, fresh window
coming." Switched 5h from wall-clock (`@14:30`) to relative time (`~1h30m`)
for consistency with 7d.

**Recovery color**: DIM_GREEN when usage is high but reset is imminent
(5h: <= 30min, 7d: <= 12h). Communicates "it was hot, it's cooling down."

### Model + Context Merge

Context bar now attaches directly to the model: `opus4.6[1m][█░░░░░15%]`
instead of `opus4.6[1m] [█░░░░░15%]`. Context is a property of the model
session, not an independent stat.

### Extra Usage: Auto Mode

New default `--extra auto` replaces `always`. Shows the extra-usage section
only when actionable:

- 5h >= 80% or 7d >= 70% (quota running out)
- Extra utilization >= 50% (budget pressure)

Hides extra during calm sessions. `always`, `on-limit`, `off` still available.

### Thresholds as Named Constants

All auto-display thresholds extracted to top-level variables:

```
FIVE_HOUR_COUNTDOWN_SECS=7200    # 2h
FIVE_HOUR_RECOVERY_SECS=1800     # 30min
SEVEN_DAY_COUNTDOWN_SECS=259200  # 3d
SEVEN_DAY_RECOVERY_SECS=43200    # 12h
EXTRA_AUTO_UTIL_PCT=50           # 50%
```

### Cleanup

- Removed dead `format_reset_clock()` (replaced by relative time)
- Removed `context` from all theme `stat_order` strings (now part of model)
- 95 bats tests (was 81)

---

## v0.5.0 — 2026-05-25 — Stdin-First Architecture & Extra Usage

Tested against Claude Code CLI v2.1.141 (MAX and PRO accounts).

### Stdin-First Architecture

Context percentage, rate limits, effort level, and fast mode are now read
directly from the CLI's JSON input instead of computing independently.

- **Context bar** uses `context_window.used_percentage` from stdin. Transcript
  JSONL parsing is kept as fallback for CLI versions before v2.1.132.
- **Quota display** uses `rate_limits` from stdin when no OAuth cache exists.
  OAuth fetch is still needed for extra-usage and user profile data.
- **Effort level** shown next to model when non-default: `opus4.6[1m] max`.
- **Fast mode** shown as `opus4.6[1m] fast` when enabled.
- `format_reset_clock` and `format_reset_relative` now handle both ISO 8601
  and unix epoch timestamps (CLI sends epoch, OAuth API sends ISO).

### Added

- Added default `extra` statusline component for Claude Code extra usage:
  `ex[$16.29/$200 8% bal$4.66]`.
- Reads monthly extra spend from `/api/oauth/usage` and prepaid balance from
  `/api/oauth/organizations/:orgUUID/prepaid/credits` when OAuth profile data is
  available.
- Caches prepaid balance for 5 minutes with the same lock/backoff pattern used
  by quota fetching.
- Refreshes expired file-based Claude Code OAuth tokens before quota/profile
  requests.

### Extra Usage Display Mode

New `--extra` flag controls when the extra-usage component appears:

- `always` — show whenever extra usage is enabled
- `on-limit` — show only when 5h >= 80% or 7d >= 70% (quota under pressure)
- `off` — never show

The `developer` theme defaults to `on-limit`; `minimal` defaults to `off`.

### UX Refinements

- Quota percentages now display as integers: `5h[12%]` instead of `5h[12.0%]`.
- Refresh indicator: `~` appears after quota cluster when an API fetch is in
  flight, `!` when the last fetch failed and data may be stale. Extra usage
  has its own independent indicator (separate API call).
- Duration shows hours for long sessions: `1h30m` instead of `90m`.
- Removed dead `add_component_no_space` and `format_usage_bar` functions.
- Fixed `format_duration(0)` returning "1m" instead of "0m".
- Fixed color variables used before definition (git info, path had no color).
- Guarded context percentage against division by zero (`CLAUDE_CONTEXT_LIMIT=0`).

### Color Hierarchy

- Path demoted to dim cyan — frees visual weight for primary signals.
- Git branch: dirty=yellow (pops), clean=dim yellow (recedes).
- Time: plain dim instead of dim cyan — less color noise.
- User tier label gets color: MAX=green, PRO=cyan, ENT/TEAM=dim cyan.

---

## v0.3.0 — 2026-05-12 — Quota Reset Time & API Cleanup

### Quota Reset Display

When utilization enters the warning zone, reset time auto-appears:

- **5h >= 80%**: wall-clock time — `5h[87%@14:30]`
- **7d >= 70%**: relative countdown — `7d[75%~2d5h]`

Clock time for 5h (you're thinking "can I resume after lunch?").
Relative for 7d ("2d5h" is more actionable than a specific datetime).
Below threshold, display is unchanged: `5h[25%] 7d[10%]`.

### API Accuracy

- Removed stale `anthropic-beta: oauth-2025-04-20` from usage API call —
  endpoint is GA, neither CLI v2.1.76 nor v2.1.121 sends this header
- Usage jq parsing batched into single `eval "$(jq -r @sh ...)"` call
  (was 4 separate jq invocations)

### Cross-Reference

API contract verified against Claude Code CLI v2.1.76 (cli.js) and v2.1.121
(Bun binary). See `docs/devlog/2026-04-28-usage-api-contract-cross-reference.org`.

---

## v0.2.0 — 2026-03-16 — 1M Context Window & API Hardening

### Critical Fixes

**1. Context Window: 1M Auto-Detection**
- Root cause: context_limit hardcoded to 200k, Opus 4.6 [1m] has 1M window
- Fix: detect `[1m]` in model.id (matches CLI's `NO()` function)
- Before: 104k tokens showed 77% (against 200k). After: 10% (against 1M)

**2. Context Calculation: Match CLI's /context**
- Formula: `percentage = round(totalTokens / contextWindow * 100)`
- Removed erroneous `system_overhead=24500` — cache_read + input already includes system prompt
- Changed denominator from `window - output_reserve` to full `window` (matches CLI)
- Fixed max_output_tokens: 16000 -> 32000

**3. Cost Formatting Bug**
- `$10.00` displayed as `$1` due to `sed 's/0$//'` eating integer digits
- Fix: `sed 's/\.00$//'` — only strip `.00`, keep `$10.50` as `$10.50`

**4. Model Detection Updated**
- Added opus-4-6, sonnet-4-6 pattern matching
- Strip `[1m]` suffix from settings.json model before case-matching (prevents `opus[1m][1m]`)

### API Improvements

**5. Adaptive Quota TTL**
- 5h utilization <20%: poll every 5min
- 20-50%: every 2min
- 50-80%: every 1min
- 80%+: every 30s
- Previously: fixed 60s regardless of utilization

**6. Error Backoff**
- 120s cooldown after failed API call (was: retry every tick)
- Error state tracked in `${session_id}.err` file

**7. OAuth Gate**
- Skip quota/user fetch when `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, or `ANTHROPIC_BASE_URL` set
- Skip when credentials file exists but contains no OAuth token
- Eliminates "no token found" log noise for API key users

**8. Dynamic User-Agent**
- Uses CLI version from input JSON (was: hardcoded `claude-code/2.1.22`)

### Code Quality

**9. Atomic Cache Writes**
- Write to `${cache_file}.tmp.$$` then `mv -f` to prevent truncated JSON from race conditions

**10. JSON Injection Prevention**
- `detect_session_boundary()` now uses `jq -n --arg` instead of raw string interpolation

**11. Profile Parsing Consolidation**
- 10 separate `echo | jq` calls replaced with single `eval "$(jq -r @sh ...)"` call

**12. Progress Bar Extraction**
- `render_bar()` function replaces 70+ lines of copy-paste across 7 bar styles
- C-style `for ((i=0; ...))` loops replace `seq` subshells

**13. Deduplicated Logic**
- `get_user_tier()`: single function for tier detection (was: 3 copies)
- `get_adaptive_ttl()`: single function for TTL calculation (was: 2 copies)

**14. Portability**
- `printf '%b'` replaces `echo -e` for ANSI stripping (portable across shells)
- `sed 's/\.00$//'` replaces `sed -E 's/0+$//'` (GNU/BSD compatible)

**15. Input Parsing**
- Single `eval "$(jq -r @sh ...)"` call replaces 12 separate subshells

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_CONTEXT_LIMIT` | auto | Context token limit override (auto-detected from model.id) |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Output token reserve |
| `CLAUDE_DATA_DIR` | script dir | Data directory (usage.jsonl) |
| `CLAUDE_CACHE_DIR` | `$CLAUDE_DATA_DIR/sessions` | Session cache directory |

---

## v0.1.0 — 2026-02-05 — API Correctness & macOS Support

Initial release with float-to-integer conversion fixes, macOS Keychain support,
OrbStack home directory resolution, profile API alignment, per-model quotas,
BSD compatibility, user/quota components, and dependency checking.
