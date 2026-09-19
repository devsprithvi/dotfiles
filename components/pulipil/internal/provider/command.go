package provider

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"text/template"
)

// Spec is a declarative description of a command-driven provider. It is the
// bridge between configuration (built-in tables in Go or custom providers in
// CUE) and a live Provider implementation.
//
// Each command is an argv slice whose elements are Go text/template strings
// evaluated against templateData. An element that renders to an empty string
// is dropped, which makes conditional arguments easy to express, e.g.
// "{{if .Version}}={{.Version}}{{end}}".
type Spec struct {
	Name         string            `json:"name"`
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

// templateData is exposed to command templates.
type templateData struct {
	Name    string
	Version string
	Query   string
	Args    []string
}

// commandProvider implements Provider by rendering and running a Spec.
type commandProvider struct {
	spec   Spec
	runner Runner
}

// New builds a Provider from a Spec using the given Runner. If runner is nil
// the default ExecRunner is used.
func New(spec Spec, runner Runner) Provider {
	if runner == nil {
		runner = NewExecRunner()
	}
	if spec.Binary == "" && len(spec.Install) > 0 {
		spec.Binary = spec.Install[0]
	}
	return &commandProvider{spec: spec, runner: runner}
}

func (p *commandProvider) Name() string       { return p.spec.Name }
func (p *commandProvider) RequiresRoot() bool { return p.spec.RequiresRoot }

func (p *commandProvider) Available(ctx context.Context) bool {
	if len(p.spec.Detect) > 0 {
		argv, err := render(p.spec.Detect, templateData{})
		if err != nil || len(argv) == 0 {
			return false
		}
		res, err := p.runner.Run(ctx, argv, RunOpts{})
		return err == nil && res.OK()
	}
	if p.spec.Binary == "" {
		return false
	}
	_, err := exec.LookPath(p.spec.Binary)
	return err == nil
}

func (p *commandProvider) Install(ctx context.Context, pkg Package) error {
	return p.mutate(ctx, p.spec.Install, pkg, "install")
}

func (p *commandProvider) Remove(ctx context.Context, pkg Package) error {
	if len(p.spec.Remove) == 0 {
		return fmt.Errorf("%w: %q cannot remove packages", ErrUnsupported, p.spec.Name)
	}
	return p.mutate(ctx, p.spec.Remove, pkg, "remove")
}

func (p *commandProvider) mutate(ctx context.Context, cmd []string, pkg Package, verb string) error {
	if len(cmd) == 0 {
		return fmt.Errorf("%w: %q has no %s command", ErrUnsupported, p.spec.Name, verb)
	}
	argv, err := render(cmd, templateData{Name: pkg.Name, Version: pkg.Version, Args: pkg.Args})
	if err != nil {
		return err
	}
	argv = append(argv, pkg.Args...)
	res, err := p.runner.Run(ctx, argv, RunOpts{Root: p.spec.RequiresRoot, Env: p.spec.Env, Stream: true})
	if err != nil {
		return err
	}
	if !res.OK() {
		return fmt.Errorf("%s %q via %s failed (exit %d)", verb, pkg.Name, p.spec.Name, res.ExitCode)
	}
	return nil
}

func (p *commandProvider) IsInstalled(ctx context.Context, pkg Package) (bool, bool) {
	if len(p.spec.Check) == 0 {
		return false, false // unknown
	}
	argv, err := render(p.spec.Check, templateData{Name: pkg.Name, Version: pkg.Version})
	if err != nil || len(argv) == 0 {
		return false, false
	}
	res, err := p.runner.Run(ctx, argv, RunOpts{Env: p.spec.Env})
	if err != nil {
		return false, false
	}
	return res.OK(), true
}

func (p *commandProvider) Sync(ctx context.Context) error {
	if len(p.spec.Update) == 0 {
		return nil // nothing to do
	}
	argv, err := render(p.spec.Update, templateData{})
	if err != nil {
		return err
	}
	res, err := p.runner.Run(ctx, argv, RunOpts{Root: p.spec.RequiresRoot, Env: p.spec.Env, Stream: true})
	if err != nil {
		return err
	}
	if !res.OK() {
		return fmt.Errorf("sync via %s failed (exit %d)", p.spec.Name, res.ExitCode)
	}
	return nil
}

func (p *commandProvider) Search(ctx context.Context, query string) ([]Candidate, error) {
	if len(p.spec.Search) == 0 {
		return nil, nil
	}
	argv, err := render(p.spec.Search, templateData{Query: query})
	if err != nil {
		return nil, err
	}
	res, err := p.runner.Run(ctx, argv, RunOpts{Env: p.spec.Env})
	if err != nil {
		return nil, err
	}
	var out []Candidate
	for _, line := range strings.Split(res.Stdout, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		name := strings.Fields(line)[0]
		out = append(out, Candidate{Name: name, Description: line})
	}
	return out, nil
}

// render evaluates each argv element as a template and drops empties.
func render(cmd []string, data templateData) ([]string, error) {
	out := make([]string, 0, len(cmd))
	for _, part := range cmd {
		tmpl, err := template.New("arg").Option("missingkey=zero").Parse(part)
		if err != nil {
			return nil, fmt.Errorf("bad command template %q: %w", part, err)
		}
		var sb strings.Builder
		if err := tmpl.Execute(&sb, data); err != nil {
			return nil, fmt.Errorf("render %q: %w", part, err)
		}
		if s := strings.TrimSpace(sb.String()); s != "" {
			out = append(out, s)
		}
	}
	return out, nil
}
