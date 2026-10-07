# Architecture

## Context

Tidewake owns reliable webhook delivery. Ironhold is its companion service and will own the receiving boundary: accepting requests, applying security policy, and retaining an auditable account of processing.

The first authenticated receiving boundary is implemented: Ironhold authenticates webhook envelopes received through `POST /api/webhooks` before persisting them in PostgreSQL. Replay protection, abuse controls, complete auditing, and an operational interface remain later boundaries rather than implied properties of ingestion.

## Current runtime

An HTTP request reaches `IronholdWeb.Endpoint`, where `IronholdWeb.Plugs.RequireJsonContentType` requires a single `application/json` media type and returns `415 Unsupported Media Type` otherwise. After endpoint Telemetry starts, `IronholdWeb.Plugs.RequireWebhookSignature` requires exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header, reads at most `262_144` raw body bytes, and returns the stable `413 Payload Too Large` response when that limit is exceeded.

The signature boundary verifies HMAC-SHA256 over `v1.<event_id>.<timestamp>.<exact_body_bytes>`. It accepts timestamps from 300 seconds in the past through 30 seconds in the future, with both limits inclusive. On success, the exact authenticated bytes are retained only in `conn.private`; `Plug.Parsers` receives those same bytes through `IronholdWeb.WebhookBodyReader` and decodes them once. The router then dispatches to `IronholdWeb.WebhookController.create/2`, where `IronholdWeb.Plugs.RequireMatchingWebhookId` requires the authenticated header ID to equal the decoded body `id` exactly before the context can run.

A valid envelope contains non-empty string `id` and `type` fields of at most 255 characters plus an object-valued `data` field. The controller maps those public names to `event_id`, `event_type`, and `payload`, then delegates persistence to `Ironhold.Webhooks`.

The context supplies `received_at` and inserts an `Ironhold.Webhooks.ReceivedWebhook` schema. The `received_webhooks` table stores `event_id`, `event_type`, `payload`, and `received_at`, with a unique database index on `event_id`. A successful insert returns `202 Accepted`; a duplicate `event_id` is normalized by the context and returned as `409 Conflict`; invalid input that reaches envelope validation returns `422 Unprocessable Entity`. Authentication failures return the same generic `401 Unauthorized` response before persistence.

`Ironhold.Application` supervises the endpoint, the Ecto repository, and the Telemetry supervisor. PostgreSQL is the only local infrastructure dependency.

## Current and future boundaries

### Webhooks — implemented initial boundary

The controller owns HTTP request and response semantics, including validation of the public envelope shape and the `202`, `409`, and `422` responses. The `Ironhold.Webhooks` context owns the receive use case, receipt-time assignment, persistence, and normalization of unique-index conflicts. `ReceivedWebhook` owns the persisted field and changeset constraints. This keeps Phoenix concerns out of the schema and database details out of the controller.

The current endpoint enforces the JSON media-type, raw-body-size, HMAC, timestamp, header/body ID, envelope-shape, field-length, and duplicate-ID boundaries before or during persistence. It accepts and stores the envelope only; downstream event processing remains pending.

### Security

[ADR 0003](adr/0003-signed-webhook-verification.md) defines the versioned HMAC contract, and [ADR 0004](adr/0004-webhook-authentication-policy.md) defines the operational policy now enforced by the endpoint. Production requires `IRONHOLD_WEBHOOK_SIGNING_SECRET` with at least 32 bytes. Replay protection, used-nonce or signature storage, rotation and multiple simultaneous secrets, and rate limiting remain pending.

### Audit

Will record security-relevant decisions and webhook processing outcomes with deliberate retention and access policies. Logging alone will not be treated as a complete audit trail.

### Observability

Ingestion emits accepted and rejected Telemetry events, with counters for accepted requests and bounded rejection reasons. Authentication separately emits `[:ironhold, :webhooks, :authentication, :verified]`, `[:ironhold, :webhooks, :authentication, :rejected]`, and `[:ironhold, :webhooks, :authentication, :identifier_mismatch]`. Each authentication event carries only `%{count: 1}` and empty metadata. Reporters, traces, alerts, service-level signals, and an operational dashboard remain future work.

## Dependency direction

The HTTP layer calls the `Ironhold.Webhooks` context rather than persisting schemas directly. The context may use the repository and schema, while neither depends on Phoenix. Future security and audit policy should preserve this direction and remain behind the code that owns each use case.

## Security posture

The webhook ingestion endpoint authenticates the sender's possession of the configured shared secret and verifies the integrity and bounded age of the exact received body. This does not prevent replay inside the accepted time window or make the payload safe for downstream processing. Ironhold does not yet store used nonces or signatures, rotate or overlap secrets, rate-limit ingestion, maintain a complete audit trail, or provide an operational dashboard.

This receiver boundary also does not establish end-to-end production delivery. Tidewake's Req adapter remains inactive, and real HTTP delivery, retries, backoff, response-size controls, and Tidewake-side SSRF protection remain pending there.
