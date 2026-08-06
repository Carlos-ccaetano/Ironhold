# ADR 0001: Project foundation

- Status: Accepted
- Date: 2026-08-06

## Context

Ironhold needs a small, understandable base before webhook and security behavior is designed. Adding speculative domain modules now would make unfinished capabilities look real and would constrain later threat-model work.

## Decision

Use a conventional Elixir/Phoenix application with Bandit as the HTTP server, Ecto with PostgreSQL for persistence, Telemetry for instrumentation, and ExUnit for tests. Credo and Sobelow provide static quality and security checks in CI. Docker Compose runs PostgreSQL only; the application continues to run directly through Mix during development.

Production configuration is read from environment variables at runtime. The initial code contains only the supervision tree, repository, HTTP endpoint and router, a small informational page, standard error rendering, and test support.

Future Webhooks, Security, Audit, and Observability boundaries are documented but will not have empty code modules.

## Consequences

- The project is easy to run and explain using familiar Phoenix conventions.
- Security-sensitive behavior can be introduced through focused, independently reviewed changes.
- The service currently has no webhook endpoint or production security controls beyond framework defaults.
- A PostgreSQL instance is required for the standard test alias and future persistence work.
