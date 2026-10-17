# Roadmap

The roadmap is incremental so that protocol and security decisions remain reviewable.

## 1. Project foundation — implemented

- Phoenix application with Bandit, Ecto, PostgreSQL, and Telemetry
- Environment-based production configuration
- Automated formatting, compilation, test, Credo, and Sobelow checks
- Initial architecture and contribution documentation

## 2. Initial webhook ingestion — implemented

- `POST /api/webhooks` accepts an envelope with `id`, `type`, and object-valued `data`
- the controller delegates to the `Ironhold.Webhooks` context, which persists through the `ReceivedWebhook` schema
- `event_id`, `event_type`, `payload`, and `received_at` are stored in PostgreSQL
- a unique database index on `event_id` prevents duplicate persistence
- successful ingestion and a freshly signed identical retry return `202`; exact replay or conflicting reuse of an `event_id` returns `409`, and invalid input returns `422`
- requests must declare a single `application/json` media type; missing, incompatible, or ambiguous values return `415`
- raw request bodies up to and including `262_144` bytes are accepted; larger bodies return a stable `413` response before persistence
- `event_id` and `event_type` are limited to 255 characters
- accepted ingestion and bounded rejection reasons emit Telemetry
- context, schema, route, contract, and failure-path tests cover the implemented boundary

These persistence and HTTP boundaries are now combined with the authenticated boundary below.

## 3. Authenticated webhook ingestion — implemented first boundary

- exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header is required
- HMAC-SHA256 is verified over `v1.<event_id>.<timestamp>.<exact_body_bytes>` before JSON decoding
- the timestamp window includes 300 seconds in the past and 30 seconds in the future
- the authenticated header ID must match the decoded body `id` exactly
- authentication failures return the generic `401` response from ADR 0004 before persistence
- production requires `IRONHOLD_WEBHOOK_SIGNING_SECRET` with at least 32 bytes
- verified signatures, authentication rejections, and identifier mismatches emit separate low-cardinality Telemetry events and counters
- secret rotation and multiple simultaneous secrets remain pending

## 4. Replay protection — implemented

- authentication and temporal validation complete before replay metadata is created
- a versioned SHA-256 fingerprint of the validated signature distinguishes exact replay from a newly signed attempt
- only the 64-character lowercase irreversible fingerprint, expiration, and insertion time are stored as replay state
- `Ecto.Multi` inserts the replay claim and received webhook in one PostgreSQL transaction
- the fingerprint constraint rejects exact replay with the generic `409` response, while event idempotency acknowledges a freshly signed identical envelope with `202` and rejects conflicting `event_id` reuse with `409`
- failed webhook insertion rolls back the provisional replay claim
- concurrent identical requests are arbitrated by the fingerprint constraint rather than process-local coordination
- `Ironhold.Webhooks.ReplayCleanup` is supervised, defaults to a five-minute interval, and removes expired claims with one idempotent database operation
- replay acceptance, detection, cleanup count, removed-claim count, duration, result, and origin have low-cardinality Telemetry events and metrics
- HTTP, context, concurrency, cleanup, and Telemetry tests cover the implemented security contract

## 5. Operational protection and audit

- Add rate limiting and abuse controls to Ironhold; a future rate-limited response may emit `Retry-After` as receiver guidance without controlling sender scheduling
- Cross-repository — Tidewake: expose manual retry with a dedicated audit record for each manual retry request
- Cross-repository — Tidewake: interpret `Retry-After` from receiver responses when rescheduling outbound deliveries
- Define structured audit records, retention, and restricted access
- Export the declared Telemetry metrics and add useful traces and external alerts

## 6. Product interface

- Add administrative authentication and authorization
- Consider an operational dashboard only after its concrete user needs and access model are known

The project foundation, authenticated webhook ingestion, HTTP boundaries, field limits, durable replay protection, supervised claim cleanup, and ingestion, authentication, and replay Telemetry are implemented. Tidewake's secure outbound HTTP transport and bounded automatic retries are also implemented, and Ironhold acknowledges an identical envelope with fresh signing material idempotently while rejecting an exact replay with `409`.

End-to-end production deployment is not complete. Cross-repository Tidewake work still includes manual retry, an audit record for each manual retry request, and sender-side interpretation of `Retry-After` when rescheduling deliveries. Ironhold work still includes rate limiting, an operational API or UI and dashboard, and deployment. A future Ironhold rate limiter may emit `Retry-After`, but that receiver signal does not give Ironhold control over Tidewake's delivery schedule.
