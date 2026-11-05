# Rosery API

Go backend for Rosery's Quran features. Rosery remains free and requires no account or user login. The backend authenticates an app installation with Apple App Attest; it does not identify a person. Quran Foundation credentials stay on this server.

The initial endpoints provide chapters, paginated Uthmani verses, and translation discovery. Existing dhikr and booklet screens remain offline and are not connected to the API yet. This is a tested local implementation; no public service has been deployed.

## Run locally

Requires Go 1.26 or newer. Configuration is read from environment variables; `.env.example` documents the variables but is not automatically loaded.

Create a **Backend/server app** in the [Quran Foundation Developer Console](https://dev-console.quran.foundation/). Put its prelive client ID and secret in your local environment, then run from this directory:

```sh
export QF_ENV=prelive
export QF_CLIENT_ID='your-client-id'
export QF_CLIENT_SECRET='your-client-secret'
go run ./cmd/rosery-api
```

`GET http://127.0.0.1:8080/healthz` checks local liveness without contacting Quran Foundation. All Quran endpoints require valid App Attest assertions, including in development; there is no shared mobile API key or unsigned development bypass. A supported physical Apple device is required for real enrollment. For device development, put an HTTPS ingress/tunnel in front of the loopback listener; configure its trusted peer addresses and origin token. Simulator protocol tests do not require Apple enrollment.

Prelive Quran Foundation contains only surahs 1 and 2. All 114 surahs require approved production credentials. Keep QF and Apple attestation environments paired with the corresponding test/release app; use different database files for development and production.

```sh
make check
make build
make vuln
```

Tests use generated signed certificate chains, cryptographic assertions, temporary databases and local mock upstream servers. They never use live client credentials. Sandbox environments may require `GOCACHE=/private/tmp/rosery-go-build` and permission to bind loopback test sockets.

See [VALIDATION.md](VALIDATION.md) for completed verification and the live integration checks still needed.

## Wire protocol

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/healthz` | Local liveness; no upstream dependency |
| POST | `/v1/attest/challenge` | `{key_id, purpose}`; purpose is `attest` or `assert` |
| POST | `/v1/attest/register` | `{key_id, challenge, attestation}`; returns 204 |
| GET | `/v1/quran/chapters` | Optional `language` |
| GET | `/v1/quran/chapters/{1..114}` | Optional `language` |
| GET | `/v1/quran/verses/by_chapter/{1..114}` | `language`, `page` 1..604, `per_page` 1..50, `words`, up to three `translations` IDs |
| GET | `/v1/quran/resources/translations` | Optional `language`; translation IDs for the verse endpoint |

Language is a two- or three-letter lowercase code. Unknown, repeated, or oversized parameters are rejected. Verse-level `fields=text_uthmani` is set by the server, with `word_fields=text_uthmani` when words are requested. The server returns the provider's JSON without rewriting Arabic text. Provider HTML in translations must be safely rendered as text or sanitized when a future reader supports it.

1. The app generates an installation key with `DCAppAttestService` and requests an `attest` challenge for that key ID. The challenge is a standard-base64 encoding of 32 random bytes and expires after two minutes.
2. The app calls `attestKey` with `SHA256(decoded challenge bytes)` and posts the result as standard-base64. The server verifies Apple's pinned root certificate chain, nonce, App ID, environment, public key and credential. Exact retries of an already accepted registration are idempotent, even after a restart.
3. Before each content request, the app requests an `assert` challenge for its registered key and signs `SHA256(clientData)` using `generateAssertion`.
4. The content request sends `X-App-Attest-Key-ID`, `X-App-Attest-Challenge` and `X-App-Attest-Assertion`. The server verifies the signature and request binding, then durably advances the assertion counter and consumes the challenge before returning content.

The canonical client data is UTF-8, with no trailing newline:

```text
rosery-v1\n{standard-base64 challenge}\n{UPPERCASE method}\n{encoded path and query as actually sent}\n{lowercase hex SHA256(body)}
```

For GET, hash an empty body. Query order is part of the signature. Client requests must be serialized per key, including across actor suspension points, to preserve assertion counter order. The iOS implementation lives in `../rosery/Networking/`; share one client per API origin. It uses Keychain storage and never silently weakens verification on unsupported devices.

Error bodies are `{ "error": { "code": "...", "message": "..." } }`. Rate limits return 429 and `Retry-After`; capacity/provider failures return 503 or 502. Obtain a new assertion challenge for a new content attempt, and respect backoff. A network error during registration should retry the same enrollment payload. An arbitrary 401 must not trigger repeated key generation.

## Security and deployment

Production traffic needs this complete path:

```text
iOS app -- HTTPS --> DDoS/WAF edge -- authenticated encrypted origin -->
private ingress -- loopback/private protected hop --> Go API --> Quran Foundation
```

Use [Cloudflare DDoS protection](https://developers.cloudflare.com/ddos-protection/) or an equivalent managed edge. [Cloudflare Tunnel or locked-down origin access](https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/) prevents bypassing that edge. For a public origin use verified TLS, firewall restrictions and authenticated origin access/mTLS; for a tunnel the Go listener can remain private. Do not expose port 8080 to the Internet. Do not send the origin secret over an unencrypted public hop.

Production startup requires `ROSERY_TRUSTED_PROXIES`, a random server-only `ROSERY_ORIGIN_TOKEN` of at least 32 characters, production App Attest, and `QF_ENV=production`. An immediate trusted ingress must **overwrite** `X-Rosery-Origin-Token` and `X-Forwarded-Proto` and construct an accurate `X-Forwarded-For` chain. It must strip client-supplied forwarding headers unless their immediate sender is independently trusted. The API trusts forwarding headers only from configured CIDRs, walks the chain from the right, and groups IPv6 addresses by /64. Configure only actual proxy addresses. A token header alone does not protect an exposed origin.

Configure WAF limits for API traffic and stricter limits on enrollment. Native requests cannot solve browser CAPTCHA/JavaScript challenges; avoid putting interactive challenge rules on these endpoints. Disable shared/CDN caching on protected routes so a cache cannot bypass app verification. The API sends `Cache-Control: no-store` for downstream responses and caches permitted upstream responses privately for at most five minutes.

Application safeguards are bounded: 100 requests/sec globally (burst 200), 120/min per IP (burst 40), 120/min per verified device (burst 30), and 120 challenge-endpoint calls/min per IP (burst 30). New enrollment challenges and registrations share a stricter 6/min quota (burst 3). Global in-flight requests default to 64, crypto operations to 8, provider calls to 32, and pending challenges to 10,000 with at most four per key. Rate tables and the provider cache are bounded; overload rejects work instead of growing a queue. These are initial single-instance limits, not a capacity claim. Tune from production measurements and enforce shared quotas at the edge.

The HTTP listener has header/body/write/idle deadlines, a 32 KiB request-body cap and a 16 KiB header cap. Provider requests use TLS, deadlines, bounded bodies, fixed hosts and paths, no redirects, coalesced token/cache misses, and a single OAuth retry after 401. OAuth tokens, attestation proofs, receipts and IP addresses are not logged. A shared secret inside the app, CORS, User-Agent checks, and certificate pinning do not replace these controls.

The lightweight `/healthz` probe still checks origin trust in production but is independent of content-work quotas. It performs no database, cryptographic verification or provider work, so ordinary saturation does not trigger liveness restarts. Apply edge limits to external probe traffic too.

App Attest helps distinguish legitimate installations; a genuine device can still abuse the service. It does not absorb volumetric traffic. The edge and origin network restrictions remain required before public launch.

## Durable state and privacy

Run **one API process per database** with a persistent writable volume. The local bbolt store saves attested public keys, monotonic counters, opaque Apple fraud receipts, accepted registration digests and creation metadata; pending challenges and content caches are in RAM. No user account, email, bookmarks, reading history or app progress is sent. Do not log request proofs or query content at the ingress. Disclose installation verification and retention in the app's privacy documentation before connecting the feature publicly.

Database files are mode 0600 and bound to one App ID and Apple environment. Losing or rolling back state can invalidate installed clients' counter/registration state, so keep the live volume durable and back it up consistently. Do not run simultaneous replicas with independent copies. Shared atomic nonce/counter state and distributed quotas are needed before scaling to multiple instances. The initial device cap is 100,000 and intentionally does not evict enrolled keys. Apple fraud-receipt risk assessment is not yet integrated.

## Content terms

This implementation uses short-lived online-response caching. It does **not** implement a persistent offline corpus, prepackage Quran Foundation data, or claim Content Sync compliance. Persistent offline Quran downloads require the official Content Sync implementation and its update obligations in a later reader feature. Existing independently bundled dhikr/booklet content is unchanged. See [Quran Foundation terms](https://api-docs.quran.foundation/legal/developer-terms/) and [Content API authentication](https://api-docs.quran.com/docs/quickstart/).
