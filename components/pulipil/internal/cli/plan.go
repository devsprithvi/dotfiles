package cli

import (
	"context"
	"strings"

	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/engine"
)

func newPlanCmd(opts *options) *cobra.Command {
	return &cobra.Command{
		Use:   "plan",
		Short: "Show what pulipil would do without making changes",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			u := opts.newUI()
			eng, cfg, path, err := opts.loadEngine()
			if err != nil {
				return err
			}
			ctx := context.Background()

			u.Section("Plan")
			u.KeyVal("config", path)
			u.KeyVal("packages", itoa(len(cfg.Packages)))
			u.KeyVal("commands", itoa(len(cfg.Commands)))
			u.Info("")

			actions, err := eng.Plan(ctx)
			if err != nil {
				return err
			}

			var install, remove, skip int
			var rows [][]string
			for _, a := range actions {
				var op, detail string
				switch a.Op {
				case engine.OpInstall:
					op = u.Styles().Accent.Render("install")
					install++
				case engine.OpRemove:
					op = u.Styles().Warn.Render("remove")
					remove++
				default:
					op = u.Styles().Subtle.Render("skip")
					detail = a.Reason
					skip++
				}
				provName := "-"
				if a.Provider != nil {
					provName = a.Provider.Name()
				}
				rows = append(rows, []string{op, a.Package.Name, provName, detail})
			}
			u.Table([]string{"ACTION", "PACKAGE", "PROVIDER", "NOTE"}, rows)
			u.Info("")
			u.Info("%s to install, %s to remove, %s unchanged",
				u.Styles().Accent.Render(itoa(install)),
				u.Styles().Warn.Render(itoa(remove)),
				u.Styles().Subtle.Render(itoa(skip)))

			steps, err := eng.PlanCommands(ctx)
			if err != nil {
				return err
			}
			if len(steps) > 0 {
				u.Info("")
				u.Section("Commands")
				var run, cskip int
				var crows [][]string
				for _, s := range steps {
					var op, detail string
					switch s.Op {
					case engine.OpRun:
						op = u.Styles().Accent.Render("run")
						detail = strings.Join(s.Command.Run, " ")
						run++
					default:
						op = u.Styles().Subtle.Render("skip")
						detail = s.Reason
						cskip++
					}
					crows = append(crows, []string{op, s.Command.Name, s.Command.Trigger, detail})
				}
				u.Table([]string{"ACTION", "COMMAND", "TRIGGER", "NOTE"}, crows)
				u.Info("")
				u.Info("%s to run, %s skipped",
					u.Styles().Accent.Render(itoa(run)),
					u.Styles().Subtle.Render(itoa(cskip)))
			}
			return nil
		},
	}
}
