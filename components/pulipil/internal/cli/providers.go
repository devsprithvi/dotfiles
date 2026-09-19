package cli

import (
	"context"

	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/config"
	"github.com/devsprithvi/pulipil/internal/engine"
	"github.com/devsprithvi/pulipil/internal/provider"
	"github.com/devsprithvi/pulipil/internal/provider/builtin"
)

func newProvidersCmd(opts *options) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "providers",
		Short: "List package providers and their availability",
		Long: "Lists built-in providers plus any custom providers declared in the\n" +
			"config (when one is present), showing which are available on this system.",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			u := opts.newUI()
			ctx := context.Background()

			reg := provider.NewRegistry()
			builtin.Register(reg, provider.NewExecRunner())

			// Best-effort: fold in custom providers if a config is present.
			if path, err := opts.resolveConfigPath(); err == nil {
				if cfg, err := config.Load(path); err == nil {
					reg = engine.New(cfg, nil).Registry()
				}
			}

			u.Section("Providers")
			var rows [][]string
			for _, p := range reg.All() {
				avail := u.Styles().Error.Render("unavailable")
				if p.Available(ctx) {
					avail = u.Styles().Success.Render("available")
				}
				root := "no"
				if p.RequiresRoot() {
					root = "yes"
				}
				rows = append(rows, []string{p.Name(), avail, root})
			}
			u.Table([]string{"PROVIDER", "STATUS", "ROOT"}, rows)
			return nil
		},
	}
	return cmd
}
