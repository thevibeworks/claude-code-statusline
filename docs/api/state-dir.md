# `~/.claude/statusline/` — state dir contract

The on-disk state under this dir, documented as a contract so external
readers (dashboards, ad-hoc `jq`) and cooperating writers can consume
it without reverse-engineering the script. Everything here is safe to
read concurrently.

- Contract version: **2** (bump on any breaking layout/field change; this
  file is the changelog)
- Synced with: statusline.sh v0.37.0
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
- **Partition by uuid, read the union.** A directory is where a sample
  LANDED, not who it belongs to: the same account reaches the top level
  when an untagged statusline fetched and `accounts/<tag>/` when a
  tagged container did (measured: 301 days at the root, 28 in the tagged
  dir, one uuid). Aggregating readers (forecast, ledger, report) read
  every store under the root — top level plus every `accounts/*/` — and
  filter on `user.uuid`; they never trust placement alone. The union is
  safe because every derived quantity is envelope-based (the same window
  seen twice takes a max, never a sum); it would not be for a sum of
  deltas. Rows with no `user.uuid` are dropped and counted
  (`corpus.dropped_no_uuid`), never attributed by guess.

## Layout

```
~/.claude/statusline/                     account state, DEFAULT account
  usage.cache                             last /api/oauth/usage response + fetched_at
  profile.cache                           last /api/oauth/profile response (24h TTL)
  prepaid_credits.cache                   prepaid balance + fetched_at (5m TTL)
  forecast.cache                          learned weekday + hour burn profile (hourly rebuild)
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

#### Two pools, one wall

The account `seven_day` limit and a `weekly_scoped` limit are two counters
over one week: the same reset instant, both cumulative from it. Their live
ratio is therefore this week's MIX RATE, and no history is needed to read
it. Everything in this section is COMPUTED LIVE from the two numbers above
— nothing here is a stored field, and no cache changes when it changes.

```
mix       = scope / seven                            scoped points per 7d point
reachable = round((100 - seven) * scope / seven)     of the scoped pool
strand    = (100 - scope) - reachable                = round(100 * (seven - scope) / seven)
```

`reachable` is what the account's remaining points can still buy in the
scoped pool; `strand` is the rest of that pool, which expires because
nothing can reach it. Round ONCE and take the strand as the remainder: the
two numbers are printed beside the total they must add to.

Live check: `seven = 81`, `scope = 63` gives mix 0.78, reachable 15, strand
22 — against 0.77 mined from the corpus at week level.

The reading speaks only when ALL of these hold:

| Rule | Value | Why |
|------|-------|-----|
| `SCOPE_SAME_WALL_SEC` | 120 | Resets no further apart than this are one wall. The two have always reset together to the microsecond, but Anthropic could split them, and a ratio taken across two different weeks is a fluent lie. |
| `SCOPE_MIX_MIN_7D` | 60 | "Which cap binds" is only a question once the account's own end is in sight, and the ratio is well established by then. |
| `SCOPE_MIX_MIN_SCOPE` | 5 | A model untouched this week belongs to the underuse reading, not to a mix. |
| `SCOPE_STRAND_MIN_PCT` | 10 | Under ten points there is nothing to act on. |

Plus: both pools under 100 (a capped pool is its own message), and the 7d
window past the young guard every projection shares (a day of this
window's own evidence).

Selecting the scoped limit where no running model names one (`report`,
ccpace): prefer `is_active == true`, else the deepest `weekly_scoped`. A
surface that knows which model the session runs matches on that instead.

The coupling in the other direction — what a scoped point costs the
account — is deliberately NOT published. Measured at n=22 it sits in a
0.2-0.5 band: fluent enough to be believed, too noisy to be true.

### profile.cache

Raw `/api/oauth/profile` response: `account.{uuid,email,display_name,…}`,
`organization.{uuid,name,organization_type,rate_limit_tier,…}`. Refreshed
at most daily, only from the usage fetch path.

### forecast.cache

Output of the hourly usage.jsonl scan (EWMA half-life 14 days):

```json
{"schema": 2, "computed_at": 1785000000, "days_history": 21,
 "recent_24h": 14.20, "recent_48h": 22.10,
 "pct_per_window": 11.83,
 "weekday_profile": {"0": 5.1, "1": 27.3, "…": 0, "6": -1},
 "hour_profile": {"0": 0.09, "…": 1.83, "23": 1.24},
 "scoped_name": "Fable", "scoped_recent_24h": 76.00,
 "scoped_profile": {"0": 5.7, "1": 23.5, "…": 0, "6": -1},
 "cost": {"usd_24h": 12.40, "usd_7d": 84.10,
          "usd_per_pct": 1.6820, "paired_pct": 50.0},
 "corpus": {"uuid": "…", "files": 5, "samples": 26081,
            "dropped_no_uuid": 94, "oldest": 1761542968}}
```

`corpus` says WHICH samples the model was run over — `schema` cannot.
Two writers that agree on envelope burn and read different stores both
pass the schema gate, and `days_history` (which decides whether the
forecast speaks at all) then depends on which binary rendered last.
The stamp is informative, not a gate: a reader that wants to know why
two caches disagree reads it; a rebuild overwrites it.

#### The co-writer contract

`schema` is the version of the MODEL, not of the file: bump it when how
burn is counted or what a profile value means changes; adding a field
does not, because readers already tolerate a missing one via `// -1`.

This is the one derived cache more than one tool wants to write, so the
rule is explicit and it cuts both ways:

- **Writers** stamp the schema they actually implement, and either emit
  the full key set or merge into what is already there. Rebuilding only
  the fields you know and dropping the rest is a truncating write.
- **Readers** treat freshness as necessary, not sufficient. A cache whose
  `schema` is missing or lower than the reader's own gets rebuilt on
  sight, no matter how recently it was written.

Freshness alone was the gate until a co-writer that summed raw positive
deltas published `149.11` into Thursday and dropped `pct_per_window`,
`scoped_*` and `cost` on the way past. The walk's corrupt-profile guard
caught the 149 and went silent — the right reflex, the wrong resting
state: the account had a sound profile ten minutes earlier and no way
back to it until the hour turned. Silence is a defence against a bad
model; it is not a substitute for knowing whose model you are reading.

`weekday_profile` keys are days-of-week `0`=Sun..`6`=Sat, values are
percent-of-7d-quota burned per day; `-1` = never observed.
`pct_per_window` is the learned cross-window exchange rate: 7d percentage
points consumed by one fully burned 5h window, mined from paired samples
inside the same 5h window; `-1` until enough paired burn has been
observed (>= half a window). Snapshots are partitioned by `account.uuid`
before aggregation.

`hour_profile` is the same account on the other axis: 24 keys, local hour
`"0"`..`"23"`, values are burn MULTIPLIERS with mean 1. The instantaneous
rate at hour h is `weekday_rate * mult[h]` (%/day), so integrating any
whole day reproduces the weekday total exactly — the weekday says what a
Tuesday costs, the hour says when in it. The field is additive, so
`schema` stays 2: a reader that has never heard of it walks flat, which is
what every reader did before it existed.

Built inside the same envelope pass — each credited delta is also credited
to `(local_day, local_hour)`, EWMA-weighted by day age with the same
14-day half-life, and today is EXCLUDED, because a day that has only
reached noon reports every evening hour as rest. The weighted share per
hour becomes `m[h] = max(share[h] * 24, 0.1)`, then the whole vector is
scaled so the mean is exactly 1, rounded to 2 decimals. Floored AND
renormalized at BUILD time so every reader sees the same numbers instead
of each applying the hedge its own way; a floored hour therefore prints
slightly under the floor (`0.09`) once many hours were floored — that is
correct, do not re-floor on read. The 0.1 floor is the hedge for the
occasional overnight autonomous run: a rest hour projects a tenth of a
uniform hour, never zero. Omitted entirely when no weighted burn exists.

Use it only if it is an object with all 24 keys, every value numeric in
`[0, 24]`, and the mean in `[0.9, 1.1]` — plus the `days_history >= 14`
gate every learned surface shares. Invalid or absent means FLAT (mult
== 1), never silence: a bad hour shape must not take a good forecast away,
and only the weekday guards do that. Both readers walk the profile by
stepping local-hour boundaries, and the recent-24h blend that opens the
walk ends at exactly 24h out.

```
REST_MULT_MAX = 0.25      an hour below this is a REST hour
```

An AWAKE WINDOW is a 5h window you are awake for. Over the span
`[now + five_secs, now + seven_secs]` — the same span the windows-ahead
count covers, with `five_secs = 0` when no 5h window is live —
`awake_secs` is the part of it falling in local hours with `mult >=
REST_MULT_MAX`, and `awake = min(windows_ahead, ceil(awake_secs /
18000))`; it ceils for the reason windows-ahead does, a partial window
being still spendable. A surface names the awake count only when the
shape is learned, `windows_ahead >= 1`, and `awake < windows_ahead` — an
equal count would spend a clause to say nothing. At `awake == 0` both the
awake clause and the ration that would divide by it go away; the landing
still speaks.

`scoped_*` mirror the all-model fields for the `weekly_scoped` limit —
the per-model weekly cap, `Fable` at time of writing. `scoped_name` is
the scope the profile is ABOUT (`null` while unobserved); burn is
tracked per scope name so a change in which model is capped cannot blend
two series into one profile.

Both profiles use the burn accounting described under [Reading the
quota series](#reading-the-quota-series) — envelope rise, not raw
positive deltas, and both are walked by the same simulator, so the
account's forecast and the model's cannot disagree about physics.

`cost` prices the quota. `usd_per_pct` is what one 7d percentage point
costs this account, and it is the join no single source can make: the
quota API reports percent and never dollars on a subscription plan
(`limit_dollars` is null), the transcripts report dollars and never
percent. Only a sample carrying both can price a point.

Its denominator is **paired**, not total: `paired_pct` counts only the
7d points observed by a sample that also carried `session.cost_usd`. A
log that predates the `session` block by months holds far more points
than dollars, and dividing by all of them would price a week at pennies.
`usd_per_pct` is `-1` until at least 5 paired points exist — a price
mined from two samples is a rumour, not a rate.

`usd_24h` / `usd_7d` are summed per session as the rise of each
session's own cumulative `cost_usd`, never as deltas of the raw column
(see the aggregation rule under usage.jsonl).

A reader must not attribute `scoped_profile` to a model other than
`scoped_name`: which model carries the weekly cap is Anthropic's choice
and has changed before, and one model's weekday shape is not another's.

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
safe to delete. Partitioned by `user.uuid` against `profile.cache` —
the default (untagged) dir predates account scoping and a real one holds
a dozen uuids. Note the cell math rounds the window key to 5 min but
floors the slot, so an unaligned period can draw a window one cell left.

### usage.jsonl

Append-only, one JSON object per line, three event types:

| `type` | Emitted | Payload |
|--------|---------|---------|
| `usage` | every successful usage fetch; and (`source:"stdin"`) every changed 5h/7d pair Claude Code hands the statusline on stdin, >= 60 s apart — same window keys, `user.uuid` from profile.cache, no `organization`/`extra_usage`/`limits` | `session_id`, `timestamp`, `user{email,name,uuid,…}`, `organization{…}`, `five_hour`, `seven_day`, `seven_day_opus`, `extra_usage`, `limits[]`, `model`, `predicted_end` |
| `session_start` | first fetch of a genuinely newer 5h window | `session_id`, `timestamp`, `five_hour_window_end`, `seven_day_window_end` |
| `session_end` | 5h window rolled while a different session was last | `session_id`, `timestamp` |

**Markers in logs written before this fix are noise.** The boundary test
compared `resets_at` as a raw string, and the server jitters it
(`06:00:00.515434` vs `06:00:00.087190`, and `05:59:59` vs `06:00:00`
straddling one boundary), so nearly every fetch wrote a
`session_end`/`session_start` pair: 26% of a measured 23 MiB log was
markers for windows that never rolled — history the 32 MiB rotation cap
then threw away. The test now compares window *instants* with 300 s of
slack and requires the new window to be NEWER, so a stale sample opens
nothing. Readers should treat a marker density near one-per-sample as a
pre-fix log and ignore the markers.

Since v0.20.0 each `usage` line also records what the learner will need
later (learning lags logging — a field absent today is a pattern that
cannot be learned next month):

| Field | Type | Meaning |
|-------|------|---------|
| `limits[]` | array | scoped limits verbatim (per-model weekly caps) |
| `model` | string \| null | model id active in the logging session, `[1m]` suffix included |
| `predicted_end` | int \| null | the learned walk's end-of-week projection at sample time; null until the profile is warm. Compare against the window's observed final to measure forecast accuracy. |

And a `session` object — the half of the picture `/api/oauth/usage` does
not have. The quota endpoint answers "how full is the account" in
percent and nothing else (`limit_dollars` is null on subscription
plans); Claude Code hands the rest to the statusline on stdin, on every
render, for free. Both writers (`api` and `source:"stdin"`) carry it;
`null` when there is no stdin context (subcommands, tests).

| Field | Type | Meaning |
|-------|------|---------|
| `session.cost_usd` | number | `cost.total_cost_usd` — **cumulative for that session** |
| `session.dur_ms` / `session.api_ms` | int | wall and API duration, cumulative per session |
| `session.lines_add` / `session.lines_del` | int | code written, cumulative per session |
| `session.ctx_in` | int | `context_window.total_input_tokens` at sample time — a level, not a flow |
| `session.ctx_size` | int | the session's context window (200k / 1M) |
| `session.effort` | string \| null | reasoning effort (`low`…`max`) |
| `session.fast` | bool | fast mode |
| `session.cli` | string \| null | Claude Code version, so a schema change is datable |
| `session.project` | string \| null | basename of `workspace.project_dir` (else `cwd`) — the one dimension a breakdown cannot recover later; never the full path |

**Aggregating cost.** `cost_usd` is per session and cumulative, and
consecutive samples routinely come from different sessions. Account
spend over a period is the sum over `session_id` of each session's max
`cost_usd` — never the sum, and never the delta, of the raw column.
A session that spans a period boundary is attributed by its samples.

Rotation keeps exactly one `.1` backup; readers wanting full history read
`usage.jsonl.1` then `usage.jsonl`.

The `report` subcommand (`statusline.sh report [--days N]`) is the
reference consumer: it replays this log and ledgers what each closed
window expired unused.

## Reading the quota series

Four properties of the raw series that a naive reader gets wrong. Every
one of them was measured against a real 23 MiB log, and each cost the
forecast an order of magnitude before it was fixed.

**1. `resets_at` is not a window-instance key for 7d.** It looks like
one, and for 5h it behaves like one. But on 2026-08-17 an account's
`seven_day.utilization` went `100.0 -> 0.0` and *stayed* there, sampled
from two independent writers, with `seven_day.resets_at` unchanged at
the same instant. The weekly counter can be reset out of band (grant,
plan change, promo) without moving the window. A NEWER key is certainly
a new window; an unchanged key proves nothing.

**2. Utilization is monotone inside a window; a dip is a stale reading.**
`rate_limits` on stdin is per session, and an idle session keeps
reporting what it last saw. A sample below the running max is almost
always that, not a refund. Burn is therefore the rise of a monotone
ENVELOPE, not the sum of positive deltas — the naive sum re-earns every
dip and read 146 points of burn against a real 50-point week.

**3. Telling (2) from (1) needs two signals.** A stale reading is one
sample and a small step back; a real reset sticks and is a long fall.
The rule here: re-baseline the envelope only when the drop is both
sustained (>= 2 consecutive samples below the envelope) and deep (>= 15
points). The failure mode is a bounded under-count, which costs a missed
warning — the over-count cost a false alarm on every render.

**4. `source:"stdin"` samples are integer-truncated.** Claude Code sends
`used_percentage` as an int; the API sends `utilization` as a float.
Mixing them puts a +-1 sawtooth in the series, which (2) also absorbs.
stdin samples additionally carry no `limits[]`, `extra_usage` or
`organization` — the scoped (per-model) series has holes wherever a
stdin sample is the only one in an interval.

Two more things the series cannot tell you, worth stating so nobody
infers them:

- **Gaps are not idleness.** Samples exist only while a statusline
  renders. A multi-hour gap means no session was running *on this
  machine* — burn from other devices or claude.ai lands as a step at the
  next sample, attributed to the wrong time.
- **`model` is the logging session's, not the spender's.** Quota is
  account-wide and many sessions share it; the model on a record is
  whichever session happened to win the fetch. Per-model attribution
  comes from `limits[]` (the scoped cap) or from Claude Code's own
  transcripts, never from this field.

## Consumer rules

1. Read-only. Locks, TTLs, and rotation are the writer's job.
2. Key on `accounts/<tag>/` for the live caches (`usage.cache`,
   `profile.cache`, `forecast.cache`); for history, read every
   `usage.jsonl(.1)` under the root and partition by `user.uuid`.
3. Trust `fetched_at`/`timestamp`, not file mtimes (migrations preserve
   content, not mtime).
4. Tolerate absent files — every file appears lazily on first use.
5. Parse leniently: server responses are stored verbatim, so upstream
   field additions land here without a version bump.
