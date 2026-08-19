# Claude Code Statusline

> Quota, context, cost, model, and git -- live in your Claude Code prompt.

[![tests](https://github.com/thevibeworks/claude-code-statusline/actions/workflows/test.yml/badge.svg)](https://github.com/thevibeworks/claude-code-statusline/actions/workflows/test.yml)
[![version](https://img.shields.io/github/v/tag/thevibeworks/claude-code-statusline?label=version&sort=semver)](https://github.com/thevibeworks/claude-code-statusline/tags)
[![license](https://img.shields.io/github/license/thevibeworks/claude-code-statusline)](LICENSE)
[![bash](https://img.shields.io/badge/shell-bash-4EAA25)](statusline.sh)
[![deps](https://img.shields.io/badge/deps-jq%20%2B%20curl-blue)](#install)

<p align="center">
  <img src="assets/statusline-preview.svg" alt="Claude Code Statusline" width="100%">
</p>

<p align="center"><a href="https://thevibeworks.github.io/claude-code-statusline/"><b>Live animated demo →</b></a></p>

One Bash file that plugs into the official `statusLine` command hook. Shows
what matters: active model, context window, session cost, 5h / 7d quota with
reset times, prompt-cache health, extra-usage spend, git activity, and subscription tier.
When the numbers stop meaning what they appear to mean, an [advisor second
row](#advisor-line) interprets them — cap projections, expiring-surplus and
underuse advice, per-model weekly limits, sibling-account relief.
No daemon, no telemetry, no npm.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh | bash
```

Downloads `statusline.sh` to `~/.claude/` and wires up `settings.json`.
Restart Claude Code (or send a message) and the statusline appears.

**Requires:** Bash, `jq`, `curl`.

### Install via Claude Code

Paste this into Claude Code and it will set everything up:

```
Install claude-code-statusline: download https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/statusline.sh to ~/.claude/statusline.sh, make it executable, and add a statusLine command entry to ~/.claude/settings.json pointing to it with padding 0.
```

<details><summary>Manual install / inspect first</summary>

```bash
# Download and inspect
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh -o /tmp/install-statusline.sh
less /tmp/install-statusline.sh
bash /tmp/install-statusline.sh

# Or skip the installer entirely
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 0
  }
}
```

</details>

## What It Shows

```text
project (main*)  +84/-14 1h30m $6.72 opus4.8[1m][███░░░26%] [MAX|you] 5h[87%@14:30] 7d[75%@2d] ex[$16.29/$200 8% bal$4.66]
   |       |       |      |     |       |                     |             |             |              |
 path   branch   edits   time  cost   model+context          user        5h quota      7d quota      extra usage
```

Every component earns its place:

| Signal | Why it matters |
|--------|----------------|
| Path and branch | Know where Claude Code is writing. Neutral grey; a dirty branch brightens to white with a `*`. |
| Trace chip | `[http://localhost:9317/s/c3a6e0f3]` when the session's wire is being captured by [cctrace](https://github.com/thevibeworks/cctrace) (`deva --trace`, or `cctrace` directly) — a full URL so terminals linkify it, deep-linking `/s/<sid8>` (cctrace >= 0.40) straight to *this* session's conversation scrolled to the newest turn; without a session id the link falls back to the `/trace` live page. `DEVA_TRACE_UI_URL` (exported by deva on traced create/reattach) outranks the container-side port, since only the host side knows the published port. **Line 1 must fit the terminal** (Claude Code hands the script `COLUMNS` and truncates or wraps anything wider, which throws every anchored row beneath the wrong edge), so when the full URL would not fit, the chip collapses to `[cctrace]` carrying the same target as an OSC 8 hyperlink — 9 columns, still one click on iTerm2/kitty/WezTerm — before the path/stats gap gives. Session identity, so it sits on the left with path and branch, dim (red stays reserved for pressure). Detected from the trace env cctrace exports into the traced process (`CCTRACE_SERVER_PORT`), from the capture's CA plumbing (`NODE_EXTRA_CA_CERTS` under a cctrace dir), or from `DEVA_TRACE=1`; when only the plumbing is visible (older cctrace) the port resolves through cctrace's live-instance registry, matched by session id (sid8 prefix — the registry stores ids redacted), then project path, then by being the only live capture, with the fallbacks trusting heartbeat-fresh entries only. A traced session with no resolvable port still shows a bare `[cctrace]` — "recorded" matters even portless. |
| Activity | Session diff without opening git. |
| Time and cost | Track long sessions. Hours format above 60m (`1h30m`). |
| Model | Abbreviated: `claude-opus-4-8` becomes `opus4.8`, `claude-fable-5` becomes `fabl5`, `claude-sonnet-5` becomes `sonnet5`. The `[1m]` tag marks a 1M-context session, detected from the window the CLI reports (`context_window_size`) — not the name — so it shows even when Claude Code strips the `[1m]` suffix (which it does since 2.1.173 whenever 1M is the default; Sonnet 5 joined Fable 5 on that path in 2.1.197). |
| Effort | Compact lowercase badge: `lo` / `md` / `xh` / `max` / `ultra` / `auto` (`high` is the default and stays hidden). Dim for routine levels; `max` / `ultra` use the pressure color; `fast` shows in fast mode. |
| Context bar | Merged with model. Green / yellow / red by window pressure. On 1M models the bar also carries the premium input-pricing band: yellow past 200k tokens, red past 800k — the % alone looks calm (320k = 32%) while every request bills at the premium rate. A real 0% (e.g. right after `/compact` resets the window) renders a visibly empty bar `[░░░░░░0%]` — the snap to empty *is* the refresh signal; the bar hides only when no context data exists at all. Changes flash for ~60s in reverse video: `[█░░░░░30%]+9` while filling, `[░░░░░░3%]-27` right after a compaction. Cost flashes the same way, cents-precise: `$7.90+.37`. |
| User tier | Neutral white-weight (MAX bold, PRO normal, dim otherwise) — identity, never a status color. Truncated display name. |
| Quota | Integer percentages. The 5h badge always carries its reset time while a window is live — `5h[42%@14:30]` reads "42% used, resets at 14:30" — because on a 5h horizon the reset is the number you plan the current sitting around. Wall-clock, not a countdown, on purpose: Claude Code only re-renders the statusline on activity, so a relative "@1h38m" silently decays into a lie during idle gaps, while "@14:30" stays true in a frozen frame. (The 7d badge is hybrid: day-relative `@5d` while the reset is >= 24h out — decays one day per day, mild and narrow — switching to the same wall-clock `@04:00` inside the last day, where an `@6h`/`@<1h` countdown decayed by the hour exactly when pressure keeps the suffix visible.) When a window's utilization climbs between renders, a reverse-video `+N` token appears right after the badge for ~60s: `5h[44%@14:32]+2` means "you just burned 2%". A drop (window reset) stays quiet — the fresh low number is its own signal. **7d is forecast, not leveled**: a learned per-weekday burn profile (EWMA over your own usage history) plus your recent 24h burn project whether the quota outlasts the window — your heavy Tuesday counts more than a generic average. The verdict is color alone; under pressure the badge shows when relief arrives: `7d[44%@5d]` red means "at your pace, dry days before the reset 5 days from now"; inside the last day it reads `7d[92%@04:00]` — resets at 04:00. Cold start (<14 days history) falls back to window-average pacing. Recovery color when reset is imminent. **Model-scoped weekly quota**: when the usage API carries a per-model weekly limit (`limits[]`, `kind=weekly_scoped`) for the model your session is running, it renders right after the model+context block — `fabl5[1m][12%] fb[67%]` on a Fable 5 session, `op[33%]` on Opus — because the quota is a property of the model you're running, not of the account-wide 5h/7d cluster. It's a weekly number (same reset as the 7d badge), scoped to one model. Other models' scoped quotas stay hidden: only the limit constraining *this* session is signal. Supersedes the legacy `seven_day_opus`/`seven_day_sonnet` fields, which the API now sends as null. |
| Extra usage | Monthly spend, limit, prepaid balance. `--extra auto` shows when quota runs out. |
| Week row | **A row of its own, under the badges**: `5h ▂▅█▃▮▯▯▯▯▯ 0.9x @23:00  7d ▅▁▂ ▃▅ˍ▃▅ …▮▯▯ 0.7x @Wed 09:00` — this sitting as ten half hours, the week as its 5h windows (day-gapped), height = what each cell burned, `▮` now, `×` where the pool runs dry, each strip ending with its pace and reset. Reconstructed from your own usage log; `auto` shows it once there is history to show. See [Week row](#week-row). |
| Deadman | **Invisible until a switch is armed.** Surfaces [deadman](https://github.com/thevibeworks/deadman) — a dead man's switch that hands the session off when you stop responding. `[☠ armed 42m]` (dim) counts down to the auto-handoff; `[☠ warned 3m]` (yellow) means the phone warning went out; `[☠ due]` means the handoff fires imminently. Sits on the left lane next to the path — it describes this session's lifecycle, not a quota. One `command -v` when the tool is absent, one fast file read when present; nothing armed renders nothing. `--deadman off` disables it. |
| Cache health | **Quiet until it bites.** Claude Code never re-renders an idle session, and while you work the prompt cache is always freshly ~1 TTL from expiry — so a proactive "expiring soon" isn't honestly observable, and `auto` spends no width on it. It speaks only when a rewrite actually happens: `≡!419k` the instant you resume onto a dead cache (idle longer than the TTL) or a mid-session prefix collapse — a 419k-token re-cache at ~20x the read rate (and the same burn on your 5h/7d quota on subscriptions). **Bold red past 200k** — the premium-band miss. `≡~` while a large prefix rebuilds. `--cache always` additionally keeps the freeze-safe deadline `≡@15:20` (last request + TTL; a past time in a frozen frame reads "expired at 15:20"). TTL defaults to 1h (claude.ai subscriber sessions) or 5m (API-key auth); an observed usage breakdown overrides it. The `≡` glyph (U+2261) reads as stacked cache layers — one terminal column, quiet and distinct. |

**Color follows three lanes** so a glance is unambiguous: **status**
(green/yellow/red) = pressure *only* — quota, context, cache, the premium
context band, expensive effort; **identity** (magenta/cyan/blue; fable = bright
red, matching its Claude Code TUI color) = model family; everything else is
**neutral** grey/white. Warm status color always means "near a limit or cost."

## vs Built-in `/statusline`

| Feature | `/statusline` | This repo |
|---------|:-------------:|:---------:|
| Context bar, cost, git | Yes | Yes |
| Live 5h / 7d quota | -- | Yes |
| Extra usage + prepaid balance | -- | Yes |
| Quota reset time | -- | Yes |
| Adaptive polling (30s -- 5min) | -- | Yes |
| Refresh `~` / error `!` indicator | -- | Yes |
| `--extra` display gating | -- | Yes |
| Tier display + model abbreviation | -- | Yes |
| 5 themes, 9 bar styles | -- | Yes |
| Prompt cache break detection | -- | Yes |
| OAuth + macOS Keychain | -- | Yes |
| Change flash on every refresh (`+.37` cost, `+9`/`-27` context, `+N` quota) | -- | Yes |
| Model-scoped weekly quota (`fb`/`op`/`sn`) | -- | Yes |
| Week row: the 5h window as half hours, the 7d period as 5h windows, what each cost | -- | Yes |
| Works behind trusted mitm proxies (NODE_EXTRA_CA_CERTS) | -- | Yes |
| 383 bats tests + CI | -- | Yes |

## Configuration

Flags go in the command string in `~/.claude/settings.json`:

```json
"command": "bash ~/.claude/statusline.sh --theme developer --extra on-limit"
```

| Flag | Values | Default |
|------|--------|---------|
| `--theme` | `minimal`, `compact`, `detailed`, `developer`, `manager` | (none) |
| `--style` | `unicode-blocks`, `single-block`, `bracketed-bars`, `filled-dots`, `square-blocks`, `line-segments`, `ascii-bars`, `percent-only`, `fraction-display` | `unicode-blocks` |
| `--order` | Comma-separated: `activity,time,cost,model,user,quota,extra` | all |
| `--path-display` | `project`, `cwd`, `full`, `relative` | `project` |
| `--alignment` | `left-right`, `right-left`, `center` | `left-right` |
| `--extra` | `auto`, `always`, `on-limit`, `off` | `auto` |
| `--cache` | `auto`, `always`, `off` | `auto` |
| `--advisor` | `auto`, `always`, `off` — projection row, see [Advisor line](#advisor-line) | `auto` |
| `--week` | `auto`, `always`, `off` — the 5h + 7d ledger row with pace and reset, see [Week row](#week-row) | `auto` |
| `--deadman` | `auto`, `off` — [deadman](https://github.com/thevibeworks/deadman) switch chip | `auto` |
| `--debug` | Write logs to `~/.claude/statusline/logs/statusline.log` | off |
| `--test [json]` | Render with mock data | off |

### Themes

| Theme | What it does |
|-------|-------------|
| `minimal` | Model + context + user. Extra off. |
| `compact` | Everything. Unicode bars. Project path. |
| `detailed` | Bracketed bars. Working directory. |
| `developer` | Full path. Filled dots. Right-aligned. Extra on-limit. |
| `manager` | Percent-only. Cost first. Centered. |

### Extra Usage Gating

```text
--extra auto        5h[24%@14:30] 7d[10%]                               (calm, hidden)
--extra auto        5h[87%@14:30] 7d[10%] ex[$19.52/$200 10%]           (5h >= 80%, shown)
--extra always      5h[24%@14:30] 7d[10%] ex[$19.52/$200 10% bal$4.66]  (always shown)
--extra on-limit    5h[87%@14:30] 7d[10%] ex[$19.52/$200 10%]           (same as auto minus extra_util gate)
--extra off         5h[24%@14:30] 7d[10%]                               (always hidden)
```

`auto` (default) shows extra when quota runs out (5h >= 80%, 7d >= 70%) or
extra budget is pressured (utilization >= 50%). Compact by default, actionable
when it matters.

### Prompt Cache

```text
--cache auto        fabl5[1m][42%]                        (healthy: silent — no width spent)
--cache auto        fabl5[1m][5%] ≡~                      (a large prefix is rebuilding)
--cache auto        fabl5[1m][43%] ≡!419k                 (resume onto a dead cache: 419k rewrite; BOLD red >200k)
--cache always      opus4.8[1m][21%] ≡:1h@14:20           (opt in to the freeze-safe deadline; :1h = observed TTL)
--cache off         opus4.8[1m][21%]                      (disabled; no state writes)
```

**Why healthy is silent.** The server refreshes the cache TTL on every request,
so while you work the cache is always freshly ~1 TTL from expiry — there is no
honest "expiring soon" to show, and a deadline that's always ~an hour out is
pure width. The expiry only becomes *real* during an idle gap, and Claude Code
renders the statusline only on activity — so no warning can appear while you're
away. The honest moment is when you come back: the first post-idle render sees
activity resume after a gap longer than the TTL and reports the rewrite as
`≡!Nk`, sized at the re-cached prefix (`≡!419k`), **bold red past
200k** — the expensive premium-band miss. This fires even when the 300ms render
debounce skipped the `read=0` turn, because the detector keys off the stale
activity anchor, not the one-frame collapse; breaks are held ~60s so a busy
turn's refresh doesn't erase them. A cache miss re-caches the whole prefix at
~20x the cache-read rate, and on subscription plans the same multiplier lands
on your 5h/7d quota.

The activity anchor is the last observed *usage change*, not the last render —
Claude Code also re-runs the statusline on vim/permission/model changes with
unchanged usage, and re-stamping there would fake a warm cache.

**The freeze-safe deadline, on demand.** `--cache always` adds `≡@15:20`
(last request + TTL): a past time in a frozen frame reads "expired at 15:20",
so you can decide *before* typing whether to resume this session or start
fresh. Wall-clock, never a countdown — "expires in 43m" rendered an hour ago is
a lie, "@15:20" stays true however stale the frame is. Claude Code's statusline
stdin exposes aggregate cache tokens only, not the `ephemeral_1h/5m` breakdown,
so the TTL is assumed from how the CLI actually requests caching (verified in
traces): **1h for claude.ai subscriber sessions, 5m for API-key /
custom-endpoint auth** (the CLI's `FORCE_PROMPT_CACHING_5M` /
`ENABLE_PROMPT_CACHING_1H` overrides are honored). An observed breakdown wins
and renders its class as provenance (`≡:5m@14:25`). Known gap: a subscriber
session that started while on overage is latched to 5m server-side, invisible
here — the `≡!Nk` badge still reports the miss after the fact.

### Quota Polling

| 5h utilization | Interval |
|----------------|----------|
| < 20% | 5 min |
| 20 -- 49% | 2 min |
| 50 -- 79% | 1 min |
| >= 80% | 30 sec |

Those intervals govern the API fetch. Claude Code itself hands the
statusline the 5h/7d numbers (`rate_limits`) on every render, and they are
merged into the badges immediately — so while stdin carries them the fetch
only serves what stdin lacks (the model-scoped weekly limit, extra usage)
and its interval floors at 2 min whatever the 5h heat. Every stdin pair
that changes is also logged as a `source:"stdin"` sample (>= 60 s apart):
free history for the ledgers and the forecast, no request behind it.

Error cooldown escalates with consecutive failures — 2 min, 4 min, 8 min, 10 min
cap — and a server `Retry-After` (429s carry one) extends it further. The
cooldown resets on the next successful fetch. Cache writes: atomic `mv`.

Indicators: `~` after quota = refresh in flight. A failed fetch shows why the
data may be stale: `!429` rate limited, `!auth` token rejected, `!5xx` server
error, `!net` connection failed.

### Try It Locally

```bash
echo '{"model":{"id":"claude-opus-4-8[1m]","display_name":"Opus"},"cwd":"/tmp/project","workspace":{"current_dir":"/tmp/project"},"cost":{"total_cost_usd":6.72,"total_lines_added":84,"total_lines_removed":14,"total_api_duration_ms":5400000},"version":"2.1.139"}' \
  | bash statusline.sh --test
```

## Week row

Line 1 says how much of each window is left; the week row says where it
went — one grammar at two scales, directly under the badges. Row 2
mirrors line 1: advice on the left, evidence on the right, the gap
between them absorbing the width, the right edge shared with line 1:

```text
proj (main*)       +84/-14 8m $6.72 fabl5[1m][██░░42%] fb[66%] [MAX|@work] 5h[38%@23:00] 7d[39%]
- budget ~3x5h left · even 20%/win   5h ▂▅█▃▮▯▯▯▯▯ 0.9x @23:00  7d ▅▁▂ ▃▅ˍ▃▅ ▃▃▁▂▁ ▅ˍ▂▁▁ ˍˍˍ▃▅ ˍˍˍ▅ ▆▆ˍ▂▮▯▯ 0.7x @Wed 09:00
```

The advisor sentence is compacted to the room line 1 leaves beside the
ledgers — weakest joint first (`;` the second voice, then `·` the tail
clause, then `,` a sub-fact), the leading fact last — so a calm frame is
two rows, not three. When fewer than 16 columns are left (narrow
terminals) the rows hang as a block instead: the ledgers meet line 1's
edge and the full sentence sits flush-left beneath them:

```text
proj (main*)   fabl5[1m][██░░42%] fb[66%] [MAX|@work] 5h[38%@23:00] 7d[39%]
   5h ▂▅█▃▮▯▯▯▯▯ 0.9x @23:00  7d ▅▁▂ ▃▅ˍ▃▅ ▃▃▁▂▁ ▅ˍ▂▁▁ ˍˍˍ▃▅ ˍˍˍ▅ ▆▆ˍ▂▮▯▯ 0.7x @Wed 09:00
   - budget ~3x5h left · even 20%/win · heading ~52%
```

Each strip ends with its **pace** (used ÷ elapsed: `0.7x` is on track,
`1.6x` caps early — dim below 1x, pressure-tinted from 1x, hidden for
the first 15 min of a window) and the **reset** its right edge stands
for (`@23:00` inside 24h, `@Wed 09:00` beyond) — axis labels for a
timeline, not badges restated. When the row shows, the advisor's calm
budget line shows with it (windows left, what even looks like, where
you land); pressure and surplus clauses still take its place when they
fire.

- **`5h`** — this sitting: the current 5h window as 10 half-hour cells,
  height = the 5h points that half hour added (each positive step between
  consecutive samples credited to the half hour the later sample fell in).
- **`7d`** — the week: the 7d period as its 5h windows (34 cells, oldest
  left, the last a 3h stub), height = the 7d points that window burned,
  with a thin gap at each local midnight so days read as clusters — and a
  day that held five windows shows it — without a ruler.

| Cell | Meaning |
|------|---------|
| `▁▂▃▄▅▆▇█` | a cell that ran; height is the points it burned (`▁` <= 2, `▅` <= 11, `█` > 20) — the same scale in both strips, so a full window and a full week read the same height |
| `ˍ` | ran, cost under a point — or ran idle inside the log's coverage; a bar of height zero, on the baseline |
| `░` | unknown: the log has no sample for that cell (never drawn as idle — a gap in the record is not a quiet session) |
| `▮` | the cell you are in now |
| `▯` | a cell still ahead of you — the hollow of `▮`, an empty slot waiting |
| `×` | a cell the pool will not cover at the current pace (7d: the learned forecast's dry point, linear when untrained; 5h: linear, the same projection as the badge) |

Burn cells take their badge's pressure color; everything else is neutral,
so the row never adds an alarm channel of its own. Both strips are
reconstructed from `usage.jsonl` — the samples every render has been
logging — keyed by each 5h window's `resets_at`. Reading down the column:
`7d[39%]` -> the strip that spent those 39% -> the advisor clause that
projects the rest. Freeze-safe by construction: `▮` moves at cell
boundaries and every other cell is history.

`--week auto` (default) draws the row only once the log holds a sample
for either period — a fresh install gets no `░░░▮▯▯` row that says nothing
the badges don't. `--week always` draws it whenever a window is live;
`--week off` never. The 7d strip is the same one `statusline.sh week`
prints; both are cached in `week.cache` and rebuilt only when the log
grows, so a render never pays for the scan. Interoperates with
[ccpace](https://github.com/thevibeworks/ccpace), which draws the same
week ledger from the same log.

## Advisor line

The statusline can render a second row — Claude Code displays each stdout
line as its own row ([docs](https://code.claude.com/docs/en/statusline)).
The advisor uses it to *interpret* the badges: it speaks only when the
numbers on line 1 don't mean what they appear to mean, and every clause
derives from a badge already shown — no third alarm channel. It cuts both
ways, with a voice per direction:

- **pressure** — `! ...` in yellow/red: you'll hit a wall before a reset.
- **budget** — `- budget ~3x5h left · even 20%/win · heading ~52%` in dim:
  the calm numbers; shown whenever the week row is showing (and always
  under `--advisor always`).
- **opportunity** — `+ ...` in cyan: paid capacity is about to expire
  unused, or a sibling account is free while you're pinned. Cyan can
  never mean pressure, so the color alone carries the stance.

Quiet means no row at all: a healthy session stays one line. Alone, the
row right-aligns to the edge the stats cluster ends at, so the advice
sits directly beneath the badges it interprets. With the
[week row](#week-row) showing it moves onto that row's left side,
compacted to fit (row 2 then mirrors line 1: advice left, evidence
right); only when no honest room is left does it drop to a third row,
flush-left under the ledgers. Claude Code trims every row it renders,
so any leading padding rides behind a zero-width reset code — a
bare-space row would land flush-left.

```text
proj (main*)   fabl5[1m][██░░42%] fb[86%] [MAX|@work] 5h[95%@06:00] 7d[44%@07:00]
                          ! 5h caps ~05:18, 42m before reset; 7d resets @07:00, 56% unused
```

What it says, in value order (max two clauses):

| Clause | When |
|--------|------|
| `! fb capped · back ~Thu 07:00` | The weekly limit scoped to *this session's model* (`limits[]` `weekly_scoped`) hit 100% — the model just became unavailable, and the one number that matters is when it returns. |
| `! 5h caps ~14:20, 52m before reset` | The 5h badge is already yellow/red and the linear projection lands before the reset. Suppressed when relief is <= 30min out, same as the badge's recovery color. |
| `+ 7d resets @07:00, 56% unused · spend it` (or `· ~40% expires even at full burn`) | Expiring surplus: inside the last day of the 7d window with >= 30% unused, a green badge means forfeiture, not headroom — at reset the remainder vanishes whether spent or not. The tail is feasibility-checked against the learned `pct_per_window` ratio (how many 7d points a fully burned 5h window costs *you*, mined from your own usage log): "spend it" appears only when full-tilt burning can actually consume the surplus; past that point the honest tail is how much expires no matter what. While the ratio is unlearned the clause states the bare fact and advises nothing. |
| `+ alt 5h[8%] free` | Fleet relief for shared-home multi-account setups: once this account's 5h hits 90%, the idlest *fresh* sibling under `accounts/*/` is the actionable way out. Read-only, no credentials. |
| `! fb caps ~Wed 18:00, 1d before reset` | The running model's scoped weekly quota caps before its reset — same linear math, gates, and recovery suppression as the 7d aggregate. |
| `! 7d dry ~Thu 09:00, 2d before reset · then extra billing` (or `then hard stop`) | The learned weekday forecast projects the quota drying up early; cold start falls back to linear pace, but only once `seven_day_pace` already warns. The tail states what actually happens at 100%. |
| `+ 7d on pace to leave ~62% unused · go heavier` | Underuse: on pace to strand a large chunk of the subscription. The learned weekday profile speaks first — it knows *your* remaining days, so it can warn from day two; cold start falls back to linear pace past half the window. Speaks only in an engaged, unsqueezed session (5h between 25% and 80%, no pressure clause) — it reaches exactly the person who can act on it and never nags an idle one. |
| `- budget ~19x5h left · even 1.1%/win · heading ~52%` | `--advisor always` only, when calm: the weekly budget in one breath — runway, what even looks like, where you land. "heading" is the learned end-of-week projection when trained, linear once the window is a day old. In the last window per-window math would just restate the headroom, so it degrades to `- budget last window · 61% left · heading ~40%`. |

The 7d window gets one voice per render — surplus, dry, or underuse,
never two that could disagree.

```bash
--advisor auto      # default: speak under pressure or expiring surplus
--advisor always    # add the weekly budget line when calm
--advisor off       # single row, never
```

All times are wall-clock (`~14:20`) or future-to-future gaps (`52m before
reset` = reset minus cap, both in the future) — freeze-safe in an idle
frame, same idiom as the badges. Add `"refreshInterval": 60` to your
`statusLine` settings if you want the row re-evaluated on a timer while
idle.

For a standalone full-screen watcher (multi-account polling,
notifications), see `claude.py --watch-usage` in
[claudex](https://github.com/thevibeworks/claudex) — it consumes the same
state dir this script maintains (see `docs/api/state-dir.md`).

## The waste ledger

The advisor prevents waste prospectively; `report` proves it
retroactively. It replays the usage log the statusline has been writing
all along and ledgers every closed window — what you used, what expired:

```bash
$ ~/.claude/statusline.sh report          # or --days 90
usage report - work (last 28d, 79 samples)

7d windows closed: 1
  Tue 07-28 00:00  used 51%  expired 49% (~4.7 x 5h windows unused)

5h windows closed: 3   avg 95% at close   2 hit the cap
exchange rate: one full 5h window = ~10.46% of the week (~9.6 windows/week, learned)

week in progress: 5% used, resets Mon 08-03 23:59
```

That "expired 49%" line is the subscription math nobody shows you: half
a week of paid capacity, gone. The windows-worth figure uses the same
learned `pct_per_window` ratio the advisor's feasibility check uses, and
"week in progress" runs the same learned projection — the surfaces
cannot disagree.

Honest limits: a window's final utilization is the last sample before
its reset, so usage from other devices after your last local render is
invisible, and a week you never opened a session in never appears at
all. The ledger reports what the log observed, nothing more.

## Scripting: `check` and `session-summary`

The statusline never runs when you're away — exactly when expiring
capacity needs a voice. Instead of shipping a daemon, `check` exposes
the advisor's judgment as an exit code; you provide the plumbing (tmux
segment, cron, CI):

```bash
~/.claude/statusline.sh check
# stdout: the plain advisor text, or "calm" / "unknown: ..."
# exit 0 calm | 1 opportunity (+) | 2 pressure (!) | 3 unknown/stale
```

```bash
# cron: nudge yourself when paid capacity is about to expire unused
*/30 * * * * ~/.claude/statusline.sh check; [ $? -eq 1 ] && notify-send "$(~/.claude/statusline.sh check)"

# tmux: advisor verdict in the status bar
set -g status-right '#(~/.claude/statusline.sh check)'
```

`session-summary` is the same idea for session retrospectives — one
line per session, built from the usage log, designed as a `SessionEnd`
hook (it reads the hook JSON on stdin):

```jsonc
// settings.json
"hooks": {
  "SessionEnd": [{"hooks": [{"type": "command",
    "command": "~/.claude/statusline.sh session-summary >> ~/.claude/statusline/session-summaries.log"}]}]
}
```

```text
session 8f3c02aa: 3h12m, 5h +34pts, 7d +4pts, claude-fable-5
```

Run it bare and it summarizes the last session in the log. Window
deltas are positive-delta sums, so a session that straddles a 5h reset
still reports what it actually consumed.

## The agent surface

Three layers, one source of truth: line 1 shows the numbers, line 2
says the one sentence that matters, and for the full conversation —
"should I start a heavy task now?", "which account has headroom?",
"what did I waste this week?" — there's a skill that teaches Claude
Code itself to read the state dir:

```bash
cp -r skills/usage-insight ~/.claude/skills/
```

Then just ask. The skill knows the state-dir contract
(`docs/api/state-dir.md`), the learned-forecast semantics
(`pct_per_window`, weekday profile, prediction calibration), and the
advisor's judgment rules — including the important one: never advise
what the data can't back. It reads the same files and runs the same
`report`/`check` subcommands, so all three layers always agree.

<details><summary>OAuth and API behavior</summary>

Quota, profile, and extra-usage requests use Claude Code's OAuth credentials
from `~/.claude/.credentials.json`. Expired tokens are refreshed automatically
via the same `refreshToken` flow the CLI uses.

If `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, or `ANTHROPIC_BASE_URL` is set,
all OAuth-dependent components (quota, user, extra) are skipped silently.

macOS Keychain is tried as fallback when no file credential exists. OrbStack
resolves the real Linux home directory via `getent passwd`.

The script never writes to Anthropic endpoints -- it only reads usage, profile,
and prepaid balance data.

**Account-scoped cache (one fetch, all sessions).** Quota / profile / prepaid
data is identical for every session on the account, so it's cached once in a
shared dir -- `~/.claude/statusline/` -- and a single fetch serves all
concurrent sessions. Per-session prompt-cache-health state stays under
`~/.claude/statusline/sessions/`. Old `$SCRIPT_DIR` state is migrated on first
run. Setting only `CLAUDE_CACHE_DIR` keeps the legacy single-dir behavior.

</details>

<details><summary>Environment variables</summary>

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_CONTEXT_LIMIT` | auto | Override context token limit |
| `CLAUDE_7D_WORKDAYS` | unset | Skip weekends in the 7d pace deadline — quota you won't spend Sat/Sun no longer counts against runway (opt-in; the limit itself stays calendar-based) |
| `CLAUDE_DATA_DIR` | `~/.claude/statusline` | Account-scoped cache + usage log location |
| `CLAUDE_CACHE_DIR` | `$CLAUDE_DATA_DIR/sessions` | Per-session cache-health state |
| `STATUSLINE_DEADMAN` | `auto` | Default for the deadman chip (`auto`/`off`); the `--deadman` flag wins |
| `STATUSLINE_ACCOUNT` | unset | Account label for multi-account setups: renders an `@label` chip and moves account caches to `accounts/<label>/` so concurrent accounts stop sharing one quota cache |
| `DEVA_AUTH_TAG` | unset | Same as above, set automatically by [deva](https://github.com/thevibeworks/deva) from `--auth-with` (`auth-file-<stem>` -> `@<stem>`); `auth-default` means single-account and is ignored. Containers from pre-v0.18 deva without the tag are resolved from `DEVA_AUTH_METHOD`/`DEVA_AUTH_DETAILS` instead |
| `DEBUG_LOG` | `~/.claude/statusline/logs/statusline.log` | Debug log path |
| `DEBUG_LOG_MAX_BYTES` | `1048576` | Debug log size cap before rotation |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Output token reserve |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude config directory |

</details>

## Testing

```bash
npm exec --yes bats -- t/
```

383 tests across `t/statusline.bats` (371 statusline + integration) and
`t/install.bats` (12 installer). CI runs on push and PR to `main`.

## Project Structure

```text
statusline.sh                Main script (one file, ~4400 lines)
DESIGN.md                    The language: rows, color lanes, glyphs, time, requests
llms.txt                     Agent-facing map of the repo
install.sh                   One-line installer
t/statusline.bats            Unit and integration tests
t/install.bats               Installer tests (mock curl, isolated $HOME)
t/helpers.bash               Sources real functions from statusline.sh
.github/workflows/test.yml   CI workflow
CHANGELOG.md                 Release notes
CONTRIBUTING.md              Contribution guide
docs/devlog/                 Implementation history
docs/api/oauth-usage.md      Observed /api/oauth/usage contract (synced: CLI v2.1.201)
docs/api/state-dir.md        On-disk state contract for external readers (ccpace, agents)
```

## Design language

[DESIGN.md](DESIGN.md): rows, lanes, glyphs, time, requests — the rules
every badge follows, in one page.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: keep it to Bash + `jq` +
`curl`, add tests, run `bats t/` before pushing.

## License

[MIT](LICENSE)
