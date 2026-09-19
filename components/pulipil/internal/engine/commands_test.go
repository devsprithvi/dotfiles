package engine

import (
	"context"
	"sync"
	"testing"

	"github.com/devsprithvi/pulipil/internal/config"
	"github.com/devsprithvi/pulipil/internal/provider"
)

// recordingRunner records every argv it is asked to run and returns a fixed
// exit code, so command execution can be asserted without side effects.
type recordingRunner struct {
	mu   sync.Mutex
	runs [][]string
	exit int
}

func (r *recordingRunner) Run(_ context.Context, argv []string, _ provider.RunOpts) (provider.Result, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.runs = append(r.runs, argv)
	return provider.Result{ExitCode: r.exit}, nil
}

func cmdConfig(cmds ...config.Command) *config.Config {
	return &config.Config{
		Packages: []config.Package{{Name: "git", State: config.StatePresent}},
		Commands: cmds,
	}
}

func TestPlanCommandsRunsAndOrders(t *testing.T) {
	cfg := cmdConfig(
		config.Command{Name: "clone", Run: []string{"git", "clone", "x"}, Needs: []string{"git"}},
		config.Command{Name: "build", Run: []string{"make"}, Needs: []string{"clone"}},
	)
	eng := New(cfg, &recordingRunner{exit: 0})
	steps, err := eng.PlanCommands(context.Background())
	if err != nil {
		t.Fatalf("plan commands: %v", err)
	}
	if len(steps) != 2 {
		t.Fatalf("want 2 steps, got %d", len(steps))
	}
	for _, s := range steps {
		if s.Op != OpRun {
			t.Fatalf("step %q should run, got %v (%s)", s.Command.Name, s.Op, s.Reason)
		}
	}
}

func TestPlanCommandsSkipsOnUnmetDependency(t *testing.T) {
	cfg := cmdConfig(
		config.Command{Name: "build", Run: []string{"make"}, Needs: []string{"cmake"}},
	)
	eng := New(cfg, &recordingRunner{exit: 0})
	steps, _ := eng.PlanCommands(context.Background())
	if steps[0].Op != OpSkip {
		t.Fatalf("want skip for unmet dependency, got %v", steps[0].Op)
	}
}

func TestPlanCommandsSkipsForwardCommandReference(t *testing.T) {
	// `first` needs `second`, but `second` is declared later: dependency
	// resolution is order-sensitive, so `first` is skipped.
	cfg := cmdConfig(
		config.Command{Name: "first", Run: []string{"echo", "1"}, Needs: []string{"second"}},
		config.Command{Name: "second", Run: []string{"echo", "2"}},
	)
	eng := New(cfg, &recordingRunner{exit: 0})
	steps, _ := eng.PlanCommands(context.Background())
	if steps[0].Op != OpSkip {
		t.Fatalf("forward reference should skip, got %v", steps[0].Op)
	}
	if steps[1].Op != OpRun {
		t.Fatalf("second should run, got %v", steps[1].Op)
	}
}

func TestPlanCommandsGuardSkipsForeignOS(t *testing.T) {
	cfg := cmdConfig(
		config.Command{Name: "win-only", Run: []string{"echo"}, When: &config.When{OS: []string{"plan9"}}},
	)
	eng := New(cfg, &recordingRunner{exit: 0})
	steps, _ := eng.PlanCommands(context.Background())
	if steps[0].Op != OpSkip {
		t.Fatalf("guarded step should skip, got %v", steps[0].Op)
	}
}

func TestApplyCommandsExecutesRunnable(t *testing.T) {
	rr := &recordingRunner{exit: 0}
	cfg := cmdConfig(
		config.Command{Name: "hello", Run: []string{"echo", "hi"}, Needs: []string{"git"}},
	)
	eng := New(cfg, rr)
	steps, _ := eng.PlanCommands(context.Background())

	var started, done bool
	hooks := Hooks{
		OnCmdStart: func(CommandStep) { started = true },
		OnCmdDone:  func(CommandStep) { done = true },
	}
	if err := eng.ApplyCommands(context.Background(), steps, hooks, false); err != nil {
		t.Fatalf("apply commands: %v", err)
	}
	if !started || !done {
		t.Fatalf("hooks not called: started=%v done=%v", started, done)
	}
	if len(rr.runs) != 1 || rr.runs[0][0] != "echo" {
		t.Fatalf("unexpected runs: %v", rr.runs)
	}
}

func TestApplyCommandsShellWraps(t *testing.T) {
	rr := &recordingRunner{exit: 0}
	cfg := cmdConfig(
		config.Command{Name: "piped", Run: []string{"echo", "hi", "|", "cat"}, Shell: true},
	)
	eng := New(cfg, rr)
	steps, _ := eng.PlanCommands(context.Background())
	if err := eng.ApplyCommands(context.Background(), steps, Hooks{}, false); err != nil {
		t.Fatalf("apply: %v", err)
	}
	if len(rr.runs) != 1 {
		t.Fatalf("want 1 run, got %v", rr.runs)
	}
	first := rr.runs[0][0]
	if first != "sh" && first != "cmd" {
		t.Fatalf("shell step should be wrapped by a shell, got %v", rr.runs[0])
	}
}

func TestApplyCommandsFailsOnNonZeroExit(t *testing.T) {
	rr := &recordingRunner{exit: 3}
	cfg := cmdConfig(
		config.Command{Name: "boom", Run: []string{"false"}},
	)
	eng := New(cfg, rr)
	steps, _ := eng.PlanCommands(context.Background())
	if err := eng.ApplyCommands(context.Background(), steps, Hooks{}, false); err == nil {
		t.Fatal("expected error on non-zero exit")
	}
}
