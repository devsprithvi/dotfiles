package provider

import (
	"context"
	"fmt"
	"runtime"
	"sort"
	"sync"
)

// Registry holds the set of known providers and resolves which one to use
// for a package. It is safe for concurrent use.
type Registry struct {
	mu        sync.RWMutex
	providers map[string]Provider
	// order preserves a deterministic listing order.
	order []string
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{providers: make(map[string]Provider)}
}

// Register adds or replaces a provider. Later registrations override earlier
// ones with the same name, which lets custom CUE providers shadow built-ins.
func (r *Registry) Register(p Provider) {
	r.mu.Lock()
	defer r.mu.Unlock()
	name := p.Name()
	if _, exists := r.providers[name]; !exists {
		r.order = append(r.order, name)
	}
	r.providers[name] = p
}

// Get returns a provider by name.
func (r *Registry) Get(name string) (Provider, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	p, ok := r.providers[name]
	return p, ok
}

// Names returns all registered provider names in registration order.
func (r *Registry) Names() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]string, len(r.order))
	copy(out, r.order)
	return out
}

// All returns every provider, sorted by name for stable presentation.
func (r *Registry) All() []Provider {
	r.mu.RLock()
	defer r.mu.RUnlock()
	names := make([]string, 0, len(r.providers))
	for n := range r.providers {
		names = append(names, n)
	}
	sort.Strings(names)
	out := make([]Provider, 0, len(names))
	for _, n := range names {
		out = append(out, r.providers[n])
	}
	return out
}

// Resolve picks a provider for a package.
//
//   - If explicit is set, that provider must exist (else an error).
//   - Otherwise the preference list is tried in order and the first
//     available provider wins.
//   - If preference is empty, a platform default order is used.
func (r *Registry) Resolve(ctx context.Context, explicit string, preference []string) (Provider, error) {
	if explicit != "" {
		p, ok := r.Get(explicit)
		if !ok {
			return nil, fmt.Errorf("unknown provider %q", explicit)
		}
		return p, nil
	}

	order := preference
	if len(order) == 0 {
		order = DefaultOrder()
	}
	for _, name := range order {
		if p, ok := r.Get(name); ok && p.Available(ctx) {
			return p, nil
		}
	}
	return nil, fmt.Errorf("no available provider for %s/%s (tried: %v)", runtime.GOOS, runtime.GOARCH, order)
}

// DefaultOrder returns a sensible provider preference for the current OS.
func DefaultOrder() []string {
	switch runtime.GOOS {
	case "darwin":
		return []string{"brew"}
	case "windows":
		return []string{"winget", "scoop"}
	default: // linux and other unixes
		return []string{"dnf", "apt", "pacman", "apk", "zypper", "brew"}
	}
}
