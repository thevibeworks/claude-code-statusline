# `~/.claude/statusline/` — state dir contract

The on-disk state statusline.sh maintains, documented as a contract so
external readers (claudex's `claude.py --watch-usage`, dashboards, ad-hoc
`jq`) can consume it without reverse-engineering the script. statusline.sh
is the ONLY writer; everything here is safe to read concurrently.

- Contract version: **1** (bump on any breaking layout/field change; this
  file is the changelog)
- Synced with: statusline.sh v0.19.0
- Permissions: the script runs under `umask 077` — files are owner-only.
  Caches hold account PII (email, uuid, org names).

## Layout

```
~/.claude/statusline/                     account state, DEFAULT account
  usage.cache                             last /api/oauth/usage response + fetched_at
  profile.cache                           last /api/oauth/profile response (24h TTL)
  prepaid_credits.cache                   prepaid balance + fetched_at (5m TTL)
  forecast.cache                          learned weekday burn profile (hourly rebuild)
  usage.jsonl                             append-only usage/session event log
  usage.jsonl.1                           single rotation backup (32 MiB cap)
  logs/statusline.log                     debug log (only with --debug; 1 MiB cap)
  sessions/                               per-session render state (all accounts)
    <session_id>_cache_health             prompt-cache health state machine
    <session_id>_quota_seen               5h/7d bump-flash state
    <session_id>_flash_seen               generic +N/-N change-flash state
  accounts/<tag>/                         same account-state set, one dir per
    usage.cache … usage.jsonl               tagged account (multi-account homes)
```

Account scoping: when `STATUSLINE_ACCOUNT`, `DEVA_AUTH_TAG`, or — for
containers created by pre-v0.18 deva — a `credentials-file`
`DEVA_AUTH_METHOD`/`DEVA_AUTH_DETAILS` pair names an account (deva-style
shared `~/.claude` with per-container credential overlays), all account
state lives under `accounts/<tag>/` instead of the top level. The top level then belongs to the untagged/default account
only. Tags are sanitized to `[A-Za-z0-9._-]`, max 24 chars, no leading
dot. `*.lock` files (`usage.lock`, `oauth_refresh.lock`, …) are transient
fetch locks — readers ignore them.

## Files

### usage.cache

The raw `/api/oauth/usage` response (see `oauth-usage.md`) plus one field:

| Field | Type | Meaning |
|-------|------|---------|
| `fetched_at` | int epoch s | When this fetch succeeded |
| `five_hour.utilization` | number 0–100 | 5h window used % |
| `five_hour.resets_at` | ISO-8601 | 5h window end |
| `seven_day.*` | same | 7d window |
| `extra_usage.*` | object | overage spend (see oauth-usage.md) |
| `limits[]` | array | scoped limits (`weekly_scoped` per-model caps) |

Freshness: refreshed on an adaptive TTL (30s at >= 80% 5h util up to 300s
when idle); a `usage.err` JSON file appears during fetch-failure cooldowns
(`{at, code, count, cooldown, msg?}`) and is removed on the next success.
Treat `fetched_at` as authoritative staleness; anything older than ~1h
means no active session is feeding this account.

### profile.cache

Raw `/api/oauth/profile` response: `account.{uuid,email,display_name,…}`,
`organization.{uuid,name,organization_type,rate_limit_tier,…}`. Refreshed
at most daily, only from the usage fetch path.

### forecast.cache

Output of the hourly usage.jsonl scan (EWMA half-life 14 days):

```json
{"computed_at": 1785000000, "days_history": 21,
 "recent_24h": 14.20, "recent_48h": 22.10,
 "pct_per_window": 11.83,
 "weekday_profile": {"0": 5.1, "1": 27.3, "…": 0, "6": -1}}
```

`weekday_profile` keys are days-of-week `0`=Sun..`6`=Sat, values are
percent-of-7d-quota burned per day; `-1` = never observed.
`pct_per_window` is the learned cross-window exchange rate: 7d percentage
points consumed by one fully burned 5h window, mined from paired samples
inside the same 5h window; `-1` until enough paired burn has been
observed (>= half a window). Snapshots are partitioned by `account.uuid`
before aggregation.

### usage.jsonl

Append-only, one JSON object per line, three event types:

| `type` | Emitted | Payload |
|--------|---------|---------|
| `usage` | every successful usage fetch | `session_id`, `timestamp`, `user{email,name,uuid,…}`, `organization{…}`, `five_hour`, `seven_day`, `seven_day_opus`, `extra_usage` |
| `session_start` | first fetch of a new 5h window | `session_id`, `timestamp`, `five_hour_window_end`, `seven_day_window_end` |
| `session_end` | 5h window rolled while a different session was last | `session_id`, `timestamp` |

Rotation keeps exactly one `.1` backup; readers wanting full history read
`usage.jsonl.1` then `usage.jsonl`.

## Consumer rules

1. Read-only. Locks, TTLs, and rotation are the writer's job.
2. Key on `accounts/<tag>/` when present; fall back to the top level.
3. Trust `fetched_at`/`timestamp`, not file mtimes (migrations preserve
   content, not mtime).
4. Tolerate absent files — every file appears lazily on first use.
5. Parse leniently: server responses are stored verbatim, so upstream
   field additions land here without a version bump.
