// Package attest verifies anonymous Rosery app installations using Apple App
// Attest. It authenticates an app-held key, not a person or a user account.
//
// One API process owns one local bbolt store. Multiple replicas require a shared
// transactional implementation with atomic counter compare-and-update; do not
// copy the database between live replicas. Fraud receipts are stored opaquely
// for later Apple risk assessment and are not used for authorization here.
package attest

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	bolt "go.etcd.io/bbolt"
)

var (
	// ErrInvalid means the attestation, assertion or challenge is unacceptable.
	ErrInvalid = errors.New("invalid app proof")
	// ErrUnavailable means local state could not be read or durably committed.
	ErrUnavailable = errors.New("app verification unavailable")
)

const (
	challengeTTL   = 2 * time.Minute
	maxChallenges  = 10000
	maxPerKey      = 4
	maxDevices     = 100000
	maxAttestation = 65536
	maxAssertion   = 8192
)

var (
	devicesBucket  = []byte("devices-v1")
	metaBucket     = []byte("meta-v1")
	identityKey    = []byte("identity")
	deviceCountKey = []byte("device-count")
)

// Config binds all verified keys to exactly one app identity and environment.
type Config struct {
	AppID       string
	Environment string
	StorePath   string
}

// Challenge is a base64 encoded random challenge with a short expiration.
type Challenge struct {
	Challenge string    `json:"challenge"`
	ExpiresAt time.Time `json:"expires_at"`
}

type pendingChallenge struct {
	keyID     string
	purpose   string
	expiresAt time.Time
}

type device struct {
	PublicKey          []byte    `json:"public_key"`
	Receipt            []byte    `json:"receipt"`
	Counter            uint32    `json:"counter"`
	RegistrationDigest []byte    `json:"registration_digest"`
	CreatedAt          time.Time `json:"created_at"`
	ValidationCategory uint32    `json:"validation_category,omitempty"`
	BundleVersion      string    `json:"bundle_version,omitempty"`
}

// Service durably records keys and assertion counters. Challenges are bounded,
// kept only in RAM, and intentionally invalidated by a server restart.
type Service struct {
	mu         sync.Mutex
	db         *bolt.DB
	verifier   *verifier
	challenges map[string]pendingChallenge
	closed     bool
	now        func() time.Time
}

// New opens a private, durable store and fails if the store belongs to another
// App ID/environment, or another process already has the file open.
func New(config Config) (*Service, error) {
	if len(config.AppID) < 13 || len(config.AppID) > 255 || !strings.Contains(config.AppID, ".") || strings.ContainsAny(config.AppID, " \n\r\t") || config.StorePath == "" {
		return nil, errors.New("app attest requires an App ID and store path")
	}
	if config.Environment != "production" && config.Environment != "development" {
		return nil, errors.New("app attest environment must be production or development")
	}
	verifier, err := newVerifier(config.AppID, config.Environment)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(config.StorePath), 0700); err != nil {
		return nil, fmt.Errorf("create App Attest state directory: %w", err)
	}
	if info, err := os.Lstat(config.StorePath); err == nil {
		if !info.Mode().IsRegular() || info.Mode()&0077 != 0 {
			return nil, errors.New("app attest store must be a private regular file (mode 0600)")
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("inspect App Attest state: %w", err)
	}
	db, err := bolt.Open(config.StorePath, 0600, &bolt.Options{Timeout: time.Second})
	if err != nil {
		return nil, fmt.Errorf("open App Attest state: %w", err)
	}
	identity := []byte(config.Environment + "\n" + config.AppID)
	if err := db.Update(func(tx *bolt.Tx) error {
		meta, err := tx.CreateBucketIfNotExists(metaBucket)
		if err != nil {
			return err
		}
		if saved := meta.Get(identityKey); saved != nil && !equal(saved, identity) {
			return errors.New("app attest store belongs to a different app or environment")
		}
		if err := meta.Put(identityKey, identity); err != nil {
			return err
		}
		bucket, err := tx.CreateBucketIfNotExists(devicesBucket)
		if err != nil {
			return err
		}
		if meta.Get(deviceCountKey) == nil {
			var count [8]byte
			binary.BigEndian.PutUint64(count[:], uint64(bucket.Stats().KeyN))
			return meta.Put(deviceCountKey, count[:])
		}
		return nil
	}); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("initialize App Attest state: %w", err)
	}
	return &Service{
		db: db, verifier: verifier, challenges: make(map[string]pendingChallenge), now: time.Now,
	}, nil
}

// Close waits for current state operations and closes the database.
func (s *Service) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true
	return s.db.Close()
}

// Challenge creates a nonce bound to an app key and purpose (attest or assert).
// The caller must also enforce external IP/global rate and concurrency limits.
func (s *Service) Challenge(keyID, purpose string) (Challenge, error) {
	if _, err := decodeKeyID(keyID); err != nil || (purpose != "attest" && purpose != "assert") {
		return Challenge{}, ErrInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return Challenge{}, ErrUnavailable
	}
	if purpose == "assert" {
		if _, err := s.loadDevice(keyID); err != nil {
			return Challenge{}, err
		}
	}
	now := s.now()
	pendingForKey := 0
	for nonce, pending := range s.challenges {
		if !now.Before(pending.expiresAt) {
			delete(s.challenges, nonce)
		} else if pending.keyID == keyID {
			pendingForKey++
		}
	}
	if len(s.challenges) >= maxChallenges || pendingForKey >= maxPerKey {
		return Challenge{}, ErrUnavailable
	}
	var nonce [32]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		return Challenge{}, ErrUnavailable
	}
	encoded := base64.StdEncoding.EncodeToString(nonce[:])
	expiresAt := now.Add(challengeTTL).UTC()
	s.challenges[encoded] = pendingChallenge{keyID: keyID, purpose: purpose, expiresAt: expiresAt}
	return Challenge{Challenge: encoded, ExpiresAt: expiresAt}, nil
}

// Attest registers a cryptographically verified Apple key. Exact retries of the
// same accepted registration are idempotent, including after a server restart.
func (s *Service) Attest(keyID, challenge, attestation string) error {
	keyBytes, err := decodeKeyID(keyID)
	if err != nil {
		return err
	}
	challengeBytes, err := decodeSized(challenge, 32, 32)
	if err != nil {
		return err
	}
	raw, err := decodeSized(attestation, 1, maxAttestation)
	if err != nil {
		return err
	}
	digest := hashParts([]byte(challenge), raw)
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return ErrUnavailable
	}
	if saved, err := s.loadDevice(keyID); err == nil {
		if equal(saved.RegistrationDigest, digest[:]) {
			return nil
		}
		return ErrInvalid
	} else if !errors.Is(err, ErrInvalid) {
		return err
	}
	if !s.validChallenge(keyID, challenge, "attest") {
		return ErrInvalid
	}
	verified, err := s.verifier.attestation(raw, keyBytes, challengeBytes)
	if err != nil {
		return err
	}
	verified.RegistrationDigest = digest[:]
	encoded, err := json.Marshal(verified)
	if err != nil {
		return ErrUnavailable
	}
	if err := s.db.Update(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(devicesBucket)
		meta := tx.Bucket(metaBucket)
		savedCount := meta.Get(deviceCountKey)
		if len(savedCount) != 8 {
			return ErrUnavailable
		}
		count := binary.BigEndian.Uint64(savedCount)
		if count >= maxDevices {
			return ErrUnavailable
		}
		if err := bucket.Put([]byte(keyID), encoded); err != nil {
			return err
		}
		var nextCount [8]byte
		binary.BigEndian.PutUint64(nextCount[:], count+1)
		return meta.Put(deviceCountKey, nextCount[:])
	}); err != nil {
		return ErrUnavailable
	}
	delete(s.challenges, challenge)
	return nil
}

// Verify validates a request-bound assertion and atomically records its counter
// before allowing the handler to run. The nonce is consumed only on success.
func (s *Service) Verify(request *http.Request, body []byte) error {
	if request == nil || request.URL == nil {
		return ErrInvalid
	}
	keyID, ok := singleHeader(request, "X-App-Attest-Key-ID")
	if !ok {
		return ErrInvalid
	}
	if _, err := decodeKeyID(keyID); err != nil {
		return err
	}
	challenge, ok := singleHeader(request, "X-App-Attest-Challenge")
	if !ok {
		return ErrInvalid
	}
	if _, err := decodeSized(challenge, 32, 32); err != nil {
		return err
	}
	assertion, ok := singleHeader(request, "X-App-Attest-Assertion")
	if !ok {
		return ErrInvalid
	}
	raw, err := decodeSized(assertion, 1, maxAssertion)
	if err != nil {
		return err
	}
	clientData := canonicalRequestData(request, body, challenge)
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return ErrUnavailable
	}
	if !s.validChallenge(keyID, challenge, "assert") {
		return ErrInvalid
	}
	saved, err := s.loadDevice(keyID)
	if err != nil {
		return err
	}
	counter, err := s.verifier.assertion(raw, clientData, saved)
	if err != nil {
		return err
	}
	saved.Counter = counter
	encoded, err := json.Marshal(saved)
	if err != nil {
		return ErrUnavailable
	}
	if err := s.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(devicesBucket).Put([]byte(keyID), encoded)
	}); err != nil {
		return ErrUnavailable
	}
	delete(s.challenges, challenge)
	return nil
}

func canonicalRequestData(request *http.Request, body []byte, challenge string) []byte {
	bodyHash := sha256.Sum256(body)
	return []byte("rosery-v1\n" + challenge + "\n" + strings.ToUpper(request.Method) + "\n" + request.URL.RequestURI() + "\n" + hex.EncodeToString(bodyHash[:]))
}

func (s *Service) validChallenge(keyID, challenge, purpose string) bool {
	pending, ok := s.challenges[challenge]
	if !ok {
		return false
	}
	if !s.now().Before(pending.expiresAt) {
		delete(s.challenges, challenge)
		return false
	}
	return pending.keyID == keyID && pending.purpose == purpose
}

func (s *Service) loadDevice(keyID string) (device, error) {
	var saved device
	err := s.db.View(func(tx *bolt.Tx) error {
		raw := tx.Bucket(devicesBucket).Get([]byte(keyID))
		if raw == nil {
			return ErrInvalid
		}
		if err := json.Unmarshal(raw, &saved); err != nil {
			return ErrUnavailable
		}
		return nil
	})
	if errors.Is(err, ErrInvalid) {
		return device{}, ErrInvalid
	}
	if err != nil {
		return device{}, ErrUnavailable
	}
	return saved, nil
}

func decodeKeyID(encoded string) ([]byte, error) {
	return decodeSized(encoded, 32, 32)
}

func decodeSized(encoded string, minBytes, maxBytes int) ([]byte, error) {
	if len(encoded) == 0 || len(encoded) > base64.StdEncoding.EncodedLen(maxBytes) || strings.ContainsAny(encoded, "\n\r") {
		return nil, ErrInvalid
	}
	decoded, err := base64.StdEncoding.Strict().DecodeString(encoded)
	if err != nil || len(decoded) < minBytes || len(decoded) > maxBytes {
		return nil, ErrInvalid
	}
	// Reject alternative textual encodings so nonce/key identity is canonical.
	if base64.StdEncoding.EncodeToString(decoded) != encoded {
		return nil, ErrInvalid
	}
	return decoded, nil
}

func singleHeader(request *http.Request, key string) (string, bool) {
	values := request.Header.Values(key)
	return request.Header.Get(key), len(values) == 1 && values[0] != ""
}
