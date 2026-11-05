package config

import (
	"strings"
	"testing"
)

func TestConfigSecurityBoundaries(t *testing.T) {
	tests := []struct {
		name  string
		env   map[string]string
		valid bool
	}{
		{"local development", nil, true},
		{"public development", map[string]string{"ROSERY_ADDR": "0.0.0.0:8080"}, false},
		{"unknown environment", map[string]string{"ROSERY_ENV": "staging"}, false},
		{"arbitrary upstream", map[string]string{"QF_ENV": "https://example.com"}, false},
		{"production missing origin controls", map[string]string{"ROSERY_ENV": "production", "QF_ENV": "production"}, false},
		{"production sandbox attestation", map[string]string{"ROSERY_ENV": "production", "QF_ENV": "production", "APP_ATTEST_ENVIRONMENT": "development"}, false},
		{"production prelive provider", map[string]string{"ROSERY_ENV": "production"}, false},
		{"universal proxy trust", map[string]string{"ROSERY_TRUSTED_PROXIES": "0.0.0.0/0"}, false},
		{"invalid concurrency", map[string]string{"ROSERY_MAX_CONCURRENT": "99999"}, false},
		{"valid production", map[string]string{"ROSERY_ENV": "production", "QF_ENV": "production", "ROSERY_ADDR": ":8080", "ROSERY_TRUSTED_PROXIES": "127.0.0.1/32,::1/128", "ROSERY_ORIGIN_TOKEN": strings.Repeat("x", 32)}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			get := func(k string) string {
				if v, ok := tt.env[k]; ok {
					return v
				}
				if k == "QF_CLIENT_ID" {
					return "client"
				}
				if k == "QF_CLIENT_SECRET" {
					return "secret-do-not-leak"
				}
				return ""
			}
			_, err := load(get)
			if (err == nil) != tt.valid {
				t.Fatalf("valid=%v, error=%v", tt.valid, err)
			}
			if err != nil && strings.Contains(err.Error(), "secret-do-not-leak") {
				t.Fatal("secret leaked in config error")
			}
		})
	}
}

func TestCredentialsRequired(t *testing.T) {
	if _, err := load(func(string) string { return "" }); err == nil {
		t.Fatal("missing provider credentials accepted")
	}
}
