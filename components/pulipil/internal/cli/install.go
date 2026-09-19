package cli

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/engine"
)

func newInstallCmd(opts *options) *cobra.Command {
	var dryRun bool
	var keepGoing bool

	cmd := &cobra.Command{
		Use:     "install",
		Aliases: []string{"apply"},
		Short:   "Install packages according to the config",
		Args:    cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			u := opts.newUI()
			eng, _, path, err := opts.loadEngine()
			if err != nil {
				return err
			}
			ctx := context.Background()

			u.Section("Install")
			u.KeyVal("config", path)

			actions, err := eng.Plan(ctx)
			if err != nil {
				return err
			}
			steps, err := eng.PlanCommands(ctx)
			if err != nil {
				return err
			}

			var todo int
			for _, a := range actions {
				if a.Op != engine.OpSkip {
					todo++
				}
			}
			for _, s := range steps {
				if s.Op != engine.OpSkip {
					todo++
				}
			}
			if todo == 0 {
				u.Info("")
				u.Success("Nothing to do — everything is already in the desired state.")
				return nil
			}

			u.Info("")
			u.Info("%d change(s) pending:", todo)
			for _, a := range actions {
				if a.Op == engine.OpSkip {
					continue
				}
				u.Info("  %s %s (%s)", a.Op.String(), a.Package.Name, a.Provider.Name())
			}
			for _, s := range steps {
				if s.Op == engine.OpSkip {
					continue
				}
				u.Info("  run %s", s.Command.Name)
			}
			u.Info("")

			if dryRun {
				u.Warn("dry-run: no changes made")
				return nil
			}

			if !opts.assumeYes && !confirm("Proceed?") {
				u.Info("Aborted.")
				return nil
			}
			u.Info("")

			hooks := engine.Hooks{
				OnStart: func(a engine.Action) { u.Step("%s %s via %s", a.Op.String(), a.Package.Name, a.Provider.Name()) },
				OnDone:  func(a engine.Action) { u.Success("%s %s", a.Package.Name, doneWord(a.Op)) },
				OnSkip:  func(a engine.Action) {},
				OnError: func(a engine.Action, err error) { u.Error("%s: %v", a.Package.Name, err) },

				OnCmdStart: func(s engine.CommandStep) { u.Step("run %s", s.Command.Name) },
				OnCmdDone:  func(s engine.CommandStep) { u.Success("%s ran", s.Command.Name) },
				OnCmdSkip:  func(s engine.CommandStep) {},
				OnCmdError: func(s engine.CommandStep, err error) { u.Error("%s: %v", s.Command.Name, err) },
			}

			if err := eng.Apply(ctx, actions, hooks, keepGoing); err != nil {
				return err
			}
			// Commands run after packages so `needs` referencing a package can
			// assume it has just been installed.
			if err := eng.ApplyCommands(ctx, steps, hooks, keepGoing); err != nil {
				return err
			}
			u.Info("")
			u.Success("Done.")
			return nil
		},
	}

	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "show planned changes but do not execute")
	cmd.Flags().BoolVar(&keepGoing, "keep-going", false, "continue past failures and report at the end")
	return cmd
}

func doneWord(op engine.Op) string {
	if op == engine.OpRemove {
		return "removed"
	}
	return "installed"
}

func confirm(prompt string) bool {
	fmt.Printf("%s [y/N] ", prompt)
	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	if err != nil {
		return false
	}
	line = strings.ToLower(strings.TrimSpace(line))
	return line == "y" || line == "yes"
}
