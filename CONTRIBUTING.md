# Contributing

## Quick Start

```bash
git clone https://github.com/thevibeworks/claude-code-statusline.git
cd claude-code-statusline
npm exec --yes bats -- t/   # or: brew install bats-core && bats t/
```

## Guidelines

- One file per script. No external dependencies beyond `jq` and `curl`.
- Test what you change. Add to `t/statusline.bats` or `t/install.bats`.
- Match existing code style. Read the code before proposing rewrites.
- Keep the statusline fast. It runs on every prompt render.

## Tests

```bash
npm exec --yes bats -- t/                   # all tests, no global install
npm exec --yes bats -- t/statusline.bats    # statusline only
npm exec --yes bats -- t/install.bats       # install only
```

Tests source functions from the real `statusline.sh` via `t/helpers.bash` —
no copies, no drift. Install tests use mock `curl` and temp `$HOME` isolation.

## Pull Requests

- One feature per PR. Small diffs review faster.
- Include test coverage for new functions.
- Update CHANGELOG.md if user-facing behavior changes.
- Run `npm exec --yes bats -- t/` before pushing. CI runs it too.

## Bug Reports

Open an issue with:
1. Your terminal + shell (e.g., alacritty + zsh, iTerm2 + bash)
2. Claude Code version (`claude --version`)
3. Debug log: `echo '...' | bash statusline.sh --test --debug && cat /tmp/claude-code-statusline.log`
