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
project (main*)  +84/-14 1h30m $6.72 opus4.6[1m][███░░░26%] cache:1h@14:20~ [MAX|feast.t.] 5h[87%@14:30] 7d[75%@Mon] ex[$16.29/$200 8% bal$4.66]
   |       |       |      |     |       |                        |                 |              |             |              |
 path   branch   edits   time  cost   model+context             cache             user         5h quota      7d quota      extra usage
```

Every component earns its place:

| Signal | Why it matters |
|--------|----------------|
| Path and branch | Know where Claude Code is writing. Dirty branch is bright yellow. |
| Activity | Session diff without opening git. |
| Time and cost | Track long sessions. Hours format above 60m (`1h30m`). |
| Model | Abbreviated. `claude-opus-4-6[1m]` becomes `opus4.6[1m]`. |
| Context bar | Merged with model. Green / yellow / red by pressure. |
| User tier | MAX is green, PRO is cyan. Truncated display name. |
| Quota | Integer percentages. Absolute reset time on pressure (>= 80%/70%) or time proximity (<= 2h/3d). `5h[87%@14:30]` `7d[75%@Mon]`. Recovery color when imminent. |
| Extra usage | Monthly spend, limit, prepaid balance. `--extra auto` shows when quota runs out. |
| Cache health | Detects observed prompt-cache rebuilds and cache-read drops. `cache!` on break, `cache~` when building. If a future Claude Code stdin includes TTL breakdown, `--cache always` can show `cache:1h@14:20`; current stdin usually exposes aggregate cache tokens only. Hidden when healthy by default. |

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
| 145 bats tests + CI | -- | Yes |

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
| `--debug` | Write logs to `/tmp/claude-code-statusline.log` | off |
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
--extra auto        5h[24%] 7d[10%]                                  (calm, hidden)
--extra auto        5h[87%@14:30] 7d[10%] ex[$19.52/$200 10%]       (5h >= 80%, shown)
--extra always      5h[24%] 7d[10%] ex[$19.52/$200 10% bal$4.66]    (always shown)
--extra on-limit    5h[87%@14:30] 7d[10%] ex[$19.52/$200 10%]       (same as auto minus extra_util gate)
--extra off         5h[24%] 7d[10%]                                  (always hidden)
```

`auto` (default) shows extra when quota runs out (5h >= 80%, 7d >= 70%) or
extra budget is pressured (utilization >= 50%). Compact by default, actionable
when it matters.

### Prompt Cache

```text
--cache auto        opus4.6[1m][21%]                      (healthy, hidden)
--cache auto        opus4.6[1m][21%] cache~               (cache is rebuilding)
--cache auto        opus4.6[1m][21%] cache!               (cache-read collapse observed)
--cache always      opus4.6[1m][21%] cache:1h@14:20       (when TTL breakdown exists)
--cache off         opus4.6[1m][21%]                      (disabled; no state writes)
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

Error backoff: 2 min. Cache writes: atomic `mv`.

Indicators: `~` after quota = refresh in flight. `!` = last fetch failed.

### Try It Locally

```bash
echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/project","workspace":{"current_dir":"/tmp/project"},"cost":{"total_cost_usd":6.72,"total_lines_added":84,"total_lines_removed":14,"total_api_duration_ms":5400000},"version":"2.1.139"}' \
  | bash statusline.sh --test
```

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

</details>

<details><summary>Environment variables</summary>

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_CONTEXT_LIMIT` | auto | Override context token limit |
| `CLAUDE_DATA_DIR` | script dir | Usage log location |
| `CLAUDE_CACHE_DIR` | `$CLAUDE_DATA_DIR/sessions` | Quota and profile cache |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Output token reserve |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude config directory |

</details>

## Testing

```bash
npm exec --yes bats -- t/
```

145 tests across `t/statusline.bats` (133 unit + integration) and
`t/install.bats` (12 installer). CI runs on push and PR to `main`.

## Project Structure

```text
statusline.sh                Main script (one file, ~1700 lines)
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
