package attest

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	_ "embed"
	"encoding/asn1"
	"encoding/binary"
	"errors"
	"fmt"
	"time"
	"unicode"

	"github.com/fxamacker/cbor/v2"
)

// Source: https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
// No system roots or certificates supplied by the client are trusted as roots.
//
//go:embed apple_root.pem
var appleRootPEM []byte

var nonceOID = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}

type verifier struct {
	roots       *x509.CertPool
	decoder     cbor.DecMode
	rpID        [32]byte
	environment string
	now         func() time.Time
}

type attestationObject struct {
	Format    string `cbor:"fmt"`
	Statement struct {
		Certificates [][]byte `cbor:"x5c"`
		Receipt      []byte   `cbor:"receipt"`
	} `cbor:"attStmt"`
	AuthData []byte `cbor:"authData"`
}

type assertionObject struct {
	Signature []byte `cbor:"signature"`
	AuthData  []byte `cbor:"authenticatorData"`
}

func newVerifier(appID, environment string) (*verifier, error) {
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(appleRootPEM) {
		return nil, errors.New("invalid embedded Apple App Attest root")
	}
	decoder, err := (cbor.DecOptions{
		DupMapKey:        cbor.DupMapKeyEnforcedAPF,
		MaxNestedLevels:  8,
		MaxArrayElements: 16,
		MaxMapPairs:      16,
		IndefLength:      cbor.IndefLengthForbidden,
		TagsMd:           cbor.TagsForbidden,
	}).DecMode()
	if err != nil {
		return nil, fmt.Errorf("create CBOR decoder: %w", err)
	}
	return &verifier{
		roots: roots, decoder: decoder, rpID: sha256.Sum256([]byte(appID)),
		environment: environment, now: time.Now,
	}, nil
}

func (v *verifier) attestation(raw, keyID, challenge []byte) (device, error) {
	var object attestationObject
	if err := v.decoder.Unmarshal(raw, &object); err != nil || object.Format != "apple-appattest" {
		return device{}, ErrInvalid
	}
	certificates := object.Statement.Certificates
	if len(certificates) < 2 || len(certificates) > 4 || len(object.Statement.Receipt) == 0 || len(object.Statement.Receipt) > 32768 {
		return device{}, ErrInvalid
	}
	leaf, err := x509.ParseCertificate(certificates[0])
	if err != nil || leaf.IsCA || leaf.KeyUsage&x509.KeyUsageDigitalSignature == 0 {
		return device{}, ErrInvalid
	}
	intermediates := x509.NewCertPool()
	for _, data := range certificates[1:] {
		cert, parseErr := x509.ParseCertificate(data)
		if parseErr != nil {
			return device{}, ErrInvalid
		}
		intermediates.AddCert(cert)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots: v.roots, Intermediates: intermediates, CurrentTime: v.now(),
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return device{}, ErrInvalid
	}
	publicKey, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok || publicKey.Curve != elliptic.P256() {
		return device{}, ErrInvalid
	}
	encodedKey, err := publicKey.Bytes()
	if err != nil || len(encodedKey) != 65 {
		return device{}, ErrInvalid
	}
	keyHash := sha256.Sum256(encodedKey)
	if !equal(keyHash[:], keyID) {
		return device{}, ErrInvalid
	}
	clientDataHash := sha256.Sum256(challenge)
	nonce := hashParts(object.AuthData, clientDataHash[:])
	if !validCertificateNonce(leaf, nonce[:]) {
		return device{}, ErrInvalid
	}
	metadata, err := v.attestationAuthData(object.AuthData, keyID, encodedKey)
	if err != nil {
		return device{}, err
	}
	publicKeyDER, err := x509.MarshalPKIXPublicKey(publicKey)
	if err != nil {
		return device{}, ErrInvalid
	}
	return device{
		PublicKey: publicKeyDER, Receipt: object.Statement.Receipt,
		CreatedAt: v.now().UTC(), BundleVersion: metadata.bundleVersion,
		ValidationCategory: metadata.validationCategory,
	}, nil
}

func validCertificateNonce(cert *x509.Certificate, expected []byte) bool {
	var found bool
	for _, extension := range cert.Extensions {
		if !extension.Id.Equal(nonceOID) {
			continue
		}
		if found {
			return false
		}
		found = true
		var parsed struct {
			Nonce []byte `asn1:"explicit,tag:1"`
		}
		rest, err := asn1.Unmarshal(extension.Value, &parsed)
		if err != nil || len(rest) != 0 || !equal(parsed.Nonce, expected) {
			return false
		}
	}
	return found
}

func (v *verifier) attestationAuthData(raw, keyID, encodedKey []byte) (authMetadata, error) {
	if len(encodedKey) != 65 || len(raw) < 87 || !equal(raw[:32], v.rpID[:]) || raw[32]&0x40 == 0 || binary.BigEndian.Uint32(raw[33:37]) != 0 {
		return authMetadata{}, ErrInvalid
	}
	expectedGUID := []byte("appattest\x00\x00\x00\x00\x00\x00\x00")
	if v.environment == "development" {
		expectedGUID = []byte("appattestdevelop")
	}
	if !equal(raw[37:53], expectedGUID) || binary.BigEndian.Uint16(raw[53:55]) != 32 || !equal(raw[55:87], keyID) {
		return authMetadata{}, ErrInvalid
	}
	var cose map[int]cbor.RawMessage
	rest, err := v.decoder.UnmarshalFirst(raw[87:], &cose)
	if err != nil || len(cose) != 5 {
		return authMetadata{}, ErrInvalid
	}
	for key, expected := range map[int]int{1: 2, 3: -7, -1: 1} {
		var value int
		if err := v.decoder.Unmarshal(cose[key], &value); err != nil || value != expected {
			return authMetadata{}, ErrInvalid
		}
	}
	var x, y []byte
	if err := v.decoder.Unmarshal(cose[-2], &x); err != nil || len(x) != 32 {
		return authMetadata{}, ErrInvalid
	}
	if err := v.decoder.Unmarshal(cose[-3], &y); err != nil || len(y) != 32 {
		return authMetadata{}, ErrInvalid
	}
	if !bytes.Equal(x, encodedKey[1:33]) || !bytes.Equal(y, encodedKey[33:65]) {
		return authMetadata{}, ErrInvalid
	}
	return v.extensions(raw[32], rest)
}

type authMetadata struct {
	validationCategory uint32
	bundleVersion      string
}

// Newer OS versions include signed distribution category and build metadata.
// Legacy iOS 17 authenticator data has no extensions and remains supported.
func (v *verifier) extensions(flags byte, raw []byte) (authMetadata, error) {
	if len(raw) == 0 {
		if flags&0x80 != 0 {
			return authMetadata{}, ErrInvalid
		}
		return authMetadata{}, nil
	}
	if flags&0x80 == 0 {
		return authMetadata{}, ErrInvalid
	}
	var extensions map[string]cbor.RawMessage
	if err := v.decoder.Unmarshal(raw, &extensions); err != nil || len(extensions) == 0 {
		return authMetadata{}, ErrInvalid
	}
	category, hasCategory := extensions["apple_validation_category_01"]
	version, hasVersion := extensions["apple_bundle_version_01"]
	// Apple's assertion prose also calls these fields validationCategory and
	// bundleVersion. Accept either spelling, but never an ambiguous duplicate.
	if alternate, ok := extensions["validationCategory"]; ok {
		if hasCategory {
			return authMetadata{}, ErrInvalid
		}
		category, hasCategory = alternate, true
	}
	if alternate, ok := extensions["bundleVersion"]; ok {
		if hasVersion {
			return authMetadata{}, ErrInvalid
		}
		version, hasVersion = alternate, true
	}
	if !hasCategory && !hasVersion {
		return authMetadata{}, nil
	}
	if !hasCategory || !hasVersion {
		return authMetadata{}, ErrInvalid
	}
	var metadata authMetadata
	if err := v.decoder.Unmarshal(category, &metadata.validationCategory); err != nil {
		var encoded []byte
		if err := v.decoder.Unmarshal(category, &encoded); err != nil || len(encoded) != 4 {
			return authMetadata{}, ErrInvalid
		}
		metadata.validationCategory = binary.LittleEndian.Uint32(encoded)
	}
	if v.environment == "production" {
		if metadata.validationCategory != 2 && metadata.validationCategory != 4 {
			return authMetadata{}, ErrInvalid
		}
	} else if metadata.validationCategory != 3 && metadata.validationCategory != 5 {
		return authMetadata{}, ErrInvalid
	}
	if err := v.decoder.Unmarshal(version, &metadata.bundleVersion); err != nil || len(metadata.bundleVersion) == 0 || len(metadata.bundleVersion) > 64 {
		return authMetadata{}, ErrInvalid
	}
	for _, char := range metadata.bundleVersion {
		if unicode.IsControl(char) {
			return authMetadata{}, ErrInvalid
		}
	}
	return metadata, nil
}

func (v *verifier) assertion(raw, clientData []byte, saved device) (uint32, error) {
	var object assertionObject
	if err := v.decoder.Unmarshal(raw, &object); err != nil || len(object.AuthData) < 37 || len(object.AuthData) > 4096 || len(object.Signature) == 0 || len(object.Signature) > 80 {
		return 0, ErrInvalid
	}
	if !equal(object.AuthData[:32], v.rpID[:]) {
		return 0, ErrInvalid
	}
	counter := binary.BigEndian.Uint32(object.AuthData[33:37])
	if counter <= saved.Counter {
		return 0, ErrInvalid
	}
	// Assertion data contains no attested credential payload, even on older
	// Apple versions that incorrectly set the AT flag on assertions.
	if _, err := v.extensions(object.AuthData[32], object.AuthData[37:]); err != nil {
		return 0, err
	}
	key, err := x509.ParsePKIXPublicKey(saved.PublicKey)
	if err != nil {
		return 0, ErrUnavailable
	}
	publicKey, ok := key.(*ecdsa.PublicKey)
	if !ok || publicKey.Curve != elliptic.P256() {
		return 0, ErrUnavailable
	}
	clientDataHash := sha256.Sum256(clientData)
	nonce := hashParts(object.AuthData, clientDataHash[:])
	// App Attest signs nonce as a message using SHA256withECDSA. Go's
	// VerifyASN1 expects the already-hashed digest, hence the second hash.
	digest := sha256.Sum256(nonce[:])
	if !ecdsa.VerifyASN1(publicKey, digest[:], object.Signature) {
		return 0, ErrInvalid
	}
	return counter, nil
}

func hashParts(first, second []byte) [32]byte {
	h := sha256.New()
	_, _ = h.Write(first)
	_, _ = h.Write(second)
	var result [32]byte
	copy(result[:], h.Sum(nil))
	return result
}

func equal(first, second []byte) bool {
	return len(first) == len(second) && subtle.ConstantTimeCompare(first, second) == 1
}
