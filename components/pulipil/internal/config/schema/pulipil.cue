// pulipil configuration schema.
//
// This schema is embedded into the pulipil binary and unified with the user's
// configuration to validate it before anything runs. A user config is a plain
// CUE file that fills in `packages` and/or `commands`, and optionally
// `providers` and `defaults`, matching the #Config definition below.
//
// Print this schema any time with: `pulipil schema`.

// #Argv is a templated argv slice used by providers. Each element is a Go
// text/template evaluated per invocation. Available fields: .Name, .Version,
// .Query, .Args. An element that renders empty is dropped, so conditionals are
// easy:  "{{.Name}}{{if .Version}}-{{.Version}}{{end}}"
#Argv: [...string]

// #Provider declares a package provider. The built-in providers (dnf, apt,
// pacman, apk, zypper, brew, scoop, winget) use this exact shape, so a custom
// provider is defined the same way and can even override a built-in by name.
#Provider: {
	// binary is the executable used for availability detection when `detect`
	// is not given. Defaults to the first element of `install`.
	binary?: string

	// requiresRoot elevates install/remove/update with sudo when needed.
	requiresRoot?: bool | *false

	// detect, when set, is run to decide availability (exit 0 == available).
	detect?: #Argv

	// install is required; it ensures a package is present.
	install!: #Argv

	// remove, check, update and search are optional capabilities.
	remove?: #Argv
	check?:  #Argv
	update?: #Argv
	search?: #Argv

	// env holds extra environment variables for this provider's commands.
	env?: {[string]: string}
}

// #SecretRef is a placeholder for the upcoming secret-injection feature used
// when installing from private repositories. It is validated now but not yet
// resolved at install time.
#SecretRef: {
	// ref is an opaque handle resolved by a secret backend (e.g. "vault:/path").
	ref!: string
	// as names the environment variable the secret is injected into.
	as?: string
}

// #Package is a single managed package.
#Package: {
	// name as understood by the chosen provider.
	name!: string

	// provider pins a specific provider by name. Empty means auto-detect
	// using `defaults.providers` (or the platform default order).
	provider?: string

	// version pins an exact version; empty means the provider default.
	version?: string

	// args are extra, provider-specific arguments appended verbatim.
	args?: [...string]

	// state controls desired presence.
	state?: "present" | "absent" | *"present"

	// when guards installation by platform.
	when?: {
		os?:   [...("linux" | "darwin" | "windows" | string)]
		arch?: [...string]
	}

	// secret is an optional credential reference (future feature).
	secret?: #SecretRef
}

// #Command is a command the engine runs as a setup/build step, in addition to
// installing packages.
//
// The engine is a small interpreter: it executes ONLY the steps you declare,
// in the order you declare them, honouring platform guards and dependencies.
// It never invents work. A step whose dependencies are not satisfied is
// skipped (not failed); a step that runs and exits non-zero is a failure and
// stops the run unless --keep-going is set.
#Command: {
	// name is a stable identifier for the step. It also serves as the
	// idempotency key an orchestrator (e.g. chezmoi run_once_/run_onchange_)
	// keys off when deciding whether to invoke pulipil at all.
	name!: string

	// run is the command to execute, as an argv list (at least one element).
	// By default it runs directly with no shell; set `shell: true` to run it
	// through the platform shell so pipes/redirection/globs work.
	run!: [string, ...string]

	// shell joins `run` and executes it via `sh -c` (or `cmd /C` on Windows).
	shell?: bool | *false

	// needs lists names that must be satisfied before this step runs. A name
	// may be a package declared in `packages` (satisfied when it is present /
	// guarded-in) or another command declared earlier (satisfied when that
	// command is not skipped). Unmet dependencies skip the step.
	needs?: [...string]

	// requiresRoot elevates the step with sudo when needed.
	requiresRoot?: bool | *false

	// when guards the step by platform, exactly like a package.
	when?: {
		os?:   [...("linux" | "darwin" | "windows" | string)]
		arch?: [...string]
	}

	// env holds extra environment variables for this step.
	env?: {[string]: string}

	// dir sets the working directory the step runs in (default: inherit).
	dir?: string

	// trigger is advisory metadata for the orchestration layer (chezmoi):
	//   once     - run one time and remember   (run_once_)
	//   onchange - run when content changes     (run_onchange_)
	//   always   - run on every apply
	// pulipil itself always executes the steps it is asked to run; `trigger`
	// tells the orchestrator WHEN to ask.
	trigger?: "once" | "onchange" | "always" | *"once"
}

// #Config is the top-level document shape a user file must satisfy.
#Config: {
	defaults?: {
		// providers is the preference order used for auto-detection.
		providers?: [...string]
	}

	// providers holds user-defined custom providers keyed by name.
	providers?: {[Name=string]: #Provider}

	// packages is the list of packages pulipil manages.
	packages?: [...#Package]

	// commands is the ordered list of steps pulipil runs after packages.
	commands?: [...#Command]
}
