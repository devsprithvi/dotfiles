// Package version holds build-time version metadata.
package version

// These values are overridden at build time via -ldflags, e.g.:
//
//	go build -ldflags "-X github.com/devsprithvi/pulipil/internal/version.Version=v0.1.0"
var (
	// Version is the semantic version of the build.
	Version = "0.1.0-dev"
	// Commit is the git commit the binary was built from.
	Commit = "none"
	// Date is the build date.
	Date = "unknown"
)

// String returns a human-friendly version string.
func String() string {
	return Version + " (" + Commit + ", " + Date + ")"
}
