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
- context, schema, route, contract, and failure-path tests cover the implemented boundary

Explicit HTTP request and payload-size limits and a stricter supported-content-type policy remain pending. This initial endpoint stores envelopes but does not establish their authenticity or freshness.

## 3. Integrity and freshness

- Define a versioned signing contract with Tidewake
- Add HMAC verification with key rotation guidance
- Add signed timestamp and replay protections backed by explicit threat-model tests

## 4. Operational protection and audit

- Add rate limiting and abuse controls
- Define structured audit records, retention, and restricted access
- Export useful Telemetry metrics, traces, and alerts

## 5. Product interface

- Add authentication and authorization
- Consider an operational dashboard only after its concrete user needs and access model are known

The project foundation and initial webhook ingestion are implemented. Explicit HTTP limits, HMAC, timestamp validation, replay protection, rate limiting, complete auditing, and the dashboard remain planned work.
