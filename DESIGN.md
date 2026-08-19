# DESIGN — the statusline's language

One glance, no reading. Every glyph, color and row below is a rule; if a
change breaks a rule, the rule wins or the rule changes here first.

## Rows

```
line 1   where · what · how much is left            (always)
row 2    where it went: 5h + 7d ledgers             (--week, auto = once there is a past)
row 3    what to do about it: the advisor           (--advisor, auto = pressure or surplus)
```

Evidence above interpretation. Rows 2–3 right-align to line 1's edge (the
badges they belong to), never to `COLUMNS`. Line 1 must fit: Claude Code
truncates or wraps a wider row and every anchor beneath it goes wrong.
Degrade in value order before overflowing — trace URL → `[cctrace]` OSC 8
link, then the path/stats gap → 1. Quiet is a row that does not exist.

## Line 1, left → right

```
path (branch*)  [trace]  [☠ deadman]     +A/-D  1h30m  $6.72+.37  model[ctx bar]  fb[67%]  [MAX|@tag]  5h[42%@14:30]+2  7d[75%@2d]  ex[$16/$200 8%]
identity ────────────────────────────    activity  time   cost      model         scoped   who         windows                 money
```

- Left = identity of *this session* (where, wire, lifecycle). Right = the
  account's numbers. Left is neutral; pressure lives right.
- One badge per fact. A number that already sits on line 1 is not repeated
  in a row below.

## Color: three lanes

```
status     green / yellow / red    pressure ONLY: quota, context, cache, premium band, effort
identity   magenta / cyan / blue   model family (fable = bright red, its TUI color)
neutral    grey / white / dim      everything else; MAX bold, PRO normal
```

Warm always means "near a limit or a cost". Cyan in the advisor means
opportunity (`+`), never pressure. Bold marks *now* (`▮`, `[MAX`), not
importance.

## Time: freeze-safe

Claude Code re-renders only on activity. A relative time rots in a frozen
frame; a wall-clock time stays true.

```
@14:30            reset inside 24h — wall clock
@5d               reset > 24h out — decays a day per day (mild)
~05:18            projection ("caps ~05:18") — wall clock
52m before reset  future-to-future gap, both endpoints in the future
```

Never `in 1h38m`.

## Flash

A change since the last frame of *this session* shows for ~60 s in
reverse video: `+9` context, `-27` after compaction, `+.37` cost, `+2`
quota climb. Drops in quota (a reset) stay silent — the low number is its
own signal.

## The ledgers (row 2)

```
5h ▃▄▮▯▯▯▯▯▯▯ 0.6x @04:00  7d ▅▁▂ ▃▅ˍ▃▅ ▃▃▁▂▁ ▅ˍ▂▁▁ ˍˍˍ▃▅ ˍˍˍ▅ ▆▆ˍ▂▮▯▯ 0.7x @Wed 09:00
```

One grammar, two scales. `5h` = this window as 10 half hours; `7d` = the
period as 34 five-hour windows, oldest left, a gap at each local midnight
*in history only* — the run from `▮` on is contiguous. Each strip ends
with its pace (used ÷ elapsed; dim <1x, pressure ≥1x, hidden under 15 min)
and the reset its right edge is — axis labels, not restated badges.

```
▁▂▃▄▅▆▇█   burned; height = points that cell cost (▁ ≤2 … ▅ ≤11 … █ >20)
ˍ          ran, negligible — a bar of height zero, on the baseline
░          unknown — no sample; never drawn as idle
▮          now
▯          ahead — the hollow of ▮
×          pace won't cover it (7d: learned forecast, linear when cold; 5h: linear)
```

Burn cells take their badge's pressure color; nothing else in the row is
colored. `▮` moves at cell boundaries; every other cell is history — the
row is freeze-safe by construction. Same glyphs, same math as
[ccpace](https://github.com/thevibeworks/ccpace)'s ledger.

## Advisor (row 3)

Speaks when line 1's numbers don't mean what they look like, and — while
the ledgers are showing — says the calm numbers they imply. Three voices,
one hue each: `!` pressure (yellow/red), `+` opportunity (cyan), `-`
budget (dim: windows left · even · heading). Every clause derives from a badge
already shown; max two clauses; the 7d window gets one voice per frame.

## Requests

The API is asked for what the protocol does not hand us, and no more.

- Claude Code passes `rate_limits` (5h/7d) on every render → merged into
  the badges immediately; logged as `source:"stdin"` samples when the pair
  changes (≥60 s apart) and is not behind the cache in the same window
  (they are per session; an idle session reports stale numbers) — free
  history for the ledgers and the forecast. The 5h ledger walks samples as
  a monotone envelope: a dip is stale, never a refund.
- `/api/oauth/usage` (scoped weekly `fb`, extra usage): adaptive TTL by 5h
  heat (300→30 s) with a 120 s floor whenever stdin already carries 5h/7d.
- Profile: 24 h. Prepaid: 5 min. All caches shared per account under
  `~/.claude/statusline/[accounts/<tag>/]` — one fetch serves every
  session, container, and ccpace (`docs/api/state-dir.md`).
- Failure: `usage.err` cooldown, 120 s doubling to 600 s, `Retry-After`
  wins; render the last cache with `!429` / `!net`, never blank.

## Words

Lowercase, terse, plain: `caps`, `dry`, `unused`, `expires`, `spend it`,
`go heavier`. No exclamation marks except the pressure sigil. Numbers
first, verbs second, adjectives never.
