// Package remote provides real-time, internet-backed completion sources.
//
// Where the command-driven providers in internal/provider shell out to a
// locally installed package manager, a remote Source queries that ecosystem's
// public registry API directly over HTTP. This is what powers live, offline-
// of-the-package-manager autocompletion in the language server: a user editing
// a pulipil.cue does not need dnf/brew/npm installed for the editor to suggest
// real, currently-published package names and versions.
//
// Every registry speaks its own wire format, so every Source owns its own
// request shape (endpoint + query encoding) and its own response shape (the
// JSON decoder that maps that registry's payload onto provider.Candidate).
// The Source interface is the single seam the rest of pulipil depends on.
package remote

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/devsprithvi/pulipil/internal/provider"
)

// Source is a single internet-backed completion backend for one ecosystem.
//
// Implementations must be safe for concurrent use and must respect the
// provided context for cancellation and timeouts.
type Source interface {
	// Name is the stable identifier, matching the local provider name where
	// one exists (e.g. "brew"), so completion can be keyed off the provider a
	// package block already targets.
	Name() string

	// Search returns live completion candidates for a partial query. An empty
	// query should return an empty slice and a nil error rather than the whole
	// registry.
	Search(ctx context.Context, query string) ([]provider.Candidate, error)
}

// Registry holds the known remote sources. It is safe for concurrent use.
type Registry struct {
	mu      sync.RWMutex
	sources map[string]Source
	order   []string
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{sources: make(map[string]Source)}
}

// Register adds or replaces a source, preserving first-seen order.
func (r *Registry) Register(s Source) {
	r.mu.Lock()
	defer r.mu.Unlock()
	name := s.Name()
	if _, exists := r.sources[name]; !exists {
		r.order = append(r.order, name)
	}
	r.sources[name] = s
}

// Get returns a source by name.
func (r *Registry) Get(name string) (Source, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	s, ok := r.sources[name]
	return s, ok
}

// Names returns the registered source names in registration order.
func (r *Registry) Names() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]string, len(r.order))
	copy(out, r.order)
	return out
}

// Has reports whether a source is registered for name.
func (r *Registry) Has(name string) bool {
	_, ok := r.Get(name)
	return ok
}

// httpSource is a generic HTTP-backed Source. Each ecosystem is expressed as a
// small trio: how to build its request URL, and how to decode its response.
// This keeps the per-provider "shape" isolated to two closures while sharing
// all transport, timeout, header and error-handling concerns.
type httpSource struct {
	name    string
	baseURL string
	client  *http.Client
	// build maps (baseURL, query) onto a concrete request URL.
	build func(base, query string) (string, error)
	// shape decodes this registry's response body into candidates.
	shape func(body []byte) ([]provider.Candidate, error)
	// userAgent is sent on every request; several registries (crates.io)
	// reject requests without one.
	userAgent string
}

func (s *httpSource) Name() string { return s.name }

func (s *httpSource) Search(ctx context.Context, query string) ([]provider.Candidate, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}
	endpoint, err := s.build(s.baseURL, query)
	if err != nil {
		return nil, fmt.Errorf("%s: build request: %w", s.name, err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("%s: new request: %w", s.name, err)
	}
	req.Header.Set("Accept", "application/json")
	if s.userAgent != "" {
		req.Header.Set("User-Agent", s.userAgent)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%s: request: %w", s.name, err)
	}
	defer resp.Body.Close()

	// Cap the body to guard against a hostile or pathological registry.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, fmt.Errorf("%s: read body: %w", s.name, err)
	}

	switch {
	case resp.StatusCode == http.StatusNotFound:
		// A miss is a legitimate "no candidates", not an error: exact-lookup
		// registries return 404 for names that do not exist yet.
		return nil, nil
	case resp.StatusCode >= 400:
		return nil, fmt.Errorf("%s: registry returned HTTP %d", s.name, resp.StatusCode)
	}

	cands, err := s.shape(body)
	if err != nil {
		return nil, fmt.Errorf("%s: decode response: %w", s.name, err)
	}
	return cands, nil
}

// clientOr returns c, or a sensibly-configured default client with a timeout.
func clientOr(c *http.Client) *http.Client {
	if c != nil {
		return c
	}
	return &http.Client{Timeout: 5 * time.Second}
}

// encodeQuery is a tiny helper to build query strings safely.
func encodeQuery(values map[string]string) string {
	q := url.Values{}
	// Sort keys for deterministic URLs (helps caching and tests).
	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		q.Set(k, values[k])
	}
	return q.Encode()
}
