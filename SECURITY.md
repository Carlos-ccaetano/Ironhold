# Security policy

## Supported versions

Ironhold is in its foundation stage. Only the latest commit on `main` is intended to receive security updates.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use the repository's private GitHub security advisory reporting flow and include:

- the affected commit or version;
- reproduction steps or a proof of concept;
- the expected impact;
- any suggested mitigation.

Please avoid accessing data that is not yours, disrupting services, or publishing details before a fix can be prepared. The maintainers will acknowledge the report and coordinate next steps through the private advisory.

## Current scope

Ironhold implements authenticated webhook ingestion at `POST /api/webhooks`, with media-type and body-size limits, HMAC-SHA256 verification and timestamp checks. PostgreSQL atomically persists replay claims and received webhooks, with event idempotency and acknowledgement of freshly signed retries of an identical stored envelope. See the [current HTTP contract](docs/api/webhooks.md) for the boundaries and failure behavior.

These implemented paths are part of the current security surface. Administrative authentication, rate limiting, broader audit features and a dashboard remain roadmap work.
