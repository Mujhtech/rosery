package attest

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func newTestService(t *testing.T, f fixture) *Service {
	t.Helper()
	s, err := New(Config{AppID: testAppID, Environment: "production", StorePath: filepath.Join(t.TempDir(), "attest.db")})
	if err != nil {
		t.Fatal(err)
	}
	s.verifier = testVerifier(t, f, "production")
	s.now = func() time.Time { return f.now }
	t.Cleanup(func() {
		if err := s.Close(); err != nil {
			t.Error(err)
		}
	})
	return s
}

func registerFixture(t *testing.T, s *Service, f fixture) (Challenge, string) {
	t.Helper()
	challenge, err := s.Challenge(f.keyID, "attest")
	if err != nil {
		t.Fatal(err)
	}
	rawChallenge, err := base64.StdEncoding.DecodeString(challenge.Challenge)
	if err != nil {
		t.Fatal(err)
	}
	raw := f.attestation(t, rawChallenge, f.authData(t, "production", nil), false)
	attestation := base64.StdEncoding.EncodeToString(raw)
	if err := s.Attest(f.keyID, challenge.Challenge, attestation); err != nil {
		t.Fatal(err)
	}
	return challenge, attestation
}

func TestNewValidatesEnvironmentAndStoreIdentity(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "attest.db")
	if _, err := New(Config{AppID: testAppID, Environment: "typo", StorePath: path}); err == nil {
		t.Fatal("accepted unknown environment")
	}
	config := Config{AppID: testAppID, Environment: "production", StorePath: path}
	s, err := New(config)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	config.Environment = "development"
	if second, err := New(config); err == nil {
		_ = second.Close()
		t.Fatal("accepted production DB for development")
	}
}

func TestChallengeValidationAndExpiry(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	s := newTestService(t, f)
	if _, err := s.Challenge("bad-key", "attest"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("malformed key: %v", err)
	}
	if _, err := s.Challenge(f.keyID, "unknown"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("unknown purpose: %v", err)
	}
	if _, err := s.Challenge(f.keyID, "assert"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("assertion for unknown key: %v", err)
	}
	challenge, err := s.Challenge(f.keyID, "attest")
	if err != nil {
		t.Fatal(err)
	}
	s.now = func() time.Time { return f.now.Add(challengeTTL) }
	rawChallenge, _ := base64.StdEncoding.DecodeString(challenge.Challenge)
	raw := f.attestation(t, rawChallenge, f.authData(t, "production", nil), false)
	if err := s.Attest(f.keyID, challenge.Challenge, base64.StdEncoding.EncodeToString(raw)); !errors.Is(err, ErrInvalid) {
		t.Fatalf("accepted expired challenge: %v", err)
	}
}

func TestChallengeCapacityProtectsExistingNonces(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	s := newTestService(t, f)
	for range maxPerKey {
		if _, err := s.Challenge(f.keyID, "attest"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.Challenge(f.keyID, "attest"); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("unbounded challenges: %v", err)
	}
	s.now = func() time.Time { return f.now.Add(challengeTTL) }
	if _, err := s.Challenge(f.keyID, "attest"); err != nil {
		t.Fatalf("expired entries were not reclaimed: %v", err)
	}
}

func TestAttestExactRetryAndDurableReplayState(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	s := newTestService(t, f)
	accepted, object := registerFixture(t, s, f)
	if err := s.Attest(f.keyID, accepted.Challenge, object); err != nil {
		t.Fatalf("exact retry: %v", err)
	}
	if err := s.Attest(f.keyID, accepted.Challenge, object[:len(object)-1]+"!"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("malformed retry: %v", err)
	}
	challenge, err := s.Challenge(f.keyID, "assert")
	if err != nil {
		t.Fatal(err)
	}
	request := signedRequest(t, f, challenge.Challenge, 1, http.MethodGet, "/v1/quran/chapters", nil)
	if err := s.Verify(request, nil); err != nil {
		t.Fatalf("first assertion: %v", err)
	}
	if err := s.Verify(request, nil); !errors.Is(err, ErrInvalid) {
		t.Fatalf("replayed assertion: %v", err)
	}
	path := s.db.Path()
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := New(Config{AppID: testAppID, Environment: "production", StorePath: path})
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = reopened.Close() }()
	reopened.verifier = testVerifier(t, f, "production")
	if err := reopened.Attest(f.keyID, accepted.Challenge, object); err != nil {
		t.Fatalf("accepted enrollment retry after restart: %v", err)
	}
	next, err := reopened.Challenge(f.keyID, "assert")
	if err != nil {
		t.Fatal(err)
	}
	stale := signedRequest(t, f, next.Challenge, 1, http.MethodGet, "/v1/quran/chapters", nil)
	if err := reopened.Verify(stale, nil); !errors.Is(err, ErrInvalid) {
		t.Fatalf("counter was lost on restart: %v", err)
	}
	valid := signedRequest(t, f, next.Challenge, 2, http.MethodGet, "/v1/quran/chapters", nil)
	if err := reopened.Verify(valid, nil); err != nil {
		t.Fatalf("invalid attempt consumed nonce: %v", err)
	}
}

func TestVerifyBindsMethodPathQueryAndBody(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		mutate func(*http.Request)
		body   []byte
	}{
		{name: "method", mutate: func(r *http.Request) { r.Method = http.MethodPost }},
		{name: "path", mutate: func(r *http.Request) { r.URL.Path = "/v1/quran/chapters/2" }},
		{name: "query", mutate: func(r *http.Request) { r.URL.RawQuery = "language=ar" }},
		{name: "body", body: []byte("tampered")},
		{name: "duplicate proof header", mutate: func(r *http.Request) { r.Header.Add("X-App-Attest-Assertion", r.Header.Get("X-App-Attest-Assertion")) }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			f := newFixture(t)
			s := newTestService(t, f)
			registerFixture(t, s, f)
			challenge, err := s.Challenge(f.keyID, "assert")
			if err != nil {
				t.Fatal(err)
			}
			r := signedRequest(t, f, challenge.Challenge, 1, http.MethodGet, "/v1/quran/chapters?language=en", nil)
			if tt.mutate != nil {
				tt.mutate(r)
			}
			if err := s.Verify(r, tt.body); !errors.Is(err, ErrInvalid) {
				t.Fatalf("tampering accepted: %v", err)
			}
			valid := signedRequest(t, f, challenge.Challenge, 1, http.MethodGet, "/v1/quran/chapters?language=en", nil)
			if err := s.Verify(valid, nil); err != nil {
				t.Fatalf("tampering consumed valid nonce: %v", err)
			}
		})
	}
}

func TestVerifyConcurrentReplaySucceedsExactlyOnce(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	s := newTestService(t, f)
	registerFixture(t, s, f)
	challenge, err := s.Challenge(f.keyID, "assert")
	if err != nil {
		t.Fatal(err)
	}
	r := signedRequest(t, f, challenge.Challenge, 1, http.MethodGet, "/v1/quran/chapters", nil)
	var wg sync.WaitGroup
	results := make(chan error, 8)
	for range 8 {
		wg.Go(func() { results <- s.Verify(r, nil) })
	}
	wg.Wait()
	close(results)
	successes := 0
	for err := range results {
		if err == nil {
			successes++
		} else if !errors.Is(err, ErrInvalid) {
			t.Fatalf("unexpected error: %v", err)
		}
	}
	if successes != 1 {
		t.Fatalf("%d successful replays, want one", successes)
	}
}

// The expected digest was independently computed with Python hashlib and is
// also asserted by the Swift API client's tests. Keep both ends byte-compatible.
func TestCanonicalRequestDataMatchesSwiftFixture(t *testing.T) {
	t.Parallel()
	challenge := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))
	request := httptest.NewRequest(http.MethodGet, "/v1/quran/chapters?language=en&page=1", nil)
	clientDataHash := sha256.Sum256(canonicalRequestData(request, nil, challenge))
	if got := hex.EncodeToString(clientDataHash[:]); got != "821dcc033488fb08e892feeeccc1eb05b0610223fa2ed48072c380be9ce33a34" {
		t.Fatalf("canonical data hash differs from Swift: %s", got)
	}
}
