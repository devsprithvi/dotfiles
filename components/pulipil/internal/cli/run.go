package cli

import (
	"context"

	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/engine"
)

// newRunCmd exposes the command-step interpreter on its own. It exists so an
// orchestrator — chezmoi's run_once_/run_onchange_ scripts in the parent
// dotfiles repo — can trigger pulipil's declared commands without touching
// package state. chezmoi decides *when* (once, on change); pulipil decides
// *what*, deterministically, from the config.
func newRunCmd(opts *options) *cobra.Command {
	var dryRun bool
	var keepGoing bool

	cmd := &cobra.Command{
		Use:   "run [command-name ...]",
		Short: "Execute declared command steps (skips package management)",
		Long: "Runs the `commands` declared in the config, in order, honouring\n" +
			"platform guards and `needs` dependencies. With no arguments every\n" +
			"runnable step executes; with names, only those steps run.\n\n" +
			"Intended to be invoked from chezmoi run_once_/run_onchange_ scripts\n" +
			"so the orchestrator controls timing while pulipil controls behaviour.",
		Args: cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			u := opts.newUI()
			eng, _, path, err := opts.loadEngine()
			if err != nil {
				return err
			}
			ctx := context.Background()

			u.Section("Run")
			u.KeyVal("config", path)

			steps, err := eng.PlanCommands(ctx)
			if err != nil {
				return err
			}

			// Optional name filter: unselected runnable steps become skips.
			if len(args) > 0 {
				want := make(map[string]bool, len(args))
				for _, n := range args {
					want[n] = true
				}
				for i := range steps {
					if steps[i].Op == engine.OpRun && !want[steps[i].Command.Name] {
						steps[i].Op = engine.OpSkip
						steps[i].Reason = "not selected"
					}
				}
			}

			var todo int
			for _, s := range steps {
				if s.Op != engine.OpSkip {
					todo++
				}
			}
			if todo == 0 {
				u.Info("")
				u.Success("No command steps to run.")
				return nil
			}

			u.Info("")
			u.Info("%d step(s) pending:", todo)
			for _, s := range steps {
				if s.Op == engine.OpSkip {
					continue
				}
				u.Info("  run %s", s.Command.Name)
			}
			u.Info("")

			if dryRun {
				u.Warn("dry-run: no commands executed")
				return nil
			}

			hooks := engine.Hooks{
				OnCmdStart: func(s engine.CommandStep) { u.Step("run %s", s.Command.Name) },
				OnCmdDone:  func(s engine.CommandStep) { u.Success("%s ran", s.Command.Name) },
				OnCmdSkip:  func(s engine.CommandStep) {},
				OnCmdError: func(s engine.CommandStep, err error) { u.Error("%s: %v", s.Command.Name, err) },
			}

			if err := eng.ApplyCommands(ctx, steps, hooks, keepGoing); err != nil {
				return err
			}
			u.Info("")
			u.Success("Done.")
			return nil
		},
	}

	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "show steps that would run but do not execute")
	cmd.Flags().BoolVar(&keepGoing, "keep-going", false, "continue past failures and report at the end")
	return cmd
}
