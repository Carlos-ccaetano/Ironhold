# ADR 0005: Webhook replay protection policy

- Status: Accepted
- Date: 2026-10-14

## Context

[ADR 0003](0003-signed-webhook-verification.md) defines the signed Tidewake webhook contract, and [ADR 0004](0004-webhook-authentication-policy.md) defines the temporal acceptance window and generic authentication failure behavior. Ironhold now verifies the HMAC and timestamp before decoding and persisting a webhook, but an authenticated request can still be repeated while its timestamp remains inside the accepted window.

The unique `received_webhooks.event_id` constraint provides persistence idempotency. It prevents two webhook rows from representing the same event, but it does not distinguish an exact reuse of authenticated signing material from a legitimate future Tidewake retry that uses the same event ID with a new timestamp and signature. Timestamp validation alone also cannot make that distinction because every replay within the accepted window has a valid timestamp.

Replay protection needs a durable, concurrency-safe decision that preserves this distinction, does not retain signing material, and cannot acknowledge a claim unless the corresponding webhook is persisted.

## Decision

### Authentication and replay order

The existing HTTP media-type and bounded-body checks continue to run first. Ironhold must then complete HMAC verification and temporal-window validation before performing any replay lookup or claim. Unauthenticated, malformed, expired, or too-far-in-the-future requests must not create replay state or reveal whether matching state exists.

After authentication succeeds, Ironhold derives a replay fingerprint from the complete signature value that has already been validated. The fingerprint is SHA-256 over a fixed, versioned Ironhold domain separator followed by the exact validated signature value. The persisted value is the 32-byte digest, not a hexadecimal copy of the signature. Including the validated signature's `v1=` prefix in the hashed input keeps the fingerprint tied to the signature version without storing the header itself.

An exact repetition of the same authenticated envelope presents the same validated signature and therefore the same fingerprint. Ironhold must reject the repetition while its replay claim is active.

A Tidewake retry that signs the event again with a new timestamp produces a new signature and a new fingerprint. It is not a cryptographic replay, even when its `event_id`, event type, and payload are unchanged. That request proceeds to the existing event-id idempotency check. If the event was already persisted, the request is a duplicate event ID rather than a replay.

The authenticated timestamp and signature must be made available only as bounded internal values for the replay decision after successful verification. The configured secret, raw or expected signature, complete signing headers, and raw request body must not be persisted.

### Durable replay claims

Replay claims are stored in PostgreSQL. Each claim contains only:

- the irreversible fingerprint;
- the claim expiration time;
- ordinary database timestamps needed to operate and clean the table.

The fingerprint has a unique database constraint. Concurrent requests carrying the same authenticated signature race on that constraint: one transaction may claim the fingerprint, while every conflicting transaction is classified internally as a replay. Application-level check-then-insert logic is not the concurrency boundary.

The claim expires when the authenticated request leaves ADR 0004's temporal acceptance window. For a validated signing timestamp, the claim remains active through the inclusive `signed_at + 300 seconds` boundary and is expired only after the current time passes that boundary. Once the claim has expired, the original request is already rejected by temporal validation, so deleting the row cannot make an old signature acceptable again.

### Transaction model

Creating the replay claim and inserting the `received_webhooks` row must occur in one PostgreSQL transaction owned by the webhook receive use case. The transaction attempts the replay claim before inserting the webhook so an exact concurrent repetition is classified as replay.

If webhook validation or persistence fails for any reason, including a duplicate `event_id`, the transaction must roll back the replay claim. A database or application failure must not consume signing material for a webhook that Ironhold did not persist. Retrying that delivery with the same authenticated request can therefore succeed after a transient persistence failure.

The two database constraints retain separate meanings:

- a replay-fingerprint conflict means the same validated signature was already accepted and claimed;
- an `event_id` conflict means a separately authenticated request refers to an event already persisted.

An exact replay of an accepted webhook encounters the fingerprint constraint first. A freshly signed Tidewake retry has a different fingerprint, reaches the event-id constraint, and rolls back its provisional claim when the duplicate event ID is reported. This ordering preserves future Tidewake retry behavior without weakening event idempotency.

### Failure behavior and observability

Replay and duplicate-event outcomes use the same generic public conflict response so callers cannot use the response body to determine whether a particular signature has been seen. The existing `409 Conflict` duplicate response is the public baseline; it must not include the fingerprint, signature, timestamp, event existence details, or database constraint names.

Internally, replay and duplicate `event_id` remain distinct bounded reasons. Telemetry and structured diagnostics may count those outcomes separately, but must not include the fingerprint, signature, secret, complete headers, raw body, decoded payload, or event ID as measurements or metadata.

### Expired-claim cleanup

A named process in `Ironhold.Application`'s supervision tree periodically removes expired claims from PostgreSQL in bounded batches. Cleanup is maintenance, not part of request acceptance: delayed cleanup may retain unusable rows longer, but must not delete an active claim or allow a temporally valid replay.

The cleanup process must be safe to run on more than one application node. Database predicates define expiration and deletion eligibility; correctness must not depend on one process being globally unique. The interval, batch size, and operational metrics will be selected during implementation and exposed through bounded configuration where needed.

Ironhold will not add Oban solely to schedule this cleanup. A small supervised process and PostgreSQL are sufficient for this single periodic responsibility. A durable job system can be reconsidered if the application later acquires broader background-job requirements.

## Security and privacy consequences

- HMAC and timestamp validation remain prerequisites for replay-state access, preventing unauthenticated requests from filling the claim table or probing it.
- PostgreSQL provides durable, multi-node replay state and atomicity with webhook persistence.
- Only a one-way digest of the validated signature is retained. The signature, shared secret, complete signing headers, and request body are not replay-state fields.
- A fingerprint is still security-sensitive correlation data. It must not be returned publicly or emitted to logs and Telemetry.
- Unique constraints, rather than process-local coordination, define the result of concurrent claims.
- Expiration bounds replay-state retention to the period in which the corresponding signed request could otherwise be accepted, plus cleanup delay.
- A newly signed retry remains eligible for normal idempotency handling; replay protection does not turn `event_id` into signing material or prevent Tidewake from retrying with a new timestamp.

## Alternatives considered

### Store claims in ETS

Rejected because ETS state is lost on restart, is local to one BEAM node, and cannot participate in the PostgreSQL transaction that persists the webhook. It would permit replays after restart or across nodes and could retain a claim when webhook persistence fails.

### Store the validated signature

Rejected because the raw signature is unnecessary signing material. A fixed-size irreversible fingerprint supports equality and uniqueness without retaining the credential presented by the caller.

### Rely only on the unique event ID

Rejected because event idempotency and cryptographic replay answer different questions. `event_id` cannot distinguish an exact repeated signature from a future Tidewake retry signed at a new time, and treating every retry as replay would erase useful internal semantics.

### Rely only on the timestamp window

Rejected because a captured authenticated request can be submitted repeatedly during the accepted window. Temporal validation limits replay duration but does not enforce one-time acceptance.

### Add Oban only for cleanup

Rejected because Ironhold has no other durable background-job requirement. Adding a job system, its tables, queues, configuration, and operational surface solely for bounded deletion would be disproportionate to the maintenance task.

## Consequences

### Positive

- Exact authenticated replays are rejected consistently across nodes and restarts.
- Claim and webhook persistence succeed or fail together.
- Concurrent acceptance is decided by database constraints without a process-local race.
- Future Tidewake retries with fresh signing material remain distinguishable from exact replay.
- Replay-state retention excludes signatures, secrets, headers, and bodies.

### Negative

- Every accepted webhook requires an additional insert and unique-index check in the ingestion transaction.
- PostgreSQL availability is required for replay decisions as well as webhook persistence.
- A supervised cleanup process and operational visibility for its progress must be added.
- Publicly combining replay and duplicate-event failures reduces client-visible diagnostic detail by design.

## Out of scope

This ADR does not implement the claim schema, migration, transaction, cleanup process, controller behavior, Telemetry events, or tests. It does not change the HMAC wire format, timestamp window, existing `event_id` contract, shared-secret provisioning, secret rotation, rate limiting, downstream event processing, or audit-retention policy.

## Follow-up

Implement the PostgreSQL claim and atomic receive transaction in a focused change. That implementation must test exact replay, freshly signed retries, duplicate event IDs, transaction rollback, concurrent claims, expiration boundaries, cleanup, generic public failures, distinct internal reasons, and non-disclosure of signing and request material.
