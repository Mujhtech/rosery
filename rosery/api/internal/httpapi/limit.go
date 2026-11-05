package httpapi

import (
	"sync"
	"time"
)

type bucket struct {
	tokens float64
	last   time.Time
}

// limiter rejects new identities at capacity instead of evicting active buckets,
// which would let an attacker reset an existing identity's quota.
type limiter struct {
	mu      sync.Mutex
	entries map[string]bucket
	perSec  float64
	burst   float64
	maxKeys int
	swept   time.Time
	now     func() time.Time
}

func newLimiter(perSec float64, burst, maxKeys int) *limiter {
	return &limiter{entries: make(map[string]bucket), perSec: perSec, burst: float64(burst), maxKeys: maxKeys, now: time.Now}
}

func (l *limiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if now.Sub(l.swept) >= time.Minute {
		for k, b := range l.entries {
			if now.Sub(b.last) > 10*time.Minute {
				delete(l.entries, k)
			}
		}
		l.swept = now
	}
	b, found := l.entries[key]
	if !found {
		if len(l.entries) >= l.maxKeys {
			return false
		}
		b = bucket{tokens: l.burst, last: now}
	}
	b.tokens = min(l.burst, b.tokens+max(0, now.Sub(b.last).Seconds())*l.perSec)
	b.last = now
	allowed := b.tokens >= 1
	if allowed {
		b.tokens--
	}
	l.entries[key] = b
	return allowed
}
