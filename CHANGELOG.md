# Changelog

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
