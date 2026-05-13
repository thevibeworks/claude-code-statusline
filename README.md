# Claude Code Statusline

A batteries-included statusline for [Claude Code](https://code.claude.com).
Shows what the built-in `/statusline` can't: live quota with reset countdowns,
adaptive polling, model abbreviation, subscription tier, themes, and bar styles.

```
myproject (main*)  +84/-14 8m $6.72 opus4.6[1m][███░░░26%] [MAX|feast.t.] 5h[24%] 7d[100%~12h6m]
    ^        ^       ^     ^   ^        ^          ^            ^           ^          ^
  project  branch  edits  time cost    model     context       user      5h quota   7d quota
```

## Install

**One-liner** (recommended -- needs `jq` and `curl`):

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh | bash
```

Downloads the script, merges into your `settings.json`, done.

**Ask Claude Code** -- paste this into any session:

```
Install claude-code-statusline: curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/install.sh | bash
```

**Manual** -- if piping curl to bash makes you twitch:

```bash
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

## What's New in v0.3.0

**Quota reset countdowns.** Percentages don't answer your actual question:

- 5h >= 80%: wall-clock -- `5h[87%@14:30]` -- "can I resume after lunch?"
- 7d >= 70%: countdown -- `7d[75%~2d5h]` -- "how long until capacity?"
- Below threshold: just the percentage. No noise until you need it.

**Model abbreviation.** `claude-opus-4-6` becomes `opus4.6`. Short aliases
stay unchanged. Version only appears when you've pinned a specific model.

## Components

Default order: `activity,time,cost,model,context,user,quota`

| Component  | Shows                       | Example               |
|------------|-----------------------------|-----------------------|
| `activity` | Lines added/removed         | `+84/-14`             |
| `time`     | API duration                | `8m`                  |
| `cost`     | Session cost                | `$6.72`               |
| `model`    | Active model (abbreviated)  | `opus4.6[1m]`         |
| `context`  | Context window usage bar    | `[███░░░26%]`         |
| `user`     | Tier + display name         | `[MAX\|feast.t.]`     |
| `quota`    | 5h / 7d quota utilization   | `5h[24%] 7d[100%~12h6m]` |

Custom order: `--order "model,context,quota"`

## Context Window

Matches the CLI's `/context` formula:

```
percentage = totalTokens / contextWindow * 100
```

Where `totalTokens = cache_read_input_tokens + input_tokens` from the latest
assistant message.

**1M auto-detection:** If `model.id` contains `[1m]`, the window is 1,000,000
tokens. Otherwise 200,000. Override with `CLAUDE_CONTEXT_LIMIT`.

Color: green < 85%, yellow >= 85%, red >= 100%.

## Quota

Format: `5h[24%] 7d[100%~12h6m] op[45%]`

- **5h** -- 5-hour rolling window. Yellow at 80%, red at 90%.
- **7d** -- 7-day aggregate. Yellow at 70%, red at 85%.
- **op** -- Opus-specific 7d (MAX users only).
- **sn** -- Sonnet-specific 7d (PRO / TEAM / ENT users).

### Adaptive Polling

Doesn't hammer the API. TTL scales with 5h utilization:

| 5h Utilization | Poll Interval |
|----------------|---------------|
| < 20%          | 5 min         |
| 20-49%         | 2 min         |
| 50-79%         | 1 min         |
| >= 80%         | 30 sec        |

Error backoff: 2 min.

### OAuth Gate

Quota and user components are **skipped** when `ANTHROPIC_API_KEY`,
`ANTHROPIC_AUTH_TOKEN`, or `ANTHROPIC_BASE_URL` is set. The usage endpoint
only works with OAuth tokens at `api.anthropic.com`.

### Credentials

1. **Linux:** `~/.claude/.credentials.json` (`claudeAiOauth.accessToken`)
2. **macOS:** Keychain first, plaintext fallback
3. **OrbStack:** resolves real `$HOME` via `getent passwd`

## Themes (`--theme`)

| Theme       | What you get                         |
|-------------|--------------------------------------|
| `minimal`   | Model + context + user only          |
| `compact`   | Everything, unicode bars (default)   |
| `detailed`  | Bracketed bars, working path         |
| `developer` | Dot bars, right-aligned, full path   |
| `manager`   | Percent only, cost prominent         |

## Bar Styles (`--style`)

| Style              | Output                 |
|--------------------|------------------------|
| `unicode-blocks`   | `[███░░░42%]` (default)|
| `single-block`     | `▓ 42%`                |
| `bracketed-bars`   | `[████░░░░] 42%`       |
| `filled-dots`      | `●●●○○○ 42%`          |
| `square-blocks`    | `▰▰▰▱▱▱ 42%`          |
| `line-segments`    | `━━━┅┅┅ 42%`          |
| `ascii-bars`       | `\|\|\|░░░ 42%`       |
| `percent-only`     | `42%`                  |
| `fraction-display` | `3/8`                  |

## Options

```
--style <style>        Progress bar style
--theme <theme>        Preset theme (overrides style/order/path/alignment)
--order <csv>          Component order: activity,time,cost,model,context,user,quota
--path-display <type>  project | cwd | full | relative
--alignment <type>     left-right | right-left | center
--debug                Log to /tmp/claude-code-statusline.log
--test [json]          Test mode (pipe JSON or pass as argument)
```

## Environment Variables

| Variable                         | Default          | Purpose                               |
|----------------------------------|------------------|---------------------------------------|
| `CLAUDE_CONTEXT_LIMIT`           | auto             | Override context token limit           |
| `CLAUDE_DATA_DIR`                | script directory | Where `usage.jsonl` lives             |
| `CLAUDE_CACHE_DIR`               | `$CLAUDE_DATA_DIR/sessions` | Quota/profile cache      |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS`  | `32000`          | Max output tokens                     |
| `CLAUDE_CONFIG_DIR`              | `~/.claude`      | Claude config directory               |

## Testing

Pipe JSON to verify output:

```bash
echo '{"model":{"id":"claude-opus-4-6-20251101[1m]","display_name":"Opus"},"cwd":"/home/dev/project","cost":{"total_cost_usd":6.72,"total_lines_added":84,"total_lines_removed":14,"total_api_duration_ms":480000}}' \
  | bash ~/.claude/statusline.sh --test
```

Add `--debug` to dump diagnostics to `/tmp/claude-code-statusline.log`.

## Official Docs

The [Claude Code statusline documentation](https://code.claude.com/docs/en/statusline)
covers the built-in JSON fields (`context_window.used_percentage`,
`rate_limits.five_hour.resets_at`, etc.) and basic configuration.

This script uses all of those fields and adds quota tracking with reset
countdowns, adaptive polling, subscription tier display, and model abbreviation
-- things the official examples don't cover.

Worth knowing from the official docs: settings live in `~/.claude/settings.json`;
`refreshInterval` enables periodic updates; script fires after each assistant
message (debounced 300ms); `disableAllHooks: true` kills the statusline too.

## License

MIT
