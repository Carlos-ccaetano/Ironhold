# Contributing

## Development workflow

1. Create a focused branch from `main`.
2. Start PostgreSQL with `docker compose up -d postgres` or use a local PostgreSQL instance.
3. Load local environment variables and run `mix setup`.
4. Keep changes small and avoid introducing abstractions before a concrete use case needs them.
5. Run the full local check set before opening a pull request.

~~~sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix sobelow --exit
mix test
~~~

Pull requests should explain the motivation, architectural decisions, validation performed, and intentionally deferred work. Never commit `.env` files, production credentials, tokens, or private keys.

## Security-sensitive changes

Changes to signing, replay protection, authentication, authorization, rate limiting, or audit retention must include their assumptions, abuse cases, failure behavior, and tests. Use the private reporting process in `SECURITY.md` for vulnerabilities rather than a public issue.
