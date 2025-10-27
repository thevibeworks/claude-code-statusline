# Claude Code Statusline

Real-time quota monitoring and usage telemetry for Claude Code CLI. Displays 5-hour and 7-day rate limits with color-coded warnings, captures subscription/org metadata, and logs usage snapshots for analytics.

## Features

✨ **Real-time Quota Monitoring**
- Live tracking of Claude API 5-hour and 7-day rate limits
- Automatic refresh with configurable intervals
- Color-coded warnings based on usage percentage

📊 **Usage Telemetry**
- Automatic logging of usage snapshots
- Cost estimation tracking
- Analytics export for reporting

🎨 **9 Progress Bar Styles**
- `basic` - Simple block-based progress
- `shades` - Shaded blocks
- `rect` - Rectangle style with equals signs
- `legacy` - Classic hash/dot style
- `circle` - Circular indicators
- `gradient` - Gradient blocks
- `arrow` - Arrow-based progress
- `dots` - Dot indicators
- `blocks` - Block indicators

🎨 **5 Preset Themes**
- `default` - Balanced color scheme
- `minimal` - Monochrome, clean design
- `colorful` - Vibrant colors
- `dark` - Dark mode friendly
- `light` - Light background optimized

📐 **Flexible Layouts**
- `compact` - Single-line display
- `minimal` - Bare essentials
- `detailed` - Full information panel
- `full` - Complete dashboard with all details

🔧 **CLI Customization**
- Debug mode for troubleshooting
- Test mode for API validation
- Configurable update intervals
- Environment variable support

## Installation

```bash
npm install -g claude-code-statusline
```

Or install locally in your project:

```bash
npm install claude-code-statusline
```

## Quick Start

### 1. Set up your API key

Create a `.env` file:

```bash
CLAUDE_API_KEY=your_api_key_here
```

Or export it in your shell:

```bash
export CLAUDE_API_KEY=your_api_key_here
```

### 2. Start monitoring

```bash
# Basic monitoring
claude-statusline monitor

# With custom theme and layout
claude-statusline monitor --theme colorful --layout detailed

# With custom progress style
claude-statusline monitor --style gradient --layout full
```

## Usage

### Monitor Command

Start real-time quota monitoring:

```bash
claude-statusline monitor [options]

Options:
  -k, --api-key <key>      Claude API key
  -t, --theme <theme>      Theme preset (default, minimal, colorful, dark, light)
  -s, --style <style>      Progress bar style (basic, shades, rect, etc.)
  -l, --layout <layout>    Layout type (compact, detailed, minimal, full)
  -i, --interval <ms>      Update interval in milliseconds (default: 5000)
  --debug                  Enable debug mode
  --no-telemetry          Disable telemetry logging
```

Examples:

```bash
# Compact layout with basic style
claude-statusline monitor --layout compact --style basic

# Full dashboard with gradient bars
claude-statusline monitor --layout full --style gradient --theme colorful

# Minimal monitoring every 10 seconds
claude-statusline monitor --layout minimal --interval 10000

# Debug mode with detailed view
claude-statusline monitor --layout detailed --debug
```

### Status Command

Get a one-time status check:

```bash
claude-statusline status [options]

Options:
  -k, --api-key <key>      Claude API key
  -t, --theme <theme>      Theme preset
  -l, --layout <layout>    Layout type (default: detailed)
```

Example:

```bash
claude-statusline status --layout full
```

### Export Command

Export usage analytics:

```bash
claude-statusline export [options]

Options:
  -k, --api-key <key>      Claude API key
  -s, --start <date>       Start date (YYYY-MM-DD)
  -e, --end <date>         End date (YYYY-MM-DD)
  -o, --output <path>      Output file path (default: ./analytics.json)
```

Example:

```bash
# Export last 7 days
claude-statusline export

# Export specific date range
claude-statusline export --start 2024-01-01 --end 2024-01-31 --output jan-analytics.json
```

### Test Command

Test API connection:

```bash
claude-statusline test [options]

Options:
  -k, --api-key <key>      Claude API key
```

Example:

```bash
claude-statusline test
```

## Configuration

### Environment Variables

Create a `.env` file in your project root:

```bash
# Claude API Configuration
CLAUDE_API_KEY=your_api_key_here
CLAUDE_API_BASE_URL=https://api.anthropic.com

# Statusline Configuration
DEFAULT_THEME=default
DEFAULT_PROGRESS_STYLE=basic
UPDATE_INTERVAL=5000
ENABLE_DEBUG=false
ENABLE_TELEMETRY=true

# Log Configuration
LOG_DIR=./logs
LOG_LEVEL=info
```

## Progress Bar Styles Preview

```
basic:    ████████████████░░░░ | 80%
shades:   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░ | 80%
rect:     [================----] 80%
legacy:   Progress [################....] 80%
circle:   ●●●●●●●●●●●●●●●●○○○○ 80%
gradient: ████████████████░░░░ | 80%
arrow:    >>>>>>>>>>>>>>>>---- 80%
dots:     ••••••••••••••••···· 80%
blocks:   ▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▉▁▁▁▁ 80%
```

## Themes

- **default**: Balanced colors suitable for most terminals
- **minimal**: Black and white, maximum compatibility
- **colorful**: Vibrant colors for dark backgrounds
- **dark**: Optimized for dark terminal themes
- **light**: Optimized for light terminal themes

## Layouts

### Compact
Single-line display with essential information:
```
Claude API Quota: | 5h: ████████████░░░░ 450/500 | 7d: ██████████████░░ 2800/3000
```

### Minimal
Bare essentials only:
```
5h:450/500 7d:2800/3000
```

### Detailed
Full information panel with warnings:
```
╔═══ Claude API Status ═══╗

Subscription: Pro

5-Hour Quota:
  ████████████████████░░░░
  Used: 450/500 (90.0%)
  Remaining: 50
  Resets: 1/15/2024, 3:30:00 PM

7-Day Quota:
  ██████████████████░░░░░░
  Used: 2800/3000 (93.3%)
  Remaining: 200
  Resets: 1/20/2024, 10:00:00 AM

⚠ Warnings:
  ⚠️ 5-hour quota is at 90.0% capacity. 50 requests remaining.

╚════════════════════════╝
```

### Full
Complete dashboard with all metadata:
```
┌─────────────────────────────────────────┐
│      Claude Code Statusline v1.0        │
└─────────────────────────────────────────┘

📊 Subscription Information:
   Tier: Pro
   Features: claude-3-opus, claude-3-sonnet, claude-3-haiku

⏱️  5-Hour Rate Limit:
   ██████████████████████████████ 90.0%
   Used: 450 | Remaining: 50 | Total: 500
   Resets in: 2h 15m

📅 7-Day Rate Limit:
   ████████████████████████████░░ 93.3%
   Used: 2800 | Remaining: 200 | Total: 3000
   Resets in: 4d 18h

⚠️  Active Warnings:
   • [WARNING] 5-hour quota is at 90.0% capacity. 50 requests remaining.
   • [WARNING] 7-day quota is at 93.3% capacity. 200 requests remaining.

─────────────────────────────────────────
Last updated: 3:30:15 PM
```

## Programmatic Usage

You can also use the library programmatically:

```typescript
import { QuotaMonitor, StatuslineConfig } from 'claude-code-statusline';

const config: StatuslineConfig = {
  theme: 'colorful',
  progressStyle: 'gradient',
  layout: 'detailed',
  updateInterval: 5000,
  enableDebug: false,
  enableTelemetry: true,
};

const monitor = new QuotaMonitor('your-api-key', config);

// Start continuous monitoring
await monitor.start();

// Or get a one-time status
const status = await monitor.getStatus();
console.log(status);

// Stop monitoring
monitor.stop();

// Export analytics
monitor.exportAnalytics(
  new Date('2024-01-01'),
  new Date('2024-01-31'),
  './analytics.json'
);
```

## Telemetry Data

Usage snapshots are logged in JSONL format in the `logs` directory:

```json
{
  "timestamp": "2024-01-15T15:30:00.000Z",
  "quotaLimits": {
    "fiveHour": {
      "limit": 500,
      "remaining": 450,
      "reset": "2024-01-15T17:30:00.000Z",
      "used": 50,
      "percentage": 10
    },
    "sevenDay": {
      "limit": 3000,
      "remaining": 2800,
      "reset": "2024-01-20T10:00:00.000Z",
      "used": 200,
      "percentage": 6.67
    }
  },
  "subscription": {
    "subscriptionTier": "Pro",
    "features": ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]
  },
  "costEstimate": 0.25
}
```

## Pain Points Solved

### 1. Quota Visibility
- Real-time monitoring of rate limits
- Clear visual indicators of usage
- Proactive warnings before hitting limits

### 2. Cost Tracking
- Usage snapshot logging
- Cost estimation
- Historical analytics export

### 3. Developer Experience
- Multiple display options for different workflows
- CLI-friendly output formats
- Easy integration into existing tools

## Development

### Build from source

```bash
# Clone the repository
git clone https://github.com/thevibeworks/claude-code-statusline.git
cd claude-code-statusline

# Install dependencies
npm install

# Build
npm run build

# Run locally
npm start monitor
```

### Run tests

```bash
npm test
```

### Lint

```bash
npm run lint
```

## References

- [Claude Code Statusline Documentation](https://docs.claude.com/en/docs/claude-code/statusline)
- [Implementation Reference](https://gist.github.com/lroolle/26100ab987747fbbafa5c021016ab9ce)

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For issues and questions, please use the [GitHub Issues](https://github.com/thevibeworks/claude-code-statusline/issues) page.