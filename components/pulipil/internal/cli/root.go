// Package cli implements the pulipil command-line interface.
package cli

import (
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/devsprithvi/pulipil/internal/config"
	"github.com/devsprithvi/pulipil/internal/engine"
	"github.com/devsprithvi/pulipil/internal/ui"
	"github.com/devsprithvi/pulipil/internal/version"
)

// options holds global flags shared across commands.
type options struct {
	configPath string
	noColor    bool
	verbose    bool
	assumeYes  bool
}

// Execute builds the root command and runs it.
func Execute() error {
	opts := &options{}

	root := &cobra.Command{
		Use:   "pulipil",
		Short: "A configuration-driven package installer engine",
		Long: "pulipil is a declarative installer engine.\n\n" +
			"You describe the packages you want in a CUE file and pulipil installs\n" +
			"them through pluggable package providers (dnf, apt, pacman, brew, ...).\n" +
			"Custom providers can be declared directly in configuration.",
		SilenceUsage:  true,
		SilenceErrors: true,
		Version:       version.String(),
	}

	pf := root.PersistentFlags()
	pf.StringVarP(&opts.configPath, "config", "c", "", "path to the pulipil CUE config (default: auto-discover)")
	pf.BoolVar(&opts.noColor, "no-color", os.Getenv("NO_COLOR") != "", "disable coloured output")
	pf.BoolVarP(&opts.verbose, "verbose", "v", false, "verbose output")
	pf.BoolVarP(&opts.assumeYes, "yes", "y", false, "assume yes for confirmation prompts")

	root.AddCommand(
		newVersionCmd(opts),
		newProvidersCmd(opts),
		newValidateCmd(opts),
		newSchemaCmd(opts),
		newPlanCmd(opts),
		newInstallCmd(opts),
		newRunCmd(opts),
		newSearchCmd(opts),
		newLSPCmd(opts),
	)

	return root.Execute()
}

// newUI returns a UI honouring the --no-color flag.
func (o *options) newUI() *ui.UI {
	return ui.New(os.Stdout, o.noColor)
}

// resolveConfigPath returns the config path to use, discovering a default in
// the working directory when none was given.
func (o *options) resolveConfigPath() (string, error) {
	if o.configPath != "" {
		return o.configPath, nil
	}
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	if p := config.Discover(wd); p != "" {
		return p, nil
	}
	return "", errNoConfig{dir: wd}
}

// loadEngine loads the config and constructs an engine with a real runner.
func (o *options) loadEngine() (*engine.Engine, *config.Config, string, error) {
	path, err := o.resolveConfigPath()
	if err != nil {
		return nil, nil, "", err
	}
	cfg, err := config.Load(path)
	if err != nil {
		return nil, nil, path, err
	}
	return engine.New(cfg, nil), cfg, path, nil
}

type errNoConfig struct{ dir string }

func (e errNoConfig) Error() string {
	return "no config file found in " + filepath.Clean(e.dir) +
		" (looked for pulipil.cue, .pulipil.cue, config.cue); pass --config"
}
