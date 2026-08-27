# Changelog

## v0.35.0 — 2026-08-27 — a directory is where a sample landed, not who it belongs to

**A directory is where a sample landed, not who it belongs to.** The
same account reaches `~/.claude/statusline/` when an untagged statusline
fetched and `accounts/<tag>/` when a deva-tagged container did, and
every aggregating reader — the forecast, the ledger strip, `report` —
read only the directory it was standing in. Measured on one machine:
301 days of history at the root, 28 in the tagged dir, one uuid. Nothing
was visibly wrong, because 28 clears the 14-day floor. The failure sits
one step ahead: every new `DEVA_AUTH_TAG` starts an empty directory for
an account with ten months of samples one level up, and renders "still
learning" for two weeks. The readers now take the union — root plus
every `accounts/*/` — and partition by `user.uuid`, which is the rule
the state-dir contract already stated and ccpace already followed. The
union is safe for this data because every quantity is envelope-based:
the same window seen from two containers takes a max, never a sum.
`week.cache` keys on every store's mtime:size so a sample landing
anywhere invalidates it. Cost: 1.2 s per hourly rebuild over 31 MiB.

**`forecast.cache` says which samples it stands on.** `schema` versions
the model and cannot: statusline and ccpace agree on envelope burn, read
different stores, both pass the gate, and `days_history` — the number
that decides whether a forecast speaks at all — depended on which binary
rendered last. A `corpus` stamp (`uuid`, `files`, `samples`,
`dropped_no_uuid`, `oldest`) makes that visible in one `jq`. It is
informative, not a gate; ccpace v0.3.1 writes the same one.

**A dropped row is counted.** 94 rows in that store carry no
`user.uuid` (the field is younger than the log) and every
uuid-partitioned reader discarded them in silence. They stay dropped —
thirteen carry an email that would identify them, and guessing identity
on a log that already interleaves accounts is how a 9000%/day burn rate
gets manufactured — but the count is in the stamp. Loss is acceptable;
silent loss is not.

**`session.project`.** Each `usage` line's session block now carries
the basename of the project directory. The quota log knows percent, the
transcript knows tokens, and neither knew which repo the week went to;
this is the one dimension a breakdown cannot recover later. Basename
only, never the path.

**The ledger is one typeface again.** The baseline — a cell that ran and
cost nothing — was `ˍ` (U+02CD MODIFIER LETTER LOW MACRON). Every bar
above it comes from Block Elements, and terminals resolve the two through
different faces: the zero line sat at a different height and a different
advance width than the bars beside it, and the seam showed on every row
that held both. It is `▁` now, the shortest bar of the same run, so the
whole ladder is one block. Burn therefore starts one rung up, at `▂`;
`▅` and everything above it keep their old thresholds, so a fully burned
window still reads the same height it always did. `LEDGER_BASE_GLYPH`
overrides it.

**A shared cache needs a version, not just a timestamp.** `forecast.cache`
lives in `~/.claude/statusline/`, which is a published shared store, and
it is the one derived file more than one tool wants to write. A
co-writer that counted burn as the sum of raw positive deltas — the
accounting this script abandoned two releases ago, because a stale dip
gets refunded and then re-earned — published a profile with `149.11`
into Thursday and dropped `pct_per_window`, `scoped_*` and `cost` on the
way past.

Everything downstream did the right thing and the result was still
wrong. The walk's corrupt-profile guard saw 149%/day, judged it
impossible and went silent. The exchange rate, the price and the scoped
forecast lost their inputs and said "still learning". The budget line
fell back to linear pace. Nothing lied; the account simply had a sound
profile ten minutes earlier and no way back to it, because the rebuild
gate asked only whether the file was fresh — and it was, having been
overwritten seconds ago. Silence is a defence against a bad model. It is
not a substitute for knowing whose model you are reading.

So the cache carries `schema` now, the version of the MODEL rather than
of the file, and freshness is necessary instead of sufficient: a cache
whose schema is missing or lower is rebuilt on sight. The contract for
co-writers is written down (`docs/api/state-dir.md`) and it cuts both
ways — stamp the schema you actually implement, and either write the
full key set or merge into what is there. Rebuilding the fields you know
and dropping the rest is a truncating write.

**`heading` was neither.** The budget line carried two futures with no
grammar to tell them apart: `even 6.2%/win` is a RATION — spend that per
window and the pool lands exactly on 100 — and the other number is a
PREDICTION of where your own pattern takes you. A direction is not a
destination, and the reader was left working out which of the two was
the forecast. It reads `lands ~91%` now, in the budget line and in
`report`'s week-in-progress alike.

Row 2 states the landing rather than the ration. Of the three clauses
the long form carries it is the only one not already on screen: the
count is drawn on the strip beside it as `...▯(✕9)` and the ration is
surplus ÷ that count, but where the week ends up is nowhere else. It is
also the clause that answers what a calm week actually asks — not "how
do I ration this" but "am I going to strand it". With no projection yet
(a young week, a cold profile) there is no landing to state and the row
falls back to the ration.

## v0.34.0 — 2026-08-24 — five slots, and a window you are in is not one you have left

**The 5h strip is five cells again — but the future in them is empty, not
judged.** v0.33.0 was right that `5h ▮▯×××` was unreadable and wrong about
which half to cut. The `×` was the problem: a linear projection dressed as
ink, saying a third time what the badge (`5h[38%@23:00]`) and the notice
(`5h caps ~14:20`) already say with better gates and an exact time. The
hollow cells were never the problem — they were the axis. Ending the strip
at `▮` took the ruler away with the forecast, and left a bar that grew an
hour at a time and answered "how long have I got" with nothing.

So: five slots, always, one per hour, no dry cell in any of them.
`5h ▃▃▮▯▯` is two whole hours after this one, read off the row without
arithmetic and without a second glance at the clock. Fixed width is the
other half of it — the row holds its shape for the life of the window
instead of reflowing every hour, which is the difference between an axis
and a bar that grows at you. An empty cell is a fact; a `×` is a guess, and
only one of those belongs in a ledger.

`▮` now rides the real clock rather than the grid. `five_period_start`
rounds to five minutes so `week_scan`'s cache key holds still across renders
— a `resets_at` that jitters by a second would re-run a whole-log `jq` pass
every render — and that rounding offsets every hour boundary by up to 2½
minutes. Invisible in a bar height; wrong exactly where this strip is read.
With the marker at `4 - floor(left / 1h)` the hollow count is the whole hours
remaining to the second: at the 119-minute mark, three hours and one minute
left drew as two, and now does not.

**`N✕5h left` no longer counts the window you are standing in.** The row
draws it as `▮` and line 1 prices it as `5h[38%]`, so counting it again
made `▮ + 11` read as twelve, and the budget sentence beside it agreed with
the miscount. "Left" now means still to come: what remains after this
window closes, `(7d left - 5h left)`, divided into windows — a stub at the
end of the week is still a window you can spend, so that rounds up.

The arithmetic has a property the old one did not: both clocks tick down
together, so the difference does not move. The count holds steady for the
life of a window and steps down by exactly one at each rollover. It was a
reading that drifted; it is a countdown now. `windows_ahead` is that
definition in one place, and the folded `...▯(✕N)` prints what the budget
line computed rather than re-deriving it off a 34-cell grid that spans 170h
against a 168h period.

`last window` now means the week ends inside the one you are in — nothing
ahead of it, nothing to divide the surplus across. It used to fire at one
window ahead too, to skip a `/win` clause that would just restate the
headroom; calling two windows the last one to save a redundant clause is the
wrong trade. At one ahead the line keeps the grammar: `1✕5h left · 25.0%/win`.

**`make install`.** The one-liner installed from GitHub and there was no
way to install the tree in front of you, so a working copy got there by
hand — and a stale hand-copy is how v0.28.0 once faked a red "7d dry" at
2%. `make install` runs the same `install.sh` with `STATUSLINE_SRC` set:
one installer, two entrypoints, no drift. It also refuses a
`statusline.sh` that does not parse — a broken statusline is not a worse
render, it is no statusline.

Three things the installer should have been doing all along, now on both
paths: it **keeps the flags** already on `statusLine.command` (rewriting
the whole command silently reverted `--order` and `--debug` on every
update), it writes through a temp file and renames (the script runs on
every render; a half-written one is a broken prompt), and it installs the
`usage-insight` skill beside it (`STATUSLINE_SKILL=0` opts out).

`make status` reports installed-vs-tree drift, settings command and skill
state; `make check` is shellcheck + bats; `make install-check` gates the
install on both. `make help` lists the rest.

435 tests (was 427).


## v0.33.0 — 2026-08-23 — the strip is a record, not a forecast

**The 5h strip stops at `▮`.** It used to draw the rest of the window as
hollow cells and then, when linear pace said so, as a wall of `×` —
`5h ▮▯××`, which a user could not read, and was right not to. Three
things were saying one thing badly: the badge above already prints when
this window ends (`5h[38%@23:00]`), the notice engine already names the
wall with an exact time and its own gates (`5h caps ~14:20`), and the
strip was dramatising both a third time in four columns. A 5h window is
short enough that its future is a clock, not a shape. The strip now
draws what happened and ends — no `▯`, no `×`, no projection at all, and
`five_dry_cell` is gone rather than guarded. Strips carry history, badges
carry state, notices do the warning.

Both glyphs keep their meaning on the 7d strip, where the future is 34
cells long and genuinely has a shape, and in the `week` report.

**The 7d future folds as soon as folding hides two cells.** The old
threshold was 10, justified by a column break-even that measured the
wrong thing: eleven hollow cells read as "too much future" long before
they got expensive. With two kept cells the tail is now at most `▯▯▯`
drawn raw, or `▯▯...▯(✕N)` — and `N`, the windows you have left, is the
part that has to survive mid-week, when a pressure notice owns the pin
and this row is the only place that number appears. A closing week still
draws to its edge with no special case: four cells or fewer leave
nothing worth folding.

Row 3's floor (`notice_flash_worth_row`) shipped in v0.32.1, below.

## v0.32.1 — 2026-08-23 — one projection, one floor

**Row 3's gate was measuring the wrong thing.** It required the flash to
beat the pin by `NOTICE_FLASH_MIN_GAIN` columns — the right question in
v0.31.0, when row 3 restated row 2 and the only issue was whether
truncation had left anything extra to say. Since v0.32.0 the flash is a
*different* notice, so that subtraction compared two unrelated sentences
and dropped a short one whenever the pin happened to be long: at 30
columns `! 5h caps ~23:54` (16) beside `! 7d caps ~Tue 07:22` (20) is a
gain of 4, and the second window lost its row for no reason a reader
could name. The gate is now an absolute floor on the compacted flash
itself (`NOTICE_FLASH_MIN_CHARS=16`, in `notice_flash_worth_row`): did
truncation leave a sentence, or a stub? `7d dry ~Wed` says nothing you
can act on; `7d dry ~Wed 19:50` still carries the number.

**A ten-minute-old 5h window drew `▮▯×××`.** One big prompt front-loads
burn — 7% in ten minutes — and `five_dry_cell` projected that as a rate
and walled off the rest of the window. On the very same render the pace
suffix hid itself (too young to judge) and the "5h caps" notice stayed
silent (it waits 15 minutes): three surfaces, one linear projection,
and only the loudest one spoke. The 5h dry cells now wait on the same
evidence the other two do. `window_evidence_floor` is that rule in one
place — 5% of the window's own length, so the 5h trio agrees at 15
minutes and the 7d pace suffix keeps its ~8.4h — and
`ADVISOR_PACE_MIN_ELAPSED` is retired into it, because a constant beside
a formula is a drift waiting to happen.

## v0.32.0 — 2026-08-23 — say it once, and only when you know it

**Row 3 was restating row 2 at greater length.** The flash reader
carried the pinned notice's key and never compared against it, so at
session start the same sentence arrived twice, once short and once
long: `- 12✕5h left · 5.8%/win` over `- budget ~12✕5h left · even
5.8%/win · heading ~85%`. The function's own comment already promised
it "never echoes the pin's own sentence" — now it skips record one and
starts at record two, and row 3 shows the highest-ranked notice the pin
is *not* already carrying. A calm start is two rows, the way it was
supposed to be.

**A 7d projection now needs a day of this window's own evidence.**
Minutes after a weekly rollover the learned walk was projecting last
week's Tuesday onto a pool 2% spent — measured: a 2.4h-old window with
2% used came back `red, dry in 95h`, painted `×` across slot 14
onward, and put `heading ~100%` on the budget line. Every input for
that verdict predates the reset, including the trailing-24h blend the
walk opens with, which describes a day lying on the far side of it.
`SEVEN_DAY_YOUNG_SECS` (86400) silences the learned walk, the linear
at-risk pace, and the dry-cell fallback until the window is a day old
— one gate, so the forecast notices, the `×` cells, the heading, the
accuracy logger and both subcommands go quiet together. Badges still
report real percentages, and a young window that is genuinely spent
still goes red on its own 85%+: the guard mutes pace, never facts. The
5h window is untouched.

**Pace waits for a fraction of its window, not a fixed 15 minutes.**
One gate served both strips: 900 seconds, which is 5% of a 5h window
and 0.1% of a week. An hour into a fresh week, 2% of the pool over
0.6% of the time rendered `3.0✕` in red. The gate is now length/20 —
5h still waits exactly 15 minutes, 7d waits ~8.4h, the same fraction
`seven_day_elapsed` has always called the noise floor.

**The fold token counts windows, not cells: `...▯(✕12)`.** The old
`...▯5h✕10` counted hollow cells the fold hid, while the budget line
beside it priced `12✕5h left` — two arithmetics on one row, and the
reader was left to arbitrate. The 34-cell grid spans 170h against a
168h period, which is where the two differed. The token is now
parenthesized, drops the redundant `5h` unit, and counts the 5h
windows remaining to the true reset: the same number the budget line
prices, from the same instant. Dry tails still read `...×(✕12)` — `×`
the cell, `✕` the operator, one column apart and never the same mark.

**The budget voice drops its sigil.** `!` and `+` mark a notice that
interrupts — you are about to hit something, or there is capacity to
take. The week's resting reading interrupts nothing, and a leading `-`
on a dim line reads as a bullet, which made rows 2 and 3 look like a
two-item list. The pin now reads `12✕5h left · 5.8%/win`. Dim is the
mark; the sentence carries itself. `--check` and `--week` still label
their long form with the word `budget`.

## v0.31.0 — 2026-08-20 — the operator is not a reading

**The ledger row was printing two different X's and calling them both
`x`.** `×` (U+00D7) has always been a cell — the window the pool will
not cover — and `x` was the ASCII letter standing in for multiplication.
The folded tail put them one column apart in the same red: `...×5hx28`,
where the first mark is a fact about your week and the second is
punctuation. It read like a font failure. The multiplication sign is
now `✕` (U+2715) everywhere the product multiplies: the folded future
`...▯5h✕28`, the pace `0.7✕`, the budget notice `- 19✕5h left`, and
`report`'s `(~4.1 ✕ 5h windows unused)`. Cells are the ink; the
operator is punctuation, and it is deliberately the lighter of the two
marks.

**Why that codepoint and not a heavier one.** Row 2 right-anchors the
week row to line 1's edge by counting characters, so a glyph that
counts one and draws two overhangs the edge once per pace suffix — the
same constraint that keeps `≡` and `☠` on their single column. `╳`
(U+2573) is ambiguous-width and doubles under a CJK locale; `✖`
(U+2716) is Emoji=Yes and can fall through to a colour font. `✕` is
neutral-width and not an emoji. Both alternatives look stronger and are
one `MULT_GLYPH=╳` away if your terminal disagrees.

## v0.30.0 — 2026-08-19 — the future folds

**The 7d strip stopped drawing the future one cell at a time.** Thirty
hollow cells after the now-marker carried one fact between them — "the
week has room left" — and spent thirty columns saying it (thirty-one
when the forecast painted them all `×`). The live row now keeps two
cells after `▮` and folds the rest into `...▯5hx28`: the count of 5h
slots to the reset, `×` red when the tail projects dry. History still
draws in full — that is the information — and the fold only engages
when it hides at least ten cells, so a closing week still draws to its
edge. The `week` subcommand's wide ledger is untouched.

**The 5h strip reads by the hour.** Ten half-hour cells were more
resolution than a glance uses; five hour cells tell the same story in
half the width, and the freed columns go to the notice beside them.

**The live demo became the instrument it demos.** The GitHub Pages
site dropped the fake macOS terminal window for a meter: a recessed
register carrying the same frame-by-frame simulation (now with the
folded week tail, hour cells, and a dry-forecast frame), a mono
reading number the anatomy table cites (№ 0008), answering-pair
anatomy rows — the left column states the reading, the right says
what to do about it — and an odometer roll on quota digits that
change. Narrow screens get a truthfully compacted line, the same way
the script itself gives up the trace chip first. Stale claims fixed
across the surfaces: 417 tests everywhere (README said 383, the site
384, llms.txt 379), and llms.txt learned the new week-row grammar.

**The forecast refuses a corrupt profile.** A weekday that claims to
average more than the whole pool per day (`145%/day` of a 100-point
week) can only come from a broken accountant — measured live when a
pre-v0.29.0 build sharing the same home wrote `recent_24h: 343` and the
walk called a 2%-used fresh window dry in 30 hours, red, on every
render. Impossible input now earns silence, not a siren; `recent_24h`
alone clamps to 100 (legitimately larger across a reset, but this
window cannot lose more than everything in a day).

## v0.29.0 — 2026-08-19 — the store learns to count

**Fixed: burn was counted wrong, by a factor of three.** The weekday
profile summed raw positive deltas of `seven_day.utilization`. Every
stale reading — an idle session reporting the numbers it last saw — was
therefore refunded and then re-earned: measured against a real 23 MiB
log, 146 points of "burn" for a week that actually moved 50. The
learner now walks a **monotone envelope**, crediting only the rise of
the running max, and the forecast that reads it stopped inventing
dry-outs that were never coming.

**Telling a stale reading from a real reset needs two signals, because
`resets_at` cannot.** It looks like a window key and for 5h it behaves
like one, but on 2026-08-17 an account's `seven_day.utilization` went
`100.0 → 0.0` and stayed there, sampled by two independent writers,
with `seven_day.resets_at` unchanged: the weekly counter can be reset
out of band. A newer key is certainly a new window; an unchanged one
proves nothing. The envelope re-baselines only on a drop that is both
sustained (≥ 2 consecutive samples) and deep (≥ 15 points) — the
failure mode is a bounded under-count, which costs a missed warning
where the over-count cost a false alarm on every render.

**Fixed: an expired window is never a sample.** A session idle across a
boundary — or a fixture piped in by hand — reports the window it last
saw. Logged, that pair read as a 49-point drop that the next real
sample re-climbed. Rejected now on its own merits: a window whose reset
is already behind us cannot be the current one.

**Fixed: 26% of the log was markers for windows that never rolled.**
`session_start`/`session_end` compared `resets_at` as a raw string, and
the server jitters it (`06:00:00.515434` vs `06:00:00.087190`, and
`05:59:59`/`06:00:00` straddling one boundary), so nearly every fetch
wrote a marker pair — 24,747 of them in a log holding 25,004 real
samples, eaten straight out of the 32 MiB rotation cap. The boundary
test now compares window *instants* with 300 s of slack and requires
the new window to be newer.

**Fixed: the week ledger drew every account at once.** `week_scan` did
not partition by `user.uuid`, which the state-dir contract has required
since v2. The default dir predates account scoping and a real one holds
a dozen uuids.

**New: the model-scoped weekly cap gets the learned forecast.** `fb
caps ~Mon 14:00, 2d before reset` — where linear pace is structurally
silent, because 45% with four days left *is* a calm straight line. A
week whose Tuesday burns 39%/day and whose Sunday burns 6%/day is not a
line. One walker (`_profile_walk`) now serves both the account 7d and
the scoped cap, so the two forecasts cannot disagree about physics, and
the scoped one only ever speaks for the scope its profile was built
from (`scoped_name`) — which model carries the cap is Anthropic's
choice and has changed before.

**New: the statusline records what a percentage costs.** Claude Code
hands us cost, tokens, context size, effort and CLI version on stdin at
every render; until now they were read for the badges and thrown away.
Each `usage` record now carries a `session` block, and `forecast.cache`
gains a `cost` object pricing a 7d point in dollars — the join no
single source can make, since the quota API reports percent and never
dollars on a subscription plan (`limit_dollars` is null) while the
transcripts report dollars and never percent. `report` shows the price
and the spend. The denominator is **paired**: only points observed by a
sample that also carried a dollar figure, because the log predates the
`session` block by months and dividing by all of it would price a week
at pennies.

**Fixed: three test fixtures raced the clock.** The fixture reads
`date`, the function reads it again, and one tick between them flips
`2h30m` to `2h29m`. Reproduced once in ten full runs; +30 s of slack
absorbs the tick without weakening the assertion.

The contract doc gains a **Reading the quota series** section: the four
properties above, plus the two things the series cannot tell you —
gaps are not idleness (samples exist only while a statusline renders),
and `model` is the logging session's, not the spender's.

## v0.28.0 — 2026-08-19 — the notice engine

**New: a notice engine behind rows 2 and 3.** The advisor was one
sentence built by one function; it is now a set of readers that emit
*notices* — records carrying rank, voice, scope, a key for the
condition, the number worth bolding, and both a short and a long form.
Row 2 **pins** the top notice (compacted to the room the ledgers leave,
cut at the rightmost joint so it gives up as little as possible) and
keeps it while the condition holds. Row 3 **flashes** the same notice in
full, but only for ~90 s after that condition first appears in this
session: the explanation arrives once, then leaves the pin alone. A
later story takes row 3 next. `--notice off` (or `STATUSLINE_NOTICE=off`)
keeps row 3 quiet.

**New: notices that know which limit binds.**

- `fb 91% vs 7d 55% · go op` — the *model's* weekly limit caps before the
  account's 7d does. Line 1 shows both numbers, never their relation,
  and the relation is the whole decision: switch and the week's
  remaining capacity comes back. The roomiest other `weekly_scoped`
  limit in the payload gets named; with a projected wall it speaks in
  the pressure voice and carries `dry ~Wed 18:00` in the long form.
- `7d rebased 53%→12%` — utilization fell *inside* one window instance.
  Burn never runs backwards, so this is a plan change or an out-of-band
  reset moving the denominator. Tracked per account, newsworthy for
  30 min, and it mutes the underuse voice while the learned walk still
  describes the old period.
- `last 5h of the week · 47% unused` — the 7d reset lands inside this 5h
  window: no later window exists to spend the remainder through. Carries
  the same feasibility tail as the surplus notice.
- `5h ~40m left · 70% unused` — throughput you cannot bank, said *only*
  when the week is stranding capacity. An unspent 5h window is otherwise
  headroom, not waste: the 5h window is a rate limit, not a budget.

**Shorter rows.** The pin drops what line 1 already prints
(`! 5h caps ~05:18`, not `..., 42m before reset`); the full sentence is
one row down, or on `--check` / `--week`, which have a line to spend.
The number you act on is **bold**. And the 5h strip no longer repeats
the reset the 5h badge carries — one badge per fact, in both directions;
the 7d strip keeps its own label until the 7d badge shows one.

**Fixed: a record with an empty field lost everything after it.** Notice
records were tab-separated, and tab is IFS whitespace — bash collapses
runs of it, so one empty field shifted every field after it. They use US
(0x1f) now. Also fixed a `{ printf; [ -f ] && tail; }` group whose exit
status came from the `[ -f ]` test, so a first-ever notice was never
stamped and the flash never faded.

## v0.27.0 — 2026-08-19 — row 2 mirrors line 1

**The advisor moves up beside the ledgers.** Row 2 now mirrors line 1:
advice on the left, evidence on the right, the gap between them
absorbing the width, the right edge shared with line 1 —
`- budget ~3x5h left · even 20%/win   5h ▂▅█▃▮▯▯▯▯▯ 0.9x @23:00  7d … 0.7x @Wed 09:00`.
The sentence is compacted to the room line 1 leaves: weakest joint
first (`;` the second voice, then `·` the tail clause, then `,` a
sub-fact), the leading fact last — `! 5h caps ~05:18, 52m before reset;
7d dry ~Thu 09:00 · then hard stop` → `! 5h caps ~05:18, 52m before
reset` → `! 5h caps ~05:18`. A calm frame is two rows, not three. Under
16 columns of room (narrow terminals) the rows hang as the v0.26.0 block
instead: ledgers meeting line 1's edge, the full sentence flush-left
beneath. Hero, README and the Pages demo follow.

## v0.26.0 — 2026-08-19 — the rows hang where they belong

**Fixed: the rows beneath line 1 finally land under the badges.** Claude
Code trims every stdout row before rendering (`.trim()` per line, 2.1.234
— verified live), so the leading spaces that right-anchored the week and
advisor rows never reached the screen and both sat flush-left. The
padding now rides behind a zero-width `\e[0m`: not whitespace, so it
survives the trim; not ink, so it costs nothing. Same for a centered
line 1.

**The rows are one block.** The widest row (the ledgers) meets line 1's
edge; the advisor shares its LEFT edge instead of the right one — a
ragged left edge under a fixed right one was a staircase; flush-left
beside the ledgers reads like text. A lone row is the block, so it
right-anchors exactly as before.

**No em dash on the line.** `! fb capped · back ~Thu 07:00`,
`+ 7d resets @09:00, 50% unused · ~33% expires even at full burn`,
`· go heavier`, `· then hard stop`: `,` joins facts, `·` joins clauses,
`;` joins voices. The dash was a cell wide, read as a minus beside
`-`/`+`, and said less.

Hero and the Pages demo now show the three-row block.

## v0.25.0 — 2026-08-19 — the ledgers say their pace

**The ledgers say their pace and their reset; the budget line rides with
them.** Each strip now ends with `0.7x @Wed 09:00`: pace = used ÷
elapsed (dim below 1x, pressure-tinted from 1x, hidden for a window's
first 15 min) and the reset its right edge stands for — axis labels for
a timeline, not badges restated (the 7d reset was mostly absent from
line 1 anyway). And while the week row is showing, the advisor's calm
budget line (`- budget ~3x5h left · even 20%/win · heading ~52%`) shows
with it under `--advisor auto`: the strips and the numbers they imply
are one unit; pressure and surplus clauses still take its place.

**Fixed: stale stdin numbers no longer poison the history.** Claude Code's
`rate_limits` are per session — an idle session keeps reporting the
numbers it last saw, so a stdin pair can sit behind the account's real
state (an `8%` between `21%` and `23%`). A stdin sample is now logged
only when it would win the display merge (same window and not below the
cache, or a newer window), and the 5h ledger walks its samples as a
monotone envelope (running max): a dip is a stale reading, never a
refund — it used to turn into a phantom `█` burst.

## v0.24.0 — 2026-08-19 — the week row, and a line 1 that fits

**New: week row — this sitting and the week as ledgers, under the badges.**
`5h ▂▅█▃▮▯▯▯▯▯  7d ▅▁▂ ▃▅ˍ▃▅ ▃▃▁▂▁ ▅ˍ▂▁▁ ··ˍ▃▅ ··ˍ▅ ▆▆ˍ▂▮ ▯▯`: one grammar
at two scales. The 5h strip is the current window as ten half hours,
height = the 5h points each added; the 7d strip is the period as its 5h
windows (34, oldest left), height = the 7d points each burned, with a
thin gap at each local midnight so days read as clusters without a
ruler. `ˍ` idle, `░` unknown (no sample — never drawn as idle), `▮` now,
`▯` ahead, `×` where the pool runs dry at your pace. Placed where it
reads: right-aligned to line 1's edge like the advisor, and *above* the
advisor — evidence, then interpretation, one column down from the
badges. Day gaps live in history only; the run from `▮` on is contiguous. `--week auto|always|off`; `auto` (default) draws it only once
the log holds a sample for either period, so a fresh install stays one
line. History comes from `usage.jsonl` via a new `week.cache` (one jq
pass for both strips, keyed by the periods + the log's mtime:size), so a
render never pays for the scan; the 7d strip builder is shared with the
`week` subcommand, so the two cannot disagree. Bug fixed on the way: the
period start is now snapped to the same 5-min grid the window keys use —
the API jitters `resets_at` by sub-seconds, and a raw `reset - 7d` could
push slot 0 to slot -1 and lose the first cell of the week. `--theme
minimal` turns the row off.

**Fewer requests: the protocol's own numbers count.** Claude Code passes
`rate_limits` (5h/7d) on every render. Beyond merging them into the
badges (already the case), the statusline now (1) floors the API fetch
interval at 2 min while stdin carries them — the fetch only serves the
model-scoped weekly limit and extra usage, which move at the week's
pace, so the 30 s hot-window cadence was pure load; and (2) logs each
changed pair as a `source:"stdin"` usage sample (>= 60 s apart, account
uuid from profile.cache) — free history for the ledgers, the forecast
and ccpace, zero requests. `--week auto` gates on a *past* cell now, so
the free samples do not switch the row on for a first-ever render.

**Line 1 fits the terminal; every row meets its edge.** Claude Code
hands the script `COLUMNS` and truncates or wraps anything wider — and a
wrapped line 1 put every anchored row (advisor, week) beneath the wrong
edge. Three fixes: widths are counted in characters whatever the
ambient locale (a C/POSIX locale made bash count `█░░░░░` as 18 columns
and pad line 1 short); when line 1 would not fit, the trace chip's URL
text collapses to `[cctrace]` carrying the same target as an OSC 8
hyperlink (9 columns for ~35) before the path/stats gap drops to 1; and
when the width is *known* (tty or `COLUMNS`) the extra rows anchor at
the visible edge rather than at overflowing content — a guessed width
(a pipe's flat 80) still never clamps, as before.

**Trace chip: `http://localhost:<port>`.** cctrace dropped its portless
route (`https://cctrace.localhost`); the chip's URL is the loopback port
form everywhere now, and deva exports the same shape in
`DEVA_TRACE_UI_URL`.

**Trace chip deep-links the current session.** The cctrace link now
jumps straight to *this* session's conversation, scrolled to the newest
turn: `[http://localhost:9317/s/c3a6e0f3]` instead of the generic
`/trace` landing page. `/s/<sid8>` is cctrace's (>= 0.40) short session
jump — a redirect to `/trace#/session/<sid8>` — and the sid8 prefix is
the same join key the chip's registry match already uses, so the link
stays exact even when the server carries other sessions (a resume, a
deadman `-p` run). Sessions without an id (and older cctrace paths)
keep the `/trace` link; the bare `[cctrace]` chip is unchanged.

**New: deadman chip — the dead man's switch becomes visible.**
When [deadman](https://github.com/thevibeworks/deadman) has a switch armed
for the current session, a chip joins the left lane next to the path:
`[☠ armed 42m]` (dim) counting down to the auto-handoff, `[☠ warned 3m]`
(yellow) once the phone warning is out, `[☠ due]` when the fire is
imminent. The chip is a lifecycle fact about *this session*, so it lives
with path and branch, not in the quota cluster. Absence costs nothing:
one builtin `command -v` when the tool isn't installed, one fast file
read (`deadman chip <session_id>`) when it is, and an unarmed session
renders nothing at all. `--deadman off` (or `STATUSLINE_DEADMAN=off`)
disables it. The ☠ glyph (U+2620) stays in single-column text
presentation — no U+FE0F — so alignment math is unaffected.

- Tests: 321 -> 331 (chip states, color escalation, zero-cost absence,
  off mode, end-to-end render).


**State-dir contract v2: cooperating writers.** The state dir is now a
versioned consumer contract — external tools (ccpace, claudex) write
alongside the statusline instead of underneath it, and the model
context resolves through `last_logged_model` (bounded scan that skips
session markers and cooperating-writer `model:null` samples) instead
of trusting the last raw line of `usage.jsonl`.

**Trace chip renders the full URL.** `[cctrace:9317]` →
`[http://localhost:9317]`, linkified by most terminals;
`DEVA_TRACE_UI_URL` (exported by deva on traced create/reattach)
outranks the container-side port — only the host knows the published
port or the portless `https://cctrace.localhost` route.

**New: `week` subcommand.** The 7d period drawn as its own 5h windows,
one cell each (34 per period): `▁▂▃▄▅▆▇█` a window that ran, height =
the 7d points it burned; `·` ran but burned under 1%; `░` unknown, no
samples on record; `▮` the window you're in now; `▯` a window still
ahead; `×` a window the pool won't cover at the current pace. Count
`▮` and what follows for the budget line's own `~Nx5h left`, so the
picture and the sentence under it are the same number.

Past cells are reconstructed from `usage.jsonl` — a window keyed by
its 5h reset (rounded: the API jitters it by microseconds, and
`05:59:59`/`06:00:00` are one window), costed by the 7d movement
observed inside it. `░` and `·` are deliberately different glyphs: a
gap in the record is not an idle session, and drawing it as one is the
lie this row must not tell. A fresh install shows an honestly unknown
past that resolves as the store fills.

The prospective glance beside `report`'s retrospective ledger, and the
same strip claudex's `claude.py` draws — including the same wall,
which uses the learned forecast when trained and the linear projection
otherwise, so a wall visible on one surface is visible on the other.
Reads the state dir only; stale data renders but says so; no cache or
no active window exits 3 like `check`.

**Changed: the calm budget line speaks the shared budget frame.**
`- budget ~19x5h left · even 1.1%/win · heading ~52%` (was `- ~19x5h
left, even pace 1.1%/win, heading ~52%`): "budget" names the frame,
"pace" no longer does double duty (it means usage/elapsed everywhere
else), and in the last window — where per-window math just restates the
headroom — it degrades to `- budget last window · 61% left · heading
~40%`. Same frame and the same "heading" verb as claude.py's watch
advisor, so the two surfaces never phrase one state two ways.

## v0.23.0 — 2026-07-29 — the trace chip, and a second line that holds its edge

**New: cctrace trace chip.** A session whose wire is being captured by
[cctrace](https://github.com/thevibeworks/cctrace) (`deva --trace`, or
`cctrace` directly) now says so: `[cctrace:9317]` on the left, next to
path and branch — the port is the live trace UI on localhost. Session
identity, not pressure, so it's dim in the neutral lane. Detection takes
the strongest signal available: the trace env cctrace exports into the
traced process (`CCTRACE_SERVER_PORT`), the capture's CA plumbing
(`NODE_EXTRA_CA_CERTS` under a cctrace dir), or deva's `DEVA_TRACE=1`;
plumbing-only captures resolve the port through cctrace's live-instance
registry — by session id (sid8 prefix: the registry stores ids redacted
past the first 8 hex), then project path, then by being the only live
capture; the fallbacks trust heartbeat-fresh entries only, since crashed
runs leave "live" files behind. No resolvable port still shows a bare
`[cctrace]`: "recorded" matters even portless.

**Fixed: the advisor row right-aligns to line 1's actual edge.** The
statusline runs with stdout on a pipe, where `tput cols` answers a flat
80 no matter how wide the terminal is — line 1 overflowed the phantom
edge while the advisor anchored on it, leaving the advice dangling
mid-line under a much longer badge cluster. The advisor now anchors on
line 1's actual rendered width, so the second line's right edge meets
the first's whatever the width guess was. Width detection itself also
got honest: the controlling tty (`stty size </dev/tty`) and an inherited
`COLUMNS` both beat `tput`'s default. 348 tests (336 statusline + 12 installer).

## v0.22.0 — 2026-07-28 — the agent surface

**New: `skills/usage-insight` — teach Claude Code to read its own
usage.** Three layers, one source of truth: line 1 shows the numbers,
the advisor row says the one sentence that matters, and the skill
carries the full conversation — "should I start a heavy task now?",
"which account has headroom?", "what did I waste this week?". Install
with `cp -r skills/usage-insight ~/.claude/skills/` and ask.

The skill encodes the state-dir contract, the learned-forecast
semantics, and the advisor's judgment rules — feasibility before
advice, facts only while the ratio is unlearned, staleness said out
loud, fresh siblings only. It runs the same `report`/`check`
subcommands instead of re-mining, so all three layers always agree.
Docs-only release: no script changes, test count unchanged.

## v0.21.0 — 2026-07-28 — the advisor, wired into your world

**New: `statusline.sh check` — the advisor as an exit code.** The
statusline never runs when you're away, which is exactly when expiring
capacity needs a voice. Instead of a daemon (still no daemon, ever),
`check` prints the plain-text advisor verdict and exits 0 calm / 1
opportunity / 2 pressure / 3 unknown-or-stale — you wire it into tmux,
cron, or CI. We provide the judgment; the host provides the plumbing.
Model context for the scoped clauses comes from the last logged
snapshot — the first consumer of v0.20's widened `model` field.

**New: `statusline.sh session-summary` — one-line session
retrospectives.** Designed as a `SessionEnd` hook (reads the hook JSON
on stdin; falls back to the last logged session for manual runs):

```
session 8f3c02aa: 3h12m, 5h +34pts, 7d +4pts, claude-fable-5
```

Window deltas are positive-delta sums (the profile builder's rule), so
a session that straddles a 5h reset still reports what it actually
consumed. 334 tests (322 statusline + 12 installer).

## v0.20.0 — 2026-07-28 — the waste ledger: see what you paid for and didn't use

**New: `statusline.sh report [--days N]` — the waste ledger.** The
advisor (v0.19) prevents waste prospectively; this proves it
retroactively. It replays the usage log the statusline has been writing
all along, detects every window close (consecutive samples disagreeing
on `resets_at`, normalized to the minute — the ratio learner's identity
rule), and ledgers each closed 7d window as used% / expired%, converted
into 5h-windows-worth via the learned `pct_per_window` exchange rate:

```
7d windows closed: 1
  Tue 07-28 00:00  used 51%  expired 49% (~4.7 x 5h windows unused)
5h windows closed: 3   avg 95% at close   2 hit the cap
exchange rate: one full 5h window = ~10.46% of the week (~9.6 windows/week, learned)
week in progress: 5% used, resets Mon 08-03 23:59
```

"week in progress" runs the same learned walk the advisor's heading
uses — the surfaces cannot disagree. Honest limits are documented: the
final utilization is the last sample before a reset, so usage from other
clients after your last local render is invisible, and never-sampled
windows don't appear.

**Widened snapshots: log today what the learner needs next month.**
Every `usage` line in usage.jsonl now also records `limits[]` (scoped
per-model weekly caps, verbatim), `model` (the id active in the logging
session), and `predicted_end` — the learned walk's end-of-week
projection *at sample time*. That last one is the calibration seed: once
windows close, predictions can be scored against observed finals, and
the forecast's accuracy becomes measurable instead of assumed. Learning
lags logging by weeks; fields absent today are patterns that can't be
learned next month.

**Fixed: `catch .` gave every empty `resets_at` one shared fake window
identity.** jq's `catch .` yields the error *message*, not the original
input — so snapshots with an empty/unparseable `resets_at` all
normalized to the same error string and could pair across real windows
in the ratio learner, quietly skewing `pct_per_window` (observed on real
data: phantom window closes and a drifted ratio). Both norm sites now
fall back to the raw input string and treat empty as empty.

Mechanics: subcommands dispatch after all function definitions, take no
stdin, and are read-only against the state dir. 327 tests (315
statusline + 12 installer).

## v0.19.0 — 2026-07-28 — smart advisor line, claude-watch retired

**New: the advisor — a second statusline row that interprets the badges.**
Claude Code renders each stdout line as its own row, so the statusline
gains an optional advice line under the badges. Design rule: line 2
speaks only when the numbers on line 1 don't mean what they appear to
mean, and every clause derives from a badge already shown — no third
alarm channel. It cuts both ways: pressure (`! ...`, yellow/red — you'll
hit a wall) and opportunity (`+ ...`, cyan — paid capacity is about to
expire unused; cyan can never mean pressure, so the color alone carries
the stance). Quiet means no row at all (zero height cost when healthy),
and the row right-aligns to the stats anchor so the advice sits directly
beneath the badges it interprets.

- `! fb capped — back ~Thu 07:00` — the weekly limit scoped to this
  session's model (`limits[]` `weekly_scoped`) hit 100%: the model just
  went away; the useful fact is when it returns.
- `! 5h caps ~14:20, 52m before reset` — linear cap projection, only
  while the 5h badge is already yellow/red and relief isn't imminent. At
  100% it stays silent: line 1 already says capped.
- `+ 7d resets @07:00, 56% unused — spend it` (or `— ~40% expires even
  at full burn`) — expiring surplus: inside the last day of the 7d window
  with >= 30% unused, a green badge means forfeiture, not headroom. This
  is exactly the zone where pressure logic goes quiet (recovery) and
  where waste peaks; the old watcher said nothing while half a week's
  subscription evaporated. The tail is feasibility-checked against the
  learned pct_per_window ratio: "spend it" only when full-tilt burn can
  actually consume the surplus, the honest expiry number once it can't,
  and no tail at all while the ratio is unlearned — never advice the
  data can't back.
- `+ alt 5h[8%] free` — fleet relief for shared-home multi-account
  setups (deva): at 5h >= 90%, the idlest fresh sibling under
  `accounts/*/` is named. Pure cache read, no credentials. Now voiced as
  opportunity (cyan), not alarm — line 1 already screams about the cap.
- `! fb caps ~Wed 18:00, 1d before reset` — the running model's scoped
  weekly quota caps before its reset; same math and gates as the 7d
  aggregate.
- `! 7d dry ~Thu 09:00, 2d before reset — then extra billing` (or
  `then hard stop`) — the learned weekday forecast's dry point, falling
  back to linear pace on cold start once `seven_day_pace` warns. The tail
  states what actually happens at the cap.
- `+ 7d on pace to leave ~62% unused — go heavier` — underuse: on pace
  to strand a large chunk of the subscription. The learned weekday
  profile speaks first — it knows YOUR remaining days, so it can warn
  from day two; cold start falls back to linear pace past half the
  window. Speaks only in an engaged, unsqueezed session (5h in
  [25%, 80%), no pressure clause), so it reaches exactly the person who
  can act on it and never nags an idle one.
- `- ~19x5h left, even pace 1.1%/win, heading ~52%` — `--advisor always`
  adds the weekly budget when calm; "heading" is the learned end-of-week
  projection when trained, linear once the window is a day old.

Max two clauses per row, in value order; the 7d window gets one voice per
render (surplus, dry, or underuse — never two that could disagree).
Modes: `--advisor auto` (default) | `always` | `off`. Themes `minimal`
and `manager` set `off`. All times wall-clock or future-to-future gaps —
freeze-safe in an idle frame. Pair with `"refreshInterval": 60` in the
`statusLine` settings to re-evaluate on a timer while idle.

**New: the forecaster learns the 5h↔7d exchange rate.**
`build_seven_day_profile` now also mines `usage.jsonl` for
`pct_per_window` — how many 7d percentage points a fully burned 5h
window costs this account — from paired samples inside the same 5h
window (`resets_at` identity guards against pairing across a reset).
That single learned ratio is the physics that converts "windows left"
into "weekly % actually spendable", and it is what lets the advisor
refuse to say "spend it" when only one window remains against half a
week of surplus. The weekday walk itself is now a shared
`_seven_day_walk` that reports both the dry gap and the projected
end-of-week utilization; the dry forecast, the underuse clause, and the
always-mode "heading" all read the same simulation, so no two surfaces
can disagree about the same future.

**Fix: account resolution no longer misses pre-v0.18-deva containers.**
Containers created before deva exported `DEVA_AUTH_TAG` carry only
`DEVA_AUTH_DETAILS` (`credentials-file (/path/<stem>.credentials.json)`);
those sessions silently fell back to the DEFAULT account's caches —
rendering another account's label and quota, the exact bug scoping exists
to kill. The tag now derives from the details string's file stem, so
long-running containers get correct identity without recreation. Also
hardened the fleet hint against a corrupt sibling cache leaking the
previous sibling's numbers onto the wrong tag.

**Retired: `claude-watch.sh`.** Its transcript cost view belongs to ccx;
its quota footer is superseded by the advisor row. Standalone watching
(multi-account polling, notifications) lives in claudex's
`claude.py --watch-usage`, which consumes this repo's state dir — now
documented as a contract in `docs/api/state-dir.md`. `install.sh` removes
a previously installed copy.

## v0.18.0 — 2026-07-27 — freeze-safe cache expiry, account identity, 7d hybrid reset

**New: account identity for multi-account credential overlays.** One
`~/.claude` used to imply one account; deva-style runners broke that by
bind-mounting a different `.credentials.json` per container over the same
shared config home. The "account-scoped" caches (`usage.cache`,
`profile.cache`, `usage.jsonl`) then bled across accounts: B rendered A's
5h/7d bars whenever A fetched last, and the profile stuck to whichever
account fetched first for 24h. The credentials file itself carries no
stable identity (tokens rotate), so the runner must say who the session
is: `STATUSLINE_ACCOUNT` (explicit) or `DEVA_AUTH_TAG` (set by deva from
`--auth-with`). When present, the user segment shows an `@tag` chip
(`[MAX|@work]`, tag beats the profile display name — two accounts can
carry the same human name) and account state moves to
`accounts/<tag>/` under the shared statusline dir: same-account sessions
still share one fetch, different accounts stop clobbering each other.
`auth-default` (single-account) changes nothing; an explicit
`CLAUDE_DATA_DIR`/`CLAUDE_CACHE_DIR` override is respected verbatim; tags
are sanitized to a filesystem-safe charset before touching a path. The
chip also renders for API-key/custom-endpoint sessions, which skip the
OAuth quota block — exactly the sessions only a tag can tell apart.

**Fix: the ≡ cache badge no longer disappears next to the bright context
bar.** An all-dim badge was invisible in real use; the glyph now keeps
full weight (yellow while building, white for the `--cache always`
deadline) with only the trailing meta dim.

**Fix: the 7d pressure suffix no longer decays in a frozen frame.** The
badge kept a relative countdown (`@6h`, `@<1h`) inside the last day —
the same decaying-countdown mistake the 5h badge fixed twice (v0.6,
v0.11), and it showed only under pressure, i.e. exactly when a stale
`@<1h` convinces you you're still capped after relief already arrived.
Now hybrid: day-relative `@Nd` while >= 24h out (decays one day per day;
mild, and the narrowest honest form), wall-clock `@04:00` inside the last
day — the 5h badge's idiom, unambiguous under 24h via next-occurrence
reading, and true no matter how stale the frame is. Zero width cost.
(Resolves the open decision in
docs/devlog/2026-07-15-statusline-refresh-mechanism.org.)

**New: prompt-cache expiry warning that survives an idle gap — "quiet until
it bites".** Claude Code re-renders the statusline only on activity (mount,
new assistant message, mode/model change — no timer; see
docs/devlog/2026-07-15-statusline-refresh-mechanism.org), so nothing can
appear *during* the idle gap where the cache actually dies. And while active
the cache is always freshly ~1 TTL from expiry, so there is no honest
"expiring soon" to render. So `auto` stays silent while healthy — no width
on a deadline that's always ~an hour out — and speaks only when a rewrite
actually happened:

- **`≡!419k` on resume**: the first post-idle render sees activity after
  a gap longer than the TTL and reports the rewrite, sized at the re-cached
  prefix (observed live: 68min idle -> `read=0 write=87869`, the full
  context re-cached at ~20x the read rate; on subscriptions it burns 5h/7d
  quota too). **Bold red past 200k** — the premium-band miss. Fires even
  when the 300ms render debounce skipped the `read=0` turn, because the
  detector keys off the stale activity anchor, not the one-frame collapse.
  Held 60s wall-clock so a busy turn's refresh doesn't erase it.
- **Anchor-slide fix**: the activity anchor re-stamps only when the usage
  numbers change. Renders also fire on vim/permission/model changes carrying
  the previous turn's usage; re-stamping there slid the anchor forward and a
  frozen frame would claim a warm cache after it died.
- **`--cache always` keeps the freeze-safe deadline** `≡@15:20` (last
  request + TTL) for anyone who wants to read "resume or start fresh?" from
  the frozen frame before typing. Wall-clock, never a countdown.
- **TTL default matches how the CLI actually caches** (from CC source +
  live traces): claude.ai subscriber REPL sessions get `ttl:"1h"` on every
  breakpoint; API-key / custom-endpoint auth stays on the stock 5m cache.
  `FORCE_PROMPT_CACHING_5M` / `ENABLE_PROMPT_CACHING_1H` honored. An
  observed `ephemeral_1h/5m` breakdown overrides and renders its class as
  provenance (`≡:5m@14:25`); the CLI does not forward the breakdown
  today. Known gap: subscriber sessions bootstrapped on overage latch 5m
  server-side — invisible here; `≡!Nk` still reports the miss.

22 new tests (287 total).

## v0.17.0 — 2026-07-13 — mitm proxy trust, diagnosable !net, unified +X flash

**Fix: every API fetch died behind a trusted mitm proxy (persistent `!net`).**
When the CLI runs under a TLS-inspecting proxy it trusts (cctrace, corporate
inspection), the statusline inherits `HTTPS_PROXY` but curl does not honor
`NODE_EXTRA_CA_CERTS` (Node-only, additive) — every fetch failed instantly
with an SSL verify error (HTTP 000), while the CLI kept working. Observed
live: 19 consecutive failures, quota frozen for 11 hours behind `!net`.

- New `curl_ca_bundle`: splices the extra cert onto a copy of the system CA
  bundle (curl has no additive flag) and passes it via `--cacert` on all
  four outbound requests (usage, profile, prepaid, OAuth refresh).
- `!net` is now diagnosable: curl's own error text (`%{errormsg}`) is logged
  and recorded in the err file — `cat usage.err` says *why* (SSL, DNS,
  refused), not just `code 000`.

**Request-header parity with the CLI.** All OAuth API calls now mirror
claude-cli exactly (verified against a v2.1.207 capture): UA
`claude-cli/<version> (external, cli)` with the version of the running CLI,
plus `anthropic-beta: oauth-2025-04-20`, `Accept`, `Accept-Encoding:
identity`. `docs/api/oauth-usage.md` re-synced to v2.1.207 (no schema change
since 2.1.201) and now documents the mitm transport pitfall.

**New: unified +X change flash.** The reverse-video flash the 5h/7d badges
already had is now a generic mechanism (`delta_flash`, one state file per
session) wired into more components — each flashes its change for 60s after
a refresh alters it:

- cost: `$7.90+.37` (cents-precise, dollars shown when the jump is >= $1)
- context: `[█░░░░░30%]+9`, and `[░░░░░░3%]-27` right after /compact —
  the drop is the point
- model-scoped quota: `fb[69%]+2`

**Test hygiene: `STATUSLINE_NO_FETCH`.** Integration tests isolate the cache
dirs but `$HOME` (and so real credentials) leaks through — once the SSL fix
landed, a bare cache dir made tests fire *real* API fetches whose background
writes raced teardown (`rm -rf: Directory not empty`, flaky ~1/8). The test
harness now exports `STATUSLINE_NO_FETCH=1`, honored by the script's main
flow: render purely from cache/stdin, never spawn a network fetch. Also
useful standalone for air-gapped/offline setups.

11 new tests (265 total).

## v0.16.0 — 2026-07-06 — atomic fetch locks (multi-instance 429 stampede)

Launching several Claude Code instances together produced 429 bursts. Two
compounding causes, confirmed against a mitm capture of CLI v2.1.201:

1. **Each CLI instance already fires 2 usage requests on boot** (two internal
   clients: `claude-cli/... (external, cli)` and `claude-code/...`). N
   instances = 2N requests before any statusline fetch.
2. **The statusline's lock was check-then-touch, not atomic** — and the
   `touch` happened *after* `get_oauth_token`, hundreds of ms after the
   check. Every freshly launched instance passed the check inside that
   window and fetched concurrently, adding up to N more requests to the
   same burst.

The statusline can only fix its own share:

- New `acquire_lock`: noclobber (`set -C`) create — atomic acquire-or-fail,
  with stale-lock reaping (orphaned locks from crashed fetchers).
- Lock is acquired **before** the token read in `fetch_usage_for_session`
  and `fetch_prepaid_balance`; released on every early-return path.
- `refresh_oauth_credentials_file` uses it too: two concurrent OAuth
  refreshes are worse than a missed one — with rotating refresh tokens the
  loser's grant can invalidate the winner's.
- Regression test: 8 concurrent fetches with a deliberately slow token read
  make exactly 1 API call (fails on the old code). Plus a 20-contender
  single-winner lock test.

New: `docs/api/oauth-usage.md` — the observed `/api/oauth/usage` wire
contract (request headers, both CLI client forms, full response schema,
`limits[]` semantics, 429 obligations), synced with Claude Code v2.1.201.
Sanitized; no credentials or account identifiers.

5 new tests (254 total).

## v0.15.1 — 2026-07-05 — scoped quota badge moves next to the model

`fb[67%]` now renders right after the model+context block instead of at the
tail of the 5h/7d cluster:

```
260128_ccreverse-up +131/-16 $10.53 fabl5[1m][█░░░░░12%] fb[67%] [MAX|you] 5h[95%@23:00] 7d[55%]
```

The scoped quota is a property of the model the session is running — the eye
looks for it where the model is, not in the account-wide quota cluster. It is
still a weekly number (same reset as the 7d badge), just scoped to one model.

- Extracted into `build_scoped_quota_display`; `build_usage_display` keeps
  only the legacy-field suppression check.
- Test count: 249.

## v0.15.0 — 2026-07-05 — model-scoped weekly quota (`fb[65%]`)

The usage API moved per-model weekly limits out of dedicated fields
(`seven_day_opus` / `seven_day_sonnet` — both now arrive null) into a generic
`limits[]` array: `kind=weekly_scoped` entries carrying
`scope.model.display_name`. The old `op`/`sn` badges silently died with that
contract change; this release reads the new shape.

- Parse `limits[]` weekly_scoped entries generically — any model family the
  API scopes a weekly limit to, current or future (Fable 5 being the one that
  surfaced the change).
- Render only the scope matching the model **this session** is running:
  `fb[65%]` on a Fable 5 session, `op[33%]` on Opus. Other models' scoped
  quotas stay hidden — the limit that constrains the session is signal, the
  rest is noise.
- Badge labels follow the existing `op`/`sn` convention: `fb` (fable), `hk`
  (haiku); unknown families degrade to their first two letters rather than
  hiding the quota behind an unmapped name.
- Legacy `seven_day_opus`/`seven_day_sonnet` rendering is kept for old cached
  responses but skipped whenever scoped limits exist (the new contract
  supersedes it).
- `build_usage_display` gains the session model as an optional 4th argument;
  both call sites pass stdin's `model.id`.

6 new tests (248 total).

## v0.14.0 — 2026-07-02 — 5h reset back to wall-clock (@14:30)

v0.11.0 re-made a mistake v0.7.0 had already fixed and documented: it turned
the 5h reset into a relative countdown (`@1h38m`). The statusline only
re-renders on activity, so a countdown rendered 30 minutes before you look at
it overstates the wait by 30 minutes — and idle is exactly when no re-render
comes to correct it.

The v0.11.0 rationale ("everything in a frozen frame is equally stale")
missed the asymmetry: cost, context %, and usage % are **"as of" facts** —
they only change with activity, and activity triggers a re-render, so a stale
frame still reads truthfully as "the state when I stepped away." A countdown
is a **"from now" claim** whose truth decays with wall-clock time at zero
activity. Wall-clock `@14:30` is the only format that stays true in a frozen
frame.

The decay rule for what a non-realtime statusline may display: a quantity is
safe if it changes only with activity, or decays slower than a plausible idle
gap. Minute-scale countdowns on a 5h window fail; the 7d badge's `@5d` passes
(day granularity) and stays relative.

### Changed

- **5h reset time is wall-clock again**: `5h[42%@14:30]`, local TZ, `@now`
  when past. Restored `format_reset_absolute` (lean version — the old `day`
  mode stays gone; the 7d badge no longer uses day names).
- v0.11.0's *always-visible* half survives: the reset time still shows on
  every live window, not just under pressure. Only the format reverted.

242 tests (4 restored), shellcheck baseline unchanged.

## v0.13.0 — 2026-07-02 — escalating fetch cooldown + categorized !badges

Live logs showed 23% of usage fetches failing 429 in clusters exactly one
backoff apart: the fixed 120s cooldown expired and retried straight into a
still-throttled window. Cross-checked against the 2.1.197 binary: the
endpoint contract is unchanged and the CLI's own `fetchUtilization` has no
429 handling either (its only retry is 401→refresh→retry) — the CLI and every
concurrent statusline render share one per-account throttle bucket, so the
client must pace itself.

### Added

- **Escalating error cooldown**: consecutive fetch failures back off
  120s → 240s → 480s → 600s (cap) instead of a fixed 120s. The err state
  survives until a fetch succeeds, so the escalation compounds; success
  clears it. Applies to both the usage and prepaid fetch paths.
- **`Retry-After` honored**: failures now capture the header via curl's
  `%header{retry-after}` (>= 7.83; older curls degrade cleanly) and the
  cooldown extends to match when the server asks for longer. Failure logs
  now include the header, consecutive-failure count, and computed cooldown.
- **Categorized stale-data indicator**: the bare `!` after quota/extra now
  says why: `!429` rate limited, `!auth` token rejected (401/403), `!5xx`
  server error, `!net` connection failed. Legacy bare-epoch err files still
  render plain `!`.
- err files are now JSON (`{at, code, count, cooldown}`); pre-v0.13.0
  bare-epoch files are read compatibly (fixed 120s window, bare `!`).

### Changed

- **Bump flash glyph: `▲` → `+`** (the Unicode triangle renders poorly in
  some terminal fonts), still reverse-video, and now bound tight to its
  badge — `5h[44%@1h18m]+2` — so it can't visually float toward the next
  badge.

226 tests (8 new), shellcheck baseline reduced by one.

## v0.12.1 — 2026-07-02 — bump flash: reverse-video ▲N outside brackets

### Changed

- **Bump flash visual**: the quota-climb indicator moved from bold `+N`
  inside the badge to a **reverse-video `▲N`** outside the brackets:
  `5h[44%@1h18m] ▲2` / `7d[10%] ▲1`. Spatially distinct + reverse video
  (inverted bg/fg) makes it unmissable without adding a fourth color lane.
  Bold-only was too subtle in most terminals, and cramming `+N` between
  `%` and `@` inside the brackets made it read as noise.
- `REVERSE`/`NO_REVERSE` (`ESC[7m`/`ESC[27m`) replaces `BOLD`/`NO_BOLD`.

218 tests, shellcheck warning count unchanged.

## v0.12.0 — 2026-07-02 — quota bump flash (▲N when 5h/7d usage climbs)

### Added

- **Bump flash**: when the 5h or 7d utilization climbs between renders, a
  reverse-video `▲N` glyph appears outside the badge for ~60s:
  `5h[44%@1h18m] ▲2` / `7d[10%] ▲1` — "you just burned 2%". Vivid without
  a new hue, so the three color lanes stay unambiguous.
- `quota_bump_notice()` + per-session state file
  (`sessions/<session_id>_quota_seen`, same lifecycle as `_cache_health`).
  Per-session on purpose: the flash compares against what THIS statusline
  last rendered, so concurrent sessions each get their own notice instead
  of racing over shared account state.
- Semantics: first sighting is quiet; a climb records the increment; an
  unchanged value keeps a still-fresh notice alive; a second climb
  overwrites (latest increment, not a running sum — "▲N" answers "what just
  happened"); a drop (window reset) clears silently, the fresh low number
  being its own signal.
- `QUOTA_BUMP_NOTICE_SECS` (60) constant.

### Fixed

- Test helpers still defined the countdown constants and extracted
  `format_reset_absolute` — both removed in v0.11.0; cleaned up.

218 tests (9 new), shellcheck warning count unchanged.

## v0.11.0 — 2026-07-02 — always-on 5h countdown + post-compact bar reset

Two changes driven by live use: "how long until my 5h window resets" was
hidden until pressure, and `/compact` made the context bar vanish instead of
visibly resetting.

### Changed

- **5h badge always shows its window countdown while a window is live**:
  `5h[42%@1h20m]` — no more gating on usage >= 80% or reset <= 2h. On a 5h
  horizon the time remaining is the number you plan the current sitting
  around, so hiding it until pressure hid the badge's most useful signal.
- **5h countdown is relative (`@1h20m`), not wall-clock (`@14:30`)** — this
  deliberately reverses the v0.5-era "absolute stays true without re-renders"
  decision. Three reasons: (1) remaining time is the actual question; a wall
  clock makes you do the subtraction. (2) The 7d badge already went relative
  (`@5d`) when the pace model landed — 5h absolute was the leftover
  inconsistency, and one `@remaining` language beats two. (3) The staleness
  argument proves too much: when the CLI stops invoking the statusline, the
  usage %, cost, and context bar in the same frame are equally stale — a
  wall-clock reset time being technically true doesn't make a frozen frame
  fresh. During active use, renders arrive seconds apart.
- **A real stdin 0% renders an empty context bar** (`[░░░░░░0%]`) instead of
  nothing. Observed live: after `/compact` the CLI pushes
  `used_percentage: 0` for the reset window, and hiding the bar at zero read
  as "the statusline didn't refresh" — the visible snap to empty IS the
  refresh. Absent data (no `context_window`, no transcript) still renders no
  bar; only a genuine zero shows one.

### Removed

- `format_reset_absolute()` and its 6 unit tests (the 5h badge was its last
  caller), plus the now-dead `FIVE_HOUR_COUNTDOWN_SECS` /
  `SEVEN_DAY_COUNTDOWN_SECS` gating constants.

Note on the freeze *during* compaction: the CLI simply does not invoke the
statusline while compacting (~90s observed), and a statusline script is a pure
function of its stdin — the first post-compact payload now visibly resets the
bar, which is everything script-side can do.

209 tests (3 new), shellcheck-clean at the same baseline as v0.10.2.

## v0.10.2 — 2026-06-12 — fix false [1m] tags from misread exceeds_200k_tokens

A systematic audit of the live debug log (857 real turns across two rotated
log files) found `exceeds_200k_tokens` was being misread since the v0.9.1 1M
detection rework. It does not mean "this window is bigger than 200k" — it
means "this session's cumulative token usage has passed 200k so far." On a
genuine 200k-window model (`claude-opus-4-6`, no `[1m]` suffix), once a long
session's total usage crosses 200k, the CLI reports the flag `true` too —
`total_input_tokens > 200000` predicted the flag in 839/840 sampled turns;
`context_window_size > 200000` predicted it in only 719/840. Treating it as a
window-size signal put a false `[1m]` tag on **~14% of observed renders**
(121/857) — every long-running session on a real 200k model.

### Fixed

- **`is_1m_model`**: dropped the `exceeds_200k_tokens` fallback tier entirely.
  `context_window_size` (`ctx_size`) is reported on every sampled turn and is
  the actual ground truth for window capacity; the `[1m]` suffix / default-1M
  family check remains as the fallback for older CLIs that omit `ctx_size`.
- **`premium_band_level`**: same fix — the flag no longer forces the yellow
  band on a low-usage 1M session or a real 200k session. Band is now purely
  `context_pct x ctx_size` against the 200k/800k thresholds.

212 tests (6 new), shellcheck clean.

## v0.10.1 — 2026-06-12 — Claude Sonnet 5 support

Claude Code 2.1.197 shipped Claude Sonnet 5, and it broke the statusline the
same way Fable 5 did back in v0.9.1 — plus a new one.

### Fixed

- **`sonnet5.5[1m]` instead of `sonnet5[1m]` (critical, live-broken).**
  `abbreviate_model_id` assumed every `claude-opus-*`/`claude-sonnet-*`/
  `claude-haiku-*` ID has a major.minor version pair (`opus-4-8` -> `opus4.8`).
  Sonnet 5 uses flat versioning (`claude-sonnet-5`, no minor component), so the
  minor-extraction fallback re-read the major digit as the minor and doubled
  it: `sonnet` + `5` + `.` + `5`. Fixed by checking whether the id has a second
  version component before appending one.
- **1M context not detected for suffix-less Sonnet 5.** Same pattern as Fable
  5 in v0.9.1: Claude Code 2.1.197 omits the `[1m]` suffix for Sonnet 5 because
  1M is now its default (confirmed live: `context_window_size:1000000`,
  `exceeds_200k_tokens:true`, `model.id:"claude-sonnet-5"`, no suffix).
  `is_default_1m_family` only matched `fable`; added `sonnet-5` by exact major
  version so `sonnet-4-6`/`sonnet-4-5` correctly stay opt-in.

206 tests (5 new), shellcheck clean.

## v0.10.0 — 2026-06-12 — learned 7d forecast + premium band in the bar

The original initiative, delivered: the statusline watches your 7d usage with
a model of YOUR week — learned from your own history, not assumed — and warns
when you'll run out of usage while days still remain in the window.

### Added

- **Learned weekday burn profile.** `build_seven_day_profile` (hourly, inside
  the TTL-gated fetch path) scans `usage.jsonl` and writes `forecast.cache`:
  per-weekday %/day (EWMA, 14-day half-life) plus recent 24h/48h burn.
  Partitioned by account uuid — interleaved multi-account history produces
  garbage rates otherwise. Plan upgrades fade out via the EWMA. Pure epoch/awk
  arithmetic, no GNU date extensions; 195 days of history builds in ~0.2s.
- **Forecast verdict.** `seven_day_forecast` walks the remaining window
  day-by-day against the profile (first 24h burns at max(profile, recent-24h))
  and flags when quota dries before reset: yellow, red when dry >= 2 days
  early. Escalates the pace color — it knows your heavy Tuesday is still
  ahead when the window-average looks calm. Cold start (< 14 days of history)
  falls back to window-average pacing silently.
- **`claude-watch.sh` forecast line**: projected dry day + the learned
  profile: `forecast dry ~Mo (2.4d before reset)  profile/d Mo12 Tu16 ...`.
- **`usage.jsonl` rotation** at 32 MiB (single `.1` backup; the profile
  builder reads both, so rotation never costs learned history).

### Changed

- **Premium pricing band moved into the context bar.** `fabl5[1m:320k]` was
  redundant — 320k IS the bar's 32%. The model tag is a constant `[1m]`; the
  bar color now carries the band: yellow past 200k, red past 800k.
- **7d reset shows explicit time remaining** — `@5d` / `@18h` (timezone-proof,
  unlike a day name) — whenever the verdict warns, even with the reset days
  away. "Abnormal burn" is exactly when you need to know how long the window
  still has to run.

## v0.9.6 — 2026-06-12 — pace verdict is color-only (no runway text)

Two attempts at a compact runway number (`~2d`, then `2d!`) were both misread
as "days until reset" — a second time-unit sitting next to a 7-day metric
cannot win, no matter the label. The derived number is gone.

### Changed

- **7d badge shows no runway text.** The pace verdict (will the quota outlast
  the window?) is carried by color alone; under pressure the `@reset` deadline
  appears — a fact, not a model: `7d[40%]` yellow (early overshoot), `7d[70%]`
  green (late, safe), `7d[95%@Mon]` red. The pace engine (`seven_day_pace`) is
  unchanged underneath, including `CLAUDE_7D_WORKDAYS`.

### Notes

- Reset times render in the local timezone of wherever the statusline runs.
  If your containers run in a different TZ than your other monitors, set `TZ`
  in the container for matching `@day` labels.

## v0.9.5 — 2026-06-12 — readable runway warning (Nd!)

`~2d` confused its own audience: it mixed two time quantities (quota-runway vs
reset-deadline) into one unlabeled number inside a `%` badge — "2 days until
what?". Reworked for legibility.

### Changed

- **Runway hint is now `Nd!`**, space-separated from the percentage:
  `7d[37% 2d!]` = ~2 days of quota left at the current burn rate. The `!` marks
  it as a warning rather than a neutral stat; the space keeps it from reading
  as part of the percentage. Still shown only under pace pressure — on-pace
  badges stay a bare `7d[27%]`.
- **Fable identity color → bright red (`0;91`)**, matching Fable's color in the
  Claude Code TUI (was bright magenta). Pressure red stays `0;31`, so alarms
  remain distinguishable. `claude-watch.sh` and the hero preview follow.

## v0.9.4 — 2026-06-12 — window-aware quota merge (multi-session freshness)

With several Claude Code instances running, the 5h/7d numbers lagged: an idle
session's stdin can carry a rate-limit window that already reset hours ago,
and the old merge let stdin clobber the shared cache unconditionally — even
when another session's fetch had just written fresher data. Observed live: one
session's stdin said 5h=33% on an expired window while the shared cache held
47% on the current window, fetched two minutes earlier.

### Fixed

- **Window-aware merge.** Neither stdin nor the cache is always fresher, and
  stdin carries no timestamp — but two structural facts decide it without one:
  across windows the later `resets_at` IS the newer window; within one window
  utilization only increases. Per window: newer `resets_at` wins outright;
  same window takes the max utilization. Stale stdin can no longer mask
  fresher cross-session data, and a frozen cache still self-heals (its
  `resets_at` falls behind stdin's).

### Notes

- Context (`NN%` / `[1m:NNNk]`) is per-session by design — it comes from that
  session's own stdin, never from shared state, so concurrent instances cannot
  pollute each other's context display.

## v0.9.3 — 2026-06-11 — show the model that's actually running (critical)

The displayed model came from `settings.json .model` (a static default) and
only fell back to the stdin `model.id` when settings had none. So a session
running Opus 4.6 while `settings.json` defaulted to `claude-fable-5[1m]` rendered
`fabl5` — the wrong model — and worse, the **name and the context window came
from different sources**: `fabl5` (settings) sat on top of a 200k/Opus context
(stdin). On a 200k model mislabeled as 1M-default Fable, the context felt
roomier than it was and the session hit the limit by surprise.

### Fixed

- **The displayed model is now the one the session is actually running**, read
  from the stdin `model.id` — the same source as the context window, so the name
  and the window can never disagree. A session that switches models mid-flight
  (`/model`, `--model`) is tracked correctly every render.
- **`settings.json .model` is now a fallback only** — consulted (and even read)
  solely when stdin carries no model id. It can no longer shadow the running
  model.
- The stdin model path now uses the full-strength identity color (e.g. `0;95`
  magenta for fable) instead of the old dim variant, matching the documented
  look.

### Notes

- The `opusplan` settings shorthand only renders via the fallback now; with a
  real `model.id` on stdin the badge shows the model actually in use, which is
  more accurate per render.

## v0.9.2 — 2026-06-11 — 7d quota paced, not leveled

The weekly quota color used a pure level threshold (yellow at 70%, red at 85%),
which is wrong in both directions: 70% on day 6 is a false alarm (you'll easily
make it), and 40% on day 1 is a real danger shown as calm green. The 7d badge
now judges **pace** — will the quota outlast the window? — using two numbers
already on stdin: `used_percentage` and `resets_at`.

### Added

- **Pace-aware 7d color.** Compares runway (quota-time left at the current burn)
  against the time until reset. A 10% buffer keeps marginal overshoots quiet, so
  the badge warns only when you'll genuinely fall short. Fixes the false-alarm
  (high-but-late) and missed-warning (moderate-but-early) cases.
- **Runway hint** `~Nd` — days of quota left at this burn rate — shown beside the
  percentage under pace pressure: `7d[40%~3d]`, `7d[95%~0d@Mon]`.
- **`@reset` gating tied to pressure**, not a fixed 70% level — it appears when
  the pace warns or usage is already high, and the reset is within 3d. On-pace
  usage stays a bare `7d[27%]`, no clock noise.
- **`CLAUDE_7D_WORKDAYS`** (opt-in, default off) — skips weekend days in the
  deadline so the meter doesn't alarm over Sat/Sun you won't spend quota on. The
  limit itself stays calendar-based; this only adjusts the planning view, and
  only changes the verdict in the borderline band where it's decision-relevant.

### Notes

- Early-window guard: pace isn't judged in the first ~8h (a single opening burst
  would otherwise read as a runaway); the badge falls back to level there.
- The opus/sonnet sub-quotas (`op`/`sn`) remain level-based — they're secondary.

## v0.9.1 — 2026-06-11 — authoritative 1M detection

Claude Code 2.1.173 stopped appending the `[1m]` suffix whenever 1M is the
active default. Real session logs show this on **both** Fable 5 and Opus 4.8
(`exceeds_200k=true` at ~24% context proves a >200k window with no suffix in the
id). Our `[1m]` detection keyed on the suffix, so those sessions lost their tag
*and* their premium-band cost cue, and the context bar measured against 200k
instead of 1M.

### Fixed

- **`[1m]` tag + premium cue restored for suffix-less 1M sessions.** Detection
  now prefers the CLI's authoritative signals over the model name, in order:
  1. `context_window_size > 200k` — the window the CLI itself reports.
  2. `exceeds_200k_tokens=true` — only a >200k window can exceed 200k tokens.
  3. `[1m]` opt-in suffix, or a family that defaults to 1M (`is_default_1m_family`
     — fable) — name fallbacks for older CLIs that send neither of the above.
- **`opus4.6[1m]` opt-in** unchanged — the suffix path still drives the tag and
  the 1M window (verified by a dedicated compat test).
- **`get_context_limit`** (transcript fallback for pre-`ctx_pct` CLIs) also
  treats a 1M-default family as 1M, so the fallback bar matches.

### Changed

- **Premium-band trigger** prefers the authoritative `exceeds_200k_tokens` flag
  over our own `context% × size` arithmetic. When the flag fires but the
  computed number doesn't itself clear 200k (e.g. exactly 20% of 1M, the common
  boundary case), the cue degrades to `[1m:200k+]` rather than printing a
  contradictory sub-200k figure.

## v0.9.0 — 2026-06-10 — color system (three lanes)

A deliberate palette redesign so a glance is unambiguous. Color follows three
lanes:

- **Status** (green/yellow/red) = pressure ONLY — quota, context, cache, the
  premium context band, expensive effort. Warm color always means "near a limit
  or cost."
- **Identity** (magenta/cyan/blue) = model family only.
- **Neutral** (grey/white by weight) = structure & you.

### Changed

- **Cost** moved off yellow → neutral grey (it's info, not a warning).
- **Path** → neutral grey (was cyan, which collided with sonnet).
- **Dirty branch** → bright white + `*` (was yellow); clean branch dim.
- **Tier** → neutral white-weight: MAX bold white, PRO white, ENT/TEAM dim. (MAX
  was green — collided with "quota healthy"; PRO was cyan — collided with sonnet.)
- **Haiku** → bright blue (was a hard-to-read dark blue).
- **Premium context cue** escalates with depth: `[1m:300k]` yellow past 200k,
  `[1m:900k]` red past 800k.
- `claude-watch.sh` model colors aligned (haiku → blue; opus/fable/sonnet match
  the statusline).

Net: yellow used to mean six things (dirty · cost · premium · max-effort · 5h ·
7d). Now warm color means pressure, full stop.

## v0.8.1 — 2026-06-10 — quieter effort badge

- Effort badge is now **lowercase** — `lo` / `md` / `xh` / `max` / `ultra` /
  `auto` instead of `L`/`M`/`XH`/`MAX`/`ULTRA`/`AUTO`. It's secondary metadata
  that renders on every line (especially for `xhigh` users, where it was
  effectively always-on), so it should stay quiet. Color still carries the
  weight: routine levels are dim; the expensive modes (`max`, `ultracode`) keep
  the pressure color. `high` remains the hidden default.

## v0.8.0 — 2026-06-10 — Shared Account Cache, fabl5, claude-watch, quota freshness

Tested against Claude Code CLI v2.1.170 (MAX and PRO accounts), Fable 5, and
the 20x Max plan.

### Quota freshness — the "5h stuck at 100%" fix

The 5h/7d number could stay frozen (e.g. stuck at 100% after a plan upgrade or
a window reset) even though the account was no longer rate-limited.

- **Prefer the CLI's stdin `rate_limits` for 5h/7d.** Claude Code passes
  current-plan, current-window quota numbers in stdin on every render. We now
  overlay those onto the cached usage data, so the displayed 5h/7d are always
  fresh and zero-cost. This self-heals plan upgrades (utilization is relative to
  the plan limit), window resets, and a stale/frozen cache. `extra_usage` and
  per-model 7d breakdowns (not in stdin) still come from the cache. New
  `merge_stdin_rate_limits()`.
- **Reap stale fetch locks.** The fetch gate skipped launching while a `*.lock`
  existed but never reaped it, so one orphaned lock (from a fetch that died
  mid-flight) could freeze the cache indefinitely. New `reap_stale_lock()`.
- **7d reset shown only near the cap.** A reset time is irrelevant at low usage,
  and a bare clock on a 7-day metric (`7d[1%@09:00]`) was confusing — the
  `@time` now appears only at >=70% utilization.

### Model display — fabl5, premium-band cue, effort badge

- `claude-fable-5` abbreviates to **`fabl5`** (4-char family + version).
- **`[1m:NNNk]`** — on a 1M-context model, once you pass 200k tokens (the
  premium input-pricing band) the tag shows absolute context in a warning
  color, e.g. `fabl5[1m:300k]`. Below 200k it stays `[1m]`.
- **Effort badge** — `low/medium/xhigh/max/ultracode/auto` render as compact
  `L/M/XH/MAX/ULTRA/AUTO` (`high` is the default and stays hidden). The
  expensive modes (`MAX`, `ULTRA`) use a warning color; the rest stay dim.

### Robustness & security

- **macOS portability**: every reset/countdown path now falls back from GNU
  `date -d` to BSD `date -j`/`-r`, so these no longer silently vanish on macOS.
- **Clean degradation**: empty/malformed stdin no longer prints fabricated
  `+/- 0m $0` — activity/time/cost are gated numerically, and sub-cent costs are
  no longer shown as `$0`.
- **`umask 077`**: caches and the debug log (which hold account PII) are written
  owner-only — important on a shared bind-mounted `~/.claude`.

### Account-Level Usage Cache (fewer API calls)

Quota data from `/api/oauth/usage` (5h / 7d / extra) is **account-scoped** —
it's identical for every session on the account. Previous versions cached it
per `session_id`, so each new session refetched the same data and N concurrent
sessions meant N redundant API calls (rate-limit risk).

Account-scoped state now lives in a single shared directory and one fetch
serves all concurrent sessions:

```
~/.claude/statusline/                  account-scoped (shared)
  usage.cache  profile.cache  prepaid_credits.cache  usage.jsonl
~/.claude/statusline/sessions/         per-session (cache-health only)
  <session_id>_cache_health
```

- Per-session prompt-cache-health state is unchanged (it legitimately tracks
  one context window) and stays under `sessions/`.
- Adaptive TTL, error backoff, and lock-file behavior are preserved; locks are
  now shared so concurrent sessions coordinate a single in-flight fetch.
- Graceful migration: if the old `$SCRIPT_DIR` layout exists and the new
  shared dir is empty, `usage.cache` / `profile.cache` /
  `prepaid_credits.cache` / `usage.jsonl` and the `sessions/` dir are moved
  over on first run (best-effort; falls back to a fresh fetch).
- `CLAUDE_DATA_DIR` / `CLAUDE_CACHE_DIR` overrides still work. Setting only
  `CLAUDE_CACHE_DIR` keeps the old single-dir behavior (account data lives
  alongside it).

### Debug Logs Out of /tmp

Debug logs default to `~/.claude/statusline/logs/statusline.log` instead of
`/tmp`. Safe for many concurrent statusline processes — across containers —
sharing one mounted `~/.claude`:

- Append-mode writes (`echo >>`) are atomic for the small lines we emit, so
  interleaving never corrupts a line. Each line is tagged with `[pid:N]`.
- A 1 MiB size cap rotates the file (single `.1` backup) using an atomic
  `mkdir` lock so concurrent processes don't all rotate at once.
- `DEBUG_LOG` env override still wins; `DEBUG_LOG_MAX_BYTES` tunes the cap.

### claude-fable-5 Support

`claude-fable-5` renders consistently with the opus / sonnet / haiku branches:

- Abbreviates to `fabl5` (single-component version, no `major.minor` split).
- Bright-magenta color (`95`), keeping it in Opus's capability-group hue while
  staying distinct from `opus`'s magenta.
- `[1m]` context suffix handled like every other model (`fabl5[1m]`).

### claude-watch.sh — Live Usage Watcher

New standalone companion. A "top"-style full-screen view of one session:

- **Per-turn**: estimated cost + input / output / cache-read / cache-create
  tokens for the latest assistant message.
- **Session totals**: cumulative tokens and estimated cost across the
  transcript (each turn priced at its own model's rate).
- **Quota**: 5h / 7d (and extra, when present) read from the shared
  `usage.cache` statusline.sh maintains.

Reads the transcript, the account usage cache, and `usage.jsonl` — all
read-only. Cost is an estimate from public per-million list pricing (mirrors
the `ccx` tool's pricing tiers); fast-mode surcharges are not modeled.
Resilient streaming parse tolerates malformed/oversized transcript lines and
renders a 27 MB / 4500-turn transcript in ~0.2s. `--help`, `--once`,
`--interval`, `--session`, `--transcript`, `--no-color`.

### Added

- Shared `usage.cache` / `usage.lock` / `usage.err` under the account dir;
  `fetch_usage_for_session` writes once for all sessions
- `migrate_legacy_state()` for graceful one-time migration from `$SCRIPT_DIR`
- `rotate_debug_log()` with size-capped, lock-guarded rotation
- `claude-fable-5` branches in `get_runtime_model`, `abbreviate_model_id`, and
  both model-color code paths
- `claude-watch.sh` (installed by `install.sh` alongside `statusline.sh`)
- `merge_stdin_rate_limits()`, `reap_stale_lock()`, `build_1m_tag()`,
  `abbrev_effort()`, `effort_color()`, and portable `_epoch_from_ts()` /
  `_fmt_epoch()` date helpers
- Test suite grew from 145 to 172 (fabl5, premium-band cue, effort badge,
  stdin-overlay precedence, stale-lock reaping, portable date helpers,
  clean-degradation on empty/sub-cent input)

### Changed

- Debug log default moved from `/tmp/claude-code-statusline.log` to
  `~/.claude/statusline/logs/statusline.log`
- Account-scoped caches (`usage`, `profile`, `prepaid_credits`, `usage.jsonl`)
  default to `~/.claude/statusline/` instead of `$SCRIPT_DIR`

## v0.7.0 — 2026-05-27 — Prompt Cache Health & Absolute Reset Times

Tested against Claude Code CLI v2.1.150 (MAX and PRO accounts).

### Cache Health Indicator

Detects prompt cache invalidation from per-turn token data already in
the CLI's stdin JSON. Uses the same token-drop threshold as Claude Code's
internal `promptCacheBreakDetection.ts`: flags a break when
`cache_read_input_tokens` drops >5% and >2000 tokens from the
previous turn.

- `cache!` (red) — cache-read drop detected; full or partial rebuild likely
- `cache~` (dim yellow) — cache building, first turn or post-break rebuild
- `cache:1h@14:20` / `cache:5m@14:20` — TTL class plus last observed
  cache activity when future/current stdin provides TTL breakdown
- Hidden when healthy by default — zero noise during normal operation
- `--cache auto|always|off` controls cache display

Display appears after the context bar:

```
opus4.6[1m][███░░26%]              (healthy — no indicator)
opus4.6[1m][███░░26%] cache:1h@14:20~ (building — first turn)
opus4.6[1m][███░░26%] cache!       (break — full rebuild)
```

State tracked in `${session_id}_cache_health` as JSON. Older one-number
state files are still accepted and upgraded on the next render.

No cache expiry countdown is shown. Claude Code does not expose a
pre-request server `expire_at`; the statusline records observed cache
activity and, when observed in usage breakdown, the 5m/1h TTL class.
Current Claude Code statusline stdin usually exposes aggregate cache tokens
only, so TTL class display is forward-compatible rather than guaranteed.

### Why It Matters

A single cache break on a 1M-context Opus session costs ~22x more than
a cached turn. For subscription users, that's quota burn equivalent to
20+ normal turns. The indicator makes this invisible cost visible.

### Added

- `get_cache_health()` function with four return states: `ok`, `break`,
  `building`, `none`
- `infer_cache_ttl_class()`, `format_cache_active_time()`, and
  `build_cache_indicator()` helpers
- `CACHE_BREAK_MIN_TOKENS` (2000) and `CACHE_BREAK_DROP_PCT` (5)
  threshold constants
- Extracts `cache_read_input_tokens`, `cache_creation_input_tokens`,
  `input_tokens`, and optional `cache_creation.ephemeral_1h_input_tokens`
  / `cache_creation.ephemeral_5m_input_tokens` from stdin
- Per-session state file (`${session_id}_cache_health`) prevents false
  positives when running concurrent Claude Code sessions
- `mkdir -p` plus atomic state-file replacement ensures detection works for
  API key users where `$CLAUDE_CACHE_DIR` may not exist yet
- 28 new tests (22 unit + 6 integration)

### Absolute Reset Times

Quota reset display changed from relative countdown to absolute time:

- **Before**: `5h[87%~1h30m]` `7d[75%~2d5h]`
- **After**: `5h[87%@14:30]` `7d[75%@Mon]`

Relative time (`~1h30m`) is only true at render time. Claude Code
controls statusline refresh, so a countdown can become stale while
still visible. Absolute time (`@14:30`, `@Mon`) stays true without
realtime refresh.

- 5h uses wall-clock time (`@HH:MM`) — answers "when can I resume?"
- 7d uses day-of-week (`@Mon`) — answers "which day does it reset?"
- Same-day 7d reset falls back to wall-clock
- `@now` when reset is past

`format_reset_absolute()` function with `short` (HH:MM) and `day`
(day-of-week, falls back to HH:MM for same day) modes.

145 total tests across both suites.

---

## v0.6.0 — 2026-05-26 — Smart Countdowns & Information Grouping

Tested against Claude Code CLI v2.1.143 (MAX and PRO accounts).

### Smart Countdown Display

Reset countdowns now respond to two independent signals:

- **Percentage pressure**: 5h >= 80% or 7d >= 70% (existing behavior)
- **Time proximity**: 5h reset <= 2h or 7d reset <= 3d (new)

Either signal triggers the countdown. A user at 40% with 90 minutes to reset
sees `5h[40%~1h30m]` — the opportunity signal: "burn freely, fresh window
coming." Switched 5h from wall-clock (`@14:30`) to relative time (`~1h30m`)
for consistency with 7d.

**Recovery color**: DIM_GREEN when usage is high but reset is imminent
(5h: <= 30min, 7d: <= 12h). Communicates "it was hot, it's cooling down."

### Model + Context Merge

Context bar now attaches directly to the model: `opus4.6[1m][█░░░░░15%]`
instead of `opus4.6[1m] [█░░░░░15%]`. Context is a property of the model
session, not an independent stat.

### Extra Usage: Auto Mode

New default `--extra auto` replaces `always`. Shows the extra-usage section
only when actionable:

- 5h >= 80% or 7d >= 70% (quota running out)
- Extra utilization >= 50% (budget pressure)

Hides extra during calm sessions. `always`, `on-limit`, `off` still available.

### Thresholds as Named Constants

All auto-display thresholds extracted to top-level variables:

```
FIVE_HOUR_COUNTDOWN_SECS=7200    # 2h
FIVE_HOUR_RECOVERY_SECS=1800     # 30min
SEVEN_DAY_COUNTDOWN_SECS=259200  # 3d
SEVEN_DAY_RECOVERY_SECS=43200    # 12h
EXTRA_AUTO_UTIL_PCT=50           # 50%
```

### Cleanup

- Removed dead `format_reset_clock()` (replaced by relative time)
- Removed `context` from all theme `stat_order` strings (now part of model)
- 95 bats tests (was 81)

---

## v0.5.0 — 2026-05-25 — Stdin-First Architecture & Extra Usage

Tested against Claude Code CLI v2.1.141 (MAX and PRO accounts).

### Stdin-First Architecture

Context percentage, rate limits, effort level, and fast mode are now read
directly from the CLI's JSON input instead of computing independently.

- **Context bar** uses `context_window.used_percentage` from stdin. Transcript
  JSONL parsing is kept as fallback for CLI versions before v2.1.132.
- **Quota display** uses `rate_limits` from stdin when no OAuth cache exists.
  OAuth fetch is still needed for extra-usage and user profile data.
- **Effort level** shown next to model when non-default: `opus4.6[1m] max`.
- **Fast mode** shown as `opus4.6[1m] fast` when enabled.
- `format_reset_clock` and `format_reset_relative` now handle both ISO 8601
  and unix epoch timestamps (CLI sends epoch, OAuth API sends ISO).

### Added

- Added default `extra` statusline component for Claude Code extra usage:
  `ex[$16.29/$200 8% bal$4.66]`.
- Reads monthly extra spend from `/api/oauth/usage` and prepaid balance from
  `/api/oauth/organizations/:orgUUID/prepaid/credits` when OAuth profile data is
  available.
- Caches prepaid balance for 5 minutes with the same lock/backoff pattern used
  by quota fetching.
- Refreshes expired file-based Claude Code OAuth tokens before quota/profile
  requests.

### Extra Usage Display Mode

New `--extra` flag controls when the extra-usage component appears:

- `always` — show whenever extra usage is enabled
- `on-limit` — show only when 5h >= 80% or 7d >= 70% (quota under pressure)
- `off` — never show

The `developer` theme defaults to `on-limit`; `minimal` defaults to `off`.

### UX Refinements

- Quota percentages now display as integers: `5h[12%]` instead of `5h[12.0%]`.
- Refresh indicator: `~` appears after quota cluster when an API fetch is in
  flight, `!` when the last fetch failed and data may be stale. Extra usage
  has its own independent indicator (separate API call).
- Duration shows hours for long sessions: `1h30m` instead of `90m`.
- Removed dead `add_component_no_space` and `format_usage_bar` functions.
- Fixed `format_duration(0)` returning "1m" instead of "0m".
- Fixed color variables used before definition (git info, path had no color).
- Guarded context percentage against division by zero (`CLAUDE_CONTEXT_LIMIT=0`).

### Color Hierarchy

- Path demoted to dim cyan — frees visual weight for primary signals.
- Git branch: dirty=yellow (pops), clean=dim yellow (recedes).
- Time: plain dim instead of dim cyan — less color noise.
- User tier label gets color: MAX=green, PRO=cyan, ENT/TEAM=dim cyan.

---

## v0.3.0 — 2026-05-12 — Quota Reset Time & API Cleanup

### Quota Reset Display

When utilization enters the warning zone, reset time auto-appears:

- **5h >= 80%**: wall-clock time — `5h[87%@14:30]`
- **7d >= 70%**: relative countdown — `7d[75%~2d5h]`

Clock time for 5h (you're thinking "can I resume after lunch?").
Relative for 7d ("2d5h" is more actionable than a specific datetime).
Below threshold, display is unchanged: `5h[25%] 7d[10%]`.

### API Accuracy

- Removed stale `anthropic-beta: oauth-2025-04-20` from usage API call —
  endpoint is GA, neither CLI v2.1.76 nor v2.1.121 sends this header
- Usage jq parsing batched into single `eval "$(jq -r @sh ...)"` call
  (was 4 separate jq invocations)

### Cross-Reference

API contract verified against Claude Code CLI v2.1.76 (cli.js) and v2.1.121
(Bun binary). See `docs/devlog/2026-04-28-usage-api-contract-cross-reference.org`.

---

## v0.2.0 — 2026-03-16 — 1M Context Window & API Hardening

### Critical Fixes

**1. Context Window: 1M Auto-Detection**
- Root cause: context_limit hardcoded to 200k, Opus 4.6 [1m] has 1M window
- Fix: detect `[1m]` in model.id (matches CLI's `NO()` function)
- Before: 104k tokens showed 77% (against 200k). After: 10% (against 1M)

**2. Context Calculation: Match CLI's /context**
- Formula: `percentage = round(totalTokens / contextWindow * 100)`
- Removed erroneous `system_overhead=24500` — cache_read + input already includes system prompt
- Changed denominator from `window - output_reserve` to full `window` (matches CLI)
- Fixed max_output_tokens: 16000 -> 32000

**3. Cost Formatting Bug**
- `$10.00` displayed as `$1` due to `sed 's/0$//'` eating integer digits
- Fix: `sed 's/\.00$//'` — only strip `.00`, keep `$10.50` as `$10.50`

**4. Model Detection Updated**
- Added opus-4-6, sonnet-4-6 pattern matching
- Strip `[1m]` suffix from settings.json model before case-matching (prevents `opus[1m][1m]`)

### API Improvements

**5. Adaptive Quota TTL**
- 5h utilization <20%: poll every 5min
- 20-50%: every 2min
- 50-80%: every 1min
- 80%+: every 30s
- Previously: fixed 60s regardless of utilization

**6. Error Backoff**
- 120s cooldown after failed API call (was: retry every tick)
- Error state tracked in `${session_id}.err` file

**7. OAuth Gate**
- Skip quota/user fetch when `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, or `ANTHROPIC_BASE_URL` set
- Skip when credentials file exists but contains no OAuth token
- Eliminates "no token found" log noise for API key users

**8. Dynamic User-Agent**
- Uses CLI version from input JSON (was: hardcoded `claude-code/2.1.22`)

### Code Quality

**9. Atomic Cache Writes**
- Write to `${cache_file}.tmp.$$` then `mv -f` to prevent truncated JSON from race conditions

**10. JSON Injection Prevention**
- `detect_session_boundary()` now uses `jq -n --arg` instead of raw string interpolation

**11. Profile Parsing Consolidation**
- 10 separate `echo | jq` calls replaced with single `eval "$(jq -r @sh ...)"` call

**12. Progress Bar Extraction**
- `render_bar()` function replaces 70+ lines of copy-paste across 7 bar styles
- C-style `for ((i=0; ...))` loops replace `seq` subshells

**13. Deduplicated Logic**
- `get_user_tier()`: single function for tier detection (was: 3 copies)
- `get_adaptive_ttl()`: single function for TTL calculation (was: 2 copies)

**14. Portability**
- `printf '%b'` replaces `echo -e` for ANSI stripping (portable across shells)
- `sed 's/\.00$//'` replaces `sed -E 's/0+$//'` (GNU/BSD compatible)

**15. Input Parsing**
- Single `eval "$(jq -r @sh ...)"` call replaces 12 separate subshells

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_CONTEXT_LIMIT` | auto | Context token limit override (auto-detected from model.id) |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `32000` | Output token reserve |
| `CLAUDE_DATA_DIR` | script dir | Data directory (usage.jsonl) |
| `CLAUDE_CACHE_DIR` | `$CLAUDE_DATA_DIR/sessions` | Session cache directory |

---

## v0.1.0 — 2026-02-05 — API Correctness & macOS Support

Initial release with float-to-integer conversion fixes, macOS Keychain support,
OrbStack home directory resolution, profile API alignment, per-model quotas,
BSD compatibility, user/quota components, and dependency checking.
