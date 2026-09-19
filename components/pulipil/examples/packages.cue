// Example pulipil configuration.
//
// This file satisfies the #Config schema (run `pulipil schema` to view it).
// Validate it with:   pulipil validate -c examples/packages.cue
// Preview actions:     pulipil plan     -c examples/packages.cue
// Apply it:            pulipil install  -c examples/packages.cue

// Auto-detection preference: the first available provider wins when a package
// does not pin one explicitly.
defaults: providers: ["dnf", "apt", "brew", "pacman"]

// A custom provider. Anyone can declare one; it is defined exactly like the
// built-ins. This example wraps `pipx` for Python applications.
providers: pipx: {
	binary:  "pipx"
	install: ["pipx", "install", "{{.Name}}{{if .Version}}=={{.Version}}{{end}}"]
	remove:  ["pipx", "uninstall", "{{.Name}}"]
	check:   ["pipx", "list", "--short"]
	search:  ["pipx", "search", "{{.Query}}"]
}

packages: [
	// Auto-detected provider, latest version.
	{name: "git"},
	{name: "curl"},

	// Pin a specific provider.
	{name: "ripgrep", provider: "dnf"},

	// Only install on Linux.
	{name: "zsh", when: os: ["linux"]},

	// Use the custom provider declared above.
	{name: "httpie", provider: "pipx"},

	// Ensure a package is absent.
	{name: "nano", state: "absent"},
]

// Commands are steps the engine runs after packages, in declared order. The
// engine is an interpreter: it runs only what you declare, skips steps whose
// dependencies are not met, and stops on the first failure.
commands: [
	// Runs only after the `git` package above is present.
	{
		name: "clone-dotfiles"
		run:  ["git", "clone", "https://example.com/repo.git", "/tmp/repo"]
		needs: ["git"]
	},

	// Depends on the previous step; skipped if the clone was skipped.
	// `shell: true` allows pipes/redirection. `trigger` is advisory metadata
	// the orchestrator (chezmoi) uses to decide when to invoke pulipil.
	{
		name:    "build"
		run:     ["make", "-C", "/tmp/repo"]
		needs:   ["clone-dotfiles"]
		trigger: "onchange"
	},
]
