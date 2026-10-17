# Ironhold

Ironhold is the companion service to Tidewake. Tidewake focuses on reliable webhook delivery; Ironhold will receive, validate, protect, and audit those webhooks.

## Current status

This repository contains the project foundation and an authenticated webhook ingestion endpoint that persists received event envelopes. The endpoint requires a single `application/json` content type, rejects unsupported or ambiguous media types, limits the raw request body to `262_144` bytes, and returns stable errors for those boundaries. Persisted event IDs and types are limited to 255 characters.

`POST /api/webhooks` requires exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header. Ironhold verifies HMAC-SHA256 over `v1.<event_id>.<timestamp>.<exact_body_bytes>` before JSON decoding, accepts timestamps from 300 seconds in the past through 30 seconds in the future, and requires the authenticated header ID to match the decoded body ID exactly. Authentication failures return the generic `401` response defined by [ADR 0004](docs/adr/0004-webhook-authentication-policy.md). Production reads the shared secret from `IRONHOLD_WEBHOOK_SIGNING_SECRET`.

After authentication, Ironhold derives an irreversible SHA-256 replay fingerprint from the validated signature. It atomically inserts that claim with the received webhook in PostgreSQL. Reusing the same signature is an exact cryptographic replay and returns the generic `409` response. A retry of the same stored envelope with a new timestamp and signature is a distinct signing attempt: Ironhold keeps its new claim, reuses the existing webhook, and returns the same generic `202 Accepted` response as the first request. Repeating that retry with the same signature returns `409`. Reusing the event ID with a different type or payload also returns `409` and rolls back the provisional claim. This separates event idempotency, which compares the stored content, from replay protection, which recognizes a previously processed signature. A supervised cleanup process removes expired claims every five minutes by default.

Ingestion, authentication, replay decisions, and replay cleanup emit low-cardinality Telemetry events and metrics. A dedicated untagged `ironhold.webhooks.ingestion.idempotent_retry.count` counter records committed idempotent acknowledgements without event or signing data. Raw signatures, shared secrets, complete signing headers, raw request bodies, URLs, and client IPs are not stored as replay state or attached to replay Telemetry. Tidewake now implements secure outbound HTTP delivery and bounded automatic retries, and Ironhold can acknowledge those retries idempotently when a fresh signature carries an identical envelope. This does not mean the applications are deployed as an end-to-end production integration. Secret rotation and multiple simultaneous secrets, rate limiting, manual retry and its audit records, `Retry-After` support, external metrics reporting and alerts, administrative authentication, deployment, and an operational interface or dashboard remain unimplemented.

## Stack

- Elixir 1.18 and Erlang/OTP 27
- Phoenix with Bandit
- Ecto and PostgreSQL
- Telemetry
- ExUnit, Credo, and Sobelow

## Requirements

- Elixir and Erlang versions from `.tool-versions`
- PostgreSQL 16, installed locally or run with Docker Compose
- Docker with Compose support (optional)

## Local setup

Copy the example environment file and load it into your shell:

~~~sh
cp .env.example .env
set -a
. ./.env
set +a
~~~

Start PostgreSQL:

~~~sh
docker compose up -d postgres
~~~

Install dependencies, prepare the database, and start Phoenix:

~~~sh
mix setup
mix phx.server
~~~

The application is available at [http://localhost:4000](http://localhost:4000). Stop the database with `docker compose down`; the named volume keeps local data between runs.

## Quality checks

~~~sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix sobelow --exit
mix test
~~~

## Initial structure

- `lib/ironhold` contains the application supervision tree and Ecto repository.
- `lib/ironhold_web` contains the endpoint, router, telemetry, controller, views, and templates.
- `config` holds environment-specific and runtime configuration.
- `test` contains ExUnit support modules and HTTP tests.
- `docs` records architectural boundaries, the roadmap, and decisions.

## Replay cleanup configuration

The cleanup worker is supervised as `Ironhold.Webhooks.ReplayCleanup`. Its interval is configured in application configuration and defaults to five minutes:

```elixir
config :ironhold, Ironhold.Webhooks.ReplayCleanup, interval: :timer.minutes(5)
```

Tests use `interval: :infinity` and trigger cleanup explicitly. There is currently no environment variable for this interval.

## Roadmap

Replay protection is implemented. The next increments concern the remaining operational controls and audit retention before an authenticated dashboard is considered. See [docs/roadmap.md](docs/roadmap.md) for the staged plan.

The initial HTTP contract is documented in [docs/api/webhooks.md](docs/api/webhooks.md).

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [SECURITY.md](SECURITY.md) for responsible vulnerability reporting.
