# ADR 0003: Signed webhook verification

- Status: Accepted
- Date: 2026-09-30

## Context

Ironhold receives webhook envelopes through `POST /api/webhooks`. The endpoint currently enforces JSON media type and raw-body size boundaries, then `Plug.Parsers` decodes the request before the controller validates and persists it. This protects the HTTP boundary but does not authenticate the sender or prove that the persisted envelope came from bytes signed by Tidewake.

Tidewake ADR 0012 defines a future shared-secret protocol over the exact serialized body sent to the delivery adapter. Ironhold must adopt that protocol without reconstructing JSON or changing any wire representation. This decision records the receiver contract and verification order before implementation. It does not claim that signed ingestion, secret configuration, timestamp validation, or replay protection exists today.

## Decision

### Wire contract

Each signed request contains exactly one value for each of these headers:

```http
Tidewake-Id: <event_id>
Tidewake-Timestamp: <timestamp>
Tidewake-Signature: v1=<hex_digest>
```

HTTP header names are case-insensitive. Ironhold must therefore treat names such as `Tidewake-Id` and `tidewake-id` as the same field. The casing shown above is preferred but is not part of verification. Missing, duplicated, or otherwise ambiguous signing headers are invalid.

`Tidewake-Id` is Tidewake's event `external_id`. It is the same value represented as `id` in the JSON envelope and persisted by Ironhold as `event_id`; it is not a Tidewake internal event, delivery, or attempt ID.

`Tidewake-Timestamp` is the request signing time represented as base-10 Unix seconds with ASCII decimal digits and no sign, fractional part, surrounding whitespace, or other formatting.

`Tidewake-Signature` is the lowercase hexadecimal representation of an HMAC-SHA256 digest prefixed with `v1=`. Version 1 therefore has exactly 64 lowercase hexadecimal digest characters after the prefix. Any other version is unknown and invalid unless a later decision explicitly adds it.

The version 1 canonical input is the byte concatenation:

```text
v1.<event_id>.<timestamp>.<exact_body_bytes>
```

Equivalently:

```elixir
<<"v1.", event_id::binary, ".", timestamp::binary, ".", body::binary>>
```

The periods are literal ASCII `.` bytes. `event_id` and `timestamp` are the exact header values. `body` is the raw request body exactly as received. Ironhold must not add a newline or perform whitespace normalization, character-set conversion, JSON normalization, decompression, parsing, or re-encoding when constructing the canonical input.

Ironhold computes HMAC-SHA256 with the configured shared secret, encodes the digest as lowercase hexadecimal, prepends `v1=`, and compares the complete expected and presented signature values in constant time. The comparison must operate on equal-length binaries using a constant-time primitive; ordinary string equality must not validate signatures.

### Verification order

After the existing HTTP media-type boundary admits the request, signed ingestion must proceed in this order:

1. Require exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` value and validate their non-secret structural formats, including the supported `v1=` prefix and hexadecimal signature shape.
2. Validate that `Tidewake-Timestamp` is the required unsigned decimal Unix-seconds representation and parse it without permissive coercion.
3. Verify that the timestamp is inside a configured temporal acceptance window, rejecting values that are too old or unreasonably far in the future.
4. Read the bounded raw request body and calculate HMAC-SHA256 over the canonical input containing those exact bytes.
5. Compare the complete expected and presented signatures in constant time.
6. Only after successful verification, decode the same raw bytes as JSON, apply the existing envelope validation, and persist the accepted webhook.
7. Add explicit replay protection in a later stage without changing the version 1 canonical input.

No controller or context operation may run for an authentication failure, and no `received_webhooks` row may be created. The existing unique `event_id` constraint provides persistence idempotency for duplicates, but it is not a complete replay defense: it does not authenticate requests, enforce timestamp use, or define how valid repeated signatures are rejected. Replay protection remains a separate follow-up.

### Raw-body boundary

Ironhold must preserve the raw body bytes before the JSON parser decodes them. The currently decoded params map is insufficient because JSON key order, whitespace, escaping, and equivalent value representations can change when parsed and encoded again. Verification against reconstructed JSON would therefore authenticate bytes different from those Tidewake signed.

The future implementation must place verification at a pre-decode boundary, or use a parser body-reading boundary that completes verification before passing the same binary to the JSON decoder. The body must still obey ADR 0002's exact `262_144`-byte limit while it is read. Raw bytes are retained only as long as needed for verification and subsequent decoding; this ADR does not authorize a second body read, re-encoding, or raw-body persistence.

### Failure behavior

Verification fails closed when any of the following occurs:

- a required signing header is absent;
- a signing header is duplicated or ambiguous;
- the signature version is unknown;
- the timestamp is malformed, expired, or outside the permitted future skew;
- the signature encoding or length is malformed;
- the signature does not match;
- the signing-secret configuration is missing or invalid.

All of these failures stop processing before JSON decoding and persistence. Missing or invalid secret configuration must never bypass verification or allow unsigned ingestion.

The public authentication failure response must be stable and generic. It must not reveal whether a secret was missing, which header or signature component failed, whether the timestamp was outside the window, whether the expected and presented signatures had different lengths, or whether signature comparison failed. Existing non-secret HTTP boundary responses such as `415` and `413` remain governed by ADR 0002.

### Secret and observability boundary

The shared secret comes only from trusted application or deployment configuration. It must not come from the request, payload, database, or persisted webhook record. Rotation, simultaneous secrets, and key identifiers require a later decision.

The configured secret, presented or expected signature, complete signing headers, and raw or decoded request body must never appear in logs or Telemetry measurements, metadata, tags, event names, or exception details. Authentication observability may use only bounded, non-sensitive outcomes that cannot reconstruct request content or signing material. The accepted decoded event fields continue to follow the existing persistence contract, but this decision adds no persistence for the raw body, secret, signature, or signing headers.

### Shared test vector

This is the exact vector from Tidewake ADR 0012. It uses an obviously non-production secret and a fixed timestamp. The body is the exact UTF-8 byte sequence shown, with no trailing newline.

```text
secret:    tidewake_test_secret_not_for_production
event_id:  evt_test_123
timestamp: 1700000000
body:      {"data":{"ok":true},"id":"evt_test_123","type":"test.ping"}
```

The canonical input is:

```text
v1.evt_test_123.1700000000.{"data":{"ok":true},"id":"evt_test_123","type":"test.ping"}
```

The expected `Tidewake-Signature` value is:

```text
v1=3323d158355377e1b2d7515e31a40365a48ff11d427a8a8f62cfda1e4bf92128
```

The value is generated with:

```elixir
secret = "tidewake_test_secret_not_for_production"
event_id = "evt_test_123"
timestamp = "1700000000"
body = ~S({"data":{"ok":true},"id":"evt_test_123","type":"test.ping"})

canonical = IO.iodata_to_binary(["v1.", event_id, ".", timestamp, ".", body])

signature =
  :crypto.mac(:hmac, :sha256, secret, canonical)
  |> Base.encode16(case: :lower)
  |> then(&("v1=" <> &1))
```

The digest was validated by Tidewake with Elixir `:crypto.mac/4` and independently reproduced with .NET `HMACSHA256` over the same UTF-8 bytes. Ironhold's future verification tests must reproduce this value before accepting the implementation.

## Consequences

### Positive

- Ironhold can verify sender possession of the shared secret and integrity of the exact received body bytes.
- The receiver contract matches Tidewake's header names, canonical input, algorithm, encoding, version prefix, and test vector.
- Timestamp validation bounds how long a captured signed request remains eligible for acceptance.
- Verification precedes decoding and persistence, so unauthenticated content cannot reach the webhook context.
- Generic failures and strict observability boundaries avoid exposing signing details through response or operational surfaces.

### Negative

- The current parser pipeline cannot verify reconstructed params and will need a raw-body-aware pre-decode boundary.
- Raw bytes must be held transiently through verification and then supplied unchanged to the decoder.
- Clock skew can reject an authentic request, so deployments require reliable clocks and a deliberately configured window.
- A single configured secret does not support seamless rotation or sender-specific keys.
- Timestamp and HMAC verification alone do not prevent replay inside the accepted window.

## Alternatives considered

### Verify after decoding and re-encoding JSON

Rejected because equivalent JSON can have different byte representations. Re-encoding would not necessarily reproduce the body Tidewake signed.

### Compare signatures with ordinary equality

Rejected because secret-dependent comparison timing is unnecessary when a constant-time primitive is available.

### Persist before verification and remove failures later

Rejected because untrusted content would cross the persistence boundary and cleanup could fail or become observable.

### Treat the unique event ID as replay protection

Rejected because database idempotency does not authenticate the request or provide an explicit time-bounded replay policy.

## Deliberately deferred

- HMAC verification implementation;
- raw-body capture or parser integration;
- signing-secret configuration and production provisioning;
- the exact temporal-window duration and allowed clock skew;
- the generic authentication response status and body;
- replay protection and replay-state storage;
- secret rotation, overlapping secrets, and key identifiers;
- multiple senders or per-sender secrets;
- logs, metrics reporters, dashboards, or alerts for signed ingestion.

## Follow-up

Implement the raw-body verification boundary in a separate change with tests for the shared vector, all fail-closed cases, exact verification order, constant-time comparison, no persistence before successful verification, parser handoff of the same bytes, and non-disclosure in responses, logs, and Telemetry.

Define the temporal-window value, stable public authentication response, secret provisioning, and replay-protection semantics before signed ingestion is enabled in production.
