package cli

import (
	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/config"
)

func newValidateCmd(opts *options) *cobra.Command {
	return &cobra.Command{
		Use:   "validate",
		Short: "Validate a pulipil config against the schema",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			u := opts.newUI()
			path, err := opts.resolveConfigPath()
			if err != nil {
				return err
			}
			cfg, err := config.Load(path)
			if err != nil {
				u.Error("%s is invalid", path)
				return err
			}
			u.Success("%s is valid", path)
			u.KeyVal("packages", itoa(len(cfg.Packages)))
			u.KeyVal("commands", itoa(len(cfg.Commands)))
			u.KeyVal("providers", itoa(len(cfg.Providers))+" custom")
			if len(cfg.Defaults.Providers) > 0 {
				u.KeyVal("prefers", join(cfg.Defaults.Providers))
			}
			return nil
		},
	}
}

func newSchemaCmd(opts *options) *cobra.Command {
	return &cobra.Command{
		Use:   "schema",
		Short: "Print the embedded CUE configuration schema",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			cmd.Println(config.SchemaSource())
			return nil
		},
	}
}
