# Webhook ingestion API

Ironhold exposes an authenticated receiving boundary for requests that follow the Tidewake webhook contract. Ironhold authenticates and records accepted event envelopes; this does not imply that Tidewake's production HTTP transport is active.

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

- `id` is a non-empty string of at most 255 characters that uniquely identifies the event. Ironhold uses it to reject duplicate deliveries.
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
7. validate the envelope and persist it.

## Responses

Ironhold returns `202 Accepted` after storing a valid webhook:

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

Ironhold returns `409 Conflict` when a webhook with the same `id` has already been accepted. Duplicate requests do not create another stored webhook:

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

## Current limitations

This boundary authenticates requests but does not process event-specific payloads or provide delivery status lookup. It does not yet provide replay protection, store used nonces or signatures, rotate or accept multiple simultaneous secrets, rate-limit ingestion, maintain a complete audit trail, or provide an operational dashboard.

This is not an end-to-end production integration with Tidewake. Tidewake's Req adapter remains inactive, so real HTTP delivery, retries, backoff, and Tidewake-side SSRF protection are still pending.
