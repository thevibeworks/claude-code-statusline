# Security

This script reads your Claude OAuth access token (from Claude Code's
credentials file or the macOS Keychain) and sends it to exactly one host:
`api.anthropic.com` (plus `platform.claude.com` for token refresh). It
never writes the token to logs or caches, and it has no analytics,
telemetry, or third-party endpoints. Verify that claim — it's one file:
grep `curl` in `statusline.sh`.

## What to report

- Anything that could leak the OAuth token (into logs, cache files, argv,
  error messages, or to a non-Anthropic host)
- Command injection via statusline stdin (Claude Code feeds it JSON that
  includes untrusted strings like branch names and paths)
- install.sh integrity issues

## How to report

Open a [private security advisory](https://github.com/thevibeworks/claude-code-statusline/security/advisories/new)
on GitHub. If that's not possible, open a regular issue saying only
"security issue, need a private channel" — do not include details.

Expect an acknowledgment within a week. This is a maintained side project,
not a company with an on-call rotation; critical token-leak reports get
fixed fast, everything else gets triaged honestly.

## Known trade-offs (not vulnerabilities)

- The token passes to curl via `-H` on argv, which is briefly visible in
  `ps` on the local machine. An attacker with local process-listing access
  can already read the credentials file itself.
- `curl | bash` install is offered for convenience; the paranoid path
  (clone, read, copy) is documented in the README and is four lines.
