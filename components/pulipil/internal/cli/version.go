package cli

import (
	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/version"
)

func newVersionCmd(opts *options) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version information",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			u := opts.newUI()
			u.Banner("pulipil", version.Version, "configuration-driven package installer")
			u.KeyVal("version", version.Version)
			u.KeyVal("commit", version.Commit)
			u.KeyVal("built", version.Date)
			return nil
		},
	}
}
