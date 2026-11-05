// Package httpapi exposes a small, accountless Quran content API.
package httpapi

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
	"time"

	"rosery/api/internal/attest"
	"rosery/api/internal/config"
	"rosery/api/internal/quran"
)

const maxBody = 32 << 10

type attester interface {
	Challenge(keyID, purpose string) (attest.Challenge, error)
	Attest(keyID, challenge, object string) error
	Verify(r *http.Request, body []byte) error
}

type contentClient interface {
	Get(context.Context, string, url.Values) ([]byte, error)
}

type Server struct {
	cfg          config.Config
	attest       attester
	content      contentClient
	logger       *slog.Logger
	global       *limiter
	ips          *limiter
	enrollment   *limiter
	registration *limiter
	devices      *limiter
	slots        chan struct{}
	cryptoSlots  chan struct{}
}

func New(cfg config.Config, a attester, q contentClient, logger *slog.Logger) *Server {
	return &Server{
		cfg: cfg, attest: a, content: q, logger: logger,
		global:       newLimiter(100, 200, 1),
		ips:          newLimiter(2, 40, 10000),
		enrollment:   newLimiter(2, 30, 10000),
		registration: newLimiter(6.0/60, 3, 10000),
		devices:      newLimiter(2, 30, 10000),
		slots:        make(chan struct{}, max(1, cfg.MaxConcurrent)),
		cryptoSlots:  make(chan struct{}, 8),
	}
}

func (s *Server) HTTPServer() *http.Server {
	return &http.Server{
		Addr: s.cfg.Address, Handler: s,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      20 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    16 << 10,
		ErrorLog:          slog.NewLogLogger(s.logger.Handler(), slog.LevelWarn),
	}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	if s.cfg.Environment == "production" {
		w.Header().Set("Strict-Transport-Security", "max-age=31536000")
	}
	defer func() {
		if recover() != nil {
			s.logger.Error("request handler panic recovered")
			writeError(w, http.StatusInternalServerError, "internal_error", "Request could not be completed.")
		}
	}()
	if len(r.RequestURI) > 2048 {
		writeError(w, http.StatusRequestURITooLong, "invalid_request", "Request URL is too long.")
		return
	}
	// A healthy process must not be restarted just because content work is full.
	// This tiny origin-checked probe performs no database, proof or upstream work.
	if r.URL.Path == "/healthz" && r.Method == http.MethodGet {
		if _, ok := s.clientIP(r); !ok {
			writeError(w, http.StatusForbidden, "untrusted_origin", "Request origin is not permitted.")
			return
		}
		if r.ContentLength != 0 || len(r.TransferEncoding) != 0 || r.URL.RawQuery != "" {
			writeError(w, http.StatusBadRequest, "invalid_request", "Liveness checks do not accept a body or query.")
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	}
	if !s.global.allow("all") {
		rateError(w)
		return
	}
	select {
	case s.slots <- struct{}{}:
		defer func() { <-s.slots }()
	default:
		unavailable(w)
		return
	}
	ip, ok := s.clientIP(r)
	if !ok {
		writeError(w, http.StatusForbidden, "untrusted_origin", "Request origin is not permitted.")
		return
	}
	if !s.ips.allow(ip) {
		rateError(w)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	r = r.WithContext(ctx)
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	if r.Method == http.MethodGet && (r.ContentLength != 0 || len(r.TransferEncoding) != 0) {
		writeError(w, http.StatusBadRequest, "invalid_request", "GET requests must not contain a body.")
		return
	}
	if r.URL.Path == "/v1/attest/challenge" || r.URL.Path == "/v1/attest/register" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "Use POST for this endpoint.")
			return
		}
		if r.URL.RawQuery != "" || !s.enrollment.allow(ip) {
			if r.URL.RawQuery != "" {
				writeError(w, http.StatusBadRequest, "invalid_request", "Query parameters are not supported.")
			} else {
				rateError(w)
			}
			return
		}
		s.enroll(w, r, ip)
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "Use GET for content endpoints.")
		return
	}
	path, query, err := contentRoute(r.URL)
	if errors.Is(err, errNotFound) {
		writeError(w, http.StatusNotFound, "not_found", "Endpoint was not found.")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid content parameters.")
		return
	}
	// Attestation is checked even on a content-cache hit.
	select {
	case s.cryptoSlots <- struct{}{}:
	default:
		unavailable(w)
		return
	}
	verificationErr := func() error {
		defer func() { <-s.cryptoSlots }()
		return s.attest.Verify(r, nil)
	}()
	if err := verificationErr; err != nil {
		s.attestError(w, err)
		return
	}
	if !s.devices.allow(r.Header.Get("X-App-Attest-Key-ID")) {
		rateError(w)
		return
	}
	body, err := s.content.Get(ctx, path, query)
	if err != nil {
		if errors.Is(err, quran.ErrBusy) {
			unavailable(w)
			return
		}
		// Upstream errors never expose credentials, provider bodies or internal URLs.
		var upstream *quran.UpstreamError
		if errors.As(err, &upstream) && upstream.RetryAfter > 0 {
			seconds := int((upstream.RetryAfter + time.Second - 1) / time.Second)
			w.Header().Set("Retry-After", strconv.Itoa(max(1, seconds)))
			writeError(w, http.StatusServiceUnavailable, "upstream_busy", "Quran content is temporarily busy.")
			return
		}
		if errors.As(err, &upstream) && upstream.StatusCode == http.StatusTooManyRequests {
			w.Header().Set("Retry-After", "30")
			writeError(w, http.StatusServiceUnavailable, "upstream_busy", "Quran content is temporarily busy.")
			return
		}
		if errors.Is(err, context.DeadlineExceeded) {
			writeError(w, http.StatusGatewayTimeout, "upstream_timeout", "Quran content took too long to respond.")
			return
		}
		if errors.Is(err, context.Canceled) {
			return
		}
		s.logger.Warn("Quran provider request failed")
		writeError(w, http.StatusBadGateway, "upstream_unavailable", "Quran content is temporarily unavailable.")
		return
	}
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write(body); err != nil {
		s.logger.Debug("content response interrupted")
	}
}

func (s *Server) enroll(w http.ResponseWriter, r *http.Request, ip string) {
	if r.URL.Path == "/v1/attest/challenge" {
		var body struct {
			KeyID   string `json:"key_id"`
			Purpose string `json:"purpose"`
		}
		if !readJSON(w, r, &body) {
			return
		}
		if body.Purpose == "attest" && !s.registration.allow(ip) {
			rateError(w)
			return
		}
		challenge, err := s.attest.Challenge(body.KeyID, body.Purpose)
		if err != nil {
			s.attestError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, challenge)
		return
	}
	var body struct {
		KeyID       string `json:"key_id"`
		Challenge   string `json:"challenge"`
		Attestation string `json:"attestation"`
	}
	if !readJSON(w, r, &body) {
		return
	}
	if !s.registration.allow(ip) {
		rateError(w)
		return
	}
	select {
	case s.cryptoSlots <- struct{}{}:
		defer func() { <-s.cryptoSlots }()
	default:
		unavailable(w)
		return
	}
	if err := s.attest.Attest(body.KeyID, body.Challenge, body.Attestation); err != nil {
		s.attestError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) attestError(w http.ResponseWriter, err error) {
	if errors.Is(err, attest.ErrUnavailable) {
		unavailable(w)
		return
	}
	writeError(w, http.StatusUnauthorized, "app_verification_failed", "App verification failed. Request a fresh challenge and try again.")
}

func (s *Server) clientIP(r *http.Request) (string, bool) {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return "", false
	}
	peer, err := netip.ParseAddr(host)
	if err != nil {
		return "", false
	}
	peer = peer.Unmap()
	trusted := s.trusted(peer)
	if s.cfg.Environment == "production" || s.cfg.OriginToken != "" {
		actual := sha256.Sum256([]byte(r.Header.Get("X-Rosery-Origin-Token")))
		expected := sha256.Sum256([]byte(s.cfg.OriginToken))
		if !trusted || subtle.ConstantTimeCompare(actual[:], expected[:]) != 1 || r.Header.Get("X-Forwarded-Proto") != "https" {
			return "", false
		}
	}
	// Only an explicitly trusted immediate peer may supply forwarding headers.
	if trusted {
		forwarded := strings.Split(r.Header.Get("X-Forwarded-For"), ",")
		if len(forwarded) > 16 {
			return "", false
		}
		for i := len(forwarded) - 1; i >= 0; i-- {
			if strings.TrimSpace(forwarded[i]) == "" {
				continue
			}
			ip, err := netip.ParseAddr(strings.TrimSpace(forwarded[i]))
			if err != nil {
				return "", false
			}
			peer = ip.Unmap()
			if !s.trusted(peer) {
				break
			}
		}
	}
	if peer.Is6() {
		return netip.PrefixFrom(peer, 64).Masked().String(), true
	}
	return peer.String(), true
}

func (s *Server) trusted(ip netip.Addr) bool {
	for _, prefix := range s.cfg.TrustedProxies {
		if prefix.Contains(ip) {
			return true
		}
	}
	return false
}

var errNotFound = errors.New("content route not found")
var errParameters = errors.New("invalid content parameters")

func contentRoute(u *url.URL) (string, url.Values, error) {
	path := strings.TrimPrefix(u.Path, "/v1/quran")
	if path == u.Path || u.RawPath != "" {
		return "", nil, errNotFound
	}
	verses := false
	switch {
	case path == "/chapters", path == "/resources/translations":
	case strings.HasPrefix(path, "/chapters/"):
		if !validNumber(strings.TrimPrefix(path, "/chapters/"), 1, 114) {
			return "", nil, errNotFound
		}
	case strings.HasPrefix(path, "/verses/by_chapter/"):
		if !validNumber(strings.TrimPrefix(path, "/verses/by_chapter/"), 1, 114) {
			return "", nil, errNotFound
		}
		verses = true
	default:
		return "", nil, errNotFound
	}
	q, err := url.ParseQuery(u.RawQuery)
	if err != nil {
		return "", nil, errParameters
	}
	for key, values := range q {
		if len(values) != 1 {
			return "", nil, errParameters
		}
		value := values[0]
		switch key {
		case "language":
			if len(value) < 2 || len(value) > 3 {
				return "", nil, errParameters
			}
			for _, r := range value {
				if r < 'a' || r > 'z' {
					return "", nil, errParameters
				}
			}
		case "page":
			if !verses || !validNumber(value, 1, 604) {
				return "", nil, errParameters
			}
		case "per_page":
			if !verses || !validNumber(value, 1, 50) {
				return "", nil, errParameters
			}
		case "words":
			if !verses || (value != "true" && value != "false") {
				return "", nil, errParameters
			}
		case "translations":
			ids := strings.Split(value, ",")
			if !verses || len(ids) > 3 {
				return "", nil, errParameters
			}
			for _, id := range ids {
				if !validNumber(id, 1, 10000) {
					return "", nil, errParameters
				}
			}
		default:
			return "", nil, errParameters
		}
	}
	if q.Get("language") == "" {
		q.Set("language", "en")
	}
	if verses {
		if q.Get("page") == "" {
			q.Set("page", "1")
		}
		if q.Get("per_page") == "" {
			q.Set("per_page", "20")
		}
		if q.Get("words") == "" {
			q.Set("words", "false")
		}
		q.Set("fields", "text_uthmani")
		if q.Get("words") == "true" {
			q.Set("word_fields", "text_uthmani")
		}
	}
	return path, q, nil
}

func validNumber(s string, low, high int) bool {
	n, err := strconv.Atoi(s)
	return err == nil && n >= low && n <= high && strconv.Itoa(n) == s
}

func readJSON(w http.ResponseWriter, r *http.Request, into any) bool {
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "application/json" {
		writeError(w, http.StatusUnsupportedMediaType, "invalid_content_type", "Use application/json.")
		return false
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	err = decoder.Decode(into)
	if err == nil {
		var extra any
		if decoder.Decode(&extra) != io.EOF {
			err = errParameters
		}
	}
	if err != nil {
		var limit *http.MaxBytesError
		if errors.As(err, &limit) {
			writeError(w, http.StatusRequestEntityTooLarge, "request_too_large", "Request body is too large.")
		} else {
			writeError(w, http.StatusBadRequest, "invalid_json", "Expected one valid JSON object with known fields.")
		}
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}

func rateError(w http.ResponseWriter) {
	w.Header().Set("Retry-After", "6")
	writeError(w, http.StatusTooManyRequests, "rate_limited", "Too many requests. Please wait before retrying.")
}

func unavailable(w http.ResponseWriter) {
	w.Header().Set("Retry-After", "5")
	writeError(w, http.StatusServiceUnavailable, "temporarily_busy", "Service is temporarily busy. Please retry later.")
}
