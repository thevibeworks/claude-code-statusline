# `/api/oauth/usage` — HTTP contract

The endpoint this statusline polls for 5h / 7d / per-model quota. This file
documents the observed wire contract so parser changes can be checked against
ground truth instead of guesswork.

- Synced with: **Claude Code v2.1.207** (captured 2026-07-13 via a local
  mitm reverse proxy in front of the official CLI; first captured against
  v2.1.201 on 2026-07-06 — no schema change between the two)
- All credentials, org IDs, and request IDs below are redacted or fabricated.
- Fields marked *reserved* were observed only as `null`; names are as sent by
  the server.

## Request

```
GET https://api.anthropic.com/api/oauth/usage
```

Headers as sent by claude-cli v2.1.207:

| Header | Value | Notes |
|--------|-------|-------|
| `Authorization` | `Bearer <oauth access token>` | The `claudeAiOauth.accessToken` from Claude Code credentials |
| `anthropic-beta` | `oauth-2025-04-20` | |
| `Accept` | `application/json, text/plain, */*` | |
| `Accept-Encoding` | `identity` | |
| `Content-Type` | `application/json` | sent even though the GET has no body |
| `User-Agent` | `claude-cli/<version> (external, cli)` | see below |

No query parameters. No request body.

### The CLI itself calls this twice per launch

One `claude` v2.1.201 session was observed issuing **two** usage requests on
boot, from two distinct internal clients:

```
user-agent: claude-cli/2.1.201 (external, cli)   + anthropic-beta: oauth-2025-04-20
user-agent: claude-code/2.1.201
```

Both received 200 with identical schema. This matters for rate-limit math:
launching N Claude Code instances produces 2N usage requests from the CLIs
alone before any statusline fetch happens. The statusline mirrors the first
form exactly (`claude-cli/<version> (external, cli)` plus the header set
above, version taken from the running CLI's stdin payload) and adds at most
one request per account per TTL window (shared cache + atomic lock, see
below).

### Transport note: mitm proxies

When the CLI runs behind a TLS-inspecting proxy it trusts (cctrace, corporate
inspection), the proxy's CA typically arrives via `NODE_EXTRA_CA_CERTS` —
which only Node honors, *in addition to* the system store. Non-Node tooling
that replays this request (curl, python, go) inherits `HTTPS_PROXY` but not
the trust, and fails instantly with an SSL verification error (curl exit 60,
`http_code` 000). curl has no additive flag: build a combined bundle
(system CAs + the extra cert) and pass it with `--cacert`. This statusline
does that automatically (`curl_ca_bundle` in `statusline.sh`).

## Response — 200

`Content-Type: application/json`. Notable response headers:
`anthropic-organization-id: <org uuid>` (redacted), `request-id: req_...`.

```json
{
  "five_hour": {
    "utilization": 96.0,
    "resets_at": "2026-07-06T10:59:59.800387+00:00",
    "limit_dollars": null,
    "used_dollars": null,
    "remaining_dollars": null
  },
  "seven_day": {
    "utilization": 65.0,
    "resets_at": "2026-07-08T15:59:59.800406+00:00",
    "limit_dollars": null,
    "used_dollars": null,
    "remaining_dollars": null
  },
  "limits": [
    {
      "kind": "session",
      "group": "session",
      "percent": 96,
      "severity": "critical",
      "resets_at": "2026-07-06T10:59:59.800387+00:00",
      "scope": null,
      "is_active": true
    },
    {
      "kind": "weekly_all",
      "group": "weekly",
      "percent": 65,
      "severity": "normal",
      "resets_at": "2026-07-08T15:59:59.800406+00:00",
      "scope": null,
      "is_active": false
    },
    {
      "kind": "weekly_scoped",
      "group": "weekly",
      "percent": 83,
      "severity": "warning",
      "resets_at": "2026-07-08T15:59:59.800706+00:00",
      "scope": {
        "model": { "id": null, "display_name": "Fable" },
        "surface": null
      },
      "is_active": false
    }
  ],
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": 20000,
    "used_credits": 0.0,
    "utilization": 0.0,
    "currency": "USD",
    "decimal_places": 2,
    "disabled_reason": "out_of_credits",
    "daily": null,
    "weekly": null
  },
  "spend": {
    "used":  { "amount_minor": 0,     "currency": "USD", "exponent": 2 },
    "limit": { "amount_minor": 20000, "currency": "USD", "exponent": 2 },
    "percent": 0,
    "severity": "normal",
    "enabled": false,
    "disabled_reason": "out_of_credits",
    "cap": { "money": null, "credits": { "amount_minor": 20000, "exponent": 2 } },
    "balance": null,
    "auto_reload": null,
    "disclaimer": "Usage credits cover you when you hit your plan limits. [...]",
    "can_purchase_credits": false,
    "can_toggle": false
  },
  "member_dashboard_available": false,

  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "seven_day_oauth_apps": null,
  "seven_day_cowork": null,
  "seven_day_omelette": null,
  "omelette_promotional": null,
  "tangelo": null,
  "iguana_necktie": null,
  "nimbus_quill": null,
  "cinder_cove": null,
  "amber_ladder": null
}
```

### Field notes

**`five_hour` / `seven_day`** — the two account-wide windows. `utilization`
is a float percentage; `resets_at` is ISO-8601 with microseconds and offset.
The `*_dollars` fields have only been observed `null` on subscription plans.

**`limits[]`** — the newer, generic limit contract (this is what the
statusline parses first):

| Field | Values observed | Meaning |
|-------|-----------------|---------|
| `kind` | `session`, `weekly_all`, `weekly_scoped` | which limit |
| `group` | `session`, `weekly` | window family |
| `percent` | integer | utilization |
| `severity` | `normal`, `warning`, `critical` | server-side level |
| `resets_at` | ISO-8601 | window end |
| `scope` | `null` or `{model:{id,display_name},surface}` | `weekly_scoped` carries the model, e.g. `display_name: "Fable"`; `id` observed `null` |
| `is_active` | bool | whether this is the currently binding limit |

A `weekly_scoped` limit shares its `resets_at` with `weekly_all` — it is the
same 7-day window, scoped to one model.

**Legacy per-model fields** — `seven_day_opus` / `seven_day_sonnet` used to
carry `{utilization, resets_at}`; since the `limits[]` array appeared they
arrive `null`. Parsers should prefer `limits[]` and keep the old fields only
as a fallback for cached data.

**Reserved fields** — `tangelo`, `iguana_necktie`, `omelette_promotional`,
`nimbus_quill`, `cinder_cove`, `amber_ladder`, `seven_day_oauth_apps`,
`seven_day_cowork`, `seven_day_omelette`: observed only as `null`. Do not
depend on them; listed so a future non-null appearance is recognized as a
contract change.

## Response — 429 (rate limited)

Not present in the proxy capture (the CLI wasn't throttled that run), but
observed regularly by this statusline's own fetches when several instances
run: plain 429 with a `Retry-After: <seconds>` header (value `300` observed).

Client obligations, as implemented here:

- Serve the cached response while throttled; never retry inside the
  `Retry-After` window.
- Escalate the retry gap on consecutive failures (this repo: 120s → 240s →
  480s → 600s cap, `Retry-After` wins when longer).
- Coordinate across processes: one shared cache + one atomic lock per
  account dir, so N concurrent statusline renders produce at most one fetch.

## Related endpoints used by this statusline (not in this capture)

| Endpoint | Purpose |
|----------|---------|
| `GET /api/oauth/profile` | account display name, org UUID, tier |
| `GET /api/oauth/organizations/<org_uuid>/prepaid/credits` | prepaid balance for the extra-usage badge (requires `x-organization-uuid` header) |
