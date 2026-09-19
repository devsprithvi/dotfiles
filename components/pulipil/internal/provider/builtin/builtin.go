// Package builtin registers pulipil's built-in package providers.
//
// Each provider is expressed as a provider.Spec: a small, declarative table
// of templated commands. This is intentionally the same mechanism used for
// user-defined custom providers, so the built-ins double as worked examples.
package builtin

import "github.com/devsprithvi/pulipil/internal/provider"

// Specs returns the built-in provider specifications.
func Specs() []provider.Spec {
	return []provider.Spec{
		{
			Name:         "dnf",
			Binary:       "dnf",
			RequiresRoot: true,
			Install:      []string{"dnf", "install", "-y", "{{.Name}}{{if .Version}}-{{.Version}}{{end}}"},
			Remove:       []string{"dnf", "remove", "-y", "{{.Name}}"},
			Check:        []string{"rpm", "-q", "{{.Name}}"},
			Update:       []string{"dnf", "makecache"},
			Search:       []string{"dnf", "--quiet", "search", "{{.Query}}"},
		},
		{
			Name:         "apt",
			Binary:       "apt-get",
			RequiresRoot: true,
			Install:      []string{"apt-get", "install", "-y", "{{.Name}}{{if .Version}}={{.Version}}{{end}}"},
			Remove:       []string{"apt-get", "remove", "-y", "{{.Name}}"},
			Check:        []string{"dpkg", "-s", "{{.Name}}"},
			Update:       []string{"apt-get", "update"},
			Search:       []string{"apt-cache", "search", "{{.Query}}"},
		},
		{
			Name:         "pacman",
			Binary:       "pacman",
			RequiresRoot: true,
			Install:      []string{"pacman", "-S", "--noconfirm", "--needed", "{{.Name}}"},
			Remove:       []string{"pacman", "-R", "--noconfirm", "{{.Name}}"},
			Check:        []string{"pacman", "-Q", "{{.Name}}"},
			Update:       []string{"pacman", "-Sy"},
			Search:       []string{"pacman", "-Ss", "{{.Query}}"},
		},
		{
			Name:         "apk",
			Binary:       "apk",
			RequiresRoot: true,
			Install:      []string{"apk", "add", "{{.Name}}{{if .Version}}={{.Version}}{{end}}"},
			Remove:       []string{"apk", "del", "{{.Name}}"},
			Check:        []string{"apk", "info", "-e", "{{.Name}}"},
			Update:       []string{"apk", "update"},
			Search:       []string{"apk", "search", "{{.Query}}"},
		},
		{
			Name:         "zypper",
			Binary:       "zypper",
			RequiresRoot: true,
			Install:      []string{"zypper", "--non-interactive", "install", "{{.Name}}"},
			Remove:       []string{"zypper", "--non-interactive", "remove", "{{.Name}}"},
			Check:        []string{"rpm", "-q", "{{.Name}}"},
			Update:       []string{"zypper", "refresh"},
			Search:       []string{"zypper", "--quiet", "search", "{{.Query}}"},
		},
		{
			Name:         "brew",
			Binary:       "brew",
			RequiresRoot: false,
			Install:      []string{"brew", "install", "{{.Name}}{{if .Version}}@{{.Version}}{{end}}"},
			Remove:       []string{"brew", "uninstall", "{{.Name}}"},
			Check:        []string{"brew", "list", "{{.Name}}"},
			Update:       []string{"brew", "update"},
			Search:       []string{"brew", "search", "{{.Query}}"},
		},
		{
			Name:         "scoop",
			Binary:       "scoop",
			RequiresRoot: false,
			Install:      []string{"scoop", "install", "{{.Name}}{{if .Version}}@{{.Version}}{{end}}"},
			Remove:       []string{"scoop", "uninstall", "{{.Name}}"},
			Check:        []string{"scoop", "list", "{{.Name}}"},
			Update:       []string{"scoop", "update"},
			Search:       []string{"scoop", "search", "{{.Query}}"},
		},
		{
			Name:         "winget",
			Binary:       "winget",
			RequiresRoot: false,
			Install:      []string{"winget", "install", "-e", "--accept-package-agreements", "--accept-source-agreements", "--id", "{{.Name}}"},
			Remove:       []string{"winget", "uninstall", "-e", "--id", "{{.Name}}"},
			Check:        []string{"winget", "list", "-e", "--id", "{{.Name}}"},
			Update:       []string{"winget", "source", "update"},
			Search:       []string{"winget", "search", "{{.Query}}"},
		},
	}
}

// Register adds all built-in providers to the registry using the given runner.
func Register(reg *provider.Registry, runner provider.Runner) {
	for _, spec := range Specs() {
		reg.Register(provider.New(spec, runner))
	}
}
