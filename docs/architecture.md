# Architecture

## Context

Tidewake owns reliable webhook delivery. Ironhold is its companion service and will own the receiving boundary: accepting requests, applying security policy, and retaining an auditable account of processing.

The authenticated receiving boundary is implemented: Ironhold authenticates webhook envelopes received through `POST /api/webhooks`, rejects exact replay of already accepted signing material, and persists accepted envelopes in PostgreSQL. Abuse controls, complete auditing, external alerting, administrative authentication, and an operational interface remain later boundaries rather than implied properties of ingestion.

## Current runtime

An HTTP request reaches `IronholdWeb.Endpoint`, where `IronholdWeb.Plugs.RequireJsonContentType` requires a single `application/json` media type and returns `415 Unsupported Media Type` otherwise. After endpoint Telemetry starts, `IronholdWeb.Plugs.RequireWebhookSignature` requires exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header, reads at most `262_144` raw body bytes, and returns the stable `413 Payload Too Large` response when that limit is exceeded.

The signature boundary verifies HMAC-SHA256 over `v1.<event_id>.<timestamp>.<exact_body_bytes>`. It accepts timestamps from 300 seconds in the past through 30 seconds in the future, with both limits inclusive. On success, the exact authenticated bytes are retained only in `conn.private`; `Plug.Parsers` receives those same bytes through `IronholdWeb.WebhookBodyReader` and decodes them once. The router then dispatches to `IronholdWeb.WebhookController.create/2`, where `IronholdWeb.Plugs.RequireMatchingWebhookId` requires the authenticated header ID to equal the decoded body `id` exactly. Only then does it derive a replay fingerprint from the validated signature and calculate `expires_at` from the authenticated timestamp using the same 300-second past-age window. The raw body and authenticated timestamp are removed from `conn.private`; only the fingerprint and expiration continue to the controller.

A valid envelope contains non-empty string `id` and `type` fields of at most 255 characters plus an object-valued `data` field. The controller maps those public names to `event_id`, `event_type`, and `payload`, then delegates persistence to `Ironhold.Webhooks`.

The context supplies `received_at` and uses `Ecto.Multi` to insert an `Ironhold.Webhooks.WebhookReplayClaim` before an `Ironhold.Webhooks.ReceivedWebhook` in one transaction. `webhook_replay_claims` stores only a unique 64-character lowercase SHA-256 fingerprint, `expires_at`, and `inserted_at`; its expiration index supports cleanup. `received_webhooks` stores `event_id`, `event_type`, `payload`, and `received_at`, with a unique database index on `event_id`. A webhook failure rolls back the provisional claim.

The fingerprint constraint classifies an identical signature as `:replay_detected` and returns the generic `409 Conflict`. A differently signed request with an already stored `event_id` is compared with the persisted envelope. Identical `event_type` and `payload` values are acknowledged idempotently with the same generic `202 Accepted` response while retaining the fresh replay claim and the single webhook row. Different content is classified as `:duplicate_event`, returns the same generic `409 Conflict`, and rolls back the new claim. Invalid input that reaches envelope validation returns `422 Unprocessable Entity`. Authentication failures return the same generic `401 Unauthorized` before replay state or webhook persistence.

`Ironhold.Application` supervises the Telemetry supervisor, Ecto repository, `Ironhold.Webhooks.ReplayCleanup`, and endpoint. Replay cleanup defaults to a five-minute application-config interval, schedules its next run after completing the current one, and removes all claims with `expires_at` less than or equal to its reference time in one database operation. PostgreSQL is the only local infrastructure dependency.

## Current and future boundaries

### Webhooks — implemented authenticated and replay-protected boundary

The controller owns HTTP request and response semantics, including validation of the public envelope shape and the `202`, `409`, and `422` responses. The `Ironhold.Webhooks` context owns atomic authenticated ingestion, receipt-time assignment, pruning, and normalization of the two unique-index conflicts. `ReceivedWebhook` and `WebhookReplayClaim` own their persisted field and changeset constraints. This keeps Phoenix concerns out of the schemas and database details out of the controller.

The current endpoint enforces the JSON media-type, raw-body-size, HMAC, timestamp, header/body ID, exact-replay, envelope-shape, field-length, and duplicate-ID boundaries before or during persistence. It accepts and stores the envelope only; downstream event processing remains pending.

### Security

[ADR 0003](adr/0003-signed-webhook-verification.md) defines the versioned HMAC contract, [ADR 0004](adr/0004-webhook-authentication-policy.md) defines the authentication policy, and [ADR 0005](adr/0005-webhook-replay-protection.md) defines the replay policy now enforced by the endpoint. Production requires `IRONHOLD_WEBHOOK_SIGNING_SECRET` with at least 32 bytes. Only an irreversible digest of the validated signature is retained as replay state; the signature, secret, complete headers, raw body, URL, and client IP are not replay-claim fields. Secret rotation, multiple simultaneous keys, and rate limiting remain pending.

### Audit

Will record security-relevant decisions and webhook processing outcomes with deliberate retention and access policies. Logging alone will not be treated as a complete audit trail.

### Observability

Ingestion emits accepted and rejected Telemetry events, with counters for accepted requests and bounded rejection reasons. Authentication separately emits `[:ironhold, :webhooks, :authentication, :verified]`, `[:ironhold, :webhooks, :authentication, :rejected]`, and `[:ironhold, :webhooks, :authentication, :identifier_mismatch]`. Replay protection emits `[:ironhold, :webhooks, :replay, :claim_accepted]`, `[:ironhold, :webhooks, :replay, :detected]`, and `[:ironhold, :webhooks, :replay, :cleanup_completed]`. Cleanup reports count, duration, removed rows on success, result, and manual or scheduled origin. Metadata remains bounded and contains no signature, fingerprint, secret, event ID, URL, payload, headers, IP, body, or stack trace. Metrics are declared in `IronholdWeb.Telemetry`; reporters, traces, external alerts, service-level signals, and an operational dashboard remain future work.

## Dependency direction

The HTTP layer calls the `Ironhold.Webhooks` context rather than persisting schemas directly. The context may use the repository and schema, while neither depends on Phoenix. Future security and audit policy should preserve this direction and remain behind the code that owns each use case.

## Security posture

The webhook ingestion endpoint authenticates the sender's possession of the configured shared secret, verifies the integrity and bounded age of the exact received body, and rejects reuse of an already accepted signature while preserving `event_id` idempotency for newly signed attempts. It does not make the payload safe for downstream processing. Ironhold does not rotate or overlap secrets, rate-limit ingestion, provide administrative authentication, maintain a complete audit trail, export external alerts, define deployment, or provide an operational dashboard.

Tidewake's secure Req-based outbound transport and bounded automatic retries are implemented, and Ironhold's idempotent acknowledgement contract accepts an identical envelope with fresh signing material while exact replay remains a `409 Conflict`. This still does not establish an end-to-end production deployment. Manual retry and its audit record, `Retry-After` support, an operational interface or dashboard, and deployment remain pending.
