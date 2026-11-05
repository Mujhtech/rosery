package quran

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func testClient(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	client, err := New(Config{
		ClientID: "test-client", ClientSecret: "test-secret", Environment: "prelive",
		HTTPClient: server.Client(),
	})
	if err != nil {
		t.Fatal(err)
	}
	// Base URLs are deliberately not public configuration. Only package-local
	// tests redirect requests away from the fixed official service hosts.
	client.apiBase = server.URL
	client.authBase = server.URL
	return client
}

func writeToken(w http.ResponseWriter, token string) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = fmt.Fprintf(w, `{"access_token":%q,"token_type":"Bearer","expires_in":3600}`, token)
}

func TestConfigurationAndAllowedPaths(t *testing.T) {
	for _, cfg := range []Config{
		{},
		{ClientID: "id", ClientSecret: "secret", Environment: "http://attacker"},
		{ClientID: "id:extra", ClientSecret: "secret", Environment: "prelive"},
		{ClientID: "id", ClientSecret: "bad\r\nsecret", Environment: "prelive"},
	} {
		if _, err := New(cfg); err == nil {
			t.Errorf("accepted invalid config for environment %q", cfg.Environment)
		}
	}
	for _, environment := range []string{"prelive", "production"} {
		client, err := New(Config{ClientID: "id", ClientSecret: "secret", Environment: environment})
		if err != nil {
			t.Fatal(err)
		}
		if !strings.HasPrefix(client.apiBase, "https://") || !strings.HasPrefix(client.authBase, "https://") {
			t.Fatal("non-https base URL")
		}
	}
	for _, path := range []string{"https://attacker.test", "//attacker.test", "/chapters/../x", "/chapters/1?q=x", "/chapters/0", "/chapters/115", "/chapters/01", "/chapters/+1", "/chapters/%31", "/verses/by_chapter/1/extra"} {
		if allowedPath(path) {
			t.Errorf("accepted path %q", path)
		}
	}
	for _, path := range []string{"/chapters", "/chapters/1", "/chapters/114", "/verses/by_chapter/2", "/resources/translations"} {
		if !allowedPath(path) {
			t.Errorf("rejected path %q", path)
		}
	}
}

func TestOAuthAndResponseCaching(t *testing.T) {
	var tokenCalls, contentCalls atomic.Int32
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			tokenCalls.Add(1)
			id, secret, ok := r.BasicAuth()
			if !ok || id != "test-client" || secret != "test-secret" || r.Method != http.MethodPost {
				t.Error("invalid OAuth authentication")
			}
			if err := r.ParseForm(); err != nil || r.Form.Get("grant_type") != "client_credentials" || r.Form.Get("scope") != "content" {
				t.Error("invalid OAuth form")
			}
			writeToken(w, "first-token")
			return
		}
		contentCalls.Add(1)
		if r.Header.Get("x-auth-token") != "first-token" || r.Header.Get("x-client-id") != "test-client" || r.Header.Get("Authorization") != "" {
			t.Error("invalid content credentials")
		}
		if r.URL.Path != "/content/api/v4/chapters" || r.URL.Query().Get("language") != "en" {
			t.Error("incorrect content endpoint")
		}
		_, _ = io.WriteString(w, `{"chapters":[{"id":1}]}`)
	})
	query := url.Values{"language": {"en"}}
	first, err := client.Get(context.Background(), "/chapters", query)
	if err != nil {
		t.Fatal(err)
	}
	first[0] = 'X'
	second, err := client.Get(context.Background(), "/chapters", query)
	if err != nil || !json.Valid(second) {
		t.Fatalf("cache data mutated: %q, %v", second, err)
	}
	if tokenCalls.Load() != 1 || contentCalls.Load() != 1 {
		t.Fatalf("unexpected requests: tokens=%d content=%d", tokenCalls.Load(), contentCalls.Load())
	}
}

func TestConcurrentIdenticalRequestsCoalesce(t *testing.T) {
	var tokens, requests atomic.Int32
	entered := make(chan struct{})
	release := make(chan struct{})
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			tokens.Add(1)
			writeToken(w, "token")
			return
		}
		if requests.Add(1) == 1 {
			close(entered)
		}
		<-release
		_, _ = io.WriteString(w, `{"chapters":[]}`)
	})
	var group sync.WaitGroup
	for range 16 {
		group.Go(func() {
			data, err := client.Get(context.Background(), "/chapters", nil)
			if err != nil || !json.Valid(data) {
				t.Errorf("Get failed: %v", err)
			}
		})
	}
	<-entered
	close(release)
	group.Wait()
	if tokens.Load() != 1 || requests.Load() != 1 {
		t.Fatalf("requests were not coalesced: tokens=%d content=%d", tokens.Load(), requests.Load())
	}
}

func TestConcurrentDistinctRequestsShareToken(t *testing.T) {
	var tokens atomic.Int32
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			tokens.Add(1)
			writeToken(w, "token")
			return
		}
		_, _ = io.WriteString(w, `{"chapter":{}}`)
	})
	var group sync.WaitGroup
	for id := 1; id <= 16; id++ {
		group.Go(func() {
			if _, err := client.Get(context.Background(), fmt.Sprintf("/chapters/%d", id), nil); err != nil {
				t.Error(err)
			}
		})
	}
	group.Wait()
	if tokens.Load() != 1 {
		t.Fatalf("got %d token requests, want 1", tokens.Load())
	}
}

func TestUnauthorizedRefreshesOnce(t *testing.T) {
	var tokens, requests atomic.Int32
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			writeToken(w, fmt.Sprintf("token-%d", tokens.Add(1)))
			return
		}
		requests.Add(1)
		if r.Header.Get("x-auth-token") == "token-1" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_, _ = io.WriteString(w, `{"chapters":[]}`)
	})
	if _, err := client.Get(context.Background(), "/chapters", nil); err != nil {
		t.Fatal(err)
	}
	if tokens.Load() != 2 || requests.Load() != 2 {
		t.Fatalf("unexpected retries: tokens=%d content=%d", tokens.Load(), requests.Load())
	}
	client.invalidateToken("token-1")
	client.mu.Lock()
	actual := client.token.value
	client.mu.Unlock()
	if actual != "token-2" {
		t.Fatal("a delayed 401 invalidated the replacement token")
	}
}

func TestUnauthorizedDoesNotLoop(t *testing.T) {
	var tokens, requests atomic.Int32
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			tokens.Add(1)
			writeToken(w, "token")
			return
		}
		requests.Add(1)
		w.WriteHeader(http.StatusUnauthorized)
	})
	_, err := client.Get(context.Background(), "/chapters", nil)
	var upstream *UpstreamError
	if !errors.As(err, &upstream) || upstream.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unexpected error: %v", err)
	}
	if tokens.Load() != 2 || requests.Load() != 2 {
		t.Fatal("unexpected retry count")
	}
}

func TestErrorsDoNotExposeSecretsAndAreNotCached(t *testing.T) {
	var requests atomic.Int32
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			writeToken(w, "secret-access-token")
			return
		}
		requests.Add(1)
		w.WriteHeader(http.StatusBadRequest)
		_, _ = io.WriteString(w, `test-secret secret-access-token internal credentials`)
	})
	for range 2 {
		_, err := client.Get(context.Background(), "/chapters", nil)
		var upstream *UpstreamError
		if !errors.As(err, &upstream) || upstream.StatusCode != http.StatusBadRequest {
			t.Fatalf("unexpected error: %v", err)
		}
		if strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), "credentials") {
			t.Fatal("upstream body escaped through error")
		}
	}
	if requests.Load() != 2 {
		t.Fatal("upstream error was cached")
	}
}

func TestRedirectsNeverForwardCredentials(t *testing.T) {
	for _, redirectToken := range []bool{true, false} {
		t.Run(fmt.Sprintf("token=%t", redirectToken), func(t *testing.T) {
			var attackerCalls atomic.Int32
			attacker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				attackerCalls.Add(1)
				w.WriteHeader(http.StatusOK)
			}))
			t.Cleanup(attacker.Close)
			client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/oauth2/token" && !redirectToken {
					writeToken(w, "token")
					return
				}
				http.Redirect(w, r, attacker.URL, http.StatusTemporaryRedirect)
			})
			_, err := client.Get(context.Background(), "/chapters", nil)
			var upstream *UpstreamError
			if !errors.As(err, &upstream) || upstream.StatusCode != http.StatusTemporaryRedirect || attackerCalls.Load() != 0 {
				t.Fatalf("redirect was not blocked: %v, calls=%d", err, attackerCalls.Load())
			}
		})
	}
}

func TestResponseValidationAndLimits(t *testing.T) {
	for _, test := range []struct {
		name string
		body string
	}{
		{name: "invalid-json", body: "not-json"},
		{name: "oversize", body: `{"text":"` + strings.Repeat("a", maxResponseBytes) + `"}`},
	} {
		t.Run(test.name, func(t *testing.T) {
			client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/oauth2/token" {
					writeToken(w, "token")
					return
				}
				_, _ = io.WriteString(w, test.body)
			})
			if _, err := client.Get(context.Background(), "/chapters", nil); err == nil {
				t.Fatal("accepted invalid upstream response")
			}
		})
	}
}

func TestTokenValidation(t *testing.T) {
	for _, body := range []string{
		`{"access_token":"token","token_type":"Bearer","expires_in":0}`,
		`{"access_token":"token","token_type":"Bearer","expires_in":99999999999999}`,
		`{"access_token":"token\r\nheader","token_type":"Bearer","expires_in":3600}`,
		`{"access_token":"token","token_type":"Basic","expires_in":3600}`,
		`{"access_token":"token","token_type":"Bearer","expires_in":3600} junk`,
		strings.Repeat("x", maxTokenBytes+1),
	} {
		client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
			_, _ = io.WriteString(w, body)
		})
		if _, err := client.Get(context.Background(), "/chapters", nil); err == nil {
			t.Fatal("accepted invalid token response")
		}
	}
}

func TestWaitingCallerCanCancel(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			writeToken(w, "token")
			return
		}
		close(entered)
		<-release
		_, _ = io.WriteString(w, `{"chapters":[]}`)
	})
	done := make(chan error, 1)
	go func() {
		_, err := client.Get(context.Background(), "/chapters", nil)
		done <- err
	}()
	<-entered
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := client.Get(ctx, "/chapters", nil); !errors.Is(err, context.Canceled) {
		t.Fatalf("got %v, want canceled", err)
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestCanceledLeaderDoesNotCancelOtherCallers(t *testing.T) {
	var requests atomic.Int32
	entered := make(chan struct{})
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			writeToken(w, "token")
			return
		}
		if requests.Add(1) == 1 {
			close(entered)
			<-r.Context().Done()
			return
		}
		_, _ = io.WriteString(w, `{"chapters":[]}`)
	})
	ctx, cancel := context.WithCancel(context.Background())
	leaderDone := make(chan error, 1)
	go func() {
		_, err := client.Get(ctx, "/chapters", nil)
		leaderDone <- err
	}()
	<-entered
	followerDone := make(chan error, 1)
	go func() {
		_, err := client.Get(context.Background(), "/chapters", nil)
		followerDone <- err
	}()
	cancel()
	if err := <-leaderDone; !errors.Is(err, context.Canceled) {
		t.Fatalf("leader: %v", err)
	}
	if err := <-followerDone; err != nil {
		t.Fatalf("follower inherited cancellation: %v", err)
	}
}

func TestCacheExpirationAndBoundedMemory(t *testing.T) {
	var requests atomic.Int32
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			writeToken(w, "token")
			return
		}
		requests.Add(1)
		_, _ = io.WriteString(w, `{"chapters":[]}`)
	})
	now := time.Now()
	client.now = func() time.Time { return now }
	if _, err := client.Get(context.Background(), "/chapters", nil); err != nil {
		t.Fatal(err)
	}
	now = now.Add(cacheLifetime + time.Second)
	if _, err := client.Get(context.Background(), "/chapters", nil); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != 2 {
		t.Fatal("expired cached content was returned")
	}
	client.mu.Lock()
	for id := range maxCacheEntries * 2 {
		client.cacheResponse(fmt.Sprintf("key-%d", id), make([]byte, 128<<10), cacheLifetime)
	}
	if len(client.cache) > maxCacheEntries || client.cacheBytes > maxCacheBytes {
		t.Fatal("cache limits exceeded")
	}
	client.mu.Unlock()
}

func TestUpstreamCapacityIsBounded(t *testing.T) {
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("a request escaped the capacity limit")
	})
	client.mu.Lock()
	for id := range maxInFlight {
		client.inFlight[fmt.Sprintf("busy-%d", id)] = &contentCall{done: make(chan struct{})}
	}
	client.mu.Unlock()
	if _, err := client.Get(context.Background(), "/chapters", nil); !errors.Is(err, ErrBusy) {
		t.Fatalf("got %v, want busy", err)
	}
}

func TestTranslationsResource(t *testing.T) {
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			writeToken(w, "token")
			return
		}
		if r.URL.Path != "/content/api/v4/resources/translations" {
			t.Errorf("unexpected path: %q", r.URL.Path)
		}
		_, _ = io.WriteString(w, `{"translations":[]}`)
	})
	if _, err := client.Get(context.Background(), "/resources/translations", nil); err != nil {
		t.Fatal(err)
	}
}

func TestResponseCacheDirectives(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	for _, test := range []struct {
		name   string
		header http.Header
		want   time.Duration
	}{
		{name: "default", want: cacheLifetime},
		{name: "no-store", header: http.Header{"Cache-Control": {"public, no-store"}}},
		{name: "no-cache", header: http.Header{"Cache-Control": {"no-cache"}}},
		{name: "private", header: http.Header{"Cache-Control": {`private="authorization"`}}},
		{name: "max-age", header: http.Header{"Cache-Control": {"max-age=60"}}, want: time.Minute},
		{name: "quoted", header: http.Header{"Cache-Control": {`max-age="60"`}}, want: time.Minute},
		{name: "shared-age", header: http.Header{"Cache-Control": {"max-age=60,s-maxage=20"}}, want: 20 * time.Second},
		{name: "bounded", header: http.Header{"Cache-Control": {"max-age=10000000000000"}}, want: cacheLifetime},
		{name: "zero", header: http.Header{"Cache-Control": {"max-age=0"}}},
		{name: "invalid-age", header: http.Header{"Cache-Control": {"max-age=nan"}}},
		{name: "empty-age", header: http.Header{"Cache-Control": {"max-age="}}},
		{name: "duplicate-age", header: http.Header{"Cache-Control": {"max-age=60", "max-age=120"}}},
		{name: "aged", header: http.Header{"Cache-Control": {"max-age=60"}, "Age": {"40"}}, want: 20 * time.Second},
		{name: "stale", header: http.Header{"Cache-Control": {"max-age=60"}, "Age": {"61"}}},
		{name: "vary-any", header: http.Header{"Vary": {"Accept, *"}}},
		{name: "expires", header: http.Header{"Date": {now.Format(http.TimeFormat)}, "Expires": {now.Add(time.Minute).Format(http.TimeFormat)}}, want: time.Minute},
		{name: "expired", header: http.Header{"Date": {now.Format(http.TimeFormat)}, "Expires": {now.Add(-time.Minute).Format(http.TimeFormat)}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := responseCacheTTL(test.header, now); got != test.want {
				t.Fatalf("got %s, want %s", got, test.want)
			}
		})
	}
}

func TestNoStoreResponsesAreNotCached(t *testing.T) {
	var requests atomic.Int32
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth2/token" {
			writeToken(w, "token")
			return
		}
		requests.Add(1)
		w.Header().Set("Cache-Control", "no-store")
		_, _ = io.WriteString(w, `{"chapters":[]}`)
	})
	for range 2 {
		if _, err := client.Get(context.Background(), "/chapters", nil); err != nil {
			t.Fatal(err)
		}
	}
	if requests.Load() != 2 {
		t.Fatal("no-store response was cached")
	}
}

func TestProviderCooldownPreventsSequentialRetryAmplification(t *testing.T) {
	for _, status := range []int{http.StatusTooManyRequests, http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout} {
		t.Run(strconv.Itoa(status), func(t *testing.T) {
			var requests atomic.Int32
			client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/oauth2/token" {
					writeToken(w, "token")
					return
				}
				requests.Add(1)
				if r.URL.Path == "/content/api/v4/chapters" {
					_, _ = io.WriteString(w, `{"chapters":[]}`)
					return
				}
				w.Header().Set("Retry-After", "10")
				w.WriteHeader(status)
			})
			now := time.Now()
			client.now = func() time.Time { return now }
			if _, err := client.Get(context.Background(), "/chapters", nil); err != nil {
				t.Fatal(err)
			}
			if _, err := client.Get(context.Background(), "/chapters/1", nil); err == nil {
				t.Fatal("provider error ignored")
			}
			_, err := client.Get(context.Background(), "/chapters/2", nil)
			var upstream *UpstreamError
			if !errors.As(err, &upstream) || upstream.StatusCode != status || upstream.RetryAfter != 10*time.Second {
				t.Fatalf("unexpected cooldown response: %#v", err)
			}
			if _, err := client.Get(context.Background(), "/chapters", nil); err != nil {
				t.Fatalf("cooldown blocked fresh cached content: %v", err)
			}
			if requests.Load() != 2 {
				t.Fatalf("cooldown allowed more requests: %d", requests.Load())
			}
			now = now.Add(11 * time.Second)
			if _, err := client.Get(context.Background(), "/chapters/2", nil); err == nil || requests.Load() != 3 {
				t.Fatal("cooldown did not expire")
			}
		})
	}
}
