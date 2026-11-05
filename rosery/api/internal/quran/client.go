// Package quran accesses Quran Foundation's read-only Content API. Credentials
// stay on the backend; this package never performs user authentication.
package quran

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	maxResponseBytes = 2 << 20
	maxTokenBytes    = 16 << 10
	maxCacheEntries  = 128
	maxCacheBytes    = 8 << 20
	maxInFlight      = 32
	requestTimeout   = 10 * time.Second
	cacheLifetime    = 5 * time.Minute
)

// ErrBusy means all upstream request slots are in use. Callers should respond
// with a temporary service-unavailable error instead of adding a work queue.
var ErrBusy = errors.New("quran upstream capacity reached")

// UpstreamError exposes only an HTTP status, never an upstream response body or
// URL. Both may contain sensitive operational information.
type UpstreamError struct {
	StatusCode int
	RetryAfter time.Duration
}

func (e *UpstreamError) Error() string {
	return fmt.Sprintf("quran upstream returned status %d", e.StatusCode)
}

// Config selects one of Quran Foundation's documented environments. HTTPClient
// is optional; redirects and an upper bound on its timeout are always enforced.
type Config struct {
	ClientID     string
	ClientSecret string
	Environment  string
	HTTPClient   *http.Client
}

// Client is safe for concurrent use. Its response cache is process-local,
// bounded, and ephemeral; it is not an offline Content Sync implementation.
type Client struct {
	clientID     string
	clientSecret string
	httpClient   *http.Client
	apiBase      string
	authBase     string
	now          func() time.Time

	mu          sync.Mutex
	token       accessToken
	tokenFlight *tokenCall
	cache       map[string]cacheEntry
	cacheBytes  int
	inFlight    map[string]*contentCall
	retryAt     time.Time
	retryStatus int
}

type accessToken struct {
	value     string
	expiresAt time.Time
}

type tokenCall struct {
	done  chan struct{}
	token accessToken
	err   error
}

type cacheEntry struct {
	data      []byte
	expiresAt time.Time
}

type contentCall struct {
	done chan struct{}
	data []byte
	err  error
}

// New validates configuration and creates a client restricted to the official
// service hosts. Custom base URLs cannot be supplied through configuration.
func New(cfg Config) (*Client, error) {
	if strings.TrimSpace(cfg.ClientID) == "" || strings.TrimSpace(cfg.ClientSecret) == "" {
		return nil, errors.New("quran client credentials are required")
	}
	if strings.ContainsAny(cfg.ClientID, "\r\n:") || strings.ContainsAny(cfg.ClientSecret, "\r\n") {
		return nil, errors.New("quran client credentials have invalid characters")
	}
	var apiBase, authBase string
	switch cfg.Environment {
	case "prelive":
		apiBase = "https://apis-prelive.quran.foundation"
		authBase = "https://prelive-oauth2.quran.foundation"
	case "production":
		apiBase = "https://apis.quran.foundation"
		authBase = "https://oauth2.quran.foundation"
	default:
		return nil, errors.New("quran environment must be prelive or production")
	}
	transport := &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 3 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSClientConfig:       &tls.Config{MinVersion: tls.VersionTLS12},
		TLSHandshakeTimeout:   3 * time.Second,
		ResponseHeaderTimeout: 5 * time.Second,
		IdleConnTimeout:       90 * time.Second,
		MaxIdleConns:          32,
		MaxIdleConnsPerHost:   16,
		MaxConnsPerHost:       16,
		DisableCompression:    true,
	}
	httpClient := &http.Client{Transport: transport, Timeout: requestTimeout}
	if cfg.HTTPClient != nil {
		cloned := *cfg.HTTPClient
		httpClient = &cloned
		if httpClient.Timeout <= 0 || httpClient.Timeout > requestTimeout {
			httpClient.Timeout = requestTimeout
		}
	}
	httpClient.Jar = nil
	httpClient.CheckRedirect = func(_ *http.Request, _ []*http.Request) error {
		return http.ErrUseLastResponse
	}
	return &Client{
		clientID: cfg.ClientID, clientSecret: cfg.ClientSecret,
		httpClient: httpClient, apiBase: apiBase, authBase: authBase,
		now: time.Now, cache: make(map[string]cacheEntry),
		inFlight: make(map[string]*contentCall),
	}, nil
}

// Get retrieves one allowed read-only endpoint, with bounded response caching.
// Paths are /chapters, /chapters/{1..114}, /verses/by_chapter/{1..114},
// or /resources/translations.
// The HTTP layer should additionally validate its public query parameters.
func (c *Client) Get(ctx context.Context, path string, query url.Values) ([]byte, error) {
	if !allowedPath(path) {
		return nil, errors.New("unsupported quran content path")
	}
	encodedQuery := query.Encode()
	if len(encodedQuery) > 2048 {
		return nil, errors.New("quran query is too long")
	}
	key := path + "?" + encodedQuery
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		c.mu.Lock()
		if entry, ok := c.cache[key]; ok && c.now().Before(entry.expiresAt) {
			data := bytes.Clone(entry.data)
			c.mu.Unlock()
			return data, nil
		}
		if call, ok := c.inFlight[key]; ok {
			c.mu.Unlock()
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-call.done:
				// A canceled leader must not force otherwise-live waiters to fail.
				if isContextError(call.err) && ctx.Err() == nil {
					continue
				}
				return bytes.Clone(call.data), call.err
			}
		}
		if retryAfter := c.retryAt.Sub(c.now()); retryAfter > 0 {
			status := c.retryStatus
			c.mu.Unlock()
			return nil, &UpstreamError{StatusCode: status, RetryAfter: retryAfter}
		}
		if len(c.inFlight) >= maxInFlight {
			c.mu.Unlock()
			return nil, ErrBusy
		}
		call := &contentCall{done: make(chan struct{})}
		c.inFlight[key] = call
		c.mu.Unlock()

		requestCtx, cancel := context.WithTimeout(ctx, requestTimeout)
		data, ttl, err := c.fetch(requestCtx, path, encodedQuery)
		cancel()

		c.mu.Lock()
		if err == nil && ttl > 0 {
			c.cacheResponse(key, data, ttl)
		}
		call.data, call.err = data, err
		delete(c.inFlight, key)
		close(call.done)
		c.mu.Unlock()
		return bytes.Clone(data), err
	}
}

func allowedPath(path string) bool {
	if path == "/chapters" || path == "/resources/translations" {
		return true
	}
	var suffix string
	switch {
	case strings.HasPrefix(path, "/chapters/"):
		suffix = strings.TrimPrefix(path, "/chapters/")
	case strings.HasPrefix(path, "/verses/by_chapter/"):
		suffix = strings.TrimPrefix(path, "/verses/by_chapter/")
	default:
		return false
	}
	id, err := strconv.Atoi(suffix)
	return err == nil && id >= 1 && id <= 114 && strconv.Itoa(id) == suffix
}

func (c *Client) fetch(ctx context.Context, path, encodedQuery string) ([]byte, time.Duration, error) {
	for attempt := 0; attempt < 2; attempt++ {
		token, err := c.getToken(ctx)
		if err != nil {
			return nil, 0, fmt.Errorf("obtain quran token: %w", err)
		}
		endpoint := c.apiBase + "/content/api/v4" + path
		if encodedQuery != "" {
			endpoint += "?" + encodedQuery
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
		if err != nil {
			return nil, 0, errors.New("construct quran content request")
		}
		req.Header.Set("Accept", "application/json")
		req.Header.Set("Accept-Encoding", "identity")
		req.Header.Set("x-auth-token", token.value)
		req.Header.Set("x-client-id", c.clientID)
		response, err := c.httpClient.Do(req)
		if err != nil {
			return nil, 0, safeRequestError(ctx, err)
		}
		data, readErr := readResponse(response, maxResponseBytes)
		c.recordCooldown(response, false)
		if response.StatusCode == http.StatusUnauthorized {
			c.invalidateToken(token.value)
			if attempt == 0 {
				continue
			}
		}
		if readErr != nil {
			if err := ctx.Err(); err != nil {
				return nil, 0, err
			}
			return nil, 0, readErr
		}
		if !json.Valid(data) {
			return nil, 0, errors.New("quran upstream returned invalid json")
		}
		return data, responseCacheTTL(response.Header, c.now()), nil
	}
	return nil, 0, &UpstreamError{StatusCode: http.StatusUnauthorized}
}

func (c *Client) getToken(ctx context.Context) (accessToken, error) {
	for {
		if err := ctx.Err(); err != nil {
			return accessToken{}, err
		}
		c.mu.Lock()
		if c.token.value != "" && c.now().Before(c.token.expiresAt) {
			token := c.token
			c.mu.Unlock()
			return token, nil
		}
		if call := c.tokenFlight; call != nil {
			c.mu.Unlock()
			select {
			case <-ctx.Done():
				return accessToken{}, ctx.Err()
			case <-call.done:
				if isContextError(call.err) && ctx.Err() == nil {
					continue
				}
				return call.token, call.err
			}
		}
		call := &tokenCall{done: make(chan struct{})}
		c.tokenFlight = call
		c.mu.Unlock()

		token, err := c.requestToken(ctx)
		c.mu.Lock()
		if err == nil {
			c.token = token
		}
		call.token, call.err = token, err
		c.tokenFlight = nil
		close(call.done)
		c.mu.Unlock()
		return token, err
	}
}

func (c *Client) requestToken(ctx context.Context) (accessToken, error) {
	form := url.Values{"grant_type": {"client_credentials"}, "scope": {"content"}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.authBase+"/oauth2/token", strings.NewReader(form.Encode()))
	if err != nil {
		return accessToken{}, errors.New("construct quran token request")
	}
	req.SetBasicAuth(c.clientID, c.clientSecret)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Accept-Encoding", "identity")
	response, err := c.httpClient.Do(req)
	if err != nil {
		return accessToken{}, safeRequestError(ctx, err)
	}
	data, err := readResponse(response, maxTokenBytes)
	c.recordCooldown(response, true)
	if err != nil {
		if contextErr := ctx.Err(); contextErr != nil {
			return accessToken{}, contextErr
		}
		return accessToken{}, err
	}
	var payload struct {
		AccessToken string `json:"access_token"`
		TokenType   string `json:"token_type"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return accessToken{}, errors.New("quran token response is invalid")
	}
	if payload.AccessToken == "" || len(payload.AccessToken) > 8192 || strings.ContainsAny(payload.AccessToken, "\r\n") ||
		!strings.EqualFold(payload.TokenType, "Bearer") || payload.ExpiresIn <= 0 || payload.ExpiresIn > 24*60*60 {
		return accessToken{}, errors.New("quran token response has invalid fields")
	}
	lifetime := time.Duration(payload.ExpiresIn) * time.Second
	// Refresh 10% early, up to one minute, including short-lived test tokens.
	margin := min(lifetime/10, time.Minute)
	return accessToken{value: payload.AccessToken, expiresAt: c.now().Add(lifetime - margin)}, nil
}

func (c *Client) invalidateToken(rejected string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	// A delayed 401 for an old token must not invalidate a newer token.
	if c.token.value == rejected {
		c.token = accessToken{}
	}
}

// cacheResponse must be called with mu held. No background cleanup goroutine is
// needed: each insertion removes expired entries and evicts oldest entries.
func (c *Client) cacheResponse(key string, data []byte, ttl time.Duration) {
	now := c.now()
	for key, entry := range c.cache {
		if !now.Before(entry.expiresAt) {
			delete(c.cache, key)
			c.cacheBytes -= len(entry.data)
		}
	}
	if entry, ok := c.cache[key]; ok {
		delete(c.cache, key)
		c.cacheBytes -= len(entry.data)
	}
	for len(c.cache) >= maxCacheEntries || c.cacheBytes+len(data) > maxCacheBytes {
		var oldestKey string
		var oldestTime time.Time
		for candidateKey, entry := range c.cache {
			if oldestTime.IsZero() || entry.expiresAt.Before(oldestTime) {
				oldestKey, oldestTime = candidateKey, entry.expiresAt
			}
		}
		entry := c.cache[oldestKey]
		delete(c.cache, oldestKey)
		c.cacheBytes -= len(entry.data)
	}
	c.cache[key] = cacheEntry{data: data, expiresAt: now.Add(ttl)}
	c.cacheBytes += len(data)
}

// Honor upstream storage restrictions and use the shortest applicable lifetime.
// We never revalidate stored responses, so no-cache also disables this cache.
func responseCacheTTL(header http.Header, now time.Time) time.Duration {
	ttl := cacheLifetime
	maxAge, sharedMaxAge := "", ""
	hasMaxAge, hasSharedMaxAge := false, false
	for _, directive := range strings.Split(strings.Join(header.Values("Cache-Control"), ","), ",") {
		name, value, _ := strings.Cut(strings.TrimSpace(directive), "=")
		switch strings.ToLower(strings.TrimSpace(name)) {
		case "no-store", "no-cache", "private":
			return 0
		case "max-age":
			if hasMaxAge {
				return 0
			}
			hasMaxAge = true
			maxAge = strings.Trim(strings.TrimSpace(value), `"`)
		case "s-maxage":
			if hasSharedMaxAge {
				return 0
			}
			hasSharedMaxAge = true
			sharedMaxAge = strings.Trim(strings.TrimSpace(value), `"`)
		}
	}
	for _, vary := range strings.Split(strings.Join(header.Values("Vary"), ","), ",") {
		if strings.TrimSpace(vary) == "*" {
			return 0
		}
	}
	if hasSharedMaxAge {
		maxAge = sharedMaxAge
	}
	if hasMaxAge || hasSharedMaxAge {
		seconds, err := strconv.ParseInt(maxAge, 10, 64)
		if err != nil || seconds < 0 {
			return 0
		}
		ttl = min(ttl, time.Duration(min(seconds, int64(cacheLifetime/time.Second)))*time.Second)
	} else if expires, err := http.ParseTime(header.Get("Expires")); err == nil {
		base := now
		if date, err := http.ParseTime(header.Get("Date")); err == nil {
			base = date
		}
		ttl = min(ttl, expires.Sub(base))
	}
	if age := header.Get("Age"); age != "" {
		seconds, err := strconv.ParseInt(age, 10, 64)
		if err != nil || seconds < 0 || seconds >= int64(cacheLifetime/time.Second) {
			return 0
		}
		ttl -= time.Duration(seconds) * time.Second
	}
	return max(0, ttl)
}

// A short provider-wide cooldown prevents sequential cache misses from turning
// upstream throttling or an outage into a flood of retries. No error body or
// credential is retained. Healthy cached content remains available throughout.
func (c *Client) recordCooldown(response *http.Response, auth bool) {
	var delay time.Duration
	switch response.StatusCode {
	case http.StatusTooManyRequests:
		delay = 30 * time.Second
	case http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout:
		delay = 5 * time.Second
	case http.StatusUnauthorized, http.StatusForbidden:
		if auth {
			delay = 30 * time.Second
		}
	}
	if delay == 0 {
		return
	}
	now := c.now()
	if raw := response.Header.Get("Retry-After"); raw != "" {
		if seconds, err := strconv.ParseInt(raw, 10, 64); err == nil && seconds >= 0 {
			delay = time.Duration(min(seconds, int64(time.Hour/time.Second))) * time.Second
		} else if until, err := http.ParseTime(raw); err == nil {
			delay = until.Sub(now)
		}
	}
	delay = min(time.Hour, max(time.Second, delay))
	c.mu.Lock()
	defer c.mu.Unlock()
	if next := now.Add(delay); next.After(c.retryAt) {
		c.retryAt = next
		c.retryStatus = response.StatusCode
	}
}

func readResponse(response *http.Response, maxBytes int64) ([]byte, error) {
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		// Do not read an untrusted error body: no sensitive text can escape,
		// and an attacker-controlled upstream cannot make it consume memory.
		return nil, &UpstreamError{StatusCode: response.StatusCode}
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, maxBytes+1))
	if err != nil {
		return nil, errors.New("read quran upstream response")
	}
	if int64(len(data)) > maxBytes {
		return nil, errors.New("quran upstream response is too large")
	}
	return data, nil
}

func safeRequestError(ctx context.Context, err error) error {
	if contextErr := ctx.Err(); contextErr != nil {
		return contextErr
	}
	var timeout net.Error
	if errors.As(err, &timeout) && timeout.Timeout() {
		return context.DeadlineExceeded
	}
	return errors.New("quran upstream request failed")
}

func isContextError(err error) bool {
	return errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}
