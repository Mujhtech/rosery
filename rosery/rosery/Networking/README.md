# Accountless Quran API client

`RoseryAPIClient` is the iOS counterpart to `api/`. It does not create user
accounts, use Quran Foundation User APIs, embed server credentials, or start
requests on app launch. Existing offline readings are independent of this client.

Create **one shared instance per API origin**, supplied by the future Quran
feature's composition root. The URL below is an example, not a deployed service:

```swift
let client = try RoseryAPIClient(baseURL: URL(string: "https://your-api-domain.example")!)
let chapters = try await client.chapters()
let page = try await client.verses(chapter: 1)
```

The first content request generates an App Attest key, fetches a short-lived
server challenge, obtains Apple's attestation, and registers the verified key.
Subsequent content requests obtain a fresh challenge and attach an assertion
bound to the HTTP method, encoded path/query, and SHA-256 of the body. A FIFO
permit serializes the entire operation across actor suspension points so
assertion counters cannot arrive out of order. The queue is bounded at 16.

Enrollment state lives in the device-only Keychain, scoped to the API URL and a
local install marker. Pending attestation bytes are retained until the backend
acknowledges registration, permitting an exact idempotent retry after a lost
response. Apple `serverUnavailable` retries preserve the key and challenge.
An Apple `invalidKey` response permits one replacement attempt; nontransient
Apple errors during initial attestation discard only the pending candidate.
An assertion input error leaves a registered key intact. HTTP failures never
silently bypass verification. Deleting/reinstalling the app or a confirmed
invalid Apple key triggers enrollment again.

Generic HTTP401 responses fail closed. The API must retain its persistent key
database and replay counters on a mounted volume and keep backups. Retaining
old attestation bytes on the client cannot safely replace a lost server database:
the original nonce may be expired or unavailable. After confirmed enrollment
loss, a deliberate `try await client.resetEnrollment()` clears the local record
under the same FIFO permit. The next request must prove a newly generated key
through Apple and server verification. This does not delete the prior server
record or Apple's private key, and must never run automatically after a timeout,
transport failure, or generic401.

The API must configure App ID `6JR3ZGLPD6.mujhtech.rosery`. The main app's Debug
entitlement uses `development`; Release uses `production`. TestFlight and App
Store distribution use Apple's production environment. Enable the App Attest
capability for the app identifier and regenerate its provisioning profile before
a signed device release. The widget does not use this client or this entitlement.

Production requires HTTPS and Apple's standard TLS validation. There are no ATS
exceptions, custom trust overrides, pinned static secrets, or redirect following.
The optional HTTP loopback allowance is compiled only into Debug configuration.
The ephemeral URLSession disables cookies, URL credentials and HTTP caching;
responses are limited to 2 MiB and unfinished transfers are explicitly canceled
when the cap is exceeded. Requests time out after 15 seconds and resources
after 30 seconds. `Retry-After` seconds and structured HTTP errors are exposed to
the caller without automatic request retry storms.

App Attest is unavailable on Simulator and some devices. This client returns
`unsupportedDevice` and keeps the existing offline app usable. A production
fallback for remote Quran content needs a separately designed verification
policy; no unsigned fallback is included. Actual Apple attestation, provisioning,
and physical-device interoperability remain device integration checks.

Run protocol, transport and model checks from the project directory:

```sh
xcrun swiftc -module-cache-path /private/tmp/rosery-api-client-cache \
  -parse-as-library -default-isolation MainActor -strict-concurrency=complete \
  -warnings-as-errors rosery/Networking/RoseryAPIProtocol.swift \
  rosery/Networking/QuranAPIModels.swift rosery/Networking/RoseryAPITransport.swift \
  Tests/APIClientChecks.swift -o /private/tmp/rosery-api-client-checks
/private/tmp/rosery-api-client-checks
```

These use in-process URLProtocol fixtures and make no external requests. They
verify request binding against a shared Go hash fixture, URL validation, Arabic text decoding, status and retry
metadata, and both advertised and streamed response-size limits.
