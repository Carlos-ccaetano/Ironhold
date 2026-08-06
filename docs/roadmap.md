# Roadmap

The roadmap is incremental so that protocol and security decisions remain reviewable.

## 1. Project foundation — current

- Phoenix application with Bandit, Ecto, PostgreSQL, and Telemetry
- Environment-based production configuration
- Automated formatting, compilation, test, Credo, and Sobelow checks
- Initial architecture and contribution documentation

## 2. Webhook ingestion contract

- Define endpoint shape, payload limits, supported content types, and error semantics
- Persist the minimum delivery metadata needed for processing
- Add contract and failure-path tests

## 3. Integrity and freshness

- Define a versioned signing contract with Tidewake
- Add HMAC verification with key rotation guidance
- Add timestamp and replay protections backed by explicit threat-model tests

## 4. Operational protection and audit

- Add rate limiting and abuse controls
- Define structured audit records, retention, and restricted access
- Export useful Telemetry metrics, traces, and alerts

## 5. Product interface

- Add authentication and authorization
- Consider an operational dashboard only after its concrete user needs and access model are known

Each item above is planned work and is not part of the current implementation.
