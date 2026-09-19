package engine

import (
	"context"
	"testing"

	"github.com/devsprithvi/pulipil/internal/config"
	"github.com/devsprithvi/pulipil/internal/provider"
)

// scriptRunner returns a fixed result for every call.
type scriptRunner struct{ exit int }

func (s scriptRunner) Run(context.Context, []string, provider.RunOpts) (provider.Result, error) {
	return provider.Result{ExitCode: s.exit}, nil
}

func testConfig(state string) *config.Config {
	return &config.Config{
		Providers: map[string]config.ProviderSpec{
			"test": {
				Binary:  "test",
				Install: []string{"test", "add", "{{.Name}}"},
				Remove:  []string{"test", "del", "{{.Name}}"},
				Check:   []string{"test", "has", "{{.Name}}"},
			},
		},
		Packages: []config.Package{
			{Name: "foo", Provider: "test", State: state},
		},
	}
}

func TestPlanInstallsWhenAbsent(t *testing.T) {
	eng := New(testConfig(config.StatePresent), scriptRunner{exit: 1}) // check -> not installed
	actions, err := eng.Plan(context.Background())
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if len(actions) != 1 || actions[0].Op != OpInstall {
		t.Fatalf("want single install action, got %+v", actions)
	}
}

func TestPlanSkipsWhenPresent(t *testing.T) {
	eng := New(testConfig(config.StatePresent), scriptRunner{exit: 0}) // check -> installed
	actions, err := eng.Plan(context.Background())
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if actions[0].Op != OpSkip {
		t.Fatalf("want skip, got %v", actions[0].Op)
	}
}

func TestPlanRemovesWhenPresentAndAbsentDesired(t *testing.T) {
	eng := New(testConfig(config.StateAbsent), scriptRunner{exit: 0}) // check -> installed
	actions, err := eng.Plan(context.Background())
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if actions[0].Op != OpRemove {
		t.Fatalf("want remove, got %v", actions[0].Op)
	}
}

func TestPlanGuardSkipsForeignOS(t *testing.T) {
	cfg := testConfig(config.StatePresent)
	cfg.Packages[0].When = &config.When{OS: []string{"plan9"}}
	eng := New(cfg, scriptRunner{exit: 1})
	actions, err := eng.Plan(context.Background())
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	if actions[0].Op != OpSkip {
		t.Fatalf("want skip for guarded package, got %v", actions[0].Op)
	}
}

func TestApplyRunsInstall(t *testing.T) {
	eng := New(testConfig(config.StatePresent), scriptRunner{exit: 0})
	actions := []Action{{
		Package:  config.Package{Name: "foo"},
		Provider: mustProvider(eng, "test"),
		Op:       OpInstall,
	}}
	var started, done bool
	hooks := Hooks{
		OnStart: func(Action) { started = true },
		OnDone:  func(Action) { done = true },
	}
	if err := eng.Apply(context.Background(), actions, hooks, false); err != nil {
		t.Fatalf("apply: %v", err)
	}
	if !started || !done {
		t.Fatalf("hooks not called: started=%v done=%v", started, done)
	}
}

func mustProvider(e *Engine, name string) provider.Provider {
	p, ok := e.Registry().Get(name)
	if !ok {
		panic("provider not registered: " + name)
	}
	return p
}
