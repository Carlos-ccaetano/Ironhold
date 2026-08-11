# Ironhold

Ironhold is the companion service to Tidewake. Tidewake focuses on reliable webhook delivery; Ironhold will receive, validate, protect, and audit those webhooks.

## Current status

This repository contains the project foundation and an initial webhook ingestion endpoint that persists received event envelopes.

HMAC validation, replay protection, rate limiting, authentication, complete auditing, and a dashboard are deliberately not implemented yet. They are planned as separate increments so that each security decision can be reviewed on its own.

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

The next increments will define webhook ingestion contracts, add integrity and replay protections, introduce operational controls and audit retention, and only then consider an authenticated dashboard. See [docs/roadmap.md](docs/roadmap.md) for the staged plan.

The initial HTTP contract is documented in [docs/api/webhooks.md](docs/api/webhooks.md).

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [SECURITY.md](SECURITY.md) for responsible vulnerability reporting.
