# Changelog

## v0.20.0 — 2026-07-28 — the waste ledger: see what you paid for and didn't use

**New: `statusline.sh report [--days N]` — the waste ledger.** The
advisor (v0.19) prevents waste prospectively; this proves it
retroactively. It replays the usage log the statusline has been writing
all along, detects every window close (consecutive samples disagreeing
on `resets_at`, normalized to the minute — the ratio learner's identity
rule), and ledgers each closed 7d window as used% / expired%, converted
into 5h-windows-worth via the learned `pct_per_window` exchange rate:

```
7d windows closed: 1
  Tue 07-28 00:00  used 51%  expired 49% (~4.7 x 5h windows unused)
5h windows closed: 3   avg 95% at close   2 hit the cap
exchange rate: one full 5h window = ~10.46% of the week (~9.6 windows/week, learned)
week in progress: 5% used, resets Mon 08-03 23:59
```

"week in progress" runs the same learned walk the advisor's heading
uses — the surfaces cannot disagree. Honest limits are documented: the
final utilization is the last sample before a reset, so usage from other
clients after your last local render is invisible, and never-sampled
windows don't appear.

**Widened snapshots: log today what the learner needs next month.**
Every `usage` line in usage.jsonl now also records `limits[]` (scoped
per-model weekly caps, verbatim), `model` (the id active in the logging
session), and `predicted_end` — the learned walk's end-of-week
projection *at sample time*. That last one is the calibration seed: once
windows close, predictions can be scored against observed finals, and
the forecast's accuracy becomes measurable instead of assumed. Learning
lags logging by weeks; fields absent today are patterns that can't be
learned next month.

**Fixed: `catch .` gave every empty `resets_at` one shared fake window
identity.** jq's `catch .` yields the error *message*, not the original
input — so snapshots with an empty/unparseable `resets_at` all
normalized to the same error string and could pair across real windows
in the ratio learner, quietly skewing `pct_per_window` (observed on real
data: phantom window closes and a drifted ratio). Both norm sites now
fall back to the raw input string and treat empty as empty.

Mechanics: subcommands dispatch after all function definitions, take no
stdin, and are read-only against the state dir. 327 tests (315
statusline + 12 installer).

## v0.19.0 — 2026-07-28 — smart advisor line, claude-watch retired

**New: the advisor — a second statusline row that interprets the badges.**
Claude Code renders each stdout line as its own row, so the statusline
gains an optional advice line under the badges. Design rule: line 2
speaks only when the numbers on line 1 don't mean what they appear to
mean, and every clause derives from a badge already shown — no third
alarm channel. It cuts both ways: pressure (`! ...`, yellow/red — you'll
hit a wall) and opportunity (`+ ...`, cyan — paid capacity is about to
expire unused; cyan can never mean pressure, so the color alone carries
the stance). Quiet means no row at all (zero height cost when healthy),
and the row right-aligns to the stats anchor so the advice sits directly
beneath the badges it interprets.

- `! fb capped — back ~Thu 07:00` — the weekly limit scoped to this
  session's model (`limits[]` `weekly_scoped`) hit 100%: the model just
  went away; the useful fact is when it returns.
- `! 5h caps ~14:20, 52m before reset` — linear cap projection, only
  while the 5h badge is already yellow/red and relief isn't imminent. At
  100% it stays silent: line 1 already says capped.
- `+ 7d resets @07:00, 56% unused — spend it` (or `— ~40% expires even
  at full burn`) — expiring surplus: inside the last day of the 7d window
  with >= 30% unused, a green badge means forfeiture, not headroom. This
  is exactly the zone where pressure logic goes quiet (recovery) and
  where waste peaks; the old watcher said nothing while half a week's
  subscription evaporated. The tail is feasibility-checked against the
  learned pct_per_window ratio: "spend it" only when full-tilt burn can
  actually consume the surplus, the honest expiry number once it can't,
  and no tail at all while the ratio is unlearned — never advice the
  data can't back.
- `+ alt 5h[8%] free` — fleet relief for shared-home multi-account
  setups (deva): at 5h >= 90%, the idlest fresh sibling under
  `accounts/*/` is named. Pure cache read, no credentials. Now voiced as
  opportunity (cyan), not alarm — line 1 already screams about the cap.
- `! fb caps ~Wed 18:00, 1d before reset` — the running model's scoped
  weekly quota caps before its reset; same math and gates as the 7d
  aggregate.
- `! 7d dry ~Thu 09:00, 2d before reset — then extra billing` (or
  `then hard stop`) — the learned weekday forecast's dry point, falling
  back to linear pace on cold start once `seven_day_pace` warns. The tail
  states what actually happens at the cap.
- `+ 7d on pace to leave ~62% unused — go heavier` — underuse: on pace
  to strand a large chunk of the subscription. The learned weekday
  profile speaks first — it knows YOUR remaining days, so it can warn
  from day two; cold start falls back to linear pace past half the
  window. Speaks only in an engaged, unsqueezed session (5h in
  [25%, 80%), no pressure clause), so it reaches exactly the person who
  can act on it and never nags an idle one.
- `- ~19x5h left, even pace 1.1%/win, heading ~52%` — `--advisor always`
  adds the weekly budget when calm; "heading" is the learned end-of-week
  projection when trained, linear once the window is a day old.

Max two clauses per row, in value order; the 7d window gets one voice per
render (surplus, dry, or underuse — never two that could disagree).
Modes: `--advisor auto` (default) | `always` | `off`. Themes `minimal`
and `manager` set `off`. All times wall-clock or future-to-future gaps —
freeze-safe in an idle frame. Pair with `"refreshInterval": 60` in the
`statusLine` settings to re-evaluate on a timer while idle.

**New: the forecaster learns the 5h↔7d exchange rate.**
`build_seven_day_profile` now also mines `usage.jsonl` for
`pct_per_window` — how many 7d percentage points a fully burned 5h
window costs this account — from paired samples inside the same 5h
window (`resets_at` identity guards against pairing across a reset).
That single learned ratio is the physics that converts "windows left"
into "weekly % actually spendable", and it is what lets the advisor
refuse to say "spend it" when only one window remains against half a
week of surplus. The weekday walk itself is now a shared
`_seven_day_walk` that reports both the dry gap and the projected
end-of-week utilization; the dry forecast, the underuse clause, and the
always-mode "heading" all read the same simulation, so no two surfaces
can disagree about the same future.

**Fix: account resolution no longer misses pre-v0.18-deva containers.**
Containers created before deva exported `DEVA_AUTH_TAG` carry only
`DEVA_AUTH_DETAILS` (`credentials-file (/path/<stem>.credentials.json)`);
those sessions silently fell back to the DEFAULT account's caches —
rendering another account's label and quota, the exact bug scoping exists
to kill. The tag now derives from the details string's file stem, so
long-running containers get correct identity without recreation. Also
hardened the fleet hint against a corrupt sibling cache leaking the
previous sibling's numbers onto the wrong tag.

**Retired: `claude-watch.sh`.** Its transcript cost view belongs to ccx;
its quota footer is superseded by the advisor row. Standalone watching
(multi-account polling, notifications) lives in claudex's
`claude.py --watch-usage`, which consumes this repo's state dir — now
documented as a contract in `docs/api/state-dir.md`. `install.sh` removes
a previously installed copy.

## v0.18.0 — 2026-07-27 — freeze-safe cache expiry, account identity, 7d hybrid reset

**New: account identity for multi-account credential overlays.** One
`~/.claude` used to imply one account; deva-style runners broke that by
bind-mounting a different `.credentials.json` per container over the same
shared config home. The "account-scoped" caches (`usage.cache`,
`profile.cache`, `usage.jsonl`) then bled across accounts: B rendered A's
5h/7d bars whenever A fetched last, and the profile stuck to whichever
account fetched first for 24h. The credentials file itself carries no
stable identity (tokens rotate), so the runner must say who the session
is: `STATUSLINE_ACCOUNT` (explicit) or `DEVA_AUTH_TAG` (set by deva from
`--auth-with`). When present, the user segment shows an `@tag` chip
(`[MAX|@work]`, tag beats the profile display name — two accounts can
carry the same human name) and account state moves to
`accounts/<tag>/` under the shared statusline dir: same-account sessions
still share one fetch, different accounts stop clobbering each other.
`auth-default` (single-account) changes nothing; an explicit
`CLAUDE_DATA_DIR`/`CLAUDE_CACHE_DIR` override is respected verbatim; tags
are sanitized to a filesystem-safe charset before touching a path. The
chip also renders for API-key/custom-endpoint sessions, which skip the
OAuth quota block — exactly the sessions only a tag can tell apart.

**Fix: the ≡ cache badge no longer disappears next to the bright context
bar.** An all-dim badge was invisible in real use; the glyph now keeps
full weight (yellow while building, white for the `--cache always`
deadline) with only the trailing meta dim.

**Fix: the 7d pressure suffix no longer decays in a frozen frame.** The
badge kept a relative countdown (`@6h`, `@<1h`) inside the last day —
the same decaying-countdown mistake the 5h badge fixed twice (v0.6,
v0.11), and it showed only under pressure, i.e. exactly when a stale
`@<1h` convinces you you're still capped after relief already arrived.
Now hybrid: day-relative `@Nd` while >= 24h out (decays one day per day;
mild, and the narrowest honest form), wall-clock `@04:00` inside the last
day — the 5h badge's idiom, unambiguous under 24h via next-occurrence
reading, and true no matter how stale the frame is. Zero width cost.
(Resolves the open decision in
docs/devlog/2026-07-15-statusline-refresh-mechanism.org.)

**New: prompt-cache expiry warning that survives an idle gap — "quiet until
it bites".** Claude Code re-renders the statusline only on activity (mount,
new assistant message, mode/model change — no timer; see
docs/devlog/2026-07-15-statusline-refresh-mechanism.org), so nothing can
appear *during* the idle gap where the cache actually dies. And while active
the cache is always freshly ~1 TTL from expiry, so there is no honest
"expiring soon" to render. So `auto` stays silent while healthy — no width
on a deadline that's always ~an hour out — and speaks only when a rewrite
actually happened:

- **`≡!419k` on resume**: the first post-idle render sees activity after
  a gap longer than the TTL and reports the rewrite, sized at the re-cached
  prefix (observed live: 68min idle -> `read=0 write=87869`, the full
  context re-cached at ~20x the read rate; on subscriptions it burns 5h/7d
  quota too). **Bold red past 200k** — the premium-band miss. Fires even
  when the 300ms render debounce skipped the `read=0` turn, because the
  detector keys off the stale activity anchor, not the one-frame collapse.
  Held 60s wall-clock so a busy turn's refresh doesn't erase it.
- **Anchor-slide fix**: the activity anchor re-stamps only when the usage
  numbers change. Renders also fire on vim/permission/model changes carrying
  the previous turn's usage; re-stamping there slid the anchor forward and a
  frozen frame would claim a warm cache after it died.
- **`--cache always` keeps the freeze-safe deadline** `≡@15:20` (last
  request + TTL) for anyone who wants to read "resume or start fresh?" from
  the frozen frame before typing. Wall-clock, never a countdown.
- **TTL default matches how the CLI actually caches** (from CC source +
  live traces): claude.ai subscriber REPL sessions get `ttl:"1h"` on every
  breakpoint; API-key / custom-endpoint auth stays on the stock 5m cache.
  `FORCE_PROMPT_CACHING_5M` / `ENABLE_PROMPT_CACHING_1H` honored. An
  observed `ephemeral_1h/5m` breakdown overrides and renders its class as
  provenance (`≡:5m@14:25`); the CLI does not forward the breakdown
  today. Known gap: subscriber sessions bootstrapped on overage latch 5m
  server-side — invisible here; `≡!Nk` still reports the miss.

22 new tests (287 total).

## v0.17.0 — 2026-07-13 — mitm proxy trust, diagnosable !net, unified +X flash

**Fix: every API fetch died behind a trusted mitm proxy (persistent `!net`).**
When the CLI runs under a TLS-inspecting proxy it trusts (cctrace, corporate
inspection), the statusline inherits `HTTPS_PROXY` but curl does not honor
`NODE_EXTRA_CA_CERTS` (Node-only, additive) — every fetch failed instantly
with an SSL verify error (HTTP 000), while the CLI kept working. Observed
live: 19 consecutive failures, quota frozen for 11 hours behind `!net`.

- New `curl_ca_bundle`: splices the extra cert onto a copy of the system CA
  bundle (curl has no additive flag) and passes it via `--cacert` on all
  four outbound requests (usage, profile, prepaid, OAuth refresh).
- `!net` is now diagnosable: curl's own error text (`%{errormsg}`) is logged
  and recorded in the err file — `cat usage.err` says *why* (SSL, DNS,
  refused), not just `code 000`.

**Request-header parity with the CLI.** All OAuth API calls now mirror
claude-cli exactly (verified against a v2.1.207 capture): UA
`claude-cli/<version> (external, cli)` with the version of the running CLI,
plus `anthropic-beta: oauth-2025-04-20`, `Accept`, `Accept-Encoding:
identity`. `docs/api/oauth-usage.md` re-synced to v2.1.207 (no schema change
since 2.1.201) and now documents the mitm transport pitfall.

**New: unified +X change flash.** The reverse-video flash the 5h/7d badges
already had is now a generic mechanism (`delta_flash`, one state file per
session) wired into more components — each flashes its change for 60s after
a refresh alters it:

- cost: `$7.90+.37` (cents-precise, dollars shown when the jump is >= $1)
- context: `[█░░░░░30%]+9`, and `[░░░░░░3%]-27` right after /compact —
  the drop is the point
- model-scoped quota: `fb[69%]+2`

**Test hygiene: `STATUSLINE_NO_FETCH`.** Integration tests isolate the cache
dirs but `$HOME` (and so real credentials) leaks through — once the SSL fix
landed, a bare cache dir made tests fire *real* API fetches whose background
writes raced teardown (`rm -rf: Directory not empty`, flaky ~1/8). The test
harness now exports `STATUSLINE_NO_FETCH=1`, honored by the script's main
flow: render purely from cache/stdin, never spawn a network fetch. Also
useful standalone for air-gapped/offline setups.

11 new tests (265 total).

## v0.16.0 — 2026-07-06 — atomic fetch locks (multi-instance 429 stampede)

Launching several Claude Code instances together produced 429 bursts. Two
compounding causes, confirmed against a mitm capture of CLI v2.1.201:

1. **Each CLI instance already fires 2 usage requests on boot** (two internal
   clients: `claude-cli/... (external, cli)` and `claude-code/...`). N
   instances = 2N requests before any statusline fetch.
2. **The statusline's lock was check-then-touch, not atomic** — and the
   `touch` happened *after* `get_oauth_token`, hundreds of ms after the
   check. Every freshly launched instance passed the check inside that
   window and fetched concurrently, adding up to N more requests to the
   same burst.

The statusline can only fix its own share:

- New `acquire_lock`: noclobber (`set -C`) create — atomic acquire-or-fail,
  with stale-lock reaping (orphaned locks from crashed fetchers).
- Lock is acquired **before** the token read in `fetch_usage_for_session`
  and `fetch_prepaid_balance`; released on every early-return path.
- `refresh_oauth_credentials_file` uses it too: two concurrent OAuth
  refreshes are worse than a missed one — with rotating refresh tokens the
  loser's grant can invalidate the winner's.
- Regression test: 8 concurrent fetches with a deliberately slow token read
  make exactly 1 API call (fails on the old code). Plus a 20-contender
  single-winner lock test.

New: `docs/api/oauth-usage.md` — the observed `/api/oauth/usage` wire
contract (request headers, both CLI client forms, full response schema,
`limits[]` semantics, 429 obligations), synced with Claude Code v2.1.201.
Sanitized; no credentials or account identifiers.

5 new tests (254 total).

## v0.15.1 — 2026-07-05 — scoped quota badge moves next to the model

`fb[67%]` now renders right after the model+context block instead of at the
tail of the 5h/7d cluster:

```
260128_ccreverse-up +131/-16 $10.53 fabl5[1m][█░░░░░12%] fb[67%] [MAX|you] 5h[95%@23:00] 7d[55%]
```

The scoped quota is a property of the model the session is running — the eye
looks for it where the model is, not in the account-wide quota cluster. It is
still a weekly number (same reset as the 7d badge), just scoped to one model.

- Extracted into `build_scoped_quota_display`; `build_usage_display` keeps
  only the legacy-field suppression check.
- Test count: 249.

## v0.15.0 — 2026-07-05 — model-scoped weekly quota (`fb[65%]`)

The usage API moved per-model weekly limits out of dedicated fields
(`seven_day_opus` / `seven_day_sonnet` — both now arrive null) into a generic
`limits[]` array: `kind=weekly_scoped` entries carrying
`scope.model.display_name`. The old `op`/`sn` badges silently died with that
contract change; this release reads the new shape.

- Parse `limits[]` weekly_scoped entries generically — any model family the
  API scopes a weekly limit to, current or future (Fable 5 being the one that
  surfaced the change).
- Render only the scope matching the model **this session** is running:
  `fb[65%]` on a Fable 5 session, `op[33%]` on Opus. Other models' scoped
  quotas stay hidden — the limit that constrains the session is signal, the
  rest is noise.
- Badge labels follow the existing `op`/`sn` convention: `fb` (fable), `hk`
  (haiku); unknown families degrade to their first two letters rather than
  hiding the quota behind an unmapped name.
- Legacy `seven_day_opus`/`seven_day_sonnet` rendering is kept for old cached
  responses but skipped whenever scoped limits exist (the new contract
  supersedes it).
- `build_usage_display` gains the session model as an optional 4th argument;
  both call sites pass stdin's `model.id`.

6 new tests (248 total).

## v0.14.0 — 2026-07-02 — 5h reset back to wall-clock (@14:30)

v0.11.0 re-made a mistake v0.7.0 had already fixed and documented: it turned
the 5h reset into a relative countdown (`@1h38m`). The statusline only
re-renders on activity, so a countdown rendered 30 minutes before you look at
it overstates the wait by 30 minutes — and idle is exactly when no re-render
comes to correct it.

The v0.11.0 rationale ("everything in a frozen frame is equally stale")
missed the asymmetry: cost, context %, and usage % are **"as of" facts** —
they only change with activity, and activity triggers a re-render, so a stale
frame still reads truthfully as "the state when I stepped away." A countdown
is a **"from now" claim** whose truth decays with wall-clock time at zero
activity. Wall-clock `@14:30` is the only format that stays true in a frozen
frame.

The decay rule for what a non-realtime statusline may display: a quantity is
safe if it changes only with activity, or decays slower than a plausible idle
gap. Minute-scale countdowns on a 5h window fail; the 7d badge's `@5d` passes
(day granularity) and stays relative.

### Changed

- **5h reset time is wall-clock again**: `5h[42%@14:30]`, local TZ, `@now`
  when past. Restored `format_reset_absolute` (lean version — the old `day`
  mode stays gone; the 7d badge no longer uses day names).
- v0.11.0's *always-visible* half survives: the reset time still shows on
  every live window, not just under pressure. Only the format reverted.

242 tests (4 restored), shellcheck baseline unchanged.

## v0.13.0 — 2026-07-02 — escalating fetch cooldown + categorized !badges

Live logs showed 23% of usage fetches failing 429 in clusters exactly one
backoff apart: the fixed 120s cooldown expired and retried straight into a
still-throttled window. Cross-checked against the 2.1.197 binary: the
endpoint contract is unchanged and the CLI's own `fetchUtilization` has no
429 handling either (its only retry is 401→refresh→retry) — the CLI and every
concurrent statusline render share one per-account throttle bucket, so the
client must pace itself.

### Added

- **Escalating error cooldown**: consecutive fetch failures back off
  120s → 240s → 480s → 600s (cap) instead of a fixed 120s. The err state
  survives until a fetch succeeds, so the escalation compounds; success
  clears it. Applies to both the usage and prepaid fetch paths.
- **`Retry-After` honored**: failures now capture the header via curl's
  `%header{retry-after}` (>= 7.83; older curls degrade cleanly) and the
  cooldown extends to match when the server asks for longer. Failure logs
  now include the header, consecutive-failure count, and computed cooldown.
- **Categorized stale-data indicator**: the bare `!` after quota/extra now
  says why: `!429` rate limited, `!auth` token rejected (401/403), `!5xx`
  server error, `!net` connection failed. Legacy bare-epoch err files still
  render plain `!`.
- err files are now JSON (`{at, code, count, cooldown}`); pre-v0.13.0
  bare-epoch files are read compatibly (fixed 120s window, bare `!`).

### Changed

- **Bump flash glyph: `▲` → `+`** (the Unicode triangle renders poorly in
  some terminal fonts), still reverse-video, and now bound tight to its
  badge — `5h[44%@1h18m]+2` — so it can't visually float toward the next
  badge.

226 tests (8 new), shellcheck baseline reduced by one.

## v0.12.1 — 2026-07-02 — bump flash: reverse-video ▲N outside brackets

### Changed

- **Bump flash visual**: the quota-climb indicator moved from bold `+N`
  inside the badge to a **reverse-video `▲N`** outside the brackets:
  `5h[44%@1h18m] ▲2` / `7d[10%] ▲1`. Spatially distinct + reverse video
  (inverted bg/fg) makes it unmissable without adding a fourth color lane.
  Bold-only was too subtle in most terminals, and cramming `+N` between
  `%` and `@` inside the brackets made it read as noise.
- `REVERSE`/`NO_REVERSE` (`ESC[7m`/`ESC[27m`) replaces `BOLD`/`NO_BOLD`.

218 tests, shellcheck warning count unchanged.

## v0.12.0 — 2026-07-02 — quota bump flash (▲N when 5h/7d usage climbs)

### Added

- **Bump flash**: when the 5h or 7d utilization climbs between renders, a
  reverse-video `▲N` glyph appears outside the badge for ~60s:
  `5h[44%@1h18m] ▲2` / `7d[10%] ▲1` — "you just burned 2%". Vivid without
  a new hue, so the three color lanes stay unambiguous.
- `quota_bump_notice()` + per-session state file
  (`sessions/<session_id>_quota_seen`, same lifecycle as `_cache_health`).
  Per-session on purpose: the flash compares against what THIS statusline
  last rendered, so concurrent sessions each get their own notice instead
  of racing over shared account state.
- Semantics: first sighting is quiet; a climb records the increment; an
  unchanged value keeps a still-fresh notice alive; a second climb
  overwrites (latest increment, not a running sum — "▲N" answers "what just
  happened"); a drop (window reset) clears silently, the fresh low number
  being its own signal.
- `QUOTA_BUMP_NOTICE_SECS` (60) constant.

### Fixed

- Test helpers still defined the countdown constants and extracted
  `format_reset_absolute` — both removed in v0.11.0; cleaned up.

218 tests (9 new), shellcheck warning count unchanged.

## v0.11.0 — 2026-07-02 — always-on 5h countdown + post-compact bar reset

Two changes driven by live use: "how long until my 5h window resets" was
hidden until pressure, and `/compact` made the context bar vanish instead of
visibly resetting.

### Changed

- **5h badge always shows its window countdown while a window is live**:
  `5h[42%@1h20m]` — no more gating on usage >= 80% or reset <= 2h. On a 5h
  horizon the time remaining is the number you plan the current sitting
  around, so hiding it until pressure hid the badge's most useful signal.
- **5h countdown is relative (`@1h20m`), not wall-clock (`@14:30`)** — this
  deliberately reverses the v0.5-era "absolute stays true without re-renders"
  decision. Three reasons: (1) remaining time is the actual question; a wall
  clock makes you do the subtraction. (2) The 7d badge already went relative
  (`@5d`) when the pace model landed — 5h absolute was the leftover
  inconsistency, and one `@remaining` language beats two. (3) The staleness
  argument proves too much: when the CLI stops invoking the statusline, the
  usage %, cost, and context bar in the same frame are equally stale — a
  wall-clock reset time being technically true doesn't make a frozen frame
  fresh. During active use, renders arrive seconds apart.
- **A real stdin 0% renders an empty context bar** (`[░░░░░░0%]`) instead of
  nothing. Observed live: after `/compact` the CLI pushes
  `used_percentage: 0` for the reset window, and hiding the bar at zero read
  as "the statusline didn't refresh" — the visible snap to empty IS the
  refresh. Absent data (no `context_window`, no transcript) still renders no
  bar; only a genuine zero shows one.

### Removed

- `format_reset_absolute()` and its 6 unit tests (the 5h badge was its last
  caller), plus the now-dead `FIVE_HOUR_COUNTDOWN_SECS` /
  `SEVEN_DAY_COUNTDOWN_SECS` gating constants.

Note on the freeze *during* compaction: the CLI simply does not invoke the
statusline while compacting (~90s observed), and a statusline script is a pure
function of its stdin — the first post-compact payload now visibly resets the
bar, which is everything script-side can do.

209 tests (3 new), shellcheck-clean at the same baseline as v0.10.2.

## v0.10.2 — 2026-06-12 — fix false [1m] tags from misread exceeds_200k_tokens

A systematic audit of the live debug log (857 real turns across two rotated
log files) found `exceeds_200k_tokens` was being misread since the v0.9.1 1M
detection rework. It does not mean "this window is bigger than 200k" — it
means "this session's cumulative token usage has passed 200k so far." On a
genuine 200k-window model (`claude-opus-4-6`, no `[1m]` suffix), once a long
session's total usage crosses 200k, the CLI reports the flag `true` too —
`total_input_tokens > 200000` predicted the flag in 839/840 sampled turns;
`context_window_size > 200000` predicted it in only 719/840. Treating it as a
window-size signal put a false `[1m]` tag on **~14% of observed renders**
(121/857) — every long-running session on a real 200k model.

### Fixed

- **`is_1m_model`**: dropped the `exceeds_200k_tokens` fallback tier entirely.
  `context_window_size` (`ctx_size`) is reported on every sampled turn and is
  the actual ground truth for window capacity; the `[1m]` suffix / default-1M
  family check remains as the fallback for older CLIs that omit `ctx_size`.
- **`premium_band_level`**: same fix — the flag no longer forces the yellow
  band on a low-usage 1M session or a real 200k session. Band is now purely
  `context_pct x ctx_size` against the 200k/800k thresholds.

212 tests (6 new), shellcheck clean.

## v0.10.1 — 2026-06-12 — Claude Sonnet 5 support

Claude Code 2.1.197 shipped Claude Sonnet 5, and it broke the statusline the
same way Fable 5 did back in v0.9.1 — plus a new one.

### Fixed

- **`sonnet5.5[1m]` instead of `sonnet5[1m]` (critical, live-broken).**
  `abbreviate_model_id` assumed every `claude-opus-*`/`claude-sonnet-*`/
  `claude-haiku-*` ID has a major.minor version pair (`opus-4-8` -> `opus4.8`).
  Sonnet 5 uses flat versioning (`claude-sonnet-5`, no minor component), so the
  minor-extraction fallback re-read the major digit as the minor and doubled
  it: `sonnet` + `5` + `.` + `5`. Fixed by checking whether the id has a second
  version component before appending one.
- **1M context not detected for suffix-less Sonnet 5.** Same pattern as Fable
  5 in v0.9.1: Claude Code 2.1.197 omits the `[1m]` suffix for Sonnet 5 because
  1M is now its default (confirmed live: `context_window_size:1000000`,
  `exceeds_200k_tokens:true`, `model.id:"claude-sonnet-5"`, no suffix).
  `is_default_1m_family` only matched `fable`; added `sonnet-5` by exact major
  version so `sonnet-4-6`/`sonnet-4-5` correctly stay opt-in.

206 tests (5 new), shellcheck clean.

## v0.10.0 — 2026-06-12 — learned 7d forecast + premium band in the bar

The original initiative, delivered: the statusline watches your 7d usage with
a model of YOUR week — learned from your own history, not assumed — and warns
when you'll run out of usage while days still remain in the window.

### Added

- **Learned weekday burn profile.** `build_seven_day_profile` (hourly, inside
  the TTL-gated fetch path) scans `usage.jsonl` and writes `forecast.cache`:
  per-weekday %/day (EWMA, 14-day half-life) plus recent 24h/48h burn.
  Partitioned by account uuid — interleaved multi-account history produces
  garbage rates otherwise. Plan upgrades fade out via the EWMA. Pure epoch/awk
  arithmetic, no GNU date extensions; 195 days of history builds in ~0.2s.
- **Forecast verdict.** `seven_day_forecast` walks the remaining window
  day-by-day against the profile (first 24h burns at max(profile, recent-24h))
  and flags when quota dries before reset: yellow, red when dry >= 2 days
  early. Escalates the pace color — it knows your heavy Tuesday is still
  ahead when the window-average looks calm. Cold start (< 14 days of history)
  falls back to window-average pacing silently.
- **`claude-watch.sh` forecast line**: projected dry day + the learned
  profile: `forecast dry ~Mo (2.4d before reset)  profile/d Mo12 Tu16 ...`.
- **`usage.jsonl` rotation** at 32 MiB (single `.1` backup; the profile
  builder reads both, so rotation never costs learned history).

### Changed

- **Premium pricing band moved into the context bar.** `fabl5[1m:320k]` was
  redundant — 320k IS the bar's 32%. The model tag is a constant `[1m]`; the
  bar color now carries the band: yellow past 200k, red past 800k.
- **7d reset shows explicit time remaining** — `@5d` / `@18h` (timezone-proof,
  unlike a day name) — whenever the verdict warns, even with the reset days
  away. "Abnormal burn" is exactly when you need to know how long the window
  still has to run.

## v0.9.6 — 2026-06-12 — pace verdict is color-only (no runway text)

Two attempts at a compact runway number (`~2d`, then `2d!`) were both misread
as "days until reset" — a second time-unit sitting next to a 7-day metric
cannot win, no matter the label. The derived number is gone.

### Changed

- **7d badge shows no runway text.** The pace verdict (will the quota outlast
  the window?) is carried by color alone; under pressure the `@reset` deadline
  appears — a fact, not a model: `7d[40%]` yellow (early overshoot), `7d[70%]`
  green (late, safe), `7d[95%@Mon]` red. The pace engine (`seven_day_pace`) is
  unchanged underneath, including `CLAUDE_7D_WORKDAYS`.

### Notes

- Reset times render in the local timezone of wherever the statusline runs.
  If your containers run in a different TZ than your other monitors, set `TZ`
  in the container for matching `@day` labels.

## v0.9.5 — 2026-06-12 — readable runway warning (Nd!)

`~2d` confused its own audience: it mixed two time quantities (quota-runway vs
reset-deadline) into one unlabeled number inside a `%` badge — "2 days until
what?". Reworked for legibility.

### Changed

- **Runway hint is now `Nd!`**, space-separated from the percentage:
  `7d[37% 2d!]` = ~2 days of quota left at the current burn rate. The `!` marks
  it as a warning rather than a neutral stat; the space keeps it from reading
  as part of the percentage. Still shown only under pace pressure — on-pace
  badges stay a bare `7d[27%]`.
- **Fable identity color → bright red (`0;91`)**, matching Fable's color in the
  Claude Code TUI (was bright magenta). Pressure red stays `0;31`, so alarms
  remain distinguishable. `claude-watch.sh` and the hero preview follow.

## v0.9.4 — 2026-06-12 — window-aware quota merge (multi-session freshness)

With several Claude Code instances running, the 5h/7d numbers lagged: an idle
session's stdin can carry a rate-limit window that already reset hours ago,
and the old merge let stdin clobber the shared cache unconditionally — even
when another session's fetch had just written fresher data. Observed live: one
session's stdin said 5h=33% on an expired window while the shared cache held
47% on the current window, fetched two minutes earlier.

### Fixed

- **Window-aware merge.** Neither stdin nor the cache is always fresher, and
  stdin carries no timestamp — but two structural facts decide it without one:
  across windows the later `resets_at` IS the newer window; within one window
  utilization only increases. Per window: newer `resets_at` wins outright;
  same window takes the max utilization. Stale stdin can no longer mask
  fresher cross-session data, and a frozen cache still self-heals (its
  `resets_at` falls behind stdin's).

### Notes

- Context (`NN%` / `[1m:NNNk]`) is per-session by design — it comes from that
  session's own stdin, never from shared state, so concurrent instances cannot
  pollute each other's context display.

## v0.9.3 — 2026-06-11 — show the model that's actually running (critical)

The displayed model came from `settings.json .model` (a static default) and
only fell back to the stdin `model.id` when settings had none. So a session
running Opus 4.6 while `settings.json` defaulted to `claude-fable-5[1m]` rendered
`fabl5` — the wrong model — and worse, the **name and the context window came
from different sources**: `fabl5` (settings) sat on top of a 200k/Opus context
(stdin). On a 200k model mislabeled as 1M-default Fable, the context felt
roomier than it was and the session hit the limit by surprise.

### Fixed

- **The displayed model is now the one the session is actually running**, read
  from the stdin `model.id` — the same source as the context window, so the name
  and the window can never disagree. A session that switches models mid-flight
  (`/model`, `--model`) is tracked correctly every render.
- **`settings.json .model` is now a fallback only** — consulted (and even read)
  solely when stdin carries no model id. It can no longer shadow the running
  model.
- The stdin model path now uses the full-strength identity color (e.g. `0;95`
  magenta for fable) instead of the old dim variant, matching the documented
  look.

### Notes

- The `opusplan` settings shorthand only renders via the fallback now; with a
  real `model.id` on stdin the badge shows the model actually in use, which is
  more accurate per render.

## v0.9.2 — 2026-06-11 — 7d quota paced, not leveled

The weekly quota color used a pure level threshold (yellow at 70%, red at 85%),
which is wrong in both directions: 70% on day 6 is a false alarm (you'll easily
make it), and 40% on day 1 is a real danger shown as calm green. The 7d badge
now judges **pace** — will the quota outlast the window? — using two numbers
already on stdin: `used_percentage` and `resets_at`.

### Added

- **Pace-aware 7d color.** Compares runway (quota-time left at the current burn)
  against the time until reset. A 10% buffer keeps marginal overshoots quiet, so
  the badge warns only when you'll genuinely fall short. Fixes the false-alarm
  (high-but-late) and missed-warning (moderate-but-early) cases.
- **Runway hint** `~Nd` — days of quota left at this burn rate — shown beside the
  percentage under pace pressure: `7d[40%~3d]`, `7d[95%~0d@Mon]`.
- **`@reset` gating tied to pressure**, not a fixed 70% level — it appears when
  the pace warns or usage is already high, and the reset is within 3d. On-pace
  usage stays a bare `7d[27%]`, no clock noise.
- **`CLAUDE_7D_WORKDAYS`** (opt-in, default off) — skips weekend days in the
  deadline so the meter doesn't alarm over Sat/Sun you won't spend quota on. The
  limit itself stays calendar-based; this only adjusts the planning view, and
  only changes the verdict in the borderline band where it's decision-relevant.

### Notes

- Early-window guard: pace isn't judged in the first ~8h (a single opening burst
  would otherwise read as a runaway); the badge falls back to level there.
- The opus/sonnet sub-quotas (`op`/`sn`) remain level-based — they're secondary.

## v0.9.1 — 2026-06-11 — authoritative 1M detection

Claude Code 2.1.173 stopped appending the `[1m]` suffix whenever 1M is the
active default. Real session logs show this on **both** Fable 5 and Opus 4.8
(`exceeds_200k=true` at ~24% context proves a >200k window with no suffix in the
id). Our `[1m]` detection keyed on the suffix, so those sessions lost their tag
*and* their premium-band cost cue, and the context bar measured against 200k
instead of 1M.

### Fixed

- **`[1m]` tag + premium cue restored for suffix-less 1M sessions.** Detection
  now prefers the CLI's authoritative signals over the model name, in order:
  1. `context_window_size > 200k` — the window the CLI itself reports.
  2. `exceeds_200k_tokens=true` — only a >200k window can exceed 200k tokens.
  3. `[1m]` opt-in suffix, or a family that defaults to 1M (`is_default_1m_family`
     — fable) — name fallbacks for older CLIs that send neither of the above.
- **`opus4.6[1m]` opt-in** unchanged — the suffix path still drives the tag and
  the 1M window (verified by a dedicated compat test).
- **`get_context_limit`** (transcript fallback for pre-`ctx_pct` CLIs) also
  treats a 1M-default family as 1M, so the fallback bar matches.

### Changed

- **Premium-band trigger** prefers the authoritative `exceeds_200k_tokens` flag
  over our own `context% × size` arithmetic. When the flag fires but the
  computed number doesn't itself clear 200k (e.g. exactly 20% of 1M, the common
  boundary case), the cue degrades to `[1m:200k+]` rather than printing a
  contradictory sub-200k figure.

## v0.9.0 — 2026-06-10 — color system (three lanes)

A deliberate palette redesign so a glance is unambiguous. Color follows three
lanes:

- **Status** (green/yellow/red) = pressure ONLY — quota, context, cache, the
  premium context band, expensive effort. Warm color always means "near a limit
  or cost."
- **Identity** (magenta/cyan/blue) = model family only.
- **Neutral** (grey/white by weight) = structure & you.

### Changed

- **Cost** moved off yellow → neutral grey (it's info, not a warning).
- **Path** → neutral grey (was cyan, which collided with sonnet).
- **Dirty branch** → bright white + `*` (was yellow); clean branch dim.
- **Tier** → neutral white-weight: MAX bold white, PRO white, ENT/TEAM dim. (MAX
  was green — collided with "quota healthy"; PRO was cyan — collided with sonnet.)
- **Haiku** → bright blue (was a hard-to-read dark blue).
- **Premium context cue** escalates with depth: `[1m:300k]` yellow past 200k,
  `[1m:900k]` red past 800k.
- `claude-watch.sh` model colors aligned (haiku → blue; opus/fable/sonnet match
  the statusline).

Net: yellow used to mean six things (dirty · cost · premium · max-effort · 5h ·
7d). Now warm color means pressure, full stop.

## v0.8.1 — 2026-06-10 — quieter effort badge

- Effort badge is now **lowercase** — `lo` / `md` / `xh` / `max` / `ultra` /
  `auto` instead of `L`/`M`/`XH`/`MAX`/`ULTRA`/`AUTO`. It's secondary metadata
  that renders on every line (especially for `xhigh` users, where it was
  effectively always-on), so it should stay quiet. Color still carries the
  weight: routine levels are dim; the expensive modes (`max`, `ultracode`) keep
  the pressure color. `high` remains the hidden default.

## v0.8.0 — 2026-06-10 — Shared Account Cache, fabl5, claude-watch, quota freshness

Tested against Claude Code CLI v2.1.170 (MAX and PRO accounts), Fable 5, and
the 20x Max plan.

### Quota freshness — the "5h stuck at 100%" fix

The 5h/7d number could stay frozen (e.g. stuck at 100% after a plan upgrade or
a window reset) even though the account was no longer rate-limited.

- **Prefer the CLI's stdin `rate_limits` for 5h/7d.** Claude Code passes
  current-plan, current-window quota numbers in stdin on every render. We now
  overlay those onto the cached usage data, so the displayed 5h/7d are always
  fresh and zero-cost. This self-heals plan upgrades (utilization is relative to
  the plan limit), window resets, and a stale/frozen cache. `extra_usage` and
  per-model 7d breakdowns (not in stdin) still come from the cache. New
  `merge_stdin_rate_limits()`.
- **Reap stale fetch locks.** The fetch gate skipped launching while a `*.lock`
  existed but never reaped it, so one orphaned lock (from a fetch that died
  mid-flight) could freeze the cache indefinitely. New `reap_stale_lock()`.
- **7d reset shown only near the cap.** A reset time is irrelevant at low usage,
  and a bare clock on a 7-day metric (`7d[1%@09:00]`) was confusing — the
  `@time` now appears only at >=70% utilization.

### Model display — fabl5, premium-band cue, effort badge

- `claude-fable-5` abbreviates to **`fabl5`** (4-char family + version).
- **`[1m:NNNk]`** — on a 1M-context model, once you pass 200k tokens (the
  premium input-pricing band) the tag shows absolute context in a warning
  color, e.g. `fabl5[1m:300k]`. Below 200k it stays `[1m]`.
- **Effort badge** — `low/medium/xhigh/max/ultracode/auto` render as compact
  `L/M/XH/MAX/ULTRA/AUTO` (`high` is the default and stays hidden). The
  expensive modes (`MAX`, `ULTRA`) use a warning color; the rest stay dim.

### Robustness & security

- **macOS portability**: every reset/countdown path now falls back from GNU
  `date -d` to BSD `date -j`/`-r`, so these no longer silently vanish on macOS.
- **Clean degradation**: empty/malformed stdin no longer prints fabricated
  `+/- 0m $0` — activity/time/cost are gated numerically, and sub-cent costs are
  no longer shown as `$0`.
- **`umask 077`**: caches and the debug log (which hold account PII) are written
  owner-only — important on a shared bind-mounted `~/.claude`.

### Account-Level Usage Cache (fewer API calls)

Quota data from `/api/oauth/usage` (5h / 7d / extra) is **account-scoped** —
it's identical for every session on the account. Previous versions cached it
per `session_id`, so each new session refetched the same data and N concurrent
sessions meant N redundant API calls (rate-limit risk).

Account-scoped state now lives in a single shared directory and one fetch
serves all concurrent sessions:

```
~/.claude/statusline/                  account-scoped (shared)
  usage.cache  profile.cache  prepaid_credits.cache  usage.jsonl
~/.claude/statusline/sessions/         per-session (cache-health only)
  <session_id>_cache_health
```

- Per-session prompt-cache-health state is unchanged (it legitimately tracks
  one context window) and stays under `sessions/`.
- Adaptive TTL, error backoff, and lock-file behavior are preserved; locks are
  now shared so concurrent sessions coordinate a single in-flight fetch.
- Graceful migration: if the old `$SCRIPT_DIR` layout exists and the new
  shared dir is empty, `usage.cache` / `profile.cache` /
  `prepaid_credits.cache` / `usage.jsonl` and the `sessions/` dir are moved
  over on first run (best-effort; falls back to a fresh fetch).
- `CLAUDE_DATA_DIR` / `CLAUDE_CACHE_DIR` overrides still work. Setting only
  `CLAUDE_CACHE_DIR` keeps the old single-dir behavior (account data lives
  alongside it).

### Debug Logs Out of /tmp

Debug logs default to `~/.claude/statusline/logs/statusline.log` instead of
`/tmp`. Safe for many concurrent statusline processes — across containers —
sharing one mounted `~/.claude`:

- Append-mode writes (`echo >>`) are atomic for the small lines we emit, so
  interleaving never corrupts a line. Each line is tagged with `[pid:N]`.
- A 1 MiB size cap rotates the file (single `.1` backup) using an atomic
  `mkdir` lock so concurrent processes don't all rotate at once.
- `DEBUG_LOG` env override still wins; `DEBUG_LOG_MAX_BYTES` tunes the cap.

### claude-fable-5 Support

`claude-fable-5` renders consistently with the opus / sonnet / haiku branches:

- Abbreviates to `fabl5` (single-component version, no `major.minor` split).
- Bright-magenta color (`95`), keeping it in Opus's capability-group hue while
  staying distinct from `opus`'s magenta.
- `[1m]` context suffix handled like every other model (`fabl5[1m]`).

### claude-watch.sh — Live Usage Watcher

New standalone companion. A "top"-style full-screen view of one session:

- **Per-turn**: estimated cost + input / output / cache-read / cache-create
  tokens for the latest assistant message.
- **Session totals**: cumulative tokens and estimated cost across the
  transcript (each turn priced at its own model's rate).
- **Quota**: 5h / 7d (and extra, when present) read from the shared
  `usage.cache` statusline.sh maintains.

Reads the transcript, the account usage cache, and `usage.jsonl` — all
read-only. Cost is an estimate from public per-million list pricing (mirrors
the `ccx` tool's pricing tiers); fast-mode surcharges are not modeled.
Resilient streaming parse tolerates malformed/oversized transcript lines and
renders a 27 MB / 4500-turn transcript in ~0.2s. `--help`, `--once`,
`--interval`, `--session`, `--transcript`, `--no-color`.

### Added

- Shared `usage.cache` / `usage.lock` / `usage.err` under the account dir;
  `fetch_usage_for_session` writes once for all sessions
- `migrate_legacy_state()` for graceful one-time migration from `$SCRIPT_DIR`
- `rotate_debug_log()` with size-capped, lock-guarded rotation
- `claude-fable-5` branches in `get_runtime_model`, `abbreviate_model_id`, and
  both model-color code paths
- `claude-watch.sh` (installed by `install.sh` alongside `statusline.sh`)
- `merge_stdin_rate_limits()`, `reap_stale_lock()`, `build_1m_tag()`,
  `abbrev_effort()`, `effort_color()`, and portable `_epoch_from_ts()` /
  `_fmt_epoch()` date helpers
- Test suite grew from 145 to 172 (fabl5, premium-band cue, effort badge,
  stdin-overlay precedence, stale-lock reaping, portable date helpers,
  clean-degradation on empty/sub-cent input)

### Changed

- Debug log default moved from `/tmp/claude-code-statusline.log` to
  `~/.claude/statusline/logs/statusline.log`
- Account-scoped caches (`usage`, `profile`, `prepaid_credits`, `usage.jsonl`)
  default to `~/.claude/statusline/` instead of `$SCRIPT_DIR`

## v0.7.0 — 2026-05-27 — Prompt Cache Health & Absolute Reset Times

Tested against Claude Code CLI v2.1.150 (MAX and PRO accounts).

### Cache Health Indicator

Detects prompt cache invalidation from per-turn token data already in
the CLI's stdin JSON. Uses the same token-drop threshold as Claude Code's
internal `promptCacheBreakDetection.ts`: flags a break when
`cache_read_input_tokens` drops >5% and >2000 tokens from the
previous turn.

- `cache!` (red) — cache-read drop detected; full or partial rebuild likely
- `cache~` (dim yellow) — cache building, first turn or post-break rebuild
- `cache:1h@14:20` / `cache:5m@14:20` — TTL class plus last observed
  cache activity when future/current stdin provides TTL breakdown
- Hidden when healthy by default — zero noise during normal operation
- `--cache auto|always|off` controls cache display

Display appears after the context bar:

```
opus4.6[1m][███░░26%]              (healthy — no indicator)
opus4.6[1m][███░░26%] cache:1h@14:20~ (building — first turn)
opus4.6[1m][███░░26%] cache!       (break — full rebuild)
```

State tracked in `${session_id}_cache_health` as JSON. Older one-number
state files are still accepted and upgraded on the next render.

No cache expiry countdown is shown. Claude Code does not expose a
pre-request server `expire_at`; the statusline records observed cache
activity and, when observed in usage breakdown, the 5m/1h TTL class.
Current Claude Code statusline stdin usually exposes aggregate cache tokens
only, so TTL class display is forward-compatible rather than guaranteed.

### Why It Matters

A single cache break on a 1M-context Opus session costs ~22x more than
a cached turn. For subscription users, that's quota burn equivalent to
20+ normal turns. The indicator makes this invisible cost visible.

### Added

- `get_cache_health()` function with four return states: `ok`, `break`,
  `building`, `none`
- `infer_cache_ttl_class()`, `format_cache_active_time()`, and
  `build_cache_indicator()` helpers
- `CACHE_BREAK_MIN_TOKENS` (2000) and `CACHE_BREAK_DROP_PCT` (5)
  threshold constants
- Extracts `cache_read_input_tokens`, `cache_creation_input_tokens`,
  `input_tokens`, and optional `cache_creation.ephemeral_1h_input_tokens`
  / `cache_creation.ephemeral_5m_input_tokens` from stdin
- Per-session state file (`${session_id}_cache_health`) prevents false
  positives when running concurrent Claude Code sessions
- `mkdir -p` plus atomic state-file replacement ensures detection works for
  API key users where `$CLAUDE_CACHE_DIR` may not exist yet
- 28 new tests (22 unit + 6 integration)

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

145 total tests across both suites.

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
