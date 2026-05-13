# Claude Code Statusline

Tmux/terminal statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).
Project, git, model, context, cost, quota, tier -- one line.

```
myproject (main*)  +84/-14 8m $6.72 opus4.6[1m][█░░░░░26%] [MAX|feast.t.] 5h[24%] 7d[100%~12h6m]
    ^        ^       ^     ^   ^        ^          ^            ^           ^          ^
  project  branch  edits  time cost    model     context       user      5h quota   7d quota
```

## Install

Needs `jq` (`brew install jq` / `apt install jq`).

**One-liner:**

```bash
curl -fsSL https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/statusline.sh -o ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
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

**Or let Claude Code do it** -- paste this prompt into any Claude Code session:

```
Download https://raw.githubusercontent.com/thevibeworks/claude-code-statusline/main/statusline.sh
to ~/.claude/statusline.sh (chmod +x). Then add to ~/.claude/settings.json:
statusLine: {type: "command", command: "bash ~/.claude/statusline.sh", padding: 0}
Merge with existing settings if the file already exists.
```
```

## What's New in v0.3.0

**Quota reset times.** When you're burning quota, the statusline tells you
when it resets -- because staring at a percentage doesn't answer the question
you actually have.

- 5h >= 80%: wall-clock time -- `5h[87%@14:30]` -- "can I resume after lunch?"
- 7d >= 70%: relative countdown -- `7d[75%~2d5h]` -- "how long until capacity?"
- Below threshold: just the percentage. You don't need the noise yet.

Clock for 5h because you're thinking about your day. Countdown for 7d because
"resets Tuesday at 09:14 UTC" means nothing to a tired human.

**Model abbreviation.** `claude-opus-4-6` becomes `opus4.6`. Short aliases
(`opus`, `sonnet`, `haiku`) stay unchanged. The version only appears when
you've pinned a specific model rather than using the default alias.

## Components

Default order: `activity,time,cost,model,context,user,quota`

| Component | Shows | Example |
|-----------|-------|---------|
| `activity` | Lines added/removed | `+84/-14` |
| `time` | API duration | `8m` |
| `cost` | Session cost | `$6.72` |
| `model` | Active model (abbreviated) | `opus4.6` |
| `context` | Context window usage bar | `[█░░░░░26%]` |
| `user` | Tier + display name | `[MAX\|feast.t.]` |
| `quota` | 5h / 7d quota utilization | `5h[24%] 7d[100%~12h6m]` |

Custom order: `--order "model,context,quota"`

## Context Window

Matches the CLI's `/context` formula exactly:

```
percentage = totalTokens / contextWindow * 100
```

Where `totalTokens = cache_read_input_tokens + input_tokens` from the latest
assistant message.

**1M auto-detection:** If `model.id` contains `[1m]`, the window is 1,000,000
tokens. Otherwise 200,000. The model display appends `[1m]` so you know which
window you're on: `opus4.6[1m]`.

Override with `CLAUDE_CONTEXT_LIMIT` if needed.

Color: green < 85%, yellow >= 85%, red >= 100%.

## Quota Display

Format: `5h[24%] 7d[100%~12h6m] op[45%]`

- **5h** -- 5-hour rolling window. Yellow at 80%, red at 90%.
- **7d** -- 7-day aggregate. Yellow at 70%, red at 85%.
- **op** -- Opus-specific 7d (MAX users only).
- **sn** -- Sonnet-specific 7d (PRO / TEAM / ENT users).

### Adaptive Polling

The script doesn't hammer the API. TTL adapts based on 5h utilization:

| 5h Utilization | Poll Interval |
|----------------|---------------|
| < 20% | 5 min |
| 20-49% | 2 min |
| 50-79% | 1 min |
| >= 80% | 30 sec |

Fresh data when it matters, backs off when it doesn't. Error backoff: 2 min.

### OAuth Gate

Quota/user components are **skipped** when `ANTHROPIC_API_KEY`,
`ANTHROPIC_AUTH_TOKEN`, or `ANTHROPIC_BASE_URL` is set. The usage endpoint
only works with OAuth tokens at `api.anthropic.com`.

### Credentials

1. **Linux:** `~/.claude/.credentials.json` (`claudeAiOauth.accessToken`)
2. **macOS:** Keychain first, plaintext fallback
3. **OrbStack:** resolves real `$HOME` via `getent passwd`

## Themes (`--theme`)

| Theme | What you get |
|-------|--------------|
| `minimal` | Model + context + user only |
| `compact` | Everything, unicode bars (default) |
| `detailed` | Bracketed bars, working path |
| `developer` | Dot bars, right-aligned, full path |
| `manager` | Percent only, cost prominent |

## Bar Styles (`--style`)

| Style | Output |
|-------|--------|
| `unicode-blocks` | `[███░░░42%]` (default) |
| `single-block` | `▓ 42%` |
| `bracketed-bars` | `[████░░░░] 42%` |
| `filled-dots` | `●●●○○○ 42%` |
| `square-blocks` | `▰▰▰▱▱▱ 42%` |
| `line-segments` | `━━━┅┅┅ 42%` |
| `ascii-bars` | `\|\|\|░░░ 42%` |
| `percent-only` | `42%` |
| `fraction-display` | `3/8` |

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

| Variable | Default | What it does |
|----------|---------|--------------|
| `CLAUDE_CONTEXT_LIMIT` | auto | Override context token limit (200k or 1M) |
| `CLAUDE_DATA_DIR` | script directory | Where `usage.jsonl` lives |
| `CLAUDE_CACHE_DIR` | `$CLAUDE_DATA_DIR/sessions` | Quota/profile cache |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Max output tokens |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude config directory |

## Testing

Pipe JSON to verify:

```bash
echo '{"model":{"id":"claude-opus-4-6-20251101[1m]","display_name":"Opus"},"cwd":"/home/dev/project","cost":{"total_cost_usd":6.72,"total_lines_added":84,"total_lines_removed":14,"total_api_duration_ms":480000}}' \
  | bash ~/.claude/statusline.sh --test
```

Add `--debug` to dump diagnostics to `/tmp/claude-code-statusline.log`.

## License

MIT
