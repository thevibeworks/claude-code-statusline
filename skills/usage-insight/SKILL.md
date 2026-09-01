---
name: usage-insight
description: >
  Answer Claude Code usage and quota questions from the statusline state
  dir (~/.claude/statusline/): why the statusline is yellow/red, whether
  to start a heavy task now, which account has headroom, what expired
  unused this week, when a capped model comes back. Triggers on quota,
  5h/7d windows, rate limits, capacity planning, statusline questions,
  "should I run this now", "which account", "what did I waste".
---

# Usage insight from the statusline state dir

claude-code-statusline maintains a read-only-for-you state dir and
documents it as a contract (docs/api/state-dir.md in
https://github.com/thevibeworks/claude-code-statusline). This skill
teaches you to read it and answer usage questions conversationally —
the deep-dive version of what the advisor row says in one sentence.

## Ground rules

1. READ-ONLY. Never write, touch, or delete anything under
   `~/.claude/statusline/`. The statusline is the only writer.
2. Account scoping: state for tagged accounts lives under
   `~/.claude/statusline/accounts/<tag>/`; the top level is the default
   account. If `STATUSLINE_ACCOUNT` or `DEVA_AUTH_TAG` is set in the
   environment, that names the current account.
3. Staleness: trust `fetched_at` (epoch seconds) in usage.cache.
   Older than ~1h means no active session feeds that account — say the
   numbers are stale instead of presenting them as now.
4. These files hold account PII (email, uuid, org). Quote numbers and
   reset times to the user; do not echo emails/uuids unless asked.

## What to read for which question

| Question | Source |
|----------|--------|
| "Why is the line yellow/red?" / "what's my quota now?" | `usage.cache`: `five_hour.{utilization,resets_at}`, `seven_day.*`, `limits[]` (per-model weekly caps, `kind=weekly_scoped`) |
| "Should I start a heavy task now?" | `usage.cache` now + `forecast.cache` patterns (below) |
| "Which account has headroom?" | every `accounts/*/usage.cache`, compare `five_hour.utilization` and `fetched_at` freshness |
| "What did I waste?" / weekly retrospective | run `~/.claude/statusline.sh report [--days N]` — the reference consumer; don't re-mine by hand |
| "Anything I should know right now?" | run `~/.claude/statusline.sh check` — exit 0 calm / 1 opportunity / 2 pressure / 3 unknown |
| "What did that session cost me?" | `~/.claude/statusline.sh session-summary` (last session), or pipe `{"session_id":"..."}` |

## Semantics crib (forecast.cache)

```json
{"days_history": 21, "recent_24h": 14.2,
 "pct_per_window": 11.83,
 "weekday_profile": {"0": 5.1, "1": 27.3, "6": -1},
 "hour_profile": {"0": 0.09, "9": 1.83, "23": 1.24}}
```

- `weekday_profile`: learned percent-of-7d-quota burned per weekday
  (0=Sun..6=Sat), EWMA half-life 14 days; `-1` = never observed.
  Cold start below 14 `days_history` — say projections are unlearned.
- `hour_profile`: burn multiplier per local hour, mean 1 — the rate at
  hour h is `weekday_profile[dow] x hour_profile[h]`. Below 0.25 is a
  REST hour; absent or malformed means flat, never silence. Hours the
  account sleeps through are not capacity: count only those at or above
  0.25 when you say what is spendable before a reset.
- `pct_per_window`: the exchange rate — 7d percentage points one fully
  burned 5h window costs THIS account. `-1` = unlearned. A week holds
  roughly `100 / pct_per_window` full windows.
- usage.jsonl lines carry `predicted_end` (the projection made at
  sample time): compare old predictions against what actually happened
  before presenting the forecast as reliable.

## Judgment rules (mirror the advisor; never advise what data can't back)

- Feasibility before advice: with S% of the 7d window unused and T
  hours to its reset, the burnable maximum is roughly
  `pct_per_window x (T / 5h)` (capped by the current 5h window's own
  headroom). If that is less than S, do NOT say "use it up" — say how
  much expires no matter what. T is AWAKE hours once `hour_profile` is
  learned: "spend it" at 23:00 is advice to burn a week through eight
  hours of sleep.
- With `pct_per_window = -1`, state facts, not advice.
- A scoped limit (`limits[]`) at 100% means that model is unavailable:
  the useful fact is its `resets_at`, not the percentage.
- 5h pressure with a reset < 30min away is self-healing — say "resets
  in N minutes" instead of alarming.
- Recommending another account: only name siblings whose cache is
  fresh (< 1h); an idle-looking stale account is unknown, not free.

## Answer style

Lead with the verdict ("yes, start it — 5h at 22% with 4h of window
left"), then the two or three numbers that justify it. Convert
percentages into work-terms using the exchange rate ("~49% expires
even at full burn — about 4.7 windows' worth"). Say when data is
stale, unlearned, or invisible (usage from other devices between
renders never reaches the log).
