package cli

import (
	"context"

	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/config"
	"github.com/devsprithvi/pulipil/internal/engine"
	"github.com/devsprithvi/pulipil/internal/lsp"
	"github.com/devsprithvi/pulipil/internal/provider"
	"github.com/devsprithvi/pulipil/internal/provider/builtin"
)

func newSearchCmd(opts *options) *cobra.Command {
	var providerName string

	cmd := &cobra.Command{
		Use:   "search <query>",
		Short: "Search a provider for packages (powers LSP completion)",
		Long: "Queries a provider's search command and lists candidates. This is the\n" +
			"same code path the language server uses for real-time completion.",
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			u := opts.newUI()
			ctx := context.Background()

			reg := provider.NewRegistry()
			builtin.Register(reg, provider.NewExecRunner())
			if path, err := opts.resolveConfigPath(); err == nil {
				if cfg, err := config.Load(path); err == nil {
					reg = engine.New(cfg, nil).Registry()
				}
			}

			name := providerName
			if name == "" {
				p, err := reg.Resolve(ctx, "", nil)
				if err != nil {
					return err
				}
				name = p.Name()
			}

			server := lsp.New(reg, cmd.OutOrStdout())
			candidates, err := server.Complete(ctx, name, args[0])
			if err != nil {
				return err
			}

			u.Section("Search: " + args[0] + " (" + name + ")")
			if len(candidates) == 0 {
				u.Skip("no results")
				return nil
			}
			var rows [][]string
			for _, c := range candidates {
				rows = append(rows, []string{c.Name, c.Description})
			}
			u.Table([]string{"NAME", "DETAIL"}, rows)
			return nil
		},
	}

	cmd.Flags().StringVarP(&providerName, "provider", "p", "", "provider to search (default: auto-detect)")
	return cmd
}
