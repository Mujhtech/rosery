package attest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/fxamacker/cbor/v2"
)

const testAppID = "ABCDE12345.com.example.rosery"

type fixture struct {
	root         *x509.Certificate
	intermediate *x509.Certificate
	issuerKey    *ecdsa.PrivateKey
	appKey       *ecdsa.PrivateKey
	keyID        string
	now          time.Time
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	now := time.Now().Truncate(time.Second)
	rootKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	rootTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Test App Attest root"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour),
		IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign,
	}
	root := issueCertificate(t, rootTemplate, rootTemplate, &rootKey.PublicKey, rootKey)
	issuerKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	intermediateTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "Test App Attest intermediate"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour),
		IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign,
	}
	intermediate := issueCertificate(t, intermediateTemplate, root, &issuerKey.PublicKey, rootKey)
	appKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	encodedKey, err := appKey.PublicKey.Bytes()
	if err != nil {
		t.Fatal(err)
	}
	keyID := sha256.Sum256(encodedKey)
	return fixture{
		root: root, intermediate: intermediate, issuerKey: issuerKey, appKey: appKey,
		keyID: base64.StdEncoding.EncodeToString(keyID[:]), now: now,
	}
}

func issueCertificate(t *testing.T, template, issuer *x509.Certificate, publicKey *ecdsa.PublicKey, issuerKey *ecdsa.PrivateKey) *x509.Certificate {
	t.Helper()
	der, err := x509.CreateCertificate(rand.Reader, template, issuer, publicKey, issuerKey)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	return cert
}

func testVerifier(t *testing.T, f fixture, environment string) *verifier {
	t.Helper()
	v, err := newVerifier(testAppID, environment)
	if err != nil {
		t.Fatal(err)
	}
	v.roots = x509.NewCertPool()
	v.roots.AddCert(f.root)
	v.now = func() time.Time { return f.now }
	return v
}

func marshalCBOR(t *testing.T, value any) []byte {
	t.Helper()
	encoded, err := cbor.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

func (f fixture) authData(t *testing.T, environment string, extensions map[string]any) []byte {
	t.Helper()
	rpID := sha256.Sum256([]byte(testAppID))
	raw := append([]byte(nil), rpID[:]...)
	flags := byte(0x40)
	if extensions != nil {
		flags |= 0x80
	}
	raw = append(raw, flags, 0, 0, 0, 0)
	aaguid := []byte("appattest\x00\x00\x00\x00\x00\x00\x00")
	if environment == "development" {
		aaguid = []byte("appattestdevelop")
	}
	raw = append(raw, aaguid...)
	keyID, err := base64.StdEncoding.DecodeString(f.keyID)
	if err != nil {
		t.Fatal(err)
	}
	raw = append(raw, 0, 32)
	raw = append(raw, keyID...)
	encodedKey, err := f.appKey.PublicKey.Bytes()
	if err != nil || len(encodedKey) != 65 {
		t.Fatalf("encode public key: %v", err)
	}
	raw = append(raw, marshalCBOR(t, map[int]any{
		1: 2, 3: -7, -1: 1,
		-2: encodedKey[1:33],
		-3: encodedKey[33:65],
	})...)
	if extensions != nil {
		raw = append(raw, marshalCBOR(t, extensions)...)
	}
	return raw
}

func (f fixture) attestation(t *testing.T, challenge []byte, authData []byte, badNonce bool) []byte {
	t.Helper()
	clientDataHash := sha256.Sum256(challenge)
	nonce := hashParts(authData, clientDataHash[:])
	if badNonce {
		nonce[0] ^= 0xff
	}
	extension, err := asn1.Marshal(struct {
		Nonce []byte `asn1:"explicit,tag:1"`
	}{nonce[:]})
	if err != nil {
		t.Fatal(err)
	}
	leaf := issueCertificate(t, &x509.Certificate{
		SerialNumber: big.NewInt(3), Subject: pkix.Name{CommonName: "App credential"},
		NotBefore: f.now.Add(-time.Minute), NotAfter: f.now.Add(time.Hour),
		BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature,
		ExtraExtensions: []pkix.Extension{{Id: nonceOID, Value: extension}},
	}, f.intermediate, &f.appKey.PublicKey, f.issuerKey)
	return marshalCBOR(t, map[string]any{
		"fmt": "apple-appattest", "authData": authData,
		"attStmt": map[string]any{
			"x5c": [][]byte{leaf.Raw, f.intermediate.Raw}, "receipt": []byte("opaque-test-receipt"),
		},
	})
}

func TestVerifierAttestation(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name        string
		environment string
		extensions  map[string]any
		mutate      func([]byte)
		badNonce    bool
		wrongRoot   bool
		wantValid   bool
	}{
		{name: "legacy production", environment: "production", wantValid: true},
		{name: "legacy development", environment: "development", wantValid: true},
		{name: "app store metadata", environment: "production", extensions: map[string]any{"apple_validation_category_01": []byte{4, 0, 0, 0}, "apple_bundle_version_01": "5"}, wantValid: true},
		{name: "testflight metadata", environment: "production", extensions: map[string]any{"apple_validation_category_01": uint32(2), "apple_bundle_version_01": "5"}, wantValid: true},
		{name: "wrong app identity", environment: "production", mutate: func(raw []byte) { raw[0] ^= 0xff }},
		{name: "wrong environment", environment: "production", mutate: func(raw []byte) { copy(raw[37:53], "appattestdevelop") }},
		{name: "nonzero counter", environment: "production", mutate: func(raw []byte) { raw[36] = 1 }},
		{name: "wrong credential id", environment: "production", mutate: func(raw []byte) { raw[55] ^= 0xff }},
		{name: "mismatched certificate nonce", environment: "production", badNonce: true},
		{name: "untrusted chain", environment: "production", wrongRoot: true},
		{name: "development distribution on production", environment: "production", extensions: map[string]any{"apple_validation_category_01": uint32(3), "apple_bundle_version_01": "5"}},
		{name: "malformed version", environment: "production", extensions: map[string]any{"apple_validation_category_01": uint32(4), "apple_bundle_version_01": ""}},
		{name: "missing category", environment: "production", extensions: map[string]any{"apple_bundle_version_01": "5"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			f := newFixture(t)
			v := testVerifier(t, f, tt.environment)
			if tt.wrongRoot {
				v.roots = x509.NewCertPool()
			}
			authData := f.authData(t, tt.environment, tt.extensions)
			if tt.mutate != nil {
				tt.mutate(authData)
			}
			challenge := []byte(strings.Repeat("a", 32))
			keyID, _ := base64.StdEncoding.DecodeString(f.keyID)
			_, err := v.attestation(f.attestation(t, challenge, authData, tt.badNonce), keyID, challenge)
			if tt.wantValid && err != nil {
				t.Fatalf("valid attestation: %v", err)
			}
			if !tt.wantValid && !errors.Is(err, ErrInvalid) {
				t.Fatalf("got %v, want invalid", err)
			}
		})
	}
}

func signedRequest(t *testing.T, f fixture, challenge string, counter uint32, method, target string, body []byte) *http.Request {
	t.Helper()
	request := httptest.NewRequest(method, target, nil)
	request.Header.Set("X-App-Attest-Key-ID", f.keyID)
	request.Header.Set("X-App-Attest-Challenge", challenge)
	bodyHash := sha256.Sum256(body)
	clientData := []byte("rosery-v1\n" + challenge + "\n" + strings.ToUpper(method) + "\n" + request.URL.RequestURI() + "\n" + hex.EncodeToString(bodyHash[:]))
	rpID := sha256.Sum256([]byte(testAppID))
	authData := make([]byte, 37)
	copy(authData, rpID[:])
	// Older Apple OS releases set the AT flag in assertions without an AT
	// payload. It must not prevent signature verification of legitimate data.
	authData[32] = 0x40
	binary.BigEndian.PutUint32(authData[33:], counter)
	clientDataHash := sha256.Sum256(clientData)
	nonce := hashParts(authData, clientDataHash[:])
	digest := sha256.Sum256(nonce[:])
	signature, err := ecdsa.SignASN1(rand.Reader, f.appKey, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	assertion := marshalCBOR(t, map[string]any{"authenticatorData": authData, "signature": signature})
	request.Header.Set("X-App-Attest-Assertion", base64.StdEncoding.EncodeToString(assertion))
	return request
}

func TestVerifierAssertion(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	v := testVerifier(t, f, "production")
	publicKey, err := x509.MarshalPKIXPublicKey(&f.appKey.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	challenge := base64.StdEncoding.EncodeToString(make([]byte, 32))
	r := signedRequest(t, f, challenge, 1, http.MethodGet, "/v1/quran/chapters?language=en", nil)
	raw, err := base64.StdEncoding.DecodeString(r.Header.Get("X-App-Attest-Assertion"))
	if err != nil {
		t.Fatal(err)
	}
	bodyHash := sha256.Sum256(nil)
	clientData := []byte("rosery-v1\n" + challenge + "\nGET\n/v1/quran/chapters?language=en\n" + hex.EncodeToString(bodyHash[:]))
	if counter, err := v.assertion(raw, clientData, device{PublicKey: publicKey}); err != nil || counter != 1 {
		t.Fatalf("assertion got counter %d, error %v", counter, err)
	}
	if _, err := v.assertion(raw, clientData, device{PublicKey: publicKey, Counter: 1}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("replayed counter got %v", err)
	}
	if _, err := v.assertion(raw, append(clientData, 'x'), device{PublicKey: publicKey}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("tampered request got %v", err)
	}
}

// These are independently published iOS-generated artifacts, not signatures
// made by this test implementation. In particular, they distinguish Apple's
// SHA256withECDSA nonce signing from signing the nonce as a prehashed digest.
func TestVerifierPublishedAppleArtifacts(t *testing.T) {
	t.Parallel()
	raw, err := os.ReadFile("testdata/ios-14.4.json")
	if err != nil {
		t.Fatal(err)
	}
	var samples struct {
		Attestation map[string]string `json:"attestation"`
		Assertion   map[string]string `json:"assertion"`
	}
	if err := json.Unmarshal(raw, &samples); err != nil {
		t.Fatal(err)
	}
	attestation := samples.Attestation
	appID := attestation["teamIdentifier"] + "." + attestation["bundleIdentifier"]
	v, err := newVerifier(appID, attestation["environment"])
	if err != nil {
		t.Fatal(err)
	}
	instant, err := time.Parse(time.RFC3339Nano, attestation["timestamp"])
	if err != nil {
		t.Fatal(err)
	}
	v.now = func() time.Time { return instant }
	decode := func(value string) []byte {
		t.Helper()
		decoded, err := base64.StdEncoding.DecodeString(value)
		if err != nil {
			t.Fatal(err)
		}
		return decoded
	}
	verified, err := v.attestation(
		decode(attestation["attestationBase64"]),
		decode(attestation["keyIdBase64"]),
		decode(attestation["clientDataBase64"]),
	)
	if err != nil {
		t.Fatalf("genuine Apple attestation rejected: %v", err)
	}
	block, _ := pem.Decode([]byte(attestation["publicKey"]))
	if block == nil || !equal(verified.PublicKey, block.Bytes) {
		t.Fatal("verified key differs from published genuine device key")
	}
	assertion := samples.Assertion
	counter, err := v.assertion(decode(assertion["assertionBase64"]), decode(assertion["clientDataBase64"]), verified)
	if err != nil || counter != 1 {
		t.Fatalf("genuine Apple assertion rejected: counter %d, error %v", counter, err)
	}
}

func FuzzVerifierRejectsMalformedObjects(f *testing.F) {
	f.Add([]byte{0xa0})
	f.Add([]byte{0xa1, 0x63, 'f', 'm', 't', 0x60})
	f.Add([]byte{0xff})
	v, err := newVerifier(testAppID, "production")
	if err != nil {
		f.Fatal(err)
	}
	f.Fuzz(func(t *testing.T, raw []byte) {
		if len(raw) > maxAttestation {
			t.Skip()
		}
		_, _ = v.attestation(raw, make([]byte, 32), make([]byte, 32))
		_, _ = v.assertion(raw, nil, device{})
	})
}
