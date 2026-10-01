# Architecture

## Context

Tidewake owns reliable webhook delivery. Ironhold is its companion service and will own the receiving boundary: accepting requests, applying security policy, and retaining an auditable account of processing.

The initial receiving increment is implemented: Ironhold accepts webhook envelopes through `POST /api/webhooks` and persists them in PostgreSQL. Integrity, freshness, abuse protection, complete auditing, and an operational interface remain later boundaries rather than implied properties of ingestion.

## Current runtime

An HTTP request reaches `IronholdWeb.Endpoint`, where `IronholdWeb.Plugs.RequireJsonContentType` requires a single `application/json` media type for API requests with bodies and returns `415 Unsupported Media Type` otherwise. `Plug.Parsers` accepts raw JSON bodies up to and including `262_144` bytes; larger bodies return the stable `413 Payload Too Large` response before controller or persistence work. The request then passes through the router's JSON `:api` pipeline and reaches `IronholdWeb.WebhookController.create/2`.

A valid envelope contains non-empty string `id` and `type` fields of at most 255 characters plus an object-valued `data` field. The controller maps those public names to `event_id`, `event_type`, and `payload`, then delegates persistence to `Ironhold.Webhooks`.

The context supplies `received_at` and inserts an `Ironhold.Webhooks.ReceivedWebhook` schema. The `received_webhooks` table stores `event_id`, `event_type`, `payload`, and `received_at`, with a unique database index on `event_id`. A successful insert returns `202 Accepted`; a duplicate `event_id` is normalized by the context and returned as `409 Conflict`; invalid input returns `422 Unprocessable Entity`. Accepted ingestion and rejections for validation, duplicate IDs, or unsupported media types emit bounded Telemetry events and counters.

`Ironhold.Application` supervises the endpoint, the Ecto repository, and the Telemetry supervisor. PostgreSQL is the only local infrastructure dependency.

## Current and future boundaries

### Webhooks — implemented initial boundary

The controller owns HTTP request and response semantics, including validation of the public envelope shape and the `202`, `409`, and `422` responses. The `Ironhold.Webhooks` context owns the receive use case, receipt-time assignment, persistence, and normalization of unique-index conflicts. `ReceivedWebhook` owns the persisted field and changeset constraints. This keeps Phoenix concerns out of the schema and database details out of the controller.

The current endpoint enforces the JSON media-type, raw-body-size, envelope-shape, field-length, and duplicate-ID boundaries before or during persistence. It accepts and stores the envelope only; downstream event processing remains pending.

### Security

ADR 0003 defines the versioned HMAC receiver contract and verification order, but no verification code is implemented. Signature verification, temporal validation, raw-body preservation for HMAC, replay protection, secret rotation, rate limiting, and authentication belong here and must be introduced with explicit threat models and tests.

### Audit

Will record security-relevant decisions and webhook processing outcomes with deliberate retention and access policies. Logging alone will not be treated as a complete audit trail.

### Observability

Ingestion emits accepted and rejected Telemetry events, with counters for accepted requests and bounded rejection reasons. Reporters, traces, alerts, service-level signals, and an operational dashboard remain future work.

## Dependency direction

The HTTP layer calls the `Ironhold.Webhooks` context rather than persisting schemas directly. The context may use the repository and schema, while neither depends on Phoenix. Future security and audit policy should preserve this direction and remain behind the code that owns each use case.

## Security posture

The webhook ingestion endpoint enforces its current media-type, raw-body-size, envelope-shape, field-length, and duplicate-ID boundaries, but accepting and persisting an envelope is not proof that it is authentic, fresh, or safe to process. Ironhold does not yet verify HMAC signatures, validate signed timestamps, preserve raw body bytes for HMAC, prevent replay, rotate secrets, rate-limit ingestion, or authenticate senders. ADR 0003 is a design contract, not an implemented feature. Complete audit records and an operational dashboard are also not implemented.
