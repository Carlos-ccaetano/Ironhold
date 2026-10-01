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
- successful ingestion returns `202`, duplicate `event_id` returns `409`, and invalid input returns `422`
- requests must declare a single `application/json` media type; missing, incompatible, or ambiguous values return `415`
- raw request bodies up to and including `262_144` bytes are accepted; larger bodies return a stable `413` response before persistence
- `event_id` and `event_type` are limited to 255 characters
- accepted ingestion and bounded rejection reasons emit Telemetry
- context, schema, route, contract, and failure-path tests cover the implemented boundary

This endpoint stores envelopes but does not establish their authenticity or freshness.

## 3. Integrity and freshness

- The versioned HMAC receiver contract is defined in ADR 0003; verification is not implemented
- Add raw-body preservation and HMAC verification with secret-rotation guidance
- Add temporal validation and replay protections backed by explicit threat-model tests

## 4. Operational protection and audit

- Add rate limiting and abuse controls
- Define structured audit records, retention, and restricted access
- Export useful Telemetry metrics, traces, and alerts

## 5. Product interface

- Add authentication and authorization
- Consider an operational dashboard only after its concrete user needs and access model are known

The project foundation, initial webhook ingestion, HTTP boundaries, field limits, and ingestion Telemetry are implemented. HMAC verification, temporal validation, raw-body preservation for HMAC, replay protection, secret rotation, rate limiting, complete auditing, and the operational dashboard remain planned work.
