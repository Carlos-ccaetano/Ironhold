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

- `id` is a non-empty string that uniquely identifies the event. Ironhold uses it to reject duplicate deliveries.
- `type` is a non-empty string that identifies the event kind.
- `data` is a JSON object containing the event payload. Its shape depends on `type`.

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

## Current limitations

This first contract only accepts and stores webhook envelopes. It does not authenticate senders, process event-specific payloads, or provide delivery status lookup.

Signature and timestamp headers will be defined in a later contract. HMAC validation, timestamp validation, replay protection, and rate limiting are intentionally not implemented yet.
