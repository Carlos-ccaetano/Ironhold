# Ironhold

Ironhold is the companion service to Tidewake. Tidewake focuses on reliable webhook delivery; Ironhold will receive, validate, protect, and audit those webhooks.

## Current status

This repository contains the project foundation and an authenticated webhook ingestion endpoint that persists received event envelopes. The endpoint requires a single `application/json` content type, rejects unsupported or ambiguous media types, limits the raw request body to `262_144` bytes, and returns stable errors for those boundaries. Persisted event IDs and types are limited to 255 characters.

`POST /api/webhooks` requires exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header. Ironhold verifies HMAC-SHA256 over `v1.<event_id>.<timestamp>.<exact_body_bytes>` before JSON decoding, accepts timestamps from 300 seconds in the past through 30 seconds in the future, and requires the authenticated header ID to match the decoded body ID exactly. Authentication failures return the generic `401` response defined by [ADR 0004](docs/adr/0004-webhook-authentication-policy.md). Production reads the shared secret from `IRONHOLD_WEBHOOK_SIGNING_SECRET`.

Ingestion and authentication emit separate low-cardinality Telemetry events and counters. Replay protection, storage of used nonces or signatures, secret rotation and multiple simultaneous secrets, rate limiting, a complete audit trail, and an operational dashboard remain unimplemented. This receiver boundary is not an end-to-end production integration: Tidewake's Req adapter remains inactive, so real HTTP delivery, retries, backoff, and Tidewake-side SSRF protection are still pending.

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

## Roadmap

The next increments will add replay protection, operational controls, and audit retention before an authenticated dashboard is considered. See [docs/roadmap.md](docs/roadmap.md) for the staged plan.

The initial HTTP contract is documented in [docs/api/webhooks.md](docs/api/webhooks.md).

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [SECURITY.md](SECURITY.md) for responsible vulnerability reporting.
