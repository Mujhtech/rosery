# API validation — 24 October 2026

Completed against the local implementation:

- `go test -race ./...`: passed across attestation, configuration, HTTP handlers and Quran Foundation client.
- `go vet ./...`: passed; final configured `golangci-lint run ./...`: 0 issues.
- `govulncheck ./...`: no known reachable vulnerabilities found.
- `go build -trimpath ./cmd/rosery-api`: passed.
- Unsigned Debug iOS Simulator build of the complete app and widgets: passed.
- Swift protocol/transport/model executable checks: passed with strict concurrency and warnings treated as errors.
- Local built-binary smoke test using dummy provider credentials: health 200, unsigned Quran request 401, database mode 0600, graceful SIGTERM shutdown. No provider content request was made.
- Independent published iOS 14.4 Apple artifacts: attestation chain and real-device assertion verification passed against Apple's root at the sample's historical timestamp.
- Generated test chains cover mismatched app/environment/credential, tampered requests, replay, concurrent duplicate assertions, nonce expiration and registration retry across restart.
- Shared Swift/Go canonical request digest: passed on both ends.
- Focused malformed-attestation/assertion fuzzing: 160,821 executions without failure in the recorded five-second run.

Tests use local fixtures, temporary stores and loopback-only mock services. Sandbox permissions were expanded for local test sockets, Go dependency downloads, public vulnerability-database access and Xcode compiler services. No code was published, no app was installed on a device, and no production service was deployed.

Still requires live integration: Quran Foundation credentials and approved production access; App Attest capability/provisioning; a supported physical device; and HTTPS hosting behind a DDoS-protected edge with protected origin access. Existing reading screens have not yet been connected to this client. Persistent offline Quran downloads and multi-replica state are separate future work.
