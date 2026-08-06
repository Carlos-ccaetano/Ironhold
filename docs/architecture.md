# Architecture

## Context

Tidewake owns reliable webhook delivery. Ironhold is its companion service and will own the receiving boundary: accepting requests, applying security policy, and retaining an auditable account of processing.

This first increment intentionally implements only the Phoenix application boundary and PostgreSQL connection. The domain boundaries below are design targets, not existing code modules or finished capabilities.

## Current runtime

An HTTP request reaches `IronholdWeb.Endpoint`, passes through `IronholdWeb.Router`, and is handled by a small controller. `Ironhold.Application` supervises the endpoint, the Ecto repository, and the Telemetry supervisor. PostgreSQL is the only local infrastructure dependency.

## Future boundaries

### Webhooks

Will define the public ingestion contract, normalize accepted requests, and coordinate processing. It should know the delivery protocol but delegate security decisions and audit persistence.

### Security

Will validate authenticity and freshness. HMAC verification, replay prevention, rate limiting, and authentication belong here and must be introduced with explicit threat models and tests.

### Audit

Will record security-relevant decisions and webhook processing outcomes with deliberate retention and access policies. Logging alone will not be treated as a complete audit trail.

### Observability

Will turn Telemetry events into useful metrics, traces, alerts, and service-level signals. The current Telemetry wiring is only the instrumentation foundation.

## Dependency direction

The HTTP layer may call application/domain code. Domain policy should not depend on Phoenix, and infrastructure implementations should remain behind the code that owns each use case. These rules should be applied when concrete behavior exists rather than through speculative interfaces today.

## Security posture

The current root page is informational. There is no webhook ingestion endpoint and therefore no claim of HMAC validation, replay protection, rate limiting, authentication, full auditing, or dashboard access.
