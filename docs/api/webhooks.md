# Webhook ingestion API

Ironhold exposes an initial receiving boundary for webhook events sent by Tidewake. Tidewake is responsible for delivering events, while Ironhold accepts and records the event envelope for later security and processing stages.

## Receive a webhook

```http
POST /api/webhooks
Content-Type: application/json
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

The raw request body may contain at most `262_144` bytes. A body at that exact limit is accepted; a larger body returns `413 Payload Too Large` with the stable detail `request body exceeds the 262144-byte limit`. Both HTTP boundary checks run before persistence.

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

Ironhold returns `422 Unprocessable Entity` when the request does not contain a valid `id`, `type`, and object-valued `data` field:

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

Accepted ingestion emits Telemetry. Validation, duplicate-ID, and unsupported-media-type rejections emit rejection Telemetry with bounded reasons.

## Current limitations

This contract only accepts and stores webhook envelopes. It does not authenticate senders, process event-specific payloads, or provide delivery status lookup.

[ADR 0003](../adr/0003-signed-webhook-verification.md) defines the future HMAC signature and timestamp contract, but it is not implemented. Ironhold does not yet verify signatures, validate timestamps, preserve raw body bytes for HMAC, prevent replay, rotate secrets, rate-limit ingestion, or provide an operational dashboard.
