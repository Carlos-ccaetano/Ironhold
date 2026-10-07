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

These persistence and HTTP boundaries are now combined with the authenticated boundary below.

## 3. Authenticated webhook ingestion — implemented first boundary

- exactly one `Tidewake-Id`, `Tidewake-Timestamp`, and `Tidewake-Signature` header is required
- HMAC-SHA256 is verified over `v1.<event_id>.<timestamp>.<exact_body_bytes>` before JSON decoding
- the timestamp window includes 300 seconds in the past and 30 seconds in the future
- the authenticated header ID must match the decoded body `id` exactly
- authentication failures return the generic `401` response from ADR 0004 before persistence
- production requires `IRONHOLD_WEBHOOK_SIGNING_SECRET` with at least 32 bytes
- verified signatures, authentication rejections, and identifier mismatches emit separate low-cardinality Telemetry events and counters
- replay protection, used-nonce or signature storage, and secret rotation or multiple simultaneous secrets remain pending

## 4. Operational protection and audit

- Add rate limiting and abuse controls
- Define structured audit records, retention, and restricted access
- Export useful Telemetry metrics, traces, and alerts

## 5. Product interface

- Add authentication and authorization
- Consider an operational dashboard only after its concrete user needs and access model are known

The project foundation, authenticated webhook ingestion, HTTP boundaries, field limits, and ingestion and authentication Telemetry are implemented. Replay protection, used-nonce or signature storage, secret rotation and multiple simultaneous secrets, rate limiting, a complete audit trail, and the operational dashboard remain planned work.

End-to-end production delivery is not complete. Tidewake's Req adapter remains inactive, so real HTTP delivery, retries, backoff, and Tidewake-side SSRF protection remain pending.
