# ADR 0002: Webhook HTTP boundaries

- Status: Accepted
- Date: 2026-09-29

## Context

`POST /api/webhooks` is a public ingestion boundary. Without explicit media-type and body-size rules, requests can consume avoidable memory during parsing, send oversized values toward persistence, and expose behavior that clients cannot handle consistently.

These boundaries must be decided before implementation so the HTTP contract, parser behavior, persistence guarantees, and observability rules can be reviewed together. This ADR defines the intended behavior; it does not claim that the limits are already enforced.

## Decision

The endpoint will accept only requests whose `Content-Type` media type is `application/json`. Valid media-type parameters are allowed, including `application/json; charset=utf-8`. A missing `Content-Type` header or any other media type will be rejected with `415 Unsupported Media Type`.

The maximum raw request-body size will be 256 KiB, exactly `262_144` bytes. A body of `262_144` bytes is within the boundary; any larger body will be rejected with `413 Payload Too Large`. The raw-byte limit must be enforced before JSON decoding and before any persistence work begins.

The error responses will preserve the endpoint's existing public error envelope:

~~~json
{
  "errors": [
    {
      "detail": "content type must be application/json"
    }
  ]
}
~~~

The response above is used for `415`. The stable `413` response is:

~~~json
{
  "errors": [
    {
      "detail": "request body exceeds the 262144-byte limit"
    }
  ]
}
~~~

Neither response may include the rejected body or any excerpt from it. No part of a rejected body may be written to application logs or attached to Telemetry events or metadata.

A request rejected for its content type or raw size must not create a `received_webhooks` record. After the boundary checks and JSON decoding succeed, the decoded request body must still be a JSON object and remains subject to the existing envelope validation. In particular, the `data` payload must remain a JSON object; syntactically valid JSON of another shape is invalid.

## Consequences

- Clients receive deterministic `415` and `413` responses using the same `errors` shape as current API failures.
- Applying the byte limit before decoding bounds parser memory use and prevents oversized requests from reaching the database.
- The rules make the public ingestion boundary explicit without weakening existing payload validation.
- Rejected content cannot leak through responses, logs, or Telemetry.
- HMAC verification, timestamp validation, and replay protection remain outside this decision and must be designed separately.
