# Ironhold

[![CI](https://github.com/Carlos-ccaetano/Ironhold/actions/workflows/ci.yml/badge.svg)](https://github.com/Carlos-ccaetano/Ironhold/actions/workflows/ci.yml)

Ironhold is a webhook receiver that authenticates requests, rejects exact replays, and stores accepted event envelopes idempotently in PostgreSQL.

Signed webhook delivery can involve both legitimate retries and captured requests sent again. Ironhold separates event idempotency from cryptographic replay protection before acknowledging receipt.

**Pre-release:** implemented and tested locally and in CI, without a proven production deployment or joint production integration with Tidewake. Green CI does not establish production readiness.

**Core stack:** Elixir 1.18 · Erlang/OTP 27 · Phoenix 1.8 · PostgreSQL 16 · HMAC-SHA256 · Telemetry · ExUnit.

## Current status

### Implemented and tested

- **Authenticated input:** HMAC-SHA256 over the exact received bytes, signature and timestamp validation, JSON content-type checks, and request body limits.
- **Durable decisions:** cryptographic replay protection, idempotency by event ID and content, and transactional PostgreSQL persistence.
- **Maintenance and evidence:** replay claim expiration and supervised cleanup, low-cardinality Telemetry events and metrics, and automated regression tests.

### Planned / not yet proven

Ingestion rate limiting, receiver `Retry-After` guidance, signing secret rotation and overlapping secrets, broader operational auditing and retention, administrative authentication, a dashboard, external metrics reporting and alerts remain pending. Production deployment and operational validation are not established. Ironhold accepts and stores envelopes; it does not process event-specific payloads.

## Documentation

- **API and design:** [HTTP webhook contract](docs/api/webhooks.md) · [Architecture](docs/architecture.md) · [Roadmap](docs/roadmap.md)
- **Project:** [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md) · [Tidewake](https://github.com/Carlos-ccaetano/Tidewake)

[Retries and replays](#retries-and-replays) · [Receiving boundary](#receiving-boundary) · [Local setup](#local-setup) · [Quality checks](#quality-checks)

## Retries and replays

For authenticated, valid envelopes within the timestamp window:

| Request | Response |
| --- | --- |
| First valid webhook | `202 Accepted` |
| Same event ID, type, and decoded payload, with a fresh timestamp and valid signature | `202 Accepted` |
| Exact replay of an already accepted signature | `409 Conflict` |
| Same event ID with conflicting type or payload | `409 Conflict` |

**Idempotency** prevents storing another copy of the same event ID and content. **Replay protection** rejects reuse of an already accepted cryptographic signing attempt. A legitimate retry with a fresh timestamp and signature is not an exact replay.

Both conflict cases return the same generic response without revealing the internal distinction. An accepted identical retry returns the same status and body as the first request.

## Relationship with Tidewake

Tidewake produces and sends signed webhooks with bounded automatic retries; its authenticated manual retry and retry audit APIs are also implemented. Ironhold is a complementary receiver. They are independent systems, repositories, and processes, with no proven joint production deployment. Ironhold does not schedule Tidewake's retries.

## Receiving boundary

### HTTP input and authentication

`POST /api/webhooks` persists authenticated event envelopes. The endpoint requires a single `application/json` content type, rejects unsupported or ambiguous media types, limits the raw request body to `262_144` bytes, and returns stable errors for those boundaries. Persisted event IDs and types are limited to 255 characters.

`POST /api/webhooks` requires exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header. Ironhold verifies HMAC-SHA256 over `v1.<event_id>.<timestamp>.<exact_body_bytes>` before JSON decoding, accepts timestamps from 300 seconds in the past through 30 seconds in the future, and requires the authenticated header ID to match the decoded body ID exactly. Authentication failures return the generic `401` response defined by [ADR 0004](docs/adr/0004-webhook-authentication-policy.md). Production reads the shared secret from `IRONHOLD_WEBHOOK_SIGNING_SECRET`.

### Persistence and replay claims

After authentication, Ironhold derives an irreversible SHA-256 replay fingerprint from the validated signature. It atomically inserts that claim with the received webhook in PostgreSQL. Reusing the same signature is an exact cryptographic replay and returns the generic `409` response. A retry of the same stored envelope with a new timestamp and signature is a distinct signing attempt: Ironhold keeps its new claim, reuses the existing webhook, and returns the same generic `202 Accepted` response as the first request. Repeating that retry with the same signature returns `409`. Reusing the event ID with a different type or payload also returns `409` and rolls back the provisional claim. This separates event idempotency, which compares the stored content, from replay protection, which recognizes a previously processed signature. A supervised cleanup process removes expired claims every five minutes by default.

### Observability and confidentiality

Ingestion, authentication, replay decisions, and replay cleanup emit low-cardinality Telemetry events and metrics. A dedicated untagged `ironhold.webhooks.ingestion.idempotent_retry.count` counter records committed idempotent acknowledgements without event or signing data. Raw signatures, shared secrets, complete signing headers, raw request bodies, URLs, and client IPs are not stored as replay state or attached to replay Telemetry.

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
