package httpapi

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"rosery/api/internal/attest"
	"rosery/api/internal/config"
	"rosery/api/internal/quran"
)

type fakeAttester struct{ verified atomic.Int32 }

type panickingAttester struct{ fakeAttester }

func (*panickingAttester) Verify(*http.Request, []byte) error { panic("test panic") }

func (f *fakeAttester) Challenge(key, purpose string) (attest.Challenge, error) {
	if key == "" || (purpose != "attest" && purpose != "assert") {
		return attest.Challenge{}, attest.ErrInvalid
	}
	return attest.Challenge{Challenge: "one-time", ExpiresAt: time.Now().Add(time.Minute)}, nil
}
func (f *fakeAttester) Attest(key, challenge, object string) error {
	if key == "" || challenge == "" || object == "" {
		return attest.ErrInvalid
	}
	return nil
}
func (f *fakeAttester) Verify(r *http.Request, body []byte) error {
	f.verified.Add(1)
	if r.Header.Get("X-App-Attest-Assertion") != "valid" {
		return attest.ErrInvalid
	}
	return nil
}

type fakeContent struct {
	calls atomic.Int32
	err   error
	path  string
	query url.Values
}

func (f *fakeContent) Get(_ context.Context, path string, query url.Values) ([]byte, error) {
	f.calls.Add(1)
	f.path, f.query = path, query
	return []byte(`{"verses":[{"text_uthmani":"بِسْمِ ٱللَّهِ"}]}`), f.err
}
func testServer() (*Server, *fakeContent) {
	q := &fakeContent{}
	return New(config.Config{Environment: "development", MaxConcurrent: 8}, &fakeAttester{}, q, slog.New(slog.NewTextHandler(io.Discard, nil))), q
}
func request(s *Server, method, path, body string, verified bool) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if verified {
		r.Header.Set("X-App-Attest-Assertion", "valid")
		r.Header.Set("X-App-Attest-Key-ID", "registered-key")
	}
	if method == http.MethodPost {
		r.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	return w
}

func TestProtectedRoutesAndValidation(t *testing.T) {
	tests := []struct {
		name, method, path, body string
		signed                   bool
		status                   int
	}{
		{"health", "GET", "/healthz", "", false, 200},
		{"unsigned content", "GET", "/v1/quran/chapters", "", false, 401},
		{"valid chapter list", "GET", "/v1/quran/chapters?language=en", "", true, 200},
		{"chapter bounds", "GET", "/v1/quran/chapters/115", "", true, 404},
		{"encoded path", "GET", "/v1/quran/chapters/%31", "", true, 404},
		{"path traversal", "GET", "/v1/quran/chapters/../resources", "", true, 404},
		{"arbitrary proxy", "GET", "/v1/quran/https://evil.example", "", true, 404},
		{"unknown query", "GET", "/v1/quran/chapters?url=https://evil.example", "", true, 400},
		{"duplicate query", "GET", "/v1/quran/chapters?language=en&language=ar", "", true, 400},
		{"oversized pagination", "GET", "/v1/quran/verses/by_chapter/2?per_page=999", "", true, 400},
		{"empty page", "GET", "/v1/quran/verses/by_chapter/2?page=", "", true, 400},
		{"invalid percent", "GET", "/v1/quran/chapters?language=%xx", "", true, 400},
		{"body on get", "GET", "/v1/quran/chapters", "payload", true, 400},
		{"write content", "DELETE", "/v1/quran/chapters", "", true, 405},
		{"bad enrollment", "POST", "/v1/attest/register", `{}`, false, 401},
		{"unknown field", "POST", "/v1/attest/challenge", `{"key_id":"a","purpose":"attest","bypass":true}`, false, 400},
		{"multiple objects", "POST", "/v1/attest/challenge", `{} {}`, false, 400},
		{"oversized body", "POST", "/v1/attest/register", `{"attestation":"` + strings.Repeat("a", maxBody) + `"}`, false, 413},
		{"valid challenge", "POST", "/v1/attest/challenge", `{"key_id":"a","purpose":"attest"}`, false, 200},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s, q := testServer()
			w := request(s, tt.method, tt.path, tt.body, tt.signed)
			if w.Code != tt.status {
				t.Fatalf("status=%d body=%s, want %d", w.Code, w.Body.String(), tt.status)
			}
			if tt.status != 200 && q.calls.Load() != 0 {
				t.Fatal("rejected request reached provider")
			}
			if w.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("protected response may be cached downstream")
			}
		})
	}
}

func TestArabicAndServerOwnedFields(t *testing.T) {
	s, q := testServer()
	w := request(s, "GET", "/v1/quran/verses/by_chapter/1?words=true&translations=20", "", true)
	if w.Code != 200 || !strings.Contains(w.Body.String(), "بِسْمِ ٱللَّهِ") {
		t.Fatalf("response=%d %s", w.Code, w.Body.String())
	}
	if q.path != "/verses/by_chapter/1" || q.query.Get("fields") != "text_uthmani" || q.query.Get("per_page") != "20" || q.query.Get("word_fields") != "text_uthmani" {
		t.Fatalf("unexpected provider request %s %v", q.path, q.query)
	}
}

func TestUntrustedForwardingCannotResetRateLimit(t *testing.T) {
	s, _ := testServer()
	s.ips = newLimiter(0, 1, 5)
	for i, spoof := range []string{"203.0.113.1", "203.0.113.2"} {
		r := httptest.NewRequest("GET", "/v1/quran/chapters", nil)
		r.Header.Set("X-App-Attest-Assertion", "valid")
		r.Header.Set("X-App-Attest-Key-ID", "registered-key")
		r.Header.Set("X-Forwarded-For", spoof)
		w := httptest.NewRecorder()
		s.ServeHTTP(w, r)
		want := 200
		if i == 1 {
			want = 429
		}
		if w.Code != want {
			t.Fatalf("spoofed IP reset quota: %d", w.Code)
		}
	}
}

func TestProductionOriginAndProxyTrust(t *testing.T) {
	s, _ := testServer()
	s.cfg.Environment = "production"
	s.cfg.OriginToken = strings.Repeat("private-server-token", 3)
	s.cfg.TrustedProxies = []netip.Prefix{netip.MustParsePrefix("127.0.0.1/32")}
	for _, tc := range []struct {
		peer, token, proto string
		allowed            bool
	}{
		{"198.51.100.1:1234", s.cfg.OriginToken, "https", false},
		{"127.0.0.1:1234", "wrong", "https", false},
		{"127.0.0.1:1234", s.cfg.OriginToken, "http", false},
		{"127.0.0.1:1234", s.cfg.OriginToken, "https", true},
	} {
		r := httptest.NewRequest("GET", "/healthz", nil)
		r.RemoteAddr = tc.peer
		r.Header.Set("X-Rosery-Origin-Token", tc.token)
		r.Header.Set("X-Forwarded-Proto", tc.proto)
		r.Header.Set("X-Forwarded-For", "1.1.1.1, 203.0.113.7")
		ip, ok := s.clientIP(r)
		if ok != tc.allowed {
			t.Fatalf("origin allowed=%v want=%v", ok, tc.allowed)
		}
		if ok && ip != "203.0.113.7" {
			t.Fatalf("trusted attacker-controlled leftmost XFF: %s", ip)
		}
	}
}

func TestBoundedWorkAndRateLimits(t *testing.T) {
	t.Run("verification panic releases capacity", func(t *testing.T) {
		s, _ := testServer()
		s.cryptoSlots = make(chan struct{}, 1)
		s.attest = &panickingAttester{}
		if w := request(s, "GET", "/v1/quran/chapters", "", true); w.Code != 500 {
			t.Fatalf("panic response=%d", w.Code)
		}
		s.attest = &fakeAttester{}
		if w := request(s, "GET", "/v1/quran/chapters", "", true); w.Code != 200 {
			t.Fatalf("verification capacity leaked after recovery: %d", w.Code)
		}
	})
	t.Run("liveness survives content saturation", func(t *testing.T) {
		s, q := testServer()
		s.slots = make(chan struct{}, 1)
		s.slots <- struct{}{}
		s.global = newLimiter(0, 0, 1)
		w := request(s, "GET", "/healthz", "", false)
		if w.Code != 200 || q.calls.Load() != 0 {
			t.Fatal("healthy saturated process would be restarted")
		}
	})
	t.Run("concurrency", func(t *testing.T) {
		s, q := testServer()
		s.slots = make(chan struct{}, 1)
		s.slots <- struct{}{}
		w := request(s, "GET", "/v1/quran/chapters", "", true)
		if w.Code != 503 || q.calls.Load() != 0 {
			t.Fatal("overload should reject before expensive work")
		}
	})
	t.Run("device", func(t *testing.T) {
		s, q := testServer()
		s.devices = newLimiter(0, 1, 2)
		request(s, "GET", "/v1/quran/chapters", "", true)
		w := request(s, "GET", "/v1/quran/chapters", "", true)
		if w.Code != 429 || w.Header().Get("Retry-After") == "" || q.calls.Load() != 1 {
			t.Fatal("device quota failed")
		}
	})
	t.Run("assertion challenges do not use enrollment quota", func(t *testing.T) {
		s, _ := testServer()
		for range 10 {
			w := request(s, "POST", "/v1/attest/challenge", `{"key_id":"known","purpose":"assert"}`, false)
			if w.Code != 200 {
				t.Fatalf("ordinary assertion challenge incorrectly enrollment-limited: %d", w.Code)
			}
		}
	})
}

func TestProviderErrorsDoNotLeak(t *testing.T) {
	for _, err := range []error{errors.New("secret internal URL and token"), &quran.UpstreamError{StatusCode: 429}, context.DeadlineExceeded} {
		s, q := testServer()
		q.err = err
		w := request(s, "GET", "/v1/quran/chapters", "", true)
		if w.Code < 500 || strings.Contains(w.Body.String(), "secret") {
			t.Fatalf("unsafe provider error: %d %s", w.Code, w.Body.String())
		}
	}
}

func TestLimiterCapacityRefillAndIPv6(t *testing.T) {
	l := newLimiter(1, 1, 2)
	now := time.Now()
	l.now = func() time.Time { return now }
	if !l.allow("a") || l.allow("a") || !l.allow("b") || l.allow("c") {
		t.Fatal("capacity or quota failed")
	}
	now = now.Add(2 * time.Second)
	if !l.allow("a") || l.allow("c") {
		t.Fatal("existing quota refill or bounded table failed")
	}
	now = now.Add(11 * time.Minute)
	if !l.allow("c") {
		t.Fatal("expired identities not removed")
	}
	s, _ := testServer()
	r := httptest.NewRequest("GET", "/healthz", nil)
	r.RemoteAddr = "[2001:db8::1234]:1234"
	ip, ok := s.clientIP(r)
	if !ok || ip != "2001:db8::/64" {
		t.Fatalf("IPv6 bucket=%s", ip)
	}
}
