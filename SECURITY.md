# Security Policy

## Supported Versions

Security fixes are applied on the active development line.

| Version | Supported |
|---|---|
| main (latest) | yes |
| older commits/tags | best effort |

## Reporting a Vulnerability

Please report vulnerabilities privately.

Preferred path:
- GitHub Security Advisory / private security report for this repository.

If private reporting is unavailable, open an issue with minimal details and ask maintainers for a private channel before publishing exploit details.

Please include:

- affected version/commit
- platform (Linux/macOS/Windows)
- reproduction steps
- impact assessment
- proof-of-concept (if safe to share privately)

## Response Process

- We will acknowledge reports as soon as possible.
- We will validate, prioritize, and prepare a fix.
- Coordinated disclosure is preferred after a patch is available.

## Scope

In-scope areas include:

- WebSocket/HTTP transport behavior
- RPC dispatch paths
- process launch/termination behavior
- TLS and certificate handling
- profile path handling and filesystem interactions
