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

One Bash file that plugs into the official `statusLine` command hook. Shows
what matters: active model, context window, session cost, 5h / 7d quota with
reset times, prompt-cache health, extra-usage spend, git activity, and subscription tier.
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
project (main*)  +84/-14 1h30m $6.72 opus4.8[1m][███░░░26%] cache:1h@14:20~ [MAX|you] 5h[87%@14:30] 7d[75%@2d] ex[$16.29/$200 8% bal$4.66]
   |       |       |      |     |       |                        |                 |              |             |              |
 path   branch   edits   time  cost   model+context             cache             user         5h quota      7d quota      extra usage
```

Every component earns its place:

| Signal | Why it matters |
|--------|----------------|
| Path and branch | Know where Claude Code is writing. Neutral grey; a dirty branch brightens to white with a `*`. |
| Activity | Session diff without opening git. |
| Time and cost | Track long sessions. Hours format above 60m (`1h30m`). |
| Model | Abbreviated: `claude-opus-4-8` becomes `opus4.8`, `claude-fable-5` becomes `fabl5`, `claude-sonnet-5` becomes `sonnet5`. The `[1m]` tag marks a 1M-context session, detected from the window the CLI reports (`context_window_size`) — not the name — so it shows even when Claude Code strips the `[1m]` suffix (which it does since 2.1.173 whenever 1M is the default; Sonnet 5 joined Fable 5 on that path in 2.1.197). |
| Effort | Compact lowercase badge: `lo` / `md` / `xh` / `max` / `ultra` / `auto` (`high` is the default and stays hidden). Dim for routine levels; `max` / `ultra` use the pressure color; `fast` shows in fast mode. |
| Context bar | Merged with model. Green / yellow / red by window pressure. On 1M models the bar also carries the premium input-pricing band: yellow past 200k tokens, red past 800k — the % alone looks calm (320k = 32%) while every request bills at the premium rate. A real 0% (e.g. right after `/compact` resets the window) renders a visibly empty bar `[░░░░░░0%]` — the snap to empty *is* the refresh signal; the bar hides only when no context data exists at all. |
| User tier | Neutral white-weight (MAX bold, PRO normal, dim otherwise) — identity, never a status color. Truncated display name. |
| Quota | Integer percentages. The 5h badge always carries its reset time while a window is live — `5h[42%@14:30]` reads "42% used, resets at 14:30" — because on a 5h horizon the reset is the number you plan the current sitting around. Wall-clock, not a countdown, on purpose: Claude Code only re-renders the statusline on activity, so a relative "@1h38m" silently decays into a lie during idle gaps, while "@14:30" stays true in a frozen frame. (The 7d badge stays relative — `@5d` decays at day granularity, slower than any idle gap.) When a window's utilization climbs between renders, a reverse-video `+N` token appears right after the badge for ~60s: `5h[44%@14:32]+2` means "you just burned 2%". A drop (window reset) stays quiet — the fresh low number is its own signal. **7d is forecast, not leveled**: a learned per-weekday burn profile (EWMA over your own usage history) plus your recent 24h burn project whether the quota outlasts the window — your heavy Tuesday counts more than a generic average. The verdict is color alone; under pressure the badge shows explicit time remaining in the window: `7d[44%@5d]` red means "at your pace, dry days before the reset 5 days from now". Cold start (<14 days history) falls back to window-average pacing. Recovery color when reset is imminent. |
| Extra usage | Monthly spend, limit, prepaid balance. `--extra auto` shows when quota runs out. |
| Cache health | Detects observed prompt-cache rebuilds and cache-read drops. `cache!` on break, `cache~` when building. If a future Claude Code stdin includes TTL breakdown, `--cache always` can show `cache:1h@14:20`; current stdin usually exposes aggregate cache tokens only. Hidden when healthy by default. |

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
| Quota bump flash (+N) | -- | Yes |
| 242 bats tests + CI | -- | Yes |

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
--cache auto        opus4.8[1m][21%]                      (healthy, hidden)
--cache auto        opus4.8[1m][21%] cache~               (cache is rebuilding)
--cache auto        opus4.8[1m][21%] cache!               (cache-read collapse observed)
--cache always      opus4.8[1m][21%] cache:1h@14:20       (when TTL breakdown exists)
--cache off         opus4.8[1m][21%]                      (disabled; no state writes)
```

Cache state is based on Claude Code's per-turn usage tokens:
`cache_read_input_tokens`, `cache_creation_input_tokens`, and `input_tokens`.
The statusline can prove that a cache was read, rebuilt, or likely broke after a
turn. It cannot know server-side `expire_at` before the next request, so it shows
absolute last-observed cache activity (`@14:20`) rather than a live countdown.
Current Claude Code statusline stdin usually exposes aggregate cache tokens only,
not `cache_creation.ephemeral_1h_input_tokens` / `ephemeral_5m_input_tokens`.
The script accepts those fields for forward compatibility, but TTL class
(`5m` / `1h`) is shown only when observed in actual usage breakdown. Local
environment variables are intent, not proof of what the server accepted.

### Quota Polling

| 5h utilization | Interval |
|----------------|----------|
| < 20% | 5 min |
| 20 -- 49% | 2 min |
| 50 -- 79% | 1 min |
| >= 80% | 30 sec |

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

## claude-watch

`claude-watch.sh` is a standalone companion that watches one session's usage in
real time -- a "top"-style full-screen view, where the statusline is a single
prompt line.

```text
━━ claude-watch ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
model  opus4.8  turns 412  2026-06-09T11:42:08Z

last turn  $0.67  in 319  out 21,274  c-read 132,952  c-make 10,960
session   $4.91  in 9,044  out 72,837  c-read 6,062,353  c-make 1,879,467

quota  5h 36%  7d 44%  extra $16.29/$200 8%  (12s ago)
forecast dry ~Mo (2.4d before reset)  profile/d Mo12 Tu16 We15 Th15 Fr9 Sa6 Su10 (ewma %)
```

It reads four things, all read-only: the session transcript (per-turn token
usage), the shared account usage cache (5h / 7d / extra quota), `usage.jsonl`,
and `forecast.cache` (the learned per-weekday burn profile statusline.sh
maintains — the forecast line projects when your quota runs dry at your own
pace and stays quiet when it outlasts the window). By default it picks the most recently modified transcript for the
current directory's project.

```bash
bash claude-watch.sh                 # auto-pick newest session in this project
bash claude-watch.sh --session ID    # watch a specific session
bash claude-watch.sh --once          # one snapshot, no watch loop
bash claude-watch.sh --interval 5    # refresh every 5s (default 3s)
bash claude-watch.sh --help
```

Cost is an **estimate** from public per-million list pricing; fast-mode
surcharges are not modeled. Quota requires `statusline.sh` to have populated
the shared usage cache. `claude-fable-5` is priced in the Opus 4.5+ capability
tier.

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
| `DEBUG_LOG` | `~/.claude/statusline/logs/statusline.log` | Debug log path |
| `DEBUG_LOG_MAX_BYTES` | `1048576` | Debug log size cap before rotation |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Output token reserve |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude config directory |

</details>

## Testing

```bash
npm exec --yes bats -- t/
```

242 tests across `t/statusline.bats` (230 statusline + integration) and
`t/install.bats` (12 installer). CI runs on push and PR to `main`.

## Project Structure

```text
statusline.sh                Main script (one file, ~2500 lines)
claude-watch.sh              Live usage/cost watcher (standalone companion)
install.sh                   One-line installer
t/statusline.bats            Unit and integration tests
t/install.bats               Installer tests (mock curl, isolated $HOME)
t/helpers.bash               Sources real functions from statusline.sh
.github/workflows/test.yml   CI workflow
CHANGELOG.md                 Release notes
CONTRIBUTING.md              Contribution guide
docs/devlog/                 Implementation history
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: keep it to Bash + `jq` +
`curl`, add tests, run `bats t/` before pushing.

## License

[MIT](LICENSE)
