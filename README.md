# Claude Code Statusline

[![tests](https://github.com/thevibeworks/claude-code-statusline/actions/workflows/test.yml/badge.svg)](https://github.com/thevibeworks/claude-code-statusline/actions/workflows/test.yml)
[![version](https://img.shields.io/github/v/tag/thevibeworks/claude-code-statusline?label=version&sort=semver)](https://github.com/thevibeworks/claude-code-statusline/releases)
[![license](https://img.shields.io/github/license/thevibeworks/claude-code-statusline)](LICENSE)

A batteries-included status bar for [Claude Code](https://code.claude.com).
Live quota with reset countdowns, adaptive polling, model abbreviation,
subscription tier, 5 themes, 9 bar styles.

```
myproject (main*)  +84/-14 8m $6.72 opus4.6[1m][█░░░░░26%] [MAX|feast.t.] 5h[24%] 7d[100%~12h6m]
    ^        ^       ^     ^   ^        ^          ^            ^           ^          ^
  project  branch  edits  time cost    model     context       user      5h quota   7d quota
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh | bash
```

Downloads the script to `~/.claude/`, configures `settings.json`, done. Needs `jq` and `curl`.

<details>
<summary>Other install methods</summary>

**Ask Claude Code** -- paste into any session:

```
Install claude-code-statusline: curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh | bash
```

**Manual:**

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

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

## Why This Instead of `/statusline`?

Claude Code's built-in [`/statusline`](https://code.claude.com/docs/en/statusline)
generates basic one-off scripts. This does more:

| Feature | `/statusline` | This |
|---------|:---:|:---:|
| Context bar | * | * |
| Cost / duration | * | * |
| Git branch | * | * |
| Live quota (5h/7d) | | * |
| Quota reset countdown | | * |
| Adaptive API polling | | * |
| Subscription tier | | * |
| Model abbreviation | | * |
| Themes / bar styles | | * |
| OAuth credential resolution | | * |
| macOS Keychain support | | * |

## Features

### Quota Reset Countdowns

When utilization enters the warning zone, reset time appears automatically:

```
Low usage:   5h[24%] 7d[10%]
Warning:     5h[87%@14:30] 7d[75%~2d5h]
Critical:    5h[95%@14:30] 7d[88%~2d5h]
```

- **5h**: wall-clock time (`@14:30`) -- you're planning your day
- **7d**: relative countdown (`~2d5h`) -- you need the duration, not a date

Thresholds: 5h at 80% (yellow), 7d at 70% (yellow).

### Model Abbreviation

Full model IDs get shortened. Aliases stay unchanged.

```
claude-opus-4-6[1m]  -->  opus4.6[1m]     (pinned version)
opus[1m]              -->  opus[1m]         (alias, unchanged)
claude-haiku-4-5-*    -->  haiku4.5
```

### Adaptive Polling

Quota polling scales with usage. Doesn't waste API calls when you're idle.

| 5h Utilization | Poll Interval |
|----------------|---------------|
| < 20%          | 5 min         |
| 20-49%         | 2 min         |
| 50-79%         | 1 min         |
| >= 80%         | 30 sec        |

Error backoff: 2 min. Atomic cache writes via tmp+mv.

### Context Window

Matches the CLI's `/context` formula exactly:

```
percentage = totalTokens / contextWindow * 100
```

1M auto-detected from `model.id` `[1m]` suffix. Override: `CLAUDE_CONTEXT_LIMIT`.

## Components

Default order: `activity,time,cost,model,context,user,quota`

| Component  | Shows                       | Example                   |
|------------|-----------------------------|-----------------------    |
| `activity` | Lines added/removed         | `+84/-14`                 |
| `time`     | API duration                | `8m`                      |
| `cost`     | Session cost                | `$6.72`                   |
| `model`    | Active model (abbreviated)  | `opus4.6[1m]`             |
| `context`  | Context window usage bar    | `[█░░░░░26%]`             |
| `user`     | Tier + display name         | `[MAX\|feast.t.]`         |
| `quota`    | 5h / 7d utilization         | `5h[24%] 7d[100%~12h6m]` |

Reorder: `--order "model,context,quota"`

## Themes and Styles

<details>
<summary>5 themes, 9 bar styles</summary>

### Themes (`--theme`)

| Theme       | Layout                               |
|-------------|--------------------------------------|
| `minimal`   | Model + context + user only          |
| `compact`   | Everything, unicode bars (default)   |
| `detailed`  | Bracketed bars, working path         |
| `developer` | Dot bars, right-aligned, full path   |
| `manager`   | Percent only, cost prominent         |

### Bar Styles (`--style`)

| Style              | Output                  |
|--------------------|-------------------------|
| `unicode-blocks`   | `[███░░░42%]` (default) |
| `single-block`     | `▓ 42%`                 |
| `bracketed-bars`   | `[████░░░░] 42%`        |
| `filled-dots`      | `●●●○○○ 42%`           |
| `square-blocks`    | `▰▰▰▱▱▱ 42%`           |
| `line-segments`    | `━━━┅┅┅ 42%`           |
| `ascii-bars`       | `\|\|\|░░░ 42%`        |
| `percent-only`     | `42%`                   |
| `fraction-display` | `3/8`                   |

</details>

## Configuration

```
--style <style>        Progress bar style
--theme <theme>        Preset (overrides style/order/path/alignment)
--order <csv>          Component order
--path-display <type>  project | cwd | full | relative
--alignment <type>     left-right | right-left | center
--debug                Log to /tmp/claude-code-statusline.log
--test [json]          Test mode
```

| Variable                         | Default          | Purpose                       |
|----------------------------------|------------------|-------------------------------|
| `CLAUDE_CONTEXT_LIMIT`           | auto             | Context token limit override  |
| `CLAUDE_DATA_DIR`                | script directory | Usage log location            |
| `CLAUDE_CACHE_DIR`               | `$DATA_DIR/sessions` | Quota/profile cache      |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS`  | `32000`          | Max output tokens             |
| `CLAUDE_CONFIG_DIR`              | `~/.claude`      | Claude config directory       |

<details>
<summary>OAuth gate and credentials</summary>

Quota/user components are **skipped** when `ANTHROPIC_API_KEY`,
`ANTHROPIC_AUTH_TOKEN`, or `ANTHROPIC_BASE_URL` is set.

Credential resolution:
1. **Linux:** `~/.claude/.credentials.json`
2. **macOS:** Keychain first, plaintext fallback
3. **OrbStack:** resolves real `$HOME` via `getent passwd`

</details>

## Testing

```bash
bats t/              # 50 tests (needs: npm install -g bats)
```

Or pipe mock JSON directly:

```bash
echo '{"model":{"id":"claude-opus-4-6[1m]","display_name":"Opus"},"cwd":"/tmp/project","cost":{"total_cost_usd":6.72,"total_lines_added":84,"total_lines_removed":14,"total_api_duration_ms":480000},"version":"2.1.139"}' \
  | bash statusline.sh --test
```

## Project Structure

```
statusline.sh       Main script (single file, no dependencies beyond jq/curl)
install.sh          One-liner installer (downloads + configures settings.json)
t/
  statusline.bats   38 unit + integration tests
  install.bats      12 install tests (mock curl, isolated $HOME)
  helpers.bash      Test helper (sources functions from real statusline.sh)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: run `bats t/` before pushing.

## Acknowledgments

Built on the [Claude Code statusline API](https://code.claude.com/docs/en/statusline).
API contract verified against Claude Code CLI v2.1.76 and v2.1.139 binaries.

## License

[MIT](LICENSE)
