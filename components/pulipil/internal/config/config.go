// Package config loads and validates pulipil's CUE configuration.
package config

// Config is the decoded, validated configuration document.
type Config struct {
	Defaults  Defaults                `json:"defaults"`
	Providers map[string]ProviderSpec `json:"providers"`
	Packages  []Package               `json:"packages"`
	Commands  []Command               `json:"commands"`
}

// Defaults holds global defaults.
type Defaults struct {
	// Providers is the auto-detection preference order.
	Providers []string `json:"providers"`
}

// ProviderSpec is a custom provider declared in configuration. It mirrors
// provider.Spec but lives here to keep the config package free of provider
// runtime concerns; the engine converts it into a provider.Spec.
type ProviderSpec struct {
	Binary       string            `json:"binary"`
	RequiresRoot bool              `json:"requiresRoot"`
	Detect       []string          `json:"detect"`
	Install      []string          `json:"install"`
	Remove       []string          `json:"remove"`
	Check        []string          `json:"check"`
	Update       []string          `json:"update"`
	Search       []string          `json:"search"`
	Env          map[string]string `json:"env"`
}

// Package is a single managed package entry.
type Package struct {
	Name     string     `json:"name"`
	Provider string     `json:"provider"`
	Version  string     `json:"version"`
	Args     []string   `json:"args"`
	State    string     `json:"state"`
	When     *When      `json:"when"`
	Secret   *SecretRef `json:"secret"`
}

// When guards a package by platform.
type When struct {
	OS   []string `json:"os"`
	Arch []string `json:"arch"`
}

// SecretRef references a credential (future feature).
type SecretRef struct {
	Ref string `json:"ref"`
	As  string `json:"as"`
}

// Command is a single declared execution step. The engine runs these after
// packages, in declared order, honouring platform guards and `Needs`.
type Command struct {
	// Name is a stable identifier and the orchestrator idempotency key.
	Name string `json:"name"`
	// Run is the argv to execute (at least one element).
	Run []string `json:"run"`
	// Shell, when true, runs Run joined through the platform shell.
	Shell bool `json:"shell"`
	// Needs names packages or earlier commands that must be satisfied first.
	Needs []string `json:"needs"`
	// RequiresRoot elevates the step with sudo when needed.
	RequiresRoot bool `json:"requiresRoot"`
	// When guards the step by platform.
	When *When `json:"when"`
	// Env holds extra environment variables for the step.
	Env map[string]string `json:"env"`
	// Dir is the working directory (empty means inherit the parent's).
	Dir string `json:"dir"`
	// Trigger is advisory orchestration metadata (once|onchange|always).
	Trigger string `json:"trigger"`
}

// State constants.
const (
	StatePresent = "present"
	StateAbsent  = "absent"
)

// Trigger constants describe when an orchestrator should invoke a command.
const (
	TriggerOnce     = "once"
	TriggerOnChange = "onchange"
	TriggerAlways   = "always"
)
