# Claude Code Statusline

> Live quota, extra-usage spend, context usage, model, cost, git activity, and
> session timing for Claude Code.

[![tests](https://github.com/thevibeworks/claude-code-statusline/actions/workflows/test.yml/badge.svg)](https://github.com/thevibeworks/claude-code-statusline/actions/workflows/test.yml)
[![version](https://img.shields.io/github/v/tag/thevibeworks/claude-code-statusline?label=version&sort=semver)](https://github.com/thevibeworks/claude-code-statusline/tags)
[![license](https://img.shields.io/github/license/thevibeworks/claude-code-statusline)](LICENSE)
[![bash](https://img.shields.io/badge/shell-bash-4EAA25)](statusline.sh)
[![deps](https://img.shields.io/badge/deps-jq%20%2B%20curl-blue)](#requirements)

<p align="center">
  <img src="assets/statusline-preview.svg" alt="Claude Code Statusline terminal preview showing git branch, edits, time, cost, model, context, user tier, quota, and extra usage." width="100%">
</p>

Claude Code Statusline is a single-file Bash statusline for developers who keep
[Claude Code](https://code.claude.com) open all day. It plugs into the official
`statusLine` command hook and turns the prompt footer into a compact operations
readout: current model, context usage, session cost, elapsed API time, git
activity, subscription tier, 5-hour / 7-day quota, and optional extra-usage
spend.

It is intentionally small: Bash, `jq`, and `curl`; no package manager, no
background daemon, no maintainer telemetry. Quota and profile calls use Claude
Code's OAuth credentials when available, including read-only extra-usage balance
when enabled, and are skipped for API-key or custom base URL setups.

## Quick Start

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh | bash
```

The installer downloads `statusline.sh` to `~/.claude/`, then configures
`~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 0
  }
}
```

Restart Claude Code, or send another message, and the statusline will render on
the next prompt.

### Requirements

- Claude Code with the `statusLine` hook
- Bash
- `jq`
- `curl`

Prefer to inspect installers first?

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh -o /tmp/claude-code-statusline-install.sh
less /tmp/claude-code-statusline-install.sh
bash /tmp/claude-code-statusline-install.sh
```

### Manual Install

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add the `statusLine` block above to `~/.claude/settings.json`.

## What It Shows

```text
myproject (main*)  +84/-14 8m $6.72 opus4.6[1m][█░░░░░26%] [MAX|feast.t.] 5h[24%] 7d[100%~12h6m] ex[$16.29/$200 8% bal$4.66]
    ^        ^       ^     ^   ^        ^          ^            ^           ^          ^                ^
  project  branch  edits  time cost    model     context       user      5h quota   7d quota       extra usage
```

| Signal | Why it matters |
|--------|----------------|
| Git path and branch | Know which repo and branch Claude Code is touching. |
| Lines added / removed | Spot session activity without opening git status. |
| API time and cost | Keep long sessions visible. |
| Model abbreviation | See the active model without reading full model IDs. |
| Context bar | Track context pressure using Claude Code's `/context` formula. |
| User tier | Confirm profile and subscription resolution. |
| 5h / 7d quota | See utilization and reset timing before you hit the wall. |
| Extra usage | Track monthly extra spend and prepaid balance when enabled. |

## Why This Instead of `/statusline`?

Claude Code's built-in [`/statusline`](https://code.claude.com/docs/en/statusline)
can generate simple one-off scripts. This repo is for people who want a
maintained default with quota intelligence, caching, themes, tests, and a clean
install path.

| Feature | `/statusline` | This repo |
|---------|:-------------:|:---------:|
| Context bar | Yes | Yes |
| Cost / duration | Yes | Yes |
| Git branch | Yes | Yes |
| Live 5h / 7d quota | No | Yes |
| Extra usage spend / balance | No | Yes |
| Quota reset countdown | No | Yes |
| Adaptive API polling | No | Yes |
| Subscription tier display | No | Yes |
| Model abbreviation | No | Yes |
| Themes and bar styles | No | Yes |
| OAuth credential resolution | No | Yes |
| macOS Keychain fallback | No | Yes |
| Bats test suite and CI | No | Yes |

## Examples

### Quota Reset Countdowns

Reset timing appears only when utilization enters the warning zone:

```text
Low usage:   5h[24%] 7d[10%]
Warning:     5h[87%@14:30] 7d[75%~2d5h]
Critical:    5h[95%@14:30] 7d[88%~2d5h]
```

- `5h` uses clock time, because you are usually planning the current work block.
- `7d` uses relative time, because duration is easier to act on than a date.
- Warning thresholds: `5h >= 80%`, `7d >= 70%`.

### Model Abbreviation

Long model IDs are shortened. Aliases stay unchanged.

```text
claude-opus-4-6[1m]  ->  opus4.6[1m]
opus[1m]             ->  opus[1m]
claude-haiku-4-5-*   ->  haiku4.5
```

### Local Test Render

```bash
echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/project","workspace":{"current_dir":"/tmp/project"},"cost":{"total_cost_usd":6.72,"total_lines_added":84,"total_lines_removed":14,"total_api_duration_ms":480000},"version":"2.1.139"}' \
  | bash statusline.sh --test
```

Try another preset:

```bash
echo '{"model":{"id":"claude-sonnet-4-6","display_name":"Sonnet"},"cwd":"/tmp/project","workspace":{"current_dir":"/tmp/project"},"cost":{"total_cost_usd":1.20,"total_lines_added":12,"total_lines_removed":3,"total_api_duration_ms":90000},"version":"2.1.139"}' \
  | bash statusline.sh --test --theme developer
```

## Configuration

Add flags to the configured command in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh --theme compact --style unicode-blocks",
    "padding": 0
  }
}
```

| Flag | Values |
|------|--------|
| `--theme` | `minimal`, `compact`, `detailed`, `developer`, `manager` |
| `--style` | `unicode-blocks`, `single-block`, `bracketed-bars`, `filled-dots`, `square-blocks`, `line-segments`, `ascii-bars`, `percent-only`, `fraction-display` |
| `--order` | Comma-separated component list, such as `model,context,quota` |
| `--path-display` | `project`, `cwd`, `full`, `relative` |
| `--alignment` | `left-right`, `right-left`, `center` |
| `--debug` | Write debug logs to `/tmp/claude-code-statusline.log` |
| `--test [json]` | Render with mock JSON instead of Claude Code input |

Default order:

```text
activity,time,cost,model,context,user,quota,extra
```

## Components

| Component | Shows | Example |
|-----------|-------|---------|
| `activity` | Lines added / removed | `+84/-14` |
| `time` | API duration | `8m` |
| `cost` | Session cost | `$6.72` |
| `model` | Active model, abbreviated | `opus4.6[1m]` |
| `context` | Context window usage | `[█░░░░░26%]` |
| `user` | Tier and display name | `[MAX|feast.t.]` |
| `quota` | 5h and 7d utilization | `5h[24%] 7d[100%~12h6m]` |
| `extra` | Extra-usage spend and prepaid balance | `ex[$16.29/$200 8% bal$4.66]` |

## Themes and Styles

### Themes

| Theme | Layout |
|-------|--------|
| `minimal` | Model, context, and user only |
| `compact` | Everything, unicode bars, project path |
| `detailed` | Bracketed bars and working directory |
| `developer` | Full path, filled dots, right-aligned stats |
| `manager` | Percent-only context, cost first, centered |

### Bar Styles

| Style | Output |
|-------|--------|
| `unicode-blocks` | `[███░░░42%]` |
| `single-block` | `▓ 42%` |
| `bracketed-bars` | `[████░░░░] 42%` |
| `filled-dots` | `●●●○○○ 42%` |
| `square-blocks` | `▰▰▰▱▱▱ 42%` |
| `line-segments` | `━━━┅┅┅ 42%` |
| `ascii-bars` | `|||░░░ 42%` |
| `percent-only` | `42%` |
| `fraction-display` | `3/8` |

## Quota and API Behavior

Quota polling scales with usage so the statusline stays useful without calling
the API on every render.

| 5h utilization | Poll interval |
|----------------|---------------|
| `< 20%` | 5 minutes |
| `20-49%` | 2 minutes |
| `50-79%` | 1 minute |
| `>= 80%` | 30 seconds |

Error backoff is 2 minutes. Cache writes are atomic via temporary file plus
`mv`.

Extra-usage data comes from Claude Code's OAuth usage response. When extra usage
is enabled and the profile cache contains an organization UUID, prepaid balance
is fetched from the matching organization credits endpoint and cached for 5
minutes. The component is read-only; it never changes your monthly limit or
auto-reload settings.

Expired OAuth access tokens are refreshed from `refreshToken` in
`~/.claude/.credentials.json` before usage/profile requests, matching Claude
Code's normal token flow. Refresh failures fall back to the existing token and
the usual API error backoff.

OAuth behavior:

1. If `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, or `ANTHROPIC_BASE_URL` is
   set, quota, user, and extra-usage components are skipped.
2. `~/.claude/.credentials.json` is checked for an OAuth token.
3. macOS Keychain is used as a fallback when no file token is available.
4. OrbStack resolves the real Linux home directory via `getent passwd`.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_CONTEXT_LIMIT` | auto | Context token limit override |
| `CLAUDE_DATA_DIR` | script directory | Usage log location |
| `CLAUDE_CACHE_DIR` | script directory `sessions/` | Quota and profile cache |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Max output token reserve |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude config directory |

## Safety Notes

- The installer modifies only `~/.claude/statusline.sh` and the `statusLine`
  block in `~/.claude/settings.json`.
- The runtime reads Claude Code's statusline JSON input and local transcript
  data needed to calculate context usage.
- Quota, profile, and extra-usage requests go to Anthropic OAuth endpoints only
  when Claude Code OAuth credentials are available.
- Debug logging is opt-in with `--debug`.
- There is no third-party analytics service and no maintainer telemetry.

## Testing

```bash
npm exec --yes bats -- t/
```

The suite currently covers 58 Bats tests:

- `t/statusline.bats`: model abbreviation, reset formatting, OAuth refresh,
  usage colors, adaptive TTL, progress bars, extra usage, context limits, and render
  integration.
- `t/install.bats`: installer file creation, settings merge behavior, command
  updates, padding preservation, and output.

CI runs the same command on push and pull request to `main`.

## Project Structure

```text
.github/workflows/test.yml   GitHub Actions test workflow
assets/statusline-preview.svg README terminal preview
statusline.sh                Main statusline script
install.sh                   One-line installer
t/statusline.bats            Statusline unit and integration tests
t/install.bats               Installer tests with mock curl and isolated HOME
t/helpers.bash               Test helpers that source the real script
CHANGELOG.md                 Release notes
CONTRIBUTING.md              Contribution guide
docs/devlog/                 API contract notes and implementation history
LICENSE                      MIT license
```

## Maintenance

- Latest tag in this repo: `v0.3.0`
- CI: GitHub Actions running `npm exec --yes bats -- t/`
- Tests: 58 Bats tests
- API contract checked against Claude Code CLI `v2.1.76` and `v2.1.139`
- License: MIT

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

Short version:

1. Keep the script dependency-light: Bash, `jq`, and `curl`.
2. Add or update tests for user-facing behavior.
3. Run `npm exec --yes bats -- t/` before opening a PR.
4. Update [CHANGELOG.md](CHANGELOG.md) for visible behavior changes.

Issues are most useful when they include terminal, shell, Claude Code version,
and a reproducible `--test` input or debug log.

## Acknowledgments

Built on the official [Claude Code statusline API](https://code.claude.com/docs/en/statusline).

## License

[MIT](LICENSE)
