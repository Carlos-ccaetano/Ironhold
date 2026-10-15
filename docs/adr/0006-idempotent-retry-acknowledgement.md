# ADR 0006: Idempotent retry acknowledgement

- Status: Accepted
- Date: 2026-10-15

## Context

[ADR 0005](0005-webhook-replay-protection.md) distinguishes an exact replay from a request for the same `event_id` signed with a new timestamp and signature. The current policy rejects both a freshly signed copy of an already stored envelope and a conflicting reuse of its event ID with the generic `409 Conflict` response.

That behavior can report a false terminal failure. If Ironhold commits a webhook but its `202 Accepted` response is lost, a legitimate retry can arrive with fresh signing material for an event that Ironhold has already accepted. The receiver needs to acknowledge that retry without allowing exact replay or silently accepting different content under the same event ID.

## Decision

This decision extends ADR 0005 and supersedes only its incompatible treatment of freshly signed duplicate events. It does not change authentication, the HMAC wire format, or exact-replay detection.

An exact replay reuses the same validated signature and therefore the same fingerprint. It remains a replay and returns the existing generic `409 Conflict` response.

A request with a new timestamp and signature has a new fingerprint. When its `event_id` already exists, Ironhold will compare only the persisted fields that represent the authenticated envelope: `event_type` and `payload`.

- If both fields are semantically identical to the stored event, the request is an idempotent retry and returns the same `202 Accepted` status and body as the first acceptance.
- If either field differs, the event ID has been reused for different content and the request returns the existing generic `409 Conflict` response.

The `202` response must not reveal whether the webhook was inserted by this request or had already been stored. JSON object representation is compared by its decoded, persisted value rather than raw-body formatting. Receipt time, database timestamps, internal IDs, and other storage metadata do not participate in equality.

## Transaction sequence

After authentication, timestamp validation, header/body ID matching, replay fingerprint derivation, and envelope validation succeed, one PostgreSQL transaction will:

1. insert the new replay claim, relying on its unique fingerprint constraint to reject exact replay;
2. attempt the webhook insert through a database conflict-aware operation that leaves the transaction usable when `event_id` already exists;
3. commit both records and return `202` when the webhook is new;
4. when the event ID exists, read the persisted envelope under the same transaction and compare only `event_type` and `payload`;
5. commit the new replay claim and return the indistinguishable `202` response when those fields match;
6. roll back the new replay claim and return the generic `409` response when they differ.

The committed claim for an idempotent retry ensures that exact reuse of that retry's signing material is detected later. PostgreSQL constraints and transactional conflict handling remain the concurrency boundary; Ironhold must not perform an application-level check-then-insert outside the transaction.

## Public behavior

| Authenticated request | Result |
| --- | --- |
| New fingerprint and new `event_id` | `202 Accepted` |
| Existing fingerprint | Generic `409 Conflict` |
| New fingerprint, existing `event_id`, identical `event_type` and `payload` | Same `202 Accepted` response |
| New fingerprint, existing `event_id`, different `event_type` or `payload` | Generic `409 Conflict` |

Responses, logs, and Telemetry must not expose whether a success inserted or reused a webhook. Signatures, secrets, raw bodies, URLs, complete headers, and payloads must not be logged or attached to Telemetry.

## Consequences

### Positive

- A lost success response no longer turns a legitimate freshly signed retry into a terminal sender failure.
- Exact replay remains distinguishable from idempotent retry.
- Conflicting content cannot be accepted under an existing event ID.
- Committing the fresh claim preserves replay protection for every acknowledged signing attempt.
- Database constraints continue to arbitrate concurrent requests.

### Negative

- An event-ID conflict now requires a transactional read and semantic comparison before the response is known.
- Public `202` responses deliberately provide no indication of whether a row was inserted or reused.
- The implementation must preserve a usable transaction after the event-ID conflict rather than relying on an aborted constraint-error path.

## Alternatives considered

### Keep returning `409` for every freshly signed duplicate

Rejected because the sender cannot distinguish a lost response from a webhook that Ironhold failed to accept.

### Return `202` for every existing event ID

Rejected because it would hide attempts to reuse an event ID with a different event type or payload.

### Check for the event before starting the transaction

Rejected because check-then-insert introduces a race and separates the replay claim from the idempotency decision.

### Roll back the fresh claim after an idempotent acknowledgement

Rejected because an exact repetition of that newly acknowledged request would not have durable replay state.

### Compare raw request bodies

Rejected because semantically identical JSON can have different byte representations, and raw bodies are not persisted.

## Out of scope

This ADR does not implement Elixir code, migrations, schemas, controller or route changes, or tests. It does not change the HMAC contract, secret rotation, rate limiting, Tidewake retry scheduling, or deployment. Implementation and public-contract documentation will follow in separate changes.
