// Package config loads and validates the API's server-only configuration.
package config

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Environment    string
	Address        string
	QFEnvironment  string
	QFClientID     string
	QFClientSecret string
	AppleAppID     string
	AttestEnv      string
	StorePath      string
	OriginToken    string
	TrustedProxies []netip.Prefix
	MaxConcurrent  int
}

func Load() (Config, error) { return load(os.Getenv) }

func load(getenv func(string) string) (Config, error) {
	value := func(key, fallback string) string {
		if s := getenv(key); s != "" {
			return s
		}
		return fallback
	}
	c := Config{
		Environment:   value("ROSERY_ENV", "development"),
		Address:       value("ROSERY_ADDR", "127.0.0.1:8080"),
		QFEnvironment: value("QF_ENV", "prelive"),
		QFClientID:    getenv("QF_CLIENT_ID"), QFClientSecret: getenv("QF_CLIENT_SECRET"),
		AppleAppID:    value("APPLE_APP_ID", "6JR3ZGLPD6.mujhtech.rosery"),
		StorePath:     value("ROSERY_STORE_PATH", "data/attest.db"),
		OriginToken:   getenv("ROSERY_ORIGIN_TOKEN"),
		MaxConcurrent: 64,
	}
	if c.Environment != "development" && c.Environment != "production" {
		return Config{}, errors.New("ROSERY_ENV must be development or production")
	}
	c.AttestEnv = value("APP_ATTEST_ENVIRONMENT", c.Environment)
	if c.AttestEnv != "development" && c.AttestEnv != "production" {
		return Config{}, errors.New("APP_ATTEST_ENVIRONMENT must be development or production")
	}
	if c.Environment == "production" && c.AttestEnv != "production" {
		return Config{}, errors.New("production requires production App Attest")
	}
	if c.QFEnvironment != "prelive" && c.QFEnvironment != "production" {
		return Config{}, errors.New("QF_ENV must be prelive or production")
	}
	if c.Environment == "production" && c.QFEnvironment != "production" {
		return Config{}, errors.New("production requires QF_ENV=production with approved production credentials")
	}
	if c.QFClientID == "" || c.QFClientSecret == "" {
		return Config{}, errors.New("QF_CLIENT_ID and QF_CLIENT_SECRET are required (server only)")
	}
	if len(c.AppleAppID) > 255 || !strings.Contains(c.AppleAppID, ".") {
		return Config{}, errors.New("APPLE_APP_ID must be the App ID prefix and bundle identifier")
	}
	if s := getenv("ROSERY_MAX_CONCURRENT"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 || n > 256 {
			return Config{}, errors.New("ROSERY_MAX_CONCURRENT must be between 1 and 256")
		}
		c.MaxConcurrent = n
	}
	for _, s := range strings.Split(getenv("ROSERY_TRUSTED_PROXIES"), ",") {
		if strings.TrimSpace(s) == "" {
			continue
		}
		p, err := netip.ParsePrefix(strings.TrimSpace(s))
		if err != nil || p.Bits() == 0 {
			return Config{}, fmt.Errorf("ROSERY_TRUSTED_PROXIES requires explicit CIDRs, without /0")
		}
		c.TrustedProxies = append(c.TrustedProxies, p.Masked())
	}
	host, _, err := net.SplitHostPort(c.Address)
	if err != nil {
		return Config{}, errors.New("ROSERY_ADDR must be host:port")
	}
	if c.Environment == "development" {
		addr, err := netip.ParseAddr(host)
		if err != nil || !addr.IsLoopback() {
			return Config{}, errors.New("development must listen on a loopback IP")
		}
	}
	if (c.Environment == "production" || c.OriginToken != "") && (len(c.TrustedProxies) == 0 || len(c.OriginToken) < 32) {
		return Config{}, errors.New("production requires trusted proxy CIDRs and a server-only origin token of at least 32 characters")
	}
	return c, nil
}
