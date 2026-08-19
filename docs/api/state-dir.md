# `~/.claude/statusline/` — state dir contract

The on-disk state under this dir, documented as a contract so external
readers (dashboards, ad-hoc `jq`) and cooperating writers can consume
it without reverse-engineering the script. Everything here is safe to
read concurrently.

- Contract version: **2** (bump on any breaking layout/field change; this
  file is the changelog)
- Synced with: statusline.sh v0.22.0
- Permissions: the script runs under `umask 077` — files are owner-only.
  Caches hold account PII (email, uuid, org names).

## Cooperating writers (v2)

v1 declared statusline.sh the only writer. v2 opens the dir to
cooperating writers — tools observing the same account (first:
[ccpace](https://github.com/thevibeworks/ccpace)) — under these rules;
a writer that cannot honor all of them must use its own dir instead:

- **Record shapes are law.** A foreign `usage` record carries the same
  fields this doc specifies, raw API sections verbatim, epoch
  `timestamp`, `user.uuid` set. Additions are additive-only; foreign
  writers tag records with `source: "<tool>/<version>"` (statusline
  omits it). Never rename or re-nest existing fields.
- **Readers tolerate.** Unknown `type` values and unknown fields are
  skipped, never errors. Records without `.model` (markers, foreign
  samples) must not blank model-derived state — take the newest record
  that has one.
- **Rotation is shared.** 32 MiB cap, single `.1` backup, and the
  `usage.jsonl.rotate.lock` mkdir-lock before any `mv`. Either writer
  may rotate; readers read `.1` then current.
- **Caches are a fetch pool.** A `usage.cache` with fresh `fetched_at`
  is a fetch already made — use it instead of hitting the API, and do
  not re-log a sample served from it (one observation, one record).
  After a successful fetch, publish it back atomically (tmp + rename).
  `profile.cache` likewise (raw profile; mtime is the fetch time,
  24 h TTL). `*.lock` files are advisory between statusline processes;
  cross-tool safety comes from atomic rename.
- **Partition by uuid.** Aggregating readers (forecast, report) filter
  on `user.uuid`, never trust directory placement alone.

## Layout

```
~/.claude/statusline/                     account state, DEFAULT account
  usage.cache                             last /api/oauth/usage response + fetched_at
  profile.cache                           last /api/oauth/profile response (24h TTL)
  prepaid_credits.cache                   prepaid balance + fetched_at (5m TTL)
  forecast.cache                          learned weekday burn profile (hourly rebuild)
  week.cache                              week-row cells: 7d per-window + 5h per-half-hour burn (rebuilt when usage.jsonl grows)
  stdin_seen                              last stdin rate_limits pair logged (`5h|7d epoch`) — dedupe for source:stdin samples
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

### week.cache

The week row's history, so a render never scans the log:

```json
{"period_start": 1786550400, "five_start": 1787119200,
 "log_sig": "1787118061:4844903", "at": 1787118354,
 "week": "1786552591 1787118061 0:11,1:2,2:4,4:10",
 "five": "1787119260 1787120100 0:5,1:10,3:25"}
```

`period_start` / `five_start` are the 7d period start and the current 5h
window start, both snapped to the 5-min grid the window keys use;
`log_sig` is usage.jsonl's `mtime:size`; `week` and `five` are
`span_lo span_hi cell:cost,...` — the log's coverage span (epoch) and, per
cell, the points observed in it. `week`: per 5h slot of the period, the
7d points that window burned (max - min of `seven_day.utilization`,
samples keyed by `five_hour.resets_at` rounded to 5 min). `five`: per
half hour of the current 5h window, the 5h points added (each positive
step between consecutive samples credited to the later sample's cell).
Rebuilt when either period, the signature, or a 5-min TTL disagrees;
safe to delete.

### usage.jsonl

Append-only, one JSON object per line, three event types:

| `type` | Emitted | Payload |
|--------|---------|---------|
| `usage` | every successful usage fetch; and (`source:"stdin"`) every changed 5h/7d pair Claude Code hands the statusline on stdin, >= 60 s apart — same window keys, `user.uuid` from profile.cache, no `organization`/`extra_usage`/`limits` | `session_id`, `timestamp`, `user{email,name,uuid,…}`, `organization{…}`, `five_hour`, `seven_day`, `seven_day_opus`, `extra_usage`, `limits[]`, `model`, `predicted_end` |
| `session_start` | first fetch of a new 5h window | `session_id`, `timestamp`, `five_hour_window_end`, `seven_day_window_end` |
| `session_end` | 5h window rolled while a different session was last | `session_id`, `timestamp` |

Since v0.20.0 each `usage` line also records what the learner will need
later (learning lags logging — a field absent today is a pattern that
cannot be learned next month):

| Field | Type | Meaning |
|-------|------|---------|
| `limits[]` | array | scoped limits verbatim (per-model weekly caps) |
| `model` | string \| null | model id active in the logging session |
| `predicted_end` | int \| null | the learned walk's end-of-week projection at sample time; null until the profile is warm. Compare against the window's observed final to measure forecast accuracy. |

Rotation keeps exactly one `.1` backup; readers wanting full history read
`usage.jsonl.1` then `usage.jsonl`.

The `report` subcommand (`statusline.sh report [--days N]`) is the
reference consumer: it replays this log and ledgers what each closed
window expired unused.

## Consumer rules

1. Read-only. Locks, TTLs, and rotation are the writer's job.
2. Key on `accounts/<tag>/` when present; fall back to the top level.
3. Trust `fetched_at`/`timestamp`, not file mtimes (migrations preserve
   content, not mtime).
4. Tolerate absent files — every file appears lazily on first use.
5. Parse leniently: server responses are stored verbatim, so upstream
   field additions land here without a version bump.
