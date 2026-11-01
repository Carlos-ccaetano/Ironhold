# Webhook ingestion API

Ironhold exposes an authenticated receiving boundary for requests that follow the Tidewake webhook contract. Tidewake implements secure outbound HTTP delivery and bounded automatic retries, while Ironhold authenticates and records accepted event envelopes. These implemented capabilities do not imply that the applications are deployed together as a production integration.

## Receive a webhook

```http
POST /api/webhooks
Content-Type: application/json
Tidewake-Id: evt_123
Tidewake-Timestamp: <unix_timestamp>
Tidewake-Signature: v1=<64_lowercase_hex_characters>
```

```json
{
  "id": "evt_123",
  "type": "order.created",
  "data": {
    "order_id": "123",
    "status": "created"
  }
}
```

The request body must be a JSON object with these fields:

- `id` is a non-empty string of at most 255 characters that uniquely identifies the event. Ironhold uses it as an idempotency key: an identical freshly signed retry can be acknowledged, while reuse with different event content is rejected.
- `type` is a non-empty string of at most 255 characters that identifies the event kind.
- `data` is a JSON object containing the event payload. Its shape depends on `type`.

The request must contain exactly one `Content-Type` header with the `application/json` media type. Media-type parameters such as `charset=utf-8` are allowed. A missing, duplicate, ambiguous, or incompatible content type returns `415 Unsupported Media Type` with the stable detail `content type must be application/json`.

The raw request body may contain at most `262_144` bytes. A body at that exact limit is accepted; a larger body returns `413 Payload Too Large` with the stable detail `request body exceeds the 262144-byte limit`.

## Authentication

The request must contain exactly one value for each signing header:

- `Tidewake-Id` is the event ID and must match the decoded JSON `id` exactly.
- `Tidewake-Timestamp` is a Unix timestamp in decimal seconds containing only ASCII digits.
- `Tidewake-Signature` is `v1=` followed by a 64-character lowercase hexadecimal HMAC-SHA256 digest.

The canonical version 1 message is the exact byte concatenation:

```text
v1.<event_id>.<timestamp>.<exact_body_bytes>
```

Ironhold calculates HMAC-SHA256 over this message using the configured shared secret. The body portion is the raw request body exactly as received: it is not decoded, normalized, or re-encoded before verification. A timestamp is accepted when it is at most 300 seconds in the past or 30 seconds in the future, with both limits inclusive.

Production reads the shared secret from `IRONHOLD_WEBHOOK_SIGNING_SECRET` and refuses to start when the value is absent or shorter than 32 bytes. The secret, signature, and raw body are not persisted or included in authentication Telemetry.

The request boundary runs in this order:

1. validate the JSON media type, returning `415` before authentication when invalid;
2. require exactly one value for each signing header;
3. read the raw body with its size limit, returning `413` before decoding or persistence when exceeded;
4. verify the timestamp and HMAC over the raw bytes;
5. decode the same authenticated bytes as JSON;
6. require `Tidewake-Id` to match the decoded body `id` exactly;
7. derive replay metadata from the already validated signature and authenticated timestamp;
8. validate the envelope, then atomically persist its replay claim and received webhook.

## Replay protection and idempotency

An observer who captures a valid signed request could otherwise submit it repeatedly while its timestamp remains acceptable. [ADR 0005](../adr/0005-webhook-replay-protection.md) defines how Ironhold closes that replay window without treating every later Tidewake attempt as the same cryptographic event.

An exact replay reuses the same body, timestamp, and validated signature. Ironhold hashes the complete validated signature with a versioned domain separator and stores only the resulting 64-character lowercase SHA-256 fingerprint. The raw signature is not recoverable from this value. The claim also stores `expires_at`, calculated as the authenticated signing timestamp plus 300 seconds.

The public envelope shape is checked before persistence. The replay claim and `received_webhooks` row are then inserted in one PostgreSQL transaction. A unique index on the fingerprint decides concurrent exact replays: only one transaction can accept the claim. If webhook changeset validation or persistence fails, the claim insert rolls back.

A retry signed with a new timestamp has a new signature and fingerprint, so it is not an exact cryptographic replay. When its `event_id` already exists, Ironhold compares the authenticated envelope's `type` and decoded `data` with the stored event. If they are identical, Ironhold treats the request as an idempotent retry: it keeps the new replay claim, does not create another webhook, and returns the same generic `202 Accepted` response as the first request. Repeating that newly signed request exactly then reuses its committed fingerprint and returns `409 Conflict` as an exact replay.

If the new signature accompanies a different `type` or `data` under the same `event_id`, Ironhold treats the request as conflicting event-ID reuse. It returns the generic `409 Conflict` response and rolls back the provisional replay claim. In simple terms, event idempotency determines whether newly authenticated content may reuse an event ID, while replay protection determines whether the same authenticated signing attempt has already been processed.

## Responses

Ironhold returns `202 Accepted` after storing a valid webhook. A freshly signed retry whose `id`, `type`, and decoded `data` match that stored webhook receives the same status and body, without revealing whether this request inserted or reused the event:

```json
{
  "data": {
    "event_id": "evt_123",
    "status": "accepted"
  }
}
```

Ironhold returns `401 Unauthorized` for any authentication failure, including missing or ambiguous signing headers, invalid timestamps or signatures, missing configuration, and a header ID that does not match the body ID. All such failures use the same response:

```json
{"errors":[{"detail":"valid webhook signature required"}]}
```

Ironhold returns `422 Unprocessable Entity` when an authenticated request reaches normal envelope validation but does not satisfy its field and shape constraints:

```json
{
  "errors": [
    {
      "detail": "id, type, and data must be provided in the expected format"
    }
  ]
}
```

Ironhold returns `409 Conflict` for an exact replay and for a freshly signed request that reuses an accepted `id` with a different `type` or `data`. The public response deliberately does not distinguish the internal `:replay_detected` and `:duplicate_event` reasons. Neither case creates another stored webhook. An exact replay does not create another claim, and conflicting event-ID reuse rolls back its provisional claim:

```json
{
  "errors": [
    {
      "detail": "a webhook with this id has already been received"
    }
  ]
}
```

Accepted ingestion emits Telemetry. Validation, duplicate-ID, and unsupported-media-type rejections emit ingestion rejection Telemetry with bounded reasons. Authentication emits separate counters for these events:

- `[:ironhold, :webhooks, :authentication, :verified]` after successful HMAC and timestamp verification;
- `[:ironhold, :webhooks, :authentication, :rejected]` when the request is rejected before successful verification;
- `[:ironhold, :webhooks, :authentication, :identifier_mismatch]` when a verified header ID does not match the decoded body ID.

Each authentication event contains only `%{count: 1}` with empty metadata.

Replay protection emits these additional events:

- `[:ironhold, :webhooks, :replay, :claim_accepted]` with `%{count: 1}` and empty metadata after the transaction commits;
- `[:ironhold, :webhooks, :replay, :detected]` with `%{count: 1}` and empty metadata for an exact replay;
- `[:ironhold, :webhooks, :replay, :cleanup_completed]` with `count` and `duration`, plus `claims_removed` after a successful cleanup. Its metadata contains only `result` (`:ok` or `:error`) and `origin` (`:manual` or `:scheduled`).

An acknowledged idempotent retry additionally emits `[:ironhold, :webhooks, :ingestion, :idempotent_retry]` with `%{count: 1}` and empty metadata, only after its transaction commits. `IronholdWeb.Telemetry.metrics/0` exposes this as the untagged `ironhold.webhooks.ingestion.idempotent_retry.count` counter, alongside counters for accepted claims, detected replays, and completed cleanups, a sum of removed claims, and cleanup duration. Ironhold does not currently configure a metrics reporter, dashboard, or external alert.

## Expiration and cleanup

`Ironhold.Webhooks.ReplayCleanup` is part of the application supervision tree. It schedules the next cleanup after the current execution finishes, so executions do not overlap within one worker. Each run removes claims whose `expires_at` is less than or equal to its reference time in one database operation; repeated and multi-node executions are idempotent.

The default interval is five minutes and is configured with application configuration:

```elixir
config :ironhold, Ironhold.Webhooks.ReplayCleanup, interval: :timer.minutes(5)
```

Tests set the interval to `:infinity` and use the explicit `Ironhold.Webhooks.ReplayCleanup.run_now/2` operation. There is no environment variable for the interval today.

## Stored data boundary

The replay-claim table stores only the irreversible fingerprint, `expires_at`, and `inserted_at`. It does not store the signature, shared secret, complete headers, raw request body, request URL, or client IP. Those values are also excluded from replay Telemetry. The accepted webhook record separately stores the decoded `event_id`, `event_type`, `payload`, and receipt time as part of the ingestion contract.

## Demonstrate retry and replay behavior locally

With PostgreSQL available through the repository's Compose service, run the focused HTTP test:

```sh
docker compose up -d postgres
MIX_ENV=test mix test test/ironhold_web/controllers/webhook_controller_test.exs
```

The test covers an initial `202`, a second `202` for the identical envelope with a fresh timestamp and signature, and a generic `409` when that second signed request is replayed exactly. PostgreSQL retains one received webhook and two replay claims for the two accepted signing attempts. The test configuration supplies a non-production signing secret; the command does not print it.

## Current limitations

This boundary authenticates requests, rejects exact replays, and acknowledges freshly signed retries of an identical stored envelope, but it does not process event-specific payloads or provide delivery status lookup. It does not rotate or accept multiple simultaneous secrets, rate-limit ingestion, provide administrative authentication, maintain a complete audit trail, export alerts, define deployment, or provide an operational dashboard.

A joint production deployment of Tidewake and Ironhold has not been demonstrated. Tidewake implements secure outbound HTTP delivery and bounded automatic retries, plus [authenticated admin-only manual retry POST and paginated administrative audit GET](https://github.com/Carlos-ccaetano/Tidewake/blob/main/docs/api/manual-retries.md). Its scheduler does not yet interpret `Retry-After` received from webhook receivers. Ironhold's ingestion rate limiting, signing-secret rotation, broader operational auditing and retention, administrative authentication, an operational API or UI and dashboard, external metrics reporting and alerts, and production validation/deployment remain pending.
