// Package provider defines the core "package provider" abstraction of pulipil.
//
// A Provider is a backend that knows how to install, remove and inspect
// packages on a system. Built-in providers wrap common package managers
// (dnf, apt, pacman, apk, zypper, brew, scoop, winget), but the same
// interface is used for user-defined custom providers declared in CUE, so
// anyone can teach pulipil about a new package source without recompiling.
package provider

import "context"

// Package is the normalized description of a single package that a provider
// is asked to act upon. It is derived from the CUE configuration.
type Package struct {
	// Name is the package identifier as understood by the provider.
	Name string
	// Version pins an exact version. Empty means "latest / provider default".
	Version string
	// Args are extra, provider-specific arguments appended verbatim.
	Args []string
}

// Candidate is a single completion result returned by a provider's search,
// consumed primarily by the language server for real-time autocompletion.
type Candidate struct {
	Name        string
	Version     string
	Description string
}

// Provider is the behaviour every package backend implements.
//
// Implementations must be safe to construct cheaply; expensive work belongs
// in the methods, which all receive a context for cancellation.
type Provider interface {
	// Name is the stable identifier used in configuration (e.g. "dnf").
	Name() string

	// Available reports whether this provider can be used on the current
	// system (its underlying tool is installed and detectable).
	Available(ctx context.Context) bool

	// RequiresRoot reports whether install/remove need elevated privileges.
	RequiresRoot() bool

	// Install ensures the package is present.
	Install(ctx context.Context, pkg Package) error

	// Remove ensures the package is absent.
	Remove(ctx context.Context, pkg Package) error

	// IsInstalled reports whether the package is currently installed. The
	// second return is false when the provider cannot determine state (in
	// which case callers should rely on the package manager's idempotency).
	IsInstalled(ctx context.Context, pkg Package) (installed bool, known bool)

	// Sync refreshes the provider's package metadata/indexes.
	Sync(ctx context.Context) error

	// Search returns completion candidates for a query. Providers that do
	// not support search may return an empty slice and a nil error.
	Search(ctx context.Context, query string) ([]Candidate, error)
}
