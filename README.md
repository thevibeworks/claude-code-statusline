# Claude Code Statusline

Custom statusline for Claude Code. Shows project, git, model, context, user tier, and quota at a glance.

```
cc-statusline (main)  +105/-3 4m $0.93 opus[1m][██░░░░41%] [MAX|feast.] 5h[12.0%] 7d[99%]
     ^          ^       ^     ^   ^       ^         ^           ^           ^         ^
   project   branch  edits  time cost   model    context      user       5h quota  7d quota
```

## Dependencies

- `jq` -- `brew install jq` / `apt install jq`
- `curl` -- already on your system
- Claude Code OAuth login -- quota and user info need `~/.claude/.credentials.json`

## Install

```bash
cp statusline.sh ~/.claude/statusline.sh
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

With theme and custom cache dir:

```json
{
  "env": {
    "CLAUDE_CACHE_DIR": "/tmp/claude-sessions"
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh --theme compact",
    "padding": 0
  }
}
```

## Components

Default order: `activity,time,cost,model,context,user,quota`

| Component | What it shows | Example |
|-----------|---------------|---------|
| `activity` | Lines added/removed | `+105/-3` |
| `time` | API duration | `4m` |
| `cost` | Session cost | `$0.93` |
| `model` | Active model | `opus` |
| `context` | Context window usage (progress bar) | `[██░░░░41%]` |
| `user` | Subscription tier + display name | `[MAX\|feast.]` |
| `quota` | 5h / 7d API quota utilization | `5h[12.0%] 7d[99%]` |

Custom order: `--order "model,context,quota"`

## Context Window

Context percentage matches the CLI's `/context` formula exactly:

```
percentage = totalTokens / contextWindow * 100
```

Where `totalTokens = cache_read_input_tokens + input_tokens` from the latest assistant message usage.

**1M context auto-detection:** If `model.id` contains `[1m]`, the window is 1,000,000 tokens. Otherwise 200,000. This mirrors the CLI's internal `NO(A)` function. The model display appends `[1m]` so you know which window you're on (e.g. `opus[1m]`).

Override with `CLAUDE_CONTEXT_LIMIT` if you need manual control.

Color thresholds: green < 85%, yellow >= 85%, red >= 100%.

## Themes (`--theme`)

| Theme | What you get |
|-------|--------------|
| `minimal` | Model + context + user only |
| `compact` | Everything, unicode progress bars (default layout) |
| `detailed` | Bracketed bars, shows working path |
| `developer` | Dot progress bars, right-aligned, full path |
| `manager` | Percent only, cost prominent |

## Progress Bar Styles (`--style`)

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

## All Options

```
--style <style>        Progress bar style
--theme <theme>        Preset theme (overrides style/order/path/alignment)
--order <csv>          Component order: activity,time,cost,model,context,user,quota
--path-display <type>  Path display: project | cwd | full | relative
--alignment <type>     Alignment: left-right | right-left | center
--debug                Debug log -> /tmp/claude-code-statusline.log
--test [json]          Test mode (pipe JSON or pass as argument)
```

## Environment Variables

| Variable | Default | What it does |
|----------|---------|--------------|
| `CLAUDE_CONTEXT_LIMIT` | auto-detected | Override context token limit (200k or 1M) |
| `CLAUDE_DATA_DIR` | script directory | Where `usage.jsonl` lives |
| `CLAUDE_CACHE_DIR` | `$CLAUDE_DATA_DIR/sessions` | Cache for quota/profile data |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Max output tokens |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude config directory |

## Quota Display

Format: `5h[12.5%] 7d[70.2%] op[45.0%]` or `sn[16.3%]`

- **5h** -- 5-hour rolling window. Shown when >0%. Yellow at 80%, red at 90%.
- **7d** -- 7-day aggregate. Shown when >0%. Yellow at 70%, red at 85%.
- **op** -- Opus-specific 7d quota (MAX users only).
- **sn** -- Sonnet-specific 7d quota (PRO / TEAM / ENT users).

### Adaptive Quota Polling

The script doesn't hammer the API like an idiot. TTL adapts based on 5h utilization:

| 5h Utilization | Poll Interval |
|----------------|---------------|
| < 20% | 5 min |
| 20-49% | 2 min |
| 50-79% | 1 min |
| >= 80% | 30 sec |

When it matters, you get fresh data. When it doesn't, it backs off. Error backoff is 2 minutes.

### OAuth Gate

If any of these are set, quota/user components are **skipped entirely**:

- `ANTHROPIC_API_KEY`
- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_BASE_URL`

The `/api/oauth/usage` endpoint only works with OAuth tokens at `api.anthropic.com`. Calling it with an API key is pointless, so we don't.

### Credential Resolution

1. **Linux:** `~/.claude/.credentials.json` (reads `claudeAiOauth.accessToken`)
2. **macOS Keychain:** service=`"Claude Code-credentials"`, account=`$USER`
3. **macOS fallback:** `~/.claude/.credentials.json` (plaintext)

**OrbStack:** If `$HOME/.claude` doesn't exist (OrbStack sets `$HOME` to the macOS host path), the script resolves the real home via `getent passwd` and uses that instead.

## Testing

Pipe test JSON to verify everything works:

```bash
echo '{"model":{"id":"claude-opus-4-5-20251101[1m]","display_name":"Opus"},"cwd":"/home/dev/project","cost":{"total_cost_usd":0.93,"total_lines_added":105,"total_lines_removed":3,"total_api_duration_ms":240000}}' \
  | bash ~/.claude/statusline.sh --test
```

Debug mode dumps everything to `/tmp/claude-code-statusline.log`:

```bash
echo '...' | bash ~/.claude/statusline.sh --test --debug
cat /tmp/claude-code-statusline.log
```

## License

MIT
