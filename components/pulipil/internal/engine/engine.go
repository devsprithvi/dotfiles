// Package engine wires configuration, providers and execution together. It
// computes an install plan from a validated config and applies it.
package engine

import (
	"context"
	"fmt"
	"runtime"
	"strings"

	"github.com/devsprithvi/pulipil/internal/config"
	"github.com/devsprithvi/pulipil/internal/provider"
	"github.com/devsprithvi/pulipil/internal/provider/builtin"
)

// Op is the action to take for a package.
type Op int

const (
	// OpInstall ensures the package is present.
	OpInstall Op = iota
	// OpRemove ensures the package is absent.
	OpRemove
	// OpSkip means no action (already in desired state, or guarded out).
	OpSkip
	// OpRun means execute a declared command step.
	OpRun
)

func (o Op) String() string {
	switch o {
	case OpInstall:
		return "install"
	case OpRemove:
		return "remove"
	case OpRun:
		return "run"
	default:
		return "skip"
	}
}

// Action is a single resolved unit of work in a plan.
type Action struct {
	Package  config.Package
	Provider provider.Provider
	Op       Op
	Reason   string
}

// CommandStep is a single resolved command in a plan. Op is either OpRun (the
// step will execute) or OpSkip (guarded out or a dependency was not met).
type CommandStep struct {
	Command config.Command
	Op      Op
	Reason  string
}

// Engine holds the provider registry and the loaded configuration.
type Engine struct {
	cfg    *config.Config
	reg    *provider.Registry
	runner provider.Runner
}

// New builds an Engine from config, registering built-in providers plus any
// custom providers declared in the config. If runner is nil, a real
// ExecRunner is used.
func New(cfg *config.Config, runner provider.Runner) *Engine {
	if runner == nil {
		runner = provider.NewExecRunner()
	}
	reg := provider.NewRegistry()
	builtin.Register(reg, runner)

	// Custom providers override built-ins of the same name.
	for name, spec := range cfg.Providers {
		reg.Register(provider.New(toProviderSpec(name, spec), runner))
	}

	return &Engine{cfg: cfg, reg: reg, runner: runner}
}

// Registry exposes the provider registry (used by `providers` and the LSP).
func (e *Engine) Registry() *provider.Registry { return e.reg }

// Plan resolves every package into a concrete Action.
func (e *Engine) Plan(ctx context.Context) ([]Action, error) {
	actions := make([]Action, 0, len(e.cfg.Packages))
	for _, pkg := range e.cfg.Packages {
		act, err := e.planPackage(ctx, pkg)
		if err != nil {
			return nil, err
		}
		actions = append(actions, act)
	}
	return actions, nil
}

func (e *Engine) planPackage(ctx context.Context, pkg config.Package) (Action, error) {
	if !platformMatches(pkg.When) {
		return Action{Package: pkg, Op: OpSkip, Reason: "guarded: platform does not match"}, nil
	}

	prov, err := e.reg.Resolve(ctx, pkg.Provider, e.cfg.Defaults.Providers)
	if err != nil {
		return Action{}, fmt.Errorf("package %q: %w", pkg.Name, err)
	}

	ppkg := provider.Package{Name: pkg.Name, Version: pkg.Version, Args: pkg.Args}
	installed, known := prov.IsInstalled(ctx, ppkg)

	switch pkg.State {
	case config.StateAbsent:
		if known && !installed {
			return Action{Package: pkg, Provider: prov, Op: OpSkip, Reason: "already absent"}, nil
		}
		return Action{Package: pkg, Provider: prov, Op: OpRemove}, nil
	default: // present
		if known && installed {
			return Action{Package: pkg, Provider: prov, Op: OpSkip, Reason: "already installed"}, nil
		}
		return Action{Package: pkg, Provider: prov, Op: OpInstall}, nil
	}
}

// Apply executes the given actions. It stops on the first error unless
// keepGoing is set, in which case it collects and returns them at the end.
func (e *Engine) Apply(ctx context.Context, actions []Action, hooks Hooks, keepGoing bool) error {
	var failures int
	for _, act := range actions {
		if act.Op == OpSkip {
			if hooks.OnSkip != nil {
				hooks.OnSkip(act)
			}
			continue
		}
		if hooks.OnStart != nil {
			hooks.OnStart(act)
		}

		ppkg := provider.Package{Name: act.Package.Name, Version: act.Package.Version, Args: act.Package.Args}
		var err error
		switch act.Op {
		case OpInstall:
			err = act.Provider.Install(ctx, ppkg)
		case OpRemove:
			err = act.Provider.Remove(ctx, ppkg)
		}

		if err != nil {
			failures++
			if hooks.OnError != nil {
				hooks.OnError(act, err)
			}
			if !keepGoing {
				return err
			}
			continue
		}
		if hooks.OnDone != nil {
			hooks.OnDone(act)
		}
	}
	if failures > 0 {
		return fmt.Errorf("%d package operation(s) failed", failures)
	}
	return nil
}

// Hooks lets callers (the CLI) render progress without the engine depending
// on any UI package. The OnCmd* callbacks mirror the package callbacks for
// command steps.
type Hooks struct {
	OnStart func(Action)
	OnDone  func(Action)
	OnSkip  func(Action)
	OnError func(Action, error)

	OnCmdStart func(CommandStep)
	OnCmdDone  func(CommandStep)
	OnCmdSkip  func(CommandStep)
	OnCmdError func(CommandStep, error)
}

// PlanCommands resolves every declared command into a CommandStep. It is
// deterministic: steps are evaluated in declared order, and a step's `needs`
// may only reference packages (present + platform-matched) or commands
// declared earlier that are not skipped. Anything else marks the step skipped
// with an explanatory reason, so `plan` shows exactly what will run and why.
func (e *Engine) PlanCommands(_ context.Context) ([]CommandStep, error) {
	// Names a `needs` entry can be satisfied by from the package set.
	pkgSatisfied := make(map[string]bool, len(e.cfg.Packages))
	for _, p := range e.cfg.Packages {
		if p.State != config.StateAbsent && platformMatches(p.When) {
			pkgSatisfied[p.Name] = true
		}
	}

	// Commands that have already been decided to run, filled as we go so that
	// dependency resolution is order-sensitive and cannot rely on later steps.
	ranOK := make(map[string]bool, len(e.cfg.Commands))

	steps := make([]CommandStep, 0, len(e.cfg.Commands))
	for _, c := range e.cfg.Commands {
		if !platformMatches(c.When) {
			steps = append(steps, CommandStep{Command: c, Op: OpSkip, Reason: "guarded: platform does not match"})
			continue
		}
		if reason := firstUnmetNeed(c.Needs, pkgSatisfied, ranOK); reason != "" {
			steps = append(steps, CommandStep{Command: c, Op: OpSkip, Reason: reason})
			continue
		}
		steps = append(steps, CommandStep{Command: c, Op: OpRun})
		ranOK[c.Name] = true
	}
	return steps, nil
}

// firstUnmetNeed returns a human-readable reason for the first dependency in
// needs that is not satisfied, or "" when all are satisfied.
func firstUnmetNeed(needs []string, pkgSatisfied, ranOK map[string]bool) string {
	for _, n := range needs {
		if pkgSatisfied[n] || ranOK[n] {
			continue
		}
		return "dependency not met: " + n
	}
	return ""
}

// ApplyCommands executes the runnable steps in order. Behaviour mirrors Apply:
// it stops on the first failure unless keepGoing is set, in which case it
// collects failures and reports a summary error at the end.
func (e *Engine) ApplyCommands(ctx context.Context, steps []CommandStep, hooks Hooks, keepGoing bool) error {
	var failures int
	for _, s := range steps {
		if s.Op == OpSkip {
			if hooks.OnCmdSkip != nil {
				hooks.OnCmdSkip(s)
			}
			continue
		}
		if hooks.OnCmdStart != nil {
			hooks.OnCmdStart(s)
		}

		argv := s.Command.Run
		if len(argv) == 0 {
			err := fmt.Errorf("command %q has no `run` argv", s.Command.Name)
			failures++
			if hooks.OnCmdError != nil {
				hooks.OnCmdError(s, err)
			}
			if !keepGoing {
				return err
			}
			continue
		}
		if s.Command.Shell {
			argv = shellWrap(argv)
		}

		res, err := e.runner.Run(ctx, argv, provider.RunOpts{
			Root:   s.Command.RequiresRoot,
			Env:    s.Command.Env,
			Dir:    s.Command.Dir,
			Stream: true,
		})
		if err == nil && !res.OK() {
			err = fmt.Errorf("command %q exited with code %d", s.Command.Name, res.ExitCode)
		}
		if err != nil {
			failures++
			if hooks.OnCmdError != nil {
				hooks.OnCmdError(s, err)
			}
			if !keepGoing {
				return err
			}
			continue
		}
		if hooks.OnCmdDone != nil {
			hooks.OnCmdDone(s)
		}
	}
	if failures > 0 {
		return fmt.Errorf("%d command step(s) failed", failures)
	}
	return nil
}

// shellWrap joins argv and wraps it for execution through the platform shell,
// so declared commands can use pipes, redirection and globbing when they opt
// in with `shell: true`.
func shellWrap(argv []string) []string {
	joined := strings.Join(argv, " ")
	if runtime.GOOS == "windows" {
		return []string{"cmd", "/C", joined}
	}
	return []string{"sh", "-c", joined}
}

// toProviderSpec converts a config.ProviderSpec into a provider.Spec.
func toProviderSpec(name string, s config.ProviderSpec) provider.Spec {
	return provider.Spec{
		Name:         name,
		Binary:       s.Binary,
		RequiresRoot: s.RequiresRoot,
		Detect:       s.Detect,
		Install:      s.Install,
		Remove:       s.Remove,
		Check:        s.Check,
		Update:       s.Update,
		Search:       s.Search,
		Env:          s.Env,
	}
}

// platformMatches evaluates a package's `when` guard against the current OS
// and architecture. A nil guard always matches.
func platformMatches(w *config.When) bool {
	if w == nil {
		return true
	}
	if len(w.OS) > 0 && !contains(w.OS, runtime.GOOS) {
		return false
	}
	if len(w.Arch) > 0 && !contains(w.Arch, runtime.GOARCH) {
		return false
	}
	return true
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}
