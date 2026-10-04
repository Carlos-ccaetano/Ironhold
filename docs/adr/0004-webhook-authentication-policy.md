# ADR 0004: Webhook authentication policy

- Status: Accepted
- Date: 2026-10-04

## Context

[ADR 0003](0003-signed-webhook-verification.md) defines the Tidewake HMAC wire contract but defers the temporal window, public failure response, and production secret policy. Those values and the observable order of checks must be fixed before implementation so authentication can be tested without weakening the HTTP boundaries in [ADR 0002](0002-webhook-http-boundaries.md). This ADR refines ADR 0003 where it specifies that order.

## Decision

### Request boundaries and authentication order

Ironhold applies the following order to `POST /api/webhooks`:

1. Enforce the existing JSON media-type boundary. An incompatible or missing media type returns `415 Unsupported Media Type` before authentication.
2. Read the raw body under the existing inclusive `262_144`-byte limit. A larger payload returns the existing `413 Payload Too Large` response.
3. Authenticate the request against the raw body bytes before decoding JSON.
4. After the HMAC succeeds, decode those same bytes and require `Tidewake-Id` to equal the body object's `id` value exactly.
5. Apply the existing envelope validation and persist only after authentication succeeds.

Authentication requires exactly one value for each `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header. A missing, duplicated, combined, or otherwise ambiguous value is invalid.

`Tidewake-Timestamp` must contain only the decimal ASCII representation of an integer Unix timestamp in seconds. Signs, fractions, whitespace, and permissive numeric coercion are invalid. The implementation samples the current Unix second once for the request and accepts the timestamp only when:

```text
now - 300 <= timestamp <= now + 30
```

Both limits are inclusive. A timestamp exactly 300 seconds in the past or 30 seconds in the future is accepted; one second beyond either limit is rejected.

The version 1 signature is calculated over the exact raw body bytes using the canonical input and HMAC-SHA256 rules from ADR 0003. JSON must not be normalized, decoded, or re-encoded before this calculation. The complete expected and presented signature values must be compared with an equal-length constant-time primitive. Ordinary string equality is not acceptable.

After signature verification, `Tidewake-Id` must match the decoded body's string `id` exactly, without case folding, trimming, Unicode normalization, or coercion. A missing, non-string, or different `id` fails authentication. No authentication failure may reach persistence.

### Failure response

Every authentication failure returns `401 Unauthorized` with this response:

```json
{"errors":[{"detail":"valid webhook signature required"}]}
```

The same response covers missing or duplicated headers, malformed timestamps or signatures, timestamps outside the window, unsupported signature versions, signature mismatches, body ID mismatches, and missing or invalid signing-secret configuration. Different failures intentionally produce no public distinction so the endpoint cannot be used as an oracle for header structure, clock-window position, signature correctness, or server configuration.

The `415` and `413` responses remain the non-authentication boundary responses defined by ADR 0002 and must not be replaced by this `401` response.

### Secret and observability policy

The shared secret is configured through `IRONHOLD_WEBHOOK_SIGNING_SECRET`. Production requires an explicit value of at least 32 bytes; a missing, empty, or shorter value must prevent the application from starting.

The configured secret, presented or expected signature, and raw request body must never appear in logs, exception details, or Telemetry measurements, metadata, tags, or event names. Authentication observability may expose only bounded, non-sensitive outcomes.

### Replay protection

The timestamp window limits the age of an acceptable request but does not prevent reuse inside that window. Replay protection and any replay-state persistence remain a separate decision and implementation stage.

## Consequences

- Boundary timestamps and failures have deterministic acceptance criteria and response behavior.
- HMAC verification authenticates the bytes sent by Tidewake rather than reconstructed JSON.
- Authentication completes before persistence while preserving the existing `415` and `413` contracts.
- Operators receive less failure detail by design; diagnostics must remain bounded and non-sensitive.
- Deployments require a reliable clock and an explicit production secret.

## Out of scope

This ADR does not implement configuration, raw-body capture, plugs, controller changes, HMAC verification, tests, replay protection, secret rotation, or multiple simultaneous secrets.
