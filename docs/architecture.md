# Architecture

## Context

Tidewake owns reliable webhook delivery. Ironhold is its companion service and will own the receiving boundary: accepting requests, applying security policy, and retaining an auditable account of processing.

The initial receiving increment is implemented: Ironhold accepts webhook envelopes through `POST /api/webhooks` and persists them in PostgreSQL. Integrity, freshness, abuse protection, complete auditing, and an operational interface remain later boundaries rather than implied properties of ingestion.

## Current runtime

An HTTP request reaches `IronholdWeb.Endpoint`, passes through the router's JSON `:api` pipeline, and reaches `IronholdWeb.WebhookController.create/2`. A valid envelope contains non-empty string `id` and `type` fields plus an object-valued `data` field. The controller maps those public names to `event_id`, `event_type`, and `payload`, then delegates persistence to `Ironhold.Webhooks`.

The context supplies `received_at` and inserts an `Ironhold.Webhooks.ReceivedWebhook` schema. The `received_webhooks` table stores `event_id`, `event_type`, `payload`, and `received_at`, with a unique database index on `event_id`. A successful insert returns `202 Accepted`; a duplicate `event_id` is normalized by the context and returned as `409 Conflict`; invalid input returns `422 Unprocessable Entity`.

`Ironhold.Application` supervises the endpoint, the Ecto repository, and the Telemetry supervisor. PostgreSQL is the only local infrastructure dependency.

## Current and future boundaries

### Webhooks — implemented initial boundary

The controller owns HTTP request and response semantics, including validation of the public envelope shape and the `202`, `409`, and `422` responses. The `Ironhold.Webhooks` context owns the receive use case, receipt-time assignment, persistence, and normalization of unique-index conflicts. `ReceivedWebhook` owns the persisted field and changeset constraints. This keeps Phoenix concerns out of the schema and database details out of the controller.

The current endpoint accepts and stores the envelope only. Explicit HTTP request and payload-size limits, supported-content-type policy beyond the current JSON pipeline, and downstream event processing remain pending.

### Security

Will validate authenticity and freshness. Versioned HMAC verification, signed timestamp validation, replay prevention, rate limiting, and authentication belong here and must be introduced with explicit threat models and tests.

### Audit

Will record security-relevant decisions and webhook processing outcomes with deliberate retention and access policies. Logging alone will not be treated as a complete audit trail.

### Observability

Will turn Telemetry events into useful metrics, traces, alerts, and service-level signals. The current Telemetry wiring is only the instrumentation foundation.

## Dependency direction

The HTTP layer calls the `Ironhold.Webhooks` context rather than persisting schemas directly. The context may use the repository and schema, while neither depends on Phoenix. Future security and audit policy should preserve this direction and remain behind the code that owns each use case.

## Security posture

The webhook ingestion endpoint is available, but accepting and persisting an envelope is not proof that it is authentic, fresh, or safe to process. Ironhold does not yet enforce explicit HTTP limits, HMAC signatures, signed timestamps, replay protection, rate limiting, or sender authentication. Complete audit records and dashboard access are also not implemented.
