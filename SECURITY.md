# Security policy

## Supported versions

Ironhold is in its foundation stage. Only the latest commit on `main` is intended to receive security updates.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use the repository's private GitHub security advisory reporting flow and include:

- the affected commit or version;
- reproduction steps or a proof of concept;
- the expected impact;
- any suggested mitigation.

Please avoid accessing data that is not yours, disrupting services, or publishing details before a fix can be prepared. The maintainers will acknowledge the report and coordinate next steps through the private advisory.

## Current scope

This foundation does not yet implement webhook ingestion, HMAC validation, replay protection, rate limiting, authentication, complete auditing, or a dashboard. Their absence is known roadmap work, not a claim that those protections exist.
