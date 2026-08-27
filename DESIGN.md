# DESIGN — the statusline's language

One glance, no reading. Every glyph, color and row below is a rule; if a
change breaks a rule, the rule wins or the rule changes here first.

## Rows

```
line 1   where · what · how much is left           (always)
row 2    the pin  |  where it went                 (top notice left, ledgers right)
row 3    the flash: that notice in full, fading    (~90 s after it first appears)
```

Row 2 mirrors line 1: advice left, evidence right, the gap absorbs the
width, the right edge is line 1's edge (never `COLUMNS`). The pinned
sentence compacts to the room the ledgers leave, cutting at the
rightmost joint (`;` a voice, `·` a clause, `,` a sub-fact) so it gives
up as little as possible; under 16 columns it drops to its own row and
the rows hang as a block: the
widest meets line 1's edge, the rest share its left edge. A lone row is
the block. Line 1 must fit: Claude Code truncates or wraps a wider row
and every anchor beneath it goes wrong. Degrade in value order before
overflowing — trace URL → `[cctrace]` OSC 8 link, then the path/stats
gap → 1. Quiet is a row that does not exist.

Claude Code trims each row it renders (`.trim()` per line, 2.1.234), so
a block's padding rides behind a zero-width `\e[0m`: not whitespace, so
it survives; not ink, so it costs nothing.

**A number line 1 prints is not printed again below.** The 5h badge
always carries its reset while the window is live, so the 5h strip drops
its `@HH:MM` and spends those columns on the message; the 7d badge
carries one only under pressure, so the 7d strip labels its own end
until it does. The test is what line 1 actually rendered, not a
re-derivation of its gates.

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
5h ▄▄▮▯▯ 0.6x @04:00  7d ▅▂▃ ▄▅▁▄▅ ▄▄▂▃▂ ▮▯▯...▯(x14) 0.7x @Wed 09:00
```

One grammar, two scales. `5h` = this window as five hour cells; `7d` =
the period as 34 five-hour slots, oldest left, a gap at each local
midnight *in history only* — the run from `▮` on is contiguous. Both
strips draw their whole grid, so a strip is an axis and not a bar that
grows at you: it holds its width for the life of the window and `▮` walks
it. On the 5h strip that makes the hollow run the answer to *how long
have I got* — `▃▄▮▯▯` is two whole hours after this one.

What neither strip draws on 5h is a *forecast*. An empty cell is a fact;
a `×` is a guess, and on a 5h window the guess is owned twice already —
the badge states the end (`5h[38%@23:00]`) and the notice names the wall
(`5h caps ~14:20`). Cells carry the shape, badges carry state, notices do
the warning. History draws in full; the live row folds the 7d future
after two kept cells into `...▯(x14)` — the 5h windows *after* the one
you are in, all alike, `×` red when the tail projects dry (the `week`
report still draws every slot). The count is the budget line's own,
priced from the same instant, and it folds as soon as folding hides two
cells: the future is one fact, and the ink belongs to history. Each strip
ends
with its pace (used ÷ elapsed; dim <1x, pressure ≥1x, hidden until 5% of the
window has run) and the reset its right edge is — axis labels, not restated
badges.

```
▂▃▄▅▆▇█    burned; height = points that cell cost (▂ ≤2 … ▅ ≤11 … █ >20)
▁          baseline: ran, negligible — the shortest bar of the same block
░          unknown — no sample; never drawn as idle
▮          now
▯          ahead — the hollow of ▮; on 5h, the hours left in the window
...▯(x14)  the folded future: 14 more 5h windows after this one (live 7d row)
×          pace won't cover it (7d only: learned forecast, linear when cold)
```

Burn cells take their badge's pressure color; nothing else in the row is
colored. `▮` moves at cell boundaries; every other cell is history — the
row is freeze-safe by construction. Same glyphs, same math as
[ccpace](https://github.com/thevibeworks/ccpace)'s ledger.

## The notice engine (row 2 left, row 3)

Readers turn the live numbers into **notices**. One record per thing
worth saying:

```
rank  voice  scope  key  hl  short  long
```

- **rank** — value order. The top record is the pin.
- **voice** — `!` pressure (yellow/red) · `+` opportunity (cyan) · `-`
  budget (dim). Cyan can never mean pressure, so colour alone carries
  the stance.
- **scope** — `5h` / `7d` / `fb` / `acct`. One voice per scope per
  frame: two clauses about one window can never disagree.
- **key** — identity of the *condition*, not of the text. Row 3 shows a
  notice only while its key is new to this session (~90 s), so a long
  explanation arrives once and then gets out of the way. Never the pin's
  key: row 3 starts at the second record, so one condition costs one row.
- **hl** — the number the reader acts on: bold, then back to the voice.
- **short / long** — the pin, and the sentence for a surface with a
  whole line (row 3, `--check`, `--week`).

The pin stays while its condition holds. The flash fades. `--notice off`
keeps row 3 quiet; `--advisor off` silences both.

What the readers know, beyond the badges:

```
fb capped ~Thu 07:00     the running model is gone until then
5h caps ~05:18           this sitting hits the wall before its reset
7d dry ~Thu 09:00        the learned weekday forecast, not a straight line
7d rebased 53%→12%       utilization fell INSIDE one window: a plan change or
                         an out-of-band reset moved the denominator, and the
                         ledger below still draws the old period
last 5h of the week      no later window exists to spend the remainder through
fb 91% vs 7d 55%         the MODEL caps first, not the account: switch, and the
                         week's remaining capacity comes back
5h ~40m left             throughput you cannot bank — said only while the week
                         has slack, since an unspent 5h window is otherwise
                         headroom, not waste
~62% will expire         on pace to strand a large chunk of the subscription
```

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
`go heavier`, `go op`. No exclamation marks except the pressure sigil. Numbers
first, verbs second, adjectives never. `,` joins facts, `·` joins
clauses, `;` joins voices. No em dash on the line: a cell wide, it reads
as a minus beside `-`/`+` and says less than `·`.
