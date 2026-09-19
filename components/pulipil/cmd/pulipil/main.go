// Command pulipil is a configuration-driven package installer engine.
//
// You declare the packages you want in a CUE file; pulipil resolves an
// appropriate package provider (dnf, apt, pacman, brew, ...) and installs
// them. Custom providers can be declared directly in the configuration.
package main

import (
	"fmt"
	"os"

	"github.com/devsprithvi/pulipil/internal/cli"
)

func main() {
	if err := cli.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "pulipil: "+err.Error())
		os.Exit(1)
	}
}
