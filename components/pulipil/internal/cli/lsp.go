package cli

import (
	"context"
	"os"

	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/config"
	"github.com/devsprithvi/pulipil/internal/engine"
	"github.com/devsprithvi/pulipil/internal/lsp"
	"github.com/devsprithvi/pulipil/internal/provider"
	"github.com/devsprithvi/pulipil/internal/provider/builtin"
	"github.com/devsprithvi/pulipil/internal/version"
)

func newLSPCmd(opts *options) *cobra.Command {
	var info bool
	var stdio bool

	cmd := &cobra.Command{
		Use:   "lsp",
		Short: "Start the pulipil.cue language server",
		Long: "The pulipil language server provides real-time, provider-aware\n" +
			"completion for pulipil.cue files. Candidates are pulled live from\n" +
			"package registries (npm, crates.io, PyPI, Homebrew), each with its\n" +
			"own response shape, and fall back to installed package managers.\n\n" +
			"Editors launch it with `pulipil lsp --stdio`. Use --info to print\n" +
			"the capability roadmap without starting a server.",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			u := opts.newUI()

			reg := provider.NewRegistry()
			builtin.Register(reg, provider.NewExecRunner())
			if path, err := opts.resolveConfigPath(); err == nil {
				if cfg, err := config.Load(path); err == nil {
					reg = engine.New(cfg, nil).Registry()
				}
			}

			if info || !stdio {
				u.Section("pulipil language server — capabilities")
				for _, item := range lsp.Roadmap() {
					u.Info("  • %s", item)
				}
				u.Info("")
				u.Skip("start the server for an editor with: pulipil lsp --stdio")
				return nil
			}

			// Serve over stdio. All human-facing output must stay off stdout,
			// which is reserved for the JSON-RPC stream.
			server := lsp.New(reg, os.Stderr).WithVersion(version.String())
			return server.Serve(context.Background(), os.Stdin, os.Stdout)
		},
	}

	cmd.Flags().BoolVar(&info, "info", false, "print the language-server capabilities and exit")
	cmd.Flags().BoolVar(&stdio, "stdio", false, "serve the language server over stdio (JSON-RPC)")
	return cmd
}
